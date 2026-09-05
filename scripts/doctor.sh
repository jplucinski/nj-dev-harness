#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$script_dir/lib.sh"

json=false
strict=false
if [ "$#" -eq 0 ] && [ -n "${DEV_HARNESS_INPUT:-}" ]; then
  read -r -a doctor_args <<<"$DEV_HARNESS_INPUT"
  set -- "${doctor_args[@]}"
fi
for arg in "$@"; do
  case "$arg" in
    --json) json=true ;;
    --all) strict=true ;;
    *) die "Unknown doctor option: $arg" ;;
  esac
done

names=()
statuses=()
details=()
errors=0

add_check() {
  names+=("$1")
  statuses+=("$2")
  details+=("$3")
  [ "$2" = error ] && errors=$((errors + 1))
  return 0
}

check_command() {
  local command_name="$1" required="$2" resolved
  if resolved="$(command -v "$command_name" 2>/dev/null)"; then
    add_check "$command_name" ok "$resolved"
  elif [ "$required" = true ] || [ "$strict" = true ]; then
    add_check "$command_name" error "not found in PATH"
  else
    add_check "$command_name" warn "not found in PATH"
  fi
}

check_command bash true
check_command task true
check_command git true
check_command fzf true
check_command rg true
check_command "${DEV_EDITOR:-code}" false
check_command docker false
check_command gh false
check_command atuin false

if obsidian_cmd="$(obsidian_executable 2>/dev/null)"; then
  add_check obsidian ok "$(command -v "$obsidian_cmd")"
elif [ "$strict" = true ]; then
  add_check obsidian error "official CLI is not enabled or not in PATH"
else
  add_check obsidian warn "official CLI is not enabled or not in PATH"
fi

if [ -n "${DEV_WORKPLACE:-}" ] && [ -d "$DEV_WORKPLACE" ]; then
  add_check DEV_WORKPLACE ok "$DEV_WORKPLACE"
elif [ "$strict" = true ]; then
  add_check DEV_WORKPLACE error "unset or directory does not exist"
else
  add_check DEV_WORKPLACE warn "unset or directory does not exist"
fi

if [ -n "${DEV_OBSIDIAN_VAULT:-}" ]; then
  add_check DEV_OBSIDIAN_VAULT ok "$DEV_OBSIDIAN_VAULT"
elif [ "$strict" = true ]; then
  add_check DEV_OBSIDIAN_VAULT error "unset; the active Obsidian vault would be used"
else
  add_check DEV_OBSIDIAN_VAULT warn "unset; the active Obsidian vault will be used"
fi

if [ -n "${DEV_AI_COMMAND:-}" ]; then
  ai_executable="${DEV_AI_COMMAND%% *}"
  if command -v "$ai_executable" >/dev/null 2>&1; then
    add_check DEV_AI_COMMAND ok "$DEV_AI_COMMAND"
  elif [ "$strict" = true ]; then
    add_check DEV_AI_COMMAND error "configured command is unavailable: $ai_executable"
  else
    add_check DEV_AI_COMMAND warn "configured command is unavailable: $ai_executable"
  fi
else
  if [ "$strict" = true ]; then
    add_check DEV_AI_COMMAND error "unset"
  else
    add_check DEV_AI_COMMAND warn "unset"
  fi
fi

if [ -n "${DEV_AI_RESUME_COMMAND:-}" ]; then
  resume_ai_executable="${DEV_AI_RESUME_COMMAND%% *}"
  if command -v "$resume_ai_executable" >/dev/null 2>&1; then
    add_check DEV_AI_RESUME_COMMAND ok "$DEV_AI_RESUME_COMMAND"
  elif [ "$strict" = true ]; then
    add_check DEV_AI_RESUME_COMMAND error "configured command is unavailable: $resume_ai_executable"
  else
    add_check DEV_AI_RESUME_COMMAND warn "configured command is unavailable: $resume_ai_executable"
  fi
fi

todo_priority="${DEV_TODO_DEFAULT_PRIORITY:-p2}"
case "$todo_priority" in
  p0|p1|p2|p3) add_check DEV_TODO_DEFAULT_PRIORITY ok "$todo_priority" ;;
  *) add_check DEV_TODO_DEFAULT_PRIORITY error "must be one of: p0, p1, p2, p3" ;;
esac

context_limit="${DEV_CONTEXT_MAX_LINES:-4000}"
case "$context_limit" in
  ''|*[!0-9]*|0) add_check DEV_CONTEXT_MAX_LINES error "must be a positive integer" ;;
  *) add_check DEV_CONTEXT_MAX_LINES ok "$context_limit" ;;
esac

resume_limit="${DEV_RESUME_LIMIT:-10}"
case "$resume_limit" in
  ''|*[!0-9]*|0) add_check DEV_RESUME_LIMIT error "must be a positive integer" ;;
  *) add_check DEV_RESUME_LIMIT ok "$resume_limit" ;;
esac

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g'
}

if [ "$json" = true ]; then
  if [ "$errors" -eq 0 ]; then overall=true; else overall=false; fi
  printf '{"ok":%s,"checks":[' "$overall"
  for index in "${!names[@]}"; do
    [ "$index" -gt 0 ] && printf ','
    printf '{"name":"%s","status":"%s","detail":"%s"}' \
      "$(json_escape "${names[$index]}")" \
      "$(json_escape "${statuses[$index]}")" \
      "$(json_escape "${details[$index]}")"
  done
  printf ']}\n'
else
  for index in "${!names[@]}"; do
    case "${statuses[$index]}" in
      ok) label='OK' ;;
      warn) label='WARN' ;;
      error) label='ERROR' ;;
    esac
    printf '[%-5s] %-22s %s\n' "$label" "${names[$index]}" "${details[$index]}"
  done
fi

[ "$errors" -eq 0 ]
