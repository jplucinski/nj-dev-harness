#!/usr/bin/env bash
set -euo pipefail

source_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/dev-harness-install-test.XXXXXX")"

cleanup() {
  case "$test_root" in
    "${TMPDIR:-/tmp}"/dev-harness-install-test.*) rm -rf -- "$test_root" ;;
    *) printf 'Refusing unsafe test cleanup: %s\n' "$test_root" >&2 ;;
  esac
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_file() {
  [ -f "$1" ] || fail "Expected file: $1"
}

assert_missing() {
  [ ! -e "$1" ] || fail "Expected path to be absent: $1"
}

assert_contains() {
  local haystack="$1" needle="$2"
  [[ "$haystack" == *"$needle"* ]] || fail "Expected output to contain: $needle"
}

assert_equals() {
  local actual="$1" expected="$2"
  [ "$actual" = "$expected" ] || fail "Expected '$expected', got '$actual'"
}

assert_files_equal() {
  cmp -s "$1" "$2" || fail "Expected files to match exactly: $1 and $2"
}

create_fake_tools() {
  local bin="$1" real_task
  mkdir -p "$bin"
  real_task="$(command -v task || true)"
  if [ -n "$real_task" ]; then
    printf '#!/usr/bin/env bash\nexec "%s" "$@"\n' "$real_task" > "$bin/task"
  else
    printf '#!/usr/bin/env bash\nexit 0\n' > "$bin/task"
  fi
  printf '#!/usr/bin/env bash\nexit 0\n' > "$bin/fzf"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$bin/grepai"
  chmod +x "$bin/task" "$bin/fzf" "$bin/grepai"
}

test_install_update_and_purge_preserve_unknown_config() {
  local fixture="$test_root/lifecycle" home install_dir config_dir fake_bin source_version output personal_content
  fixture="$test_root/lifecycle"
  home="$fixture/home"
  install_dir="$fixture/managed installation"
  config_dir="$home/.config/dev-harness"
  fake_bin="$fixture/bin"
  source_version="$(tr -d '\r\n' < "$source_dir/VERSION")"
  mkdir -p "$home"
  create_fake_tools "$fake_bin"

  output="$(
    HOME="$home" \
    DEV_HARNESS_HOME="$install_dir" \
    DEV_HARNESS_CONFIG_DIR="$config_dir" \
    PATH="$fake_bin:$PATH" \
      bash "$source_dir/install.sh" install --configure-shell 2>&1
  )"

  assert_contains "$output" "Dev Harness install: version $source_version"
  assert_file "$install_dir/.dev-harness-manifest"
  assert_file "$install_dir/scripts/doctor.sh"
  assert_file "$install_dir/scripts/dirty.sh"
  assert_file "$install_dir/scripts/focus.sh"
  assert_file "$install_dir/scripts/workflow.sh"
  assert_file "$config_dir/config.env"
  assert_file "$home/Taskfile.yml"
  assert_file "$home/.bashrc"
  assert_contains "$(tr -d '\r' < "$home/.bashrc")" '# >>> Dev Harness (managed) >>>'
  assert_equals "$(tr -d '\r\n' < "$install_dir/VERSION")" "$source_version"

  printf 'stale managed doctor script\n' > "$install_dir/scripts/doctor.sh"

  output="$(
    HOME="$home" \
    DEV_HARNESS_HOME="$install_dir" \
    DEV_HARNESS_CONFIG_DIR="$config_dir" \
    PATH="$fake_bin:$PATH" \
      bash "$source_dir/install.sh" update --configure-shell 2>&1
  )"
  assert_contains "$output" "Dev Harness update: version $source_version"
  assert_file "$install_dir/.dev-harness-manifest"
  assert_files_equal "$source_dir/scripts/doctor.sh" "$install_dir/scripts/doctor.sh"

  personal_content='Keep this personal file exactly as written.
Second line remains personal.'
  printf '%s\n' "$personal_content" > "$config_dir/personal-notes.txt"
  output="$(
    HOME="$home" \
    DEV_HARNESS_HOME="$install_dir" \
    DEV_HARNESS_CONFIG_DIR="$config_dir" \
    PATH="$fake_bin:$PATH" \
      bash "$source_dir/install.sh" uninstall --purge-config 2>&1
  )"

  assert_contains "$output" 'Unknown files remain and were preserved'
  assert_missing "$install_dir"
  assert_missing "$config_dir/config.env"
  assert_missing "$home/Taskfile.yml"
  assert_file "$config_dir/personal-notes.txt"
  assert_equals "$(cat "$config_dir/personal-notes.txt")" "$personal_content"
  if grep -Fq '# >>> Dev Harness (managed) >>>' "$home/.bashrc"; then
    fail 'Uninstall left the managed shell block behind'
  fi
}

test_install_update_and_purge_preserve_unknown_config
printf 'PASS: installer lifecycle preserves unknown personal configuration\n'
