#!/usr/bin/env bash
set -euo pipefail

# sbackup-mount.sh
# Mount decrypted crypt backups for a provider + dataset.

if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <provider> <dataset-id>"
    exit 1
fi

PROV="$1"
ID="$2"

# Crypt backup remote
REMOTE="${PROV}-crypt-local-bak:${ID}"

# Mount root
MOUNT_ROOT="$HOME/data/decrypted-backups/$PROV/$ID"
mkdir -p "$MOUNT_ROOT"

echo "Listing encrypted backups for provider=$PROV dataset=$ID"
echo

# List timestamp directories
mapfile -t BACKUPS < <(rclone lsf "$REMOTE" --dirs-only 2>/dev/null | sort)

if [ "${#BACKUPS[@]}" -eq 0 ]; then
    echo "No encrypted backups found."
    exit 0
fi

# Show numbered list
i=1
for b in "${BACKUPS[@]}"; do
    echo "  $i) ${b%/}"
    ((i++))
done

echo
read -rp "Select backup(s) to mount (e.g. 1 or 1 3 4): " -a CHOICES

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
