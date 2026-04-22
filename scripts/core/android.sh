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
# Paths
# ---------------------------------------------------------
android_shared_base() {
    echo "$HOME/storage/shared/data/sync"
}

android_shared_dataset_path() {
    local prov="$1"
    local id="$2"
    echo "$(android_shared_base)/$prov/decrypted/$id"
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
# Mirror decrypted → shared storage (sstart)
# ---------------------------------------------------------
android_mirror_to_shared() {
    local decrypted_dir="$1"
    local prov="$2"
    local id="$3"

    local shared_dir
    shared_dir="$(android_shared_dataset_path "$prov" "$id")"

    log "Android: mirroring decrypted data to shared storage:"
    log "  $decrypted_dir  →  $shared_dir"

    mkdir -p "$shared_dir"

    run_cmd rclone sync "$decrypted_dir/" "$shared_dir/"
}

# ---------------------------------------------------------
# Mirror shared storage → decrypted (sstop)
# ---------------------------------------------------------
android_mirror_from_shared() {
    local decrypted_dir="$1"
    local prov="$2"
    local id="$3"

    local shared_dir
    shared_dir="$(android_shared_dataset_path "$prov" "$id")"

    if [ ! -d "$shared_dir" ]; then
        log "Android: no shared storage directory found, skipping mirror-back."
        return 0
    fi

    log "Android: mirroring shared storage back to decrypted:"
    log "  $shared_dir  →  $decrypted_dir"

    mkdir -p "$decrypted_dir"

    run_cmd rclone sync "$shared_dir/" "$decrypted_dir/"
}

# ---------------------------------------------------------
# Cleanup shared storage (remove decrypted data)
# ---------------------------------------------------------
android_cleanup_shared() {
    local prov="$1"
    local id="$2"

    local shared_dir
    shared_dir="$(android_shared_dataset_path "$prov" "$id")"

    if [ -d "$shared_dir" ]; then
        log "Android: removing decrypted data from shared storage:"
        log "  $shared_dir"
        rm -rf "$shared_dir"
    fi
}
