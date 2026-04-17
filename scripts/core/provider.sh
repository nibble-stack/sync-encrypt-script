#!/usr/bin/env bash
set -euo pipefail

validate_provider() {
    local p="$1"
    [[ "$p" =~ ^[A-Za-z0-9_-]+$ ]] || {
        echo "ERROR: invalid provider '$p'" >&2
        exit 1
    }
}

# Remote name helpers
crypt_local()        { echo "$1-crypt-local"; }
crypt_cloud()        { echo "$1-crypt-cloud"; }
crypt_local_bak()    { echo "$1-crypt-local-bak"; }
crypt_cloud_bak()    { echo "$1-crypt-cloud-bak"; }

sync_local()         { echo "$1-sync-local"; }
sync_cloud()         { echo "$1-sync-cloud"; }
sync_local_bak()     { echo "$1-sync-local-bak"; }
sync_cloud_bak()     { echo "$1-sync-cloud-bak"; }
