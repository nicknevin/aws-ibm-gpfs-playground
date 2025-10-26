#!/bin/bash
# Script to set up shared binaries for DR clusters, avoiding duplicate downloads

set -e

OCP_VERSION="4.19.15"
SHARED_DIR="$HOME/dr-playground/shared/$OCP_VERSION"

echo "=== Setting up Shared OpenShift Binaries ==="
echo "This will avoid downloading 756 MB per cluster"
echo ""

# Create shared directory
echo "Creating shared directory: $SHARED_DIR"
mkdir -p "$SHARED_DIR"
cd "$SHARED_DIR"

# URLs for OpenShift binaries
OC_CLIENT_URL="https://mirror.openshift.com/pub/openshift-v4/multi/clients/ocp/$OCP_VERSION/amd64/openshift-client-linux.tar.gz"
OC_INSTALL_URL="https://mirror.openshift.com/pub/openshift-v4/multi/clients/ocp/$OCP_VERSION/amd64/openshift-install-linux.tar.gz"
BUTANE_URL="https://mirror.openshift.com/pub/openshift-v4/clients/butane/v0.23.0-0/butane-amd64"

# Check what's already available (PATH, shared directory, and existing cluster directories)
echo "Checking for existing binaries..."

check_binary() {
    local binary=$1
    
    # Check if binary exists in PATH
    if command -v "$binary" >/dev/null 2>&1; then
        echo "  ✓ Found $binary in PATH ($(which $binary))"
        return 0
    fi
    
    # Check in shared directory
    if [ -f "$SHARED_DIR/$binary" ]; then
        echo "  ✓ Found $binary in shared directory"
        return 0
    fi
    
    # Check in existing cluster directories
    if find "$HOME/dr-playground" -maxdepth 3 -name "$binary" -type f 2>/dev/null | grep -q .; then
        echo "  ✓ Found $binary in existing cluster directory"
        return 0
    fi
    
    # Binary not found anywhere
    echo "  ✗ Missing: $binary"
    return 1
}

DOWNLOADS_NEEDED=false

if ! check_binary "openshift-install"; then
    DOWNLOADS_NEEDED=true
fi

if ! check_binary "oc"; then
    DOWNLOADS_NEEDED=true
fi

if ! check_binary "kubectl"; then
    DOWNLOADS_NEEDED=true
fi

if ! check_binary "butane"; then
    DOWNLOADS_NEEDED=true
fi

# Download binaries if needed
if [ "$DOWNLOADS_NEEDED" = true ]; then
    echo ""
    echo "Downloading missing binaries..."
    
    if [ ! -f "openshift-client-linux.tar.gz" ]; then
        echo "Downloading openshift-client..."
        wget -q --show-progress "$OC_CLIENT_URL" -O openshift-client-linux.tar.gz
        echo "✓ Downloaded openshift-client"
    fi
    
    if [ ! -f "openshift-install-linux.tar.gz" ]; then
        echo "Downloading openshift-install..."
        wget -q --show-progress "$OC_INSTALL_URL" -O openshift-install-linux.tar.gz
        echo "✓ Downloaded openshift-install"
    fi
    
    echo "Extracting binaries..."
    tar xzf openshift-client-linux.tar.gz 2>/dev/null || true
    tar xzf openshift-install-linux.tar.gz 2>/dev/null || true
    
    if [ ! -f "butane" ]; then
        echo "Downloading butane..."
        wget -q --show-progress "$BUTANE_URL" -O butane
        if [ $? -eq 0 ]; then
            chmod +x butane
            echo "✓ Downloaded butane"
        else
            echo "⚠ Butane download failed, trying alternative..."
            # Try copying from existing cluster if available
            if EXISTING_BUTANE=$(find "$HOME/dr-playground" -maxdepth 3 -name "butane" -type f 2>/dev/null | head -1); then
                cp "$EXISTING_BUTANE" butane
                echo "✓ Copied butane from existing installation"
            else
                echo "✗ Butane download failed"
            fi
        fi
    fi
    
    echo "Cleaning up archives..."
    rm -f openshift-client-linux.tar.gz openshift-install-linux.tar.gz
    
    echo ""
    echo "✓ Binaries downloaded to $SHARED_DIR"
else
    echo ""
    echo "✓ All binaries already exist in $SHARED_DIR"
fi

echo ""
echo "=== Creating Symlinks for Clusters ==="
echo ""

# Function to create symlinks for a cluster
create_symlinks() {
    local cluster_name=$1
    local cluster_dir="$HOME/dr-playground/$cluster_name/$OCP_VERSION"
    
    if [ -d "$HOME/dr-playground/$cluster_name/ocp_install_files" ]; then
        echo "⚠ Cluster $cluster_name already has installation files. Skipping..."
        return
    fi
    
    echo "Creating symlinks for cluster: $cluster_name"
    mkdir -p "$cluster_dir"
    
    # Remove existing files if they exist (not symlinks)
    for binary in oc kubectl openshift-install butane; do
        if [ -f "$cluster_dir/$binary" ] && [ ! -L "$cluster_dir/$binary" ]; then
            echo "  Removing existing $binary from $cluster_name"
            rm "$cluster_dir/$binary"
        fi
    done
    
    # Create symlinks (using absolute paths)
    for binary in oc kubectl openshift-install butane; do
        if [ ! -L "$cluster_dir/$binary" ] && [ ! -f "$cluster_dir/$binary" ]; then
            ln -sf "$SHARED_DIR/$binary" "$cluster_dir/$binary"
            echo "  ✓ Created symlink: $cluster_dir/$binary → $SHARED_DIR/$binary"
        elif [ -L "$cluster_dir/$binary" ]; then
            echo "  - Symlink already exists: $cluster_dir/$binary"
        else
            echo "  ⊗ File exists (not a symlink): $cluster_dir/$binary"
        fi
    done
}

# Create symlinks for each cluster passed as argument
for cluster_name in "$@"; do
    create_symlinks "$cluster_name"
done

echo ""
echo "=== Summary ==="
echo "Shared binaries location: $SHARED_DIR"
echo "Disk space saved: 756 MB per additional cluster"

# Show storage usage
echo ""
echo "Storage usage:"
du -sh "$SHARED_DIR" 2>/dev/null || echo "Unable to check size"
echo ""
echo "✓ Setup complete!"
