#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 1 ]; then
    echo "Usage: $0 <provider1> [provider2] ..."
    exit 1
fi

CONF="$HOME/.config/rclone/rclone.conf"
USERNAME="$(whoami)"

mkdir -p "$(dirname "$CONF")"
touch "$CONF"

echo "=== Auto rclone.conf Generator (hybrid) ==="
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
            if (substr($0,1,1)=="[") {
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
    echo "$label already exists." >&2
    echo "1) Skip (default)" >&2
    echo "2) Overwrite" >&2
    read -rp "> " CH || CH=""
    echo "${CH:-1}"
}

choose_storage_type() {
    echo "Select storage type for base remote:" >&2
    local types=("drive" "dropbox" "onedrive" "protondrive" "webdav" "s3" "other")
    local i=1
    for t in "${types[@]}"; do
        echo "$i) $t" >&2
        i=$((i+1))
    done
    read -rp "> " choice
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

    # BASE REMOTE HANDLING
    if remote_exists "$PROV"; then
        CH=$(ask_skip_overwrite "Base remote [$PROV]")
        if [ "$CH" = "2" ]; then
            echo "Overwriting base remote [$PROV] via rclone."
            rclone config delete "$PROV" || true
            TYPE=$(choose_storage_type)
            if [[ "$TYPE" == "other" ]]; then
                echo
                echo "Launching full rclone config. Create a remote named: $PROV"
                echo "When done, exit rclone config and return here."
                read -rp "Press Enter to start rclone config..." _
                rclone config
            else
                echo "Creating base remote [$PROV] of type [$TYPE] via rclone config create."
                rclone config create "$PROV" "$TYPE"
            fi
        else
            echo "✔ Keeping existing base remote [$PROV]"
        fi
    else
        echo "Base remote [$PROV] does not exist."
        TYPE=$(choose_storage_type)
        if [[ "$TYPE" == "other" ]]; then
            echo
            echo "Launching full rclone config. Create a remote named: $PROV"
            echo "When done, exit rclone config and return here."
            read -rp "Press Enter to start rclone config..." _
            rclone config
        else
            echo "Creating base remote [$PROV] of type [$TYPE] via rclone config create."
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

    ACTIONS=()   # parallel to REMOTES: skip | create | overwrite
    NEED_PASS=0

    # First pass: decide what to do for each remote
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

    # If nothing to do, skip password and creation
    if [ "$NEED_PASS" -eq 0 ]; then
        echo
        echo "✔ All remotes for [$PROV] already exist and were skipped."
        echo
        continue
    fi

    echo
    echo "Encrypted password setup for provider [$PROV]:"
    read -s -rp "Enter plain-text password: " PLAIN_PASS
    echo
    read -s -rp "Enter plain-text salt: " PLAIN_SALT
    echo

    PASS=$(obscure "$PLAIN_PASS")
    SALT=$(obscure "$PLAIN_SALT")

    mkdir -p \
        "$HOME/sync/$PROV/${PROV}-crypt" \
        "$HOME/sync/$PROV/${PROV}-sync" \
        "$HOME/sync/$PROV/${PROV}-decrypt" \
        "$HOME/sync/$PROV/${PROV}-sync-pending" \
        "$HOME/sync-backup/${PROV}-bak/${PROV}-crypt-bak" \
        "$HOME/sync-backup/${PROV}-bak/${PROV}-sync-bak"

    # Second pass: apply actions
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
remote = $PROV:sync/$PROV/${PROV}-crypt
password = $PASS
password2 = $SALT"
                ;;
            "$PROV-crypt-local")
                append_remote "[$R]
type = crypt
remote = /home/$USERNAME/sync/$PROV/${PROV}-crypt
password = $PASS
password2 = $SALT"
                ;;
            "$PROV-crypt-cloud-bak")
                append_remote "[$R]
type = crypt
remote = $PROV:sync-backup/${PROV}-bak/${PROV}-crypt-bak
password = $PASS
password2 = $SALT"
                ;;
            "$PROV-crypt-local-bak")
                append_remote "[$R]
type = crypt
remote = /home/$USERNAME/sync-backup/${PROV}-bak/${PROV}-crypt-bak
password = $PASS
password2 = $SALT"
                ;;
            "$PROV-sync-cloud")
                append_remote "[$R]
type = alias
remote = $PROV:sync/$PROV/${PROV}-sync"
                ;;
            "$PROV-sync-local")
                append_remote "[$R]
type = alias
remote = /home/$USERNAME/sync/$PROV/${PROV}-sync"
                ;;
            "$PROV-sync-cloud-bak")
                append_remote "[$R]
type = alias
remote = $PROV:sync-backup/${PROV}-bak/${PROV}-sync-bak"
                ;;
            "$PROV-sync-local-bak")
                append_remote "[$R]
type = alias
remote = /home/$USERNAME/sync-backup/${PROV}-bak/${PROV}-sync-bak"
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
