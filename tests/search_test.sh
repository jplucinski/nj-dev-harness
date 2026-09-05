#!/usr/bin/env bash
set -euo pipefail

source_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/dev-harness-search-test.XXXXXX")"

cleanup() {
  case "$test_root" in
    "${TMPDIR:-/tmp}"/dev-harness-search-test.*) rm -rf -- "$test_root" ;;
    *) printf 'Refusing unsafe test cleanup: %s\n' "$test_root" >&2 ;;
  esac
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  local haystack="$1" needle="$2"
  [[ "$haystack" == *"$needle"* ]] || fail "Expected output to contain: $needle"
}

assert_equals() {
  local actual="$1" expected="$2"
  [ "$actual" = "$expected" ] || fail "Expected '$expected', got '$actual'"
}

create_repo() {
  local path="$1"
  mkdir -p "$path"
  git -C "$path" init -q
  git -C "$path" symbolic-ref HEAD refs/heads/main
  git -C "$path" config user.email test@example.com
  git -C "$path" config user.name 'Dev Harness Test'
  git -C "$path" config core.autocrlf false
  printf 'fixture\n' > "$path/README.md"
  git -C "$path" add README.md
  git -C "$path" commit -q -m 'Initial commit'
}

create_command_wrapper() {
  local destination="$1" command_name="$2" resolved
  resolved="$(command -v "$command_name")"
  printf '#!/bin/sh\nexec "%s" "$@"\n' "$resolved" > "$destination/$command_name"
  chmod +x "$destination/$command_name"
}

test_workplace_root_requires_config() {
  local output status=0
  output="$(DEV_WORKPLACE= bash -c '. "'"$source_dir"'/scripts/lib.sh"; workplace_root' 2>&1)" || status=$?
  [ "$status" -ne 0 ] || fail 'workplace_root accepted an empty DEV_WORKPLACE'
  assert_contains "$output" 'Set DEV_WORKPLACE in ~/.config/dev-harness/config.env.'
}

test_workplace_root_requires_a_directory() {
  local missing="$test_root/missing-workplace" output status=0
  output="$(DEV_WORKPLACE="$missing" bash -c '. "'"$source_dir"'/scripts/lib.sh"; workplace_root' 2>&1)" || status=$?
  [ "$status" -ne 0 ] || fail 'workplace_root accepted a missing directory'
  assert_contains "$output" "DEV_WORKPLACE does not exist: $missing"
}

test_workplace_project_dirs_lists_sorted_children_including_spaces() {
  local workplace="$test_root/function action place" output
  mkdir -p "$workplace/zeta" "$workplace/alpha project"
  printf 'skip\n' > "$workplace/file.txt"
  output="$(DEV_WORKPLACE="$workplace" bash -c '. "'"$source_dir"'/scripts/lib.sh"; workplace_project_dirs')"
  assert_equals "$output" "$(printf '%s\n' "$(cd "$workplace/alpha project" && pwd -P)" "$(cd "$workplace/zeta" && pwd -P)")"
}

test_workplace_project_dirs_dies_when_empty() {
  local workplace="$test_root/empty-workplace" output status=0
  mkdir -p "$workplace"
  output="$(DEV_WORKPLACE="$workplace" bash -c '. "'"$source_dir"'/scripts/lib.sh"; workplace_project_dirs' 2>&1)" || status=$?
  [ "$status" -ne 0 ] || fail 'workplace_project_dirs accepted an empty workplace'
  assert_contains "$output" "No project directories found in $workplace"
}

search_reload() {
  DEV_WORKPLACE="$1" bash "$source_dir/scripts/search.sh" reload "$2"
}

test_reload_ignores_short_queries() {
  local workplace="$test_root/short-query" output
  mkdir -p "$workplace/payments"
  printf 'OrderService\n' > "$workplace/payments/A.java"
  output="$(search_reload "$workplace" '')"
  assert_equals "$output" ''
  output="$(search_reload "$workplace" 'O')"
  assert_equals "$output" ''
}

test_reload_finds_a_sibling_project_not_just_cwd() {
  local workplace="$test_root/function action place" output
  mkdir -p "$workplace/notes vault" "$workplace/payments/src"
  printf 'nothing\n' > "$workplace/notes vault/readme.md"
  printf 'public class OrderService {}\n' > "$workplace/payments/src/OrderService.java"
  output="$(
    cd "$workplace/notes vault"
    search_reload "$workplace" 'OrderService'
  )"
  assert_contains "$output" 'OrderService.java'
  assert_contains "$output" 'OrderService'
  [[ "$output" == *payments* ]] || fail 'reload did not search the sibling payments project'
}

test_reload_respects_child_gitignore() {
  local workplace="$test_root/ignore-child" output
  create_repo "$workplace/payments"
  printf 'secret-token\n' > "$workplace/payments/ignored.txt"
  printf 'ignored.txt\n' > "$workplace/payments/.gitignore"
  git -C "$workplace/payments" add .gitignore
  git -C "$workplace/payments" commit -q -m 'Ignore ignored.txt'
  printf 'visible-token\n' > "$workplace/payments/visible.txt"
  output="$(search_reload "$workplace" 'token')"
  assert_contains "$output" 'visible.txt'
  [[ "$output" != *ignored.txt* ]] || fail 'rg searched a gitignored file'
}

test_reload_searches_a_non_git_child() {
  local workplace="$test_root/plain-child" output
  mkdir -p "$workplace/scratch"
  printf 'OrderService\n' > "$workplace/scratch/notes.md"
  output="$(search_reload "$workplace" 'OrderService')"
  assert_contains "$output" 'notes.md'
}

test_live_search_opens_a_workplace_relative_match() {
  local workplace="$test_root/live-open" fake_bin editor_record output status=0
  fake_bin="$workplace/bin"
  editor_record="$workplace/editor-argument"
  mkdir -p "$workplace/payments/src" "$fake_bin"
  printf 'public class OrderService {}\n' > "$workplace/payments/src/OrderService.java"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'printf "\n%s\n" "payments/src/OrderService.java:1:8:OrderService"' \
    > "$fake_bin/fzf"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'printf "%s\n" "$*" > "$EDITOR_RECORD"' \
    > "$fake_bin/code"
  chmod +x "$fake_bin/fzf" "$fake_bin/code"

  output="$(
    PATH="$fake_bin:$PATH" DEV_WORKPLACE="$workplace" DEV_EDITOR=code EDITOR_RECORD="$editor_record" \
      bash "$source_dir/scripts/search.sh" live
  )" || status=$?

  [ "$status" -eq 0 ] || fail "live search failed: $output"
  assert_contains "$(cat "$editor_record")" "--goto"
  assert_contains "$(cat "$editor_record")" "payments/src/OrderService.java:1:8"
}

test_open_search_mode_is_removed() {
  local fixture="$test_root/open-search-removed" fake_bin output status=0
  fake_bin="$fixture/bin"
  mkdir -p "$fake_bin"
  printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$fake_bin/fzf"
  printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$fake_bin/rg"
  printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$fake_bin/code"
  chmod +x "$fake_bin/fzf" "$fake_bin/rg" "$fake_bin/code"
  output="$(PATH="$fake_bin:$PATH" DEV_EDITOR=code bash "$source_dir/scripts/open.sh" search 2>&1)" || status=$?
  [ "$status" -ne 0 ] || fail 'open.sh still accepts search'
  assert_contains "$output" 'Unknown open mode: search'
}

test_palette_offers_search_outside_git_when_workplace_exists() {
  local fixture="$test_root/palette-search" workplace bin palette_log
  workplace="$fixture/workplace"
  bin="$fixture/bin"
  palette_log="$fixture/palette.tsv"
  mkdir -p "$workplace/payments" "$bin"
  printf '%s\n' '#!/usr/bin/env bash' 'cat > "$PALETTE_LOG"' 'exit 130' > "$bin/fzf"
  printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$bin/task"
  chmod +x "$bin/fzf" "$bin/task"
  PATH="$bin:$(dirname "$(command -v git)"):/usr/bin:/bin" \
    DEV_WORKPLACE="$workplace" PALETTE_LOG="$palette_log" \
    bash "$source_dir/scripts/palette.sh" select || true
  assert_contains "$(cat "$palette_log")" $'search\t'
}

test_palette_hides_search_without_workplace() {
  local fixture="$test_root/palette-no-workplace" bin palette_log
  bin="$fixture/bin"
  palette_log="$fixture/palette.tsv"
  mkdir -p "$bin" "$fixture/plain"
  printf '%s\n' '#!/usr/bin/env bash' 'cat > "$PALETTE_LOG"' 'exit 130' > "$bin/fzf"
  printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$bin/task"
  chmod +x "$bin/fzf" "$bin/task"
  (
    cd "$fixture/plain"
    PATH="$bin:$(dirname "$(command -v git)"):/usr/bin:/bin" \
      DEV_WORKPLACE= PALETTE_LOG="$palette_log" \
      bash "$source_dir/scripts/palette.sh" select || true
  )
  if grep -Eq '^search\t' "$palette_log"; then
    fail 'search appeared without DEV_WORKPLACE'
  fi
}

test_search_preview_reads_the_workplace_file() {
  local workplace="$test_root/preview-workplace" output
  mkdir -p "$workplace/payments"
  printf 'alpha-line\nOrderService\n' > "$workplace/payments/A.java"
  output="$(
    DEV_WORKPLACE="$workplace" \
      bash "$source_dir/scripts/preview.sh" search 'payments/A.java:2:1:OrderService'
  )"
  assert_contains "$output" 'OrderService'
}

install_fake_grepai() {
  local bin="$1" log="$2" behavior="${3:-full}"
  mkdir -p "$bin"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    "log='$log'" \
    "behavior='$behavior'" \
    'printf "%s\n" "$*" >> "$log"' \
    'case "$1" in' \
    '  init)' \
    '    mkdir -p .grepai' \
    '    : > .grepai/config.yaml' \
    '    exit 0' \
    '    ;;' \
    '  index)' \
    '    if [ "${2:-}" = --help ]; then' \
    '      [ "$behavior" = has-index ] || exit 1' \
    '      exit 0' \
    '    fi' \
    '    mkdir -p .grepai' \
    '    printf "indexed\n" > .grepai/index.gob' \
    '    exit 0' \
    '    ;;' \
    '  watch)' \
    '    case "${2:-}" in' \
    '      --status) [ "$behavior" = watch-running ] && exit 0; exit 1 ;;' \
    '      --background) mkdir -p .grepai; printf "watched\n" > .grepai/index.gob; exit 0 ;;' \
    '      *) exit 1 ;;' \
    '    esac' \
    '    ;;' \
    '  search)' \
    '    cat <<'\''EOF'\''' \
    '{' \
    '  "query": "authentication",' \
    '  "results": [' \
    '    {' \
    '      "score": 0.92,' \
    '      "file": "payments/src/Auth.java",' \
    '      "start_line": 15,' \
    '      "end_line": 45,' \
    '      "content": "class Auth {"' \
    '    }' \
    '  ],' \
    '  "total": 1' \
    '}' \
    'EOF' \
    '    ;;' \
    '  *) exit 1 ;;' \
    'esac' \
    > "$bin/grepai"
  chmod +x "$bin/grepai"
}

prepare_workplace() {
  local workplace="$1"
  mkdir -p "$workplace/payments/src"
  printf 'class Auth {}\n' > "$workplace/payments/src/Auth.java"
}

test_index_requires_grepai() {
  local workplace="$test_root/index-missing-grepai" fake_bin output status=0
  prepare_workplace "$workplace"
  fake_bin="$workplace/bin"
  mkdir -p "$fake_bin"
  output="$(
    PATH="$fake_bin:/usr/bin:/bin" DEV_WORKPLACE="$workplace" \
      bash "$source_dir/scripts/search.sh" index 2>&1
  )" || status=$?
  [ "$status" -ne 0 ] || fail 'index accepted a PATH without grepai'
  assert_contains "$output" 'Missing command: grepai'
}

test_index_inits_once_then_runs_index_subcommand() {
  local workplace="$test_root/index-has-index" fake_bin log
  prepare_workplace "$workplace"
  fake_bin="$workplace/bin"
  log="$workplace/grepai.log"
  install_fake_grepai "$fake_bin" "$log" has-index
  PATH="$fake_bin:$PATH" DEV_WORKPLACE="$workplace" \
    bash "$source_dir/scripts/search.sh" index
  assert_contains "$(cat "$log")" 'init --yes --provider ollama --backend gob'
  [ -f "$workplace/.grepai/config.yaml" ] || fail 'index did not create config.yaml'
  [ -f "$workplace/.grepai/index.gob" ] || fail 'index did not create index.gob'
  : > "$log"
  PATH="$fake_bin:$PATH" DEV_WORKPLACE="$workplace" \
    bash "$source_dir/scripts/search.sh" index
  if grep -q 'init ' "$log"; then
    fail 'index ran init again when config.yaml already existed'
  fi
  assert_contains "$(cat "$log")" 'index'
}

test_index_falls_back_to_watch_background() {
  local workplace="$test_root/index-watch" fake_bin log
  prepare_workplace "$workplace"
  fake_bin="$workplace/bin"
  log="$workplace/grepai.log"
  install_fake_grepai "$fake_bin" "$log" watch-only
  PATH="$fake_bin:$PATH" DEV_WORKPLACE="$workplace" \
    bash "$source_dir/scripts/search.sh" index
  assert_contains "$(cat "$log")" 'watch --background'
}

test_index_skips_watch_when_already_running() {
  local workplace="$test_root/index-running" fake_bin log
  prepare_workplace "$workplace"
  mkdir -p "$workplace/.grepai"
  : > "$workplace/.grepai/config.yaml"
  printf 'seed\n' > "$workplace/.grepai/index.gob"
  fake_bin="$workplace/bin"
  log="$workplace/grepai.log"
  install_fake_grepai "$fake_bin" "$log" watch-running
  PATH="$fake_bin:$PATH" DEV_WORKPLACE="$workplace" \
    bash "$source_dir/scripts/search.sh" index
  assert_contains "$(cat "$log")" 'watch --status'
  if grep -q 'watch --background' "$log"; then
    fail 'index started a second watcher'
  fi
}

test_semantic_requires_index() {
  local workplace="$test_root/semantic-no-index" fake_bin output status=0
  prepare_workplace "$workplace"
  fake_bin="$workplace/bin"
  log="$workplace/grepai.log"
  install_fake_grepai "$fake_bin" "$log" has-index
  output="$(
    PATH="$fake_bin:$PATH" DEV_WORKPLACE="$workplace" \
      bash "$source_dir/scripts/search.sh" semantic 2>&1
  )" || status=$?
  [ "$status" -ne 0 ] || fail 'semantic ran without an index'
  assert_contains "$output" 'gtask index'
}

test_semantic_opens_a_formatted_match() {
  local workplace="$test_root/semantic-open" fake_bin editor_record output status=0
  prepare_workplace "$workplace"
  mkdir -p "$workplace/.grepai"
  : > "$workplace/.grepai/config.yaml"
  printf 'seed\n' > "$workplace/.grepai/index.gob"
  fake_bin="$workplace/bin"
  install_fake_grepai "$fake_bin" "$workplace/grepai.log" has-index
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'printf "\n%s\n" "payments/src/Auth.java:15:1:0.92 class Auth {"' \
    > "$fake_bin/fzf"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'printf "%s\n" "$*" > "$EDITOR_RECORD"' \
    > "$fake_bin/code"
  chmod +x "$fake_bin/fzf" "$fake_bin/code"
  output="$(
    PATH="$fake_bin:$PATH" DEV_WORKPLACE="$workplace" DEV_EDITOR=code \
    EDITOR_RECORD="$workplace/editor-argument" DEV_HARNESS_INPUT='authentication' \
      bash "$source_dir/scripts/search.sh" semantic
  )" || status=$?
  [ "$status" -eq 0 ] || fail "semantic search failed: $output"
  assert_contains "$(cat "$workplace/editor-argument")" "--goto"
  assert_contains "$(cat "$workplace/editor-argument")" "payments/src/Auth.java:15:1"
}

test_semantic_empty_query_exits_without_search() {
  local workplace="$test_root/semantic-empty" fake_bin log status=0
  prepare_workplace "$workplace"
  mkdir -p "$workplace/.grepai"
  : > "$workplace/.grepai/config.yaml"
  printf 'seed\n' > "$workplace/.grepai/index.gob"
  fake_bin="$workplace/bin"
  log="$workplace/grepai.log"
  install_fake_grepai "$fake_bin" "$log" has-index
  PATH="$fake_bin:$PATH" DEV_WORKPLACE="$workplace" DEV_HARNESS_INPUT= \
    bash "$source_dir/scripts/search.sh" semantic </dev/null || status=$?
  [ "$status" -eq 0 ] || fail 'empty semantic query should exit 0'
  if grep -q 'search' "$log" 2>/dev/null; then
    fail 'semantic searched with an empty query'
  fi
}

test_workplace_root_requires_config
printf 'PASS: workplace_root requires DEV_WORKPLACE\n'
test_workplace_root_requires_a_directory
printf 'PASS: workplace_root requires a directory\n'
test_workplace_project_dirs_lists_sorted_children_including_spaces
printf 'PASS: workplace_project_dirs lists sorted children\n'
test_workplace_project_dirs_dies_when_empty
printf 'PASS: workplace_project_dirs dies when empty\n'
test_reload_ignores_short_queries
printf 'PASS: reload ignores short queries\n'
test_reload_finds_a_sibling_project_not_just_cwd
printf 'PASS: reload finds a sibling project\n'
test_reload_respects_child_gitignore
printf 'PASS: reload respects child gitignore\n'
test_reload_searches_a_non_git_child
printf 'PASS: reload searches a non-git child\n'
test_live_search_opens_a_workplace_relative_match
printf 'PASS: live search opens a workplace-relative match\n'
test_open_search_mode_is_removed
printf 'PASS: open.sh search mode is removed\n'
test_palette_offers_search_outside_git_when_workplace_exists
printf 'PASS: palette offers search outside Git when workplace exists\n'
test_palette_hides_search_without_workplace
printf 'PASS: palette hides search without workplace\n'
test_search_preview_reads_the_workplace_file
printf 'PASS: search preview reads the workplace file\n'
test_index_requires_grepai
printf 'PASS: index requires grepai\n'
test_index_inits_once_then_runs_index_subcommand
printf 'PASS: index inits once then runs index\n'
test_index_falls_back_to_watch_background
printf 'PASS: index falls back to watch --background\n'
test_index_skips_watch_when_already_running
printf 'PASS: index skips watch when already running\n'
test_semantic_requires_index
printf 'PASS: semantic requires gtask index\n'
test_semantic_opens_a_formatted_match
printf 'PASS: semantic opens a formatted match\n'
test_semantic_empty_query_exits_without_search
printf 'PASS: empty semantic query exits without search\n'
