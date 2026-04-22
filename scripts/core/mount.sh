#!/usr/bin/env bash
set -euo pipefail

mount_decrypted() {
    local remote="$1" mount_dir="$2"

    # Skip mount entirely on Android
    if android_detect; then
        log "Android detected — skipping mount (FUSE not supported)"
        return
    fi

    mkdir -p "$mount_dir"

    if [ "${DRY_RUN:-0}" -eq 1 ]; then
        log "DRY-RUN: rclone mount $remote $mount_dir --daemon"
        return
    fi

    rclone mount "$remote" "$mount_dir" --daemon
    sleep 1

    # Portable mount check using rclone rc
    if ! rclone rc mount/listmounts 2>/dev/null | grep -q "\"MountPoint\": \"$mount_dir\""; then
        log "ERROR: mount failed at $mount_dir"
        exit 1
    fi
}

unmount_path() {
    local dir="$1"
    fusermount3 -u "$dir" 2>/dev/null || fusermount -u "$dir" 2>/dev/null || true
}
