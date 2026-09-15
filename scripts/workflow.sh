#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$script_dir/lib.sh"

mode="${1:-}"
shift || true
workflow_args=()
workflow_temp_file=""

cleanup() {
  [ -z "$workflow_temp_file" ] || rm -f -- "$workflow_temp_file"
}
trap cleanup EXIT

load_workflow_args() {
  local input="${DEV_HARNESS_INPUT:-}"
  if [ "$#" -gt 0 ] && [ -n "$input" ]; then
    die 'Options were supplied both as arguments and through DEV_HARNESS_INPUT.'
  fi
  if [ "$#" -gt 0 ]; then
    workflow_args=("$@")
  elif [ -n "$input" ]; then
    read -r -a workflow_args <<< "$input" || true
  fi
}

run_why() {
  local root
  [ "${#workflow_args[@]}" -eq 0 ] || die 'why does not accept options.'
  root="$(repo_root)"
  bash "$script_dir/resume.sh" preview "$root"
}

render_handoff() {
  local root="$1"
  bash "$script_dir/resume.sh" context "$root"
}

run_handoff() {
  local action=print root option=""
  [ "${#workflow_args[@]}" -gt 0 ] && option="${workflow_args[0]}"
  case "${#workflow_args[@]}:$option" in
    0:) ;;
    1:--copy) action=copy ;;
    *) die "Use 'handoff [--copy]'." ;;
  esac

  root="$(repo_root)"
  workflow_temp_file="$(mktemp "${TMPDIR:-/tmp}/dev-harness-handoff.XXXXXX")"
  render_handoff "$root" > "$workflow_temp_file"
  if [ "$action" = copy ]; then
    clip_copy < "$workflow_temp_file"
    printf 'Handoff context copied.\n' >&2
  else
    cat "$workflow_temp_file"
  fi
}

print_bullets_or_none() {
  local rows="$1"
  if [ -n "$rows" ]; then
    printf '%s\n' "$rows"
  else
    printf '%s\n' '- none'
  fi
}

render_standup() {
  local root="$1" project branch commits changes todos todo_rows
  project="$(cd "$root" && project_slug)"
  branch="$(git -C "$root" branch --show-current 2>/dev/null || true)"
  [ -n "$branch" ] || branch=detached
  commits="$(git -C "$root" log --since='24 hours ago' --format='- %h %s' 2>/dev/null || true)"
  changes="$(cd "$root" && bash "$script_dir/changes.sh" files | sed 's/^/- /')"

  if obsidian_executable >/dev/null 2>&1; then
    todo_rows="$(cd "$root" && bash "$script_dir/obsidian.sh" todos-tsv project open)"
    todos="$(printf '%s\n' "$todo_rows" | awk -F '\t' 'NF { priority=toupper($4); print "- " priority " " $2 }')"
  else
    todos='- unavailable (Obsidian CLI not configured)'
  fi

  printf '## %s · %s\n\n' "$project" "$branch"
  printf '### Commits in the last 24 hours\n'
  print_bullets_or_none "$commits"
  printf '\n### Current changes\n'
  print_bullets_or_none "$changes"
  printf '\n### Open TODOs\n'
  print_bullets_or_none "$todos"
}

run_standup() {
  local action=print root report option=""
  [ "${#workflow_args[@]}" -gt 0 ] && option="${workflow_args[0]}"
  case "${#workflow_args[@]}:$option" in
    0:) ;;
    1:--copy) action=copy ;;
    1:--day) action=day ;;
    *) die "Use 'standup [--copy|--day]'." ;;
  esac

  root="$(repo_root)"
  if [ "$action" = day ]; then
    obsidian_executable >/dev/null 2>&1 \
      || die 'Obsidian CLI is required for standup --day. Enable it in Obsidian Settings → General.'
  fi
  workflow_temp_file="$(mktemp "${TMPDIR:-/tmp}/dev-harness-standup.XXXXXX")"
  render_standup "$root" > "$workflow_temp_file"

  case "$action" in
    print) cat "$workflow_temp_file" ;;
    copy)
      clip_copy < "$workflow_temp_file"
      printf 'Standup copied.\n' >&2
      ;;
    day)
      report="$(cat "$workflow_temp_file")"
      (cd "$root" && bash "$script_dir/obsidian.sh" day-append "$report")
      printf 'Standup appended to today.\n' >&2
      ;;
  esac
}

case "$mode" in
  why) load_workflow_args "$@"; run_why ;;
  handoff) load_workflow_args "$@"; run_handoff ;;
  standup) load_workflow_args "$@"; run_standup ;;
  *) die "Unknown workflow mode: $mode" ;;
esac
