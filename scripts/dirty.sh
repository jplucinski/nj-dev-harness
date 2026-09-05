#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$script_dir/lib.sh"

mode="${1:-manage}"
shift || true

candidate_file="$(mktemp "${TMPDIR:-/tmp}/dev-harness-dirty-candidates.XXXXXX")"
trap 'rm -f -- "$candidate_file"' EXIT

canonical_worktree() {
  local input="$1" root
  root="$(git -C "$input" rev-parse --show-toplevel 2>/dev/null)" || return 1
  root="$(to_shell_path "$root")"
  (cd "$root" && pwd -P)
}

project_name_at() {
  local path="$1" common common_abs
  common="$(git -C "$path" rev-parse --git-common-dir 2>/dev/null)" || return 1
  case "$common" in
    /*|[A-Za-z]:[\\/]*) common_abs="$(to_shell_path "$common")" ;;
    *) common_abs="$path/$common" ;;
  esac
  if [ "$(basename "$common_abs")" = .git ]; then
    basename "$(dirname "$common_abs")"
  else
    basename "$path"
  fi
}

add_dirty_candidate() {
  local input="$1" path status project branch staged unstaged untracked
  path="$(canonical_worktree "$input")" || return 0
  if awk -F '\t' -v candidate="$path" '$6 == candidate { found=1 } END { exit !found }' "$candidate_file"; then
    return 0
  fi

  status="$(git -C "$path" status --porcelain)"
  [ -n "$status" ] || return 0
  staged="$(printf '%s\n' "$status" | awk 'length($0) && substr($0,1,1) != " " && substr($0,1,1) != "?" {n++} END {print n+0}')"
  unstaged="$(printf '%s\n' "$status" | awk 'length($0) && substr($0,2,1) != " " && substr($0,1,2) != "??" {n++} END {print n+0}')"
  untracked="$(printf '%s\n' "$status" | awk 'substr($0,1,2) == "??" {n++} END {print n+0}')"
  project="$(project_name_at "$path")"
  branch="$(git -C "$path" branch --show-current 2>/dev/null || true)"
  [ -n "$branch" ] || branch=detached
  printf '%s\t%s\t+%s\t~%s\t?%s\t%s\n' \
    "$project" "$branch" "$staged" "$unstaged" "$untracked" "$path" >> "$candidate_file"
}

collect_candidates() {
  local has_current=false has_workplace=false workplace project_dir worktree_path
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    has_current=true
    add_dirty_candidate "$PWD"
  fi

  workplace="${DEV_WORKPLACE:-}"
  if [ -n "$workplace" ]; then
    workplace="$(to_shell_path "$workplace")"
    if [ -d "$workplace" ]; then
      has_workplace=true
      while IFS= read -r project_dir; do
        if git -C "$project_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
          add_dirty_candidate "$project_dir"
          while IFS= read -r worktree_path; do
            [ -n "$worktree_path" ] || continue
            add_dirty_candidate "$(to_shell_path "$worktree_path")"
          done < <(git -C "$project_dir" worktree list --porcelain 2>/dev/null | sed -n 's/^worktree //p')
        fi
      done < <(find "$workplace" -mindepth 1 -maxdepth 1 -type d -print | LC_ALL=C sort)
    fi
  fi

  if [ "$has_current" = false ] && [ "$has_workplace" = false ]; then
    die 'No Git projects found. Set DEV_WORKPLACE or run this command inside a repository.'
  fi
}

print_candidates() {
  collect_candidates
  [ -s "$candidate_file" ] || return 0
  LC_ALL=C sort -t $'\t' -k1,1 -k2,2 "$candidate_file"
}

print_preview() {
  [ "$#" -eq 1 ] && [ -n "${1:-}" ] || die 'Dirty preview requires a worktree path.'
  bash "$script_dir/resume.sh" preview "$1"
}

open_candidate() {
  local path="$1" editor="${DEV_EDITOR:-code}"
  need "$editor"
  "$editor" "$path"
}

select_candidate() {
  local rows selection key row path header
  [ "$#" -eq 0 ] || die 'dirty does not accept arguments.'
  rows="$(print_candidates)"
  if [ -z "$rows" ]; then
    if [ "$mode" = select ]; then
      printf 'No dirty repositories.\n' >&2
    else
      printf 'No dirty repositories.\n'
    fi
    return 0
  fi
  need fzf
  if [ "$mode" = select ]; then
    header='Enter: cd here · Ctrl-O: open in editor'
  else
    header='Enter: print path · Ctrl-O: open in editor'
  fi
  selection="$(printf '%s\n' "$rows" | fzf \
    --delimiter=$'\t' \
    --with-nth=1,2,3,4,5,6 \
    --nth=1,2,6 \
    --expect=ctrl-o \
    --header="$header" \
    --preview="bash \"$script_dir/dirty.sh\" preview {6}" \
    --preview-window='right,65%,wrap' \
    --prompt='dirty > ')" || return 0
  key="$(printf '%s\n' "$selection" | sed -n '1p')"
  row="$(printf '%s\n' "$selection" | sed -n '2p')"
  [ -n "$row" ] || return 0
  path="$(printf '%s' "$row" | cut -f6-)"
  [ -n "$path" ] || return 0
  if [ -z "$key" ]; then
    printf '%s\n' "$path"
  elif [ "$key" = ctrl-o ]; then
    if [ "$mode" = select ]; then
      open_candidate "$path" >&2
    else
      open_candidate "$path"
    fi
  else
    die "Unknown dirty action: $key"
  fi
}

case "$mode" in
  candidates) [ "$#" -eq 0 ] || die 'dirty candidates does not accept arguments.'; print_candidates ;;
  preview) print_preview "$@" ;;
  select|manage) select_candidate "$@" ;;
  *) die "Unknown dirty mode: $mode" ;;
esac
