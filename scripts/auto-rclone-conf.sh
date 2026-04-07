#!/usr/bin/env bash
set -euo pipefail

# Auto rclone.conf Generator (DATA_ROOT-aware, TTY-safe)

if [ "$#" -lt 1 ]; then
    echo "Usage: $0 <provider1> [provider2] ..."
    exit 1
fi

CONF="$HOME/.config/rclone/rclone.conf"
USERNAME="$(whoami)"
DATA_ROOT="$HOME/data"

mkdir -p "$(dirname "$CONF")"
touch "$CONF"

echo "=== Auto rclone.conf Generator (data/ layout) ==="
echo "Providers: $*"
echo

remote_exists() {
    rclone listremotes 2>/dev/null | grep -q "^$1:"
}

remove_remote() {
    local name="$1"
    local tmp="$CONF.tmp"
    awk -v sec="[$name]" '
        BEGIN { insec=0 }
        {
            if ($0 ~ /^

\[/) {
                if ($0 == sec) { insec=1; next }
                else insec=0
            }
            if (!insec) print
        }
    ' "$CONF" > "$tmp" && mv "$tmp" "$CONF"
}

append_remote() {
    echo "$1" >> "$CONF"
    echo >> "$CONF"
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

for PROV in "$@"; do
    echo "----------------------------------------"
    echo "Configuring provider: $PROV"
    echo "----------------------------------------"

    # Base remote
    if remote_exists "$PROV"; then
        CH=$(ask_skip_overwrite "Base remote [$PROV]")
        if [ "$CH" = "2" ]; then
            rclone config delete "$PROV" || true
            TYPE=$(choose_storage_type)
            if [[ "$TYPE" == "other" ]]; then
                echo "Launching full rclone config. Create remote named: $PROV" > /dev/tty
                read -rp "Press Enter to continue..." _ < /dev/tty
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
            read -rp "Press Enter to continue..." _ < /dev/tty
            rclone config
        else
            rclone config create "$PROV" "$TYPE"
        fi
    fi

    REMOTES=(
        "$PROV-crypt-cloud"
        "$PROV-crypt-local"
        "$PROV-crypt-cloud-bak"
        "$PROV-crypt-local-bak"
        "$PROV-sync-cloud"
        "$PROV-sync-local"
        "$PROV-sync-cloud-bak"
        "$PROV-sync-local-bak"
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
        echo "✔ All remotes for [$PROV] already exist."
        continue
    fi

    echo > /dev/tty
    echo "Encrypted password setup for provider [$PROV]:" > /dev/tty
    read -s -rp "Enter encryption password: " PLAIN_PASS < /dev/tty
    echo > /dev/tty
    read -s -rp "Enter encryption salt: " PLAIN_SALT < /dev/tty
    echo > /dev/tty

    PASS=$(obscure "$PLAIN_PASS")
    SALT=$(obscure "$PLAIN_SALT")

    # Local directory structure
    mkdir -p \
        "$DATA_ROOT/sync/$PROV/${PROV}-crypt" \
        "$DATA_ROOT/sync/$PROV/${PROV}-sync" \
        "$DATA_ROOT/sync/$PROV/${PROV}-decrypt" \
        "$DATA_ROOT/sync/$PROV/${PROV}-pending" \
        "$DATA_ROOT/sync-backup/${PROV}-bak/${PROV}-crypt-bak" \
        "$DATA_ROOT/sync-backup/${PROV}-bak/${PROV}-sync-bak"

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
            "$PROV-crypt-cloud")
                append_remote "[$R]
type = crypt
remote = $PROV:data/sync/$PROV/${PROV}-crypt
password = $PASS
password2 = $SALT"
                ;;
            "$PROV-crypt-local")
                append_remote "[$R]
type = crypt
remote = /home/$USERNAME/data/sync/$PROV/${PROV}-crypt
password = $PASS
password2 = $SALT"
                ;;
            "$PROV-crypt-cloud-bak")
                append_remote "[$R]
type = crypt
remote = $PROV:data/sync-backup/${PROV}-bak/${PROV}-crypt-bak
password = $PASS
password2 = $SALT"
                ;;
            "$PROV-crypt-local-bak")
                append_remote "[$R]
type = crypt
remote = /home/$USERNAME/data/sync-backup/${PROV}-bak/${PROV}-crypt-bak
password = $PASS
password2 = $SALT"
                ;;
            "$PROV-sync-cloud")
                append_remote "[$R]
type = alias
remote = $PROV:data/sync/$PROV/${PROV}-sync"
                ;;
            "$PROV-sync-local")
                append_remote "[$R]
type = alias
remote = /home/$USERNAME/data/sync/$PROV/${PROV}-sync"
                ;;
            "$PROV-sync-cloud-bak")
                append_remote "[$R]
type = alias
remote = $PROV:data/sync-backup/${PROV}-bak/${PROV}-sync-bak"
                ;;
            "$PROV-sync-local-bak")
                append_remote "[$R]
type = alias
remote = /home/$USERNAME/data/sync-backup/${PROV}-bak/${PROV}-sync-bak"
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
