#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$script_dir/lib.sh"

mode="${1:-}"
[ "$#" -eq 1 ] || die "Use 'location.sh <workplace|vault>'."

case "$mode" in
  workplace)
    variable=DEV_WORKPLACE
    configured_path="${DEV_WORKPLACE:-}"
    ;;
  vault)
    variable=DEV_OBSIDIAN_VAULT_PATH
    configured_path="${DEV_OBSIDIAN_VAULT_PATH:-}"
    ;;
  *) die "Unknown location: $mode" ;;
esac

[ -n "$configured_path" ] || die "$variable is not set."
configured_path="$(to_shell_path "$configured_path")"
[ -d "$configured_path" ] || die "$variable does not point to a directory: $configured_path"

(cd "$configured_path" && pwd -P)
