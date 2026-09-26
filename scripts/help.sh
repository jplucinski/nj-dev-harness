#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$script_dir/lib.sh"

mode="${1:-help}"

show_help() {
  printf '%s\n' \
    'Dev Harness · Find → Do → Remember' \
    '' \
    'Start here' \
    '  gtask                 searchable palette; selection is saved to history' \
    '  resume                return to recent project or worktree context' \
    '  cproj                 select a project (Enter: cd · Ctrl-O: open · Ctrl-Y: copy)' \
    '  cwt                   select a worktree (Enter: cd · Ctrl-O: open · Ctrl-X: remove)' \
    '  lg / ld / k9          lazygit / lazydocker / k9s when installed' \
    '' \
    'Discover more' \
    '  gtask help            this workflow cheat sheet' \
    '  gtask aliases         shell, function, and Task shortcuts' \
    '  gtask extend          how to add personal commands' \
    '  gtask --list          every global Task command' \
    '' \
    'Console' \
    '  .. / ... / ....     cd up 1 / 2 / 3 directories' \
    '  -                   cd to the previous directory' \
    '  ll / la             ls -lah / ls -A' \
    '  mkcd DIR            mkdir -p DIR and cd into it' \
    '' \
    'Find' \
    '  gtask resume         inspect recent contexts without changing this shell' \
    '  cwork / cvault        cd to the workplace / Obsidian vault path' \
    '  gtask open            select a file below the current directory' \
    '  gtask changed         select a changed file' \
    '  gtask search -- TEXT  search workplace contents' \
    '  gtask semantic -- TEXT  search workplace code by meaning (requires grepai)' \
    '  gtask index           initialize the workplace semantic index (requires grepai)' \
    '' \
    'Do' \
    '  gtask wt -- BRANCH    create a timestamped worktree' \
    '  gtask worktrees       inspect or manage worktrees from the current repo' \
    '  gtask changes         summarize changes from the saved base' \
    '  gtask context         select bounded context for AI' \
    '  gtask review          review selected changes with AI (interactive fzf)' \
    '  gtask review -- --all review all filtered changes without the picker' \
    '  gtask ai              start the configured AI CLI' \
    '' \
    'Remember' \
    '  gtask note -- TITLE   create an ordinary Obsidian note' \
    '  gtask day -- TEXT     append to today' \
    '  gtask week -- TEXT    append to this week' \
    '  gtask todo -- p1 TEXT create a project TODO note' \
    '  gtask todo            list open TODOs for this project' \
    '  gtask todos           list open TODOs across the vault' \
    '  gtask todos -- done   list completed TODOs' \
    '  gtask done / reopen   complete / reopen via fzf' \
    '' \
    'Workflow utilities' \
    '  gr                    cd to the current repository root' \
    '  dirty                select a dirty repository/worktree and cd' \
    '  why                  explain the current repository context' \
    '  handoff [--copy]     print or copy secret-filtered resume context' \
    '  standup [--copy]     print or copy a local daily status' \
    '  standup --day        append the status to today in Obsidian' \
    '  focus [p0..p3]       select an open TODO and cd to its project' \
    '  Read-only defaults; none of these commands starts AI.' \
    '' \
    'Validate' \
    '  gtask doctor          show core and optional capabilities' \
    '  gtask doctor -- --all treat invalid configuration as errors'
}

show_aliases() {
  printf '%s\n' \
    'Dev Harness aliases and fast paths' \
    '' \
    'Core shell commands' \
    '  gtask    task -g plus palette and shell/Atuin history integration' \
    '  resume   select recent context and cd' \
    '  cproj    select project and cd (Ctrl-O opens DEV_EDITOR)' \
    '  cwt      select worktree and cd (Ctrl-O opens DEV_EDITOR)' \
    '  lg       lazygit' \
    '  ld       lazydocker' \
    '  k9       k9s' \
    '' \
    'Deprecated shell commands' \
    '  oproj    use cproj and press Ctrl-O' \
    '  owt      use cwt and press Ctrl-O' \
    '' \
    'Shell aliases' \
    '  gs       git status -sb' \
    '  gd       git diff' \
    '  gds      git diff --staged' \
    '  gl       git log --oneline --graph --decorate -20' \
    '  ..       cd ..' \
    '  ...      cd ../..' \
    '  ....     cd ../../..' \
    '  -        cd -' \
    '  ll       ls -lah' \
    '  la       ls -A' \
    '' \
    'Shell functions' \
    '  mkcd     mkdir -p DIR and cd into it' \
    '  gr       cd to the current repository root' \
    '  dirty    select a dirty repository/worktree and cd' \
    '  why      explain the current repository context' \
    '  handoff  print or copy secret-filtered resume context' \
    '  standup  print, copy, or append a local daily status' \
    '  focus    select an open TODO and cd to its project' \
    '  cwork    cd to DEV_WORKPLACE' \
    '  cvault   cd to DEV_OBSIDIAN_VAULT_PATH' \
    '' \
    'Task aliases' \
    '  gtask h          gtask help' \
    '  gtask aka        gtask aliases' \
    '  gtask ext        gtask extend' \
    '  gtask o          gtask open' \
    '  gtask oc         gtask changed' \
    '  gtask s          gtask search' \
    '  gtask sem        gtask semantic' \
    '  gtask worktree   gtask wt' \
    '  gtask wts        gtask worktrees' \
    '  gtask ctx        gtask context' \
    '  gtask rv         gtask review' \
    '  gtask tds        gtask todos' \
    '  gtask y          gtask why' \
    '  gtask hf         gtask handoff' \
    '  gtask stp        gtask standup' \
    '  gtask foc        gtask focus'
}

show_extend() {
  printf '%s\n' \
    'Extend Dev Harness' \
    '' \
    'Choose the smallest extension type' \
    '  alias      one existing command, only shorter' \
    '  function   must change the current shell, for example cd' \
    '  task       discoverable global command' \
    '  script     multi-step logic called by a task' \
    '  local task project-specific build, test, run, or deploy' \
    '' \
    '1. Add personal global tasks' \
    "   $HOME/.config/dev-harness/Taskfile.yml" \
    '' \
    "   version: '3'" \
    '   tasks:' \
    '     ports:' \
    '       desc: Show listening ports' \
    "       dir: '{{.USER_WORKING_DIR}}'" \
    '       cmds:' \
    '         - your-command-here' \
    '' \
    '   Personal tasks are included automatically and flattened, so run:' \
    '   gtask ports' \
    '' \
    '2. Make the task searchable in the fzf palette' \
    "   $HOME/.config/dev-harness/palette.tsv" \
    '' \
    '   Add one tab-separated line:' \
    '   ports<TAB>show listening ports<TAB>network ports sockets' \
    '' \
    '   Columns: task name, visible description, hidden search keywords.' \
    '' \
    '3. Add aliases or directory-changing functions' \
    '   Put personal aliases/functions in ~/.bashrc or ~/.zshrc after sourcing Dev Harness.' \
    '' \
    '4. Keep project behavior local' \
    '   Add build, test, run, deploy, and release tasks to that project Taskfile.' \
    '' \
    'Avoid editing ~/.dev-harness directly; reinstalling may replace those files.'
}

case "$mode" in
  help) show_help ;;
  aliases) show_aliases ;;
  extend) show_extend ;;
  *) die "Unknown help mode: $mode" ;;
esac
