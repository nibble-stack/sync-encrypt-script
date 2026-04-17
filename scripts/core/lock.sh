#!/usr/bin/env bash
set -euo pipefail

lock_file() {
    # Prefer TMPDIR, then Termux PREFIX/tmp, then HOME/tmp
    local base_tmp

    if [ -n "${TMPDIR-}" ]; then
        base_tmp="$TMPDIR"
    elif [ -n "${PREFIX-}" ]; then
        base_tmp="$PREFIX/tmp"
    else
        base_tmp="$HOME/tmp"
    fi

    echo "$base_tmp/sync-$1-$2.lock"
}

acquire_lock() {
    local lf
    lf="$(lock_file "$1" "$2")"

    # Ensure the directory exists
    mkdir -p "$(dirname "$lf")"

    if [ -e "$lf" ]; then
        echo "Lock exists: $lf" >&2
        exit 1
    fi

    echo "$$" > "$lf"
}

release_lock() {
    rm -f "$(lock_file "$1" "$2")"
}
