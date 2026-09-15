#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$script_dir/lib.sh"

mode="${1:-interactive}"
shift || true

run_prompt() {
  local prompt_file="$1" review_command
  review_command="${DEV_AI_REVIEW_COMMAND:-}"
  if [ -z "$review_command" ]; then
    warn "DEV_AI_REVIEW_COMMAND is not set; printing the prompt locally."
    cat "$prompt_file"
  else
    bash -c "$review_command" <"$prompt_file"
  fi
}

pick_changed_files() {
  local source_mode="${1:-files}" rows selection item
  picked_files=()
  pick_key=""
  rows="$(bash "$script_dir/changes.sh" "$source_mode")"
  [ -n "$rows" ] || return 0

  if ! command -v fzf >/dev/null 2>&1 || [ ! -t 0 ] || [ ! -t 1 ]; then
    while IFS= read -r item; do [ -n "$item" ] && picked_files+=("$item"); done <<<"$rows"
    return 0
  fi

  selection="$(printf '%s\n' "$rows" | fzf \
    --multi \
    --expect=ctrl-y \
    --bind='ctrl-a:select-all,ctrl-d:deselect-all' \
    --header='Tab: select · Ctrl-A: all · Enter: use · Ctrl-Y: copy context' \
    --preview="bash \"$script_dir/preview.sh\" diff {}" \
    --preview-window='right,65%,wrap' \
    --prompt='context > ')" || return 1
  pick_key="$(printf '%s\n' "$selection" | sed -n '1p')"
  while IFS= read -r item; do [ -n "$item" ] && picked_files+=("$item"); done \
    < <(printf '%s\n' "$selection" | sed '1d')
}

select_review_files() {
  local input="${DEV_HARNESS_INPUT:-}" option item rows
  local review_args=()
  review_all=false
  if [ -n "$input" ]; then
    read -r -a review_args <<<"$input" || true
  fi
  if [ "${#review_args[@]}" -gt 0 ]; then
    for option in "${review_args[@]}"; do
      case "$option" in
        --all) review_all=true ;;
        '') ;;
        *) die "Unknown review option: $option. Use --all for explicit non-interactive review." ;;
      esac
    done
  fi

  if [ "$review_all" = true ]; then
    picked_files=()
    rows="$(bash "$script_dir/changes.sh" files)"
    while IFS= read -r item; do
      [ -n "$item" ] && picked_files+=("$item")
    done <<<"$rows"
    return 0
  fi

  command -v fzf >/dev/null 2>&1 && [ -t 0 ] && [ -t 1 ] \
    || die "Review requires interactive fzf selection or explicit --all."
  pick_changed_files files
}

write_selected_file_contents() {
  local path file_path max_lines per_file
  max_lines="${DEV_CONTEXT_MAX_LINES:-4000}"
  case "$max_lines" in
    ''|*[!0-9]*|0) die "DEV_CONTEXT_MAX_LINES must be a positive integer." ;;
  esac
  per_file=$((max_lines / $#))
  [ "$per_file" -gt 0 ] || per_file=1
  for path in "$@"; do
    if is_sensitive_path "$path"; then
      printf '\n## %s\n[sensitive path excluded]\n' "$path"
    elif [ -f "$path" ]; then
      printf '\n## %s\n```\n' "$path"
      case "$path" in /*) file_path="$path" ;; *) file_path="./$path" ;; esac
      head -n "$per_file" "$file_path"
      printf '\n```\n'
    fi
  done
}

case "$mode" in
  interactive)
    ai_command="${DEV_AI_COMMAND:-}"
    [ -n "$ai_command" ] || die "Set DEV_AI_COMMAND, for example: codex"
    exec bash -c "$ai_command"
    ;;
  context)
    input="${DEV_HARNESS_INPUT:-}"
    copy_context=false
    source_mode=files
    use_all=false
    context_args=()
    if [ -n "$input" ]; then
      read -r -a context_args <<<"$input" || true
    fi
    if [ "${#context_args[@]}" -gt 0 ]; then
      for context_arg in "${context_args[@]}"; do
        case "$context_arg" in
          --copy) copy_context=true ;;
          --all) use_all=true ;;
          --staged) source_mode=staged-files ;;
          '') ;;
          *) die "Unknown context option: $context_arg" ;;
        esac
      done
    fi

    tmp="$(mktemp)"
    trap 'rm -f "$tmp"' EXIT
    if [ "$use_all" = true ]; then
      bash "$script_dir/changes.sh" context >"$tmp"
    else
      pick_changed_files "$source_mode" || exit 0
      if [ "${#picked_files[@]}" -gt 0 ]; then
        bash "$script_dir/changes.sh" context "${picked_files[@]}" >"$tmp"
      else
        bash "$script_dir/changes.sh" context >"$tmp"
      fi
      [ "$pick_key" = ctrl-y ] && copy_context=true
    fi

    if [ "$copy_context" = true ]; then
      clip_copy <"$tmp"
      printf 'Context copied to clipboard.\n'
    else
      cat "$tmp"
    fi
    ;;
  review)
    select_review_files || exit 0
    tmp="$(mktemp)"
    trap 'rm -f "$tmp"' EXIT
    {
      printf '%s\n\n' 'Review the following repository changes relative to the stated base.'
      printf '%s\n' 'Prioritize correctness, regressions, security, missing tests, and maintainability.'
      printf '%s\n\n' 'Reference exact files and lines where possible. Do not invent files or behavior.'
      if [ "${#picked_files[@]}" -gt 0 ]; then
        bash "$script_dir/changes.sh" context "${picked_files[@]}"
      else
        bash "$script_dir/changes.sh" context
      fi
    } >"$tmp"
    run_prompt "$tmp"
    ;;
  analyze-files)
    [ "$#" -gt 0 ] || die "No files selected for AI analysis."
    tmp="$(mktemp)"
    trap 'rm -f "$tmp"' EXIT
    {
      printf '%s\n' 'Analyze the selected repository files. Focus on the user-visible behavior, risks, and useful improvements.'
      write_selected_file_contents "$@"
    } >"$tmp"
    run_prompt "$tmp"
    ;;
  review-files)
    [ "$#" -gt 0 ] || die "No files selected for AI review."
    tmp="$(mktemp)"
    trap 'rm -f "$tmp"' EXIT
    {
      printf '%s\n\n' 'Review only the selected repository changes. Prioritize correctness, regressions, security, and missing tests.'
      bash "$script_dir/changes.sh" context "$@"
    } >"$tmp"
    run_prompt "$tmp"
    ;;
  *) die "Unknown AI mode: $mode" ;;
esac
