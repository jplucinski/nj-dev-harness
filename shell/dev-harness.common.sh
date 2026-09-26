# shellcheck shell=bash
# Dev Harness shell integration shared by Bash and Zsh adapters.

_dev_harness_home="${DEV_HARNESS_HOME:-$HOME/.dev-harness}"
_dev_harness_config="${DEV_HARNESS_CONFIG:-$HOME/.config/dev-harness/config.env}"

if [ -f "$_dev_harness_config" ]; then
  # shellcheck disable=SC1090
  . "$_dev_harness_config"
fi

# Adapters must set _dev_harness_atuin_shell to bash or zsh before sourcing this file.

_dev_harness_run_gtask_palette() {
  local selected selected_command atuin_bin atuin_id status

  if [ "$#" -gt 0 ]; then
    command task -g "$@"
    return
  fi

  selected="$(bash "$_dev_harness_home/scripts/palette.sh" select)" || return
  [ -n "$selected" ] || return

  selected_command="gtask $selected"

  if type _dev_harness_record_shell_history >/dev/null 2>&1; then
    _dev_harness_record_shell_history "$selected_command"
  fi

  atuin_id=""
  if [ -n "${ATUIN_SESSION:-}" ] && atuin_bin="$(command -v atuin 2>/dev/null)"; then
    atuin_id="$(ATUIN_SHELL="${_dev_harness_atuin_shell:-bash}" "$atuin_bin" history start -- "$selected_command" 2>/dev/null || true)"
  fi

  command task -g "$selected"
  status=$?

  if [ -n "$atuin_id" ]; then
    ATUIN_SHELL="${_dev_harness_atuin_shell:-bash}" "$atuin_bin" history end --exit "$status" -- "$atuin_id" >/dev/null 2>&1 || true
  fi
  return "$status"
}

unalias gtask 2>/dev/null || true
gtask() {
  _dev_harness_run_gtask_palette "$@"
}

alias gs='git status -sb'
alias gd='git diff'
alias gds='git diff --staged'
alias gl='git log --oneline --graph --decorate -20'
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias -- -='cd -'
alias ll='ls -lah'
alias la='ls -A'

unalias mkcd 2>/dev/null || true
mkcd() {
  [ "$#" -eq 1 ] && [ -n "$1" ] || {
    printf 'usage: mkcd DIR\n' >&2
    return 1
  }
  mkdir -p -- "$1" && cd -- "$1" || return
}

unalias gr 2>/dev/null || true
gr() {
  local root
  root="$(git rev-parse --show-toplevel 2>/dev/null)" || {
    printf 'Not inside a Git repository.\n' >&2
    return 1
  }
  cd "$root" || return
}

unalias resume 2>/dev/null || true
resume() {
  local selected
  selected="$(bash "$_dev_harness_home/scripts/resume.sh" select)" || return
  [ -n "$selected" ] || return 0
  cd "$selected" || return
}

unalias dirty 2>/dev/null || true
dirty() {
  local selected
  [ "$#" -eq 0 ] || {
    printf 'dirty does not accept arguments.\n' >&2
    return 1
  }
  selected="$(bash "$_dev_harness_home/scripts/dirty.sh" select)" || return
  [ -n "$selected" ] || return 0
  cd "$selected" || return
}

unalias why handoff standup 2>/dev/null || true
why() {
  bash "$_dev_harness_home/scripts/workflow.sh" why "$@"
}

handoff() {
  bash "$_dev_harness_home/scripts/workflow.sh" handoff "$@"
}

standup() {
  bash "$_dev_harness_home/scripts/workflow.sh" standup "$@"
}

unalias focus 2>/dev/null || true
focus() {
  local selected
  selected="$(bash "$_dev_harness_home/scripts/focus.sh" select "$@")" || return
  [ -n "$selected" ] || return 0
  cd "$selected" || return
}

cproj() {
  local selected
  selected="$(bash "$_dev_harness_home/scripts/project.sh" print)" || return
  [ -n "$selected" ] || return 0
  cd "$selected" || return
}

unalias cwork 2>/dev/null || true
cwork() {
  local selected
  [ "$#" -eq 0 ] || {
    printf 'cwork does not accept arguments.\n' >&2
    return 1
  }
  selected="$(bash "$_dev_harness_home/scripts/location.sh" workplace)" || return
  cd "$selected" || return
}

unalias cvault 2>/dev/null || true
cvault() {
  local selected
  [ "$#" -eq 0 ] || {
    printf 'cvault does not accept arguments.\n' >&2
    return 1
  }
  selected="$(bash "$_dev_harness_home/scripts/location.sh" vault)" || return
  cd "$selected" || return
}

oproj() {
  local selected editor
  printf 'oproj is deprecated; use cproj and press Ctrl-O to open in DEV_EDITOR.\n' >&2
  selected="$(bash "$_dev_harness_home/scripts/project.sh" print)" || return
  [ -n "$selected" ] || return
  editor="${DEV_EDITOR:-code}"
  "$editor" "$selected"
}

cwt() {
  local selected
  selected="$(bash "$_dev_harness_home/scripts/worktrees.sh" cd)" || return
  [ -n "$selected" ] || return 0
  cd "$selected" || return
}

owt() {
  printf 'owt is deprecated; use cwt and press Ctrl-O to open in DEV_EDITOR.\n' >&2
  bash "$_dev_harness_home/scripts/worktrees.sh" open
}

unalias lg 2>/dev/null || true
lg() {
  local bin
  bin="$(command -v lazygit 2>/dev/null)" || {
    printf 'lazygit is not installed.\n' >&2
    return 1
  }
  exec "$bin" "$@"
}

unalias ld 2>/dev/null || true
ld() {
  local bin
  bin="$(command -v lazydocker 2>/dev/null)" || {
    printf 'lazydocker is not installed.\n' >&2
    return 1
  }
  exec "$bin" "$@"
}

unalias k9 2>/dev/null || true
k9() {
  local bin
  bin="$(command -v k9s 2>/dev/null)" || {
    printf 'k9s is not installed.\n' >&2
    return 1
  }
  exec "$bin" "$@"
}

unset _dev_harness_config
