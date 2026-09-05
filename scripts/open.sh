#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$script_dir/lib.sh"

mode="${1:-file}"
shift || true
need fzf
need rg
editor="${DEV_EDITOR:-code}"
need "$editor"
root=""
path_separator='/'
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) path_separator='//' ;;
esac

open_file() {
  local path="$1"
  "$editor" "$root/$path"
}

open_match() {
  local match="$1" file line column editor_name
  IFS=: read -r file line column _ <<<"$match"
  editor_name="$(basename "$editor")"
  case "$editor_name" in
    code|code.cmd|code-insiders|code-insiders.cmd) "$editor" --goto "$root/$file:$line:$column" ;;
    *) "$editor" "$root/$file" ;;
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

handle_files() {
  local item
  [ "${#selection_items[@]}" -gt 0 ] || exit 0
  case "$selection_key" in
    ctrl-y)
      printf '%s\n' "${selection_items[@]}" | clip_copy
      printf 'Copied %s path(s).\n' "${#selection_items[@]}" >&2
      ;;
    ctrl-a) bash "$script_dir/ai.sh" analyze-files "${selection_items[@]}" ;;
    ctrl-r) bash "$script_dir/ai.sh" review-files "${selection_items[@]}" ;;
    ''|ctrl-o)
      for item in "${selection_items[@]}"; do open_file "$item"; done
      ;;
  esac
}

fzf_file_picker() {
  local prompt="$1" preview_mode="$2"
  fzf \
    --multi \
    --expect=ctrl-o,ctrl-y,ctrl-a,ctrl-r \
    --header='Tab: multi · Enter/Ctrl-O: open · Ctrl-Y: copy · Ctrl-A: AI · Ctrl-R: review' \
    --preview="bash \"$script_dir/preview.sh\" $preview_mode {}" \
    --preview-window='right,65%,wrap' \
    --prompt="$prompt"
}

changed_files() {
  if git rev-parse --verify HEAD >/dev/null 2>&1; then
    git diff --name-only --diff-filter=ACMR HEAD --
  else
    git diff --cached --name-only --diff-filter=ACMR --
  fi
  git ls-files --others --exclude-standard
}

case "$mode" in
  file)
    root="$(pwd -P)"
    raw="$(rg --files --path-separator "$path_separator" --hidden -g '!.git' | fzf_file_picker 'file > ' file)" || exit 0
    parse_selection "$raw"
    handle_files
    ;;
  changed)
    need git
    root="$(repo_root)"
    cd "$root"
    tmp="$(mktemp)"
    trap 'rm -f "$tmp"' EXIT
    changed_files >"$tmp"
    raw="$(sort -u "$tmp" | fzf_file_picker 'changed > ' diff)" || exit 0
    parse_selection "$raw"
    handle_files
    ;;
  search)
    need git
    root="$(repo_root)"
    cd "$root"
    query="${DEV_HARNESS_INPUT:-$*}"
    if [ -z "$query" ]; then
      read -r -p 'Search: ' query
    fi
    [ -n "$query" ] || exit 0
    results="$(rg --line-number --column --no-heading --hidden -g '!.git' -- "$query" || true)"
    [ -n "$results" ] || die "No matches for: $query"
    raw="$(printf '%s\n' "$results" | fzf \
      --multi \
      --expect=ctrl-o,ctrl-y,ctrl-a,ctrl-r \
      --header='Tab: multi · Enter/Ctrl-O: open · Ctrl-Y: copy · Ctrl-A: AI · Ctrl-R: review' \
      --preview="bash \"$script_dir/preview.sh\" search {}" \
      --preview-window='right,65%,wrap' \
      --prompt='match > ')" || exit 0
    parse_selection "$raw"
    [ "${#selection_items[@]}" -gt 0 ] || exit 0
    case "$selection_key" in
      ctrl-y) printf '%s\n' "${selection_items[@]}" | clip_copy ;;
      ctrl-a|ctrl-r)
        files=()
        for item in "${selection_items[@]}"; do
          IFS=: read -r file _ <<<"$item"
          files+=("$file")
        done
        if [ "$selection_key" = ctrl-a ]; then
          bash "$script_dir/ai.sh" analyze-files "${files[@]}"
        else
          bash "$script_dir/ai.sh" review-files "${files[@]}"
        fi
        ;;
      ''|ctrl-o)
        for item in "${selection_items[@]}"; do open_match "$item"; done
        ;;
    esac
    ;;
  *) die "Unknown open mode: $mode" ;;
esac
