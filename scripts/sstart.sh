#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

if [[ $# -lt 2 ]]; then
  echo "Usage: sstart.sh <provider> <id> [--mount]"
  exit 1
fi

PROV="$1"
ID="$2"
MODE="${3:-}"

BASE="$HOME/sync/$PROV"
BACKUP_BASE="$HOME/sync-backup/$PROV-bak"

CRYPT_DIR="$BASE/${PROV}-crypt/${PROV}-crypt-$ID"
DECRYPT_DIR="$BASE/${PROV}-decrypt/${PROV}-decrypt-$ID"
SYNC_DIR="$BASE/${PROV}-sync/${PROV}-sync-$ID"

# rclone remotes
CRYPT_CLOUD="${PROV}-crypt-cloud"
CRYPT_LOCAL="${PROV}-crypt-local"
SYNC_CLOUD="${PROV}-sync-cloud"
SYNC_LOCAL="${PROV}-sync-local"

# Determine type
if [[ -d "$CRYPT_DIR" ]]; then
  TYPE="crypt"
elif [[ -d "$SYNC_DIR" ]]; then
  TYPE="sync"
else
  echo "No dataset found. Creating new dataset: $PROV-$ID"
  TYPE="crypt"
  ensure_local_dir "$CRYPT_DIR"
fi

echo "Starting $TYPE dataset: $PROV-$ID"

if [[ "$TYPE" == "crypt" ]]; then
  ensure_cloud_dir "$CRYPT_CLOUD" "${PROV}-crypt-$ID"

  echo "Syncing encrypted dataset (cloud → local)"
  rclone sync "${CRYPT_CLOUD}:${PROV}-crypt-$ID" "$CRYPT_DIR"

  echo "Syncing encrypted dataset (local → cloud)"
  rclone sync "$CRYPT_DIR" "${CRYPT_CLOUD}:${PROV}-crypt-$ID"

  if [[ "$MODE" == "--mount" ]]; then
    ensure_local_dir "$DECRYPT_DIR"
    echo "Mounting decrypted view"
    rclone mount "${CRYPT_LOCAL}:${PROV}-crypt-$ID" "$DECRYPT_DIR" --daemon
  fi

else
  ensure_cloud_dir "$SYNC_CLOUD" "${PROV}-sync-$ID"
  echo "Syncing plain dataset (cloud → local)"
  rclone sync "${SYNC_CLOUD}:${PROV}-sync-$ID" "$SYNC_DIR"
fi
