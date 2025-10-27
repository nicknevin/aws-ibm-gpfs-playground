# Rook-Ceph Storage Configuration Fix

## Issue Summary

The initial Rook-Ceph installation script was configured to use raw device paths (`/dev/sde`) which doesn't work correctly when:
1. Local Storage Operator (LSO) is already managing the disks
2. EBS volumes show up as different device names (nvme1n1, nvme2n1, etc.)
3. LSO has already created PVs from these volumes

## What Was Wrong

### Original Configuration
```yaml
storage:
  useAllNodes: false
  useAllDevices: false
  nodes:
    - name: node1
      devices:
        - name: "/dev/sde"  # ❌ This device doesn't exist!
```

**Problems:**
- `/dev/sde` doesn't exist - EBS volumes appear as nvme devices
- LSO already created PVs from these devices
- Rook tried to access raw devices but couldn't find them
- Result: **0 OSDs created, no storage available**

### Correct Configuration
```yaml
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
            storageClassName: lso-sc  # ✅ Use PVs from LSO!
            volumeMode: Block
            accessModes:
              - ReadWriteOnce
```

**Benefits:**
- ✅ Uses PVs created by Local Storage Operator
- ✅ Proper integration between LSO and Rook
- ✅ OSDs get created successfully
- ✅ Storage becomes available

## What Was Fixed

### 1. Installation Script (`scripts/install-rook-ceph.sh`)

**Changes:**
- Added automatic detection of LSO PVs
- Uses `storageClassDeviceSets` when LSO PVs are available
- Falls back to raw devices only if no LSO PVs found
- Fixed toolbox deployment with proper shell script syntax

**Code Added:**
```bash
print_info "Checking if LSO (Local Storage Operator) PVs are available..."
LSO_PV_COUNT=$(oc get pv --no-headers 2>/dev/null | grep -c "lso-sc" || echo "0")

if [ "$LSO_PV_COUNT" -ge 3 ]; then
    print_success "Found ${LSO_PV_COUNT} LSO PVs - using storageClassDeviceSets"
    STORAGE_MODE="pvc"
else
    print_warning "No LSO PVs found - using raw devices"
    STORAGE_MODE="devices"
fi
```

### 2. Toolbox Deployment

**Fixed:**
- Removed dependency on non-existent `/usr/local/bin/toolbox.sh`
- Created proper inline shell script to configure Ceph
- Fixed environment variable expansion
- Added proper keyring and config file creation

### 3. New Fix Script (`scripts/fix-rook-ceph-storage.sh`)

Created a script to fix existing broken installations without full reinstall.

## How to Fix Your Current Installation

You have two options:

### Option A: Run the Fix Script (Recommended)

This will fix your current installation without losing monitors or data:

```bash
cd /home/nlevanon/workspace/DR/aws-ibm-gpfs-playground

# Run the fix script
./scripts/fix-rook-ceph-storage.sh dr-eun1b-1
```

**What it does:**
1. Backs up current configuration
2. Deletes CephCluster CR (preserves monitors)
3. Recreates with correct PVC-based storage
4. Waits for OSDs to be created
5. Fixes toolbox deployment

**Time:** ~10-15 minutes

### Option B: Clean Reinstall

If you prefer to start fresh:

```bash
cd /home/nlevanon/workspace/DR/aws-ibm-gpfs-playground

# 1. Delete Rook-Ceph
oc delete cephcluster rook-ceph -n rook-ceph
oc delete namespace rook-ceph

# 2. Wait a few minutes for cleanup

# 3. Reinstall with fixed script
./scripts/install-rook-ceph.sh dr-eun1b-1
```

**Time:** ~30-50 minutes

## Verification After Fix

After running the fix, verify everything is working:

```bash
export KUBECONFIG=~/dr-playground/dr-eun1b-1/ocp_install_files/auth/kubeconfig

# Check Ceph cluster
oc get cephcluster -n rook-ceph
# Should show: Phase: Ready, HEALTH: HEALTH_OK or HEALTH_WARN

# Check OSDs (should show 3 pods)
oc get pods -n rook-ceph | grep osd
# Expected:
# rook-ceph-osd-0-xxxxx   2/2     Running
# rook-ceph-osd-1-xxxxx   2/2     Running
# rook-ceph-osd-2-xxxxx   2/2     Running

# Check Ceph status
oc rsh -n rook-ceph deployment/rook-ceph-tools ceph -s
# Should show: osd: 3 osds: 3 up, 3 in

# Check PVCs created by Rook
oc get pvc -n rook-ceph
# Should show 3 PVCs in Bound state
```

**Expected Ceph Status:**
```
cluster:
  id:     xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
  health: HEALTH_OK (or HEALTH_WARN initially)

services:
  mon: 3 daemons, quorum a,b,c
  mgr: a(active), standbys: b
  mds: 1/1 daemons up, 1 standby
  osd: 3 osds: 3 up, 3 in          ✅ THIS IS KEY!

data:
  pools:   3 pools, 65 pgs
  usage:   XX GiB used, ~450 GiB / 480 GiB avail
```

## Dashboard Access

After the fix, the dashboard should be accessible:

```bash
export KUBECONFIG=~/dr-playground/dr-eun1b-1/ocp_install_files/auth/kubeconfig

# Get dashboard URL
echo "URL: https://$(oc get route ceph-dashboard -n rook-ceph -o jsonpath='{.spec.host}')"

# Get credentials
echo "Username: admin"
echo "Password: $(oc get secret rook-ceph-dashboard-password -n rook-ceph -o jsonpath='{.data.password}' | base64 -d)"
```

If the dashboard isn't accessible, make sure the route exists:

```bash
# Check route
oc get route ceph-dashboard -n rook-ceph

# If missing, create it
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
```

## Common Issues After Fix

### Issue: OSDs still at 0

**Check:**
```bash
oc get pvc -n rook-ceph
oc describe pvc -n rook-ceph
```

**Solution:** Wait 10-15 minutes. OSD creation takes time.

### Issue: PVCs stuck in Pending

**Check:**
```bash
oc get pv | grep lso-sc
```

**Solution:** Ensure LSO PVs are Available (not Bound). If all LSO PVs are already bound, you need to free them or create new ones.

### Issue: Toolbox errors

**Solution:** Toolbox takes 30-60 seconds to be fully ready after pod starts. Wait a minute and try again.

## Future Installations

For future cluster installations, the updated script will automatically:
1. Detect if LSO PVs exist
2. Use correct storage configuration
3. Create working toolbox
4. Result in a fully functional Ceph cluster on first try

## Related Documentation

- [CEPH-ROOK-INSTALLATION.md](CEPH-ROOK-INSTALLATION.md) - Complete installation guide
- [MONITORING-GUIDE.md](MONITORING-GUIDE.md) - How to monitor Ceph
- [CEPH-QUICK-START.md](CEPH-QUICK-START.md) - Quick reference

---

**Last Updated**: October 27, 2025  
**Version**: 1.0

