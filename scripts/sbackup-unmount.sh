#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="sbackup-unmount"

# ---------------------------------------------------------
# Load core modules
# ---------------------------------------------------------
SCRIPT_PATH="$(readlink -f "$0")"
BASE_DIR="$(dirname "$SCRIPT_PATH")"
# BASE_DIR="$(dirname "$0")"
source "$BASE_DIR/core/env.sh"
source "$BASE_DIR/core/utils.sh"
source "$BASE_DIR/core/provider.sh"
source "$BASE_DIR/core/paths.sh"
source "$BASE_DIR/core/mount.sh"

# ---------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <provider> <dataset-id>"
    exit 1
fi

PROV="$1"
ID="$2"

validate_provider "$PROV"
[[ "$ID" =~ ^[A-Za-z0-9._-]+$ ]] || {
    echo "ERROR: invalid dataset id '$ID'" >&2
    exit 1
}

# ---------------------------------------------------------
# Paths
# ---------------------------------------------------------
MOUNT_ROOT="$(backup_mount_root "$PROV" "$ID")"

if [ ! -d "$MOUNT_ROOT" ]; then
    echo "No decrypted backup mounts found for $PROV/$ID."
    exit 0
fi

echo "Checking mounted backups under $MOUNT_ROOT"
echo

found_any=false

# ---------------------------------------------------------
# Unmount all mounted backup directories
# ---------------------------------------------------------
for dir in "$MOUNT_ROOT"/*; do
    [ -d "$dir" ] || continue

    if mountpoint -q "$dir"; then
        found_any=true
        echo "Unmounting: $dir"
        unmount_path "$dir"
        rmdir "$dir" 2>/dev/null || true
    fi
done

if ! $found_any; then
    echo "No mounted backups found."
else
    echo
    echo "All decrypted backups have been unmounted."
fi
