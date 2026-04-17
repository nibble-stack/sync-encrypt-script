#!/usr/bin/env bash
set -euo pipefail

bisync_run() {
    local local_remote="$1" cloud_remote="$2" kind="$3"
    local marker="$MARKER_DIR/${PROV}-${ID}-${kind}.init"

    if [ "${DRY_RUN:-0}" -eq 1 ]; then
        log "DRY-RUN: bisync $kind"
        return
    fi

    if [ ! -f "$marker" ]; then
        log "[bisync] First-time bisync for $kind"
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
    local local_remote="$1" cloud_remote="$2"
    local local_bak="$3" cloud_bak="$4"
    local kind="$5"

    local local_exists=0 cloud_exists=0

    rclone lsd "$local_remote:$ID" >/dev/null 2>&1 && local_exists=1
    rclone lsd "$cloud_remote:$ID" >/dev/null 2>&1 && cloud_exists=1

    if [ "$local_exists" -eq 0 ] && [ "$cloud_exists" -eq 0 ]; then
        log "$kind: neither side exists, skipping"
        return
    fi

    if [ "$local_exists" -eq 1 ] && [ "$cloud_exists" -eq 0 ]; then
        create_backup "$local_remote" "$ID" "$local_bak" "$ID/pre" "pre-local"
        run_cmd rclone sync "$local_remote:$ID" "$cloud_remote:$ID"
        create_backup "$cloud_remote" "$ID" "$cloud_bak" "$ID/pre" "pre-cloud"
        bisync_run "$local_remote" "$cloud_remote" "$kind"
        return
    fi

    if [ "$local_exists" -eq 0 ] && [ "$cloud_exists" -eq 1 ]; then
        create_backup "$cloud_remote" "$ID" "$cloud_bak" "$ID/pre" "pre-cloud"
        run_cmd rclone sync "$cloud_remote:$ID" "$local_remote:$ID"
        create_backup "$local_remote" "$ID" "$local_bak" "$ID/pre" "pre-local"
        bisync_run "$local_remote" "$cloud_remote" "$kind"
        return
    fi

    create_backup "$local_remote" "$ID" "$local_bak" "$ID/pre" "pre-local"
    create_backup "$cloud_remote" "$ID" "$cloud_bak" "$ID/pre" "pre-cloud"
    bisync_run "$local_remote" "$cloud_remote" "$kind"
}
