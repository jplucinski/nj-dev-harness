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

open_match() {
  local match="$1" file line column editor editor_name
  editor="${DEV_EDITOR:-code}"
  need "$editor"
  IFS=: read -r file line column _ <<<"$match"
  editor_name="$(basename "$editor")"
  case "$editor_name" in
    code|code.cmd|code-insiders|code-insiders.cmd)
      "$editor" --goto "$(workplace_root)/$file:$line:$column"
      ;;
    *)
      "$editor" "$(workplace_root)/$file"
      ;;
  esac
}

parse_selection() {
  local raw="$1" item
  selection_key="$(printf '%s\n' "$raw" | sed -n '1p')"
  selection_items=()
  while IFS= read -r item; do
    [ -n "$item" ] && selection_items+=("$item")
  done < <(printf '%s\n' "$raw" | sed '1d')
}

match_files() {
  local item file
  files=()
  for item in "$@"; do
    IFS=: read -r file _ <<<"$item"
    files+=("$(workplace_root)/$file")
  done
}

run_live() {
  local query raw item
  need fzf
  need rg
  need "${DEV_EDITOR:-code}"
  workplace_project_dirs >/dev/null
  query="${DEV_HARNESS_INPUT:-$*}"
  raw="$(
    fzf \
      --disabled \
      --multi \
      --query="$query" \
      --bind "start:reload:bash \"$script_dir/search.sh\" reload {q}" \
      --bind "change:reload:bash \"$script_dir/search.sh\" reload {q}" \
      --expect=ctrl-o,ctrl-y,ctrl-a,ctrl-r \
      --header='Tab: multi · Enter/Ctrl-O: open · Ctrl-Y: copy · Ctrl-A: AI · Ctrl-R: review' \
      --preview="bash \"$script_dir/preview.sh\" search {}" \
      --preview-window='right,65%,wrap' \
      --prompt='match > '
  )" || exit 0
  parse_selection "$raw"
  [ "${#selection_items[@]}" -gt 0 ] || exit 0
  case "$selection_key" in
    ctrl-y) printf '%s\n' "${selection_items[@]}" | clip_copy ;;
    ctrl-a|ctrl-r)
      match_files "${selection_items[@]}"
      bash "$script_dir/ai.sh" analyze-files "${files[@]}"
      ;;
    ''|ctrl-o)
      for item in "${selection_items[@]}"; do open_match "$item"; done
      ;;
  esac
}

case "$mode" in
  reload)
    reload_search "${DEV_HARNESS_INPUT:-$*}"
    ;;
  live)
    run_live "$@"
    ;;
  semantic|index)
    die "Search mode '$mode' is not implemented yet."
    ;;
  *) die "Unknown search mode: $mode" ;;
esac
