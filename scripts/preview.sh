#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$script_dir/lib.sh"

mode="${1:-file}"
target="${2:-}"

show_file() {
  local path="$1" line="${2:-1}" start end
  [ -f "$path" ] || { printf 'File not found: %s\n' "$path"; return; }
  case "$line" in ''|*[!0-9]*) line=1 ;; esac
  if [ "$line" -gt 1 ]; then
    start=$((line - 30))
    [ "$start" -gt 0 ] || start=1
    end=$((line + 80))
  else
    start=1
    end=300
  fi
  if command -v bat >/dev/null 2>&1; then
    bat --color=always --style=numbers --highlight-line "$line" --line-range "$start:$end" -- "$path"
  else
    awk -v start="$start" -v end="$end" 'NR >= start && NR <= end {printf "%6d  %s\n", NR, $0}' "$path"
  fi
}

case "$mode" in
  file)
    root="$(repo_root)"
    show_file "$root/$target"
    ;;
  diff)
    root="$(repo_root)"
    cd "$root"
    if is_sensitive_path "$target"; then
      printf 'Sensitive file preview is hidden: %s\n' "$target"
    elif git ls-files --error-unmatch -- "$target" >/dev/null 2>&1; then
      bash "$script_dir/changes.sh" context "$target" || true
    else
      printf 'Untracked file: %s\n\n' "$target"
      show_file "$root/$target"
    fi
    ;;
  search)
    IFS=: read -r file line _ <<<"$target"
    root="$(repo_root)"
    show_file "$root/$file" "$line"
    ;;
  project|worktree)
    path="$(to_shell_path "$target")"
    printf '%s\n\n' "$path"
    if git -C "$path" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      git -C "$path" status -sb || true
      printf '\nRecent commits:\n'
      git -C "$path" log --oneline --decorate -5 || true
    else
      printf 'Not a Git repository.\n'
    fi
    ;;
  container)
    docker logs --tail 80 "$target" 2>&1 || true
    ;;
  *) die "Unknown preview mode: $mode" ;;
esac
