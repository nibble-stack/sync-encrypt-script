#!/usr/bin/env bash
set -euo pipefail

provider_root()           { echo "$DATA_ROOT/sync/$1"; }
provider_crypt_path()     { echo "$DATA_ROOT/sync/$1/crypt"; }
provider_sync_path()      { echo "$DATA_ROOT/sync/$1/sync"; }
provider_dec_path()       { echo "$DATA_ROOT/sync/$1/decrypted"; }
provider_pending_path()   { echo "$DATA_ROOT/sync/$1/pending"; }

provider_backup_root()    { echo "$DATA_ROOT/sync-backup/$1-bak"; }
provider_backup_crypt()   { echo "$DATA_ROOT/sync-backup/$1-bak/crypt"; }
provider_backup_sync()    { echo "$DATA_ROOT/sync-backup/$1-bak/sync"; }

backup_mount_root()       { echo "$HOME/data/decrypted-backups/$1/$2"; }
