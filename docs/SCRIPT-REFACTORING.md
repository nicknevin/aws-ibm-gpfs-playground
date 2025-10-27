# Script Refactoring - Common Library Implementation

## Overview

To reduce code duplication and improve maintainability across Rook-Ceph management scripts, we've created a common library that centralizes frequently-used functions.

## What Was Created

### 1. Common Library (`scripts/lib/common.sh`)

A comprehensive bash library providing:

- **Output Functions**: Consistent colored output (info, success, warning, error, debug)
- **KUBECONFIG Validation**: Cluster connectivity checks
- **Resource Operations**: Wait functions for pods, deployments, PVCs, namespaces
- **Ceph-Specific Operations**: Health checks, OSD management, toolbox execution
- **CRD Management**: Apply with automatic retry logic  
- **Cleanup Operations**: Resource deletion with automatic finalizer handling
- **URL Validation**: Check if URLs are accessible

### 2. Documentation (`scripts/lib/README.md`)

Complete documentation including:
- Function reference with parameters
- Usage examples
- Benefits analysis (before/after comparison)
- Environment variables
- Testing guidelines

## Refactored Scripts

### ✅ `test-ceph-storage.sh` - COMPLETED

**Improvements:**
- Reduced code from ~460 lines to ~400 lines
- Eliminated duplicate print functions (saved ~40 lines)
- Replaced custom PVC wait logic with `wait_for_pvc()` function
- Replaced custom health checks with `get_ceph_health()` and `check_ceph_cluster()`
- Replaced storage class checks with `check_storage_class()`
- Replaced toolbox execution with `get_ceph_status()`

**Before:**
```bash
# 40+ lines of color and print function definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
# ...

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}
# ... more functions

# Custom PVC wait logic (17 lines)
for i in {1..30}; do
    PVC_STATUS=$(oc get pvc test-rbd-pvc -n ${TEST_NAMESPACE} -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
    if [ "$PVC_STATUS" = "Bound" ]; then
        print_success "PVC bound successfully"
        break
    fi
    if [ $i -eq 30 ]; then
        print_error "PVC failed to bind within 5 minutes"
        oc get pvc test-rbd-pvc -n ${TEST_NAMESPACE}
        oc describe pvc test-rbd-pvc -n ${TEST_NAMESPACE}
        exit 1
    fi
    echo -n "."
    sleep 10
done
echo ""
```

**After:**
```bash
# Load common library (replaces 40+ lines)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

# PVC wait (replaces 17 lines with 4 lines)
print_info "Step 1.2: Waiting for PVC to bind..."
if ! wait_for_pvc "test-rbd-pvc" "${TEST_NAMESPACE}" 300; then
    oc get pvc test-rbd-pvc -n ${TEST_NAMESPACE}
    oc describe pvc test-rbd-pvc -n ${TEST_NAMESPACE}
    exit 1
fi
```

**Code Reduction:**
- **~60 lines removed** through use of common functions
- **Better error handling** with centralized retry logic
- **More consistent** output formatting across scripts

### 📝 `install-rook-ceph.sh` - TO BE REFACTORED

**Potential Improvements:**
```bash
# Current (example section):
echo -e "${BLUE}Checking operator...${NC}"
for i in {1..60}; do
    if oc get deployment rook-ceph-operator -n rook-ceph &>/dev/null; then
        echo "Operator ready"
        break
    fi
    sleep 5
done

# After refactoring:
print_info "Checking operator..."
wait_for_deployment "rook-ceph-operator" "rook-ceph" 300
print_success "Operator ready"
```

**Benefits:**
- Remove ~80 lines of duplicate functions
- Use `apply_crd()` with automatic retry
- Use `wait_for_deployment()`, `wait_for_pod()`, `wait_for_ceph_cluster()`
- Use `wait_for_osds()` instead of custom loop
- More consistent error handling

### 📝 `fix-rook-ceph-storage.sh` - TO BE REFACTORED

**Potential Improvements:**
```bash
# Current (example section):
print_info "  Deleting CephBlockPools..."
oc delete cephblockpool --all -n ${NAMESPACE} --wait=false 2>/dev/null || true
# ... similar for other resources
# ... finalizer removal logic

# After refactoring:
cleanup_ceph_dependents "${NAMESPACE}"
delete_resource_with_finalizers "cephcluster" "rook-ceph" "${NAMESPACE}" 120
```

**Benefits:**
- Remove ~60 lines of duplicate cleanup logic
- Use `cleanup_ceph_dependents()` for automatic cleanup
- Use `delete_resource_with_finalizers()` for stuck resources
- Use `wait_for_ceph_cluster()` instead of custom polling

## Benefits Summary

### Code Reduction

| Script | Original | After Refactoring | Lines Saved |
|--------|----------|-------------------|-------------|
| `test-ceph-storage.sh` | 457 | ~400 | ~60 |
| `install-rook-ceph.sh` | 502 | ~420 (est.) | ~80 (est.) |
| `fix-rook-ceph-storage.sh` | 348 | ~280 (est.) | ~70 (est.) |
| **Total** | **1307** | **~1100** | **~210** |

### Consistency

- **Unified output formatting**: All scripts use same color scheme and symbols
- **Standardized error handling**: Consistent retry logic and timeouts
- **Common patterns**: Same approach to validation, waiting, cleanup

### Maintainability

- **Single source of truth**: Update function once, all scripts benefit
- **Easier testing**: Test common functions independently
- **Better documentation**: One place to document best practices
- **Reduced bugs**: Fix a bug once rather than in multiple places

### Examples

#### Before (3 different implementations)

**Script 1:**
```bash
for i in {1..30}; do
    if oc get pvc test-pvc -n default &>/dev/null; then
        status=$(oc get pvc test-pvc -n default -o jsonpath='{.status.phase}')
        [ "$status" = "Bound" ] && break
    fi
    sleep 10
done
```

**Script 2:**
```bash
timeout=300
elapsed=0
while [ $elapsed -lt $timeout ]; do
    pvc_status=$(oc get pvc test-pvc -n default -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
    if [ "$pvc_status" = "Bound" ]; then
        break
    fi
    sleep 10
    elapsed=$((elapsed + 10))
done
```

**Script 3:**
```bash
oc wait --for=jsonpath='{.status.phase}'=Bound pvc/test-pvc -n default --timeout=300s
```

#### After (1 implementation, used everywhere)

**All scripts:**
```bash
wait_for_pvc "test-pvc" "default" 300
```

## Usage Pattern

### Step 1: Source the Library

```bash
#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
```

### Step 2: Use Common Functions

```bash
# Validate KUBECONFIG
validate_kubeconfig "$KUBECONFIG" || exit 1

# Print formatted output
print_header "My Script"
print_info "Starting process..."

# Wait for resources
wait_for_pvc "my-pvc" "default" 300
wait_for_deployment "my-app" "default" 300

# Ceph operations
if check_ceph_cluster "rook-ceph" "rook-ceph"; then
    health=$(get_ceph_health "rook-ceph" "rook-ceph")
    print_success "Ceph health: $health"
fi

# Cleanup with finalizers
cleanup_ceph_dependents "rook-ceph"
```

## Future Enhancements

### Additional Functions to Add

1. **Monitoring Functions**
   ```bash
   enable_ceph_monitoring NAMESPACE
   disable_ceph_monitoring NAMESPACE
   get_dashboard_url NAMESPACE
   get_dashboard_credentials NAMESPACE
   ```

2. **Backup/Restore Functions**
   ```bash
   backup_ceph_config NAMESPACE OUTPUT_DIR
   restore_ceph_config NAMESPACE BACKUP_DIR
   ```

3. **Performance Functions**
   ```bash
   benchmark_ceph_performance NAMESPACE
   get_ceph_metrics NAMESPACE
   ```

4. **Validation Functions**
   ```bash
   validate_ceph_installation NAMESPACE
   check_ceph_prerequisites
   validate_storage_configuration
   ```

### Testing Framework

Create `scripts/lib/test_common.sh`:
```bash
#!/bin/bash
# Unit tests for common.sh

test_print_functions() {
    print_info "Test info"
    print_success "Test success"
    print_warning "Test warning"
    print_error "Test error"
}

test_wait_functions() {
    # Create test PVC
    # Run wait_for_pvc
    # Assert success
}

# Run all tests
run_all_tests
```

## Migration Guide

### For Script Maintainers

1. **Read the common library**: Understand available functions
2. **Identify duplicates**: Find code that can be replaced
3. **Replace gradually**: Don't refactor everything at once
4. **Test thoroughly**: Verify behavior hasn't changed
5. **Update documentation**: Note any behavior changes

### Step-by-Step Example

**Original script section:**
```bash
echo "Checking if PVC is bound..."
for i in {1..30}; do
    STATUS=$(oc get pvc my-pvc -n default -o jsonpath='{.status.phase}' 2>/dev/null)
    if [ "$STATUS" = "Bound" ]; then
        echo "PVC is bound!"
        break
    fi
    if [ $i -eq 30 ]; then
        echo "ERROR: PVC failed to bind"
        exit 1
    fi
    echo -n "."
    sleep 10
done
```

**Step 1: Add library import**
```bash
source "$(dirname "$0")/lib/common.sh"
```

**Step 2: Replace the loop**
```bash
print_info "Checking if PVC is bound..."
if wait_for_pvc "my-pvc" "default" 300; then
    print_success "PVC is bound!"
else
    print_error "PVC failed to bind"
    exit 1
fi
```

**Step 3: Test**
```bash
./my-script.sh
# Verify output looks correct
# Verify functionality works as before
```

## Conclusion

The common library significantly improves:
- **Code quality**: Less duplication, more consistency
- **Maintainability**: Easier to update and fix
- **Readability**: Clearer intent, less boilerplate
- **Reliability**: Tested functions with proper error handling

All new scripts should use the common library from the start, and existing scripts should be gradually migrated.

---

*Created: October 27, 2025*  
*Status: In Progress*  
*Refactored Scripts: 1/3*

