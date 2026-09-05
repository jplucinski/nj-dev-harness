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

add_row help 'show the workflow cheat sheet' 'pomoc commands komendy workflow h'
add_row aliases 'show aliases and fast paths' 'aliasy skróty shortcuts aka'
add_row extend 'show how to add personal commands' 'rozszerzanie custom własne extension plugin ext'
add_row open 'select a file below the current directory' 'plik file editor katalog folder o'

resume_added=false
dirty_added=false
if [ -n "${DEV_WORKPLACE:-}" ] && [ -d "$(to_shell_path "$DEV_WORKPLACE")" ]; then
  add_row projects 'select a project path' 'projekt workspace workplace katalog'
  add_row resume 'return to recent project or worktree context' 'wznow wróć continue recent context projekt worktree'
  add_row dirty 'select a dirty repository or worktree' 'dirty brudne zmiany modified repo worktree'
  add_row search 'search workplace text' 'szukaj tekst grep rg s workplace'
  add_row semantic 'search workplace code by meaning' 'semantic grepai szukaj znaczenie sem'
  add_row index 'initialize workplace semantic index' 'grepai index ollama embeddings'
  resume_added=true
  dirty_added=true
elif command -v atuin >/dev/null 2>&1; then
  add_row resume 'return to recent project or worktree context' 'wznow wróć continue recent context projekt worktree'
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
    add_row resume 'return to recent project or worktree context' 'wznow wróć continue recent context projekt worktree'
  fi
  if [ "$dirty_added" = false ]; then
    add_row dirty 'select a dirty repository or worktree' 'dirty brudne zmiany modified repo worktree'
  fi
  add_row why 'explain the current repository context' 'why dlaczego kontekst orientation gdzie jestem'
  add_row handoff 'print or copy secret-filtered handoff context' 'handoff przekazanie kontekst copy sesja'
  add_row standup 'build a local daily status' 'standup status dzienny daily podsumowanie'
  add_row changed "open changed files ($total)" 'zmiany changed diff oc'
  add_row wt 'create a timestamped worktree' 'worktree branch gałąź'
  add_row worktrees "inspect or switch worktrees ($worktrees)" 'worktree lista przełącz wts'
  add_row changes 'summarize changes relative to the saved base' 'zmiany diff main summary'
  add_row context 'select repository context for AI' 'kontekst ai files ctx'
  add_row ai 'start the configured AI CLI here' 'codex claude gemini copilot opencode'
  add_row review "review selected changes with AI ($total)" 'recenzja przegląd ai diff rv'
fi

if command -v docker >/dev/null 2>&1; then
  add_row logs 'select a container and follow logs' 'docker kontener logi'
  add_row shell 'select a container and open a shell' 'docker kontener terminal bash sh'
fi

if obsidian_executable >/dev/null 2>&1; then
  add_row note 'create an Obsidian note' 'notatka notes pamięć'
  add_row day 'open or append to today' 'daily dzisiaj dzień journal'
  add_row week 'open or append to this week' 'weekly tydzień podsumowanie'
  add_row todo 'list or create project TODO notes' 'zadanie task projekt priority'
  add_row todos 'list TODO notes from the entire vault' 'zadania tasks global vault tds'
  add_row done 'select and complete a TODO note' 'wykonane zakończ complete task'
  add_row reopen 'select and reopen a completed TODO note' 'przywróć otwórz task'
  add_row focus 'select a priority TODO and its project' 'focus priorytet skupienie zadanie project foc'
fi

add_row doctor 'validate installation and configuration' 'walidacja instalacja config health'

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
