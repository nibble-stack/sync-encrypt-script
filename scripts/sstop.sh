#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="sstop"

# ---------------------------------------------------------
# Load core modules
# ---------------------------------------------------------
BASE_DIR="$(dirname "$0")"
source "$BASE_DIR/core/env.sh"
source "$BASE_DIR/core/utils.sh"
source "$BASE_DIR/core/provider.sh"
source "$BASE_DIR/core/paths.sh"
source "$BASE_DIR/core/lock.sh"
source "$BASE_DIR/core/backup.sh"
source "$BASE_DIR/core/bisync.sh"
source "$BASE_DIR/core/mount.sh"

# ---------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------
if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
    echo "Usage: $0 <provider> <dataset-id> [--dry-run]" >&2
    exit 1
fi

PROV="$1"
ID="$2"
EXTRA="${3:-}"

validate_provider "$PROV"
[[ "$ID" =~ ^[A-Za-z0-9._-]+$ ]] || {
    echo "ERROR: invalid dataset id '$ID'" >&2
    exit 1
}

DRY_RUN=0
[ "$EXTRA" = "--dry-run" ] && DRY_RUN=1

# ---------------------------------------------------------
# Paths
# ---------------------------------------------------------
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
# Unmount decrypted view (if mounted)
# ---------------------------------------------------------
log "Unmounting $DECRYPT_DATA (if mounted)"

if mountpoint -q "$DECRYPT_DATA"; then
    if [ "$DRY_RUN" -eq 1 ]; then
        log "DRY-RUN: fusermount3 -u $DECRYPT_DATA || fusermount -u $DECRYPT_DATA"
    else
        unmount_path "$DECRYPT_DATA"
    fi
fi

# ---------------------------------------------------------
# Offline behavior
# ---------------------------------------------------------
if ! online; then
    log "Offline, cannot sync/bisync. Leaving lock as-is."
    exit 0
fi

log "Online, syncing and bisyncing (dry-run=$DRY_RUN)"

# ---------------------------------------------------------
# Post-backup + bisync for crypt dataset
# ---------------------------------------------------------
ensure_dataset_synced_and_bisynced \
    "$REMOTE_CRYPT_LOCAL" "$REMOTE_CRYPT_CLOUD" \
    "$REMOTE_CRYPT_LOCAL_BAK" "$REMOTE_CRYPT_CLOUD_BAK" \
    "crypt"

# ---------------------------------------------------------
# Post-backup + bisync for sync dataset
# ---------------------------------------------------------
ensure_dataset_synced_and_bisynced \
    "$REMOTE_SYNC_LOCAL" "$REMOTE_SYNC_CLOUD" \
    "$REMOTE_SYNC_LOCAL_BAK" "$REMOTE_SYNC_CLOUD_BAK" \
    "sync"

# ---------------------------------------------------------
# Remove lock
# ---------------------------------------------------------
if [ "$DRY_RUN" -eq 1 ]; then
    log "DRY-RUN: would remove lock file $(lock_file "$PROV" "$ID")"
else
    release_lock "$PROV" "$ID"
fi

log "Done."
