#!/usr/bin/env bash
set -euo pipefail

# sstart: start a session (encrypted mount or sync-only)
# Usage: sstart <provider> <dataset-id> --mount|--sync

if [ "$#" -ne 3 ]; then
    echo "Usage: $0 <provider> <dataset-id> --mount|--sync"
    exit 1
fi

PROV="$1"
ID="$2"
MODE="$3"

DATA_ROOT="$HOME/data"
PROV_DIR="$DATA_ROOT/sync/$PROV"
BAK_DIR="$DATA_ROOT/sync-backup/${PROV}-bak"

CRYPT_ROOT="$PROV_DIR/${PROV}-crypt"
DECRYPT_ROOT="$PROV_DIR/${PROV}-decrypt"
SYNC_ROOT="$PROV_DIR/${PROV}-sync"
PENDING_ROOT="$PROV_DIR/${PROV}-pending"

DECRYPT_DATA="$DECRYPT_ROOT/${PROV}-decrypt-$ID"
SYNC_DATA="$SYNC_ROOT/${PROV}-sync-$ID"

CRYPT_BAK_ROOT="$BAK_DIR/${PROV}-crypt-bak"
SYNC_BAK_ROOT="$BAK_DIR/${PROV}-sync-bak"

REMOTE_CRYPT_LOCAL="${PROV}-crypt-local"
REMOTE_CRYPT_CLOUD="${PROV}-crypt-cloud"
REMOTE_CRYPT_LOCAL_BAK="${PROV}-crypt-local-bak"
REMOTE_CRYPT_CLOUD_BAK="${PROV}-crypt-cloud-bak"

REMOTE_SYNC_LOCAL="${PROV}-sync-local"
REMOTE_SYNC_CLOUD="${PROV}-sync-cloud"
REMOTE_SYNC_LOCAL_BAK="${PROV}-sync-local-bak"
REMOTE_SYNC_CLOUD_BAK="${PROV}-sync-cloud-bak"

echo "[sstart] provider=$PROV dataset=$ID mode=$MODE"

mkdir -p "$DECRYPT_DATA" "$SYNC_DATA" "$PENDING_ROOT" "$CRYPT_BAK_ROOT" "$SYNC_BAK_ROOT"

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
# PRE-SESSION BACKUP
# -----------------------------
TS="$(timestamp)"

if [ "$MODE" = "--mount" ]; then
    echo "[sstart] Pre-backup (crypt + sync)"

    # crypt pre-backup
    if rclone lsd "$REMOTE_CRYPT_LOCAL:${PROV}-crypt-$ID" >/dev/null 2>&1; then
        BAK_NAME="${PROV}-crypt-bak-$ID-pre-$TS"
        create_backup \
            "$REMOTE_CRYPT_LOCAL:${PROV}-crypt-$ID" \
            "$REMOTE_CRYPT_LOCAL_BAK" \
            "$BAK_NAME"

        # rotate local crypt pre-backups
        rotate_backups "$REMOTE_CRYPT_LOCAL_BAK" "${PROV}-crypt-bak-$ID-pre"
    else
        echo "[sstart] No existing crypt dataset yet, skipping crypt pre-backup"
    fi

    # sync pre-backup
    if rclone lsd "$REMOTE_SYNC_LOCAL:${PROV}-sync-$ID" >/dev/null 2>&1; then
        BAK_NAME="${PROV}-sync-bak-$ID-pre-$TS"
        create_backup \
            "$REMOTE_SYNC_LOCAL:${PROV}-sync-$ID" \
            "$REMOTE_SYNC_LOCAL_BAK" \
            "$BAK_NAME"

        # rotate local sync pre-backups
        rotate_backups "$REMOTE_SYNC_LOCAL_BAK" "${PROV}-sync-bak-$ID-pre"
    else
        echo "[sstart] No existing sync dataset yet, skipping sync pre-backup"
    fi

elif [ "$MODE" = "--sync" ]; then
    echo "[sstart] Pre-backup (sync-only)"

    if rclone lsd "$REMOTE_SYNC_LOCAL:${PROV}-sync-$ID" >/dev/null 2>&1; then
        BAK_NAME="${PROV}-sync-bak-$ID-pre-$TS"
        create_backup \
            "$REMOTE_SYNC_LOCAL:${PROV}-sync-$ID" \
            "$REMOTE_SYNC_LOCAL_BAK" \
            "$BAK_NAME"

        # rotate local sync pre-backups
        rotate_backups "$REMOTE_SYNC_LOCAL_BAK" "${PROV}-sync-bak-$ID-pre"
    else
        echo "[sstart] No existing sync dataset yet, skipping sync pre-backup"
    fi
fi

# After pre-backup, mirror backups to cloud (so pre-safety exists remotely too)
sync_backups_to_cloud "$REMOTE_CRYPT_LOCAL_BAK" "$REMOTE_CRYPT_CLOUD_BAK"
sync_backups_to_cloud "$REMOTE_SYNC_LOCAL_BAK" "$REMOTE_SYNC_CLOUD_BAK"

# Rotate cloud pre-backups as well
rotate_backups "$REMOTE_CRYPT_CLOUD_BAK" "${PROV}-crypt-bak-$ID-pre"
rotate_backups "$REMOTE_SYNC_CLOUD_BAK" "${PROV}-sync-bak-$ID-pre"

# -----------------------------
# SYNC LOGIC
# -----------------------------
if online; then
    echo "[sstart] Online"

    if [ "$MODE" = "--mount" ]; then
        echo "[sstart] Syncing crypt + sync (cloud <-> local)"

        if rclone lsd "$REMOTE_CRYPT_CLOUD:${PROV}-crypt-$ID" >/dev/null 2>&1; then
            rclone sync "$REMOTE_CRYPT_CLOUD:${PROV}-crypt-$ID" \
                        "$REMOTE_CRYPT_LOCAL:${PROV}-crypt-$ID" || true
        else
            echo "[sstart] No crypt dataset on cloud yet, skipping cloud pull"
        fi

        if rclone lsd "$REMOTE_SYNC_CLOUD:${PROV}-sync-$ID" >/dev/null 2>&1; then
            rclone sync "$REMOTE_SYNC_CLOUD:${PROV}-sync-$ID" \
                        "$REMOTE_SYNC_LOCAL:${PROV}-sync-$ID" || true
        else
            echo "[sstart] No sync dataset on cloud yet, skipping cloud pull"
        fi

        if rclone lsd "$REMOTE_CRYPT_LOCAL:${PROV}-crypt-$ID" >/dev/null 2>&1; then
            rclone sync "$REMOTE_CRYPT_LOCAL:${PROV}-crypt-$ID" \
                        "$REMOTE_CRYPT_CLOUD:${PROV}-crypt-$ID" || true
        else
            echo "[sstart] No local crypt dataset yet, skipping push"
        fi

        if rclone lsd "$REMOTE_SYNC_LOCAL:${PROV}-sync-$ID" >/dev/null 2>&1; then
            rclone sync "$REMOTE_SYNC_LOCAL:${PROV}-sync-$ID" \
                        "$REMOTE_SYNC_CLOUD:${PROV}-sync-$ID" || true
        else
            echo "[sstart] No local sync dataset yet, skipping push"
        fi

    else
        echo "[sstart] Syncing sync-only (cloud <-> local)"

        if rclone lsd "$REMOTE_SYNC_CLOUD:${PROV}-sync-$ID" >/dev/null 2>&1; then
            rclone sync "$REMOTE_SYNC_CLOUD:${PROV}-sync-$ID" \
                        "$REMOTE_SYNC_LOCAL:${PROV}-sync-$ID" || true
        else
            echo "[sstart] No sync dataset on cloud yet, skipping cloud pull"
        fi

        if rclone lsd "$REMOTE_SYNC_LOCAL:${PROV}-sync-$ID" >/dev/null 2>&1; then
            rclone sync "$REMOTE_SYNC_LOCAL:${PROV}-sync-$ID" \
                        "$REMOTE_SYNC_CLOUD:${PROV}-sync-$ID" || true
        else
            echo "[sstart] No local sync dataset yet, skipping push"
        fi
    fi

else
    echo "[sstart] Offline, marking pending"
    touch "$PENDING_ROOT/${PROV}-sync-pending-$ID"
    [ "$MODE" = "--mount" ] && touch "$PENDING_ROOT/${PROV}-crypt-pending-$ID"
fi

# -----------------------------
# MOUNT (encrypted datasets only)
# -----------------------------
if [ "$MODE" = "--mount" ]; then
    echo "[sstart] Mounting decrypted view at $DECRYPT_DATA"
    rclone mount "$REMOTE_CRYPT_LOCAL:${PROV}-crypt-$ID" "$DECRYPT_DATA" --daemon
    echo "[sstart] Mounted. Work in: $DECRYPT_DATA"
else
    echo "[sstart] Sync-only session started for $SYNC_DATA"
fi
