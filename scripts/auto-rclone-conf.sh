#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="auto-conf"

# Load core modules
source "$(dirname "$0")/core/env.sh"
source "$(dirname "$0")/core/utils.sh"
source "$(dirname "$0")/core/provider.sh"
source "$(dirname "$0")/core/paths.sh"

CONF="$HOME/.config/rclone/rclone.conf"

# ---------------------------------------------------------
# Helpers specific to auto-rclone-conf
# ---------------------------------------------------------

remote_exists() {
    rclone listremotes 2>/dev/null | grep -q "^$1:"
}

remove_remote() {
    local name="$1"
    local tmp
    tmp="$(mktemp)"

    awk -v sec="[$name]" '
        BEGIN { insec=0 }
        {
            if (substr($0,1,1)=="[") {
                if ($0 == sec) { insec=1; next }
                else insec=0
            }
            if (!insec) print
        }
    ' "$CONF" > "$tmp"

    mv "$tmp" "$CONF"
}

append_remote() {
    {
        echo "$1"
        echo
    } >> "$CONF"
}

ask_skip_overwrite() {
    local label="$1"
    echo "$label already exists." > /dev/tty
    echo "1) Skip (default)" > /dev/tty
    echo "2) Overwrite" > /dev/tty
    read -rp "> " CH < /dev/tty || CH=""
    echo "${CH:-1}"
}

choose_storage_type() {
    echo "Select storage type for base remote:" > /dev/tty
    local types=("drive" "dropbox" "onedrive" "protondrive" "webdav" "s3" "other")
    local i=1
    for t in "${types[@]}"; do
        echo "$i) $t" > /dev/tty
        i=$((i+1))
    done
    read -rp "> " choice < /dev/tty
    choice="${choice:-1}"
    local idx=$((choice-1))
    echo "${types[$idx]}"
}

obscure() {
    rclone obscure "$1"
}

# ---------------------------------------------------------
# Main script
# ---------------------------------------------------------

if [ "$#" -lt 1 ]; then
    echo "Usage: $0 <provider1> [provider2] ..." >&2
    exit 1
fi

mkdir -p "$(dirname "$CONF")"
touch "$CONF"

echo "=== Auto rclone.conf Generator (modular version) ==="
echo "Providers: $*"
echo

for PROV in "$@"; do
    validate_provider "$PROV"

    echo "----------------------------------------"
    echo "Configuring provider: $PROV"
    echo "----------------------------------------"

    # -----------------------------------------------------
    # Base remote creation / overwrite
    # -----------------------------------------------------
    if remote_exists "$PROV"; then
        CH=$(ask_skip_overwrite "Base remote [$PROV]")
        if [ "$CH" = "2" ]; then
            echo "Overwriting base remote [$PROV]" > /dev/tty
            rclone config delete "$PROV" || true

            TYPE=$(choose_storage_type)
            if [[ "$TYPE" == "other" ]]; then
                echo "Launching full rclone config. Create remote named: $PROV" > /dev/tty
                read -rp "Press Enter to start..." _ < /dev/tty
                rclone config
            else
                rclone config create "$PROV" "$TYPE"
            fi
        else
            echo "✔ Keeping existing base remote [$PROV]"
        fi
    else
        TYPE=$(choose_storage_type)
        if [[ "$TYPE" == "other" ]]; then
            echo "Launching full rclone config. Create remote named: $PROV" > /dev/tty
            read -rp "Press Enter to start..." _ < /dev/tty
            rclone config
        else
            rclone config create "$PROV" "$TYPE"
        fi
    fi

    # -----------------------------------------------------
    # Remote names (from provider.sh)
    # -----------------------------------------------------
    REMOTES=(
        "$(crypt_cloud "$PROV")"
        "$(crypt_local "$PROV")"
        "$(crypt_cloud_bak "$PROV")"
        "$(crypt_local_bak "$PROV")"
        "$(sync_cloud "$PROV")"
        "$(sync_local "$PROV")"
        "$(sync_cloud_bak "$PROV")"
        "$(sync_local_bak "$PROV")"
    )

    ACTIONS=()
    NEED_PASS=0

    for R in "${REMOTES[@]}"; do
        if remote_exists "$R"; then
            CH=$(ask_skip_overwrite "Remote [$R]")
            if [ "$CH" = "1" ]; then
                ACTIONS+=("skip")
            else
                ACTIONS+=("overwrite")
                NEED_PASS=1
            fi
        else
            ACTIONS+=("create")
            NEED_PASS=1
        fi
    done

    if [ "$NEED_PASS" -eq 0 ]; then
        echo "✔ All remotes for [$PROV] already exist and were skipped."
        continue
    fi

    # -----------------------------------------------------
    # Password + salt
    # -----------------------------------------------------
    echo > /dev/tty
    echo "Encrypted password setup for provider [$PROV]:" > /dev/tty
    read -s -rp "Enter encryption password: " PLAIN_PASS < /dev/tty
    echo > /dev/tty
    read -s -rp "Enter encryption salt: " PLAIN_SALT < /dev/tty
    echo > /dev/tty

    PASS=$(obscure "$PLAIN_PASS")
    SALT=$(obscure "$PLAIN_SALT")

    # -----------------------------------------------------
    # Create directory structure (paths.sh)
    # -----------------------------------------------------
    mkdir -p \
        "$(provider_crypt_path "$PROV")" \
        "$(provider_sync_path "$PROV")" \
        "$(provider_dec_path "$PROV")" \
        "$(provider_pending_path "$PROV")" \
        "$(provider_backup_crypt "$PROV")" \
        "$(provider_backup_sync "$PROV")"

    # -----------------------------------------------------
    # Create or overwrite remotes
    # -----------------------------------------------------
    for idx in "${!REMOTES[@]}"; do
        R="${REMOTES[$idx]}"
        A="${ACTIONS[$idx]}"

        if [ "$A" = "skip" ]; then
            echo "✔ Skipped $R"
            continue
        fi

        if [ "$A" = "overwrite" ]; then
            remove_remote "$R"
        fi

        case "$R" in
            "$(crypt_cloud "$PROV")")
                append_remote "[$R]
type = crypt
remote = $PROV:data/sync/$PROV/crypt
password = $PASS
password2 = $SALT"
                ;;
            "$(crypt_local "$PROV")")
                append_remote "[$R]
type = crypt
remote = $(provider_crypt_path "$PROV")
password = $PASS
password2 = $SALT"
                ;;
            "$(crypt_cloud_bak "$PROV")")
                append_remote "[$R]
type = crypt
remote = $PROV:data/sync-backup/${PROV}-bak/crypt
password = $PASS
password2 = $SALT"
                ;;
            "$(crypt_local_bak "$PROV")")
                append_remote "[$R]
type = crypt
remote = $(provider_backup_crypt "$PROV")
password = $PASS
password2 = $SALT"
                ;;
            "$(sync_cloud "$PROV")")
                append_remote "[$R]
type = alias
remote = $PROV:data/sync/$PROV/sync"
                ;;
            "$(sync_local "$PROV")")
                append_remote "[$R]
type = alias
remote = $(provider_sync_path "$PROV")"
                ;;
            "$(sync_cloud_bak "$PROV")")
                append_remote "[$R]
type = alias
remote = $PROV:data/sync-backup/${PROV}-bak/sync"
                ;;
            "$(sync_local_bak "$PROV")")
                append_remote "[$R]
type = alias
remote = $(provider_backup_sync "$PROV")"
                ;;
        esac

        echo "✔ Created remote: $R"
    done

    echo
    echo "✔ Provider [$PROV] fully configured."
    echo
done

echo "All providers processed."
echo "You can inspect your config with:  rclone config file"
