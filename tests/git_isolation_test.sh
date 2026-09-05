#!/usr/bin/env bash
set -euo pipefail

test_root="$(mktemp -d "${TMPDIR:-/tmp}/dev-harness-git-isolation-test.XXXXXX")"

cleanup() {
  case "$test_root" in
    "${TMPDIR:-/tmp}"/dev-harness-git-isolation-test.*) rm -rf -- "$test_root" ;;
    *) printf 'Refusing unsafe test cleanup: %s\n' "$test_root" >&2 ;;
  esac
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

test_git_ignores_host_configuration_and_hooks() {
  local repo="$test_root/repository" marker
  marker="${DEV_HARNESS_TEST_HOST_HOOK_MARKER:?}"
  mkdir -p "$repo"
  git -C "$repo" init -q
  git -C "$repo" symbolic-ref HEAD refs/heads/main
  git -C "$repo" config user.email test@example.com
  git -C "$repo" config user.name 'Dev Harness Test'
  printf 'fixture\n' > "$repo/README.md"
  git -C "$repo" add README.md
  git -C "$repo" commit -q -m 'Isolation probe'

  [ ! -e "$marker" ] || fail 'Git executed hooksPath inherited from the host configuration'
  if git -C "$repo" config --get dev-harness.host-sentinel >/dev/null 2>&1; then
    fail 'Git read a sentinel value from the host configuration'
  fi
}

test_git_ignores_host_configuration_and_hooks
printf 'PASS: test Git operations ignore host configuration and hooks\n'
