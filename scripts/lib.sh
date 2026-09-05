#!/usr/bin/env bash

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

warn() {
  printf 'Warning: %s\n' "$*" >&2
}

need() {
  command -v "$1" >/dev/null 2>&1 || die "Missing command: $1"
}

clip_copy() {
  if command -v pbcopy >/dev/null 2>&1; then
    pbcopy
  elif command -v clip.exe >/dev/null 2>&1; then
    clip.exe
  elif command -v wl-copy >/dev/null 2>&1; then
    wl-copy
  elif command -v xclip >/dev/null 2>&1; then
    xclip -selection clipboard
  else
    die "No supported clipboard command found (pbcopy, clip.exe, wl-copy, or xclip)."
  fi
}

is_sensitive_path() {
  local path
  path="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  case "$path" in
    .env|*/.env|.env.*|*/.env.*|*.pem|*.key|*.p12|*.pfx|*.ppk|*.jks|*.keystore|.npmrc|*/.npmrc|.pypirc|*/.pypirc|.ssh/*|*/.ssh/*|id_rsa|*/id_rsa|id_dsa|*/id_dsa|id_ecdsa|*/id_ecdsa|id_ed25519|*/id_ed25519|*credentials*|*secrets*) return 0 ;;
    *) return 1 ;;
  esac
}

sensitive_git_pathspecs() {
  printf '%s\n' \
    ':(exclude,icase,glob)**/.env' \
    ':(exclude,icase,glob)**/.env.*' \
    ':(exclude,icase,glob)**/*.pem' \
    ':(exclude,icase,glob)**/*.key' \
    ':(exclude,icase,glob)**/*.p12' \
    ':(exclude,icase,glob)**/*.pfx' \
    ':(exclude,icase,glob)**/*.ppk' \
    ':(exclude,icase,glob)**/*.jks' \
    ':(exclude,icase,glob)**/*.keystore' \
    ':(exclude,icase,glob)**/.npmrc' \
    ':(exclude,icase,glob)**/.pypirc' \
    ':(exclude,icase,glob)**/.ssh/**' \
    ':(exclude,icase,glob)**/id_rsa' \
    ':(exclude,icase,glob)**/id_dsa' \
    ':(exclude,icase,glob)**/id_ecdsa' \
    ':(exclude,icase,glob)**/id_ed25519' \
    ':(exclude,icase,glob)**/credentials*' \
    ':(exclude,icase,glob)**/credentials*/**' \
    ':(exclude,icase,glob)**/secrets*' \
    ':(exclude,icase,glob)**/secrets*/**'
}

to_shell_path() {
  local path="$1"
  case "$path" in
    [A-Za-z]:[\\/]*)
      if command -v cygpath >/dev/null 2>&1; then
        cygpath -u "$path"
      else
        printf '%s\n' "$path"
      fi
      ;;
    *) printf '%s\n' "$path" ;;
  esac
}

workplace_root() {
  local workplace="${DEV_WORKPLACE:-}"
  [ -n "$workplace" ] || die "Set DEV_WORKPLACE in ~/.config/dev-harness/config.env."
  workplace="$(to_shell_path "$workplace")"
  [ -d "$workplace" ] || die "DEV_WORKPLACE does not exist: $workplace"
  (cd "$workplace" && pwd -P)
}

workplace_project_dirs() {
  local workplace path found=false
  workplace="$(workplace_root)"
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    (cd "$path" && pwd -P)
    found=true
  done < <(find "$workplace" -mindepth 1 -maxdepth 1 -type d -print | LC_ALL=C sort)
  [ "$found" = true ] || die "No project directories found in $workplace"
}

repo_root() {
  local root
  root="$(git rev-parse --show-toplevel 2>/dev/null)" || die "This command must run inside a Git repository."
  to_shell_path "$root"
}

repo_name() {
  basename "$(repo_root)"
}

project_slug() {
  local name root common common_abs
  if git rev-parse --show-toplevel >/dev/null 2>&1; then
    root="$(to_shell_path "$(git rev-parse --show-toplevel)")"
    common="$(git rev-parse --git-common-dir)"
    case "$common" in
      /*|[A-Za-z]:/*) common_abs="$(to_shell_path "$common")" ;;
      *) common_abs="$root/$common" ;;
    esac
    if [ "$(basename "$common_abs")" = .git ]; then
      name="$(basename "$(dirname "$common_abs")")"
    else
      name="$(basename "$root")"
    fi
  else
    name="$(basename "$PWD")"
  fi
  slugify "$name"
}

slugify() {
  printf '%s' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's#[/\\[:space:]]+#-#g; s#[^[:alnum:]_.-]+#-#g; s#-+#-#g; s#(^-|-$)##g'
}

default_branch() {
  local candidate
  if [ -n "${DEV_MAIN_BRANCH:-}" ]; then
    printf '%s\n' "$DEV_MAIN_BRANCH"
    return
  fi

  candidate="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)"
  if [ -n "$candidate" ]; then
    printf '%s\n' "$candidate"
    return
  fi

  for candidate in main origin/main master origin/master; do
    if git rev-parse --verify --quiet "$candidate^{commit}" >/dev/null; then
      printf '%s\n' "$candidate"
      return
    fi
  done

  git rev-list --max-parents=0 HEAD 2>/dev/null | tail -n 1
}

git_common_dir_abs() {
  local root common
  root="$(repo_root)"
  common="$(git rev-parse --git-common-dir)"
  case "$common" in
    /*|[A-Za-z]:/*) to_shell_path "$common" ;;
    *) printf '%s/%s\n' "$root" "$common" ;;
  esac
}

obsidian_executable() {
  if command -v obsidian.com >/dev/null 2>&1; then
    printf '%s\n' obsidian.com
  elif command -v obsidian >/dev/null 2>&1; then
    printf '%s\n' obsidian
  else
    return 1
  fi
}
