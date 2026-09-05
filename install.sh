#!/usr/bin/env bash
set -euo pipefail

product_name="Dev Harness"
loader_marker="# Managed by Dev Harness installer. Put personal tasks in ~/.config/dev-harness/Taskfile.yml."
shell_block_start="# >>> Dev Harness (managed) >>>"
shell_block_end="# <<< Dev Harness (managed) <<<"

source_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
install_dir="${DEV_HARNESS_HOME:-$HOME/.dev-harness}"
config_dir="${DEV_HARNESS_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/dev-harness}"
global_taskfile="$HOME/Taskfile.yml"
bashrc="$HOME/.bashrc"
manifest_name=".dev-harness-manifest"

mode="install"
mode_was_set=false
dry_run=false
configure_shell=false
purge_config=false
global_connected=false

usage() {
  cat <<'EOF'
Dev Harness installer

Usage:
  ./install.sh [install|update] [--dry-run] [--configure-shell]
  ./install.sh uninstall [--dry-run] [--purge-config]
  ./install.sh --version

Commands:
  install       Install or refresh managed files (default)
  update        Same safe, idempotent operation as install
  uninstall     Remove only files managed by Dev Harness

Options:
  --dry-run           Show intended changes without writing them
  --configure-shell   Add the Dev Harness source block to ~/.bashrc
  --purge-config      With uninstall, remove known personal configuration files
  -h, --help          Show this help

Required tools:
  bash, task, git, fzf
EOF
}

say() {
  printf '%s\n' "$*"
}

warn() {
  printf 'WARN: %s\n' "$*" >&2
}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

set_mode() {
  if [ "$mode_was_set" = true ]; then
    die "Choose only one command: install, update, or uninstall."
  fi
  mode="$1"
  mode_was_set=true
}

for arg in "$@"; do
  case "$arg" in
    install|update|uninstall) set_mode "$arg" ;;
    --dry-run) dry_run=true ;;
    --configure-shell) configure_shell=true ;;
    --purge-config) purge_config=true ;;
    -h|--help) usage; exit 0 ;;
    --version)
      [ -f "$source_dir/VERSION" ] || die "VERSION file is missing."
      printf '%s %s\n' "$product_name" "$(tr -d '\r\n' < "$source_dir/VERSION")"
      exit 0
      ;;
    *) die "Unknown argument: $arg. Run ./install.sh --help." ;;
  esac
done

[ -n "${HOME:-}" ] || die "HOME is not set."
[ "$purge_config" = false ] || [ "$mode" = uninstall ] || die "--purge-config is only valid with uninstall."
[ "$configure_shell" = false ] || [ "$mode" != uninstall ] || die "--configure-shell is not valid with uninstall."

validate_destructive_target() {
  local target="$1" label="$2"
  case "$target" in
    ""|/|.|"$HOME"|[A-Za-z]:|[A-Za-z]:/|[A-Za-z]:\\)
      die "Refusing unsafe $label target: $target"
      ;;
  esac
}

validate_destructive_target "$install_dir" "installation"
validate_destructive_target "$config_dir" "configuration"
[ "$install_dir" != "$source_dir" ] || [ "$mode" != uninstall ] || [ -f "$source_dir/$manifest_name" ] || \
  die "Refusing to uninstall an unmanifested source directory."

version_file="$source_dir/VERSION"
if [ -f "$version_file" ]; then
  version="$(tr -d '\r\n' < "$version_file")"
else
  version="unknown"
fi

normalize_task_path() {
  local path="$1"
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -m "$path"
  else
    printf '%s\n' "$path"
  fi
}

yaml_single_quote() {
  local value="$1"
  value="${value//\'/\'\'}"
  printf "'%s'" "$value"
}

managed_taskfile_path="$(normalize_task_path "$install_dir/Taskfile.yml")"

loader_content() {
  printf '%s\n' "$loader_marker"
  printf "version: '3'\n\n"
  printf 'includes:\n'
  printf '  dev-harness:\n'
  printf '    taskfile: %s\n' "$(yaml_single_quote "$managed_taskfile_path")"
  printf '    flatten: true\n'
}

print_include_help() {
  local existing="$1"
  warn "Global Taskfile already exists and was left unchanged: $existing"
  printf '\nAdd this entry under its existing includes: section (or create that section):\n\n'
  printf '  dev-harness:\n'
  printf '    taskfile: %s\n' "$(yaml_single_quote "$managed_taskfile_path")"
  printf '    flatten: true\n\n'
}

global_candidates() {
  printf '%s\n' \
    "$HOME/Taskfile.yml" \
    "$HOME/taskfile.yml" \
    "$HOME/Taskfile.yaml" \
    "$HOME/taskfile.yaml"
}

find_existing_global_taskfile() {
  local candidate
  while IFS= read -r candidate; do
    if [ -e "$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done < <(global_candidates)
  return 1
}

is_managed_loader() {
  local file="$1"
  [ -f "$file" ] && IFS= read -r first_line < "$file" && [ "$first_line" = "$loader_marker" ]
}

is_expected_loader() {
  local file="$1" actual expected
  [ -f "$file" ] || return 1
  actual="$(tr -d '\r' < "$file")"
  expected="$(loader_content)"
  [ "$actual" = "$expected" ]
}

legacy_global_owned=false
if [ -f "$global_taskfile" ]; then
  if [ -f "$install_dir/Taskfile.yml" ] && cmp -s "$global_taskfile" "$install_dir/Taskfile.yml"; then
    legacy_global_owned=true
  elif [ -f "$source_dir/Taskfile.global.yml" ] && cmp -s "$global_taskfile" "$source_dir/Taskfile.global.yml"; then
    legacy_global_owned=true
  fi
fi

validate_source() {
  local required
  for required in \
    VERSION \
    Taskfile.global.yml \
    install.sh \
    install.ps1 \
    config/dev-harness.env.example \
    shell/dev-harness.bash \
    scripts/doctor.sh; do
    [ -f "$source_dir/$required" ] || die "Installation source is incomplete: missing $required"
  done
}

validate_required_tools() {
  local tool missing=false
  for tool in bash task git fzf; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      warn "Required tool not found in PATH: $tool"
      missing=true
    fi
  done
  [ "$missing" = false ] || die "Install the required tools and run the installer again. No files were changed."
}

report_optional_tools() {
  local tool missing=()
  for tool in rg code gh docker atuin; do
    command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
  done
  if [ "${#missing[@]}" -gt 0 ]; then
    warn "Optional integrations not found: ${missing[*]}"
  fi
}

relative_path_is_safe() {
  case "$1" in
    ""|/*|../*|*/../*|*/..|..|[A-Za-z]:*) return 1 ;;
    *) return 0 ;;
  esac
}

ensure_directory() {
  local directory="$1" parent
  [ -d "$directory" ] && return 0
  parent="$(dirname "$directory")"
  [ "$parent" != "$directory" ] || die "Cannot create directory: $directory"
  ensure_directory "$parent"
  mkdir -- "$directory"
}

stage_managed_files() {
  local stage="$1"
  mkdir -p "$stage/scripts" "$stage/shell" "$stage/config"
  cp "$source_dir"/scripts/*.sh "$stage/scripts/"
  cp "$source_dir/shell/dev-harness.bash" "$stage/shell/"
  cp "$source_dir/config/dev-harness.env.example" "$stage/config/"
  cp "$source_dir/Taskfile.global.yml" "$stage/Taskfile.yml"
  cp "$source_dir/install.sh" "$stage/install.sh"
  cp "$source_dir/install.ps1" "$stage/install.ps1"
  cp "$source_dir/VERSION" "$stage/VERSION"
  (
    cd "$stage"
    find VERSION Taskfile.yml install.sh install.ps1 config scripts shell -type f -print | LC_ALL=C sort
  ) > "$stage/$manifest_name"
}

deploy_stage() {
  local stage="$1" relative parent old_manifest="$install_dir/$manifest_name"

  ensure_directory "$install_dir"

  while IFS= read -r relative; do
    relative_path_is_safe "$relative" || die "Unsafe path in new installation manifest: $relative"
    parent="$(dirname "$install_dir/$relative")"
    ensure_directory "$parent"
    cp "$stage/$relative" "$install_dir/$relative"
  done < "$stage/$manifest_name"

  if [ -f "$old_manifest" ]; then
    while IFS= read -r relative; do
      relative_path_is_safe "$relative" || {
        warn "Ignored unsafe path in previous installation manifest: $relative"
        continue
      }
      if ! grep -Fqx "$relative" "$stage/$manifest_name"; then
        rm -f -- "$install_dir/$relative"
      fi
    done < "$old_manifest"
  fi

  cp "$stage/$manifest_name" "$old_manifest"
  chmod +x "$install_dir/install.sh" "$install_dir"/scripts/*.sh
}

install_config() {
  if [ -f "$config_dir/config.env" ]; then
    say "Kept personal configuration: $config_dir/config.env"
    return
  fi
  if [ "$dry_run" = true ]; then
    say "Would create personal configuration: $config_dir/config.env"
    return
  fi
  ensure_directory "$config_dir"
  cp "$source_dir/config/dev-harness.env.example" "$config_dir/config.env"
  say "Created personal configuration: $config_dir/config.env"
}

install_global_loader() {
  local existing=""
  existing="$(find_existing_global_taskfile || true)"

  if [ -z "$existing" ]; then
    if [ "$dry_run" = true ]; then
      say "Would create global Taskfile loader: $global_taskfile"
    else
      loader_content > "$global_taskfile"
      say "Created global Taskfile loader: $global_taskfile"
    fi
    global_connected=true
    return
  fi

  if [ "$existing" = "$global_taskfile" ] && { is_managed_loader "$existing" || [ "$legacy_global_owned" = true ]; }; then
    if is_expected_loader "$existing"; then
      say "Global Taskfile loader is up to date: $existing"
    elif [ "$dry_run" = true ]; then
      say "Would refresh global Taskfile loader: $existing"
    else
      loader_content > "$existing"
      say "Migrated global Taskfile to the stable loader: $existing"
    fi
    global_connected=true
    return
  fi

  print_include_help "$existing"
}

shell_source_line() {
  local quoted
  printf -v quoted '%q' "$install_dir/shell/dev-harness.bash"
  printf 'source %s' "$quoted"
}

configure_bashrc() {
  local source_line
  source_line="$(shell_source_line)"

  if [ -f "$bashrc" ] && grep -Fqx "$shell_block_start" "$bashrc" && grep -Fqx "$shell_block_end" "$bashrc"; then
    say "Shell integration is already present: $bashrc"
    return
  fi

  if [ -f "$bashrc" ] && { grep -Fq "$install_dir/shell/dev-harness.bash" "$bashrc" || grep -Fqx "$source_line" "$bashrc"; }; then
    say "Shell integration is already present: $bashrc"
    return
  fi

  if [ -f "$bashrc" ] && { grep -Fqx "$shell_block_start" "$bashrc" || grep -Fqx "$shell_block_end" "$bashrc"; }; then
    warn "An incomplete Dev Harness block exists in $bashrc; it was left unchanged."
    return
  fi

  if [ "$dry_run" = true ]; then
    say "Would add shell integration to: $bashrc"
    return
  fi

  {
    [ ! -s "$bashrc" ] || printf '\n'
    printf '%s\n' "$shell_block_start"
    printf '%s\n' "$source_line"
    printf '%s\n' "$shell_block_end"
  } >> "$bashrc"
  say "Added shell integration to: $bashrc"
}

show_shell_instruction() {
  printf '\nTo enable aliases and directory-changing shortcuts, add this line to ~/.bashrc:\n\n'
  shell_source_line
  printf '\n'
}

remove_shell_block() {
  local start_line end_line middle_line expected_line temp
  [ -f "$bashrc" ] || return 0
  start_line="$(grep -nFx "$shell_block_start" "$bashrc" | cut -d: -f1 | head -n 1 || true)"
  end_line="$(grep -nFx "$shell_block_end" "$bashrc" | cut -d: -f1 | head -n 1 || true)"
  [ -n "$start_line" ] || return 0

  if [ -z "$end_line" ] || [ "$end_line" -le "$start_line" ]; then
    warn "Managed shell block is incomplete; $bashrc was left unchanged."
    return 0
  fi

  middle_line="$(sed -n "$((start_line + 1))p" "$bashrc")"
  expected_line="$(shell_source_line)"
  if [ "$end_line" -ne "$((start_line + 2))" ] || [ "$middle_line" != "$expected_line" ]; then
    warn "Managed shell block was edited, so $bashrc was left unchanged."
    return 0
  fi

  if [ "$dry_run" = true ]; then
    say "Would remove managed shell integration from: $bashrc"
    return 0
  fi

  temp="$(mktemp "${TMPDIR:-/tmp}/dev-harness-bashrc.XXXXXX")"
  awk -v start="$start_line" -v end="$end_line" 'NR < start || NR > end' "$bashrc" > "$temp"
  cp "$temp" "$bashrc"
  rm -f -- "$temp"
  say "Removed managed shell integration from: $bashrc"
}

remove_global_loader() {
  if is_expected_loader "$global_taskfile"; then
    if [ "$dry_run" = true ]; then
      say "Would remove managed global Taskfile loader: $global_taskfile"
    else
      rm -f -- "$global_taskfile"
      say "Removed managed global Taskfile loader: $global_taskfile"
    fi
  elif [ "$legacy_global_owned" = true ]; then
    if [ "$dry_run" = true ]; then
      say "Would remove legacy managed global Taskfile: $global_taskfile"
    else
      rm -f -- "$global_taskfile"
      say "Removed legacy managed global Taskfile: $global_taskfile"
    fi
  elif is_managed_loader "$global_taskfile"; then
    warn "Managed loader was edited, so it was left unchanged: $global_taskfile"
  fi
}

remove_managed_installation() {
  local manifest="$install_dir/$manifest_name" relative
  if [ ! -f "$manifest" ]; then
    [ ! -e "$install_dir" ] || warn "No installation manifest found; $install_dir was left unchanged."
    return 0
  fi

  if [ "$dry_run" = true ]; then
    say "Would remove managed installation files from: $install_dir"
    return 0
  fi

  while IFS= read -r relative; do
    relative_path_is_safe "$relative" || {
      warn "Ignored unsafe path in installation manifest: $relative"
      continue
    }
    rm -f -- "$install_dir/$relative"
  done < "$manifest"
  rm -f -- "$manifest"
  rmdir "$install_dir/scripts" "$install_dir/shell" "$install_dir/config" "$install_dir" 2>/dev/null || true
  say "Removed managed installation files from: $install_dir"
  [ ! -d "$install_dir" ] || warn "Unmanaged files remain in $install_dir and were preserved."
}

remove_personal_config() {
  local resolved_config
  [ "$purge_config" = true ] || {
    say "Kept personal configuration: $config_dir"
    return 0
  }
  if [ "$dry_run" = true ]; then
    say "Would remove known personal Dev Harness configuration files from: $config_dir"
    return 0
  fi
  [ -d "$config_dir" ] || return 0
  resolved_config="$(cd "$config_dir" && pwd -P)"
  validate_destructive_target "$resolved_config" "configuration"
  [ "$(basename "$resolved_config")" = dev-harness ] \
    || die "Refusing unsafe configuration target: $resolved_config (expected a directory named dev-harness)"
  rm -f -- \
    "$resolved_config/config.env" \
    "$resolved_config/Taskfile.yml" \
    "$resolved_config/palette.tsv"
  rmdir "$resolved_config" 2>/dev/null || true
  say "Removed personal Dev Harness configuration: $resolved_config"
  [ ! -d "$resolved_config" ] || warn "Unknown files remain and were preserved: $resolved_config"
}

run_doctor() {
  say ""
  say "Installation check:"
  (
    if [ -f "$config_dir/config.env" ]; then
      set +u
      # shellcheck disable=SC1090
      . "$config_dir/config.env"
      set -u
    fi
    bash "$install_dir/scripts/doctor.sh"
  )
}

if [ "$mode" = uninstall ]; then
  say "$product_name uninstall"
  remove_global_loader
  remove_shell_block
  remove_managed_installation
  remove_personal_config
  say "Notes and the Obsidian vault were not touched."
  exit 0
fi

validate_source
validate_required_tools
report_optional_tools

say "$product_name $mode: version $version"
say "Managed location: $install_dir"

if [ "$dry_run" = true ]; then
  say "Would install or refresh managed files."
else
  stage_dir="$(mktemp -d "${TMPDIR:-/tmp}/dev-harness-install.XXXXXX")"
  trap 'rm -rf -- "$stage_dir"' EXIT
  stage_managed_files "$stage_dir"
  deploy_stage "$stage_dir"
  say "Installed managed files: $install_dir"
fi

install_config
install_global_loader

if [ "$configure_shell" = true ]; then
  configure_bashrc
else
  show_shell_instruction
fi

if [ "$dry_run" = false ]; then
  run_doctor
  if [ "$global_connected" = true ]; then
    printf '\nReady. Restart the terminal, then run: gtask\n'
  else
    printf '\nManaged files are installed. Add the include shown above, restart the terminal, then run: gtask\n'
  fi
else
  say "Dry run complete. No user files were changed."
fi
