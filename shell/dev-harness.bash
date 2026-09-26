# Dev Harness shell integration for Bash and Git Bash.

_dev_harness_atuin_shell=bash

_dev_harness_record_shell_history() {
  local selected_command="$1"
  if [[ $- == *i* ]]; then
    builtin history -s "$selected_command"
    if [ -n "${HISTFILE:-}" ]; then
      builtin history -a
    fi
  fi
}

_common_file="${BASH_SOURCE[0]%/*}/dev-harness.common.sh"
# shellcheck disable=SC1090
. "$_common_file"
unset _common_file _dev_harness_atuin_shell _dev_harness_record_shell_history
