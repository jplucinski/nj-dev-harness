#!/usr/bin/env bash
set -euo pipefail

source_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

test_bash_shell_integration_sources() {
  bash -c '
    DEV_HARNESS_HOME="'"$source_dir"'"
    DEV_HARNESS_CONFIG=/dev/null
    # shellcheck disable=SC1090
    . "$DEV_HARNESS_HOME/shell/dev-harness.bash"
    type gtask >/dev/null
    type cproj >/dev/null
    type lg >/dev/null
  '
}

test_zsh_shell_integration_sources() {
  if ! command -v zsh >/dev/null 2>&1; then
    printf 'SKIP: zsh is not on PATH\n'
    return 0
  fi
  zsh -c '
    DEV_HARNESS_HOME="'"$source_dir"'"
    DEV_HARNESS_CONFIG=/dev/null
    # shellcheck disable=SC1090
    . "$DEV_HARNESS_HOME/shell/dev-harness.zsh"
    whence gtask >/dev/null
    whence cproj >/dev/null
    whence lg >/dev/null
  '
}

test_bash_shell_integration_sources
printf 'PASS: Bash shell integration sources\n'
test_zsh_shell_integration_sources
printf 'PASS: Zsh shell integration sources\n'
