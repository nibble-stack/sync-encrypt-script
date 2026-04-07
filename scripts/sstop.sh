#!/usr/bin/env bash
set -euo pipefail

# sstop: stop an encrypted session (unmount + sync + post-backup)
# Usage: sstop <provider> <dataset-id>

if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <provider> <dataset-id>"
    exit 1
fi

PROV="$1"
ID="$2"

DATA_ROOT="$HOME/data"
PROV_DIR="$DATA_ROOT/sync/$PROV"
BAK_DIR="$DATA_ROOT/sync-backup/${PROV}-bak"

DECRYPT_ROOT="$PROV_DIR/${PROV}-decrypt"
DECRYPT_DATA="$DECRYPT_ROOT/${PROV}-decrypt-$ID"

REMOTE_CRYPT_LOCAL="${PROV}-crypt-local"
REMOTE_CRYPT_CLOUD="${PROV}-crypt-cloud"
REMOTE_CRYPT_LOCAL_BAK="${PROV}-crypt-local-bak"
REMOTE_CRYPT_CLOUD_BAK="${PROV}-crypt-cloud-bak"

REMOTE_SYNC_LOCAL="${PROV}-sync-local"
REMOTE_SYNC_CLOUD="${PROV}-sync-cloud"
REMOTE_SYNC_LOCAL_BAK="${PROV}-sync-local-bak"
REMOTE_SYNC_CLOUD_BAK="${PROV}-sync-cloud-bak"

echo "[sstop] provider=$PROV dataset=$ID"

timestamp() {
    date +"%Y%m%d-%H%M%S"
}

online() {
    ping -c1 -W1 8.8.8.8 >/dev/null 2>&1
}

# -----------------------------
# UNMOUNT
# -----------------------------
if mountpoint -q "$DECRYPT_DATA"; then
    echo "[sstop] Unmounting $DECRYPT_DATA"
    fusermount3 -u "$DECRYPT_DATA" 2>/dev/null || fusermount -u "$DECRYPT_DATA" 2>/dev/null || true
else
    echo "[sstop] $DECRYPT_DATA is not a mountpoint, skipping unmount"
fi

# -----------------------------
# SYNC BACK TO CLOUD
# -----------------------------
if ! online; then
    echo "[sstop] Offline, cannot sync. Will sync next time."
    exit 0
fi

echo "[sstop] Online"
echo "[sstop] Syncing local -> cloud (crypt + sync)"

if rclone lsd "$REMOTE_CRYPT_LOCAL:${PROV}-crypt-$ID" >/dev/null 2>&1; then
    rclone sync "$REMOTE_CRYPT_LOCAL:${PROV}-crypt-$ID" \
                "$REMOTE_CRYPT_CLOUD:${PROV}-crypt-$ID" || true
else
    echo "[sstop] No local crypt dataset yet, skipping push"
fi

if rclone lsd "$REMOTE_SYNC_LOCAL:${PROV}-sync-$ID" >/dev/null 2>&1; then
    rclone sync "$REMOTE_SYNC_LOCAL:${PROV}-sync-$ID" \
                "$REMOTE_SYNC_CLOUD:${PROV}-sync-$ID" || true
else
    echo "[sstop] No local sync dataset yet, skipping push"
fi

# -----------------------------
# POST-BACKUP
# -----------------------------
TS="$(timestamp)"

echo "[sstop] Post-backup (encrypted dataset)"

if rclone lsd "$REMOTE_CRYPT_LOCAL:${PROV}-crypt-$ID" >/dev/null 2>&1; then
    rclone sync "$REMOTE_CRYPT_LOCAL:${PROV}-crypt-$ID" \
                "$REMOTE_CRYPT_LOCAL_BAK:${PROV}-crypt-bak-$ID-post-$TS" || true
else
    echo "[sstop] No local crypt dataset yet, skipping crypt post-backup"
fi

if rclone lsd "$REMOTE_SYNC_LOCAL:${PROV}-sync-$ID" >/dev/null 2>&1; then
    rclone sync "$REMOTE_SYNC_LOCAL:${PROV}-sync-$ID" \
                "$REMOTE_SYNC_LOCAL_BAK:${PROV}-sync-bak-$ID-post-$TS" || true
else
    echo "[sstop] No local sync dataset yet, skipping sync post-backup"
fi

echo "[sstop] Done."
