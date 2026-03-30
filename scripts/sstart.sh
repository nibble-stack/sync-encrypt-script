#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 3 ]; then
    echo "Usage: $0 <provider> <dataset-id> --mount|--sync"
    exit 1
fi

PROV="$1"          # e.g. gd
ID="$2"            # e.g. 01
MODE="$3"          # --mount or --sync

ROOT="$HOME/sync/$PROV"
BACKROOT="$HOME/sync-backup/${PROV}-bak"
PENDING_DIR="$ROOT/${PROV}-sync-pending"
mkdir -p "$PENDING_DIR"

# Dataset paths
CRYPT_DIR="$ROOT/${PROV}-crypt/${PROV}-crypt-$ID"
SYNC_DIR="$ROOT/${PROV}-sync/${PROV}-sync-$ID"
DECRYPT_DIR="$ROOT/${PROV}-decrypt/${PROV}-decrypt-$ID"

# Backup paths
CRYPT_BAK="$BACKROOT/${PROV}-crypt-bak/${PROV}-crypt-$ID"
SYNC_BAK="$BACKROOT/${PROV}-sync-bak/${PROV}-sync-$ID"

mkdir -p "$CRYPT_DIR" "$SYNC_DIR" "$DECRYPT_DIR" "$CRYPT_BAK" "$SYNC_BAK"

# Remotes
LOCAL_CRYPT="${PROV}-crypt-local:${PROV}-crypt-$ID"
CLOUD_CRYPT="${PROV}-crypt-cloud:${PROV}-crypt-$ID"
LOCAL_SYNC="${PROV}-sync-local:${PROV}-sync-$ID"
CLOUD_SYNC="${PROV}-sync-cloud:${PROV}-sync-$ID"

LOCAL_CRYPT_BAK="${PROV}-crypt-local-bak:${PROV}-crypt-$ID"
CLOUD_CRYPT_BAK="${PROV}-crypt-cloud-bak:${PROV}-crypt-$ID"
LOCAL_SYNC_BAK="${PROV}-sync-local-bak:${PROV}-sync-$ID"
CLOUD_SYNC_BAK="${PROV}-sync-cloud-bak:${PROV}-sync-$ID"

# Pending flag
PENDING_FLAG="$PENDING_DIR/${PROV}-${ID}.pending"

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

# Determine dataset type
if [ "$MODE" = "--mount" ]; then
    TYPE="crypt"
    LOCAL_REMOTE="$LOCAL_CRYPT"
    CLOUD_REMOTE="$CLOUD_CRYPT"
    LOCAL_BAK="$LOCAL_CRYPT_BAK"
    CLOUD_BAK="$CLOUD_CRYPT_BAK"
    BAK_DIR="$CRYPT_BAK"
else
    TYPE="sync"
    LOCAL_REMOTE="$LOCAL_SYNC"
    CLOUD_REMOTE="$CLOUD_SYNC"
    LOCAL_BAK="$LOCAL_SYNC_BAK"
    CLOUD_BAK="$CLOUD_SYNC_BAK"
    BAK_DIR="$SYNC_BAK"
fi

# -----------------------------
# Ensure cloud directories exist
# -----------------------------
rclone mkdir "$CLOUD_REMOTE" >/dev/null 2>&1 || true
rclone mkdir "$CLOUD_BAK" >/dev/null 2>&1 || true

# -----------------------------
# PRE-SESSION BACKUP
# -----------------------------
TS_PRE="$(timestamp)-pre"
mkdir -p "$BAK_DIR/$TS_PRE"

# Local backup
rclone copy "$LOCAL_REMOTE" "$LOCAL_BAK/$TS_PRE" || true

# Cloud backup
rclone copy "$LOCAL_REMOTE" "$CLOUD_BAK/$TS_PRE" || true

rotate_backups "$BAK_DIR"

# -----------------------------
# PENDING UPLOAD HANDLING
# -----------------------------
if online; then
    if [ -f "$PENDING_FLAG" ]; then
        rclone sync "$LOCAL_REMOTE" "$CLOUD_REMOTE" || true
        rm -f "$PENDING_FLAG"
    fi

    # Pull cloud → local
    rclone sync "$CLOUD_REMOTE" "$LOCAL_REMOTE" || true
else
    echo "Offline: using local copy only."
fi

# -----------------------------
# LOCAL → CLOUD SYNC
# -----------------------------
if online; then
    rclone sync "$LOCAL_REMOTE" "$CLOUD_REMOTE" || true
else
    touch "$PENDING_FLAG"
fi

# -----------------------------
# MOUNT (encrypted only)
# -----------------------------
if [ "$MODE" = "--mount" ]; then
    if mountpoint -q "$DECRYPT_DIR"; then
        echo "Already mounted at $DECRYPT_DIR"
        exit 0
    fi

    rclone mount "$LOCAL_REMOTE" "$DECRYPT_DIR" --vfs-cache-mode full --daemon
    sleep 2
    echo "Mounted decrypted view at $DECRYPT_DIR"
fi

# -----------------------------
# POST-SESSION BACKUP (sync-only only)
# -----------------------------
if [ "$MODE" = "--sync" ]; then
    TS_POST="$(timestamp)-post"
    mkdir -p "$BAK_DIR/$TS_POST"

    rclone copy "$LOCAL_REMOTE" "$LOCAL_BAK/$TS_POST" || true
    rclone copy "$LOCAL_REMOTE" "$CLOUD_BAK/$TS_POST" || true

    rotate_backups "$BAK_DIR"
fi

echo "Start complete for $PROV dataset $ID ($TYPE mode)"
