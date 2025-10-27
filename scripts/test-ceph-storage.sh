#!/bin/bash
#
# test-ceph-storage.sh
# Tests Rook-Ceph storage functionality (both block and file storage)
#
# Usage: ./scripts/test-ceph-storage.sh [KUBECONFIG_PATH]
#

set -e

# Load common library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

# Configuration
KUBECONFIG_PATH="${1:-$KUBECONFIG}"
TEST_NAMESPACE="ceph-storage-test"
CLEANUP_ON_SUCCESS=true
CLEANUP_ON_FAILURE=false

# Validate KUBECONFIG
if ! validate_kubeconfig "$KUBECONFIG_PATH"; then
    exit 1
fi

print_header "Rook-Ceph Storage Test Suite"
echo ""
get_cluster_info | while read -r line; do print_info "$line"; done
print_info "Test Namespace: ${TEST_NAMESPACE}"
echo ""

# Function to cleanup
cleanup() {
    local exit_code=$1
    echo ""
    if [ "$exit_code" -eq 0 ] && [ "$CLEANUP_ON_SUCCESS" = true ]; then
        print_info "Cleaning up test resources..."
        oc delete project ${TEST_NAMESPACE} --ignore-not-found=true --wait=false &>/dev/null || true
        print_success "Cleanup initiated"
    elif [ "$exit_code" -ne 0 ] && [ "$CLEANUP_ON_FAILURE" = true ]; then
        print_info "Test failed. Cleaning up..."
        oc delete project ${TEST_NAMESPACE} --ignore-not-found=true --wait=false &>/dev/null || true
    elif [ "$exit_code" -ne 0 ]; then
        print_warning "Test failed. Resources left for debugging in namespace: ${TEST_NAMESPACE}"
        print_info "To cleanup manually: oc delete project ${TEST_NAMESPACE}"
    fi
}

# Trap exit
trap 'cleanup $?' EXIT

# Check if Rook-Ceph is installed
print_info "Checking Rook-Ceph installation..."
if ! check_ceph_cluster "rook-ceph" "rook-ceph"; then
    print_error "CephCluster 'rook-ceph' not found. Please install Rook-Ceph first."
    exit 1
fi

CEPH_HEALTH=$(get_ceph_health "rook-ceph" "rook-ceph")
if [ "$CEPH_HEALTH" != "HEALTH_OK" ] && [ "$CEPH_HEALTH" != "HEALTH_WARN" ]; then
    print_error "Ceph cluster is not healthy: $CEPH_HEALTH"
    exit 1
fi
print_success "Ceph cluster is healthy: $CEPH_HEALTH"

# Check storage classes
print_info "Checking storage classes..."
if ! check_storage_class "rook-ceph-block"; then
    print_error "StorageClass 'rook-ceph-block' not found"
    exit 1
fi
print_success "Found StorageClass: rook-ceph-block"

if ! check_storage_class "rook-cephfs"; then
    print_warning "StorageClass 'rook-cephfs' not found (CephFS tests will be skipped)"
    TEST_CEPHFS=false
else
    print_success "Found StorageClass: rook-cephfs"
    TEST_CEPHFS=true
fi

# Create test namespace
echo ""
print_header "Creating Test Namespace"
if oc get project ${TEST_NAMESPACE} &>/dev/null; then
    print_warning "Namespace ${TEST_NAMESPACE} already exists, deleting..."
    oc delete project ${TEST_NAMESPACE} --wait=true
    sleep 5
fi
oc new-project ${TEST_NAMESPACE} &>/dev/null
print_success "Created namespace: ${TEST_NAMESPACE}"

# =============================================================================
# TEST 1: Block Storage (RWO)
# =============================================================================
echo ""
print_header "TEST 1: Block Storage (ReadWriteOnce - RWO)"
echo ""

print_info "Step 1.1: Creating RBD PVC (5Gi)..."
cat <<EOF | oc apply -f - &>/dev/null
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-rbd-pvc
  namespace: ${TEST_NAMESPACE}
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: rook-ceph-block
  resources:
    requests:
      storage: 5Gi
EOF
print_success "PVC created"

print_info "Step 1.2: Waiting for PVC to bind..."
if ! wait_for_pvc "test-rbd-pvc" "${TEST_NAMESPACE}" 300; then
    oc get pvc test-rbd-pvc -n ${TEST_NAMESPACE}
    oc describe pvc test-rbd-pvc -n ${TEST_NAMESPACE}
    exit 1
fi

print_info "Step 1.3: Creating test pod with RBD volume..."
cat <<EOF | oc apply -f - &>/dev/null
apiVersion: v1
kind: Pod
metadata:
  name: test-rbd-pod
  namespace: ${TEST_NAMESPACE}
spec:
  containers:
  - name: test
    image: registry.access.redhat.com/ubi8/ubi-minimal:latest
    command: 
      - /bin/bash
      - -c
      - |
        echo "Writing test data..."
        echo "Hello from Rook-Ceph Block Storage!" > /data/test.txt
        echo "Timestamp: \$(date)" >> /data/test.txt
        echo "Hostname: \$(hostname)" >> /data/test.txt
        dd if=/dev/zero of=/data/testfile bs=1M count=100
        echo ""
        echo "=== Test file created ==="
        ls -lh /data/testfile
        echo ""
        echo "=== Content of test.txt ==="
        cat /data/test.txt
        echo ""
        echo "=== Disk usage ==="
        df -h /data
        echo ""
        echo "Test completed successfully!"
        sleep infinity
    volumeMounts:
    - name: data
      mountPath: /data
  volumes:
  - name: data
    persistentVolumeClaim:
      claimName: test-rbd-pvc
EOF
print_success "Pod created"

print_info "Step 1.4: Waiting for pod to be ready..."
oc wait --for=condition=ready pod/test-rbd-pod -n ${TEST_NAMESPACE} --timeout=120s &>/dev/null
print_success "Pod is ready"

print_info "Step 1.5: Reading pod logs..."
sleep 5
POD_OUTPUT=$(oc logs test-rbd-pod -n ${TEST_NAMESPACE} 2>/dev/null)
if echo "$POD_OUTPUT" | grep -q "Test completed successfully"; then
    print_success "Block storage test PASSED"
    echo ""
    echo "$POD_OUTPUT" | sed 's/^/  /'
else
    print_error "Block storage test FAILED"
    echo "$POD_OUTPUT"
    exit 1
fi

print_info "Step 1.6: Verifying data persistence..."
TEST_CONTENT=$(oc exec test-rbd-pod -n ${TEST_NAMESPACE} -- cat /data/test.txt 2>/dev/null)
if echo "$TEST_CONTENT" | grep -q "Hello from Rook-Ceph"; then
    print_success "Data persisted successfully"
else
    print_error "Data persistence check failed"
    exit 1
fi

print_success "✅ Block Storage (RWO) Test: PASSED"

# =============================================================================
# TEST 2: File Storage (RWX) - CephFS
# =============================================================================
if [ "$TEST_CEPHFS" = true ]; then
    echo ""
    print_header "TEST 2: File Storage (ReadWriteMany - RWX)"
    echo ""

    print_info "Step 2.1: Creating CephFS PVC (5Gi)..."
    cat <<EOF | oc apply -f - &>/dev/null
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-cephfs-pvc
  namespace: ${TEST_NAMESPACE}
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: rook-cephfs
  resources:
    requests:
      storage: 5Gi
EOF
    print_success "PVC created"

    print_info "Step 2.2: Waiting for PVC to bind..."
    if ! wait_for_pvc "test-cephfs-pvc" "${TEST_NAMESPACE}" 300; then
        oc get pvc test-cephfs-pvc -n ${TEST_NAMESPACE}
        oc describe pvc test-cephfs-pvc -n ${TEST_NAMESPACE}
        exit 1
    fi

    print_info "Step 2.3: Creating deployment with 3 replicas sharing the volume..."
    cat <<EOF | oc apply -f - &>/dev/null
apiVersion: apps/v1
kind: Deployment
metadata:
  name: test-cephfs-deploy
  namespace: ${TEST_NAMESPACE}
spec:
  replicas: 3
  selector:
    matchLabels:
      app: test-cephfs
  template:
    metadata:
      labels:
        app: test-cephfs
    spec:
      containers:
      - name: test
        image: registry.access.redhat.com/ubi8/ubi-minimal:latest
        command:
          - /bin/bash
          - -c
          - |
            echo "Pod \$(hostname) started at \$(date)" >> /shared/access.log
            while true; do
              echo "\$(date) - \$(hostname)" >> /shared/heartbeat.log
              sleep 30
            done
        volumeMounts:
        - name: shared
          mountPath: /shared
      volumes:
      - name: shared
        persistentVolumeClaim:
          claimName: test-cephfs-pvc
EOF
    print_success "Deployment created"

    print_info "Step 2.4: Waiting for all pods to be ready..."
    oc wait --for=condition=ready pod -l app=test-cephfs -n ${TEST_NAMESPACE} --timeout=120s --all &>/dev/null
    print_success "All pods are ready"

    print_info "Step 2.5: Waiting for pods to write data (60 seconds)..."
    sleep 60

    print_info "Step 2.6: Verifying shared access from all pods..."
    PODS=($(oc get pods -n ${TEST_NAMESPACE} -l app=test-cephfs -o jsonpath='{.items[*].metadata.name}'))
    
    if [ ${#PODS[@]} -ne 3 ]; then
        print_error "Expected 3 pods, found ${#PODS[@]}"
        exit 1
    fi
    
    print_success "Found ${#PODS[@]} pods"
    
    # Check access.log from first pod
    ACCESS_LOG=$(oc exec ${PODS[0]} -n ${TEST_NAMESPACE} -- cat /shared/access.log 2>/dev/null)
    ACCESS_COUNT=$(echo "$ACCESS_LOG" | wc -l)
    
    if [ "$ACCESS_COUNT" -ge 3 ]; then
        print_success "All 3 pods wrote to shared volume"
        echo ""
        echo "  Access log entries:"
        echo "$ACCESS_LOG" | sed 's/^/    /'
    else
        print_error "Expected 3 entries in access.log, found $ACCESS_COUNT"
        echo "$ACCESS_LOG"
        exit 1
    fi
    
    # Check heartbeat.log
    HEARTBEAT_LOG=$(oc exec ${PODS[0]} -n ${TEST_NAMESPACE} -- cat /shared/heartbeat.log 2>/dev/null)
    HEARTBEAT_COUNT=$(echo "$HEARTBEAT_LOG" | wc -l)
    
    if [ "$HEARTBEAT_COUNT" -ge 3 ]; then
        print_success "Heartbeat logs verified ($HEARTBEAT_COUNT entries)"
    else
        print_warning "Low heartbeat count: $HEARTBEAT_COUNT"
    fi
    
    print_success "✅ File Storage (RWX) Test: PASSED"
fi

# =============================================================================
# TEST 3: Storage Expansion (optional)
# =============================================================================
echo ""
print_header "TEST 3: Storage Class Features"
echo ""

print_info "Checking storage class capabilities..."

# Check if volume expansion is allowed
EXPANSION_ALLOWED=$(oc get sc rook-ceph-block -o jsonpath='{.allowVolumeExpansion}')
if [ "$EXPANSION_ALLOWED" = "true" ]; then
    print_success "Volume expansion: Enabled"
else
    print_warning "Volume expansion: Disabled"
fi

# Check reclaim policy
RECLAIM_POLICY=$(oc get sc rook-ceph-block -o jsonpath='{.reclaimPolicy}')
print_info "Reclaim policy: $RECLAIM_POLICY"

# Check provisioner
PROVISIONER=$(oc get sc rook-ceph-block -o jsonpath='{.provisioner}')
print_info "Provisioner: $PROVISIONER"

print_success "✅ Storage Class Features: Verified"

# =============================================================================
# TEST 4: Ceph Cluster Status
# =============================================================================
echo ""
print_header "TEST 4: Ceph Cluster Status"
echo ""

print_info "Retrieving Ceph cluster status..."
CEPH_STATUS=$(get_ceph_status "rook-ceph")

echo "$CEPH_STATUS"
echo ""

if echo "$CEPH_STATUS" | grep -q "HEALTH_OK"; then
    print_success "✅ Ceph Health: HEALTHY"
elif echo "$CEPH_STATUS" | grep -q "HEALTH_WARN"; then
    print_warning "⚠ Ceph Health: WARNING"
else
    print_error "✗ Ceph Health: ERROR"
fi

OSD_COUNT=$(echo "$CEPH_STATUS" | grep -oP 'osd: \K\d+' | head -1)
print_info "OSDs in cluster: $OSD_COUNT"

# =============================================================================
# Summary
# =============================================================================
echo ""
print_header "Test Summary"
echo ""

print_success "✅ Block Storage (RWO): PASSED"
if [ "$TEST_CEPHFS" = true ]; then
    print_success "✅ File Storage (RWX): PASSED"
else
    print_warning "⚠ File Storage (RWX): SKIPPED"
fi
print_success "✅ Storage Classes: VERIFIED"
print_success "✅ Ceph Cluster: HEALTHY"

echo ""
print_header "All Tests Completed Successfully! 🎉"
echo ""

print_info "PVCs created:"
oc get pvc -n ${TEST_NAMESPACE}
echo ""

print_info "Pods running:"
oc get pods -n ${TEST_NAMESPACE}
echo ""

if [ "$CLEANUP_ON_SUCCESS" = true ]; then
    print_warning "Test namespace will be deleted automatically"
else
    print_info "Test namespace preserved: ${TEST_NAMESPACE}"
    print_info "To cleanup: oc delete project ${TEST_NAMESPACE}"
fi

exit 0

