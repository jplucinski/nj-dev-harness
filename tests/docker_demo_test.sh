#!/usr/bin/env bash
set -euo pipefail

test_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$test_dir/.." && pwd)"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/dev-harness-docker-demo-test.XXXXXX")"

cleanup() {
  case "$test_root" in
    "${TMPDIR:-/tmp}"/dev-harness-docker-demo-test.*) rm -rf -- "$test_root" ;;
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

demo_home="$test_root/home"
workplace="$demo_home/Workplace"
repo="$workplace/payments-demo"
mkdir -p "$demo_home"

output="$(
  HOME="$demo_home" \
  DEV_WORKPLACE="$workplace" \
  GIT_CONFIG_GLOBAL=/dev/null \
  GIT_CONFIG_SYSTEM=/dev/null \
    bash "$root/demo/entrypoint.sh" --prepare-only
)"

assert_contains "$output" 'Dev Harness demo'
[ -d "$repo/.git" ] || fail 'Demo did not create the sample Git repository'
[ "$(git -C "$repo" branch --show-current)" = main ] || fail 'Demo repository is not on main'
[ "$(git -C "$repo" rev-list --count HEAD)" = 1 ] || fail 'Demo repository should contain one baseline commit'

status="$(git -C "$repo" status --short --untracked-files=all)"
assert_contains "$status" 'M src/PaymentService.java'
assert_contains "$status" '?? notes/retry-plan.md'

printf 'preserve me\n' > "$repo/preserve-me.txt"
HOME="$demo_home" \
DEV_WORKPLACE="$workplace" \
GIT_CONFIG_GLOBAL=/dev/null \
GIT_CONFIG_SYSTEM=/dev/null \
  bash "$root/demo/entrypoint.sh" --prepare-only >/dev/null

[ -f "$repo/preserve-me.txt" ] || fail 'Repeated demo preparation overwrote an existing repository'
[ "$(git -C "$repo" rev-list --count HEAD)" = 1 ] || fail 'Repeated demo preparation created another commit'

printf 'PASS: Docker demo prepares an idempotent sample repository with changes\n'
