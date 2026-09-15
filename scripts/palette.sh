#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$script_dir/lib.sh"

need fzf
need task

palette_mode="${1:-run}"
case "$palette_mode" in
  run|select) ;;
  *) die "Unknown palette mode: $palette_mode" ;;
esac

header="Dev Harness · global utilities"
rows=""

add_row() {
  rows="${rows}${1}"$'\t'"${2}"$'\t'"${3:-}"$'\n'
}

add_row help 'show the workflow cheat sheet' 'help commands workflow h'
add_row aliases 'show aliases and fast paths' 'aliases shortcuts aka'
add_row extend 'show how to add personal commands' 'extend custom extension plugin ext'
add_row open 'select a file below the current directory' 'file editor folder o'

resume_added=false
dirty_added=false
if [ -n "${DEV_WORKPLACE:-}" ] && [ -d "$(to_shell_path "$DEV_WORKPLACE")" ]; then
  add_row projects 'select a project path' 'project workspace workplace folder'
  add_row resume 'return to recent project or worktree context' 'resume continue recent context project worktree'
  add_row dirty 'select a dirty repository or worktree' 'dirty modified changes repo worktree'
  add_row search 'search workplace text' 'search text grep rg s workplace'
  add_row semantic 'search workplace code by meaning' 'semantic grepai meaning sem'
  add_row index 'initialize workplace semantic index' 'grepai index ollama embeddings'
  resume_added=true
  dirty_added=true
elif command -v atuin >/dev/null 2>&1; then
  add_row resume 'return to recent project or worktree context' 'resume continue recent context project worktree'
  resume_added=true
fi

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  root="$(repo_root)"
  repo="$(basename "$root")"
  branch="$(git branch --show-current)"
  status="$(git status --porcelain)"
  staged="$(printf '%s\n' "$status" | awk 'length($0) && substr($0,1,1) != " " && substr($0,1,1) != "?" {n++} END {print n+0}')"
  unstaged="$(printf '%s\n' "$status" | awk 'length($0) && substr($0,2,1) != " " && substr($0,1,2) != "??" {n++} END {print n+0}')"
  untracked="$(printf '%s\n' "$status" | awk 'substr($0,1,2) == "??" {n++} END {print n+0}')"
  worktrees="$(git worktree list --porcelain | awk '/^worktree / {n++} END {print n+0}')"
  total=$((staged + unstaged + untracked))
  header="$repo · ${branch:-detached} · +$staged ~$unstaged ?$untracked · ${worktrees} worktrees"

  if [ "$resume_added" = false ]; then
    add_row resume 'return to recent project or worktree context' 'resume continue recent context project worktree'
  fi
  if [ "$dirty_added" = false ]; then
    add_row dirty 'select a dirty repository or worktree' 'dirty modified changes repo worktree'
  fi
  add_row why 'explain the current repository context' 'why context orientation where'
  add_row handoff 'print or copy secret-filtered handoff context' 'handoff context copy session'
  add_row standup 'build a local daily status' 'standup status daily summary'
  add_row changed "open changed files ($total)" 'changes changed diff oc'
  add_row wt 'create a timestamped worktree' 'worktree branch'
  add_row worktrees "inspect or switch worktrees ($worktrees)" 'worktree list switch wts'
  add_row changes 'summarize changes relative to the saved base' 'changes diff main summary'
  add_row context 'select repository context for AI' 'context ai files ctx'
  add_row ai 'start the configured AI CLI here' 'codex claude gemini copilot opencode'
  add_row review "review selected changes with AI ($total)" 'review ai diff rv'
fi

if command -v docker >/dev/null 2>&1; then
  add_row logs 'select a container and follow logs' 'docker container logs'
  add_row shell 'select a container and open a shell' 'docker container terminal bash sh'
fi

if obsidian_executable >/dev/null 2>&1; then
  add_row note 'create an Obsidian note' 'note notes memory'
  add_row day 'open or append to today' 'daily today journal'
  add_row week 'open or append to this week' 'weekly summary'
  add_row todo 'list or create project TODO notes' 'todo task project priority'
  add_row todos 'list TODO notes from the entire vault' 'todos tasks global vault tds'
  add_row 'done' 'select and complete a TODO note' 'done complete task'
  add_row reopen 'select and reopen a completed TODO note' 'reopen open task'
  add_row focus 'select a priority TODO and its project' 'focus priority project foc'
fi

add_row doctor 'validate installation and configuration' 'doctor install config health'

custom_palette="${DEV_HARNESS_CUSTOM_PALETTE:-$HOME/.config/dev-harness/palette.tsv}"
if [ -f "$custom_palette" ]; then
  while IFS=$'\t' read -r custom_task custom_description custom_keywords; do
    case "$custom_task" in ''|'#'*) continue ;; esac
    if [ -z "$custom_description" ]; then
      warn "Ignored malformed palette entry for '$custom_task' in $custom_palette"
      continue
    fi
    add_row "$custom_task" "$custom_description" "$custom_keywords"
  done <"$custom_palette"
fi

selection="$(printf '%s' "$rows" | fzf \
  --delimiter=$'\t' \
  --nth=1,2,3 \
  --with-nth=1,2 \
  --header="$header" \
  --prompt='dev harness > ')" || exit 0

task_name="${selection%%$'\t'*}"
[ -n "$task_name" ] || exit 0
if [ "$palette_mode" = select ]; then
  printf '%s\n' "$task_name"
else
  exec task -g "$task_name"
fi
