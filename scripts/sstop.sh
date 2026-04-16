#!/usr/bin/env bash
set -euo pipefail

# sstop: stop a session (unmount + sync + post-backup)
# Usage: sstop <provider> <dataset-id> [--dry-run]

DATA_ROOT="$HOME/data"
MARKER_DIR="$HOME/.config/sync-bisync"
DEVICE_ID_FILE="$HOME/.config/sync-device-id"
META_VERSION="1"

log() {
    printf '[sstop] %s\n' "$*" >&2
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

if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
    echo "Usage: $0 <provider> <dataset-id> [--dry-run]" >&2
    exit 1
fi

PROV="$1"
ID="$2"
EXTRA="${3:-}"

sanitize_provider "$PROV"
sanitize_id "$ID"

if [ "$EXTRA" = "--dry-run" ]; then
    DRY_RUN=1
fi

PROV_DIR="$DATA_ROOT/sync/$PROV"
BAK_DIR="$DATA_ROOT/sync-backup/${PROV}-bak"

DEC_DIR="$PROV_DIR/decrypted"
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

mkdir -p "$BAK_DIR" "$MARKER_DIR"

DEVICE_ID="$(cat "$DEVICE_ID_FILE" 2>/dev/null || echo "unknown")"

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
        create_backup "$local_remote" "$ID" "$local_bak" "$ID/post" "post-local"
        run_cmd rclone sync "$local_remote:$ID" "$cloud_remote:$ID"
        create_backup "$cloud_remote" "$ID" "$cloud_bak" "$ID/post" "post-cloud"
        bisync_run_with_init "$local_remote" "$cloud_remote" "$kind"
        return
    fi

    if [ "$local_exists" -eq 0 ] && [ "$cloud_exists" -eq 1 ]; then
        log "$kind: cloud exists, local missing -> backup cloud, sync down, backup local, then bisync"
        create_backup "$cloud_remote" "$ID" "$cloud_bak" "$ID/post" "post-cloud"
        run_cmd rclone sync "$cloud_remote:$ID" "$local_remote:$ID"
        create_backup "$local_remote" "$ID" "$local_bak" "$ID/post" "post-local"
        bisync_run_with_init "$local_remote" "$cloud_remote" "$kind"
        return
    fi

    log "$kind: both sides exist -> post-backup then bisync"
    create_backup "$local_remote" "$ID" "$local_bak" "$ID/post" "post-local"
    create_backup "$cloud_remote" "$ID" "$cloud_bak" "$ID/post" "post-cloud"
    bisync_run_with_init "$local_remote" "$cloud_remote" "$kind"
}

log "Unmounting $DECRYPT_DATA (if mounted)"
if mountpoint -q "$DECRYPT_DATA"; then
    if [ "$DRY_RUN" -eq 1 ]; then
        log "DRY-RUN: fusermount3 -u $DECRYPT_DATA || fusermount -u $DECRYPT_DATA"
    else
        fusermount3 -u "$DECRYPT_DATA" 2>/dev/null || fusermount -u "$DECRYPT_DATA" 2>/dev/null || true
    fi
fi

if ! online; then
    log "Offline, cannot sync/bisync. Leaving lock as-is."
    exit 0
fi

log "Online, syncing and bisyncing (dry-run=$DRY_RUN)"

ensure_dataset_synced_and_bisynced "$REMOTE_CRYPT_LOCAL" "$REMOTE_CRYPT_CLOUD" "$REMOTE_CRYPT_LOCAL_BAK" "$REMOTE_CRYPT_CLOUD_BAK" "crypt"
ensure_dataset_synced_and_bisynced "$REMOTE_SYNC_LOCAL" "$REMOTE_SYNC_CLOUD" "$REMOTE_SYNC_LOCAL_BAK" "$REMOTE_SYNC_CLOUD_BAK" "sync"

# Rotate already done inside create_backup, but keeping explicit calls here is harmless if you prefer:
# rotate_backups "$REMOTE_CRYPT_LOCAL_BAK" "$ID/post"
# rotate_backups "$REMOTE_CRYPT_CLOUD_BAK" "$ID/post"
# rotate_backups "$REMOTE_SYNC_LOCAL_BAK" "$ID/post"
# rotate_backups "$REMOTE_SYNC_CLOUD_BAK" "$ID/post"

if [ "$DRY_RUN" -eq 1 ]; then
    log "DRY-RUN: would remove lock file $LOCK_FILE"
else
    rm -f "$LOCK_FILE"
fi

log "Done."
