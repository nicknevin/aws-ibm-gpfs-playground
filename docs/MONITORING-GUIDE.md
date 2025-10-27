# Storage Monitoring Guide

Complete guide for monitoring Local Storage Operator (LSO) and Rook-Ceph installations.

## Table of Contents

1. [Before Rook-Ceph Installation](#before-rook-ceph-installation)
2. [After Rook-Ceph Installation](#after-rook-ceph-installation)
3. [Monitoring Tools](#monitoring-tools)
4. [Quick Commands Reference](#quick-commands-reference)

---

## Before Rook-Ceph Installation

After running `ansible-playbook -i hosts -e @dr-eun1b-cluster1.yaml playbooks/dr-ceph.yml --tags lso1,ceph_disks`, you have:

### What's Installed

✅ **Local Storage Operator (LSO)** - Manages local disks  
✅ **EBS Volumes** - 3x 160GB io2 volumes attached to nodes  
✅ **LocalVolume CR** - Configured to discover disks  
✅ **Persistent Volumes** - 3 PVs created by LSO  
✅ **Storage Class** - `lso-sc` for local block storage  

### Monitoring with `oc` CLI

```bash
# Set KUBECONFIG
export KUBECONFIG=~/dr-playground/dr-eun1b-1/ocp_install_files/auth/kubeconfig
OC=~/dr-playground/dr-eun1b-1/4.19.15/oc

# Check LSO operator
$OC get pods -n openshift-local-storage

# Expected output:
# NAME                                    READY   STATUS    RESTARTS   AGE
# diskmaker-manager-xxxxx                 2/2     Running   0          10m
# diskmaker-manager-xxxxx                 2/2     Running   0          10m
# diskmaker-manager-xxxxx                 2/2     Running   0          10m
# local-storage-operator-xxxxxxxx-xxxxx   1/1     Running   0          20m

# Check Persistent Volumes
$OC get pv

# Expected output:
# NAME                CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS      CLAIM   STORAGECLASS
# local-pv-3c21ab10   160Gi      RWO            Delete           Available           lso-sc
# local-pv-7afd9b19   160Gi      RWO            Delete           Available           lso-sc
# local-pv-811e1c9    160Gi      RWO            Delete           Available           lso-sc

# Check LocalVolume configuration
$OC get localvolume -n openshift-local-storage

# Check node labels
$OC get nodes -L cluster.ocs.openshift.io/openshift-storage

# Check storage class
$OC get sc lso-sc
```

### Monitoring with k9s

```bash
# Install k9s (if not installed)
curl -sS https://webinstall.dev/k9s | bash

# Launch k9s
export KUBECONFIG=~/dr-playground/dr-eun1b-1/ocp_install_files/auth/kubeconfig
k9s

# Navigation in k9s:
# :namespace openshift-local-storage  → Switch to LSO namespace
# :pods                                → View all pods
# :pv                                  → View persistent volumes
# :nodes                               → View nodes
# Press '?' for help
# Press 'Ctrl+C' to exit
```

**k9s Quick Tips:**
- Type `:` to enter command mode
- Type `/` to search/filter
- Press `Enter` on a resource to see details
- Press `l` to view logs (when on a pod)
- Press `d` to describe resource
- Press `Ctrl+D` to delete (be careful!)

### Monitoring with OpenShift Web Console

```bash
# Get console URL
export KUBECONFIG=~/dr-playground/dr-eun1b-1/ocp_install_files/auth/kubeconfig
OC=~/dr-playground/dr-eun1b-1/4.19.15/oc
echo "Console URL: $($OC whoami --show-console)"

# Get kubeadmin password
echo "Password: $(cat ~/dr-playground/dr-eun1b-1/ocp_install_files/auth/kubeadmin-password)"
```

**In the Console:**
1. Navigate to **Workloads** → **Pods**
2. Filter by namespace: `openshift-local-storage`
3. Check pod status (all should be Running)
4. Navigate to **Storage** → **PersistentVolumes**
5. You should see 3 volumes with status "Available"

### Verify EBS Volumes in AWS

```bash
# Check EBS volumes via AWS CLI
aws ec2 describe-volumes \
  --region eu-north-1 \
  --filters "Name=tag:Name,Values=ceph-ebs-*" \
  --query 'Volumes[*].[VolumeId,State,Attachments[0].InstanceId,Size,VolumeType]' \
  --output table
```

**Expected Output:**
```
---------------------------------------------------------
|                   DescribeVolumes                     |
+------------------+----------+---------------+----+----+
|  vol-xxxxxxxxx   | in-use   | i-xxxxxxxxx   | 160| io2|
|  vol-xxxxxxxxx   | in-use   | i-xxxxxxxxx   | 160| io2|
|  vol-xxxxxxxxx   | in-use   | i-xxxxxxxxx   | 160| io2|
+------------------+----------+---------------+----+----+
```

### Check Physical Disks on Nodes

```bash
export KUBECONFIG=~/dr-playground/dr-eun1b-1/ocp_install_files/auth/kubeconfig
OC=~/dr-playground/dr-eun1b-1/4.19.15/oc

# Pick a node
NODE=$($OC get nodes -o name | head -1)

# Debug into the node
$OC debug $NODE

# Inside the debug pod:
chroot /host
lsblk
# You should see /dev/nvme1n1 (or similar) - this is your EBS volume

# Check disk by-id
ls -la /dev/disk/by-id/ | grep nvme-Amazon

# Exit the debug pod
exit
exit
```

---

## After Rook-Ceph Installation

After running `./scripts/install-rook-ceph.sh dr-eun1b-1`, you will have additional resources:

### What's Installed

✅ **Rook Operator** - Manages Ceph cluster  
✅ **Ceph Cluster** - Storage cluster with MON, OSD, MGR components  
✅ **Ceph OSDs** - 3 Object Storage Daemons (one per node)  
✅ **Ceph Monitors** - 3 monitors for cluster coordination  
✅ **Storage Classes** - RBD (block), CephFS (file), RGW (object)  
✅ **Ceph Dashboard** - Web UI for monitoring  
✅ **Ceph Toolbox** - CLI tools for management  

### Monitoring with `oc` CLI

```bash
export KUBECONFIG=~/dr-playground/dr-eun1b-1/ocp_install_files/auth/kubeconfig
OC=~/dr-playground/dr-eun1b-1/4.19.15/oc

# Check Rook-Ceph namespace
$OC get pods -n rook-ceph

# Expected pods (after full installation):
# - rook-ceph-operator (1 pod)
# - rook-ceph-mon-a, -b, -c (3 monitor pods)
# - rook-ceph-osd-0, -1, -2 (3 OSD pods)
# - rook-ceph-mgr-a (1 manager pod)
# - rook-ceph-mds (2 metadata server pods for CephFS)
# - csi-cephfsplugin-* (CSI driver pods)
# - csi-rbdplugin-* (CSI driver pods)
# - rook-ceph-tools (toolbox for management)

# Check Ceph cluster status
$OC get cephcluster -n rook-ceph

# Check storage classes
$OC get sc | grep rook
# Expected:
# rook-ceph-block    - Block storage (RWO)
# rook-cephfs        - File storage (RWX)
# rook-ceph-bucket   - Object storage (OBC)

# Check Ceph health
$OC rsh -n rook-ceph deployment/rook-ceph-tools ceph status

# Expected output:
#   cluster:
#     id:     xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
#     health: HEALTH_OK
#   services:
#     mon: 3 daemons, quorum a,b,c
#     mgr: a(active)
#     osd: 3 osds: 3 up, 3 in

# Check OSD status
$OC rsh -n rook-ceph deployment/rook-ceph-tools ceph osd status

# Check storage usage
$OC rsh -n rook-ceph deployment/rook-ceph-tools ceph df
```

### Monitoring with Ceph Dashboard

```bash
export KUBECONFIG=~/dr-playground/dr-eun1b-1/ocp_install_files/auth/kubeconfig
OC=~/dr-playground/dr-eun1b-1/4.19.15/oc

# Get dashboard URL
echo "Dashboard URL: https://$($OC get route ceph-dashboard -n rook-ceph -o jsonpath='{.spec.host}')"

# Get credentials
echo "Username: admin"
echo "Password: $($OC get secret rook-ceph-dashboard-password -n rook-ceph -o jsonpath='{.data.password}' | base64 -d)"
```

**Dashboard Features:**
- **Cluster** → Overall health and status
- **Hosts** → View nodes and OSDs
- **Monitors** → Monitor daemon status
- **OSDs** → Detailed OSD information
- **Pools** → Storage pool statistics
- **Block** → RBD images and performance
- **Filesystem** → CephFS status
- **Object Gateway** → S3/Swift gateway (if enabled)

### Monitoring with k9s

```bash
export KUBECONFIG=~/dr-playground/dr-eun1b-1/ocp_install_files/auth/kubeconfig
k9s

# Useful k9s commands for Ceph:
# :namespace rook-ceph     → Switch to Rook namespace
# :pods                    → View all Ceph pods
# :cephcluster             → View Ceph cluster CR
# :cephblockpool           → View RBD pools
# :cephfilesystem          → View CephFS
```

### Monitoring with OpenShift Console

1. Navigate to **Storage** → **PersistentVolumes**
2. You should see your PVs now in "Bound" state (claimed by Ceph OSDs)
3. Navigate to **Workloads** → **Pods** → Filter by `rook-ceph` namespace
4. Check all pods are in "Running" state

---

## Monitoring Tools

### 1. Command-Line Monitoring Script

Save this script to easily monitor your storage:

```bash
#!/bin/bash
# Save as: ~/bin/monitor-storage.sh

export KUBECONFIG=~/dr-playground/dr-eun1b-1/ocp_install_files/auth/kubeconfig
OC=~/dr-playground/dr-eun1b-1/4.19.15/oc

echo "════════════════════════════════════════════════════════════"
echo "  Storage Monitoring Dashboard"
echo "════════════════════════════════════════════════════════════"

echo -e "\n📦 LSO Status:"
$OC get pods -n openshift-local-storage --no-headers | wc -l | xargs -I {} echo "  Pods: {}"
$OC get pv --no-headers 2>/dev/null | wc -l | xargs -I {} echo "  PVs: {}"

if $OC get namespace rook-ceph &>/dev/null; then
  echo -e "\n🐙 Rook-Ceph Status:"
  $OC get pods -n rook-ceph --no-headers 2>/dev/null | wc -l | xargs -I {} echo "  Pods: {}"
  
  if $OC get deployment rook-ceph-tools -n rook-ceph &>/dev/null; then
    echo -e "\n💚 Ceph Health:"
    $OC rsh -n rook-ceph deployment/rook-ceph-tools ceph status 2>/dev/null || echo "  Toolbox not ready"
  fi
else
  echo -e "\n🐙 Rook-Ceph: Not installed yet"
fi

echo -e "\n📊 Storage Classes:"
$OC get sc --no-headers | grep -E "lso|rook|ceph" | awk '{print "  "$1}'

echo ""
```

### 2. Watch Commands

```bash
# Watch LSO pods
watch -n 5 'oc get pods -n openshift-local-storage'

# Watch Rook-Ceph pods
watch -n 5 'oc get pods -n rook-ceph'

# Watch Ceph health
watch -n 10 'oc rsh -n rook-ceph deployment/rook-ceph-tools ceph -s'

# Watch PVs
watch -n 5 'oc get pv'
```

### 3. Prometheus Queries

If you have Prometheus access:

```promql
# Ceph cluster health
ceph_health_status

# OSD up/down
ceph_osd_up

# Total cluster capacity
ceph_cluster_total_bytes

# Used capacity
ceph_cluster_total_used_bytes

# Pool usage
ceph_pool_stored
```

### 4. Log Monitoring

```bash
export KUBECONFIG=~/dr-playground/dr-eun1b-1/ocp_install_files/auth/kubeconfig
OC=~/dr-playground/dr-eun1b-1/4.19.15/oc

# LSO operator logs
$OC logs -n openshift-local-storage -l name=local-storage-operator --tail=50 -f

# Rook operator logs
$OC logs -n rook-ceph -l app=rook-ceph-operator --tail=50 -f

# Specific Ceph component logs
$OC logs -n rook-ceph -l app=rook-ceph-mon --tail=50
$OC logs -n rook-ceph -l app=rook-ceph-osd --tail=50
$OC logs -n rook-ceph -l app=rook-ceph-mgr --tail=50
```

---

## Quick Commands Reference

### Essential Commands

```bash
# Set environment (run this first in each terminal)
export KUBECONFIG=~/dr-playground/dr-eun1b-1/ocp_install_files/auth/kubeconfig
export OC=~/dr-playground/dr-eun1b-1/4.19.15/oc

# Quick health check
$OC get pods -n openshift-local-storage
$OC get pods -n rook-ceph 2>/dev/null || echo "Rook not installed"
$OC get pv

# Ceph status (if Rook installed)
$OC rsh -n rook-ceph deployment/rook-ceph-tools ceph -s

# Storage classes
$OC get sc

# Test creating a PVC (after Rook installed)
cat <<EOF | $OC apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-pvc
  namespace: default
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: rook-ceph-block
  resources:
    requests:
      storage: 1Gi
EOF

# Check PVC status
$OC get pvc test-pvc

# Delete test PVC
$OC delete pvc test-pvc
```

### Troubleshooting Commands

```bash
# Check events
$OC get events -n openshift-local-storage --sort-by='.lastTimestamp'
$OC get events -n rook-ceph --sort-by='.lastTimestamp'

# Describe problematic resources
$OC describe pod <pod-name> -n rook-ceph
$OC describe pv <pv-name>

# Check node resources
$OC adm top nodes
$OC adm top pods -n rook-ceph

# Get detailed pod logs
$OC logs <pod-name> -n rook-ceph --all-containers=true
```

---

## Related Documentation

- **Installation Guide**: [CEPH-ROOK-INSTALLATION.md](CEPH-ROOK-INSTALLATION.md)
- **Quick Start**: [CEPH-QUICK-START.md](CEPH-QUICK-START.md)
- **Main DR Guide**: [README-DR-EUROPE.md](../README-DR-EUROPE.md)

---

**Last Updated**: October 27, 2025  
**Version**: 1.0

