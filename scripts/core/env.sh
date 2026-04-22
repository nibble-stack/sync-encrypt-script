#!/usr/bin/env bash
set -euo pipefail

# Global environment variables shared across all scripts

DATA_ROOT="$HOME/data"
MARKER_DIR="$HOME/.config/sync-bisync"
DEVICE_ID_FILE="$HOME/.config/sync-device-id"
META_VERSION="1"

# Ensure config directories exist
mkdir -p "$HOME/.config"
mkdir -p "$MARKER_DIR"

# Ensure device ID exists
if [ ! -f "$DEVICE_ID_FILE" ]; then
    mkdir -p "$(dirname "$DEVICE_ID_FILE")"
    head -c 8 /dev/urandom | base32 | tr -d '=' | tr 'A-Z' 'a-z' > "$DEVICE_ID_FILE"
fi

DEVICE_ID="$(cat "$DEVICE_ID_FILE")"
