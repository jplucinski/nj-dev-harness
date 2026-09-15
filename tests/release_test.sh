#!/usr/bin/env bash
set -euo pipefail

source_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/dev-harness-release-test.XXXXXX")"

cleanup() {
  case "$test_root" in
    *dev-harness-release-test.*) rm -rf -- "$test_root" || true ;;
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

copy_source_fixture() {
  local destination="$1"
  mkdir -p "$destination"
  cp -R "$source_dir/." "$destination/"
}

create_directory_symlink() {
  local target="$1" link="$2" target_windows link_windows

  if ln -s "$target" "$link" 2>/dev/null && [ -L "$link" ]; then
    return
  fi
  rm -rf -- "$link"

  if command -v powershell.exe >/dev/null 2>&1 && command -v cygpath >/dev/null 2>&1; then
    target_windows="$(cygpath -w "$target")"
    link_windows="$(cygpath -w "$link")"
    # PowerShell expands its $env variables; Bash must pass the command literally.
    # shellcheck disable=SC2016
    DEV_HARNESS_LINK_TARGET="$target_windows" \
    DEV_HARNESS_LINK_PATH="$link_windows" \
      powershell.exe -NoProfile -Command \
        '$ErrorActionPreference = "Stop"; New-Item -ItemType Junction -Path $env:DEV_HARNESS_LINK_PATH -Target $env:DEV_HARNESS_LINK_TARGET | Out-Null'
    [ -L "$link" ] && return
  fi

  fail "Could not create a directory symlink for the release safety test: $link"
}

expected_archive_files() {
  local package_name="$1" relative
  for relative in \
    VERSION \
    README.md \
    CHANGELOG.md \
    LICENSE \
    install.sh \
    install.ps1 \
    Taskfile.global.yml \
    config/dev-harness.env.example \
    demo/Dockerfile \
    demo/entrypoint.sh \
    shell/dev-harness.bash \
    scripts/ai.sh \
    scripts/changes.sh \
    scripts/dirty.sh \
    scripts/docker.sh \
    scripts/doctor.sh \
    scripts/help.sh \
    scripts/lib.sh \
    scripts/location.sh \
    scripts/focus.sh \
    scripts/obsidian.sh \
    scripts/open.sh \
    scripts/palette.sh \
    scripts/preview.sh \
    scripts/project.sh \
    scripts/resume.sh \
    scripts/search.sh \
    scripts/workflow.sh \
    scripts/worktree.sh \
    scripts/worktrees.sh; do
    printf '%s/%s\n' "$package_name" "$relative"
  done | LC_ALL=C sort
}

archive_file_entries() {
  local archive="$1"
  case "$archive" in
    *.tar.gz) tar -tzf "$archive" ;;
    *.zip) unzip -Z1 "$archive" ;;
    *) fail "Unsupported archive in test: $archive" ;;
  esac | tr -d '\r' | tr '\\' '/' | sed '/\/$/d' | LC_ALL=C sort
}

assert_archive_manifest() {
  local archive="$1" package_name="$2" actual expected
  actual="$(archive_file_entries "$archive")"
  expected="$(expected_archive_files "$package_name")"
  [ "$actual" = "$expected" ] || {
    printf 'Expected archive files:\n%s\n' "$expected" >&2
    printf 'Actual archive files in %s:\n%s\n' "$archive" "$actual" >&2
    fail "Archive manifest differs from the explicit release allowlist: $archive"
  }
}

verify_checksums() {
  local dist_dir="$1"
  (
    cd "$dist_dir"
    case "$(uname -s)" in
      Darwin) shasum -a 256 -c SHA256SUMS ;;
      *) sha256sum -c SHA256SUMS ;;
    esac
  ) >/dev/null || fail 'SHA256SUMS does not verify both release archives'
}

file_sha256() {
  local file="$1"
  case "$(uname -s)" in
    Darwin) shasum -a 256 "$file" | awk '{ print $1 }' ;;
    *) sha256sum "$file" | awk '{ print $1 }' ;;
  esac
}

assert_checksum_manifest() {
  local checksum_file="$1" tar_name="$2" zip_name="$3"
  local line checksum remainder line_count=0 seen_tar=false seen_zip=false

  while IFS= read -r line || [ -n "$line" ]; do
    line_count=$((line_count + 1))
    checksum="${line%% *}"
    remainder="${line#"$checksum"}"
    [ "${#checksum}" -eq 64 ] || fail "Invalid SHA-256 digest length in: $line"
    case "$checksum" in
      *[!0-9A-Fa-f]*) fail "Invalid SHA-256 digest in: $line" ;;
    esac
    case "$remainder" in
      "  $tar_name"|" *$tar_name")
        [ "$seen_tar" = false ] || fail "Duplicate checksum entry: $tar_name"
        seen_tar=true
        ;;
      "  $zip_name"|" *$zip_name")
        [ "$seen_zip" = false ] || fail "Duplicate checksum entry: $zip_name"
        seen_zip=true
        ;;
      *) fail "Unexpected checksum path or format: $line" ;;
    esac
  done < "$checksum_file"

  [ "$line_count" -eq 2 ] || fail "Expected exactly two checksum entries, got $line_count"
  [ "$seen_tar" = true ] || fail "Missing checksum entry: $tar_name"
  [ "$seen_zip" = true ] || fail "Missing checksum entry: $zip_name"
}

test_release_archives_use_the_exact_public_allowlist() {
  local fixture="$test_root/package" source_copy version package_name dist_dir tar_path zip_path
  local first_tar_hash first_zip_hash first_manifest_hash
  source_copy="$fixture/source"
  copy_source_fixture "$source_copy"

  mkdir -p \
    "$source_copy/.git" \
    "$source_copy/tests" \
    "$source_copy/docs/superpowers" \
    "$source_copy/dist" \
    "$source_copy/config"
  printf 'private repository metadata\n' > "$source_copy/.git/private"
  printf 'maintainer fixture\n' > "$source_copy/tests/private-fixture"
  printf 'maintainer plan\n' > "$source_copy/docs/superpowers/private-plan.md"
  printf 'stale release output\n' > "$source_copy/dist/stale-asset"
  printf 'DEV_AI_REVIEW_COMMAND=private-command\n' > "$source_copy/config/config.env"

  (
    cd "$source_copy"
    bash tools/package-release.sh
  )

  version="$(tr -d '\r\n' < "$source_copy/VERSION")"
  package_name="dev-harness-$version"
  dist_dir="$source_copy/dist"
  tar_path="$dist_dir/$package_name.tar.gz"
  zip_path="$dist_dir/$package_name.zip"

  [ -f "$tar_path" ] || fail "Missing release archive: $tar_path"
  [ -f "$zip_path" ] || fail "Missing release archive: $zip_path"
  [ -f "$dist_dir/SHA256SUMS" ] || fail 'Missing release checksums'

  assert_archive_manifest "$tar_path" "$package_name"
  assert_archive_manifest "$zip_path" "$package_name"
  assert_checksum_manifest "$dist_dir/SHA256SUMS" "$(basename "$tar_path")" "$(basename "$zip_path")"
  verify_checksums "$dist_dir"

  first_tar_hash="$(file_sha256 "$tar_path")"
  first_zip_hash="$(file_sha256 "$zip_path")"
  first_manifest_hash="$(file_sha256 "$dist_dir/SHA256SUMS")"

  (
    cd "$source_copy"
    bash tools/package-release.sh
  )

  assert_archive_manifest "$tar_path" "$package_name"
  assert_archive_manifest "$zip_path" "$package_name"
  assert_checksum_manifest "$dist_dir/SHA256SUMS" "$(basename "$tar_path")" "$(basename "$zip_path")"
  verify_checksums "$dist_dir"
  assert_equals "$(file_sha256 "$tar_path")" "$first_tar_hash"
  assert_equals "$(file_sha256 "$zip_path")" "$first_zip_hash"
  assert_equals "$(file_sha256 "$dist_dir/SHA256SUMS")" "$first_manifest_hash"
}

test_release_checkout_does_not_persist_credentials() {
  local workflow="$source_dir/.github/workflows/release.yml" checkout_block
  checkout_block="$(awk '
    /uses: actions\/checkout@d23441a48e516b6c34aea4fa41551a30e30af803/ { capture = 1 }
    capture && /^[[:space:]]*- name:/ { exit }
    capture { print }
  ' "$workflow")"
  assert_contains "$checkout_block" 'persist-credentials: false'
}

test_release_rejects_an_empty_version() {
  local source_copy="$test_root/empty-version/source" output status=0
  copy_source_fixture "$source_copy"
  rm -rf -- "$source_copy/dist"
  : > "$source_copy/VERSION"

  output="$(cd "$source_copy" && bash tools/package-release.sh 2>&1)" || status=$?

  [ "$status" -ne 0 ] || fail 'Packaging accepted an empty VERSION'
  assert_contains "$output" 'VERSION is empty'
  [ ! -e "$source_copy/dist" ] || fail 'Packaging wrote output for an empty VERSION'
}

test_release_rejects_unsafe_version_characters() {
  local source_copy="$test_root/unsafe-version/source" output status=0
  copy_source_fixture "$source_copy"
  rm -rf -- "$source_copy/dist"
  printf '0.3.0/unsafe\n' > "$source_copy/VERSION"

  output="$(cd "$source_copy" && bash tools/package-release.sh 2>&1)" || status=$?

  [ "$status" -ne 0 ] || fail 'Packaging accepted unsafe VERSION characters'
  assert_contains "$output" 'VERSION contains unsupported characters'
  [ ! -e "$source_copy/dist" ] || fail 'Packaging wrote output for an unsafe VERSION'
}

test_release_rejects_symlinked_dist_without_touching_target() {
  local fixture="$test_root/symlinked-dist" source_copy external version marker output status=0
  source_copy="$fixture/source"
  external="$fixture/external-dist"
  copy_source_fixture "$source_copy"
  rm -rf -- "$source_copy/dist"

  version="$(tr -d '\r\n' < "$source_copy/VERSION")"
  marker="$external/dev-harness-$version/preserve-marker"
  mkdir -p "$(dirname "$marker")"
  printf 'must remain outside package output\n' > "$marker"
  create_directory_symlink "$external" "$source_copy/dist"

  output="$(cd "$source_copy" && bash tools/package-release.sh 2>&1)" || status=$?

  [ -f "$marker" ] || fail 'Packaging followed symlinked dist and removed the external marker'
  [ "$status" -ne 0 ] || fail 'Packaging accepted a symlinked dist directory'
  assert_contains "$output" 'Refusing unsafe dist directory'
}

test_release_archives_use_the_exact_public_allowlist
test_release_rejects_an_empty_version
test_release_rejects_unsafe_version_characters
test_release_rejects_symlinked_dist_without_touching_target
test_release_checkout_does_not_persist_credentials
printf 'PASS: release packaging is allowlisted, versioned, and checksummed\n'
