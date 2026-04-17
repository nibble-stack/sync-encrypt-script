#!/usr/bin/env bash
set -euo pipefail

lock_file() {
    echo "/tmp/sync-$1-$2.lock"
}

acquire_lock() {
    local lf
    lf="$(lock_file "$1" "$2")"
    if [ -e "$lf" ]; then
        echo "Lock exists: $lf" >&2
        exit 1
    fi
    echo "$$" > "$lf"
}

release_lock() {
    rm -f "$(lock_file "$1" "$2")"
}
