#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(dirname "$script_dir")"
version_file="$root/VERSION"

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

[ -f "$version_file" ] || die "VERSION file is missing: $version_file"
version="$(tr -d '\r\n' < "$version_file")"
[ -n "$version" ] || die 'VERSION is empty'
case "$version" in
  *[!0-9A-Za-z.-]*) die 'VERSION contains unsupported characters; use only 0-9, A-Z, a-z, dot, and dash' ;;
esac

for tool in tar gzip; do
  command -v "$tool" >/dev/null 2>&1 || die "Required packaging tool not found in PATH: $tool"
done

package_name="dev-harness-$version"
cd "$root"
dist_dir="dist"
package_dir="$dist_dir/$package_name"
tar_name="$package_name.tar.gz"
zip_name="$package_name.zip"
tar_archive="$dist_dir/$tar_name"
zip_archive="$dist_dir/$zip_name"
checksum_file="$dist_dir/SHA256SUMS"

case "$package_dir" in
  "$dist_dir"/dev-harness-*) ;;
  *) die "Refusing unsafe package directory: $package_dir" ;;
esac

source_files=(
  VERSION
  README.md
  CHANGELOG.md
  LICENSE
  install.sh
  install.ps1
  Taskfile.global.yml
  config/dev-harness.env.example
  demo/Dockerfile
  demo/entrypoint.sh
  shell/dev-harness.bash
  scripts/ai.sh
  scripts/changes.sh
  scripts/dirty.sh
  scripts/docker.sh
  scripts/doctor.sh
  scripts/focus.sh
  scripts/help.sh
  scripts/lib.sh
  scripts/location.sh
  scripts/obsidian.sh
  scripts/open.sh
  scripts/palette.sh
  scripts/preview.sh
  scripts/project.sh
  scripts/resume.sh
  scripts/workflow.sh
  scripts/worktree.sh
  scripts/worktrees.sh
)

for relative in "${source_files[@]}"; do
  [ -f "$root/$relative" ] || die "Release input is missing: $relative"
done

ensure_safe_dist_dir() {
  local root_physical dist_physical expected_dist
  root_physical="$(pwd -P)"
  expected_dist="$root_physical/dist"

  [ ! -L "$dist_dir" ] || die "Refusing unsafe dist directory: $dist_dir is a symbolic link"
  if [ -e "$dist_dir" ] && [ ! -d "$dist_dir" ]; then
    die "Refusing unsafe dist directory: $dist_dir is not a directory"
  fi
  [ -d "$dist_dir" ] || mkdir -- "$dist_dir"

  dist_physical="$(cd "$dist_dir" && pwd -P)"
  [ "$dist_physical" = "$expected_dist" ] \
    || die "Refusing unsafe dist directory: resolved to $dist_physical, expected $expected_dist"
}

ensure_safe_dist_dir
rm -rf -- "$package_dir"
rm -f -- "$tar_archive" "$zip_archive" "$checksum_file"
mkdir -p "$package_dir"

for relative in "${source_files[@]}"; do
  destination="$package_dir/$relative"
  mkdir -p "$(dirname "$destination")"
  cp "$root/$relative" "$destination"
done

find "$package_dir" -type d -exec chmod 755 {} +
find "$package_dir" -type f -exec chmod 644 {} +
chmod 755 "$package_dir/install.sh" "$package_dir/demo/entrypoint.sh" "$package_dir"/scripts/*.sh

# A fixed archive timestamp makes repeated packaging independent of checkout time.
find "$package_dir" -exec touch -t 200001010000.00 {} +

create_tar_archive() {
  (
    cd "$dist_dir"
    if tar --version 2>/dev/null | grep -Fq 'GNU tar'; then
      tar \
        --sort=name \
        --owner=0 \
        --group=0 \
        --numeric-owner \
        --mtime='2000-01-01 00:00:00 UTC' \
        -cf - \
        "$package_name"
    elif tar --version 2>/dev/null | grep -Fq 'bsdtar'; then
      tar \
        --uid 0 \
        --gid 0 \
        --uname root \
        --gname root \
        -cf - \
        "$package_name"
    else
      tar -cf - "$package_name"
    fi
  ) | gzip -n > "$tar_archive"
}

create_zip_archive() {
  if command -v zip >/dev/null 2>&1; then
    (
      cd "$dist_dir"
      zip -X -q -r "$zip_name" "$package_name"
    )
    return
  fi

  command -v powershell.exe >/dev/null 2>&1 \
    || die 'ZIP creation requires zip or powershell.exe with Compress-Archive'

  if command -v cygpath >/dev/null 2>&1; then
    package_windows="$(cygpath -w "$package_dir")"
    zip_windows="$(cygpath -w "$zip_archive")"
  else
    package_windows="$package_dir"
    zip_windows="$zip_archive"
  fi

  # PowerShell expands its $env variables; Bash must pass the command literally.
  # shellcheck disable=SC2016
  DEV_HARNESS_PACKAGE_SOURCE="$package_windows" \
  DEV_HARNESS_PACKAGE_ZIP="$zip_windows" \
    powershell.exe -NoProfile -Command \
      '$ErrorActionPreference = "Stop"; Compress-Archive -LiteralPath $env:DEV_HARNESS_PACKAGE_SOURCE -DestinationPath $env:DEV_HARNESS_PACKAGE_ZIP -CompressionLevel Optimal -Force'
}

write_checksums() {
  (
    cd "$dist_dir"
    case "$(uname -s)" in
      Darwin)
        command -v shasum >/dev/null 2>&1 || die 'Required checksum tool not found in PATH: shasum'
        shasum -a 256 "$tar_name" "$zip_name" > SHA256SUMS
        ;;
      *)
        command -v sha256sum >/dev/null 2>&1 || die 'Required checksum tool not found in PATH: sha256sum'
        sha256sum "$tar_name" "$zip_name" > SHA256SUMS
        ;;
    esac
  )
}

create_tar_archive
create_zip_archive
write_checksums

printf 'Created release assets in %s:\n' "$dist_dir"
printf '  %s\n' "$tar_name" "$zip_name" "$(basename "$checksum_file")"
