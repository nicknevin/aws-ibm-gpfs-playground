#!/bin/bash
#
# Fix Rook-Ceph Storage Configuration
# 
# This script fixes a Rook-Ceph installation that was configured with
# raw device paths instead of using PVCs from Local Storage Operator
#
# Usage:
#   ./scripts/fix-rook-ceph-storage.sh <cluster-name>
#
# Example:
#   ./scripts/fix-rook-ceph-storage.sh dr-eun1b-1
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if cluster name is provided
if [ -z "$1" ]; then
    print_error "Cluster name not provided"
    echo "Usage: $0 <cluster-name>"
    echo "Example: $0 dr-eun1b-1"
    exit 1
fi

CLUSTER_NAME=$1
PLAYGROUND_DIR="${HOME}/dr-playground/${CLUSTER_NAME}"
KUBECONFIG="${PLAYGROUND_DIR}/ocp_install_files/auth/kubeconfig"
NAMESPACE="rook-ceph"

print_info "Fixing Rook-Ceph storage configuration for cluster: ${CLUSTER_NAME}"
echo ""

# Check if KUBECONFIG exists
if [ ! -f "${KUBECONFIG}" ]; then
    print_error "KUBECONFIG not found at ${KUBECONFIG}"
    exit 1
fi

export KUBECONFIG

# Check if cluster exists
if ! oc get cephcluster rook-ceph -n ${NAMESPACE} &>/dev/null; then
    print_error "CephCluster 'rook-ceph' not found in namespace ${NAMESPACE}"
    exit 1
fi

# Check if LSO PVs exist
print_info "Checking for LSO PVs..."
LSO_PV_COUNT=$(oc get pv --no-headers 2>/dev/null | grep -c "lso-sc" || echo "0")

if [ "$LSO_PV_COUNT" -lt 3 ]; then
    print_error "Found only ${LSO_PV_COUNT} LSO PVs. Need at least 3."
    print_info "Please run the LSO setup first:"
    echo "  ansible-playbook -i hosts -e @dr-eun1b-cluster1.yaml playbooks/dr-ceph.yml --tags lso1,ceph_disks"
    exit 1
fi

print_success "Found ${LSO_PV_COUNT} LSO PVs"

# Get current cluster configuration
print_info "Backing up current CephCluster configuration..."
oc get cephcluster rook-ceph -n ${NAMESPACE} -o yaml > "${PLAYGROUND_DIR}/rook-ceph-cluster-backup-$(date +%Y%m%d-%H%M%S).yaml"
print_success "Backup saved to ${PLAYGROUND_DIR}/rook-ceph-cluster-backup-*.yaml"

echo ""
print_warning "This will:"
print_warning "  1. Delete the current CephCluster (keeps monitors and data)"
print_warning "  2. Recreate it with PVC-based storage configuration"
print_warning "  3. OSDs will be recreated using LSO PVs"
echo ""
read -p "Do you want to continue? (yes/no): " -r
if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    print_info "Operation cancelled"
    exit 0
fi

echo ""
print_info "Step 1: Deleting dependent resources first..."
print_info "  Deleting CephBlockPools..."
oc delete cephblockpool --all -n ${NAMESPACE} --wait=false 2>/dev/null || true
print_info "  Deleting CephFilesystems..."
oc delete cephfilesystem --all -n ${NAMESPACE} --wait=false 2>/dev/null || true
print_info "  Deleting CephObjectStores..."
oc delete cephobjectstore --all -n ${NAMESPACE} --wait=false 2>/dev/null || true

print_info "Waiting 10 seconds for deletions to start..."
sleep 10

print_info "Removing finalizers from stuck resources..."
for resource in cephblockpool cephfilesystem cephobjectstore; do
    for item in $(oc get ${resource} -n ${NAMESPACE} -o name 2>/dev/null); do
        oc patch ${item} -n ${NAMESPACE} --type merge -p '{"metadata":{"finalizers":[]}}' 2>/dev/null || true
    done
done

print_info "Step 2: Deleting CephCluster CR..."
oc delete cephcluster rook-ceph -n ${NAMESPACE} --wait=false

print_info "Waiting for cluster deletion to start (20 seconds)..."
sleep 20

print_info "Removing CephCluster finalizers if stuck..."
oc patch cephcluster rook-ceph -n ${NAMESPACE} --type merge -p '{"metadata":{"finalizers":[]}}' 2>/dev/null || print_info "  CephCluster already deleted"

print_info "Waiting for full cleanup (30 seconds)..."
sleep 30

echo ""
print_info "Step 3: Creating new CephCluster with PVC-based storage..."
cat <<'EOF' | oc apply -f -
apiVersion: ceph.rook.io/v1
kind: CephCluster
metadata:
  name: rook-ceph
  namespace: rook-ceph
spec:
  dataDirHostPath: /var/lib/rook
  cephVersion:
    image: quay.io/ceph/ceph:v18.2.4
    allowUnsupported: false
  mon:
    count: 3
    allowMultiplePerNode: false
  mgr:
    count: 2
    allowMultiplePerNode: false
    modules:
      - name: pg_autoscaler
        enabled: true
      - name: rook
        enabled: true
  dashboard:
    enabled: true
    ssl: true
  monitoring:
    enabled: false
    createPrometheusRules: false
  network:
    connections:
      encryption:
        enabled: false
      compression:
        enabled: false
  crashCollector:
    disable: false
  logCollector:
    enabled: true
    periodicity: daily
    maxLogSize: 500M
  cleanupPolicy:
    confirmation: ""
    sanitizeDisks:
      method: quick
      dataSource: zero
      iteration: 1
  resources:
    mon:
      requests:
        cpu: "1000m"
        memory: "2Gi"
      limits:
        memory: "2Gi"
    osd:
      requests:
        cpu: "2000m"
        memory: "5Gi"
      limits:
        memory: "5Gi"
    mgr:
      requests:
        cpu: "1000m"
        memory: "3Gi"
      limits:
        memory: "3Gi"
    mds:
      requests:
        cpu: "3000m"
        memory: "8Gi"
      limits:
        memory: "8Gi"
  storage:
    useAllNodes: true
    useAllDevices: false
    storageClassDeviceSets:
      - name: set1
        count: 3
        portable: false
        volumeClaimTemplates:
          - metadata:
              name: data
            spec:
              resources:
                requests:
                  storage: 150Gi
              storageClassName: lso-sc
              volumeMode: Block
              accessModes:
                - ReadWriteOnce
EOF

print_success "CephCluster recreated"

echo ""
print_info "Step 4: Waiting for OSDs to be created (this may take 5-10 minutes)..."
for i in {1..60}; do
    OSD_COUNT=$(oc get pods -n ${NAMESPACE} --no-headers 2>&1 | grep "rook-ceph-osd-[0-9]" | wc -l | tr -d ' ')
    # Ensure OSD_COUNT is a valid integer
    if ! [[ "$OSD_COUNT" =~ ^[0-9]+$ ]]; then
        OSD_COUNT=0
    fi
    if [ "$OSD_COUNT" -ge 3 ]; then
        print_success "Found ${OSD_COUNT} OSD pods"
        break
    fi
    if [ $i -eq 60 ]; then
        print_warning "Timeout waiting for OSDs. Found ${OSD_COUNT} OSDs"
        print_info "You can check status with: oc get pods -n ${NAMESPACE} | grep osd"
    fi
    echo -n "."
    sleep 10
done
echo ""

echo ""
print_info "Step 5: Creating storage pools..."

print_info "  Creating CephBlockPool (replicapool)..."
cat <<'EOF' | oc apply -f -
apiVersion: ceph.rook.io/v1
kind: CephBlockPool
metadata:
  name: replicapool
  namespace: rook-ceph
spec:
  failureDomain: host
  replicated:
    size: 3
    requireSafeReplicaSize: true
  compressionMode: none
EOF

print_info "  Creating CephFilesystem (myfs)..."
cat <<'EOF' | oc apply -f -
apiVersion: ceph.rook.io/v1
kind: CephFilesystem
metadata:
  name: myfs
  namespace: rook-ceph
spec:
  metadataPool:
    replicated:
      size: 3
      requireSafeReplicaSize: true
    compressionMode: none
  dataPools:
    - name: replicated
      failureDomain: host
      replicated:
        size: 3
        requireSafeReplicaSize: true
      compressionMode: none
  metadataServer:
    activeCount: 1
    activeStandby: true
    resources:
      limits:
        memory: "4Gi"
      requests:
        cpu: "1000m"
        memory: "4Gi"
EOF

print_info "  Waiting for pools to be ready..."
sleep 30

# Check if pools are ready
BLOCKPOOL_STATUS=$(oc get cephblockpool replicapool -n ${NAMESPACE} -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
FS_STATUS=$(oc get cephfilesystem myfs -n ${NAMESPACE} -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")

if [ "$BLOCKPOOL_STATUS" = "Ready" ]; then
    print_success "CephBlockPool is ready"
else
    print_warning "CephBlockPool status: $BLOCKPOOL_STATUS"
fi

if [ "$FS_STATUS" = "Ready" ]; then
    print_success "CephFilesystem is ready"
else
    print_warning "CephFilesystem status: $FS_STATUS"
fi

echo ""
print_info "Step 6: Fixing Ceph toolbox..."
oc delete deployment rook-ceph-tools -n ${NAMESPACE} --ignore-not-found=true

cat <<'EOF' | oc apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: rook-ceph-tools
  namespace: rook-ceph
  labels:
    app: rook-ceph-tools
spec:
  replicas: 1
  selector:
    matchLabels:
      app: rook-ceph-tools
  template:
    metadata:
      labels:
        app: rook-ceph-tools
    spec:
      dnsPolicy: ClusterFirstWithHostNet
      containers:
        - name: rook-ceph-tools
          image: quay.io/ceph/ceph:v18.2.4
          command:
            - /bin/bash
            - -c
            - |
              # Create ceph config
              cat > /etc/ceph/ceph.conf <<EOC
              [global]
              mon_host = $(grep -E -o '([0-9]{1,3}\.){3}[0-9]{1,3}' /etc/rook/mon-endpoints | tr '\n' ',' | sed 's/,$//')
              [client.admin]
              keyring = /etc/ceph/keyring
              EOC
              
              # Create keyring
              cat > /etc/ceph/keyring <<EOK
              [${ROOK_CEPH_USERNAME}]
              key = ${ROOK_CEPH_SECRET}
              caps mds = "allow *"
              caps mgr = "allow *"
              caps mon = "allow *"
              caps osd = "allow *"
              EOK
              
              # Keep container running
              tail -f /dev/null
          imagePullPolicy: IfNotPresent
          tty: true
          stdin: true
          env:
            - name: ROOK_CEPH_USERNAME
              valueFrom:
                secretKeyRef:
                  name: rook-ceph-mon
                  key: ceph-username
            - name: ROOK_CEPH_SECRET
              valueFrom:
                secretKeyRef:
                  name: rook-ceph-mon
                  key: ceph-secret
          volumeMounts:
            - mountPath: /etc/ceph
              name: ceph-config
            - name: mon-endpoint-volume
              mountPath: /etc/rook
      volumes:
        - name: ceph-config
          emptyDir: {}
        - name: mon-endpoint-volume
          configMap:
            name: rook-ceph-mon-endpoints
            items:
              - key: data
                path: mon-endpoints
EOF

print_info "Waiting for toolbox to be ready..."
sleep 20
oc wait --for=condition=ready pod -l app=rook-ceph-tools -n ${NAMESPACE} --timeout=120s || print_warning "Toolbox may take a few more minutes"

echo ""
print_info "=========================================="
print_success "Rook-Ceph storage fix complete!"
print_info "=========================================="

echo ""
print_info "Step 7: Verification"
echo ""

print_info "CephCluster status:"
oc get cephcluster -n ${NAMESPACE}

echo ""
print_info "Storage pools:"
oc get cephblockpool,cephfilesystem -n ${NAMESPACE}

echo ""
print_info "Storage classes:"
oc get sc | grep rook

echo ""
print_info "Checking Ceph status (may take a minute for toolbox to be fully ready)..."
sleep 10
oc rsh -n ${NAMESPACE} deployment/rook-ceph-tools ceph -s 2>&1 || print_warning "Toolbox not ready yet, try: oc rsh -n ${NAMESPACE} deployment/rook-ceph-tools ceph -s"

echo ""
print_info "Useful commands:"
print_info "  Check OSD pods:"
echo "    oc get pods -n ${NAMESPACE} | grep osd"

print_info "  Monitor Ceph health:"
echo "    oc rsh -n ${NAMESPACE} deployment/rook-ceph-tools ceph -s"

print_info "  Test storage:"
echo "    ./scripts/test-ceph-storage.sh ${KUBECONFIG}"

echo ""
print_success "Fix script completed!"

