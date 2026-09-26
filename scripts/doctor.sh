#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$script_dir/lib.sh"

json=false
strict=false
if [ "$#" -eq 0 ] && [ -n "${DEV_HARNESS_INPUT:-}" ]; then
  doctor_args=()
  read -r -a doctor_args <<<"$DEV_HARNESS_INPUT" || true
  if [ "${#doctor_args[@]}" -gt 0 ]; then
    set -- "${doctor_args[@]}"
  fi
fi
for arg in "$@"; do
  case "$arg" in
    --json) json=true ;;
    --all) strict=true ;;
    *) die "Unknown doctor option: $arg" ;;
  esac
done

groups=()
names=()
statuses=()
details=()
errors=0

add_check() {
  local group="$1" name="$2" status="$3" detail="$4"
  groups+=("$group")
  names+=("$name")
  statuses+=("$status")
  details+=("$detail")
  [ "$status" = error ] && errors=$((errors + 1))
  return 0
}

check_core_command() {
  local command_name="$1" resolved
  if resolved="$(command -v "$command_name" 2>/dev/null)"; then
    add_check Core "$command_name" ok "$resolved"
  else
    add_check Core "$command_name" error "not found in PATH"
  fi
}

check_optional_command() {
  local group="$1" command_name="$2" resolved
  if resolved="$(command -v "$command_name" 2>/dev/null)"; then
    add_check "$group" "$command_name" ok "$resolved"
  else
    add_check "$group" "$command_name" info "not installed"
  fi
}

check_core_command bash
check_core_command git
check_core_command task
check_core_command fzf
check_core_command rg

check_optional_command "Git UI" lazygit
check_optional_command Docker docker
check_optional_command Docker lazydocker
check_optional_command Kubernetes kubectl
check_optional_command Kubernetes k9s
check_optional_command Kubernetes stern
check_optional_command "Semantic search" grepai
check_optional_command "Semantic search" ollama

if obsidian_cmd="$(obsidian_executable 2>/dev/null)"; then
  add_check Knowledge obsidian ok "$(command -v "$obsidian_cmd")"
else
  add_check Knowledge obsidian info "official CLI is not enabled or not in PATH"
fi

check_optional_command History atuin
check_optional_command Integrations gh

if [ -n "${DEV_WORKPLACE:-}" ] && [ -d "$DEV_WORKPLACE" ]; then
  add_check Configuration DEV_WORKPLACE ok "$DEV_WORKPLACE"
  if [ -f "$DEV_WORKPLACE/.grepai/config.yaml" ]; then
    add_check "Semantic search" grepai-config ok "$DEV_WORKPLACE/.grepai/config.yaml"
  else
    add_check "Semantic search" grepai-config info "run gtask index after installing grepai"
  fi
  if [ -f "$DEV_WORKPLACE/.grepai/index.gob" ]; then
    add_check "Semantic search" grepai-index ok "$DEV_WORKPLACE/.grepai/index.gob"
  else
    add_check "Semantic search" grepai-index info "run gtask index after installing grepai"
  fi
else
  add_check Configuration DEV_WORKPLACE info "unset or directory does not exist"
fi

if [ -n "${DEV_OBSIDIAN_VAULT:-}" ]; then
  add_check Configuration DEV_OBSIDIAN_VAULT ok "$DEV_OBSIDIAN_VAULT"
else
  add_check Configuration DEV_OBSIDIAN_VAULT info "unset; the active Obsidian vault will be used"
fi

if [ -n "${DEV_AI_COMMAND:-}" ]; then
  ai_executable="${DEV_AI_COMMAND%% *}"
  if command -v "$ai_executable" >/dev/null 2>&1; then
    add_check Configuration DEV_AI_COMMAND ok "$DEV_AI_COMMAND"
  elif [ "$strict" = true ]; then
    add_check Configuration DEV_AI_COMMAND error "configured command is unavailable: $ai_executable"
  else
    add_check Configuration DEV_AI_COMMAND info "configured command is unavailable: $ai_executable"
  fi
else
  add_check Configuration DEV_AI_COMMAND info "unset"
fi

if [ -n "${DEV_AI_RESUME_COMMAND:-}" ]; then
  resume_ai_executable="${DEV_AI_RESUME_COMMAND%% *}"
  if command -v "$resume_ai_executable" >/dev/null 2>&1; then
    add_check Configuration DEV_AI_RESUME_COMMAND ok "$DEV_AI_RESUME_COMMAND"
  elif [ "$strict" = true ]; then
    add_check Configuration DEV_AI_RESUME_COMMAND error "configured command is unavailable: $resume_ai_executable"
  else
    add_check Configuration DEV_AI_RESUME_COMMAND info "configured command is unavailable: $resume_ai_executable"
  fi
fi

todo_priority="${DEV_TODO_DEFAULT_PRIORITY:-p2}"
case "$todo_priority" in
  p0|p1|p2|p3) add_check Configuration DEV_TODO_DEFAULT_PRIORITY ok "$todo_priority" ;;
  *) add_check Configuration DEV_TODO_DEFAULT_PRIORITY error "must be one of: p0, p1, p2, p3" ;;
esac

context_limit="${DEV_CONTEXT_MAX_LINES:-4000}"
case "$context_limit" in
  ''|*[!0-9]*|0) add_check Configuration DEV_CONTEXT_MAX_LINES error "must be a positive integer" ;;
  *) add_check Configuration DEV_CONTEXT_MAX_LINES ok "$context_limit" ;;
esac

resume_limit="${DEV_RESUME_LIMIT:-10}"
case "$resume_limit" in
  ''|*[!0-9]*|0) add_check Configuration DEV_RESUME_LIMIT error "must be a positive integer" ;;
  *) add_check Configuration DEV_RESUME_LIMIT ok "$resume_limit" ;;
esac

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g'
}

human_symbol() {
  case "$1" in
    ok) printf '✓' ;;
    info) printf '○' ;;
    error) printf '✗' ;;
    *) printf '?' ;;
  esac
}

if [ "$json" = true ]; then
  if [ "$errors" -eq 0 ]; then overall=true; else overall=false; fi
  printf '{"ok":%s,"checks":[' "$overall"
  for index in "${!names[@]}"; do
    [ "$index" -gt 0 ] && printf ','
    printf '{"name":"%s","status":"%s","detail":"%s","group":"%s"}' \
      "$(json_escape "${names[$index]}")" \
      "$(json_escape "${statuses[$index]}")" \
      "$(json_escape "${details[$index]}")" \
      "$(json_escape "${groups[$index]}")"
  done
  printf ']}\n'
else
  current_group=""
  for index in "${!names[@]}"; do
    if [ "${groups[$index]}" != "$current_group" ]; then
      [ -z "$current_group" ] || printf '\n'
      current_group="${groups[$index]}"
      printf '%s\n' "$current_group"
    fi
    printf '  %s %-22s %s\n' \
      "$(human_symbol "${statuses[$index]}")" \
      "${names[$index]}" \
      "${details[$index]}"
  done
fi

[ "$errors" -eq 0 ]
