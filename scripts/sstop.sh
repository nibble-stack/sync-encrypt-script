#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

if [[ $# -lt 2 ]]; then
  echo "Usage: sstop.sh <provider> <id> [--umount]"
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

CRYPT_CLOUD="${PROV}-crypt-cloud"
CRYPT_LOCAL="${PROV}-crypt-local"
CRYPT_CLOUD_BAK="${PROV}-crypt-cloud-bak"
CRYPT_LOCAL_BAK="${PROV}-crypt-local-bak"

SYNC_CLOUD="${PROV}-sync-cloud"
SYNC_LOCAL="${PROV}-sync-local"
SYNC_CLOUD_BAK="${PROV}-sync-cloud-bak"
SYNC_LOCAL_BAK="${PROV}-sync-local-bak"

TS="$(timestamp)"

if [[ -d "$CRYPT_DIR" ]]; then
  TYPE="crypt"
elif [[ -d "$SYNC_DIR" ]]; then
  TYPE="sync"
else
  echo "Dataset not found"
  exit 1
fi

echo "Stopping $TYPE dataset: $PROV-$ID"

if [[ "$TYPE" == "crypt" ]]; then
  if [[ "$MODE" == "--umount" ]]; then
    fusermount -u "$DECRYPT_DIR" 2>/dev/null || true
  fi

  echo "Final sync (local → cloud)"
  rclone sync "$CRYPT_DIR" "${CRYPT_CLOUD}:${PROV}-crypt-$ID"

  ensure_local_dir "$CRYPT_LOCAL_BAK/${PROV}-crypt-$ID/$TS"
  rsync -a --delete "$CRYPT_DIR/" "$CRYPT_LOCAL_BAK/${PROV}-crypt-$ID/$TS/"
  rotate_local_backups "$CRYPT_LOCAL_BAK/${PROV}-crypt-$ID"

  ensure_cloud_dir "$CRYPT_CLOUD_BAK" "${PROV}-crypt-$ID/$TS"
  rclone sync "$CRYPT_DIR" "${CRYPT_CLOUD_BAK}:${PROV}-crypt-$ID/$TS"
  rotate_cloud_backups "$CRYPT_CLOUD_BAK" "${PROV}-crypt-$ID"

else
  echo "Final sync (local → cloud)"
  rclone sync "$SYNC_DIR" "${SYNC_CLOUD}:${PROV}-sync-$ID"

  ensure_local_dir "$SYNC_LOCAL_BAK/${PROV}-sync-$ID/$TS"
  rsync -a --delete "$SYNC_DIR/" "$SYNC_LOCAL_BAK/${PROV}-sync-$ID/$TS/"
  rotate_local_backups "$SYNC_LOCAL_BAK/${PROV}-sync-$ID"

  ensure_cloud_dir "$SYNC_CLOUD_BAK" "${PROV}-sync-$ID/$TS"
  rclone sync "$SYNC_DIR" "${SYNC_CLOUD_BAK}:${PROV}-sync-$ID/$TS"
  rotate_cloud_backups "$SYNC_CLOUD_BAK" "${PROV}-sync-$ID"
fi
