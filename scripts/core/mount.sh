#!/usr/bin/env bash
set -euo pipefail

mount_decrypted() {
    local remote="$1" mount_dir="$2"

    mkdir -p "$mount_dir"

    if [ "${DRY_RUN:-0}" -eq 1 ]; then
        log "DRY-RUN: rclone mount $remote $mount_dir --daemon"
        return
    fi

    rclone mount "$remote" "$mount_dir" --daemon
    sleep 1

    mountpoint -q "$mount_dir" || {
        log "ERROR: mount failed at $mount_dir"
        exit 1
    }
}

unmount_path() {
    local dir="$1"
    fusermount3 -u "$dir" 2>/dev/null || fusermount -u "$dir" 2>/dev/null || true
}
