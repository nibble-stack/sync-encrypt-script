#!/usr/bin/env bash
set -euo pipefail

# sbackup-unmount.sh
# Unmount all decrypted crypt backups for a provider + dataset.

if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <provider> <dataset-id>"
    exit 1
fi

PROV="$1"
ID="$2"

MOUNT_ROOT="$HOME/data/decrypted-backups/$PROV/$ID"

if [ ! -d "$MOUNT_ROOT" ]; then
    echo "No decrypted backup mounts found for $PROV/$ID."
    exit 0
fi

echo "Checking mounted backups under $MOUNT_ROOT"
echo

found_any=false

for dir in "$MOUNT_ROOT"/*; do
    [ -d "$dir" ] || continue

    if mountpoint -q "$dir"; then
        found_any=true
        echo "Unmounting: $dir"
        fusermount3 -u "$dir" 2>/dev/null || fusermount -u "$dir" 2>/dev/null || echo "Failed to unmount $dir"
        rmdir "$dir" 2>/dev/null || true
    fi
done

if ! $found_any; then
    echo "No mounted backups found."
else
    echo
    echo "All decrypted backups have been unmounted."
fi
