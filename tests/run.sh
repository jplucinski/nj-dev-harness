#!/usr/bin/env bash
set -euo pipefail

test_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(dirname "$test_dir")"
test_environment="$(mktemp -d "${TMPDIR:-/tmp}/dev-harness-test-runner.XXXXXX")"

cleanup() {
  case "$test_environment" in
    "${TMPDIR:-/tmp}"/dev-harness-test-runner.*) rm -rf -- "$test_environment" ;;
    *) printf 'Refusing unsafe test cleanup: %s\n' "$test_environment" >&2 ;;
  esac
}
trap cleanup EXIT

host_home="$test_environment/host-home"
host_xdg="$test_environment/host-xdg"
host_hooks="$test_environment/host-hooks"
host_templates="$test_environment/host-templates"
host_global_config="$test_environment/host-global.gitconfig"
host_system_config="$test_environment/host-system.gitconfig"
host_hook_marker="$test_environment/host-hook-ran"
isolated_home="$test_environment/isolated-home"
isolated_xdg="$test_environment/isolated-xdg"
isolated_templates="$test_environment/isolated-templates"
isolated_global_config="$test_environment/isolated-global.gitconfig"
mkdir -p "$host_home" "$host_xdg/git" "$host_hooks" "$host_templates/hooks"
mkdir -p "$isolated_home" "$isolated_xdg" "$isolated_templates"
: > "$host_global_config"
: > "$host_system_config"
: > "$isolated_global_config"
git config --file "$host_global_config" core.hooksPath "$host_hooks"
git config --file "$host_global_config" dev-harness.host-sentinel true
git config --file "$host_system_config" dev-harness.host-sentinel true
printf '%s\n' \
  '#!/usr/bin/env bash' \
  ': > "${DEV_HARNESS_TEST_HOST_HOOK_MARKER:?}"' > "$host_hooks/pre-commit"
cp "$host_hooks/pre-commit" "$host_templates/hooks/pre-commit"
chmod +x "$host_hooks/pre-commit" "$host_templates/hooks/pre-commit"
export HOME="$host_home"
export XDG_CONFIG_HOME="$host_xdg"
export GIT_CONFIG_GLOBAL="$host_global_config"
export GIT_CONFIG_SYSTEM="$host_system_config"
export GIT_TEMPLATE_DIR="$host_templates"
export DEV_HARNESS_TEST_HOST_HOOK_MARKER="$host_hook_marker"

for suite in \
  git_isolation_test.sh \
  review_fixes_test.sh \
  resume_test.sh \
  workflow_utils_test.sh \
  docker_demo_test.sh \
  install_test.sh \
  worktree_test.sh \
  obsidian_test.sh \
  release_test.sh \
  pages_test.sh; do
  HOME="$isolated_home" \
  XDG_CONFIG_HOME="$isolated_xdg" \
  GIT_CONFIG_GLOBAL="$isolated_global_config" \
  GIT_CONFIG_SYSTEM=/dev/null \
  GIT_TEMPLATE_DIR="$isolated_templates" \
    bash "$test_dir/$suite"
done

[ ! -e "$host_hook_marker" ] || {
  printf 'FAIL: a test suite executed hooksPath inherited from the host configuration\n' >&2
  exit 1
}

while IFS= read -r -d '' file; do
  bash -n "$file"
done < <(find "$root/scripts" "$root/shell" "$root/tests" "$root/tools" -type f \( -name '*.sh' -o -name '*.bash' \) -print0)
bash -n "$root/install.sh"
printf 'PASS: complete Dev Harness verification\n'
