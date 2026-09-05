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

format_grepai_json() {
  local workplace="$1"
  awk -v workplace="$workplace" '
    function trim(s) {
      sub(/^[[:space:]]+/, "", s)
      sub(/[[:space:]]+$/, "", s)
      return s
    }
    function unquote(s) {
      sub(/^"/, "", s)
      sub(/"$/, "", s)
      gsub(/\\n/, "\n", s)
      return s
    }
    function emit() {
      if (file == "" || line == "") return
      rel = file
      prefix = workplace "/"
      if (index(rel, prefix) == 1) rel = substr(rel, length(prefix) + 1)
      snippet = content
      sub(/\n.*/, "", snippet)
      printf "%s:%s:1:%s %s\n", rel, line, score, snippet
      file = ""; line = ""; score = ""; content = ""
    }
    {
      line_text = $0
      if (line_text ~ /"file":/) {
        emit()
        sub(/.*"file":[[:space:]]*/, "", line_text)
        sub(/,.*/, "", line_text)
        file = unquote(trim(line_text))
      }
      if ($0 ~ /"start_line":/) {
        line_text = $0
        sub(/.*"start_line":[[:space:]]*/, "", line_text)
        sub(/,.*/, "", line_text)
        line = trim(line_text)
      }
      if ($0 ~ /"score":/) {
        line_text = $0
        sub(/.*"score":[[:space:]]*/, "", line_text)
        sub(/,.*/, "", line_text)
        score = trim(line_text)
      }
      if ($0 ~ /"content":/) {
        line_text = $0
        sub(/.*"content":[[:space:]]*/, "", line_text)
        sub(/,$/, "", line_text)
        content = unquote(trim(line_text))
      }
    }
    END { emit() }
  '
}

run_index() {
  local workplace
  need grepai
  workplace="$(workplace_root)"
  workplace_project_dirs >/dev/null
  cd "$workplace"
  if [ ! -f .grepai/config.yaml ]; then
    grepai init --yes --provider ollama --backend gob
  fi
  if grepai index --help >/dev/null 2>&1; then
    grepai index
  elif grepai watch --status >/dev/null 2>&1; then
    return 0
  else
    grepai watch --background
  fi
}

handle_matches() {
  local item
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

run_semantic() {
  local query json results raw workplace
  need grepai
  workplace="$(workplace_root)"
  workplace_project_dirs >/dev/null
  if [ ! -f "$workplace/.grepai/config.yaml" ] || [ ! -f "$workplace/.grepai/index.gob" ]; then
    die "Run gtask index before semantic search."
  fi
  query="${DEV_HARNESS_INPUT:-$*}"
  if [ -z "$query" ]; then
    read -r -p 'Search: ' query || true
  fi
  [ -n "$query" ] || exit 0
  need fzf
  need "${DEV_EDITOR:-code}"
  json="$(
    cd "$workplace"
    grepai search --json --limit 50 -- "$query"
  )"
  results="$(printf '%s\n' "$json" | format_grepai_json "$workplace")"
  [ -n "$results" ] || die "No matches for: $query"
  raw="$(printf '%s\n' "$results" | fzf \
    --multi \
    --expect=ctrl-o,ctrl-y,ctrl-a,ctrl-r \
    --header='Tab: multi · Enter/Ctrl-O: open · Ctrl-Y: copy · Ctrl-A: AI · Ctrl-R: review' \
    --preview="bash \"$script_dir/preview.sh\" search {}" \
    --preview-window='right,65%,wrap' \
    --prompt='match > ')" || exit 0
  parse_selection "$raw"
  handle_matches
}

case "$mode" in
  reload)
    reload_search "${DEV_HARNESS_INPUT:-$*}"
    ;;
  live)
    run_live "$@"
    ;;
  semantic)
    run_semantic "$@"
    ;;
  index)
    run_index
    ;;
  *) die "Unknown search mode: $mode" ;;
esac
