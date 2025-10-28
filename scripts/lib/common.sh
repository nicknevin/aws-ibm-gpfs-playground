#!/bin/bash
#
# common.sh - Shared utilities for Rook-Ceph installation and management scripts
#
# Usage: source "$(dirname "$0")/lib/common.sh"
#

# =============================================================================
# Colors for output
# =============================================================================
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[1;33m'
export BLUE='\033[0;34m'
export CYAN='\033[0;36m'
export MAGENTA='\033[0;35m'
export NC='\033[0m' # No Color

# =============================================================================
# Print functions
# =============================================================================

print_header() {
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC} $1"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
}

print_section() {
    echo -e "${CYAN}▶${NC} ${MAGENTA}$1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_debug() {
    if [ "${DEBUG:-false}" = "true" ]; then
        echo -e "${MAGENTA}[DEBUG]${NC} $1"
    fi
}

# =============================================================================
# KUBECONFIG validation
# =============================================================================

validate_kubeconfig() {
    local kubeconfig_path="${1:-$KUBECONFIG}"
    
    if [ -z "$kubeconfig_path" ]; then
        print_error "KUBECONFIG not set. Please provide KUBECONFIG path"
        return 1
    fi
    
    if [ ! -f "$kubeconfig_path" ]; then
        print_error "KUBECONFIG file not found: $kubeconfig_path"
        return 1
    fi
    
    export KUBECONFIG="$kubeconfig_path"
    
    if ! oc whoami &>/dev/null && ! kubectl cluster-info &>/dev/null; then
        print_error "Cannot connect to cluster with KUBECONFIG: $kubeconfig_path"
        return 1
    fi
    
    return 0
}

get_cluster_info() {
    if command -v oc &>/dev/null; then
        echo "Server: $(oc whoami --show-server 2>/dev/null || echo 'Unknown')"
        echo "User: $(oc whoami 2>/dev/null || echo 'Unknown')"
    else
        echo "Server: $(kubectl cluster-info 2>/dev/null | head -1 || echo 'Unknown')"
        echo "User: $(kubectl config current-context 2>/dev/null || echo 'Unknown')"
    fi
}

# =============================================================================
# Kubernetes/OpenShift resource operations
# =============================================================================

# Wait for namespace to be created and ready
wait_for_namespace() {
    local namespace="$1"
    local timeout="${2:-60}"
    local interval=5
    local elapsed=0
    
    print_info "Waiting for namespace '$namespace' to be ready..."
    
    while [ $elapsed -lt $timeout ]; do
        if oc get namespace "$namespace" &>/dev/null; then
            print_success "Namespace '$namespace' is ready"
            return 0
        fi
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    
    print_error "Timeout waiting for namespace '$namespace'"
    return 1
}

# Wait for pod to be ready
wait_for_pod() {
    local pod_selector="$1"
    local namespace="$2"
    local timeout="${3:-300}"
    
    print_info "Waiting for pod '$pod_selector' in namespace '$namespace'..."
    
    if oc wait --for=condition=ready pod -l "$pod_selector" -n "$namespace" --timeout="${timeout}s" &>/dev/null; then
        print_success "Pod is ready"
        return 0
    else
        print_error "Pod failed to become ready within ${timeout}s"
        return 1
    fi
}

# Wait for deployment to be ready
wait_for_deployment() {
    local deployment="$1"
    local namespace="$2"
    local timeout="${3:-300}"
    
    print_info "Waiting for deployment '$deployment' in namespace '$namespace'..."
    
    if oc wait --for=condition=available deployment/"$deployment" -n "$namespace" --timeout="${timeout}s" &>/dev/null; then
        print_success "Deployment is ready"
        return 0
    else
        print_error "Deployment failed to become ready within ${timeout}s"
        return 1
    fi
}

# Wait for PVC to be bound
wait_for_pvc() {
    local pvc_name="$1"
    local namespace="$2"
    local timeout="${3:-300}"
    local interval=10
    local elapsed=0
    
    print_info "Waiting for PVC '$pvc_name' to bind..."
    
    while [ $elapsed -lt $timeout ]; do
        local status=$(oc get pvc "$pvc_name" -n "$namespace" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
        if [ "$status" = "Bound" ]; then
            print_success "PVC bound successfully"
            return 0
        fi
        echo -n "."
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    
    echo ""
    print_error "PVC failed to bind within ${timeout}s"
    return 1
}

# Apply CRD with retry
apply_crd() {
    local crd_url="$1"
    local max_retries="${2:-3}"
    local retry=0
    
    print_info "Applying CRD from: $crd_url"
    
    while [ $retry -lt $max_retries ]; do
        if oc apply -f "$crd_url" &>/dev/null; then
            print_success "CRD applied successfully"
            return 0
        fi
        retry=$((retry + 1))
        if [ $retry -lt $max_retries ]; then
            print_warning "Failed to apply CRD, retrying ($retry/$max_retries)..."
            sleep 5
        fi
    done
    
    print_error "Failed to apply CRD after $max_retries attempts"
    return 1
}

# Apply YAML manifest from string
apply_manifest() {
    local manifest="$1"
    local description="${2:-manifest}"
    
    print_info "Applying $description..."
    
    if echo "$manifest" | oc apply -f - &>/dev/null; then
        print_success "$description applied successfully"
        return 0
    else
        print_error "Failed to apply $description"
        return 1
    fi
}

# Delete resource with finalizer removal if stuck
delete_resource_with_finalizers() {
    local resource_type="$1"
    local resource_name="$2"
    local namespace="$3"
    local timeout="${4:-60}"
    
    print_info "Deleting $resource_type '$resource_name' in namespace '$namespace'..."
    
    # Attempt normal deletion
    oc delete "$resource_type" "$resource_name" -n "$namespace" --wait=false 2>/dev/null || true
    
    # Wait briefly
    sleep 10
    
    # Check if still exists
    if oc get "$resource_type" "$resource_name" -n "$namespace" &>/dev/null; then
        print_warning "Resource stuck, removing finalizers..."
        oc patch "$resource_type" "$resource_name" -n "$namespace" --type merge -p '{"metadata":{"finalizers":[]}}' 2>/dev/null || true
        
        # Wait for deletion
        local elapsed=0
        local interval=5
        while [ $elapsed -lt $timeout ]; do
            if ! oc get "$resource_type" "$resource_name" -n "$namespace" &>/dev/null; then
                print_success "$resource_type deleted"
                return 0
            fi
            sleep $interval
            elapsed=$((elapsed + interval))
        done
        
        print_warning "$resource_type may still exist"
        return 1
    else
        print_success "$resource_type deleted"
        return 0
    fi
}

# =============================================================================
# Ceph-specific operations
# =============================================================================

# Check if Ceph cluster exists
check_ceph_cluster() {
    local namespace="${1:-rook-ceph}"
    local cluster_name="${2:-rook-ceph}"
    
    if oc get cephcluster "$cluster_name" -n "$namespace" &>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Get Ceph cluster health
get_ceph_health() {
    local namespace="${1:-rook-ceph}"
    local cluster_name="${2:-rook-ceph}"
    
    oc get cephcluster "$cluster_name" -n "$namespace" -o jsonpath='{.status.ceph.health}' 2>/dev/null || echo "Unknown"
}

# Get Ceph cluster phase
get_ceph_phase() {
    local namespace="${1:-rook-ceph}"
    local cluster_name="${2:-rook-ceph}"
    
    oc get cephcluster "$cluster_name" -n "$namespace" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown"
}

# Wait for Ceph cluster to be ready
wait_for_ceph_cluster() {
    local namespace="${1:-rook-ceph}"
    local cluster_name="${2:-rook-ceph}"
    local timeout="${3:-600}"
    local interval=10
    local elapsed=0
    
    print_info "Waiting for CephCluster '$cluster_name' to be ready..."
    
    while [ $elapsed -lt $timeout ]; do
        local phase=$(get_ceph_phase "$namespace" "$cluster_name")
        local health=$(get_ceph_health "$namespace" "$cluster_name")
        
        print_debug "Phase: $phase, Health: $health"
        
        if [ "$phase" = "Ready" ]; then
            if [ "$health" = "HEALTH_OK" ] || [ "$health" = "HEALTH_WARN" ]; then
                print_success "CephCluster is ready (Health: $health)"
                return 0
            fi
        fi
        
        echo -n "."
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    
    echo ""
    print_error "CephCluster failed to become ready within ${timeout}s"
    print_info "Phase: $(get_ceph_phase "$namespace" "$cluster_name")"
    print_info "Health: $(get_ceph_health "$namespace" "$cluster_name")"
    return 1
}

# Count OSDs
count_osds() {
    local namespace="${1:-rook-ceph}"
    
    oc get pods -n "$namespace" --no-headers 2>/dev/null | grep -c "rook-ceph-osd-[0-9]" || echo "0"
}

# Wait for OSDs to be created
wait_for_osds() {
    local expected_count="$1"
    local namespace="${2:-rook-ceph}"
    local timeout="${3:-600}"
    local interval=10
    local elapsed=0
    
    print_info "Waiting for at least $expected_count OSDs to be created..."
    
    while [ $elapsed -lt $timeout ]; do
        local osd_count=$(count_osds "$namespace")
        
        if [ "$osd_count" -ge "$expected_count" ]; then
            print_success "Found $osd_count OSDs"
            return 0
        fi
        
        echo -n "."
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    
    echo ""
    print_error "Expected $expected_count OSDs, only found $(count_osds "$namespace") within ${timeout}s"
    return 1
}

# Execute command in Ceph toolbox
ceph_exec() {
    local namespace="${1:-rook-ceph}"
    shift
    local command="$*"
    
    oc rsh -n "$namespace" deployment/rook-ceph-tools $command 2>/dev/null
}

# Get Ceph status
get_ceph_status() {
    local namespace="${1:-rook-ceph}"
    
    ceph_exec "$namespace" ceph -s
}

# Check if storage class exists
check_storage_class() {
    local sc_name="$1"
    
    if oc get storageclass "$sc_name" &>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Check if CephBlockPool exists
check_ceph_blockpool() {
    local pool_name="$1"
    local namespace="${2:-rook-ceph}"
    
    if oc get cephblockpool "$pool_name" -n "$namespace" &>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Check if CephFilesystem exists
check_ceph_filesystem() {
    local fs_name="$1"
    local namespace="${2:-rook-ceph}"
    
    if oc get cephfilesystem "$fs_name" -n "$namespace" &>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Get CephBlockPool status
get_ceph_blockpool_status() {
    local pool_name="$1"
    local namespace="${2:-rook-ceph}"
    
    oc get cephblockpool "$pool_name" -n "$namespace" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown"
}

# Get CephFilesystem status
get_ceph_filesystem_status() {
    local fs_name="$1"
    local namespace="${2:-rook-ceph}"
    
    oc get cephfilesystem "$fs_name" -n "$namespace" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown"
}

# Wait for CephBlockPool to be ready
wait_for_ceph_blockpool() {
    local pool_name="$1"
    local namespace="${2:-rook-ceph}"
    local timeout="${3:-300}"
    local interval=10
    local elapsed=0
    
    print_info "Waiting for CephBlockPool '$pool_name' to be ready..."
    
    while [ $elapsed -lt $timeout ]; do
        local status=$(get_ceph_blockpool_status "$pool_name" "$namespace")
        
        if [ "$status" = "Ready" ]; then
            print_success "CephBlockPool is ready"
            return 0
        fi
        
        echo -n "."
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    
    echo ""
    print_error "CephBlockPool failed to become ready within ${timeout}s (status: $(get_ceph_blockpool_status "$pool_name" "$namespace"))"
    return 1
}

# Wait for CephFilesystem to be ready
wait_for_ceph_filesystem() {
    local fs_name="$1"
    local namespace="${2:-rook-ceph}"
    local timeout="${3:-300}"
    local interval=10
    local elapsed=0
    
    print_info "Waiting for CephFilesystem '$fs_name' to be ready..."
    
    while [ $elapsed -lt $timeout ]; do
        local status=$(get_ceph_filesystem_status "$fs_name" "$namespace")
        
        if [ "$status" = "Ready" ]; then
            print_success "CephFilesystem is ready"
            return 0
        fi
        
        echo -n "."
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    
    echo ""
    print_error "CephFilesystem failed to become ready within ${timeout}s (status: $(get_ceph_filesystem_status "$fs_name" "$namespace"))"
    return 1
}

# =============================================================================
# LSO (Local Storage Operator) operations
# =============================================================================

# Count LSO PVs safely
count_lso_pvs() {
    local pv_count=$(oc get pv --no-headers 2>&1 | grep "lso-sc" | wc -l | tr -d ' ')
    # Ensure PV count is a valid integer
    if ! [[ "$pv_count" =~ ^[0-9]+$ ]]; then
        pv_count=0
    fi
    echo "$pv_count"
}

# Check if LSO is installed
check_lso_installed() {
    if oc get localvolume -n openshift-local-storage local-block &>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Label nodes for LSO
label_nodes_for_lso() {
    print_info "Labeling worker nodes for LSO..."
    for node in $(oc get nodes -l node-role.kubernetes.io/worker -o name); do
        oc label $node cluster.ocs.openshift.io/openshift-storage="" --overwrite 2>&1 | grep -v "not labeled" || true
        print_info "  Labeled: $(basename $node)"
    done
    print_success "All worker nodes labeled for LSO"
}

# Check and ensure nodes are labeled for LSO
ensure_lso_node_labels() {
    local labeled_nodes=$(oc get nodes -l cluster.ocs.openshift.io/openshift-storage -o name 2>/dev/null | wc -l | tr -d ' ')
    local worker_nodes=$(oc get nodes -l node-role.kubernetes.io/worker -o name 2>/dev/null | wc -l | tr -d ' ')
    
    if [ "$labeled_nodes" -lt "$worker_nodes" ]; then
        print_warning "Only ${labeled_nodes}/${worker_nodes} nodes have LSO label. Labeling all worker nodes..."
        label_nodes_for_lso
    else
        print_success "All ${labeled_nodes} worker nodes already labeled for LSO"
    fi
}

# Show LSO debug information
show_lso_debug() {
    print_info "Debug: Checking all PVs..."
    oc get pv -o wide 2>&1
    print_info ""
    print_info "Debug: Checking LocalVolume configuration..."
    oc get localvolume -n openshift-local-storage local-block -o yaml 2>&1
    print_info ""
    print_info "Debug: Checking LSO operator pods..."
    oc get pods -n openshift-local-storage 2>&1
    print_info ""
    print_info "Debug: Checking LSO operator logs (last 20 lines)..."
    oc logs -n openshift-local-storage -l app=local-storage-operator --tail=20 2>&1 || echo "No operator logs found"
}

# Wait for LSO PVs to be created
wait_for_lso_pvs() {
    local required_count="${1:-3}"
    local timeout="${2:-60}"
    local interval=10
    local elapsed=0
    
    print_info "Waiting for LSO PVs to be created..."
    
    while [ $elapsed -lt $timeout ]; do
        local pv_count=$(count_lso_pvs)
        
        if [ "$pv_count" -ge "$required_count" ]; then
            print_success "Found $pv_count LSO PVs"
            return 0
        fi
        
        echo -n "."
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    
    echo ""
    print_error "Timeout waiting for LSO PVs. Found $(count_lso_pvs)/${required_count}"
    return 1
}

# =============================================================================
# URL validation
# =============================================================================

validate_url() {
    local url="$1"
    
    if curl --output /dev/null --silent --head --fail "$url" 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

# =============================================================================
# Cleanup operations
# =============================================================================

# Clean up Ceph dependent resources
cleanup_ceph_dependents() {
    local namespace="${1:-rook-ceph}"
    
    print_info "Cleaning up Ceph dependent resources..."
    
    # Delete BlockPools
    print_info "  Deleting CephBlockPools..."
    for pool in $(oc get cephblockpool -n "$namespace" -o name 2>/dev/null); do
        oc delete "$pool" -n "$namespace" --wait=false 2>/dev/null || true
    done
    
    # Delete FileSystems
    print_info "  Deleting CephFilesystems..."
    for fs in $(oc get cephfilesystem -n "$namespace" -o name 2>/dev/null); do
        oc delete "$fs" -n "$namespace" --wait=false 2>/dev/null || true
    done
    
    # Delete ObjectStores
    print_info "  Deleting CephObjectStores..."
    for store in $(oc get cephobjectstore -n "$namespace" -o name 2>/dev/null); do
        oc delete "$store" -n "$namespace" --wait=false 2>/dev/null || true
    done
    
    sleep 10
    
    # Remove finalizers
    print_info "  Removing finalizers from stuck resources..."
    for resource in cephblockpool cephfilesystem cephobjectstore; do
        for item in $(oc get "$resource" -n "$namespace" -o name 2>/dev/null); do
            oc patch "$item" -n "$namespace" --type merge -p '{"metadata":{"finalizers":[]}}' 2>/dev/null || true
        done
    done
    
    print_success "Dependent resources cleaned up"
}

# =============================================================================
# Version information
# =============================================================================

get_library_version() {
    echo "1.0.0"
}

print_library_info() {
    print_debug "Common Library Version: $(get_library_version)"
}

# =============================================================================
# Resource Cleanup Operations
# =============================================================================

# Safe delete Kubernetes resource with finalizer handling
# Usage: safe_delete_resource <resource-type> <resource-name> <namespace> [timeout]
# Example: safe_delete_resource cephblockpool replicapool rook-ceph 30
safe_delete_resource() {
    local resource_type="$1"
    local resource_name="$2"
    local namespace="$3"
    local timeout="${4:-30}"  # Default 30s timeout
    
    if [ -z "$resource_type" ] || [ -z "$resource_name" ] || [ -z "$namespace" ]; then
        print_error "safe_delete_resource: Missing required parameters"
        echo "Usage: safe_delete_resource <resource-type> <resource-name> <namespace> [timeout]"
        return 1
    fi
    
    # Check if resource exists
    if ! oc get "$resource_type" "$resource_name" -n "$namespace" &>/dev/null; then
        print_debug "Resource $resource_type/$resource_name does not exist in namespace $namespace"
        return 0
    fi
    
    print_info "Checking $resource_type '$resource_name' for finalizers..."
    
    # Get finalizers
    local finalizers
    finalizers=$(oc get "$resource_type" "$resource_name" -n "$namespace" -o jsonpath='{.metadata.finalizers}' 2>/dev/null || echo "[]")
    
    # Check if finalizers exist and are not empty
    if [ "$finalizers" != "[]" ] && [ "$finalizers" != "" ] && [ "$finalizers" != "null" ]; then
        print_warning "Found finalizers: $finalizers"
        print_info "Removing finalizers before deletion..."
        
        if oc patch "$resource_type" "$resource_name" -n "$namespace" --type json \
            -p='[{"op": "remove", "path": "/metadata/finalizers"}]' 2>&1; then
            print_success "Finalizers removed"
            sleep 2
        else
            print_warning "Failed to remove finalizers, attempting deletion anyway..."
        fi
    else
        print_debug "No finalizers found"
    fi
    
    # Delete resource
    print_info "Deleting $resource_type '$resource_name'..."
    if oc delete "$resource_type" "$resource_name" -n "$namespace" --timeout="${timeout}s" 2>&1; then
        print_success "Resource deleted successfully"
        return 0
    else
        print_warning "Deletion timed out or failed, attempting force delete..."
    fi
    
    # Force delete if normal delete failed
    if oc get "$resource_type" "$resource_name" -n "$namespace" &>/dev/null; then
        print_warning "Resource still exists, forcing removal..."
        
        # Remove finalizers again (in case they were re-added)
        oc patch "$resource_type" "$resource_name" -n "$namespace" --type json \
            -p='[{"op": "remove", "path": "/metadata/finalizers"}]' 2>&1 || true
        
        # Force delete
        oc delete "$resource_type" "$resource_name" -n "$namespace" --force --grace-period=0 2>&1 || true
        sleep 2
        
        # Final check
        if oc get "$resource_type" "$resource_name" -n "$namespace" &>/dev/null; then
            print_error "Failed to delete $resource_type/$resource_name"
            return 1
        else
            print_success "Resource forcefully removed"
            return 0
        fi
    fi
    
    return 0
}

# Safe delete all resources of a type with finalizer handling
# Usage: safe_delete_all_resources <resource-type> <namespace> [timeout]
# Example: safe_delete_all_resources pvc rook-ceph 30
safe_delete_all_resources() {
    local resource_type="$1"
    local namespace="$2"
    local timeout="${3:-30}"  # Default 30s timeout
    
    if [ -z "$resource_type" ] || [ -z "$namespace" ]; then
        print_error "safe_delete_all_resources: Missing required parameters"
        echo "Usage: safe_delete_all_resources <resource-type> <namespace> [timeout]"
        return 1
    fi
    
    # Get list of resources
    local resources
    resources=$(oc get "$resource_type" -n "$namespace" -o name 2>/dev/null)
    
    if [ -z "$resources" ]; then
        print_info "No $resource_type resources found in namespace $namespace"
        return 0
    fi
    
    local count
    count=$(echo "$resources" | wc -l | tr -d ' ')
    print_info "Found $count $resource_type resource(s) to delete"
    
    # Remove finalizers from all resources first
    print_info "Removing finalizers from all $resource_type resources..."
    for resource in $resources; do
        oc patch "$resource" -n "$namespace" --type json \
            -p='[{"op": "remove", "path": "/metadata/finalizers"}]' 2>&1 || true
    done
    sleep 2
    
    # Delete all resources
    print_info "Deleting all $resource_type resources..."
    if oc delete "$resource_type" --all -n "$namespace" --timeout="${timeout}s" 2>&1; then
        print_success "All resources deleted"
        return 0
    else
        print_warning "Some resources may not have been deleted, checking..."
    fi
    
    # Force delete any remaining resources
    resources=$(oc get "$resource_type" -n "$namespace" -o name 2>/dev/null)
    if [ -n "$resources" ]; then
        print_warning "Force deleting remaining resources..."
        for resource in $resources; do
            oc delete "$resource" -n "$namespace" --force --grace-period=0 2>&1 || true
        done
    fi
    
    print_success "Cleanup complete for $resource_type"
    return 0
}

# =============================================================================
# Initialization
# =============================================================================

# Print library info if DEBUG is enabled
print_library_info

