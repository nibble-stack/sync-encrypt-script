#!/usr/bin/env bash
set -euo pipefail

# Create a single timestamped backup (snapshot) on one remote
create_backup() {
    local src_remote="$1" src_path="$2"
    local dst_remote="$3" dst_path="$4"
    local phase="$5"

    local ts tmp_dir final_dir
    ts="$(timestamp)"
    tmp_dir="$dst_path/${ts}.tmp"
    final_dir="$dst_path/$ts"

    # Snapshot copy
    run_cmd rclone copy "$src_remote:$src_path" "$dst_remote:$tmp_dir" || true

    # metadata.json
    local tmpmeta
    tmpmeta="$(mktemp -d)"
    cat > "$tmpmeta/metadata.json" <<EOF
{
  "provider": "$PROV",
  "dataset": "$ID",
  "kind": "backup",
  "phase": "$phase",
  "timestamp": "$ts",
  "version": "$META_VERSION"
}
EOF

    run_cmd rclone copy "$tmpmeta" "$dst_remote:$tmp_dir" >/dev/null 2>&1 || true
    rm -rf "$tmpmeta"

    run_cmd rclone moveto "$dst_remote:$tmp_dir" "$dst_remote:$final_dir" || true

    rotate_backups "$dst_remote" "$dst_path"
}

# Keep only the newest 3 backups
rotate_backups() {
    local remote="$1" path="$2"
    mapfile -t backups < <(rclone lsf "$remote:$path" --dirs-only 2>/dev/null | sort -r || true)

    if [ "${#backups[@]}" -gt 3 ]; then
        for old in "${backups[@]:3}"; do
            run_cmd rclone purge "$remote:$path/$old" || true
        done
    fi
}

# Backup both local and cloud sides (same dataset) with rotation
backup_both_sides() {
    local local_remote="$1" cloud_remote="$2"
    local local_bak="$3" cloud_bak="$4"
    local phase="$5"

    # Local encrypted/sync → local backup
    create_backup "$local_remote" "$ID" "$local_bak" "$ID" "$phase-local"

    # Cloud encrypted/sync → cloud backup
    create_backup "$cloud_remote" "$ID" "$cloud_bak" "$ID" "$phase-cloud"
}
