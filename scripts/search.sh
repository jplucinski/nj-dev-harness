#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$script_dir/lib.sh"

mode="${1:-live}"
shift || true

path_separator='/'
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) path_separator='//' ;;
esac

rg_roots() {
  local path
  while IFS= read -r path; do
    printf '%s\n' "$(basename "$path")"
  done < <(workplace_project_dirs)
}

reload_search() {
  local query="$1" workplace root
  local -a roots
  need rg
  [ "${#query}" -ge 2 ] || return 0
  workplace="$(workplace_root)"
  (
    cd "$workplace"
    roots=()
    while IFS= read -r root; do
      roots+=("$root")
    done < <(rg_roots)
    rg --line-number --column --no-heading --smart-case --hidden -g '!.git' \
      --path-separator "$path_separator" -- "$query" "${roots[@]}" || true
  )
}

case "$mode" in
  reload)
    reload_search "${DEV_HARNESS_INPUT:-$*}"
    ;;
  live|semantic|index)
    die "Search mode '$mode' is not implemented yet."
    ;;
  *) die "Unknown search mode: $mode" ;;
esac
