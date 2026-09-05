#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$script_dir/lib.sh"

mode="${1:-logs}"
need docker
need fzf

rows="$(docker ps --format '{{.ID}}\t{{.Names}}\t{{.Image}}\t{{.Status}}')"
[ -n "$rows" ] || die "No running Docker containers."
selected="$(printf '%s\n' "$rows" | fzf \
  --delimiter=$'\t' \
  --with-nth=2,3,4 \
  --expect=ctrl-y \
  --header='Enter: use container · Ctrl-Y: copy container name' \
  --preview="bash \"$script_dir/preview.sh\" container {1}" \
  --preview-window='right,60%,wrap' \
  --prompt='container > ')" || exit 0
key="$(printf '%s\n' "$selected" | sed -n '1p')"
row="$(printf '%s\n' "$selected" | sed -n '2p')"
[ -n "$row" ] || exit 0
container="${row%%$'\t'*}"
container_name="$(printf '%s' "$row" | cut -f2)"

if [ "$key" = ctrl-y ]; then
  printf '%s' "$container_name" | clip_copy
  printf 'Copied: %s\n' "$container_name" >&2
  exit 0
fi

case "$mode" in
  logs) exec docker logs --follow --tail 200 "$container" ;;
  shell)
    if ! docker exec -it "$container" bash; then
      exec docker exec -it "$container" sh
    fi
    ;;
  *) die "Unknown Docker mode: $mode" ;;
esac
