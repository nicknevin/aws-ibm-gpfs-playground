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
# Initialization
# =============================================================================

# Print library info if DEBUG is enabled
print_library_info

