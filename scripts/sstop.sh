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

# List backups for a given prefix, newest first
list_backups() {
    local remote="$1"   # e.g. gd-crypt-local-bak
    local prefix="$2"   # e.g. gd-crypt-bak-01-pre or gd-crypt-bak-01-post

    rclone lsf "$remote:" 2>/dev/null | grep "^$prefix" | sort -r || true
}

# Rotate backups: keep 5 for a given prefix (pre or post separately)
rotate_backups() {
    local remote="$1"
    local prefix="$2"

    mapfile -t backups < <(list_backups "$remote" "$prefix")

    if [ "${#backups[@]}" -gt 5 ]; then
        for old in "${backups[@]:5}"; do
            echo "[rotate] Removing old backup: $remote:$old"
            rclone purge "$remote:$old" || true
        done
    fi
}

# Create a backup snapshot
create_backup() {
    local src="$1"      # e.g. gd-crypt-local:gd-crypt-01
    local dst="$2"      # e.g. gd-crypt-local-bak
    local name="$3"     # full dir name, e.g. gd-crypt-bak-01-pre-20260410-120000

    echo "[backup] Creating backup: $dst:$name"
    rclone sync "$src" "$dst:$name" || true
}

# Mirror local backups to cloud
sync_backups_to_cloud() {
    local local_bak="$1"   # e.g. gd-crypt-local-bak
    local cloud_bak="$2"   # e.g. gd-crypt-cloud-bak

    echo "[backup] Syncing backups to cloud: $local_bak: -> $cloud_bak:"
    rclone sync "$local_bak:" "$cloud_bak:" || true
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

echo "[sstop] Post-backup"

# crypt post-backup
if rclone lsd "$REMOTE_CRYPT_LOCAL:${PROV}-crypt-$ID" >/dev/null 2>&1; then
    BAK_NAME="${PROV}-crypt-bak-$ID-post-$TS"
    create_backup \
        "$REMOTE_CRYPT_LOCAL:${PROV}-crypt-$ID" \
        "$REMOTE_CRYPT_LOCAL_BAK" \
        "$BAK_NAME"

    # rotate local crypt post-backups
    rotate_backups "$REMOTE_CRYPT_LOCAL_BAK" "${PROV}-crypt-bak-$ID-post"
else
    echo "[sstop] No local crypt dataset yet, skipping crypt post-backup"
fi

# sync post-backup
if rclone lsd "$REMOTE_SYNC_LOCAL:${PROV}-sync-$ID" >/dev/null 2>&1; then
    BAK_NAME="${PROV}-sync-bak-$ID-post-$TS"
    create_backup \
        "$REMOTE_SYNC_LOCAL:${PROV}-sync-$ID" \
        "$REMOTE_SYNC_LOCAL_BAK" \
        "$BAK_NAME"

    # rotate local sync post-backups
    rotate_backups "$REMOTE_SYNC_LOCAL_BAK" "${PROV}-sync-bak-$ID-post"
else
    echo "[sstop] No local sync dataset yet, skipping sync post-backup"
fi

# Mirror backups to cloud
sync_backups_to_cloud "$REMOTE_CRYPT_LOCAL_BAK" "$REMOTE_CRYPT_CLOUD_BAK"
sync_backups_to_cloud "$REMOTE_SYNC_LOCAL_BAK" "$REMOTE_SYNC_CLOUD_BAK"

# Rotate cloud post-backups
rotate_backups "$REMOTE_CRYPT_CLOUD_BAK" "${PROV}-crypt-bak-$ID-post"
rotate_backups "$REMOTE_SYNC_CLOUD_BAK" "${PROV}-sync-bak-$ID-post"

echo "[sstop] Done."
