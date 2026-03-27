#!/usr/bin/env bash
set -euo pipefail

timestamp() {
  date +"%Y%m%d-%H%M%S"
}

ensure_local_dir() {
  local dir="$1"
  mkdir -p "$dir"
}

ensure_cloud_dir() {
  local remote="$1"
  local path="$2"
  rclone mkdir "${remote}:${path}" >/dev/null 2>&1 || true
}

rotate_local_backups() {
  local base_dir="$1"
  [[ ! -d "$base_dir" ]] && return 0

  mapfile -t dirs < <(find "$base_dir" -mindepth 1 -maxdepth 1 -type d | sort -r)
  local count=${#dirs[@]}
  (( count <= 5 )) && return 0

  for ((i=5; i<count; i++)); do
    rm -rf -- "${dirs[$i]}"
  done
}

rotate_cloud_backups() {
  local remote="$1"
  local path="$2"

  mapfile -t dirs < <(rclone lsd "${remote}:${path}" | awk '{print $5}' | sort -r)
  local count=${#dirs[@]}
  (( count <= 5 )) && return 0

  for ((i=5; i<count; i++)); do
    rclone purge "${remote}:${path}/${dirs[$i]}"
  done
}
