#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$script_dir/lib.sh"

mode="${1:-manage}"
shift || true
focus_args=()
focus_temp_file=""
priority=""

cleanup() {
  [ -z "$focus_temp_file" ] || rm -f -- "$focus_temp_file"
}
trap cleanup EXIT

load_focus_args() {
  local input="${DEV_HARNESS_INPUT:-}"
  if [ "$#" -gt 0 ] && [ -n "$input" ]; then
    die 'Priority was supplied both as an argument and through DEV_HARNESS_INPUT.'
  fi
  if [ "$#" -gt 0 ]; then
    focus_args=("$@")
  elif [ -n "$input" ]; then
    read -r -a focus_args <<< "$input"
  fi
}

parse_priority() {
  [ "$#" -le 1 ] || die "Use 'focus [p0|p1|p2|p3]'."
  priority="${1:-}"
  case "$priority" in
    ''|p0|p1|p2|p3) ;;
    *) die "Use 'focus [p0|p1|p2|p3]'." ;;
  esac
}

run_obsidian() {
  local obsidian_bin
  obsidian_bin="$(obsidian_executable)" \
    || die 'Obsidian CLI is unavailable. Enable it in Obsidian Settings → General.'
  if [ -n "${DEV_OBSIDIAN_VAULT:-}" ]; then
    "$obsidian_bin" "vault=$DEV_OBSIDIAN_VAULT" "$@"
  else
    "$obsidian_bin" "$@"
  fi
}

print_candidates() {
  local rows
  if [ -n "$priority" ]; then
    rows="$(bash "$script_dir/obsidian.sh" todos-tsv all open "$priority")"
  else
    rows="$(bash "$script_dir/obsidian.sh" todos-tsv all open)"
  fi
  [ -n "$rows" ] || return 0
  printf '%s\n' "$rows" \
    | awk -F '\t' -v OFS='\t' 'NF { print toupper($4), $3, $2, $6, $1 }'
}

preview_note() {
  [ "$#" -eq 1 ] && [ -n "${1:-}" ] || die 'Focus preview requires one TODO note path.'
  run_obsidian read path="$1"
}

open_note() {
  local path="$1"
  run_obsidian open path="$path"
}

resolve_project() {
  local project="$1" current_root workplace candidate root candidate_project count
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    current_root="$(to_shell_path "$(git rev-parse --show-toplevel)")"
    current_root="$(cd "$current_root" && pwd -P)"
    if [ "$(cd "$current_root" && project_slug)" = "$project" ]; then
      printf '%s\n' "$current_root"
      return 0
    fi
  fi

  focus_temp_file="$(mktemp "${TMPDIR:-/tmp}/dev-harness-focus-projects.XXXXXX")"
  workplace="${DEV_WORKPLACE:-}"
  if [ -n "$workplace" ]; then
    workplace="$(to_shell_path "$workplace")"
    if [ -d "$workplace" ]; then
      while IFS= read -r candidate; do
        root="$(git -C "$candidate" rev-parse --show-toplevel 2>/dev/null || true)"
        [ -n "$root" ] || continue
        root="$(to_shell_path "$root")"
        root="$(cd "$root" && pwd -P)"
        candidate_project="$(cd "$root" && project_slug)"
        [ "$candidate_project" = "$project" ] || continue
        if ! awk -v path="$root" '$0 == path { found=1 } END { exit !found }' "$focus_temp_file"; then
          printf '%s\n' "$root" >> "$focus_temp_file"
        fi
      done < <(find "$workplace" -mindepth 1 -maxdepth 1 -type d -print | LC_ALL=C sort)
    fi
  fi

  count="$(awk 'END { print NR+0 }' "$focus_temp_file")"
  case "$count" in
    1) cat "$focus_temp_file" ;;
    0)
      die "No repository named '$project' found. Set DEV_WORKPLACE or use Ctrl-O to open the TODO note."
      ;;
    *)
      printf "Ambiguous project '%s'; matching repositories:\n" "$project" >&2
      sed 's/^/  /' "$focus_temp_file" >&2
      return 1
      ;;
  esac
}

select_candidate() {
  local rows selection key row project note_path selected_path header
  rows="$(print_candidates)"
  if [ -z "$rows" ]; then
    if [ "$mode" = select ]; then
      printf 'No matching TODOs.\n' >&2
    else
      printf 'No matching TODOs.\n'
    fi
    return 0
  fi
  need fzf
  if [ "$mode" = select ]; then
    header='Enter: cd to project · Ctrl-O: open TODO note'
  else
    header='Enter: print project path · Ctrl-O: open TODO note'
  fi
  selection="$(printf '%s\n' "$rows" | fzf \
    --delimiter=$'\t' \
    --with-nth=1,2,3,4 \
    --nth=1,2,3,4 \
    --expect=ctrl-o \
    --header="$header" \
    --preview="bash \"$script_dir/focus.sh\" preview {5}" \
    --preview-window='right,60%,wrap' \
    --prompt='focus > ')" || return 0
  key="$(printf '%s\n' "$selection" | sed -n '1p')"
  row="$(printf '%s\n' "$selection" | sed -n '2p')"
  [ -n "$row" ] || return 0
  project="$(printf '%s' "$row" | cut -f2)"
  note_path="$(printf '%s' "$row" | cut -f5-)"
  if [ -z "$key" ]; then
    selected_path="$(resolve_project "$project")" || return
    printf '%s\n' "$selected_path"
  elif [ "$key" = ctrl-o ]; then
    if [ "$mode" = select ]; then
      open_note "$note_path" >&2
    else
      open_note "$note_path"
    fi
  else
    die "Unknown focus action: $key"
  fi
}

case "$mode" in
  candidates)
    load_focus_args "$@"
    parse_priority "${focus_args[@]}"
    print_candidates
    ;;
  preview)
    preview_note "$@"
    ;;
  select|manage)
    load_focus_args "$@"
    parse_priority "${focus_args[@]}"
    select_candidate
    ;;
  *) die "Unknown focus mode: $mode" ;;
esac
