#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$script_dir/lib.sh"

need git
branch="${DEV_HARNESS_INPUT:-${1:-}}"
if [ -z "$branch" ]; then
  read -r -p 'Branch: ' branch
fi
[ -n "$branch" ] || exit 0

root="$(repo_root)"
repo="$(basename "$root")"
base_ref="$(default_branch)"
[ -n "$base_ref" ] || die "Could not determine the default branch. Set DEV_MAIN_BRANCH."
base_sha="$(git -C "$root" rev-parse "$base_ref^{commit}")"
slug="$(slugify "$branch")"
[ -n "$slug" ] || die "Branch name does not produce a safe worktree name."

if [ -n "${DEV_WORKTREE_ROOT:-}" ]; then
  worktree_root="$(to_shell_path "$DEV_WORKTREE_ROOT")"
else
  worktree_root="$(dirname "$root")/.worktrees"
fi

stamp="$(date '+%Y%m%d-%H%M%S')"
name="$repo-$slug-$stamp"
path="$worktree_root/$name"
suffix=2
while [ -e "$path" ]; do
  path="$worktree_root/$name-$suffix"
  suffix=$((suffix + 1))
done

mkdir -p "$worktree_root"
if git -C "$root" show-ref --verify --quiet "refs/heads/$branch"; then
  git -C "$root" worktree add "$path" "$branch"
else
  git -C "$root" worktree add -b "$branch" "$path" "$base_ref"
fi

metadata_dir="$worktree_root/.dev-harness"
mkdir -p "$metadata_dir"
metadata="$metadata_dir/$(basename "$path").meta"
{
  printf 'repo=%s\n' "$repo"
  printf 'base_ref=%s\n' "$base_ref"
  printf 'base_sha=%s\n' "$base_sha"
  printf 'branch=%s\n' "$branch"
  printf 'created=%s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')"
  printf 'path=%s\n' "$path"
} >"$metadata"

printf '%s\n' "$path"
