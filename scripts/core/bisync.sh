#!/usr/bin/env bash
set -euo pipefail

bisync_run() {
    local local_remote="$1" cloud_remote="$2" kind="$3"
    local marker="$MARKER_DIR/${PROV}-${ID}-${kind}.init"

    if [ "${DRY_RUN:-0}" -eq 1 ]; then
        log "DRY-RUN: bisync $kind"
        return
    fi

    local suffix=".conflict-${PROV}-${ID}-${DEVICE_ID}-{{timestamp}}"

    if [ ! -f "$marker" ]; then
        log "[bisync] First-time bisync for $kind"
        rclone bisync "$local_remote:$ID" "$cloud_remote:$ID" \
            --resync \
            --conflict-suffix "$suffix" || true
        touch "$marker"
    else
        log "[bisync] Normal bisync for $kind"
        if [ "${ALLOW_FORCE:-0}" -eq 1 ]; then
            FORCE_FLAG="--force"
        else
            FORCE_FLAG=""
        fi
        rclone bisync "$local_remote:$ID" "$cloud_remote:$ID" \
            --conflict-suffix "$suffix" \
            $FORCE_FLAG || true
    fi
}
