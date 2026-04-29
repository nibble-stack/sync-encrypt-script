#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------
# Android detection
# ---------------------------------------------------------
android_detect() {
    case "${PREFIX:-}" in
        */com.termux/*) return 0 ;;
    esac
    return 1
}

# ---------------------------------------------------------
# Shared storage base
# ---------------------------------------------------------
android_shared_base() {
    echo "$HOME/storage/shared/data/sync"
}

# ---------------------------------------------------------
# Crypt dataset shared path
# ---------------------------------------------------------
android_shared_crypt_path() {
    local prov="$1"
    local id="$2"
    echo "$(android_shared_base)/$prov/decrypted/$id"
}

# ---------------------------------------------------------
# Sync-only dataset shared path  (NEW)
# ---------------------------------------------------------
android_shared_sync_path() {
    local prov="$1"
    local id="$2"
    echo "$(android_shared_base)/$prov/sync/$id"
}

# ---------------------------------------------------------
# Ensure shared storage is available
# ---------------------------------------------------------
android_require_storage() {
    if [ ! -d "$HOME/storage/shared" ]; then
        echo "Android detected but shared storage not initialized."
        echo "Run: termux-setup-storage"
        exit 1
    fi
}

# ---------------------------------------------------------
# Mirror decrypted → shared (crypt)
# ---------------------------------------------------------
android_mirror_to_shared() {
    local decrypted_dir="$1"
    local prov="$2"
    local id="$3"

    local shared_dir
    shared_dir="$(android_shared_crypt_path "$prov" "$id")"

    log "Android: mirroring decrypted → shared:"
    log "  $decrypted_dir → $shared_dir"

    mkdir -p "$shared_dir"
    run_cmd rclone sync "$decrypted_dir/" "$shared_dir/"
}

# ---------------------------------------------------------
# Mirror shared → decrypted (crypt)
# ---------------------------------------------------------
android_mirror_from_shared() {
    local decrypted_dir="$1"
    local prov="$2"
    local id="$3"

    local shared_dir
    shared_dir="$(android_shared_crypt_path "$prov" "$id")"

    if [ ! -d "$shared_dir" ]; then
        log "Android: no shared crypt folder found, skipping mirror-back."
        return 0
    fi

    log "Android: mirroring shared → decrypted:"
    log "  $shared_dir → $decrypted_dir"

    mkdir -p "$decrypted_dir"
    run_cmd rclone sync "$shared_dir/" "$decrypted_dir/"
}

# ---------------------------------------------------------
# Cleanup shared crypt folder
# ---------------------------------------------------------
android_cleanup_shared() {
    local prov="$1"
    local id="$2"

    local shared_dir
    shared_dir="$(android_shared_crypt_path "$prov" "$id")"

    if [ -d "$shared_dir" ]; then
        log "Android: removing shared decrypted folder:"
        log "  $shared_dir"
        rm -rf "$shared_dir"
    fi
}

# ---------------------------------------------------------
# NEW: Mirror sync-only → shared
# ---------------------------------------------------------
android_mirror_sync_to_shared() {
    local sync_dir="$1"
    local prov="$2"
    local id="$3"

    local shared_dir
    shared_dir="$(android_shared_sync_path "$prov" "$id")"

    log "Android: mirroring sync-only → shared:"
    log "  $sync_dir → $shared_dir"

    mkdir -p "$shared_dir"
    run_cmd rclone sync "$sync_dir/" "$shared_dir/"
}

# ---------------------------------------------------------
# NEW: Mirror shared → sync-only
# ---------------------------------------------------------
android_mirror_sync_from_shared() {
    local sync_dir="$1"
    local prov="$2"
    local id="$3"

    local shared_dir
    shared_dir="$(android_shared_sync_path "$prov" "$id")"

    if [ ! -d "$shared_dir" ]; then
        log "Android: no shared sync-only folder found, skipping mirror-back."
        return 0
    fi

    log "Android: mirroring shared → sync-only:"
    log "  $shared_dir → $sync_dir"

    mkdir -p "$sync_dir"
    run_cmd rclone sync "$shared_dir/" "$sync_dir/"
}
