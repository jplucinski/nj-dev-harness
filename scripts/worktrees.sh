#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$script_dir/lib.sh"

mode="${1:-manage}"
need git
need fzf
root="$(repo_root)"

porcelain="$(git worktree list --porcelain)"
rows=""
worktree_path=""
worktree_branch=""
worktree_head=""
emit_worktree() {
  local short_branch normalized
  [ -n "${worktree_path:-}" ] || return 0
  normalized="$(to_shell_path "$worktree_path")"
  short_branch="${worktree_branch#refs/heads/}"
  [ -n "$short_branch" ] || short_branch='detached'
  rows="${rows}${short_branch}"$'\t'"${normalized}"$'\t'"${worktree_head:0:10}"$'\n'
  worktree_path=""
  worktree_branch=""
  worktree_head=""
}
while IFS= read -r line || [ -n "$line" ]; do
  case "$line" in
    worktree\ *)
      emit_worktree
      worktree_path="${line#worktree }"
      ;;
    HEAD\ *) worktree_head="${line#HEAD }" ;;
    branch\ *) worktree_branch="${line#branch }" ;;
    detached) worktree_branch='detached' ;;
    '') emit_worktree ;;
  esac
done <<<"$porcelain"
emit_worktree

[ -n "$rows" ] || die "No Git worktrees found."

if [ "$mode" = manage ]; then
  expected_keys='ctrl-o,ctrl-y,ctrl-a,ctrl-x'
  help_text='Enter: print · Ctrl-O: VS Code · Ctrl-Y: copy · Ctrl-A: AI · Ctrl-X: remove'
else
  expected_keys='ctrl-o,ctrl-y'
  help_text='Enter: select · Ctrl-O: VS Code · Ctrl-Y: copy path'
fi

selection="$(printf '%s\n' "$rows" | fzf \
  --delimiter=$'\t' \
  --with-nth=1,3,2 \
  --expect="$expected_keys" \
  --header="$help_text" \
  --preview="bash \"$script_dir/preview.sh\" worktree {2}" \
  --preview-window='right,60%,wrap' \
  --prompt='worktree > ')" || exit 0

key="$(printf '%s\n' "$selection" | sed -n '1p')"
row="$(printf '%s\n' "$selection" | sed -n '2p')"
[ -n "$row" ] || exit 0
path="$(printf '%s' "$row" | cut -f2)"

open_worktree() {
  local editor="${DEV_EDITOR:-code}"
  need "$editor"
  "$editor" "$path" >&2
}

case "$key" in
  ctrl-o)
    open_worktree
    exit 0
    ;;
  ctrl-y)
    printf '%s' "$path" | clip_copy
    printf 'Copied: %s\n' "$path" >&2
    ;;
  ctrl-a)
    (cd "$path" && bash "$script_dir/ai.sh" interactive)
    ;;
  ctrl-x)
    current="$(repo_root)"
    [ "$path" != "$current" ] || die "Cannot remove the worktree currently in use."
    printf 'Target: %s\n' "$path"
    git -C "$path" status -sb || true
    read -r -p 'Remove this worktree? [y/N] ' answer </dev/tty
    case "$answer" in
      y|Y|yes|YES)
        git -C "$root" worktree remove -- "$path"
        rm -f "$(dirname "$path")/.dev-harness/$(basename "$path").meta"
        printf 'Removed: %s\n' "$path"
        ;;
      *) printf 'Canceled.\n' ;;
    esac
    ;;
  '')
    case "$mode" in
      print|manage) printf '%s\n' "$path" ;;
      open) open_worktree ;;
      *) die "Unknown worktree mode: $mode" ;;
    esac
    ;;
esac
