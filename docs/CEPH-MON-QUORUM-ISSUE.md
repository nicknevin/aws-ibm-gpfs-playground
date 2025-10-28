# Ceph Monitor Quorum Issue - Troubleshooting Guide

## Problem Description

### Symptoms
- Ceph dashboard is down/inaccessible
- `ceph -s` command times out with error:
  ```
  monclient(hunting): authenticate timed out after 300
  [errno 110] RADOS timed out (error connecting to the cluster)
  ```
- CephCluster stuck in "Progressing" phase
- CephCluster status message: "Configuring Ceph Mons"
- No OSD pods are running
- No PVCs created for OSDs

### Root Cause

The Ceph monitors are stuck in **"probing" state** and cannot form a quorum.

**Monitor pod logs show:**
```
mon.a@0(probing) e3 handle_auth_request failed to assign global_id
mon.a@0(probing) e3 get_health_metrics reporting 590 slow ops
```

**Rook operator logs show:**
```
op-mon: mons running: [a b c]
op-mon: mons running: [a b c]
(repeating every 20 seconds, never progressing)
```

### Why This Happens

1. **Stale monitor data** from previous installation attempts
2. **Corrupted monitor store** in `/var/lib/rook` on nodes
3. **Failed quorum bootstrap** - monitors can't agree on initial state
4. **Previous cluster not fully cleaned up** before reinstallation

### Diagnosis Commands

```bash
# Check CephCluster status
oc get cephcluster -n rook-ceph -o wide

# Check if stuck in "Progressing" phase
oc get cephcluster rook-ceph -n rook-ceph -o jsonpath='{.status.phase}'

# Check monitor logs (look for "probing" state)
oc logs -n rook-ceph $(oc get pod -n rook-ceph -l app=rook-ceph-mon,mon=a -o name) -c mon --tail=50

# Check operator logs (look for repeated "mons running" without progress)
oc logs -n rook-ceph deployment/rook-ceph-operator --tail=100

# Check for missing OSDs
oc get pods -n rook-ceph | grep osd
# (should show 3 OSD pods, but shows none)

# Check for missing PVCs
oc get pvc -n rook-ceph
# (should show set1-data-* PVCs, but shows none)
```

## Solution

### Option 1: Emergency Cleanup Script (Recommended)

Use the automated emergency cleanup script:

```bash
cd /home/nlevanon/workspace/DR/aws-ibm-gpfs-playground

# Run emergency cleanup
./scripts/emergency-ceph-cleanup.sh dr-eun1b-1

# Wait 1-2 minutes for operator to stabilize

# Reinstall Ceph cluster
./scripts/install-rook-ceph.sh dr-eun1b-1
```

The script will:
1. Remove CephBlockPool and CephFilesystem resources
2. Set cleanupPolicy to destroy data
3. Delete CephCluster with proper cleanup
4. Clean up all PVCs
5. Remove stale monitor data from `/var/lib/rook` on all nodes
6. Verify LSO PVs are available
7. Prepare for fresh installation

### Option 2: Manual Cleanup

If you prefer manual cleanup:

```bash
export KUBECONFIG=~/dr-playground/dr-eun1b-1/ocp_install_files/auth/kubeconfig

# 1. Remove dependent resources
oc delete cephblockpool replicapool -n rook-ceph --timeout=30s || true
oc delete cephfilesystem myfs -n rook-ceph --timeout=30s || true

# 2. Set cleanup policy
oc patch cephcluster rook-ceph -n rook-ceph --type merge \
  -p '{"spec":{"cleanupPolicy":{"confirmation":"yes-really-destroy-data"}}}'

# 3. Delete CephCluster
oc delete cephcluster rook-ceph -n rook-ceph --timeout=60s

# 4. If stuck, remove finalizers
oc patch cephcluster rook-ceph -n rook-ceph --type json \
  -p='[{"op": "remove", "path": "/metadata/finalizers"}]'

# 5. Clean node data (on each worker node)
for node in $(oc get nodes -l node-role.kubernetes.io/worker -o name); do
  oc debug $node -- chroot /host rm -rf /var/lib/rook/*
done

# 6. Delete PVCs
oc delete pvc --all -n rook-ceph --timeout=30s

# 7. Wait for cleanup to complete
sleep 60

# 8. Reinstall
./scripts/install-rook-ceph.sh dr-eun1b-1
```

## Prevention

To avoid this issue in the future:

1. **Always use proper cleanup** before reinstalling:
   ```bash
   ./scripts/emergency-ceph-cleanup.sh <cluster-name>
   ```

2. **Don't manually delete CephCluster** without setting cleanupPolicy first:
   ```yaml
   spec:
     cleanupPolicy:
       confirmation: "yes-really-destroy-data"
   ```

3. **Clean node data** after cluster deletion:
   ```bash
   # On each node
   rm -rf /var/lib/rook/*
   ```

4. **Wait for full cleanup** before reinstalling:
   ```bash
   # Verify no Ceph pods remain
   oc get pods -n rook-ceph
   
   # Verify no PVCs remain
   oc get pvc -n rook-ceph
   
   # Verify LSO PVs are Available
   oc get pv | grep lso-sc
   ```

## Related Documentation

- [CEPH-ROOK-INSTALLATION.md](CEPH-ROOK-INSTALLATION.md) - Full installation guide
- [CEPH-OSD-FIX.md](CEPH-OSD-FIX.md) - OSD-specific issues
- [MONITORING-GUIDE.md](MONITORING-GUIDE.md) - How to monitor Ceph health

## Technical Details

### Why Monitors Can't Form Quorum

Ceph requires a **quorum** of monitors to operate. For 3 monitors, at least 2 must agree on the cluster state.

When monitors are stuck in "probing" state:
1. Each monitor is trying to discover the cluster state
2. They can't agree because they have conflicting/stale data
3. Without quorum, they can't accept client connections
4. This blocks all cluster operations, including OSD creation

### Monitor Data Location

Monitor data is stored in:
- **On nodes:** `/var/lib/rook/rook-ceph/mon-<id>/`
- **In pods:** `/var/lib/ceph/mon/ceph-<id>/`

When stale, this data prevents proper bootstrap.

### CleanupPolicy Importance

The `cleanupPolicy` tells Rook what to do when CephCluster is deleted:

```yaml
spec:
  cleanupPolicy:
    confirmation: ""  # Default: NO cleanup
    # OR
    confirmation: "yes-really-destroy-data"  # Full cleanup
```

**Without** proper cleanup policy:
- Monitor data remains on nodes
- PVs are not released
- Next installation inherits corrupted state

**With** proper cleanup policy:
- Rook creates cleanup jobs
- Monitor and OSD data is wiped
- Clean slate for new installation

## Success Verification

After cleanup and reinstallation, verify:

```bash
# 1. CephCluster should be "Ready"
oc get cephcluster -n rook-ceph
# Should show: PHASE=Ready, HEALTH=HEALTH_OK

# 2. All pods running
oc get pods -n rook-ceph
# Should show: 3 mons, 2 mgrs, 3 osds, toolbox

# 3. Ceph status works
oc rsh -n rook-ceph deployment/rook-ceph-tools ceph -s
# Should show: HEALTH_OK, 3 mons, 3 osds up and in

# 4. Dashboard accessible
oc get route -n rook-ceph rook-ceph-dashboard
# Access the URL
```

## Known Issues

### Issue: Cleanup Script Times Out

**Symptom:** CephCluster deletion hangs for >5 minutes

**Solution:**
```bash
# Force remove finalizers
oc patch cephcluster rook-ceph -n rook-ceph --type json \
  -p='[{"op": "remove", "path": "/metadata/finalizers"}]'
```

### Issue: PVCs Won't Delete

**Symptom:** PVCs stuck in "Terminating"

**Solution:**
```bash
# Remove finalizers from each PVC
for pvc in $(oc get pvc -n rook-ceph -o name); do
  oc patch $pvc -n rook-ceph --type json \
    -p='[{"op": "remove", "path": "/metadata/finalizers"}]'
done
```

### Issue: LSO PVs Not Available After Cleanup

**Symptom:** `oc get pv | grep lso-sc` shows "Bound" instead of "Available"

**Solution:**
```bash
# Re-run LSO setup
ansible-playbook -i hosts -e @dr-eun1b-cluster1.yaml \
  playbooks/dr-ceph.yml --tags lso1,ceph_disks
```

## Support

If you encounter persistent issues:

1. **Collect diagnostics:**
   ```bash
   # Save operator logs
   oc logs -n rook-ceph deployment/rook-ceph-operator > operator.log
   
   # Save monitor logs
   oc logs -n rook-ceph $(oc get pod -n rook-ceph -l app=rook-ceph-mon,mon=a -o name) -c mon > mon-a.log
   
   # Save cluster state
   oc get cephcluster rook-ceph -n rook-ceph -o yaml > cephcluster.yaml
   ```

2. **Check Rook documentation:**
   - https://rook.io/docs/rook/latest/Troubleshooting/ceph-common-issues/

3. **Consider complete namespace reset:**
   ```bash
   # WARNING: Nuclear option - removes everything
   oc delete namespace rook-ceph
   # Wait for namespace to be fully deleted
   # Then reinstall from scratch
   ```

