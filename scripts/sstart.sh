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
MARKER_DIR="$HOME/.config/sync-bisync"

CRYPT_DIR="$PROV_DIR/crypt"
SYNC_DIR="$PROV_DIR/sync"
DEC_DIR="$PROV_DIR/decrypted"
PENDING_DIR="$PROV_DIR/pending"

DECRYPT_DATA="$DEC_DIR/$ID"

REMOTE_CRYPT_LOCAL="${PROV}-crypt-local"
REMOTE_CRYPT_CLOUD="${PROV}-crypt-cloud"
REMOTE_CRYPT_LOCAL_BAK="${PROV}-crypt-local-bak"
REMOTE_CRYPT_CLOUD_BAK="${PROV}-crypt-cloud-bak"

REMOTE_SYNC_LOCAL="${PROV}-sync-local"
REMOTE_SYNC_CLOUD="${PROV}-sync-cloud"
REMOTE_SYNC_LOCAL_BAK="${PROV}-sync-local-bak"
REMOTE_SYNC_CLOUD_BAK="${PROV}-sync-cloud-bak"

LOCK_FILE="/tmp/sync-${PROV}-${ID}.lock"
META_VERSION="1"

mkdir -p "$CRYPT_DIR" "$SYNC_DIR" "$DEC_DIR" "$PENDING_DIR" "$BAK_DIR" "$MARKER_DIR"

DEVICE_ID_FILE="$HOME/.config/sync-device-id"
if [ ! -f "$DEVICE_ID_FILE" ]; then
    mkdir -p "$(dirname "$DEVICE_ID_FILE")"
    head -c 8 /dev/urandom | base32 | tr -d '=' | tr 'A-Z' 'a-z' > "$DEVICE_ID_FILE"
fi
DEVICE_ID="$(cat "$DEVICE_ID_FILE")"

timestamp() { date +"%Y%m%d-%H%M%S"; }
online() { ping -c1 -W1 8.8.8.8 >/dev/null 2>&1; }

acquire_lock() {
    if [ -e "$LOCK_FILE" ]; then
        echo "[sstart] Lock exists: $LOCK_FILE"
        exit 1
    fi
    echo "$$" > "$LOCK_FILE"
}
release_lock() { rm -f "$LOCK_FILE"; }

create_backup() {
    local src_remote="$1" src_path="$2" dst_remote="$3" dst_path="$4" phase="$5"
    local ts tmp_dir final_dir
    ts="$(timestamp)"
    tmp_dir="$dst_path/${ts}.tmp"
    final_dir="$dst_path/$ts"

    echo "[backup] Creating backup: $dst_remote:$final_dir"
    rclone sync "$src_remote:$src_path" "$dst_remote:$tmp_dir" || true
    rclone check "$src_remote:$src_path" "$dst_remote:$tmp_dir" || true

    local tmpmeta
    tmpmeta="$(mktemp -d)"
    cat > "$tmpmeta/metadata.json" <<EOF
{
  "provider": "$PROV",
  "dataset": "$ID",
  "kind": "backup",
  "phase": "$phase",
  "timestamp": "$ts",
  "version": "$META_VERSION"
}
EOF
    rclone copy "$tmpmeta" "$dst_remote:$tmp_dir" >/dev/null 2>&1 || true
    rm -rf "$tmpmeta"

    rclone moveto "$dst_remote:$tmp_dir" "$dst_remote:$final_dir" || true
}

rotate_backups() {
    local remote="$1" path="$2"
    mapfile -t backups < <(rclone lsf "$remote:$path" --dirs-only 2>/dev/null | sort -r)
    if [ "${#backups[@]}" -gt 5 ]; then
        for old in "${backups[@]:5}"; do
            rclone purge "$remote:$path/$old" || true
        done
    fi
}

bisync_run_with_init() {
    local local_remote="$1" cloud_remote="$2" kind="$3"
    local marker="$MARKER_DIR/${PROV}-${ID}-${kind}.init"

    if [ ! -f "$marker" ]; then
        echo "[bisync] First-time bisync for $kind, running --resync"
        rclone bisync "$local_remote:$ID" "$cloud_remote:$ID" \
            --resync \
            --conflict-suffix ".conflict-$DEVICE_ID-{{timestamp}}" || true
        touch "$marker"
    else
        echo "[bisync] Normal bisync for $kind"
        rclone bisync "$local_remote:$ID" "$cloud_remote:$ID" \
            --conflict-suffix ".conflict-$DEVICE_ID-{{timestamp}}" || true
    fi
}

ensure_dataset_synced_and_bisynced() {
    local local_remote="$1" cloud_remote="$2" local_bak="$3" cloud_bak="$4" kind="$5"

    local local_exists=0 cloud_exists=0

    if rclone lsd "$local_remote:$ID" >/dev/null 2>&1; then
        local_exists=1
    fi
    if rclone lsd "$cloud_remote:$ID" >/dev/null 2>&1; then
        cloud_exists=1
    fi

    if [ "$local_exists" -eq 0 ] && [ "$cloud_exists" -eq 0 ]; then
        echo "[sstart] $kind: neither local nor cloud exists, skipping"
        return
    fi

    if [ "$local_exists" -eq 1 ] && [ "$cloud_exists" -eq 0 ]; then
        echo "[sstart] $kind: local exists, cloud missing -> backup local, sync up, backup cloud, then bisync"
        create_backup "$local_remote" "$ID" "$local_bak" "$ID/pre" "pre-local"
        rclone sync "$local_remote:$ID" "$cloud_remote:$ID"
        create_backup "$cloud_remote" "$ID" "$cloud_bak" "$ID/pre" "pre-cloud"
        bisync_run_with_init "$local_remote" "$cloud_remote" "$kind"
        return
    fi

    if [ "$local_exists" -eq 0 ] && [ "$cloud_exists" -eq 1 ]; then
        echo "[sstart] $kind: cloud exists, local missing -> backup cloud, sync down, backup local, then bisync"
        create_backup "$cloud_remote" "$ID" "$cloud_bak" "$ID/pre" "pre-cloud"
        rclone sync "$cloud_remote:$ID" "$local_remote:$ID"
        create_backup "$local_remote" "$ID" "$local_bak" "$ID/pre" "pre-local"
        bisync_run_with_init "$local_remote" "$cloud_remote" "$kind"
        return
    fi

    echo "[sstart] $kind: both sides exist -> pre-backup then bisync"
    create_backup "$local_remote" "$ID" "$local_bak" "$ID/pre" "pre-local"
    create_backup "$cloud_remote" "$ID" "$cloud_bak" "$ID/pre" "pre-cloud"
    bisync_run_with_init "$local_remote" "$cloud_remote" "$kind"
}

acquire_lock
trap release_lock EXIT

echo "[sstart] provider=$PROV dataset=$ID mode=$MODE device=$DEVICE_ID"

if ! online; then
    echo "[sstart] Offline, skipping sync/bisync; just mounting if requested."
else
    if [ "$MODE" = "--mount" ]; then
        ensure_dataset_synced_and_bisynced "$REMOTE_CRYPT_LOCAL" "$REMOTE_CRYPT_CLOUD" "$REMOTE_CRYPT_LOCAL_BAK" "$REMOTE_CRYPT_CLOUD_BAK" "crypt"
        ensure_dataset_synced_and_bisynced "$REMOTE_SYNC_LOCAL" "$REMOTE_SYNC_CLOUD" "$REMOTE_SYNC_LOCAL_BAK" "$REMOTE_SYNC_CLOUD_BAK" "sync"
    else
        ensure_dataset_synced_and_bisynced "$REMOTE_SYNC_LOCAL" "$REMOTE_SYNC_CLOUD" "$REMOTE_SYNC_LOCAL_BAK" "$REMOTE_SYNC_CLOUD_BAK" "sync"
    fi
fi

if [ "$MODE" = "--mount" ]; then
    echo "[sstart] Mounting decrypted view at $DECRYPT_DATA"
    mkdir -p "$DECRYPT_DATA"
    rclone mount "$REMOTE_CRYPT_LOCAL:$ID" "$DECRYPT_DATA" --daemon
    echo "[sstart] Mounted. Work in: $DECRYPT_DATA"
else
    echo "[sstart] Sync-only session started for provider=$PROV dataset=$ID"
fi
