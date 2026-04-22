#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="sstart"

# ---------------------------------------------------------
# Load core modules
# ---------------------------------------------------------
SCRIPT_PATH="$(readlink -f "$0")"
BASE_DIR="$(dirname "$SCRIPT_PATH")"
source "$BASE_DIR/core/env.sh"
source "$BASE_DIR/core/utils.sh"
source "$BASE_DIR/core/provider.sh"
source "$BASE_DIR/core/paths.sh"
source "$BASE_DIR/core/lock.sh"
source "$BASE_DIR/core/backup.sh"
source "$BASE_DIR/core/bisync.sh"
source "$BASE_DIR/core/mount.sh"
source "$BASE_DIR/core/android.sh"

# ---------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------
if [ "$#" -lt 3 ] || [ "$#" -gt 4 ]; then
    echo "Usage: $0 <provider> <dataset-id> --mount|--sync [--dry-run]" >&2
    exit 1
fi

PROV="$1"
ID="$2"
MODE="$3"
EXTRA="${4:-}"

validate_provider "$PROV"
[[ "$ID" =~ ^[A-Za-z0-9._-]+$ ]] || {
    echo "ERROR: invalid dataset id '$ID'" >&2
    exit 1
}

if [ "$MODE" != "--mount" ] && [ "$MODE" != "--sync" ]; then
    echo "Usage: $0 <provider> <dataset-id> --mount|--sync [--dry-run]" >&2
    exit 1
fi

DRY_RUN=0
[ "$EXTRA" = "--dry-run" ] && DRY_RUN=1

# ---------------------------------------------------------
# Paths
# ---------------------------------------------------------
PROV_ROOT="$(provider_root "$PROV")"
CRYPT_DIR="$(provider_crypt_path "$PROV")"
SYNC_DIR="$(provider_sync_path "$PROV")"
DEC_DIR="$(provider_dec_path "$PROV")"

DECRYPT_DATA="$DEC_DIR/$ID"

# ---------------------------------------------------------
# Remote names
# ---------------------------------------------------------
REMOTE_CRYPT_LOCAL="$(crypt_local "$PROV")"
REMOTE_CRYPT_CLOUD="$(crypt_cloud "$PROV")"
REMOTE_CRYPT_LOCAL_BAK="$(crypt_local_bak "$PROV")"
REMOTE_CRYPT_CLOUD_BAK="$(crypt_cloud_bak "$PROV")"

REMOTE_SYNC_LOCAL="$(sync_local "$PROV")"
REMOTE_SYNC_CLOUD="$(sync_cloud "$PROV")"
REMOTE_SYNC_LOCAL_BAK="$(sync_local_bak "$PROV")"
REMOTE_SYNC_CLOUD_BAK="$(sync_cloud_bak "$PROV")"

# ---------------------------------------------------------
# Sync-only dataset validation
# ---------------------------------------------------------
if [ "$MODE" = "--sync" ]; then
    LOCAL_SYNC_DIR="$SYNC_DIR/$ID"
    if [ ! -d "$LOCAL_SYNC_DIR" ]; then
        echo "[sstart] Local sync dataset folder not found:"
        echo "         $LOCAL_SYNC_DIR"
        echo
        echo "[sstart] To create a new sync-only dataset:"
        echo "         mkdir -p $LOCAL_SYNC_DIR"
        echo "         Put your files inside it"
        echo "         Run again: ./sstart.sh $PROV $ID --sync"
        exit 1
    fi
fi

# ---------------------------------------------------------
# Ensure directories exist
# ---------------------------------------------------------
mkdir -p "$CRYPT_DIR" "$SYNC_DIR" "$DEC_DIR"

# ---------------------------------------------------------
# Lock handling
# ---------------------------------------------------------
acquire_lock "$PROV" "$ID"
trap 'release_lock "$PROV" "$ID"' EXIT

log "provider=$PROV dataset=$ID mode=$MODE device=$DEVICE_ID dry-run=$DRY_RUN"

# ---------------------------------------------------------
# Online/offline behavior
# ---------------------------------------------------------
if ! online; then
    log "Offline, skipping bisync/backup; only local operations will run."
else
    if [ "$MODE" = "--mount" ]; then
        # crypt dataset only
        bisync_run "$REMOTE_CRYPT_LOCAL" "$REMOTE_CRYPT_CLOUD" "crypt"
    else
        # sync-only dataset
        bisync_run "$REMOTE_SYNC_LOCAL" "$REMOTE_SYNC_CLOUD" "sync"
        backup_both_sides "$REMOTE_SYNC_LOCAL" "$REMOTE_SYNC_CLOUD" \
            "$REMOTE_SYNC_LOCAL_BAK" "$REMOTE_SYNC_CLOUD_BAK" \
            "post-sync"
    fi
fi

# ---------------------------------------------------------
# Decrypt or mount decrypted view
# ---------------------------------------------------------
if [ "$MODE" = "--mount" ]; then
    if android_detect; then
        log "Android detected — decrypting without mount"
        run_cmd rclone sync "$REMOTE_CRYPT_LOCAL:$ID" "$DECRYPT_DATA"
        log "Decrypted data ready at $DECRYPT_DATA"

        log "Android detected — enabling shared-storage mirroring"
        android_require_storage
        android_mirror_to_shared "$DECRYPT_DATA" "$PROV" "$ID"
        log "Android mirror ready at: $(android_shared_dataset_path "$PROV" "$ID")"
    else
        log "Mounting decrypted view at $DECRYPT_DATA"
        mount_decrypted "$REMOTE_CRYPT_LOCAL:$ID" "$DECRYPT_DATA"
        log "Mounted. Work in: $DECRYPT_DATA"
    fi
else
    log "Sync-only session started for provider=$PROV dataset=$ID"
fi
