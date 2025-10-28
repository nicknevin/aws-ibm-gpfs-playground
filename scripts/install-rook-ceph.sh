#!/bin/bash
#
# Upstream Rook-Ceph Installation Script
# 
# This script installs upstream Rook-Ceph (without ODF) on an OpenShift cluster
#
# Usage:
#   ./scripts/install-rook-ceph.sh <cluster-name>
#
# Example:
#   ./scripts/install-rook-ceph.sh dr-eun1b-1
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
ROOK_VERSION="v1.15.5"
NAMESPACE="rook-ceph"

print_info "Installing Upstream Rook-Ceph on cluster: ${CLUSTER_NAME}"
print_info "Rook version: ${ROOK_VERSION}"
echo ""

# Check if KUBECONFIG exists
if [ ! -f "${KUBECONFIG}" ]; then
    print_error "KUBECONFIG not found at ${KUBECONFIG}"
    print_error "Please ensure the cluster is created first"
    exit 1
fi

export KUBECONFIG

# Check if oc command is available
if ! command -v oc &> /dev/null; then
    print_error "oc command not found"
    print_error "Please ensure OpenShift CLI is installed"
    exit 1
fi

# Test cluster connectivity
print_info "Testing cluster connectivity..."
if ! oc get nodes &> /dev/null; then
    print_error "Cannot connect to cluster"
    exit 1
fi
print_success "Cluster is accessible"

# Get worker nodes count
WORKER_COUNT=$(oc get nodes -l node-role.kubernetes.io/worker --no-headers | wc -l)
print_info "Found ${WORKER_COUNT} worker nodes"

if [ "$WORKER_COUNT" -lt 3 ]; then
    print_warning "Less than 3 worker nodes detected. Ceph requires at least 3 nodes for proper replication"
fi

echo ""
print_info "Step 1/7: Creating Rook-Ceph namespace..."
if oc get namespace ${NAMESPACE} &> /dev/null; then
    print_warning "Namespace ${NAMESPACE} already exists, skipping"
else
    oc create namespace ${NAMESPACE}
    print_success "Namespace created"
fi

echo ""
print_info "Step 2/7: Installing Rook CRDs..."
oc apply -f "https://raw.githubusercontent.com/rook/rook/${ROOK_VERSION}/deploy/examples/crds.yaml"
print_success "CRDs installed"

echo ""
print_info "Step 3/7: Installing Rook common resources..."
oc apply -f "https://raw.githubusercontent.com/rook/rook/${ROOK_VERSION}/deploy/examples/common.yaml"
print_success "Common resources installed"

echo ""
print_info "Step 4/7: Installing Rook operator..."
oc apply -f "https://raw.githubusercontent.com/rook/rook/${ROOK_VERSION}/deploy/examples/operator-openshift.yaml"
print_info "Waiting for Rook operator to be ready (this may take a few minutes)..."
oc wait --for=condition=ready pod -l app=rook-ceph-operator -n ${NAMESPACE} --timeout=300s
print_success "Rook operator is ready"

echo ""
print_info "Step 5/8: Labeling worker nodes for Ceph..."
for node in $(oc get nodes -l node-role.kubernetes.io/worker -o name); do
    oc label $node role=storage-node --overwrite
    print_info "  Labeled: $(basename $node)"
done
print_success "All worker nodes labeled"

echo ""
print_info "Step 6/8: Creating Ceph cluster configuration..."

# Get worker node names
NODES=($(oc get nodes -l node-role.kubernetes.io/worker -o jsonpath='{.items[*].metadata.name}'))

# Create cluster YAML
CLUSTER_YAML="${PLAYGROUND_DIR}/rook-ceph-cluster.yaml"

print_info "Checking if LSO (Local Storage Operator) PVs are available..."
LSO_PV_COUNT=$(oc get pv --no-headers 2>/dev/null | grep -c "lso-sc" || echo "0")

if [ "$LSO_PV_COUNT" -ge 3 ]; then
    print_success "Found ${LSO_PV_COUNT} LSO PVs - using storageClassDeviceSets (PVC-based storage)"
    STORAGE_MODE="pvc"
else
    # Check if LSO LocalVolume exists (LSO is installed but PVs not ready yet)
    if oc get localvolume -n openshift-local-storage local-block &>/dev/null; then
        print_warning "LSO is installed but PVs not ready yet. Waiting 30 seconds..."
        sleep 30
        LSO_PV_COUNT=$(oc get pv --no-headers 2>/dev/null | grep -c "lso-sc" || echo "0")
        if [ "$LSO_PV_COUNT" -ge 3 ]; then
            print_success "Found ${LSO_PV_COUNT} LSO PVs after waiting - using storageClassDeviceSets"
            STORAGE_MODE="pvc"
        else
            print_error "LSO is installed but no PVs found. Please check LSO configuration."
            print_info "Expected: 3+ PVs with storageClassName 'lso-sc'"
            print_info "Current: ${LSO_PV_COUNT} PVs found"
            exit 1
        fi
    else
        print_error "No LSO PVs found and LSO not installed."
        print_info "Please run: ansible-playbook -i hosts -e @<cluster-config>.yaml playbooks/dr-ceph.yml --tags lso1,ceph_disks"
        exit 1
    fi
fi

cat > "${CLUSTER_YAML}" <<EOF
apiVersion: ceph.rook.io/v1
kind: CephCluster
metadata:
  name: rook-ceph
  namespace: ${NAMESPACE}
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
    # Note: Monitoring disabled to avoid RBAC issues with servicemonitors
    # Can be enabled after cluster is running if Prometheus Operator is installed
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

print_success "Cluster configuration created at ${CLUSTER_YAML}"

echo ""
print_info "Step 7/8: Deploying Ceph cluster (this will take 15-30 minutes)..."
oc apply -f "${CLUSTER_YAML}"

print_info "Waiting for Ceph monitors to be ready..."
sleep 30
oc wait --for=condition=ready pod -l app=rook-ceph-mon -n ${NAMESPACE} --timeout=600s || true

print_info "Waiting for Ceph OSDs to be ready..."
sleep 30
oc wait --for=condition=ready pod -l app=rook-ceph-osd -n ${NAMESPACE} --timeout=1200s || true

print_success "Ceph cluster deployed"

echo ""
print_info "Step 8/8: Creating storage classes..."

# Create RBD Block Storage
print_info "  Creating RBD (Block) storage class..."
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
---
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: rook-ceph-block
provisioner: rook-ceph.rbd.csi.ceph.com
parameters:
  clusterID: rook-ceph
  pool: replicapool
  imageFormat: "2"
  imageFeatures: layering
  csi.storage.k8s.io/provisioner-secret-name: rook-csi-rbd-provisioner
  csi.storage.k8s.io/provisioner-secret-namespace: rook-ceph
  csi.storage.k8s.io/controller-expand-secret-name: rook-csi-rbd-provisioner
  csi.storage.k8s.io/controller-expand-secret-namespace: rook-ceph
  csi.storage.k8s.io/node-stage-secret-name: rook-csi-rbd-node
  csi.storage.k8s.io/node-stage-secret-namespace: rook-ceph
  csi.storage.k8s.io/fstype: ext4
allowVolumeExpansion: true
reclaimPolicy: Delete
EOF

# Create CephFS File Storage
print_info "  Creating CephFS (File) storage class..."
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
  dataPools:
    - name: replicated
      replicated:
        size: 3
        requireSafeReplicaSize: true
  preserveFilesystemOnDelete: true
  metadataServer:
    activeCount: 1
    activeStandby: true
    resources:
      requests:
        cpu: "3000m"
        memory: "8Gi"
      limits:
        memory: "8Gi"
---
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: rook-cephfs
provisioner: rook-ceph.cephfs.csi.ceph.com
parameters:
  clusterID: rook-ceph
  fsName: myfs
  pool: myfs-replicated
  csi.storage.k8s.io/provisioner-secret-name: rook-csi-cephfs-provisioner
  csi.storage.k8s.io/provisioner-secret-namespace: rook-ceph
  csi.storage.k8s.io/controller-expand-secret-name: rook-csi-cephfs-provisioner
  csi.storage.k8s.io/controller-expand-secret-namespace: rook-ceph
  csi.storage.k8s.io/node-stage-secret-name: rook-csi-cephfs-node
  csi.storage.k8s.io/node-stage-secret-namespace: rook-ceph
allowVolumeExpansion: true
reclaimPolicy: Delete
EOF

sleep 10
print_success "Storage classes created"

echo ""
print_info "Deploying Ceph toolbox for management..."
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
sleep 10
oc wait --for=condition=ready pod -l app=rook-ceph-tools -n ${NAMESPACE} --timeout=300s || true

echo ""
print_info "Creating route for Ceph dashboard..."
cat <<'EOF' | oc apply -f -
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: ceph-dashboard
  namespace: rook-ceph
spec:
  port:
    targetPort: https-dashboard
  tls:
    insecureEdgeTerminationPolicy: Redirect
    termination: passthrough
  to:
    kind: Service
    name: rook-ceph-mgr-dashboard
    weight: 100
EOF

echo ""
echo "=========================================="
print_success "Rook-Ceph installation complete!"
echo "=========================================="
echo ""
print_info "Cluster Information:"
echo "  Namespace: ${NAMESPACE}"
echo "  Cluster Name: rook-ceph"
echo ""

# Get Ceph status
print_info "Ceph Cluster Status:"
oc rsh -n ${NAMESPACE} deployment/rook-ceph-tools ceph -s 2>/dev/null || print_warning "  Ceph toolbox not ready yet, try: oc rsh -n ${NAMESPACE} deployment/rook-ceph-tools ceph -s"

echo ""
print_info "Storage Classes Available:"
oc get sc | grep rook || echo "  Storage classes being created..."

echo ""
print_info "Ceph Dashboard:"
DASHBOARD_URL=$(oc get route ceph-dashboard -n ${NAMESPACE} -o jsonpath='{.spec.host}' 2>/dev/null)
if [ -n "${DASHBOARD_URL}" ]; then
    echo "  URL: https://${DASHBOARD_URL}"
    echo "  Username: admin"
    echo "  Password: $(oc get secret rook-ceph-dashboard-password -n ${NAMESPACE} -o jsonpath='{.data.password}' 2>/dev/null | base64 -d)"
else
    print_warning "  Dashboard route not ready yet"
fi

echo ""
print_info "Next Steps:"
echo "  1. Check cluster status: oc rsh -n ${NAMESPACE} deployment/rook-ceph-tools ceph -s"
echo "  2. Check pods: oc get pods -n ${NAMESPACE}"
echo "  3. Check storage classes: oc get sc"
echo "  4. See the full guide: docs/CEPH-ROOK-INSTALLATION.md"
echo ""
print_success "Installation script finished!"

