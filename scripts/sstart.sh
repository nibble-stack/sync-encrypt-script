#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 3 ]; then
    echo "Usage: $0 <provider> <dataset-id> --mount|--sync"
    exit 1
fi

PROV="$1"          # e.g. db
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

# Backup roots (per provider, NOT per dataset)
CRYPT_BAK="$BACKROOT/${PROV}-crypt-bak"
SYNC_BAK="$BACKROOT/${PROV}-sync-bak"

# Remotes
LOCAL_CRYPT="${PROV}-crypt-local:${PROV}-crypt-$ID"
CLOUD_CRYPT="${PROV}-crypt-cloud:${PROV}-crypt-$ID"
LOCAL_SYNC="${PROV}-sync-local:${PROV}-sync-$ID"
CLOUD_SYNC="${PROV}-sync-cloud:${PROV}-sync-$ID"

LOCAL_CRYPT_BAK="${PROV}-crypt-local-bak:"
CLOUD_CRYPT_BAK="${PROV}-crypt-cloud-bak:"
LOCAL_SYNC_BAK="${PROV}-sync-local-bak:"
CLOUD_SYNC_BAK="${PROV}-sync-cloud-bak:"

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

# Ensure remotes exist
for dir in "$CLOUD_REMOTE" "$CLOUD_BAK" "$LOCAL_REMOTE" "$LOCAL_BAK"; do
    rclone mkdir "$dir" >/dev/null 2>&1 || true
done

# Friendly first-run notice (your original logic)
if [ -z "$(rclone lsf "$LOCAL_REMOTE" | grep -v '^\.placeholder$')" ]; then
    echo "NOTICE: Initializing a new encrypted folder. The --checksum fallback warning from rclone is normal until real files are added."
fi

# Initialize placeholder if folder is empty
if [ -z "$(rclone lsf "$LOCAL_REMOTE")" ]; then
    echo "Initializing empty encrypted folder..."
    echo ".placeholder" | rclone rcat "$LOCAL_REMOTE/.placeholder"
fi

# PRE-SESSION BACKUP (only if real files exist, recursively)
if rclone ls "$LOCAL_REMOTE" 2>/dev/null | grep -qv '\.placeholder'; then
    TS_PRE="$(timestamp)-${PROV}-${ID}-pre"
    mkdir -p "$BAK_DIR/$TS_PRE"

    # Local backup (to backup remote rooted at BAK_DIR)
    rclone copy "$LOCAL_REMOTE/" "${LOCAL_BAK}${TS_PRE}" --exclude ".placeholder" || true
    # Cloud backup
    rclone copy "$LOCAL_REMOTE/" "${CLOUD_BAK}${TS_PRE}" --exclude ".placeholder" || true

    rotate_backups "$BAK_DIR"
fi

# PENDING UPLOAD HANDLING
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

# LOCAL → CLOUD SYNC
if online; then
    rclone sync "$LOCAL_REMOTE" "$CLOUD_REMOTE" || true
else
    touch "$PENDING_FLAG"
fi

# POST-SYNC: remove placeholder if real files exist
if rclone ls "$LOCAL_REMOTE" 2>/dev/null | grep -qv '\.placeholder'; then
    rclone purge "$LOCAL_REMOTE/.placeholder" 2>/dev/null || true
fi

# MOUNT (encrypted only)
if [ "$MODE" = "--mount" ]; then
    mkdir -p "$DECRYPT_DIR"
    if mountpoint -q "$DECRYPT_DIR"; then
        echo "Already mounted at $DECRYPT_DIR"
        exit 0
    fi
    rclone mount "$LOCAL_REMOTE" "$DECRYPT_DIR" --vfs-cache-mode full --daemon
    sleep 2
    echo "Mounted decrypted view at $DECRYPT_DIR"
fi

echo "Start complete for $PROV dataset $ID ($TYPE mode)"
