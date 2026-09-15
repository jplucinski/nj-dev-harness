#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$script_dir/lib.sh"

mode="${1:-print}"
workplace_root >/dev/null
need fzf

rows="$(
  while IFS= read -r path; do
    printf '%s\t%s\n' "$(basename "$path")" "$path"
  done < <(workplace_project_dirs)
)"
selected="$(printf '%s\n' "$rows" | fzf \
  --delimiter=$'\t' \
  --with-nth=1 \
  --expect=ctrl-o,ctrl-y \
  --header='Enter: select · Ctrl-O: VS Code · Ctrl-Y: copy path' \
  --preview="bash \"$script_dir/preview.sh\" project {2}" \
  --preview-window='right,60%,wrap' \
  --prompt='project > ')" || exit 0
key="$(printf '%s\n' "$selected" | sed -n '1p')"
row="$(printf '%s\n' "$selected" | sed -n '2p')"
[ -n "$row" ] || exit 0
path="${row#*$'\t'}"

case "$key" in
  ctrl-o)
    editor="${DEV_EDITOR:-code}"
    need "$editor"
    "$editor" "$path" >&2
    exit 0
    ;;
  ctrl-y)
    printf '%s' "$path" | clip_copy
    printf 'Copied: %s\n' "$path" >&2
    exit 0
    ;;
esac

case "$mode" in
  print) printf '%s\n' "$path" ;;
  open)
    editor="${DEV_EDITOR:-code}"
    need "$editor"
    "$editor" "$path"
    ;;
  *) die "Unknown project mode: $mode" ;;
esac
