#!/usr/bin/env bash
set -euo pipefail

log() {
    printf '[%s] %s\n' "$SCRIPT_NAME" "$*" >&2
}

timestamp() {
    date +"%Y%m%d-%H%M%S"
}

online() {
    curl -s --max-time 3 https://www.google.com >/dev/null 2>&1 \
        || ping -c1 -W1 8.8.8.8 >/dev/null 2>&1
}

run_cmd() {
    if [ "${DRY_RUN:-0}" -eq 1 ]; then
        log "DRY-RUN: $*"
    else
        log "RUN: $*"
        "$@"
    fi
}
