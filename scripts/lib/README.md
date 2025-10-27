# Common Library for Rook-Ceph Scripts

This directory contains shared utility functions used across multiple Rook-Ceph management scripts.

## Files

### `common.sh`

A bash library providing common functions for:
- **Output formatting**: Consistent colored output with print functions
- **KUBECONFIG validation**: Cluster connectivity checks
- **Kubernetes operations**: Wait functions for resources, PVCs, deployments
- **Ceph operations**: Health checks, OSD counting, toolbox execution
- **CRD management**: Apply with retry logic
- **Cleanup operations**: Resource deletion with finalizer handling

## Usage

### In Your Script

```bash
#!/bin/bash

# Load common library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

# Now you can use all common functions
validate_kubeconfig "$KUBECONFIG"
print_success "Connected to cluster!"
```

## Available Functions

### Output Functions

```bash
print_header "Section Title"          # Prints a boxed header
print_section "Subsection"             # Prints a section marker
print_info "Information message"       # Blue info message
print_success "Success message"        # Green checkmark message
print_warning "Warning message"        # Yellow warning message
print_error "Error message"            # Red error message
print_debug "Debug message"            # Magenta debug (only if DEBUG=true)
```

### KUBECONFIG Functions

```bash
validate_kubeconfig [path]             # Validates and sets KUBECONFIG
get_cluster_info                       # Returns cluster server and user info
```

### Kubernetes Resource Operations

```bash
wait_for_namespace NAME [TIMEOUT]                    # Wait for namespace to exist
wait_for_pod SELECTOR NAMESPACE [TIMEOUT]            # Wait for pod to be ready
wait_for_deployment NAME NAMESPACE [TIMEOUT]         # Wait for deployment to be available
wait_for_pvc NAME NAMESPACE [TIMEOUT]                # Wait for PVC to be bound
apply_crd URL [RETRIES]                              # Apply CRD with retry logic
apply_manifest "YAML" "description"                  # Apply manifest from string
delete_resource_with_finalizers TYPE NAME NAMESPACE  # Delete with finalizer removal
```

### Ceph-Specific Functions

```bash
check_ceph_cluster [NAMESPACE] [NAME]                # Check if CephCluster exists
get_ceph_health [NAMESPACE] [NAME]                   # Get cluster health status
get_ceph_phase [NAMESPACE] [NAME]                    # Get cluster phase
wait_for_ceph_cluster [NAMESPACE] [NAME] [TIMEOUT]   # Wait for cluster to be ready
count_osds [NAMESPACE]                               # Count running OSD pods
wait_for_osds COUNT [NAMESPACE] [TIMEOUT]            # Wait for N OSDs to be created
ceph_exec NAMESPACE COMMAND                          # Execute command in toolbox
get_ceph_status [NAMESPACE]                          # Get 'ceph -s' output
check_storage_class NAME                             # Check if storage class exists
cleanup_ceph_dependents [NAMESPACE]                  # Clean up dependent resources
```

### Utility Functions

```bash
validate_url URL                       # Check if URL is accessible
get_library_version                    # Get library version
```

## Examples

### Example 1: Check Ceph Health

```bash
#!/bin/bash
source "$(dirname "$0")/lib/common.sh"

validate_kubeconfig "$KUBECONFIG" || exit 1

if check_ceph_cluster "rook-ceph" "rook-ceph"; then
    health=$(get_ceph_health "rook-ceph" "rook-ceph")
    print_success "Ceph health: $health"
else
    print_error "Ceph cluster not found"
    exit 1
fi
```

### Example 2: Wait for Resources

```bash
#!/bin/bash
source "$(dirname "$0")/lib/common.sh"

validate_kubeconfig "$KUBECONFIG" || exit 1

print_info "Creating PVC..."
oc apply -f my-pvc.yaml

# Wait for PVC to be bound
if wait_for_pvc "my-pvc" "default" 300; then
    print_success "PVC is bound"
else
    print_error "PVC failed to bind"
    exit 1
fi
```

### Example 3: Cleanup with Finalizers

```bash
#!/bin/bash
source "$(dirname "$0")/lib/common.sh"

validate_kubeconfig "$KUBECONFIG" || exit 1

# Clean up dependent resources automatically
cleanup_ceph_dependents "rook-ceph"

# Delete CephCluster with finalizer handling
delete_resource_with_finalizers "cephcluster" "rook-ceph" "rook-ceph" 120
```

### Example 4: Apply CRDs with Retry

```bash
#!/bin/bash
source "$(dirname "$0")/lib/common.sh"

validate_kubeconfig "$KUBECONFIG" || exit 1

# Apply CRD with automatic retry
if apply_crd "https://raw.githubusercontent.com/rook/rook/master/deploy/examples/crds.yaml" 3; then
    print_success "CRDs applied"
else
    print_error "Failed to apply CRDs"
    exit 1
fi
```

## Scripts Using This Library

The following scripts have been refactored to use the common library:

1. **`test-ceph-storage.sh`** - Storage testing script
2. **`install-rook-ceph.sh`** - Installation script (to be refactored)
3. **`fix-rook-ceph-storage.sh`** - Fix/repair script (to be refactored)

## Environment Variables

### `DEBUG`
Set to `true` to enable debug output:
```bash
DEBUG=true ./scripts/test-ceph-storage.sh
```

### `KUBECONFIG`
Path to kubeconfig file (can be overridden by script arguments)

## Benefits

### Before (Without Common Library)
```bash
# Duplicated in every script:
RED='\033[0;31m'
GREEN='\033[0;32m'
# ... 20 lines of color definitions

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}
# ... Repeated print functions

# Duplicated validation
if [ -z "$KUBECONFIG_PATH" ]; then
    echo "KUBECONFIG not set"
    exit 1
fi
# ... More validation

# Duplicated wait logic
for i in {1..30}; do
    PVC_STATUS=$(oc get pvc ... 2>/dev/null || echo "Unknown")
    if [ "$PVC_STATUS" = "Bound" ]; then
        break
    fi
    # ... More wait logic
done
```

### After (With Common Library)
```bash
#!/bin/bash
source "$(dirname "$0")/lib/common.sh"

validate_kubeconfig "$KUBECONFIG" || exit 1
wait_for_pvc "my-pvc" "default" 300
print_success "PVC is bound!"
```

**Result**: 50+ lines reduced to 4 lines, with better error handling and consistency.

## Version

Current version: **1.0.0**

## Maintenance

When adding new common functionality:
1. Add the function to `common.sh`
2. Document it in this README
3. Add example usage
4. Update scripts to use the new function
5. Test the function with various error conditions

## Testing

Test the library by sourcing it and calling functions:

```bash
# Test sourcing
source scripts/lib/common.sh

# Test functions
print_success "Library loaded successfully!"
get_library_version
```

---

*Last updated: October 27, 2025*

