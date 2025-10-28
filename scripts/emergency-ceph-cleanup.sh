#!/bin/bash
set -e

# Emergency Ceph Cleanup Script
# Use this when Ceph monitors are stuck in probing state
# and cannot form quorum

# Load common library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

# Check arguments
if [ $# -ne 1 ]; then
    print_error "Cluster name not provided"
    echo ""
    echo "Usage: $0 <cluster-name>"
    echo ""
    echo "Example:"
    echo "  $0 dr-eun1b-1"
    exit 1
fi

CLUSTER_NAME=$1
PLAYGROUND_DIR="${HOME}/dr-playground/${CLUSTER_NAME}"
export KUBECONFIG="${PLAYGROUND_DIR}/ocp_install_files/auth/kubeconfig"

print_header "EMERGENCY CEPH CLEANUP FOR ${CLUSTER_NAME}"

validate_kubeconfig

NAMESPACE="rook-ceph"

# Check if cluster exists
if ! oc get namespace ${NAMESPACE} &>/dev/null; then
    print_warning "Namespace ${NAMESPACE} does not exist. Nothing to clean up."
    exit 0
fi

print_warning "This script will COMPLETELY REMOVE the Ceph cluster and all data!"
print_warning "Monitors are stuck in probing state and need full cleanup."
echo ""
print_info "The script will:"
echo "  1. Remove CephCluster, CephBlockPool, CephFilesystem"
echo "  2. Clean up all PVCs"
echo "  3. Clean up monitor and OSD data on nodes"
echo "  4. Reset to clean state"
echo ""
read -p "Continue? (yes/NO): " confirm
if [ "$confirm" != "yes" ]; then
    print_info "Aborted"
    exit 0
fi

echo ""
print_info "Step 1/8: Removing CephBlockPool and CephFilesystem..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Remove CephBlockPool using common function
safe_delete_resource cephblockpool replicapool ${NAMESPACE} 15

# Remove CephFilesystem using common function
safe_delete_resource cephfilesystem myfs ${NAMESPACE} 15

print_success "Dependent resources removed"

echo ""
print_info "Step 2/8: Setting CephCluster cleanupPolicy..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if oc get cephcluster rook-ceph -n ${NAMESPACE} &>/dev/null; then
    # Update cleanupPolicy to allow data deletion
    oc patch cephcluster rook-ceph -n ${NAMESPACE} --type merge -p '{"spec":{"cleanupPolicy":{"confirmation":"yes-really-destroy-data"}}}' 2>&1
    print_success "CleanupPolicy set to destroy data on deletion"
else
    print_info "CephCluster does not exist, skipping"
fi

echo ""
print_info "Step 3/8: Deleting CephCluster..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if oc get cephcluster rook-ceph -n ${NAMESPACE} &>/dev/null; then
    print_info "Deleting CephCluster 'rook-ceph'..."
    oc delete cephcluster rook-ceph -n ${NAMESPACE} --timeout=60s 2>&1 || true
    
    # Wait up to 2 minutes for cleanup jobs
    print_info "Waiting for cleanup to complete (max 2 minutes)..."
    for i in {1..12}; do
        if ! oc get cephcluster rook-ceph -n ${NAMESPACE} &>/dev/null; then
            break
        fi
        sleep 10
        echo -n "."
    done
    echo ""
    
    # Force remove if still exists
    if oc get cephcluster rook-ceph -n ${NAMESPACE} &>/dev/null; then
        print_warning "CephCluster still exists, forcing removal..."
        oc patch cephcluster rook-ceph -n ${NAMESPACE} --type json -p='[{"op": "remove", "path": "/metadata/finalizers"}]' 2>&1 || true
        sleep 5
    fi
    
    print_success "CephCluster deleted"
else
    print_info "CephCluster does not exist"
fi

echo ""
print_info "Step 4/8: Cleaning up PVCs..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Use common function to safely delete all PVCs
safe_delete_all_resources pvc ${NAMESPACE} 15

echo ""
print_info "Step 5/8: Cleaning up remaining pods..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Delete all remaining pods (except operator and CSI)
oc delete pod -n ${NAMESPACE} -l app!=rook-ceph-operator,app!=csi-rbdplugin,app!=csi-cephfsplugin --timeout=30s 2>&1 || true
print_success "Pods cleaned up"

echo ""
print_info "Step 6/8: Cleaning up node data..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Get worker nodes
NODES=($(oc get nodes -l node-role.kubernetes.io/worker -o jsonpath='{.items[*].metadata.name}'))

for node in "${NODES[@]}"; do
    print_info "Cleaning up node: $node"
    
    # Clean monitor data
    oc debug node/$node -- chroot /host /bin/bash -c "
        if [ -d /var/lib/rook ]; then
            echo '  Removing /var/lib/rook...'
            rm -rf /var/lib/rook/* 2>/dev/null || true
        fi
    " 2>&1 | grep -v "Starting pod" | grep -v "To use host" || true
    
    print_info "  ✓ Cleaned: $node"
done

print_success "Node data cleaned"

echo ""
print_info "Step 7/8: Verifying cleanup..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

REMAINING_PODS=$(oc get pods -n ${NAMESPACE} --no-headers 2>/dev/null | grep -v operator | grep -v csi | wc -l | tr -d ' ')
if [ "$REMAINING_PODS" -gt 0 ]; then
    print_warning "Still have ${REMAINING_PODS} pods remaining (will be cleaned up by operator)"
    oc get pods -n ${NAMESPACE} | grep -v operator | grep -v csi || true
else
    print_success "All non-operator pods removed"
fi

echo ""
print_info "Step 8/8: Checking LSO PVs..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

LSO_PV_COUNT=$(count_lso_pvs)
if [ "$LSO_PV_COUNT" -ge 3 ]; then
    print_success "Found ${LSO_PV_COUNT} LSO PVs available"
    oc get pv | grep lso-sc
else
    print_warning "Only ${LSO_PV_COUNT} LSO PVs found (need 3)"
    print_info "You may need to run:"
    echo "  ansible-playbook -i hosts -e @dr-eun1b-cluster1.yaml playbooks/dr-ceph.yml --tags lso1,ceph_disks"
fi

echo ""
print_success "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
print_success "CLEANUP COMPLETE!"
print_success "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
print_info "Next steps:"
echo ""
echo "1. Wait 1-2 minutes for operator to stabilize"
echo ""
echo "2. Reinstall Ceph cluster:"
echo "   ./scripts/install-rook-ceph.sh ${CLUSTER_NAME}"
echo ""
echo "3. Monitor the installation:"
echo "   watch -n 5 'oc get pods -n rook-ceph'"
echo ""

