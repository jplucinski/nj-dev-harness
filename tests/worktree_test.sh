#!/usr/bin/env bash
set -euo pipefail

source_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/dev-harness-worktree-test.XXXXXX")"

cleanup() {
  case "$test_root" in
    "${TMPDIR:-/tmp}"/dev-harness-worktree-test.*) rm -rf -- "$test_root" ;;
    *) printf 'Refusing unsafe test cleanup: %s\n' "$test_root" >&2 ;;
  esac
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_equals() {
  local actual="$1" expected="$2"
  [ "$actual" = "$expected" ] || fail "Expected '$expected', got '$actual'"
}

assert_file() {
  [ -f "$1" ] || fail "Expected file: $1"
}

git_path() {
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -m "$1"
  else
    cd "$1" && pwd -P
  fi
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

create_date_wrapper() {
  local bin="$1" real_date
  real_date="$(command -v date)"
  mkdir -p "$bin"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'case "$1" in' \
    "  '+%Y%m%d-%H%M%S') printf '%s\\n' '20260902-123456' ;;" \
    "  '+%Y-%m-%dT%H:%M:%S%z') printf '%s\\n' '2026-09-02T12:34:56+0200' ;;" \
    "  *) exec \"$real_date\" \"\$@\" ;;" \
    'esac' > "$bin/date"
  chmod +x "$bin/date"
}

run_worktree() {
  local repo="$1" root="$2" fake_bin="$3" branch="$4"
  (
    cd "$repo"
    if [ -n "$root" ]; then
      PATH="$fake_bin:$PATH" DEV_MAIN_BRANCH=main DEV_WORKTREE_ROOT="$root" \
        bash "$source_dir/scripts/worktree.sh" "$branch"
    else
      PATH="$fake_bin:$PATH" DEV_MAIN_BRANCH=main \
        bash "$source_dir/scripts/worktree.sh" "$branch"
    fi
  ) | tail -n 1
}

test_new_worktree_has_timestamped_name_and_complete_metadata() {
  local fixture="$test_root/metadata" repo root fake_bin output expected_path metadata base_sha expected_metadata
  repo="$fixture/inventory"
  root="$fixture/.worktrees"
  fake_bin="$fixture/bin"
  create_repo "$repo"
  repo="$(cd "$repo" && pwd -P)"
  mkdir -p "$root"
  root="$(cd "$root" && pwd -P)"
  create_date_wrapper "$fake_bin"
  base_sha="$(git -C "$repo" rev-parse main^{commit})"

  output="$(run_worktree "$repo" '' "$fake_bin" 'feature/receipt')"
  expected_path="$root/inventory-feature-receipt-20260902-123456"
  assert_equals "$output" "$expected_path"
  [ -e "$expected_path/.git" ] || fail 'Expected a Git worktree at the reported path'
  metadata="$root/.dev-harness/$(basename "$expected_path").meta"
  assert_file "$metadata"
  expected_metadata="$(printf 'repo=inventory\nbase_ref=main\nbase_sha=%s\nbranch=feature/receipt\ncreated=2026-09-02T12:34:56+0200\npath=%s' "$base_sha" "$expected_path")"
  assert_equals "$(tr -d '\r' < "$metadata")" "$expected_metadata"
}

test_existing_timestamped_target_uses_numeric_suffix() {
  local fixture="$test_root/collision" repo root fake_bin original target output marker
  repo="$fixture/catalog"
  root="$fixture/worktrees"
  fake_bin="$fixture/bin"
  create_repo "$repo"
  repo="$(cd "$repo" && pwd -P)"
  mkdir -p "$root"
  root="$(cd "$root" && pwd -P)"
  create_date_wrapper "$fake_bin"
  original="$root/catalog-feature-collision-20260902-123456"
  mkdir -p "$original"
  marker='do not replace this collision target'
  printf '%s\n' "$marker" > "$original/preserved.txt"

  output="$(run_worktree "$repo" "$root" "$fake_bin" 'feature/collision')"
  target="$original-2"
  assert_equals "$output" "$target"
  assert_file "$original/preserved.txt"
  assert_equals "$(cat "$original/preserved.txt")" "$marker"
  [ -e "$target/.git" ] || fail 'Expected worktree at the numeric collision suffix'
}

test_worktree_paths_with_spaces_are_preserved() {
  local fixture="$test_root/space paths" repo root fake_bin output expected
  repo="$fixture/customer portal"
  root="$fixture/worktree root"
  fake_bin="$fixture/bin"
  create_repo "$repo"
  repo="$(cd "$repo" && pwd -P)"
  mkdir -p "$root"
  root="$(cd "$root" && pwd -P)"
  create_date_wrapper "$fake_bin"

  output="$(run_worktree "$repo" "$root" "$fake_bin" 'feature/space-safe')"
  expected="$root/customer portal-feature-space-safe-20260902-123456"
  assert_equals "$(basename "$output")" "$(basename "$expected")"
  [ -e "$output/.git" ] || fail 'Worktree path containing spaces is not usable'
  assert_file "$root/.dev-harness/$(basename "$expected").meta"
  assert_equals "$(git -C "$output" rev-parse --show-toplevel)" "$(git_path "$output")"
  assert_equals "$(git -C "$output" branch --show-current)" 'feature/space-safe'
}

test_new_worktree_has_timestamped_name_and_complete_metadata
printf 'PASS: worktree name and metadata are deterministic\n'
test_existing_timestamped_target_uses_numeric_suffix
printf 'PASS: worktree collision uses a numeric suffix\n'
test_worktree_paths_with_spaces_are_preserved
printf 'PASS: worktree paths with spaces remain valid\n'
