#!/usr/bin/env bash
set -euo pipefail

create_backup() {
    local src_remote="$1" src_path="$2"
    local dst_remote="$3" dst_path="$4"
    local phase="$5"

    local ts tmp_dir final_dir
    ts="$(timestamp)"
    tmp_dir="$dst_path/${ts}.tmp"
    final_dir="$dst_path/$ts"

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

rotate_backups() {
    local remote="$1" path="$2"
    mapfile -t backups < <(rclone lsf "$remote:$path" --dirs-only 2>/dev/null | sort -r || true)

    if [ "${#backups[@]}" -gt 5 ]; then
        for old in "${backups[@]:5}"; do
            run_cmd rclone purge "$remote:$path/$old" || true
        done
    fi
}
