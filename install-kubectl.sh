#!/usr/bin/env bash

set -euo pipefail

BACKUP_DIR="/usr/local/bin"

usage() {
    echo "Usage:"
    echo "  $0 [VERSION]        Install specific kubectl version (e.g. v1.29.3)"
    echo "  $0                  Install latest stable kubectl"
    echo "  $0 rollback         Rollback interactively to a previous version"
    echo "  $0 list             List available kubectl backups"
    exit 1
}

list_backups() {
    echo "[INFO] Searching for kubectl backups..."
    BACKUPS=( $(ls -t ${BACKUP_DIR}/kubectl.backup.* 2>/dev/null || true) )

    if [ ${#BACKUPS[@]} -eq 0 ]; then
        echo "[INFO] No kubectl backups found."
        exit 0
    fi

    echo "[INFO] Available backups:"
    for i in "${!BACKUPS[@]}"; do
        echo "  [$i] ${BACKUPS[$i]}"
    done
    exit 0
}

rollback() {
    BACKUPS=( $(ls -t ${BACKUP_DIR}/kubectl.backup.* 2>/dev/null || true) )

    if [ ${#BACKUPS[@]} -eq 0 ]; then
        echo "[ERROR] No kubectl backups found."
        exit 1
    fi

    echo "[INFO] Available backups:"
    for i in "${!BACKUPS[@]}"; do
        echo "  [$i] ${BACKUPS[$i]}"
    done

    read -p "Enter the number of the backup to restore: " CHOICE

    if ! [[ "$CHOICE" =~ ^[0-9]+$ ]] || [ "$CHOICE" -ge "${#BACKUPS[@]}" ]; then
        echo "[ERROR] Invalid choice."
        exit 1
    fi

    SELECTED_BACKUP=${BACKUPS[$CHOICE]}
    echo "[INFO] Restoring backup: $SELECTED_BACKUP"
    sudo mv "$SELECTED_BACKUP" "${BACKUP_DIR}/kubectl"
    sudo chmod +x "${BACKUP_DIR}/kubectl"

    echo "[SUCCESS] kubectl has been rolled back to the selected backup."
    exit 0
}

# Handle list and rollback commands
if [ $# -eq 1 ]; then
    case "$1" in
        rollback) rollback ;;
        list) list_backups ;;
    esac
fi

echo "[INFO] Detecting OS and architecture..."

# Detect distro
if [ -f /etc/os-release ]; then
    . /etc/os-release
    DISTRO=$ID
else
    echo "[ERROR] Cannot detect OS."
    exit 1
fi

# Detect architecture
ARCH=$(uname -m)
case "$ARCH" in
    x86_64)   ARCH="amd64" ;;
    aarch64)  ARCH="arm64" ;;
    armv7l)   ARCH="arm" ;;
    armv6l)   ARCH="arm" ;;
    *) 
        echo "[ERROR] Unsupported architecture: $ARCH"
        exit 1
        ;;
esac

echo "[INFO] Detected OS: $DISTRO"
echo "[INFO] Detected Architecture: $ARCH"

# Install dependencies
case "$DISTRO" in
    ubuntu|debian)
        sudo apt-get update -y
        sudo apt-get install -y curl
        ;;
    centos|rhel)
        sudo yum install -y curl
        ;;
    fedora)
        sudo dnf install -y curl
        ;;
    opensuse*|sles)
        sudo zypper install -y curl
        ;;
    *)
        echo "[ERROR] Unsupported Linux distribution: $DISTRO"
        exit 1
        ;;
esac

# Get kubectl version (argument or latest stable)
if [ $# -eq 0 ]; then
    echo "[INFO] No version provided. Fetching latest stable version..."
    KUBECTL_VERSION=$(curl -L -s https://dl.k8s.io/release/stable.txt)
else
    KUBECTL_VERSION=$1
    echo "[INFO] Installing specified version: $KUBECTL_VERSION"
fi

# Backup existing kubectl if present
if command -v kubectl &>/dev/null; then
    CURRENT_VERSION=$(kubectl version --client --short 2>/dev/null || echo "unknown")
    BACKUP_PATH="${BACKUP_DIR}/kubectl.backup.$(date +%Y%m%d%H%M%S)"
    echo "[INFO] Found existing kubectl ($CURRENT_VERSION). Backing up to $BACKUP_PATH"
    sudo cp "$(command -v kubectl)" "$BACKUP_PATH"
else
    echo "[INFO] No existing kubectl found. Fresh install."
fi

# Download kubectl
echo "[INFO] Downloading kubectl $KUBECTL_VERSION for $ARCH..."
curl -LO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${ARCH}/kubectl"

chmod +x kubectl
sudo mv kubectl /usr/local/bin/

# Verify installation
echo "[INFO] Verifying kubectl installation..."
if kubectl version --client; then
    echo "[SUCCESS] kubectl $KUBECTL_VERSION installed successfully on ${DISTRO} (${ARCH})!"
else
    echo "[ERROR] kubectl installation failed. Rolling back..."
    rollback
fi
