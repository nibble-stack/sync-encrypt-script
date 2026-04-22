#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="sstop"

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

# ---------------------------------------------------------
# Unmount decrypted view (Linux/macOS only)
# ---------------------------------------------------------
log "Unmounting $DECRYPT_DATA (if mounted)"

if ! android_detect && mountpoint -q "$DECRYPT_DATA"; then
    if [ "$DRY_RUN" -eq 1 ]; then
        log "DRY-RUN: unmount $DECRYPT_DATA"
    else
        unmount_path "$DECRYPT_DATA"
    fi
fi

# ---------------------------------------------------------
# ANDROID: Sync shared storage → decrypted BEFORE encrypting
# ---------------------------------------------------------
if android_detect; then
    log "Android detected — syncing shared storage back to decrypted"
    android_require_storage
    android_mirror_from_shared "$DECRYPT_DATA" "$PROV" "$ID"
fi

# ---------------------------------------------------------
# Encrypt decrypted → crypt (Android only; Linux uses mount)
# ---------------------------------------------------------
if android_detect; then
    log "Android: encrypting decrypted data back into crypt remote"
    run_cmd rclone sync "$DECRYPT_DATA" "$REMOTE_CRYPT_LOCAL:$ID"
fi

# ---------------------------------------------------------
# Offline behavior
# ---------------------------------------------------------
if ! online; then
    log "Offline, cannot backup/bisync. Leaving lock as-is."
    exit 0
fi

log "Online, running post-backup and bisync for crypt (dry-run=$DRY_RUN)"

# ---------------------------------------------------------
# Post-backup + bisync for crypt dataset
# ---------------------------------------------------------
backup_both_sides "$REMOTE_CRYPT_LOCAL" "$REMOTE_CRYPT_CLOUD" \
    "$REMOTE_CRYPT_LOCAL_BAK" "$REMOTE_CRYPT_CLOUD_BAK" \
    "post-crypt"

bisync_run "$REMOTE_CRYPT_LOCAL" "$REMOTE_CRYPT_CLOUD" "crypt"

# ---------------------------------------------------------
# ANDROID: Cleanup shared storage + wipe decrypted
# ---------------------------------------------------------
if android_detect; then
    log "Android detected — cleaning decrypted data from shared storage"
    android_cleanup_shared "$PROV" "$ID"

    log "Android detected — wiping decrypted local directory"
    rm -rf "$DECRYPT_DATA"
fi

# ---------------------------------------------------------
# Remove lock
# ---------------------------------------------------------
if [ "$DRY_RUN" -eq 1 ]; then
    log "DRY-RUN: would remove lock file $(lock_file "$PROV" "$ID")"
else
    release_lock "$PROV" "$ID"
fi

log "Done."
