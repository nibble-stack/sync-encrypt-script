#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="sbackup-select"

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
REMOTE="$(crypt_local_bak "$PROV"):$ID"
MOUNT_ROOT="$(backup_mount_root "$PROV" "$ID")"

mkdir -p "$MOUNT_ROOT"

echo "Listing encrypted backups for provider=$PROV dataset=$ID"
echo

# ---------------------------------------------------------
# List timestamp directories
# ---------------------------------------------------------
mapfile -t BACKUPS < <(rclone lsf "$REMOTE" --dirs-only 2>/dev/null | sort)

if [ "${#BACKUPS[@]}" -eq 0 ]; then
    echo "No encrypted backups found."
    exit 0
fi

# ---------------------------------------------------------
# Show numbered list
# ---------------------------------------------------------
i=1
for b in "${BACKUPS[@]}"; do
    echo "  $i) ${b%/}"
    ((i++))
done

echo
read -rp "Select backup(s) to mount (e.g. 1 or 1 3 4): " -a CHOICES

# ---------------------------------------------------------
# Mount selected backups
# ---------------------------------------------------------
for choice in "${CHOICES[@]}"; do
    idx=$((choice-1))

    if (( idx < 0 || idx >= ${#BACKUPS[@]} )); then
        echo "Invalid choice: $choice"
        continue
    fi

    TS="${BACKUPS[$idx]%/}"
    MOUNT_DIR="$MOUNT_ROOT/$TS"

    mkdir -p "$MOUNT_DIR"

    echo "Mounting backup $TS at $MOUNT_DIR ..."
    rclone mount "$REMOTE/$TS" "$MOUNT_DIR" \
        --read-only \
        --vfs-cache-mode full \
        --daemon

    sleep 1
    if mountpoint -q "$MOUNT_DIR"; then
        echo "✔ Mounted: $MOUNT_DIR"
    else
        echo "✖ Failed to mount $TS"
        rmdir "$MOUNT_DIR" 2>/dev/null || true
    fi
done

echo
echo "Done. Browse decrypted backups under: $MOUNT_ROOT"
