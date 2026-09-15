#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$script_dir/lib.sh"

mode="${1:-manage}"
shift || true

resume_limit="${DEV_RESUME_LIMIT:-10}"
case "$resume_limit" in
  ''|*[!0-9]*|0) die "DEV_RESUME_LIMIT must be a positive integer." ;;
esac

project_name_at() {
  local path="$1" root common common_abs
  root="$(to_shell_path "$(git -C "$path" rev-parse --show-toplevel 2>/dev/null)")" || return 1
  common="$(git -C "$path" rev-parse --git-common-dir 2>/dev/null)" || return 1
  case "$common" in
    /*|[A-Za-z]:[\\/]*) common_abs="$(to_shell_path "$common")" ;;
    *) common_abs="$root/$common" ;;
  esac
  if [ "$(basename "$common_abs")" = .git ]; then
    basename "$(dirname "$common_abs")"
  else
    basename "$root"
  fi
}

candidate_file="$(mktemp "${TMPDIR:-/tmp}/dev-harness-resume-candidates.XXXXXX")"
trap 'rm -f -- "$candidate_file"' EXIT

add_candidate() {
  local rank="$1" activity="$2" input_path="$3" path project branch
  [ -d "$input_path" ] || return 0
  path="$(git -C "$input_path" rev-parse --show-toplevel 2>/dev/null)" || return 0
  path="$(to_shell_path "$path")"
  if awk -F '\t' -v candidate="$path" '$5 == candidate { found=1 } END { exit !found }' "$candidate_file"; then
    return 0
  fi
  project="$(project_name_at "$path")" || return 0
  branch="$(git -C "$path" branch --show-current 2>/dev/null || true)"
  [ -n "$branch" ] || branch=detached
  printf '%s\t%s\t%s\t%s\t%s\n' "$rank" "$project" "$branch" "$activity" "$path" >> "$candidate_file"
}

collect_candidates() {
  local rank=10 activity directory workplace project_dir worktree_path

  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    add_candidate 0 current "$PWD"
  fi

  if command -v atuin >/dev/null 2>&1; then
    while IFS=$'\t' read -r activity directory; do
      [ -n "$directory" ] || continue
      add_candidate "$rank" "${activity:-recent}" "$(to_shell_path "$directory")"
      rank=$((rank + 1))
    done < <(atuin search --limit 200 --format $'{relativetime}\t{directory}' '*' 2>/dev/null \
      | awk -F '\t' 'NF >= 2 && !seen[$2]++ { print $1 "\t" $2 }' || true)
  fi

  workplace="${DEV_WORKPLACE:-}"
  [ -n "$workplace" ] || return 0
  workplace="$(to_shell_path "$workplace")"
  [ -d "$workplace" ] || return 0
  rank=10000
  while IFS= read -r project_dir; do
    if git -C "$project_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      add_candidate "$rank" project "$project_dir"
      rank=$((rank + 1))
      while IFS= read -r worktree_path; do
        [ -n "$worktree_path" ] || continue
        add_candidate "$rank" worktree "$(to_shell_path "$worktree_path")"
        rank=$((rank + 1))
      done < <(git -C "$project_dir" worktree list --porcelain 2>/dev/null | sed -n 's/^worktree //p')
    fi
  done < <(find "$workplace" -mindepth 1 -maxdepth 1 -type d -print | LC_ALL=C sort)
}

print_candidates() {
  collect_candidates
  [ -s "$candidate_file" ] || die "No Git projects found. Set DEV_WORKPLACE or run this command inside a repository."
  LC_ALL=C sort -t $'\t' -k1,1n -k2,2 "$candidate_file" \
    | awk -F '\t' -v OFS='\t' '!seen[$5]++ { print $2, $3, $4, $5 }' \
    | head -n "$resume_limit"
}

print_preview() {
  local input_path="${1:-}" path project branch base_ref status staged unstaged untracked commits todo
  [ -n "$input_path" ] || die "Resume preview requires a project path."
  input_path="$(to_shell_path "$input_path")"
  path="$(git -C "$input_path" rev-parse --show-toplevel 2>/dev/null)" \
    || die "Resume target is not a Git worktree: $input_path"
  path="$(to_shell_path "$path")"
  project="$(project_name_at "$path")"
  branch="$(git -C "$path" branch --show-current)"
  [ -n "$branch" ] || branch=detached
  base_ref="$(cd "$path" && default_branch || true)"
  [ -n "$base_ref" ] || base_ref=unknown
  status="$(git -C "$path" status --porcelain)"
  staged="$(printf '%s\n' "$status" | awk 'length($0) && substr($0,1,1) != " " && substr($0,1,1) != "?" {n++} END {print n+0}')"
  unstaged="$(printf '%s\n' "$status" | awk 'length($0) && substr($0,2,1) != " " && substr($0,1,2) != "??" {n++} END {print n+0}')"
  untracked="$(printf '%s\n' "$status" | awk 'substr($0,1,2) == "??" {n++} END {print n+0}')"
  if [ "$base_ref" = unknown ]; then
    commits='?'
  else
    commits="$(git -C "$path" rev-list --count "$base_ref..HEAD" 2>/dev/null || printf '?')"
  fi

  printf 'Project:    %s\n' "$project"
  printf 'Worktree:   %s\n' "$path"
  printf 'Branch:     %s\n' "$branch"
  printf 'Base:       %s\n' "$base_ref"
  printf 'Changes:    %s staged · %s unstaged · %s untracked\n' "$staged" "$unstaged" "$untracked"
  printf 'Commits:    %s since base\n' "$commits"
  printf '\nLast commit:\n'
  git -C "$path" log -1 --format='  %h %s · %cr' 2>/dev/null || true

  if [ -n "$status" ]; then
    printf '\nChanged files:\n'
    printf '%s\n' "$status" | head -n 20
  fi

  todo="$(next_todo_at "$path")"
  case "$todo" in
    ''|'No matching TODOs.') ;;
    *) printf '\nNext TODO:\n  %s\n' "$todo" ;;
  esac
}

next_todo_at() {
  local path="$1"
  obsidian_executable >/dev/null 2>&1 || return 0
  (cd "$path" && DEV_HARNESS_INPUT='' bash "$script_dir/obsidian.sh" todo 2>/dev/null | head -n 1) || true
}

print_resume_context() {
  local input_path="${1:-}" path todo
  [ -n "$input_path" ] || die "Resume context requires a project path."
  input_path="$(to_shell_path "$input_path")"
  path="$(git -C "$input_path" rev-parse --show-toplevel 2>/dev/null)" \
    || die "Resume target is not a Git worktree: $input_path"
  path="$(to_shell_path "$path")"

  printf '%s\n' 'Resume the work in this repository.'
  printf '%s\n' 'First explain the current state and propose the next three steps.'
  printf '%s\n\n' 'Do not modify files until explicitly asked.'
  (cd "$path" && bash "$script_dir/changes.sh" summary)
  todo="$(next_todo_at "$path")"
  case "$todo" in
    ''|'No matching TODOs.') ;;
    *) printf '\nHighest-priority open TODO:\n%s\n' "$todo" ;;
  esac
}

run_resume_ai() {
  local path="$1" resume_command
  resume_command="${DEV_AI_RESUME_COMMAND:-${DEV_AI_REVIEW_COMMAND:-}}"
  if [ -z "$resume_command" ]; then
    warn "DEV_AI_RESUME_COMMAND and DEV_AI_REVIEW_COMMAND are unset; printing the resume context locally."
    print_resume_context "$path"
    return 0
  fi
  (cd "$path" && print_resume_context "$path" | bash -c "$resume_command")
}

perform_candidate_action() {
  local key="$1" path="$2" editor
  case "$key" in
    ctrl-o)
      editor="${DEV_EDITOR:-code}"
      need "$editor"
      "$editor" "$path"
      ;;
    ctrl-y)
      print_resume_context "$path" | clip_copy
      printf 'Resume context copied: %s\n' "$path" >&2
      ;;
    ctrl-a) run_resume_ai "$path" ;;
    ctrl-r) (cd "$path" && bash "$script_dir/ai.sh" review) ;;
    *) die "Unknown resume action: $key" ;;
  esac
}

select_candidate() {
  local rows selection key row path header
  need fzf
  rows="$(print_candidates)"
  if [ "$mode" = select ]; then
    header='Enter: cd here · Ctrl-O: VS Code · Ctrl-Y: copy · Ctrl-A: AI · Ctrl-R: review'
  else
    header='Enter: print path · Ctrl-O: VS Code · Ctrl-Y: copy · Ctrl-A: AI · Ctrl-R: review'
  fi
  selection="$(printf '%s\n' "$rows" | fzf \
    --delimiter=$'\t' \
    --with-nth=1,2,3 \
    --nth=1,2,3,4 \
    --expect=ctrl-o,ctrl-y,ctrl-a,ctrl-r \
    --header="$header" \
    --preview="bash \"$script_dir/resume.sh\" preview {4}" \
    --preview-window='right,65%,wrap' \
    --prompt='resume > ')" || exit 0
  key="$(printf '%s\n' "$selection" | sed -n '1p')"
  row="$(printf '%s\n' "$selection" | sed -n '2p')"
  [ -n "$row" ] || exit 0
  path="$(printf '%s' "$row" | cut -f4-)"
  [ -n "$path" ] || exit 0
  if [ -z "$key" ]; then
    printf '%s\n' "$path"
  elif [ "$mode" = select ]; then
    perform_candidate_action "$key" "$path" >&2
  else
    perform_candidate_action "$key" "$path"
  fi
}

case "$mode" in
  candidates) print_candidates ;;
  preview) print_preview "${1:-}" ;;
  context) print_resume_context "${1:-}" ;;
  select|manage) select_candidate ;;
  *) die "Unknown resume mode: $mode" ;;
esac
