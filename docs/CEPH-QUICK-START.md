# Ceph Storage - Quick Start Guide

This is a quick reference for installing Ceph storage on your OpenShift cluster. For detailed documentation, see [CEPH-ROOK-INSTALLATION.md](CEPH-ROOK-INSTALLATION.md).

## TL;DR - Just Install It

### Option 1: Upstream Rook-Ceph (Recommended - No License Required)

```bash
# 1. Prepare disks and install Local Storage Operator
cd /home/nlevanon/workspace/DR/aws-ibm-gpfs-playground
ansible-playbook -i hosts -e @dr-eun1b-cluster1.yaml playbooks/dr-ceph.yml --tags lso1,ceph_disks

# 2. Run the automated installation script
./scripts/install-rook-ceph.sh dr-eun1b-1

# Wait 30-50 minutes for installation to complete
```

### Option 2: OpenShift Data Foundation (Requires Red Hat Subscription)

```bash
# One command does everything
ansible-playbook -i hosts -e @dr-eun1b-cluster1.yaml playbooks/dr-ceph.yml

# Wait 30-60 minutes for installation to complete
```

## Quick Verification

### Check if Ceph is Running

```bash
# Set KUBECONFIG
export KUBECONFIG=~/dr-playground/dr-eun1b-1/ocp_install_files/auth/kubeconfig

# Check pods (Upstream Rook)
oc get pods -n rook-ceph

# OR check pods (ODF)
oc get pods -n openshift-storage

# Check storage classes
oc get sc | grep -E "rook|ceph|ocs"
```

### Check Ceph Health

**For Upstream Rook:**
```bash
oc rsh -n rook-ceph deployment/rook-ceph-tools ceph status
```

**For ODF:**
```bash
oc rsh -n openshift-storage $(oc get pod -n openshift-storage -l app=rook-ceph-tools -o name) ceph status
```

**Expected output:**
```
cluster:
  id:     xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
  health: HEALTH_OK
 
services:
  mon: 3 daemons, quorum a,b,c
  mgr: a(active), standbys: b
  osd: 3 osds: 3 up, 3 in
```

## Storage Classes Created

### Upstream Rook-Ceph

- `rook-ceph-block` - Block storage (RWO) for databases, VMs
- `rook-cephfs` - File storage (RWX) for shared files
- `rook-ceph-bucket` - Object storage (S3-compatible)

### OpenShift Data Foundation

- `ocs-storagecluster-ceph-rbd` - Block storage (RWO)
- `ocs-storagecluster-cephfs` - File storage (RWX)
- `ocs-storagecluster-ceph-rgw` - Object storage (S3)

## Quick Test - Create a PVC

### Test Block Storage

```bash
# Create test namespace
oc new-project ceph-test

# Create PVC (adjust storage class name based on your installation)
cat <<EOF | oc apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-pvc
  namespace: ceph-test
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: rook-ceph-block  # OR ocs-storagecluster-ceph-rbd for ODF
  resources:
    requests:
      storage: 5Gi
EOF

# Check PVC status
oc get pvc -n ceph-test

# Should show STATUS: Bound
```

### Test File Storage (RWX)

```bash
# Create RWX PVC
cat <<EOF | oc apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-shared-pvc
  namespace: ceph-test
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: rook-cephfs  # OR ocs-storagecluster-cephfs for ODF
  resources:
    requests:
      storage: 5Gi
EOF

# Check PVC
oc get pvc -n ceph-test
```

## Access Ceph Dashboard

### Upstream Rook

```bash
# Get dashboard URL
echo "https://$(oc get route ceph-dashboard -n rook-ceph -o jsonpath='{.spec.host}')"

# Get credentials
echo "Username: admin"
echo "Password: $(oc get secret rook-ceph-dashboard-password -n rook-ceph -o jsonpath='{.data.password}' | base64 -d)"
```

### ODF

```bash
# Access through OpenShift Console
oc whoami --show-console

# Navigate to: Storage → Data Foundation → Storage Systems
```

## Troubleshooting Quick Reference

### Pods Not Running

```bash
# Check pod status
oc get pods -n rook-ceph  # OR -n openshift-storage for ODF

# Describe problematic pod
oc describe pod <pod-name> -n rook-ceph

# Check logs
oc logs <pod-name> -n rook-ceph
```

### Ceph Not Healthy

```bash
# Get detailed health info
oc rsh -n rook-ceph deployment/rook-ceph-tools ceph health detail

# Check OSD status
oc rsh -n rook-ceph deployment/rook-ceph-tools ceph osd status

# Check monitor status
oc rsh -n rook-ceph deployment/rook-ceph-tools ceph mon stat
```

### PVC Stuck in Pending

```bash
# Check storage class exists
oc get sc

# Check events
oc get events -n <namespace> --sort-by='.lastTimestamp'

# Check if Ceph cluster is ready
oc get cephcluster -n rook-ceph  # OR storagecluster -n openshift-storage for ODF
```

## Common Issues

### Issue: "No storage class found"

**Solution:**
```bash
# Wait a few minutes, storage classes are created after cluster is ready
# Force reconciliation (Upstream Rook):
oc delete pod -l app=rook-ceph-operator -n rook-ceph
```

### Issue: "OSDs not starting"

**Solution:**
```bash
# Check if disks are available
oc debug node/<node-name>
chroot /host
lsblk

# Verify /dev/sde is present and not in use
```

### Issue: "Monitors not forming quorum"

**Solution:**
```bash
# Check monitor pods
oc get pods -n rook-ceph -l app=rook-ceph-mon

# Check monitor logs
oc logs -n rook-ceph -l app=rook-ceph-mon --tail=100
```

## Key Differences: Upstream Rook vs ODF

| Feature | Upstream Rook | ODF |
|---------|---------------|-----|
| **Namespace** | `rook-ceph` | `openshift-storage` |
| **Cost** | Free | Requires Red Hat subscription |
| **Support** | Community | Red Hat commercial |
| **NooBaa** | Optional | Included |
| **Dashboard** | External route | Integrated in console |
| **Storage Class Prefix** | `rook-*` | `ocs-storagecluster-*` |

## Quick Commands Cheat Sheet

```bash
# Set KUBECONFIG
export KUBECONFIG=~/dr-playground/dr-eun1b-1/ocp_install_files/auth/kubeconfig

# Check Ceph status
oc rsh -n rook-ceph deployment/rook-ceph-tools ceph -s

# List storage classes
oc get sc

# Check all Ceph pods
oc get pods -n rook-ceph -o wide

# Check OSD usage
oc rsh -n rook-ceph deployment/rook-ceph-tools ceph osd df

# Check pool usage
oc rsh -n rook-ceph deployment/rook-ceph-tools ceph df

# List PVCs using Ceph
oc get pvc --all-namespaces -o wide | grep -E "rook|ceph|ocs"

# Dashboard URL
oc get route -n rook-ceph  # OR -n openshift-storage for ODF

# Operator logs
oc logs -n rook-ceph -l app=rook-ceph-operator --tail=50 -f
```

## Need More Help?

- **Full Documentation**: [CEPH-ROOK-INSTALLATION.md](CEPH-ROOK-INSTALLATION.md)
- **Rook Documentation**: https://rook.io/docs/rook/latest/
- **Ceph Documentation**: https://docs.ceph.com/en/latest/
- **Rook Troubleshooting**: https://rook.io/docs/rook/latest/Troubleshooting/ceph-common-issues/

---

**Last Updated**: October 27, 2025

