#!/usr/bin/env bash
set -euo pipefail

# macOS binaries used by Dev Harness. Does not install the harness itself.

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

command -v brew >/dev/null 2>&1 || die "Homebrew is not installed. See https://brew.sh"

brew install \
  git \
  go-task \
  fzf \
  ripgrep \
  bat \
  lazygit \
  lazydocker \
  k9s \
  gh 

brew install --cask \
  ghostty \
  obsidian \
  visual-studio-code \
  docker
