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

# Backup roots (per provider)
BACKROOT="$HOME/sync-backup/${PROV}-bak"
CRYPT_BAK="$BACKROOT/${PROV}-crypt-bak"

# Backup remotes (rooted at CRYPT_BAK)
LOCAL_CRYPT_BAK="${PROV}-crypt-local-bak:"
CLOUD_CRYPT_BAK="${PROV}-crypt-cloud-bak:"

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

# UNMOUNT
if mountpoint -q "$DECRYPT_DIR"; then
    fusermount -u "$DECRYPT_DIR" || true
    sleep 1
fi

# Remove empty decrypted dirs
if [ -d "$DECRYPT_DIR" ] && [ -z "$(ls -A "$DECRYPT_DIR")" ]; then
    rmdir "$DECRYPT_DIR" 2>/dev/null || true
fi

PARENT_DECRYPT_DIR="$(dirname "$DECRYPT_DIR")"
if [ -d "$PARENT_DECRYPT_DIR" ] && [ -z "$(ls -A "$PARENT_DECRYPT_DIR")" ]; then
    rmdir "$PARENT_DECRYPT_DIR" 2>/dev/null || true
fi

# Remove placeholder if there are other files
if rclone ls "$LOCAL_CRYPT" 2>/dev/null | grep -qv '\.placeholder'; then
    rclone purge "$LOCAL_CRYPT/.placeholder" 2>/dev/null || true
fi

# SYNC LOCAL → CLOUD
if online; then
    rclone sync "$LOCAL_CRYPT" "$CLOUD_CRYPT" || true
else
    mkdir -p "$ROOT/${PROV}-sync-pending"
    touch "$ROOT/${PROV}-sync-pending/${PROV}-${ID}.pending"
fi

# POST-SESSION BACKUP (ONLY IF ENCRYPTED FILES EXIST, RECURSIVELY)
encrypted_files_exist=$(rclone ls "$LOCAL_CRYPT" 2>/dev/null | grep -v '\.placeholder' || true)

if [ -n "$encrypted_files_exist" ]; then
    TS_POST="$(timestamp)-${PROV}-${ID}-post"
    mkdir -p "$CRYPT_BAK/$TS_POST"

    # Backup encrypted files only
    rclone copy "$LOCAL_CRYPT" "${LOCAL_CRYPT_BAK}${TS_POST}" --exclude ".placeholder" || true
    rclone copy "$LOCAL_CRYPT" "${CLOUD_CRYPT_BAK}${TS_POST}" --exclude ".placeholder" || true

    rotate_backups "$CRYPT_BAK"
fi

echo "Stop complete for $PROV dataset $ID (encrypted mode)"
