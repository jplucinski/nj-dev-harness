# Dev Harness shell integration for Zsh.

_dev_harness_atuin_shell=zsh

_dev_harness_record_shell_history() {
  local selected_command="$1"
  if [[ -o interactive ]]; then
    print -s -- "$selected_command"
  fi
}

_common_file="${0:A:h}/dev-harness.common.sh"
# shellcheck disable=SC1090
. "$_common_file"
unset _common_file _dev_harness_atuin_shell _dev_harness_record_shell_history
