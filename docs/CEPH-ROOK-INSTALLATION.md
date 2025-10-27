# Ceph/Rook Installation and Management Guide

## Table of Contents

1. [Overview](#overview)
2. [Installation Options](#installation-options)
3. [What Gets Installed](#what-gets-installed)
4. [Installation Process](#installation-process)
5. [Verification](#verification)
6. [Monitoring](#monitoring)
7. [Troubleshooting](#troubleshooting)
8. [Storage Classes and Usage](#storage-classes-and-usage)
9. [Cleanup and Removal](#cleanup-and-removal)

## Overview

This guide covers the installation and management of **Ceph storage** on OpenShift using **Rook** (the Kubernetes operator for Ceph).

### What is Rook?

**Rook** is a Cloud-Native storage orchestrator for Kubernetes. It automates the deployment, bootstrapping, configuration, provisioning, scaling, upgrading, migration, disaster recovery, monitoring, and resource management of Ceph storage.

## Installation Options

You have two options for installing Rook-Ceph on OpenShift:

### Option 1: Upstream Rook-Ceph (Community) - **RECOMMENDED**

**Pros**:
- ✅ Latest upstream features
- ✅ More control over configuration
- ✅ No licensing concerns
- ✅ Direct community support
- ✅ Faster updates from upstream
- ✅ Lighter weight (no ODF overhead)

**Cons**:
- ❌ No Red Hat commercial support
- ❌ Manual installation required
- ❌ No ODF-specific integrations

**Best for**: Development, testing, cost-conscious deployments, users who prefer upstream

### Option 2: OpenShift Data Foundation (ODF) - Red Hat's Product

**Pros**:
- ✅ Commercial Red Hat support
- ✅ Operator-based installation (easier)
- ✅ Additional features (NooBaa, Multi-cloud Gateway)
- ✅ Integrated with OpenShift Console
- ✅ Red Hat certified and tested

**Cons**:
- ❌ Requires Red Hat subscription
- ❌ More overhead (additional operators)
- ❌ Less flexibility in configuration
- ❌ May lag behind upstream Rook releases

**Best for**: Production environments requiring Red Hat support, enterprises with Red Hat subscriptions

### Comparison Table

| Feature | Upstream Rook-Ceph | ODF (Red Hat) |
|---------|-------------------|---------------|
| **Cost** | Free | Requires subscription |
| **Support** | Community | Red Hat Commercial |
| **Installation** | Manual YAML | Operator |
| **Updates** | Upstream pace | Red Hat pace |
| **NooBaa** | Optional | Included |
| **Ceph Version** | Latest stable | Red Hat tested |
| **Configuration** | Full control | Opinionated defaults |

**This guide covers BOTH installation methods.**

### Architecture

```
┌───────────────────────────────────────────────────────────────┐
│                    OpenShift Cluster                          │
│                                                                │
│  ┌─────────────────────────────────────────────────────────┐  │
│  │  Local Storage Operator (LSO)                          │  │
│  │  - Discovers and manages local disks                   │  │
│  │  - Creates PVs from EBS volumes attached to nodes      │  │
│  └─────────────────────────────────────────────────────────┘  │
│                           ↓                                    │
│  ┌─────────────────────────────────────────────────────────┐  │
│  │  OpenShift Data Foundation (ODF) Operator              │  │
│  │  - Installs Rook-Ceph operator                         │  │
│  │  - Manages Ceph cluster lifecycle                      │  │
│  └─────────────────────────────────────────────────────────┘  │
│                           ↓                                    │
│  ┌─────────────────────────────────────────────────────────┐  │
│  │  Ceph Storage Cluster                                   │  │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐              │  │
│  │  │ Ceph Mon │  │ Ceph Mon │  │ Ceph Mon │              │  │
│  │  │ (Monitor)│  │ (Monitor)│  │ (Monitor)│              │  │
│  │  └──────────┘  └──────────┘  └──────────┘              │  │
│  │                                                           │  │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐              │  │
│  │  │ Ceph OSD │  │ Ceph OSD │  │ Ceph OSD │              │  │
│  │  │ (Storage)│  │ (Storage)│  │ (Storage)│              │  │
│  │  │ on EBS   │  │ on EBS   │  │ on EBS   │              │  │
│  │  └──────────┘  └──────────┘  └──────────┘              │  │
│  │                                                           │  │
│  │  ┌──────────┐  ┌──────────┐                             │  │
│  │  │ Ceph MGR │  │ Ceph MDS │                             │  │
│  │  │(Manager) │  │(Metadata)│                             │  │
│  │  └──────────┘  └──────────┘                             │  │
│  │                                                           │  │
│  │  ┌────────────────────────────────────────┐              │  │
│  │  │ NooBaa (Multi-Cloud Object Gateway)   │              │  │
│  │  │ - S3-compatible object storage         │              │  │
│  │  └────────────────────────────────────────┘              │  │
│  └─────────────────────────────────────────────────────────┘  │
│                           ↓                                    │
│  ┌─────────────────────────────────────────────────────────┐  │
│  │  Storage Classes                                         │  │
│  │  - RBD (Block Storage)                                   │  │
│  │  - CephFS (File Storage)                                 │  │
│  │  - RGW (Object Storage - S3)                             │  │
│  └─────────────────────────────────────────────────────────┘  │
└───────────────────────────────────────────────────────────────┘
```

## What Gets Installed

### Components by Installation Method

#### Common to Both Methods:
- Local Storage Operator (LSO) - manages local disks
- Ceph storage cluster (MON, OSD, MGR, MDS)
- Storage classes for Block (RBD), File (CephFS), and Object (RGW) storage

#### ODF-Specific (Option 2 Only):
- OpenShift Data Foundation operator
- NooBaa multi-cloud gateway
- ODF Console integration
- Additional monitoring and management tools

#### Upstream Rook-Specific (Option 1):
- Rook operator directly from upstream
- Optional Ceph dashboard
- Optional object storage gateway
- More customizable configurations

---

## Installation Process

Choose your installation method:
- **[Method A: Upstream Rook-Ceph Installation](#method-a-upstream-rook-ceph-installation)** (Recommended for most users)
- **[Method B: ODF Installation](#method-b-odf-installation-via-playbook)** (For Red Hat support)

---

## Method A: Upstream Rook-Ceph Installation

This method installs vanilla Rook-Ceph without OpenShift Data Foundation.

### Prerequisites

Before running the installation, ensure:

1. **Cluster is running**: Your OpenShift cluster must be operational
2. **Worker nodes available**: At least 3 worker nodes (or 3 master nodes acting as workers)
3. **AWS credentials configured**: For EBS volume creation
4. **KUBECONFIG set**: Point to your cluster's kubeconfig
5. **oc CLI available**: OpenShift command-line tool

### Step 1: Prepare Local Storage

First, we need to prepare the EBS volumes and Local Storage Operator:

```bash
cd /home/nlevanon/workspace/DR/aws-ibm-gpfs-playground

# Set your cluster config
export CLUSTER_CONFIG=dr-eun1b-cluster1.yaml

# Install LSO and create EBS volumes
ansible-playbook -i hosts -e @${CLUSTER_CONFIG} playbooks/dr-ceph.yml --tags lso1,ceph_disks
```

This will:
1. Install Local Storage Operator
2. Create EBS io2 volumes (160 GiB per worker)
3. Attach volumes to worker nodes
4. Create LocalVolume CR for disk discovery
5. Create PVs from discovered disks

**Time**: 5-10 minutes

### Step 2: Install Upstream Rook Operator

Now install the Rook operator from upstream:

```bash
# Set your cluster KUBECONFIG
export KUBECONFIG=~/dr-playground/dr-eun1b-1/ocp_install_files/auth/kubeconfig

# Get latest Rook version (or specify a version)
ROOK_VERSION=v1.15.5

# Create rook-ceph namespace
oc create namespace rook-ceph

# Install CRDs
oc apply -f https://raw.githubusercontent.com/rook/rook/${ROOK_VERSION}/deploy/examples/crds.yaml

# Install common resources
oc apply -f https://raw.githubusercontent.com/rook/rook/${ROOK_VERSION}/deploy/examples/common.yaml

# Install Rook operator for OpenShift
oc apply -f https://raw.githubusercontent.com/rook/rook/${ROOK_VERSION}/deploy/examples/operator-openshift.yaml

# Wait for operator to be ready
oc wait --for=condition=ready pod -l app=rook-ceph-operator -n rook-ceph --timeout=300s
```

**Time**: 2-5 minutes

### Step 3: Label Worker Nodes

Label the nodes where Ceph should run:

```bash
# Label all worker nodes for Ceph
for node in $(oc get nodes -l node-role.kubernetes.io/worker -o name); do
  oc label $node role=storage-node
done

# Verify labels
oc get nodes -l role=storage-node
```

### Step 4: Create Ceph Cluster

Create the Ceph cluster configuration:

```bash
# Create cluster YAML
cat <<'EOF' > ~/dr-playground/dr-eun1b-1/rook-ceph-cluster.yaml
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
    enabled: true
    createPrometheusRules: true
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
    useAllNodes: false
    useAllDevices: false
    nodes:
      - name: REPLACE_WITH_NODE_NAME_1
        devices:
          - name: "/dev/sde"
      - name: REPLACE_WITH_NODE_NAME_2
        devices:
          - name: "/dev/sde"
      - name: REPLACE_WITH_NODE_NAME_3
        devices:
          - name: "/dev/sde"
EOF

# Get worker node names and update the YAML
NODES=($(oc get nodes -l node-role.kubernetes.io/worker -o jsonpath='{.items[*].metadata.name}'))

# Replace node names in the YAML
sed -i "s/REPLACE_WITH_NODE_NAME_1/${NODES[0]}/g" ~/dr-playground/dr-eun1b-1/rook-ceph-cluster.yaml
sed -i "s/REPLACE_WITH_NODE_NAME_2/${NODES[1]}/g" ~/dr-playground/dr-eun1b-1/rook-ceph-cluster.yaml
sed -i "s/REPLACE_WITH_NODE_NAME_3/${NODES[2]}/g" ~/dr-playground/dr-eun1b-1/rook-ceph-cluster.yaml

# Apply the cluster configuration
oc apply -f ~/dr-playground/dr-eun1b-1/rook-ceph-cluster.yaml

# Watch the cluster come up
oc get pods -n rook-ceph -w
```

**Time**: 15-30 minutes

### Step 5: Create Storage Classes

Create storage classes for RBD (Block) and CephFS (File):

```bash
# Create RBD Storage Class (Block - RWO)
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

# Create CephFS Storage Class (File - RWX)
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

# (Optional) Create Object Storage
cat <<'EOF' | oc apply -f -
apiVersion: ceph.rook.io/v1
kind: CephObjectStore
metadata:
  name: my-store
  namespace: rook-ceph
spec:
  metadataPool:
    replicated:
      size: 3
  dataPool:
    replicated:
      size: 3
  preservePoolsOnDelete: true
  gateway:
    port: 80
    instances: 1
    resources:
      requests:
        cpu: "1000m"
        memory: "2Gi"
      limits:
        memory: "2Gi"
---
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: rook-ceph-bucket
provisioner: rook-ceph.ceph.rook.io/bucket
reclaimPolicy: Delete
parameters:
  objectStoreName: my-store
  objectStoreNamespace: rook-ceph
EOF
```

**Time**: 5-10 minutes

### Step 6: Enable Ceph Dashboard (Optional)

Expose the Ceph dashboard via OpenShift route:

```bash
# Create route for Ceph dashboard
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

# Get dashboard URL
echo "Dashboard URL: https://$(oc get route ceph-dashboard -n rook-ceph -o jsonpath='{.spec.host}')"

# Get dashboard password
echo "Username: admin"
echo "Password: $(oc get secret rook-ceph-dashboard-password -n rook-ceph -o jsonpath='{.data.password}' | base64 -d)"
```

### Step 7: Deploy Ceph Toolbox (for management)

```bash
# Deploy toolbox
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
              # Replicate the script from toolbox.sh inline so the ceph image can be run directly without requiring the rook toolbox
              CEPH_CONFIG="/etc/ceph/ceph.conf"
              MON_CONFIG="/etc/rook/mon-endpoints"
              KEYRING_FILE="/etc/ceph/keyring"

              # create a ceph config file in its default location so ceph/rados tools can be used
              # without specifying any arguments
              cat <<-ENDHERE > ${CEPH_CONFIG}
              [global]
              mon_host = $(grep mon_host ${MON_CONFIG} | awk '{print $3}')

              [client.admin]
              keyring = ${KEYRING_FILE}
              ENDHERE

              # watch the endpoints in the background and update if they change
              /usr/local/bin/toolbox.sh &

              # run bash in the foreground
              /bin/bash
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

# Wait for toolbox to be ready
oc wait --for=condition=ready pod -l app=rook-ceph-tools -n rook-ceph --timeout=300s

# Test the toolbox
oc rsh -n rook-ceph deployment/rook-ceph-tools ceph status
```

### Verification for Upstream Rook

```bash
# Check all pods
oc get pods -n rook-ceph

# Check Ceph status
oc rsh -n rook-ceph deployment/rook-ceph-tools ceph -s

# Check storage classes
oc get sc | grep rook

# Expected storage classes:
# rook-ceph-block    - Block storage (RWO)
# rook-cephfs        - File storage (RWX)
# rook-ceph-bucket   - Object storage (OBC)
```

**Total Installation Time**: 30-50 minutes

---

## Method B: ODF Installation (via Playbook)

This method uses the existing playbook to install OpenShift Data Foundation (Red Hat's product).

The `dr-ceph.yml` playbook installs the following components:

### 1. Local Storage Operator (LSO)
- **Namespace**: `openshift-local-storage`
- **Purpose**: Discovers and manages local disks (EBS volumes attached to nodes)
- **Provides**: Local PVs for Ceph OSDs

### 2. OpenShift Data Foundation (ODF) Operator
- **Namespace**: `openshift-storage`
- **Purpose**: Installs and manages Rook-Ceph
- **Includes**:
  - Rook operator (manages Ceph lifecycle)
  - Ceph operators (mon, osd, mgr, mds)
  - NooBaa operator (multi-cloud object gateway)

### 3. Ceph Storage Cluster Components

#### Ceph Monitors (MON)
- **Count**: 3 replicas
- **Purpose**: Maintain cluster state and consensus
- **Resources**: 1 CPU, 2 GiB RAM
- **Storage**: 30 GiB PVC on gp2-csi

#### Ceph OSDs (Object Storage Daemons)
- **Count**: 3 (1 per worker node)
- **Purpose**: Store actual data
- **Resources**: 2 CPU, 5 GiB RAM
- **Storage**: 120 GiB block volumes from LSO (using attached EBS volumes)

#### Ceph Manager (MGR)
- **Count**: 2 (active-standby)
- **Purpose**: Cluster monitoring, orchestration, and dashboard
- **Resources**: 1 CPU, 3 GiB RAM

#### Ceph MDS (Metadata Servers)
- **Count**: 2 (active-standby)
- **Purpose**: Manages CephFS metadata
- **Resources**: 3 CPU, 8 GiB RAM

#### NooBaa
- **Components**: NooBaa Core + PostgreSQL DB
- **Purpose**: S3-compatible object storage gateway
- **Resources**: 
  - Core: 1 CPU, 4 GiB RAM
  - DB: 1 CPU, 4 GiB RAM

### 4. Storage Infrastructure

#### EBS Volumes
- **Type**: io2 (high-performance SSD)
- **Size**: 160 GiB per worker node
- **IOPS**: 5000
- **Device**: /dev/sde
- **Count**: 1 per worker node

#### Storage Classes Created
- RBD (Block): For RWO persistent volumes
- CephFS (File): For RWX persistent volumes  
- RGW (Object): For S3-compatible object storage

## Installation Process

### Prerequisites

Before running the installation, ensure:

1. **Cluster is running**: Your OpenShift cluster must be operational
2. **Worker nodes available**: At least 3 worker nodes (or 3 master nodes acting as workers)
3. **AWS credentials configured**: For EBS volume creation
4. **KUBECONFIG set**: Point to your cluster's kubeconfig

### Installation Command

```bash
cd /home/nlevanon/workspace/DR/aws-ibm-gpfs-playground

# Install Ceph on DR Cluster 1
ansible-playbook -i hosts -e @dr-eun1b-cluster1.yaml playbooks/dr-ceph.yml
```

### What the Playbook Does

The playbook executes the following steps:

#### Phase 1: Local Storage Operator Setup (5-10 minutes)
1. Creates `openshift-local-storage` namespace
2. Installs Local Storage Operator subscription
3. Waits for LSO to be ready

#### Phase 2: EBS Volume Creation (2-5 minutes)
1. Discovers worker node EC2 instance IDs
2. Creates EBS io2 volumes (160 GiB each)
3. Attaches volumes to worker nodes as `/dev/sde`
4. Tags volumes with `ceph-ebs-<instance-id>`

#### Phase 3: LocalVolume Configuration (1-2 minutes)
1. Creates LocalVolume CR to discover EBS volumes
2. LSO creates PVs from discovered disks
3. Creates `lso-sc` StorageClass

#### Phase 4: ODF Operator Installation (5-10 minutes)
1. Creates `openshift-storage` namespace
2. Installs ODF operator subscription
3. Labels worker nodes with `cluster.ocs.openshift.io/openshift-storage=''`
4. Waits for operator to be ready

#### Phase 5: Ceph Cluster Deployment (15-30 minutes)
1. Creates StorageCluster CR
2. Rook operator deploys Ceph components:
   - 3 Ceph Monitors
   - 3 Ceph OSDs (one per worker)
   - 2 Ceph Managers
   - 2 Ceph MDS servers
   - NooBaa core and DB
3. Creates StorageClasses
4. Creates CephObjectStore
5. Exposes S3 route

**Total Installation Time**: ~30-60 minutes

### Installation Flow Diagram

```
Start
  ↓
Install LSO Operator ────→ Wait for operator ready (5-10 min)
  ↓
Discover Worker Nodes ───→ Query AWS EC2 for running workers
  ↓
Create EBS Volumes ──────→ 160GB io2 per worker (2-5 min)
  ↓
Create LocalVolume CR ───→ LSO discovers disks, creates PVs (1-2 min)
  ↓
Install ODF Operator ────→ Wait for operator ready (5-10 min)
  ↓
Label Worker Nodes ──────→ Mark for Ceph placement
  ↓
Create StorageCluster ───→ Rook deploys Ceph (15-30 min)
  ↓
Verify Components ───────→ Check pods, PVs, StorageClasses
  ↓
End
```

## Verification

### Quick Health Check

Run this command to get a quick overview:

```bash
export KUBECONFIG=~/dr-playground/dr-eun1b-1/ocp_install_files/auth/kubeconfig

# Check all ODF/Ceph pods
oc get pods -n openshift-storage
```

**Expected Output** (all pods should be Running):
```
NAME                                                              READY   STATUS
csi-cephfsplugin-xxxxx                                           3/3     Running
csi-cephfsplugin-provisioner-xxxxx                               6/6     Running
csi-rbdplugin-xxxxx                                              3/3     Running
csi-rbdplugin-provisioner-xxxxx                                  6/6     Running
noobaa-core-0                                                     1/1     Running
noobaa-db-pg-0                                                    1/1     Running
noobaa-endpoint-xxxxx                                             1/1     Running
noobaa-operator-xxxxx                                             1/1     Running
ocs-metrics-exporter-xxxxx                                        1/1     Running
ocs-operator-xxxxx                                                1/1     Running
odf-console-xxxxx                                                 1/1     Running
odf-operator-controller-manager-xxxxx                             2/2     Running
rook-ceph-crashcollector-xxxxx                                    1/1     Running
rook-ceph-mds-ocs-storagecluster-cephfilesystem-a-xxxxx          2/2     Running
rook-ceph-mds-ocs-storagecluster-cephfilesystem-b-xxxxx          2/2     Running
rook-ceph-mgr-a-xxxxx                                             2/2     Running
rook-ceph-mon-a-xxxxx                                             2/2     Running
rook-ceph-mon-b-xxxxx                                             2/2     Running
rook-ceph-mon-c-xxxxx                                             2/2     Running
rook-ceph-operator-xxxxx                                          1/1     Running
rook-ceph-osd-0-xxxxx                                             2/2     Running
rook-ceph-osd-1-xxxxx                                             2/2     Running
rook-ceph-osd-2-xxxxx                                             2/2     Running
rook-ceph-osd-prepare-xxxxx                                       0/1     Completed
```

### Detailed Verification Steps

#### 1. Verify Operators are Installed

```bash
# Check LSO operator
oc get csv -n openshift-local-storage

# Check ODF operator
oc get csv -n openshift-storage
```

**Expected**: Both operators should show `Succeeded` phase.

#### 2. Verify EBS Volumes are Attached

```bash
# From AWS CLI
aws ec2 describe-volumes \
  --region eu-north-1 \
  --filters "Name=tag:Name,Values=ceph-ebs-*" \
  --query 'Volumes[*].[VolumeId,State,Attachments[0].InstanceId,Size]' \
  --output table
```

**Expected**: 3 volumes (one per worker), all in `in-use` state.

#### 3. Verify Local PVs are Created

```bash
# Check PVs created by LSO
oc get pv | grep local

# Check LocalVolume CR
oc get localvolume -n openshift-local-storage
```

**Expected**: 3 PVs in `Bound` state.

#### 4. Verify Ceph Cluster Health

```bash
# Check StorageCluster status
oc get storagecluster -n openshift-storage

# Get detailed status
oc describe storagecluster ocs-storagecluster -n openshift-storage | grep -A 10 "Status:"
```

**Expected**: Phase should be `Ready` or `Progressing` (during installation).

#### 5. Check Ceph Health via Toolbox

```bash
# Deploy Ceph toolbox (if not already deployed)
cat <<EOF | oc apply -f -
apiVersion: ocs.openshift.io/v1
kind: OCSInitialization
metadata:
  name: ocsinit
  namespace: openshift-storage
spec:
  enableCephTools: true
EOF

# Wait for toolbox pod
oc wait --for=condition=ready pod -l app=rook-ceph-tools -n openshift-storage --timeout=300s

# Check Ceph status
oc rsh -n openshift-storage $(oc get pod -n openshift-storage -l app=rook-ceph-tools -o name) ceph status

# Check Ceph health
oc rsh -n openshift-storage $(oc get pod -n openshift-storage -l app=rook-ceph-tools -o name) ceph health detail

# Check OSD status
oc rsh -n openshift-storage $(oc get pod -n openshift-storage -l app=rook-ceph-tools -o name) ceph osd status

# Check pool status
oc rsh -n openshift-storage $(oc get pod -n openshift-storage -l app=rook-ceph-tools -o name) ceph osd pool ls detail
```

**Expected Ceph Status**:
```
cluster:
  id:     xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
  health: HEALTH_OK
 
services:
  mon: 3 daemons, quorum a,b,c
  mgr: a(active), standbys: b
  mds: ocs-storagecluster-cephfilesystem:1 {0=a=up:active} 1 up:standby-replay
  osd: 3 osds: 3 up, 3 in
```

#### 6. Verify Storage Classes

```bash
# List all storage classes
oc get sc

# Check Ceph-specific storage classes
oc get sc | grep -E "rbd|cephfs|rgw"
```

**Expected Storage Classes**:
```
ocs-storagecluster-ceph-rbd          # Block storage (RWO)
ocs-storagecluster-cephfs            # File storage (RWX)
ocs-storagecluster-ceph-rgw          # Object storage (S3)
```

#### 7. Verify NooBaa (Object Storage)

```bash
# Check NooBaa status
oc get noobaa -n openshift-storage

# Get S3 endpoint
oc get route s3 -n openshift-storage -o jsonpath='{.spec.host}'

# Get NooBaa admin credentials
oc get secret noobaa-admin -n openshift-storage -o jsonpath='{.data.email}' | base64 -d
oc get secret noobaa-admin -n openshift-storage -o jsonpath='{.data.password}' | base64 -d
```

### Verification Checklist

- [ ] All pods in `openshift-storage` namespace are Running
- [ ] All pods in `openshift-local-storage` namespace are Running
- [ ] StorageCluster shows Phase: Ready
- [ ] Ceph status shows HEALTH_OK
- [ ] 3 OSDs are up and in
- [ ] 3 MONs are in quorum
- [ ] Storage classes are available
- [ ] NooBaa is running and accessible

## Monitoring

### 1. OpenShift Console (Web UI)

The easiest way to monitor Ceph is through the OpenShift console:

```bash
# Get console URL
oc whoami --show-console
```

Navigate to: **Storage** → **Data Foundation** → **Storage Systems**

Here you can see:
- Cluster health overview
- Capacity and usage metrics
- Performance graphs
- Component status

### 2. Ceph Dashboard

Rook deploys a Ceph dashboard for detailed monitoring:

```bash
# Check if dashboard is exposed
oc get route -n openshift-storage | grep dashboard

# If not exposed, create a route
cat <<EOF | oc apply -f -
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: ceph-dashboard
  namespace: openshift-storage
spec:
  port:
    targetPort: https-dashboard
  tls:
    insecureEdgeTerminationPolicy: Redirect
    termination: reencrypt
  to:
    kind: Service
    name: rook-ceph-mgr-dashboard
    weight: 100
EOF

# Get dashboard URL
echo "https://$(oc get route ceph-dashboard -n openshift-storage -o jsonpath='{.spec.host}')"

# Get dashboard credentials
echo "Username: admin"
echo "Password: $(oc get secret rook-ceph-dashboard-password -n openshift-storage -o jsonpath='{.data.password}' | base64 -d)"
```

**Dashboard Features**:
- Cluster health and status
- OSD performance metrics
- Pool usage and IOPS
- Monitor quorum status
- Performance counters
- Configuration settings

### 3. Command-Line Monitoring

#### Check Cluster Status
```bash
# Quick health check
oc rsh -n openshift-storage $(oc get pod -n openshift-storage -l app=rook-ceph-tools -o name) ceph -s

# Detailed health
oc rsh -n openshift-storage $(oc get pod -n openshift-storage -l app=rook-ceph-tools -o name) ceph health detail
```

#### Monitor OSDs
```bash
# OSD tree (topology)
oc rsh -n openshift-storage $(oc get pod -n openshift-storage -l app=rook-ceph-tools -o name) ceph osd tree

# OSD performance
oc rsh -n openshift-storage $(oc get pod -n openshift-storage -l app=rook-ceph-tools -o name) ceph osd perf

# OSD disk usage
oc rsh -n openshift-storage $(oc get pod -n openshift-storage -l app=rook-ceph-tools -o name) ceph osd df
```

#### Monitor Pools
```bash
# List pools
oc rsh -n openshift-storage $(oc get pod -n openshift-storage -l app=rook-ceph-tools -o name) ceph osd pool ls detail

# Pool statistics
oc rsh -n openshift-storage $(oc get pod -n openshift-storage -l app=rook-ceph-tools -o name) ceph df

# Pool IOPS
oc rsh -n openshift-storage $(oc get pod -n openshift-storage -l app=rook-ceph-tools -o name) ceph osd pool stats
```

#### Monitor Placement Groups (PGs)
```bash
# PG summary
oc rsh -n openshift-storage $(oc get pod -n openshift-storage -l app=rook-ceph-tools -o name) ceph pg stat

# Detailed PG status
oc rsh -n openshift-storage $(oc get pod -n openshift-storage -l app=rook-ceph-tools -o name) ceph pg dump
```

### 4. Prometheus Metrics

Ceph exports metrics to Prometheus. Access them via:

```bash
# Get Prometheus route
oc get route prometheus-k8s -n openshift-monitoring -o jsonpath='{.spec.host}'
```

**Key Metrics to Monitor**:
- `ceph_cluster_total_bytes` - Total cluster capacity
- `ceph_cluster_total_used_bytes` - Used capacity
- `ceph_osd_up` - OSD up/down status
- `ceph_osd_in` - OSD in/out status
- `ceph_health_status` - Overall health (0=OK, 1=WARN, 2=ERR)
- `ceph_pool_stored` - Data stored per pool
- `ceph_pool_rd` - Pool read IOPS
- `ceph_pool_wr` - Pool write IOPS

### 5. Log Monitoring

```bash
# Rook operator logs
oc logs -n openshift-storage -l app=rook-ceph-operator --tail=100 -f

# Specific Ceph component logs
oc logs -n openshift-storage -l app=rook-ceph-mon --tail=100
oc logs -n openshift-storage -l app=rook-ceph-osd --tail=100
oc logs -n openshift-storage -l app=rook-ceph-mgr --tail=100

# NooBaa logs
oc logs -n openshift-storage -l app=noobaa --tail=100
```

### 6. Alerts and Notifications

Check active alerts:

```bash
# Get Ceph-related alerts
oc get prometheusrule -n openshift-storage -o yaml | grep -A 5 "alert:"
```

Common alerts:
- `CephClusterWarningState` - Cluster in warning state
- `CephClusterErrorState` - Cluster in error state
- `CephOSDDiskNotResponding` - OSD not responding
- `CephMonQuorumAtRisk` - Monitor quorum at risk
- `CephPGRepairTakingTooLong` - PG repair taking too long

## Troubleshooting

### Common Issues and Solutions

#### Issue 1: Pods Stuck in Pending State

**Symptoms**:
```bash
oc get pods -n openshift-storage
NAME                     READY   STATUS    RESTARTS   AGE
rook-ceph-osd-0-xxxxx    0/2     Pending   0          10m
```

**Diagnosis**:
```bash
# Check pod events
oc describe pod <pod-name> -n openshift-storage

# Check node labels
oc get nodes --show-labels | grep storage

# Check PVs
oc get pv
```

**Common Causes & Solutions**:

1. **No storage nodes labeled**:
   ```bash
   # Label worker nodes for Ceph
   for node in $(oc get nodes -l node-role.kubernetes.io/worker -o name); do
     oc label $node cluster.ocs.openshift.io/openshift-storage=''
   done
   ```

2. **Insufficient resources**:
   ```bash
   # Check node resources
   oc adm top nodes
   
   # Scale down non-essential workloads or add more nodes
   ```

3. **No PVs available**:
   ```bash
   # Check if LSO created PVs
   oc get pv | grep local
   
   # Verify LocalVolume CR
   oc get localvolume -n openshift-local-storage -o yaml
   
   # Check LSO operator logs
   oc logs -n openshift-local-storage -l name=local-storage-operator
   ```

#### Issue 2: Ceph Health Warning

**Symptoms**:
```bash
oc rsh -n openshift-storage $(oc get pod -n openshift-storage -l app=rook-ceph-tools -o name) ceph health
HEALTH_WARN ...
```

**Diagnosis**:
```bash
# Get detailed health
oc rsh -n openshift-storage $(oc get pod -n openshift-storage -l app=rook-ceph-tools -o name) ceph health detail

# Check specific component status
oc rsh -n openshift-storage $(oc get pod -n openshift-storage -l app=rook-ceph-tools -o name) ceph -s
```

**Common Warnings & Solutions**:

1. **Clock skew detected**:
   ```
   HEALTH_WARN clock skew detected on mon.b
   ```
   **Solution**: Ensure NTP is synchronized on all nodes
   ```bash
   # Check time on nodes (run on each node)
   oc debug node/<node-name> -- chroot /host timedatectl
   ```

2. **Too few PGs**:
   ```
   HEALTH_WARN too few PGs per OSD
   ```
   **Solution**: Increase PG count for pools (not recommended for production without planning)
   ```bash
   # This is usually OK for small clusters and will resolve over time
   ```

3. **OSDs down**:
   ```
   HEALTH_WARN 1 osds down
   ```
   **Solution**: Check OSD pod status
   ```bash
   oc get pods -n openshift-storage -l app=rook-ceph-osd
   oc describe pod <osd-pod-name> -n openshift-storage
   oc logs <osd-pod-name> -n openshift-storage
   ```

#### Issue 3: StorageCluster Not Ready

**Symptoms**:
```bash
oc get storagecluster -n openshift-storage
NAME                 PHASE
ocs-storagecluster   Progressing
```

**Diagnosis**:
```bash
# Check StorageCluster status
oc describe storagecluster ocs-storagecluster -n openshift-storage

# Check operator logs
oc logs -n openshift-storage -l app=rook-ceph-operator --tail=100

# Check events
oc get events -n openshift-storage --sort-by='.lastTimestamp'
```

**Solutions**:

1. **Wait longer** - Initial deployment takes 15-30 minutes
2. **Check operator status**:
   ```bash
   oc get csv -n openshift-storage
   oc logs -n openshift-storage deployment/ocs-operator
   ```
3. **Verify prerequisites**:
   - Worker nodes labeled
   - PVs available
   - Sufficient node resources

#### Issue 4: No Storage Classes Created

**Symptoms**:
```bash
oc get sc | grep ceph
# No output
```

**Diagnosis**:
```bash
# Check if StorageCluster is ready
oc get storagecluster -n openshift-storage

# Check CSI drivers
oc get pods -n openshift-storage | grep csi
```

**Solution**:
```bash
# Storage classes are created automatically when StorageCluster is ready
# If missing, check operator logs
oc logs -n openshift-storage -l app=rook-ceph-operator --tail=200 | grep -i storageclass

# Manually trigger by patching StorageCluster (rarely needed)
oc patch storagecluster ocs-storagecluster -n openshift-storage --type merge -p '{"spec":{"managedResources":{"cephBlockPools":{"reconcileStrategy":"manage"}}}}'
```

#### Issue 5: OSD Creation Fails

**Symptoms**:
```bash
oc get pods -n openshift-storage | grep osd-prepare
rook-ceph-osd-prepare-xxxxx   0/1     Error   0          5m
```

**Diagnosis**:
```bash
# Check OSD prepare logs
oc logs -n openshift-storage <osd-prepare-pod-name>

# Check device availability
oc rsh -n openshift-storage <osd-prepare-pod-name> lsblk
```

**Common Causes & Solutions**:

1. **Disk already has data/filesystem**:
   ```bash
   # SSH to worker node
   oc debug node/<node-name>
   chroot /host
   
   # Check disk
   lsblk
   wipefs -a /dev/sde  # CAUTION: This erases data!
   ```

2. **Wrong device name**:
   ```bash
   # Verify device name in LocalVolume CR
   oc get localvolume -n openshift-local-storage -o yaml
   
   # Update if needed
   oc edit localvolume -n openshift-local-storage
   ```

3. **Insufficient disk size**:
   ```bash
   # OSD requires at least 10GB
   # Check EBS volume size
   aws ec2 describe-volumes --region eu-north-1 --filters "Name=tag:Name,Values=ceph-ebs-*"
   ```

#### Issue 6: NooBaa Not Starting

**Symptoms**:
```bash
oc get pods -n openshift-storage | grep noobaa
noobaa-core-0    0/1     CrashLoopBackOff   5          10m
```

**Diagnosis**:
```bash
# Check NooBaa logs
oc logs -n openshift-storage noobaa-core-0

# Check NooBaa status
oc get noobaa -n openshift-storage -o yaml
```

**Solutions**:

1. **Database not ready**:
   ```bash
   # Check PostgreSQL pod
   oc get pods -n openshift-storage | grep noobaa-db
   oc logs -n openshift-storage noobaa-db-pg-0
   ```

2. **Insufficient resources**:
   ```bash
   # Check node resources
   oc adm top nodes
   
   # Adjust NooBaa resources if needed
   oc edit noobaa -n openshift-storage
   ```

### Debug Commands

#### Enable Debug Logging

```bash
# Enable debug logging for Rook operator
oc set env -n openshift-storage deployment/rook-ceph-operator ROOK_LOG_LEVEL=DEBUG

# View debug logs
oc logs -n openshift-storage -l app=rook-ceph-operator -f
```

#### Ceph Toolbox Commands

```bash
# Get toolbox pod name
TOOLS_POD=$(oc get pod -n openshift-storage -l app=rook-ceph-tools -o name)

# Interactive shell
oc rsh -n openshift-storage $TOOLS_POD

# Inside toolbox, useful commands:
ceph status                    # Overall status
ceph health detail            # Detailed health info
ceph osd tree                 # OSD topology
ceph osd df                   # OSD disk usage
ceph df                       # Cluster usage
ceph pg dump                  # Placement groups
ceph mon stat                 # Monitor status
ceph mgr dump                 # Manager status
ceph auth list                # Authentication keys
ceph config dump              # Configuration
rados df                      # Pool usage
rados lspools                 # List pools
```

#### Check Ceph Logs Directly

```bash
# All Ceph logs
oc logs -n openshift-storage -l app=rook-ceph --all-containers=true --tail=100

# Specific components
oc logs -n openshift-storage -l ceph_daemon_type=mon --tail=100
oc logs -n openshift-storage -l ceph_daemon_type=osd --tail=100
oc logs -n openshift-storage -l ceph_daemon_type=mgr --tail=100
```

### Advanced Troubleshooting

#### Reset StorageCluster (CAUTION: Destroys data!)

```bash
# Delete StorageCluster
oc delete storagecluster ocs-storagecluster -n openshift-storage

# Wait for cleanup (may take several minutes)
oc get pods -n openshift-storage -w

# Recreate StorageCluster
ansible-playbook -i hosts -e @dr-eun1b-cluster1.yaml playbooks/dr-ceph.yml --tags ceph1
```

#### Force OSD Removal

```bash
# Mark OSD out
oc rsh -n openshift-storage $TOOLS_POD ceph osd out <osd-id>

# Wait for data rebalancing
oc rsh -n openshift-storage $TOOLS_POD ceph osd safe-to-destroy <osd-id>

# Remove OSD
oc rsh -n openshift-storage $TOOLS_POD ceph osd purge <osd-id> --yes-i-really-mean-it
```

## Storage Classes and Usage

### Available Storage Classes

After successful installation, you should have the following storage classes:

```bash
oc get sc | grep ocs

ocs-storagecluster-ceph-rbd       # Block (RWO) - RBD
ocs-storagecluster-cephfs         # File (RWX) - CephFS  
ocs-storagecluster-ceph-rgw       # Object (S3) - RGW
```

### Usage Examples

#### 1. Block Storage (RBD) - ReadWriteOnce

Best for: Databases, virtual machine disks, any single-pod application

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: my-block-pvc
  namespace: my-namespace
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: ocs-storagecluster-ceph-rbd
  resources:
    requests:
      storage: 10Gi
```

**Test the PVC**:
```bash
# Create test namespace
oc new-project ceph-test

# Create PVC
cat <<EOF | oc apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-rbd-pvc
  namespace: ceph-test
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: ocs-storagecluster-ceph-rbd
  resources:
    requests:
      storage: 5Gi
EOF

# Check PVC status
oc get pvc -n ceph-test

# Create a test pod
cat <<EOF | oc apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: test-rbd-pod
  namespace: ceph-test
spec:
  containers:
  - name: test
    image: busybox
    command: ["sh", "-c", "while true; do echo 'Hello Ceph RBD' > /data/test.txt; cat /data/test.txt; sleep 30; done"]
    volumeMounts:
    - name: data
      mountPath: /data
  volumes:
  - name: data
    persistentVolumeClaim:
      claimName: test-rbd-pvc
EOF

# Check pod logs
oc logs -n ceph-test test-rbd-pod
```

#### 2. File Storage (CephFS) - ReadWriteMany

Best for: Shared storage, multiple pods, CI/CD artifacts

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: my-file-pvc
  namespace: my-namespace
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: ocs-storagecluster-cephfs
  resources:
    requests:
      storage: 20Gi
```

**Test with multiple pods**:
```bash
# Create CephFS PVC
cat <<EOF | oc apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-cephfs-pvc
  namespace: ceph-test
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: ocs-storagecluster-cephfs
  resources:
    requests:
      storage: 5Gi
EOF

# Create deployment with 3 replicas sharing the volume
cat <<EOF | oc apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: test-cephfs
  namespace: ceph-test
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
        image: busybox
        command: ["sh", "-c", "while true; do echo \$(hostname) >> /shared/hosts.txt; cat /shared/hosts.txt; sleep 30; done"]
        volumeMounts:
        - name: shared
          mountPath: /shared
      volumes:
      - name: shared
        persistentVolumeClaim:
          claimName: test-cephfs-pvc
EOF

# Check that all pods are writing to shared volume
oc logs -n ceph-test -l app=test-cephfs --tail=20
```

#### 3. Object Storage (S3) - NooBaa

Best for: Application backups, large files, multi-cloud data

```bash
# Get S3 endpoint
S3_ENDPOINT=$(oc get route s3 -n openshift-storage -o jsonpath='{.spec.host}')

# Get credentials
S3_ACCESS_KEY=$(oc get secret noobaa-admin -n openshift-storage -o jsonpath='{.data.AWS_ACCESS_KEY_ID}' | base64 -d)
S3_SECRET_KEY=$(oc get secret noobaa-admin -n openshift-storage -o jsonpath='{.data.AWS_SECRET_ACCESS_KEY}' | base64 -d)

echo "S3 Endpoint: https://$S3_ENDPOINT"
echo "Access Key: $S3_ACCESS_KEY"
echo "Secret Key: $S3_SECRET_KEY"
```

**Test with AWS CLI**:
```bash
# Install AWS CLI if not present
pip3 install awscli

# Configure AWS CLI
aws configure set aws_access_key_id $S3_ACCESS_KEY
aws configure set aws_secret_access_key $S3_SECRET_KEY
aws configure set region us-east-1

# Create bucket
aws s3 mb s3://test-bucket --endpoint-url https://$S3_ENDPOINT

# Upload file
echo "Hello Ceph S3" > test.txt
aws s3 cp test.txt s3://test-bucket/ --endpoint-url https://$S3_ENDPOINT

# List buckets
aws s3 ls --endpoint-url https://$S3_ENDPOINT

# List objects
aws s3 ls s3://test-bucket/ --endpoint-url https://$S3_ENDPOINT

# Download file
aws s3 cp s3://test-bucket/test.txt test-download.txt --endpoint-url https://$S3_ENDPOINT
cat test-download.txt
```

### Set Default Storage Class (Optional)

```bash
# Make RBD the default storage class
oc patch storageclass ocs-storagecluster-ceph-rbd -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

# Remove default from another storage class if needed
oc patch storageclass gp2-csi -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'
```

## Cleanup and Removal

### Uninstall Ceph Cluster (Preserves data)

To remove Ceph but keep data on EBS volumes:

```bash
# Delete StorageCluster
oc delete storagecluster ocs-storagecluster -n openshift-storage

# Wait for cleanup
oc get pods -n openshift-storage -w
```

### Complete Removal (DESTROYS DATA!)

To completely remove Ceph and all data:

```bash
# 1. Delete all PVCs using Ceph storage
oc get pvc --all-namespaces -o json | jq -r '.items[] | select(.spec.storageClassName | contains("ceph") or contains("ocs")) | "\(.metadata.namespace)/\(.metadata.name)"' | xargs -I {} sh -c 'NS=$(echo {} | cut -d/ -f1); PVC=$(echo {} | cut -d/ -f2); oc delete pvc $PVC -n $NS'

# 2. Delete StorageCluster
oc delete storagecluster ocs-storagecluster -n openshift-storage

# 3. Wait for all Ceph pods to terminate
oc get pods -n openshift-storage -w

# 4. Delete ODF operator
oc delete subscription odf-operator -n openshift-storage
oc delete csv -n openshift-storage $(oc get csv -n openshift-storage -o name | grep odf)

# 5. Delete namespace (wait for graceful deletion)
oc delete namespace openshift-storage

# 6. Delete Local Storage Operator
oc delete localvolume --all -n openshift-local-storage
oc delete subscription local-storage-operator -n openshift-local-storage
oc delete csv -n openshift-local-storage $(oc get csv -n openshift-local-storage -o name | grep local-storage)
oc delete namespace openshift-local-storage

# 7. Remove node labels
for node in $(oc get nodes -o name); do
  oc label $node cluster.ocs.openshift.io/openshift-storage-
done

# 8. Delete EBS volumes (from AWS)
aws ec2 describe-volumes \
  --region eu-north-1 \
  --filters "Name=tag:Name,Values=ceph-ebs-*" \
  --query 'Volumes[*].VolumeId' \
  --output text | xargs -I {} aws ec2 delete-volume --volume-id {} --region eu-north-1
```

### Clean Worker Node Disks (If needed)

If you want to completely wipe the disks on worker nodes:

```bash
# For each worker node
oc debug node/<node-name>

# Inside debug pod
chroot /host

# WARNING: This destroys all data!
wipefs -a /dev/sde
dd if=/dev/zero of=/dev/sde bs=1M count=100

exit
exit
```

## Additional Resources

### Official Documentation
- [OpenShift Data Foundation Documentation](https://access.redhat.com/documentation/en-us/red_hat_openshift_data_foundation/)
- [Rook Ceph Quickstart Guide](https://rook.io/docs/rook/latest/Getting-Started/quickstart/)
- [Rook Ceph Documentation](https://rook.io/docs/rook/latest/)
- [Ceph Documentation](https://docs.ceph.com/en/latest/)

### Useful Links
- [ODF Knowledge Base](https://access.redhat.com/articles/5692201)
- [Rook GitHub Repository](https://github.com/rook/rook)
- [Rook Troubleshooting Guide](https://rook.io/docs/rook/latest/Troubleshooting/ceph-common-issues/)
- [Ceph Community](https://ceph.io/en/community/)

### Support
- **Red Hat Support**: [https://access.redhat.com/support](https://access.redhat.com/support)
- **Rook Slack**: [https://rook.io/slack](https://rook.io/slack)
- **Ceph Mailing Lists**: [https://ceph.io/en/community/mailing-lists/](https://ceph.io/en/community/mailing-lists/)

---

**Document Version**: 1.0  
**Last Updated**: October 27, 2025  
**Maintained By**: DevOps Team

