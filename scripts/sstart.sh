#!/usr/bin/env bash
set -euo pipefail

# sstart: start a session (encrypted mount or sync-only)
# Usage: sstart <provider> <dataset-id> --mount|--sync [--dry-run]

DATA_ROOT="$HOME/data"
MARKER_DIR="$HOME/.config/sync-bisync"
DEVICE_ID_FILE="$HOME/.config/sync-device-id"
META_VERSION="1"

log() {
    printf '[sstart] %s\n' "$*" >&2
}

DRY_RUN=0

run_cmd() {
    if [ "$DRY_RUN" -eq 1 ]; then
        log "DRY-RUN: $*"
    else
        log "RUN: $*"
        "$@"
    fi
}

timestamp() { date +"%Y%m%d-%H%M%S"; }

online() {
    # Try HTTPS first, fallback to ping
    if curl -s --max-time 3 https://www.google.com >/dev/null 2>&1; then
        return 0
    fi
    ping -c1 -W1 8.8.8.8 >/dev/null 2>&1
}

sanitize_id() {
    local id="$1"
    if [[ ! "$id" =~ ^[A-Za-z0-9._-]+$ ]]; then
        log "ERROR: invalid dataset id '$id' (allowed: A-Za-z0-9._-)"
        exit 1
    fi
}

sanitize_provider() {
    local p="$1"
    if [[ ! "$p" =~ ^[A-Za-z0-9_-]+$ ]]; then
        log "ERROR: invalid provider '$p' (allowed: A-Za-z0-9_-)"
        exit 1
    fi
}

if [ "$#" -lt 3 ] || [ "$#" -gt 4 ]; then
    echo "Usage: $0 <provider> <dataset-id> --mount|--sync [--dry-run]" >&2
    exit 1
fi

PROV="$1"
ID="$2"
MODE="$3"
EXTRA="${4:-}"

sanitize_provider "$PROV"
sanitize_id "$ID"

if [ "$MODE" != "--mount" ] && [ "$MODE" != "--sync" ]; then
    echo "Usage: $0 <provider> <dataset-id> --mount|--sync [--dry-run]" >&2
    exit 1
fi

if [ "$EXTRA" = "--dry-run" ]; then
    DRY_RUN=1
fi

PROV_DIR="$DATA_ROOT/sync/$PROV"
BAK_DIR="$DATA_ROOT/sync-backup/${PROV}-bak"

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

mkdir -p "$CRYPT_DIR" "$SYNC_DIR" "$DEC_DIR" "$PENDING_DIR" "$BAK_DIR" "$MARKER_DIR"

if [ ! -f "$DEVICE_ID_FILE" ]; then
    mkdir -p "$(dirname "$DEVICE_ID_FILE")"
    head -c 8 /dev/urandom | base32 | tr -d '=' | tr 'A-Z' 'a-z' > "$DEVICE_ID_FILE"
fi
DEVICE_ID="$(cat "$DEVICE_ID_FILE")"

acquire_lock() {
    if [ -e "$LOCK_FILE" ]; then
        log "Lock exists: $LOCK_FILE"
        exit 1
    fi
    echo "$$" > "$LOCK_FILE"
}

release_lock() {
    rm -f "$LOCK_FILE"
}

create_backup() {
    local src_remote="$1" src_path="$2" dst_remote="$3" dst_path="$4" phase="$5"
    local ts tmp_dir final_dir tmpmeta
    ts="$(timestamp)"
    tmp_dir="$dst_path/${ts}.tmp"
    final_dir="$dst_path/$ts"

    log "[backup] Creating backup: $dst_remote:$final_dir"
    run_cmd rclone copy "$src_remote:$src_path" "$dst_remote:$tmp_dir" || true

    tmpmeta="$(mktemp -d)"
    trap 'rm -rf "$tmpmeta"' RETURN
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
    run_cmd rclone copy "$tmpmeta" "$dst_remote:$tmp_dir" >/dev/null 2>&1 || true
    rm -rf "$tmpmeta"
    trap - RETURN

    run_cmd rclone moveto "$dst_remote:$tmp_dir" "$dst_remote:$final_dir" || true
    rotate_backups "$dst_remote" "$dst_path"
}

rotate_backups() {
    local remote="$1" path="$2"
    local backups
    mapfile -t backups < <(rclone lsf "$remote:$path" --dirs-only 2>/dev/null | sort -r || true)
    if [ "${#backups[@]}" -gt 5 ]; then
        for old in "${backups[@]:5}"; do
            run_cmd rclone purge "$remote:$path/$old" || true
        done
    fi
}

bisync_run_with_init() {
    local local_remote="$1" cloud_remote="$2" kind="$3"
    local marker="$MARKER_DIR/${PROV}-${ID}-${kind}.init"

    if [ "$DRY_RUN" -eq 1 ]; then
        log "DRY-RUN: bisync $kind (marker: $marker)"
        return 0
    fi

    if [ ! -f "$marker" ]; then
        log "[bisync] First-time bisync for $kind, running --resync"
        rclone bisync "$local_remote:$ID" "$cloud_remote:$ID" \
            --resync \
            --conflict-suffix ".conflict-$DEVICE_ID-{{timestamp}}" || true
        touch "$marker"
    else
        log "[bisync] Normal bisync for $kind"
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
        log "$kind: neither local nor cloud exists, skipping"
        return
    fi

    if [ "$local_exists" -eq 1 ] && [ "$cloud_exists" -eq 0 ]; then
        log "$kind: local exists, cloud missing -> backup local, sync up, backup cloud, then bisync"
        create_backup "$local_remote" "$ID" "$local_bak" "$ID/pre" "pre-local"
        run_cmd rclone sync "$local_remote:$ID" "$cloud_remote:$ID"
        create_backup "$cloud_remote" "$ID" "$cloud_bak" "$ID/pre" "pre-cloud"
        bisync_run_with_init "$local_remote" "$cloud_remote" "$kind"
        return
    fi

    if [ "$local_exists" -eq 0 ] && [ "$cloud_exists" -eq 1 ]; then
        log "$kind: cloud exists, local missing -> backup cloud, sync down, backup local, then bisync"
        create_backup "$cloud_remote" "$ID" "$cloud_bak" "$ID/pre" "pre-cloud"
        run_cmd rclone sync "$cloud_remote:$ID" "$local_remote:$ID"
        create_backup "$local_remote" "$ID" "$local_bak" "$ID/pre" "pre-local"
        bisync_run_with_init "$local_remote" "$cloud_remote" "$kind"
        return
    fi

    log "$kind: both sides exist -> pre-backup then bisync"
    create_backup "$local_remote" "$ID" "$local_bak" "$ID/pre" "pre-local"
    create_backup "$cloud_remote" "$ID" "$cloud_bak" "$ID/pre" "pre-cloud"
    bisync_run_with_init "$local_remote" "$cloud_remote" "$kind"
}

acquire_lock
trap release_lock EXIT

log "provider=$PROV dataset=$ID mode=$MODE device=$DEVICE_ID dry-run=$DRY_RUN"

if ! online; then
    log "Offline, skipping sync/bisync; just mounting if requested."
else
    if [ "$MODE" = "--mount" ]; then
        ensure_dataset_synced_and_bisynced "$REMOTE_CRYPT_LOCAL" "$REMOTE_CRYPT_CLOUD" "$REMOTE_CRYPT_LOCAL_BAK" "$REMOTE_CRYPT_CLOUD_BAK" "crypt"
        ensure_dataset_synced_and_bisynced "$REMOTE_SYNC_LOCAL" "$REMOTE_SYNC_CLOUD" "$REMOTE_SYNC_LOCAL_BAK" "$REMOTE_SYNC_CLOUD_BAK" "sync"
    else
        ensure_dataset_synced_and_bisynced "$REMOTE_SYNC_LOCAL" "$REMOTE_SYNC_CLOUD" "$REMOTE_SYNC_LOCAL_BAK" "$REMOTE_SYNC_CLOUD_BAK" "sync"
    fi
fi

if [ "$MODE" = "--mount" ]; then
    log "Mounting decrypted view at $DECRYPT_DATA"
    mkdir -p "$DECRYPT_DATA"
    if [ "$DRY_RUN" -eq 1 ]; then
        log "DRY-RUN: rclone mount $REMOTE_CRYPT_LOCAL:$ID $DECRYPT_DATA --daemon"
    else
        rclone mount "$REMOTE_CRYPT_LOCAL:$ID" "$DECRYPT_DATA" --daemon
        sleep 1
        if ! mountpoint -q "$DECRYPT_DATA"; then
            log "ERROR: mount failed at $DECRYPT_DATA"
            exit 1
        fi
    fi
    log "Mounted. Work in: $DECRYPT_DATA"
else
    log "Sync-only session started for provider=$PROV dataset=$ID"
fi
