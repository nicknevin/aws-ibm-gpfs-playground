# Ceph OSD Fix - Device Path Issue

## Problem

When running `./scripts/install-rook-ceph.sh`, OSDs fail to start with error:

```
I | cephosd: device "nvme1n1" is available.
I | cephosd: skipping device "nvme1n1" that does not match the device filter/list
    ([{/dev/disk/by-id/nvme-Amazon_Elastic_Block_Store_vol* 1  0   false false}])
W | cephosd: skipping OSD configuration as no devices matched the storage settings
```

**Result**: `osd: 0 osds: 0 up, 0 in` - No OSDs running!

## Root Cause

The install script was incorrectly trying to use raw device paths with a glob pattern that doesn't match the actual device names:

- **Script expected**: `/dev/disk/by-id/nvme-Amazon_Elastic_Block_Store_vol*`
- **Actual devices**: `/dev/nvme1n1`, `/dev/nvme2n1`
- **Reality**: LSO (Local Storage Operator) already claimed the disks and created PVs

## Solution Applied

### 1. Updated `install-rook-ceph.sh`

**Changed from**: Optional LSO detection with fallback to raw devices
**Changed to**: **Mandatory LSO requirement** with proper error messages

```bash
# Old behavior:
if [ "$LSO_PV_COUNT" -ge 3 ]; then
    use PVCs
else
    use raw devices with glob pattern  # ❌ This doesn't work!
fi

# New behavior:
if [ "$LSO_PV_COUNT" -ge 3 ]; then
    use PVCs  # ✅ Always works!
else
    print error and exit  # ❌ Stop immediately, don't continue
fi
```

### 2. Key Changes

1. **Mandatory LSO Check**: Script now requires LSO PVs to exist before proceeding
2. **Wait Logic**: Waits 30 seconds if LSO is installed but PVs aren't ready yet
3. **Clear Error Messages**: Tells user exactly what to do if LSO isn't found
4. **PVC-Only Mode**: Removed broken raw device mode entirely
5. **Updated Documentation**: Added troubleshooting guide for this specific issue

### 3. Updated Files

- ✅ `scripts/install-rook-ceph.sh` - Mandatory LSO requirement
- ✅ `docs/CEPH-QUICK-START.md` - Added prerequisite warning and troubleshooting
- ✅ `docs/CEPH-OSD-FIX.md` - This document

## How to Use

### Fresh Installation (Correct Way)

```bash
# 1. REQUIRED: Install LSO and prepare disks FIRST
cd /home/nlevanon/workspace/DR/aws-ibm-gpfs-playground
ansible-playbook -i hosts -e @dr-eun1b-cluster1.yaml playbooks/dr-ceph.yml --tags lso1,ceph_disks

# 2. Verify LSO PVs exist (IMPORTANT!)
export KUBECONFIG=~/dr-playground/dr-eun1b-1/ocp_install_files/auth/kubeconfig
oc get pv | grep lso-sc

# Expected output: 3 PVs with STATUS: Available or Bound
# local-pv-xxxxx   160Gi   RWO   Delete   Available   lso-sc

# 3. Now run Rook-Ceph installation
./scripts/install-rook-ceph.sh dr-eun1b-1
```

### If You Already Have a Broken Installation

**Option A: Use the fix script**
```bash
cd /home/nlevanon/workspace/DR/aws-ibm-gpfs-playground
./scripts/fix-rook-ceph-storage.sh dr-eun1b-1
```

**Option B: Clean reinstall**
```bash
# 1. Delete the broken cluster
oc delete cephcluster rook-ceph -n rook-ceph
oc delete cephblockpool,cephfilesystem --all -n rook-ceph

# 2. Ensure LSO is installed
ansible-playbook -i hosts -e @dr-eun1b-cluster1.yaml playbooks/dr-ceph.yml --tags lso1,ceph_disks

# 3. Verify PVs
oc get pv | grep lso-sc

# 4. Reinstall
./scripts/install-rook-ceph.sh dr-eun1b-1
```

## Verification

After installation, verify OSDs are running:

```bash
export KUBECONFIG=~/dr-playground/dr-eun1b-1/ocp_install_files/auth/kubeconfig

# Should show 3 running OSD pods
oc get pods -n rook-ceph | grep "rook-ceph-osd-[0-9]"

# Should show: osd: 3 osds: 3 up, 3 in
oc rsh -n rook-ceph deployment/rook-ceph-tools ceph -s

# Expected output:
#   cluster:
#     health: HEALTH_OK or HEALTH_WARN (acceptable)
#   services:
#     mon: 3 daemons, quorum a,b,c
#     mgr: a(active), standbys: b
#     osd: 3 osds: 3 up, 3 in  ✅
```

## Why This Matters

### Before Fix:
- ❌ Silent failure - script completed but OSDs never started
- ❌ Confusing error messages in OSD prepare logs
- ❌ Required manual intervention and fix script
- ❌ Wasted 30+ minutes before realizing it failed

### After Fix:
- ✅ Fails fast with clear error message if LSO missing
- ✅ Tells user exactly what command to run
- ✅ Uses correct storage configuration from the start
- ✅ No need for fix script in normal workflow
- ✅ Saves time and reduces confusion

## Technical Details

### Storage Configuration Comparison

**Old (Broken) - Raw Devices:**
```yaml
storage:
  useAllNodes: false
  useAllDevices: false
  nodes:
    - name: ip-10-0-13-48.eu-north-1.compute.internal
      devices:
        - name: "/dev/disk/by-id/nvme-Amazon_Elastic_Block_Store_vol*"
```
❌ **Problem**: Glob pattern doesn't work, devices skipped

**New (Working) - PVC-based:**
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
            storageClassName: lso-sc
            volumeMode: Block
            accessModes:
              - ReadWriteOnce
```
✅ **Works**: Uses LSO PVCs, Rook creates PVCs, LSO binds them to local disks

## Related Issues

- **Issue**: `device "nvme1n1" does not match device filter`
  - **Cause**: Glob pattern mismatch
  - **Fix**: Use LSO PVCs instead of raw devices

- **Issue**: `OSD count 0 < osd_pool_default_size 3`
  - **Cause**: No OSDs started
  - **Fix**: Reconfigure storage with fix script or reinstall with LSO

- **Issue**: `PG_AVAILABILITY: Reduced data availability: 3 pgs inactive`
  - **Cause**: No OSDs to store data
  - **Fix**: Same as above

## Prevention

To prevent this issue in the future:

1. **Always run LSO setup first**: Don't skip step 1 of the installation
2. **Verify PVs before Rook**: Check `oc get pv | grep lso-sc` shows 3 PVs
3. **Use updated install script**: The fixed version will catch the issue early
4. **Check the docs**: Follow the exact order in CEPH-QUICK-START.md

## Questions?

See:
- [CEPH-QUICK-START.md](CEPH-QUICK-START.md) - Quick start guide
- [CEPH-ROOK-INSTALLATION.md](CEPH-ROOK-INSTALLATION.md) - Detailed installation
- [ROOK-STORAGE-FIX.md](ROOK-STORAGE-FIX.md) - Fix existing installations

---

**Fixed**: October 28, 2025  
**Issue**: OSD device path mismatch  
**Status**: Resolved in updated install script

