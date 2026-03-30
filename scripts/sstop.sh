#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <provider> <dataset-id>"
    exit 1
fi

PROV="$1"
ID="$2"

ROOT="$HOME/sync/$PROV"
DECRYPT_DIR="$ROOT/${PROV}-decrypt/${PROV}-decrypt-$ID"

# Remotes
LOCAL_CRYPT="${PROV}-crypt-local:${PROV}-crypt-$ID"
CLOUD_CRYPT="${PROV}-crypt-cloud:${PROV}-crypt-$ID"

# Backup paths
BACKROOT="$HOME/sync-backup/${PROV}-bak"
CRYPT_BAK="$BACKROOT/${PROV}-crypt-bak/${PROV}-crypt-$ID"
LOCAL_CRYPT_BAK="${PROV}-crypt-local-bak:${PROV}-crypt-$ID"
CLOUD_CRYPT_BAK="${PROV}-crypt-cloud-bak:${PROV}-crypt-$ID"

mkdir -p "$CRYPT_BAK"

online() {
    ping -c1 -W1 8.8.8.8 >/dev/null 2>&1
}

rotate_backups() {
    local dir="$1"
    local backups
    backups=($(ls -1t "$dir" 2>/dev/null || true))
    if [ "${#backups[@]}" -gt 5 ]; then
        for b in "${backups[@]:5}"; do
            rm -rf "$dir/$b"
        done
    fi
}

timestamp() {
    date +"%Y%m%d-%H%M%S"
}

# -----------------------------
# UNMOUNT
# -----------------------------
if mountpoint -q "$DECRYPT_DIR"; then
    fusermount -u "$DECRYPT_DIR" || true
    sleep 1
fi

# -----------------------------
# SYNC LOCAL → CLOUD
# -----------------------------
if online; then
    rclone sync "$LOCAL_CRYPT" "$CLOUD_CRYPT" || true
else
    touch "$ROOT/${PROV}-sync-pending/${PROV}-${ID}.pending"
fi

# -----------------------------
# POST-SESSION BACKUP
# -----------------------------
TS_POST="$(timestamp)-post"
mkdir -p "$CRYPT_BAK/$TS_POST"

rclone copy "$LOCAL_CRYPT" "$LOCAL_CRYPT_BAK/$TS_POST" || true
rclone copy "$LOCAL_CRYPT" "$CLOUD_CRYPT_BAK/$TS_POST" || true

rotate_backups "$CRYPT_BAK"

echo "Stop complete for $PROV dataset $ID (encrypted mode)"
