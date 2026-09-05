#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$script_dir/lib.sh"

need git
mode="${1:-summary}"
shift || true
selected_paths=("$@")
root="$(repo_root)"
cd "$root"
sensitive_pathspec=""

base_ref=""
base_sha=""
repository="$(basename "$root")"
has_head=false

if git rev-parse --verify HEAD >/dev/null 2>&1; then
  has_head=true
  base_ref="$(default_branch)"
  [ -n "$base_ref" ] || die "Could not determine the default branch. Set DEV_MAIN_BRANCH."

  metadata="$(dirname "$root")/.dev-harness/$(basename "$root").meta"
  if [ -f "$metadata" ]; then
    base_sha="$(sed -n 's/^base_sha=//p' "$metadata" | head -n 1)"
    saved_ref="$(sed -n 's/^base_ref=//p' "$metadata" | head -n 1)"
    saved_repo="$(sed -n 's/^repo=//p' "$metadata" | head -n 1)"
    [ -n "$saved_ref" ] && base_ref="$saved_ref"
    [ -n "$saved_repo" ] && repository="$saved_repo"
  fi

  if [ -z "$base_sha" ] || ! git cat-file -e "$base_sha^{commit}" 2>/dev/null; then
    base_sha="$(git merge-base HEAD "$base_ref" 2>/dev/null || git rev-parse "$base_ref^{commit}")"
  fi
fi

branch="$(git branch --show-current)"
if [ "${#selected_paths[@]}" -gt 0 ]; then
  context_paths=()
  for selected_path in "${selected_paths[@]}"; do
    if is_sensitive_path "$selected_path"; then
      warn "Excluded sensitive path from context: $selected_path"
    else
      context_paths+=(":(literal)$selected_path")
    fi
  done
  [ "${#context_paths[@]}" -gt 0 ] || die "No safe paths remain in the selected context."
else
  context_paths=(.)
  while IFS= read -r sensitive_pathspec; do
    context_paths+=("$sensitive_pathspec")
  done < <(sensitive_git_pathspecs)
fi

path_is_selected() {
  local candidate="$1" selected_path
  [ "${#selected_paths[@]}" -eq 0 ] && return 0
  for selected_path in "${selected_paths[@]}"; do
    [ "$candidate" = "$selected_path" ] && return 0
  done
  return 1
}

safe_untracked() {
  local candidate
  while IFS= read -r candidate; do
    is_sensitive_path "$candidate" && continue
    path_is_selected "$candidate" && printf '%s\n' "$candidate"
  done < <(git ls-files --others --exclude-standard)
  return 0
}

print_untracked_diffs() {
  local candidate status
  while IFS= read -r candidate; do
    [ -n "$candidate" ] || continue
    if git diff --no-index --no-ext-diff --unified=3 -- /dev/null "$candidate"; then
      :
    else
      status=$?
      [ "$status" -eq 1 ] || return "$status"
    fi
  done < <(safe_untracked)
}

safe_changed_files() {
  {
    if [ "$has_head" = true ]; then
      git diff --name-only --diff-filter=ACMR "$base_sha...HEAD" -- "${context_paths[@]}" || true
    fi
    git diff --cached --name-only --diff-filter=ACMR -- "${context_paths[@]}" || true
    git diff --name-only --diff-filter=ACMR -- "${context_paths[@]}" || true
    safe_untracked
  } | sort -u
}

safe_staged_files() {
  git diff --cached --name-only --diff-filter=ACMR -- "${context_paths[@]}" || true
}

print_summary() {
  printf 'Repository: %s\n' "$repository"
  printf 'Branch:     %s\n' "${branch:-detached HEAD}"
  if [ "$has_head" = true ]; then
    printf 'Base:       %s (%s)\n\n' "$base_ref" "$base_sha"
  else
    printf 'Base:       no commits yet\n\n'
  fi

  printf 'Commits since base:\n'
  if [ "$has_head" = true ]; then
    git log --oneline "$base_sha..HEAD" || true
  fi
  printf '\nCommitted changes:\n'
  if [ "$has_head" = true ]; then
    git diff --name-status "$base_sha...HEAD" -- "${context_paths[@]}" || true
  fi
  printf '\nStaged changes:\n'
  git diff --cached --name-status -- "${context_paths[@]}" || true
  printf '\nUnstaged changes:\n'
  git diff --name-status -- "${context_paths[@]}" || true
  printf '\nUntracked files:\n'
  safe_untracked
}

print_context() {
  max_lines="${DEV_CONTEXT_MAX_LINES:-4000}"
  case "$max_lines" in
    ''|*[!0-9]*|0) die "DEV_CONTEXT_MAX_LINES must be a positive integer." ;;
  esac

  print_summary
  printf '\nDiff statistics:\n'
  if [ "$has_head" = true ]; then
    git diff --stat "$base_sha...HEAD" -- "${context_paths[@]}" || true
  fi
  git diff --cached --stat -- "${context_paths[@]}" || true
  git diff --stat -- "${context_paths[@]}" || true
  printf '\nBounded diff (maximum %s lines):\n' "$max_lines"
  {
    if [ "$has_head" = true ]; then
      git diff --no-ext-diff --unified=3 "$base_sha...HEAD" -- "${context_paths[@]}" || true
    fi
    git diff --no-ext-diff --unified=3 --cached -- "${context_paths[@]}" || true
    git diff --no-ext-diff --unified=3 -- "${context_paths[@]}" || true
    print_untracked_diffs
  } | head -n "$max_lines"
}

case "$mode" in
  summary) print_summary ;;
  context) print_context ;;
  files) safe_changed_files ;;
  staged-files) safe_staged_files ;;
  *) die "Unknown changes mode: $mode" ;;
esac
