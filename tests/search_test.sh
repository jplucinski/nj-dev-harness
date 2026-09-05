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
