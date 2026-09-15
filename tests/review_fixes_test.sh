#!/usr/bin/env bash
set -euo pipefail

source_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/dev-harness-review-fixes-test.XXXXXX")"

cleanup() {
  case "$test_root" in
    *dev-harness-review-fixes-test.*) rm -rf -- "$test_root" || true ;;
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

assert_not_contains() {
  local haystack="$1" needle="$2"
  [[ "$haystack" != *"$needle"* ]] || fail "Expected output not to contain: $needle"
}

assert_equals() {
  local actual="$1" expected="$2"
  [ "$actual" = "$expected" ] || fail "Expected '$expected', got '$actual'"
}

create_repo() {
  local path="$1"
  mkdir -p "$path"
  git -C "$path" init -q
  git -C "$path" symbolic-ref HEAD refs/heads/main
  git -C "$path" config user.email test@example.com
  git -C "$path" config user.name 'Dev Harness Test'
  git -C "$path" config core.autocrlf false
  printf 'fixture\n' > "$path/README.md"
  git -C "$path" add README.md
  git -C "$path" commit -q -m 'Initial commit'
}

create_empty_repo() {
  local path="$1"
  mkdir -p "$path"
  git -C "$path" init -q
  git -C "$path" symbolic-ref HEAD refs/heads/main
  git -C "$path" config user.email test@example.com
  git -C "$path" config user.name 'Dev Harness Test'
  git -C "$path" config core.autocrlf false
}

create_command_wrapper() {
  local destination="$1" command_name="$2" resolved
  resolved="$(command -v "$command_name")"
  printf '#!/bin/sh\nexec "%s" "$@"\n' "$resolved" > "$destination/$command_name"
  chmod +x "$destination/$command_name"
}

stage_index_only_path() {
  local repo="$1" path="$2" content="$3" blob
  blob="$(printf '%s' "$content" | git -C "$repo" hash-object -w --stdin)"
  git -C "$repo" update-index --add --cacheinfo "100644,$blob,$path"
}

test_purge_config_refuses_a_parent_directory() {
  local fixture="$test_root/purge-parent" output status=0
  mkdir -p "$fixture/home"
  printf 'preserve me\n' > "$fixture/unrelated-user-file"

  output="$(
    HOME="$fixture/home" \
    DEV_HARNESS_HOME="$fixture/install" \
    DEV_HARNESS_CONFIG_DIR="$fixture/home/.." \
      bash "$source_dir/install.sh" uninstall --purge-config 2>&1
  )" || status=$?

  [ "$status" -ne 0 ] || fail 'Unsafe parent configuration directory was accepted'
  [ -f "$fixture/unrelated-user-file" ] || fail 'Purge removed an unrelated file'
  assert_contains "$output" 'Refusing unsafe configuration target'
}

test_purge_config_preserves_unknown_files() {
  local fixture="$test_root/purge-owned" config_dir output
  config_dir="$fixture/config/dev-harness"
  mkdir -p "$fixture/home" "$config_dir"
  printf 'settings\n' > "$config_dir/config.env"
  printf 'tasks\n' > "$config_dir/Taskfile.yml"
  printf 'palette\n' > "$config_dir/palette.tsv"
  printf 'preserve me\n' > "$config_dir/personal-notes.txt"

  output="$(
    HOME="$fixture/home" \
    DEV_HARNESS_HOME="$fixture/install" \
    DEV_HARNESS_CONFIG_DIR="$config_dir" \
      bash "$source_dir/install.sh" uninstall --purge-config 2>&1
  )"

  [ ! -e "$config_dir/config.env" ] || fail 'Purge kept config.env'
  [ ! -e "$config_dir/Taskfile.yml" ] || fail 'Purge kept the personal Taskfile'
  [ ! -e "$config_dir/palette.tsv" ] || fail 'Purge kept the personal palette'
  [ -f "$config_dir/personal-notes.txt" ] || fail 'Purge removed an unknown configuration file'
  assert_contains "$output" 'Unknown files remain'
}

test_context_includes_untracked_file_contents() {
  local repo="$test_root/untracked/repository" output
  create_repo "$repo"
  printf 'UNTRACKED_CONTENT_MARKER\n' > "$repo/NewService.java"

  output="$(
    cd "$repo"
    DEV_MAIN_BRANCH=main DEV_CONTEXT_MAX_LINES=4000 \
      bash "$source_dir/scripts/changes.sh" context
  )"

  assert_contains "$output" 'NewService.java'
  assert_contains "$output" 'UNTRACKED_CONTENT_MARKER'
}

test_ai_excludes_extensionless_private_keys() {
  local repo="$test_root/private-key/repository" output
  create_repo "$repo"
  printf 'FAKE_PRIVATE_KEY_MARKER\n' > "$repo/id_rsa"

  output="$(
    cd "$repo"
    DEV_AI_REVIEW_COMMAND='' bash "$source_dir/scripts/ai.sh" analyze-files id_rsa 2>/dev/null
  )"

  assert_contains "$output" '[sensitive path excluded]'
  assert_not_contains "$output" 'FAKE_PRIVATE_KEY_MARKER'
}

test_ai_excludes_java_keystores() {
  local repo="$test_root/java-keystore/repository" output
  create_repo "$repo"
  printf 'FAKE_KEYSTORE_MARKER\n' > "$repo/development.jks"

  output="$(
    cd "$repo"
    DEV_AI_REVIEW_COMMAND='' bash "$source_dir/scripts/ai.sh" analyze-files development.jks 2>/dev/null
  )"

  assert_contains "$output" '[sensitive path excluded]'
  assert_not_contains "$output" 'FAKE_KEYSTORE_MARKER'
}

test_context_excludes_tracked_sensitive_changes() {
  local repo="$test_root/tracked-secrets/repository" output
  create_repo "$repo"
  printf 'initial key\n' > "$repo/id_ed25519"
  printf 'initial keystore\n' > "$repo/development.jks"
  git -C "$repo" add id_ed25519 development.jks
  git -C "$repo" commit -q -m 'Add sensitive fixtures'
  printf 'TRACKED_PRIVATE_KEY_MARKER\n' >> "$repo/id_ed25519"
  printf 'TRACKED_KEYSTORE_MARKER\n' >> "$repo/development.jks"

  output="$(
    cd "$repo"
    DEV_MAIN_BRANCH=main DEV_CONTEXT_MAX_LINES=4000 \
      bash "$source_dir/scripts/changes.sh" context
  )"

  assert_not_contains "$output" 'TRACKED_PRIVATE_KEY_MARKER'
  assert_not_contains "$output" 'TRACKED_KEYSTORE_MARKER'
}

test_context_excludes_sensitive_directory_descendants() {
  local repo="$test_root/sensitive-descendants/repository" output
  create_repo "$repo"
  mkdir -p "$repo/credentials" "$repo/Secrets-prod" "$repo/src"
  printf 'initial credential\n' > "$repo/credentials/token.txt"
  git -C "$repo" add credentials/token.txt
  git -C "$repo" commit -q -m 'Add sensitive fixture'

  printf 'TRACKED_CREDENTIAL_MARKER\n' >> "$repo/credentials/token.txt"
  printf 'STAGED_SECRET_MARKER\n' > "$repo/Secrets-prod/config.txt"
  git -C "$repo" add Secrets-prod/config.txt
  printf 'SAFE_DESCENDANT_CONTEXT_MARKER\n' > "$repo/src/App.java"

  output="$(
    cd "$repo"
    DEV_MAIN_BRANCH=main DEV_CONTEXT_MAX_LINES=4000 \
      bash "$source_dir/scripts/changes.sh" context
  )"

  assert_not_contains "$output" 'credentials/token.txt'
  assert_not_contains "$output" 'TRACKED_CREDENTIAL_MARKER'
  assert_not_contains "$output" 'Secrets-prod/config.txt'
  assert_not_contains "$output" 'STAGED_SECRET_MARKER'
  assert_contains "$output" 'src/App.java'
  assert_contains "$output" 'SAFE_DESCENDANT_CONTEXT_MARKER'
}

test_context_handles_a_repository_without_commits() {
  local repo="$test_root/unborn/prototype" output status=0
  create_empty_repo "$repo"
  printf 'FIRST_FILE_MARKER\n' > "$repo/Prototype.java"

  output="$(
    cd "$repo"
    DEV_CONTEXT_MAX_LINES=4000 bash "$source_dir/scripts/changes.sh" context 2>&1
  )" || status=$?

  [ "$status" -eq 0 ] || fail "Unborn repository context exited with status $status: $output"
  assert_contains "$output" 'Base:       no commits yet'
  assert_contains "$output" 'Prototype.java'
  assert_contains "$output" 'FIRST_FILE_MARKER'
}

test_shared_sensitive_policy_matches_repository_context_filter() {
  local repo="$test_root/shared-sensitive-policy/repository" output path
  local sensitive_paths=(.env .ssh/custom_key id_ed25519 development.jks credentials-prod secrets-prod credentials/token.txt Secrets-prod/config.txt ID_ED25519 DEVELOPMENT.JKS .SSH/custom_key Secrets-prod)
  local filesystem_sensitive_paths=(.env .ssh/custom_key id_ed25519 development.jks credentials-prod secrets-prod)
  create_repo "$repo"
  mkdir -p "$repo/.ssh" "$repo/src"
  for path in "${filesystem_sensitive_paths[@]}"; do
    mkdir -p "$(dirname "$repo/$path")"
    printf 'SENSITIVE_MARKER_%s\n' "$path" > "$repo/$path"
  done
  printf 'SAFE_CONTEXT_MARKER\n' > "$repo/src/App.java"
  git -C "$repo" add -- "${filesystem_sensitive_paths[@]}" src/App.java
  stage_index_only_path "$repo" ID_ED25519 'UPPER_ED25519_MARKER'
  stage_index_only_path "$repo" DEVELOPMENT.JKS 'UPPER_JKS_MARKER'
  stage_index_only_path "$repo" .SSH/custom_key 'UPPER_SSH_MARKER'
  stage_index_only_path "$repo" Secrets-prod 'MIXED_SECRET_MARKER'

  output="$(
    cd "$repo"
    DEV_CONTEXT_MAX_LINES=4000 bash "$source_dir/scripts/changes.sh" context
  )"

  # shellcheck source=../scripts/lib.sh
  . "$source_dir/scripts/lib.sh"
  for path in "${sensitive_paths[@]}"; do
    is_sensitive_path "$path" || fail "Individual sensitive-path predicate missed: $path"
    assert_not_contains "$output" "$path"
  done
  assert_contains "$output" 'src/App.java'
  assert_contains "$output" 'SAFE_CONTEXT_MARKER'
}

test_cproj_keeps_editor_output_out_of_path_selection() {
  local fixture="$test_root/cproj-action" workplace fake_bin output
  workplace="$fixture/workplace"
  fake_bin="$fixture/bin"
  mkdir -p "$workplace/customer portal" "$fake_bin"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'first=""' \
    'while IFS= read -r line; do' \
    '  [ -n "$line" ] || continue' \
    '  first="$line"' \
    '  break' \
    'done' \
    'printf "ctrl-o\n%s\n" "$first"' > "$fake_bin/fzf"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'printf "EDITOR RESPONSE\n"' > "$fake_bin/review-editor"
  chmod +x "$fake_bin/fzf" "$fake_bin/review-editor"

  output="$(
    PATH="$fake_bin:$PATH" \
    DEV_WORKPLACE="$workplace" \
    DEV_EDITOR=review-editor \
    DEV_HARNESS_HOME="$source_dir" \
    DEV_HARNESS_CONFIG="$fixture/missing-config" \
    START_DIRECTORY="$fixture" \
      bash -c '
        . "$DEV_HARNESS_HOME/shell/dev-harness.bash"
        cd "$START_DIRECTORY"
        status=0
        cproj || status=$?
        printf "RESULT_STATUS=%s\nRESULT_DIRECTORY=%s\n" "$status" "$(pwd -P)"
      ' 2>&1
  )"

  assert_contains "$output" 'EDITOR RESPONSE'
  assert_contains "$output" 'RESULT_STATUS=0'
  assert_contains "$output" "RESULT_DIRECTORY=$(cd "$fixture" && pwd -P)"
  assert_not_contains "$output" 'No such file or directory'
}

test_cwt_keeps_editor_output_out_of_path_selection() {
  local fixture="$test_root/cwt-action" repo fake_bin output
  repo="$fixture/repository"
  fake_bin="$fixture/bin"
  create_repo "$repo"
  mkdir -p "$fake_bin"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'first=""' \
    'while IFS= read -r line; do' \
    '  [ -n "$line" ] || continue' \
    '  first="$line"' \
    '  break' \
    'done' \
    'printf "ctrl-o\n%s\n" "$first"' > "$fake_bin/fzf"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'printf "EDITOR RESPONSE\n"' > "$fake_bin/review-editor"
  chmod +x "$fake_bin/fzf" "$fake_bin/review-editor"

  output="$(
    PATH="$fake_bin:$PATH" \
    DEV_EDITOR=review-editor \
    DEV_HARNESS_HOME="$source_dir" \
    DEV_HARNESS_CONFIG="$fixture/missing-config" \
    START_DIRECTORY="$repo" \
      bash -c '
        . "$DEV_HARNESS_HOME/shell/dev-harness.bash"
        cd "$START_DIRECTORY"
        status=0
        cwt || status=$?
        printf "RESULT_STATUS=%s\nRESULT_DIRECTORY=%s\n" "$status" "$(pwd -P)"
      ' 2>&1
  )"

  assert_contains "$output" 'EDITOR RESPONSE'
  assert_contains "$output" 'RESULT_STATUS=0'
  assert_contains "$output" "RESULT_DIRECTORY=$(cd "$repo" && pwd -P)"
  assert_not_contains "$output" 'No such file or directory'
}

test_changed_picker_works_without_head() {
  local fixture="$test_root/changed-picker-unborn" repo fake_bin editor_record output status=0
  repo="$fixture/repository"
  fake_bin="$fixture/bin"
  editor_record="$fixture/editor-argument"
  create_empty_repo "$repo"
  printf 'staged\n' > "$repo/Staged.java"
  git -C "$repo" add Staged.java
  printf 'untracked\n' > "$repo/Untracked.java"
  mkdir -p "$fake_bin"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'while IFS= read -r item; do' \
    '  [ "$item" = Staged.java ] && printf "ctrl-o\n%s\n" "$item" && exit 0' \
    'done' > "$fake_bin/fzf"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'printf "%s" "$1" > "$EDITOR_RECORD"' > "$fake_bin/review-editor"
  chmod +x "$fake_bin/fzf" "$fake_bin/review-editor"

  output="$(
    cd "$repo"
    PATH="$fake_bin:$PATH" \
      DEV_EDITOR=review-editor \
      EDITOR_RECORD="$editor_record" \
      bash "$source_dir/scripts/open.sh" changed 2>&1
  )" || status=$?

  [ "$status" -eq 0 ] || fail "Unborn changed picker exited with status $status: $output"
  [ -f "$editor_record" ] || fail 'Changed picker did not invoke the editor'
  [[ "$(cat "$editor_record")" == */Staged.java ]] || fail "Editor opened unexpected path: $(cat "$editor_record")"
}

test_open_picker_searches_the_current_directory_outside_git() {
  local fixture="$test_root/open-current-directory" workspace fake_bin editor_record output status=0
  workspace="$fixture/workspace with spaces"
  fake_bin="$fixture/bin"
  editor_record="$fixture/editor-argument"
  mkdir -p "$workspace/nested folder" "$fake_bin"
  printf 'selected\n' > "$workspace/nested folder/selected note.md"
  printf 'ignored\n' > "$workspace/ignored.txt"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'while IFS= read -r item; do' \
    '  [ "$item" = "nested folder/selected note.md" ] && printf "\n%s\n" "$item" && exit 0' \
    'done' > "$fake_bin/fzf"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'printf "%s" "$1" > "$EDITOR_RECORD"' > "$fake_bin/review-editor"
  chmod +x "$fake_bin/fzf" "$fake_bin/review-editor"

  output="$(
    cd "$workspace"
    PATH="$fake_bin:$PATH" DEV_EDITOR=review-editor EDITOR_RECORD="$editor_record" \
      bash "$source_dir/scripts/open.sh" file 2>&1
  )" || status=$?

  [ "$status" -eq 0 ] || fail "File picker failed outside Git: $output"
  [ -f "$editor_record" ] || fail 'File picker did not invoke the editor'
  assert_equals "$(cat "$editor_record")" "$(cd "$workspace" && pwd -P)/nested folder/selected note.md"
}

test_palette_offers_the_file_picker_outside_git() {
  local fixture="$test_root/open-global-palette" workspace fake_bin output
  workspace="$fixture/plain directory"
  fake_bin="$fixture/bin"
  mkdir -p "$workspace" "$fake_bin"
  printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$fake_bin/task"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    "while IFS=\$'\\t' read -r task description keywords; do" \
    '  [ "$task" = open ] && printf "open\t%s\t%s\n" "$description" "$keywords" && exit 0' \
    'done' > "$fake_bin/fzf"
  chmod +x "$fake_bin/task" "$fake_bin/fzf"

  output="$(
    cd "$workspace"
    PATH="$fake_bin:$PATH" DEV_WORKPLACE='' bash "$source_dir/scripts/palette.sh" select
  )"

  assert_equals "$output" open
}

test_cwork_changes_to_the_configured_workplace() {
  local fixture="$test_root/cwork-shortcut" workplace output status=0
  workplace="$fixture/workplace with spaces"
  mkdir -p "$workplace"

  output="$(
    DEV_HARNESS_HOME="$source_dir" DEV_HARNESS_CONFIG="$fixture/missing-config" \
    DEV_WORKPLACE="$workplace" SOURCE_SHELL="$source_dir/shell/dev-harness.bash" \
      bash -c '. "$SOURCE_SHELL"; cwork; pwd -P' 2>&1
  )" || status=$?

  [ "$status" -eq 0 ] || fail "cwork failed: $output"
  assert_equals "$output" "$(cd "$workplace" && pwd -P)"
}

test_cvault_changes_to_the_configured_vault_path() {
  local fixture="$test_root/cvault-shortcut" vault output status=0
  vault="$fixture/Obsidian Vault"
  mkdir -p "$vault"

  output="$(
    DEV_HARNESS_HOME="$source_dir" DEV_HARNESS_CONFIG="$fixture/missing-config" \
    DEV_OBSIDIAN_VAULT_PATH="$vault" SOURCE_SHELL="$source_dir/shell/dev-harness.bash" \
      bash -c '. "$SOURCE_SHELL"; cvault; pwd -P' 2>&1
  )" || status=$?

  [ "$status" -eq 0 ] || fail "cvault failed: $output"
  assert_equals "$output" "$(cd "$vault" && pwd -P)"
}

test_context_rejects_a_zero_line_limit() {
  local repo="$test_root/zero-limit/repository" output status=0
  create_repo "$repo"
  printf 'changed\n' >> "$repo/README.md"

  output="$(
    cd "$repo"
    DEV_MAIN_BRANCH=main DEV_CONTEXT_MAX_LINES=0 \
      bash "$source_dir/scripts/changes.sh" context 2>&1
  )" || status=$?

  [ "$status" -ne 0 ] || fail 'A zero context line limit was accepted'
  assert_contains "$output" 'DEV_CONTEXT_MAX_LINES must be a positive integer'
}

test_file_analysis_rejects_a_zero_line_limit() {
  local repo="$test_root/zero-analysis-limit/repository" output status=0
  create_repo "$repo"

  output="$(
    cd "$repo"
    DEV_CONTEXT_MAX_LINES=0 DEV_AI_REVIEW_COMMAND='' \
      bash "$source_dir/scripts/ai.sh" analyze-files README.md 2>&1
  )" || status=$?

  [ "$status" -ne 0 ] || fail 'File analysis accepted a zero context line limit'
  assert_contains "$output" 'DEV_CONTEXT_MAX_LINES must be a positive integer'
}

test_noninteractive_review_refuses_inferred_consent() {
  local fixture="$test_root/noninteractive-review-refusal" repo output status=0
  repo="$fixture/repository"
  create_repo "$repo"
  printf 'changed\n' >> "$repo/README.md"

  output="$(
    cd "$repo"
    DEV_HARNESS_INPUT='' \
    DEV_AI_REVIEW_COMMAND="printf invoked > '$fixture/ai-invoked'" \
      bash "$source_dir/scripts/ai.sh" review 2>&1
  )" || status=$?

  [ "$status" -ne 0 ] || fail 'Non-interactive review inferred consent'
  [ ! -e "$fixture/ai-invoked" ] || fail 'AI command was invoked without explicit --all'
  assert_contains "$output" 'requires interactive fzf selection or explicit --all'
}

test_noninteractive_review_all_invokes_ai_with_safe_changes() {
  local fixture="$test_root/noninteractive-review-all" repo output status=0
  repo="$fixture/repository"
  create_repo "$repo"
  printf 'ordinary change\n' >> "$repo/README.md"
  printf 'ENV_MARKER\n' > "$repo/.env"
  mkdir -p "$repo/.ssh"
  printf 'SSH_MARKER\n' > "$repo/.ssh/custom_key"
  printf 'JKS_MARKER\n' > "$repo/development.jks"
  printf 'ED25519_MARKER\n' > "$repo/id_ed25519"

  output="$(
    cd "$repo"
    DEV_HARNESS_INPUT='--all' \
    DEV_AI_REVIEW_COMMAND="tee '$fixture/review-input' >/dev/null; touch '$fixture/ai-invoked'" \
      bash "$source_dir/scripts/ai.sh" review 2>&1
  )" || status=$?

  [ "$status" -eq 0 ] || fail "Explicit --all review failed: $output"
  [ -e "$fixture/ai-invoked" ] || fail 'AI command was not invoked for explicit --all'
  output="$(cat "$fixture/review-input")"
  assert_contains "$output" 'ordinary change'
  assert_not_contains "$output" 'ENV_MARKER'
  assert_not_contains "$output" 'SSH_MARKER'
  assert_not_contains "$output" 'JKS_MARKER'
  assert_not_contains "$output" 'ED25519_MARKER'
}

test_review_rejects_unknown_options() {
  local fixture="$test_root/review-unknown-option" repo output status=0
  repo="$fixture/repository"
  create_repo "$repo"
  printf 'changed\n' >> "$repo/README.md"

  output="$(
    cd "$repo"
    DEV_HARNESS_INPUT='--everything' \
    DEV_AI_REVIEW_COMMAND="touch '$fixture/ai-invoked'" \
      bash "$source_dir/scripts/ai.sh" review 2>&1
  )" || status=$?

  [ "$status" -ne 0 ] || fail 'Unknown review option was accepted'
  [ ! -e "$fixture/ai-invoked" ] || fail 'AI command was invoked for an unknown review option'
  assert_contains "$output" 'Unknown review option: --everything'
}

test_doctor_rejects_a_zero_context_line_limit() {
  local output status=0

  output="$(
    DEV_CONTEXT_MAX_LINES=0 \
    DEV_RESUME_LIMIT=10 \
    DEV_TODO_DEFAULT_PRIORITY=p2 \
    DEV_AI_COMMAND=git \
      bash "$source_dir/scripts/doctor.sh" --json
  )" || status=$?

  [ "$status" -ne 0 ] || fail 'Doctor accepted a zero context line limit'
  assert_contains "$output" '"name":"DEV_CONTEXT_MAX_LINES","status":"error"'
}

test_doctor_reports_the_github_cli_integration() {
  local output status=0

  output="$(
    DEV_CONTEXT_MAX_LINES=4000 \
    DEV_RESUME_LIMIT=10 \
    DEV_TODO_DEFAULT_PRIORITY=p2 \
    DEV_AI_COMMAND=git \
      bash "$source_dir/scripts/doctor.sh" --json
  )" || status=$?

  assert_contains "$output" '"name":"gh","status":"'
}

test_install_requires_fzf_before_writing() {
  local fixture="$test_root/install-requires-fzf" fake_bin home output status=0
  fake_bin="$fixture/bin"
  home="$fixture/home"
  mkdir -p "$fake_bin" "$home"
  create_command_wrapper "$fake_bin" bash
  create_command_wrapper "$fake_bin" task
  create_command_wrapper "$fake_bin" git
  create_command_wrapper "$fake_bin" dirname
  create_command_wrapper "$fake_bin" tr

  output="$(
    HOME="$home" \
    PATH="$fake_bin" \
      bash "$source_dir/install.sh" install --dry-run 2>&1
  )" || status=$?

  [ "$status" -ne 0 ] || fail 'Installer accepted a PATH without fzf'
  [ ! -e "$home/.dev-harness" ] || fail 'Installer wrote ~/.dev-harness before rejecting fzf'
  [ ! -e "$home/.config/dev-harness" ] || fail 'Installer wrote ~/.config/dev-harness before rejecting fzf'
  assert_contains "$output" 'Required tool not found in PATH: fzf'
}

test_doctor_reports_fzf_as_required_json_error() {
  local fixture="$test_root/doctor-requires-fzf" fake_bin output
  fake_bin="$fixture/bin"
  mkdir -p "$fake_bin"
  create_command_wrapper "$fake_bin" bash
  create_command_wrapper "$fake_bin" task
  create_command_wrapper "$fake_bin" git
  create_command_wrapper "$fake_bin" dirname
  create_command_wrapper "$fake_bin" sed

  output="$(
    PATH="$fake_bin" \
      bash "$source_dir/scripts/doctor.sh" --json 2>&1
  )" || true

  assert_contains "$output" '"name":"fzf","status":"error"'
}

test_install_requires_rg_before_writing() {
  local fixture="$test_root/install-requires-rg" fake_bin home output status=0
  fake_bin="$fixture/bin"
  home="$fixture/home"
  mkdir -p "$fake_bin" "$home"
  create_command_wrapper "$fake_bin" bash
  create_command_wrapper "$fake_bin" task
  create_command_wrapper "$fake_bin" git
  create_command_wrapper "$fake_bin" dirname
  create_command_wrapper "$fake_bin" tr
  printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$fake_bin/fzf"
  chmod +x "$fake_bin/fzf"

  output="$(
    HOME="$home" \
    PATH="$fake_bin" \
      bash "$source_dir/install.sh" install --dry-run 2>&1
  )" || status=$?

  [ "$status" -ne 0 ] || fail 'Installer accepted a PATH without rg'
  [ ! -e "$home/.dev-harness" ] || fail 'Installer wrote ~/.dev-harness before rejecting rg'
  [ ! -e "$home/.config/dev-harness" ] || fail 'Installer wrote ~/.config/dev-harness before rejecting rg'
  assert_contains "$output" 'Required tool not found in PATH: rg'
}

test_doctor_reports_rg_as_required_json_error() {
  local fixture="$test_root/doctor-requires-rg" fake_bin output
  fake_bin="$fixture/bin"
  mkdir -p "$fake_bin"
  create_command_wrapper "$fake_bin" bash
  create_command_wrapper "$fake_bin" task
  create_command_wrapper "$fake_bin" git
  create_command_wrapper "$fake_bin" dirname
  create_command_wrapper "$fake_bin" sed
  printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$fake_bin/fzf"
  chmod +x "$fake_bin/fzf"

  output="$(
    PATH="$fake_bin" \
      bash "$source_dir/scripts/doctor.sh" --json 2>&1
  )" || true

  assert_contains "$output" '"name":"rg","status":"error"'
}

test_install_requires_grepai_before_writing() {
  local fixture="$test_root/install-requires-grepai" fake_bin home output status=0
  fake_bin="$fixture/bin"
  home="$fixture/home"
  mkdir -p "$fake_bin" "$home"
  create_command_wrapper "$fake_bin" bash
  create_command_wrapper "$fake_bin" task
  create_command_wrapper "$fake_bin" git
  create_command_wrapper "$fake_bin" dirname
  create_command_wrapper "$fake_bin" tr
  printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$fake_bin/fzf"
  printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$fake_bin/rg"
  chmod +x "$fake_bin/fzf" "$fake_bin/rg"

  output="$(
    HOME="$home" \
    PATH="$fake_bin" \
      bash "$source_dir/install.sh" install --dry-run 2>&1
  )" || status=$?

  [ "$status" -ne 0 ] || fail 'Installer accepted a PATH without grepai'
  [ ! -e "$home/.dev-harness" ] || fail 'Installer wrote ~/.dev-harness before rejecting grepai'
  [ ! -e "$home/.config/dev-harness" ] || fail 'Installer wrote ~/.config/dev-harness before rejecting grepai'
  assert_contains "$output" 'Required tool not found in PATH: grepai'
}

test_doctor_reports_grepai_as_required_json_error() {
  local fixture="$test_root/doctor-requires-grepai" fake_bin output
  fake_bin="$fixture/bin"
  mkdir -p "$fake_bin"
  create_command_wrapper "$fake_bin" bash
  create_command_wrapper "$fake_bin" task
  create_command_wrapper "$fake_bin" git
  create_command_wrapper "$fake_bin" dirname
  create_command_wrapper "$fake_bin" sed
  printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$fake_bin/fzf"
  printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$fake_bin/rg"
  chmod +x "$fake_bin/fzf" "$fake_bin/rg"

  output="$(
    PATH="$fake_bin" \
      bash "$source_dir/scripts/doctor.sh" --json 2>&1
  )" || true

  assert_contains "$output" '"name":"grepai","status":"error"'
}

install_doctor_command_stubs() {
  local fake_bin="$1"
  mkdir -p "$fake_bin"
  create_command_wrapper "$fake_bin" bash
  create_command_wrapper "$fake_bin" task
  create_command_wrapper "$fake_bin" git
  create_command_wrapper "$fake_bin" dirname
  create_command_wrapper "$fake_bin" sed
  printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$fake_bin/fzf"
  printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$fake_bin/rg"
  printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$fake_bin/grepai"
  chmod +x "$fake_bin/fzf" "$fake_bin/rg" "$fake_bin/grepai"
}

test_doctor_errors_when_workplace_has_no_grepai_config() {
  local fixture="$test_root/doctor-grepai-config" fake_bin workplace output
  fake_bin="$fixture/bin"
  workplace="$fixture/workplace"
  mkdir -p "$workplace/payments"
  install_doctor_command_stubs "$fake_bin"

  output="$(
    PATH="$fake_bin" DEV_WORKPLACE="$workplace" \
      bash "$source_dir/scripts/doctor.sh" --json 2>&1
  )" || true

  assert_contains "$output" '"name":"grepai-config","status":"error"'
  assert_contains "$output" 'run gtask index'
}

test_doctor_warns_when_workplace_index_is_missing() {
  local fixture="$test_root/doctor-grepai-index" fake_bin workplace output
  fake_bin="$fixture/bin"
  workplace="$fixture/workplace"
  mkdir -p "$workplace/.grepai"
  : > "$workplace/.grepai/config.yaml"
  install_doctor_command_stubs "$fake_bin"

  output="$(
    PATH="$fake_bin" DEV_WORKPLACE="$workplace" \
      bash "$source_dir/scripts/doctor.sh" --json 2>&1
  )" || true
  assert_contains "$output" '"name":"grepai-index","status":"warn"'

  output="$(
    PATH="$fake_bin" DEV_WORKPLACE="$workplace" \
      bash "$source_dir/scripts/doctor.sh" --json --all 2>&1
  )" || true
  assert_contains "$output" '"name":"grepai-index","status":"error"'
}

test_context_truncates_large_untracked_files_without_error() {
  local repo="$test_root/untracked-truncation/repository" output
  create_repo "$repo"
  printf 'keep-me\ndrop-me\nextra\n' > "$repo/LargeFile.java"

  output="$(
    cd "$repo"
    DEV_MAIN_BRANCH=main DEV_CONTEXT_MAX_LINES=5 \
      bash "$source_dir/scripts/changes.sh" context
  )"

  assert_contains "$output" 'Bounded diff (maximum 5 lines)'
}

test_purge_config_refuses_a_parent_directory
printf 'PASS: config purge refuses a parent directory\n'
test_purge_config_preserves_unknown_files
printf 'PASS: config purge preserves unknown files\n'
test_context_includes_untracked_file_contents
printf 'PASS: AI context includes untracked file contents\n'
test_ai_excludes_extensionless_private_keys
printf 'PASS: AI excludes extensionless private keys\n'
test_ai_excludes_java_keystores
printf 'PASS: AI excludes Java keystores\n'
test_context_excludes_tracked_sensitive_changes
printf 'PASS: context excludes tracked sensitive changes\n'
test_context_excludes_sensitive_directory_descendants
printf 'PASS: context excludes sensitive directory descendants\n'
test_context_handles_a_repository_without_commits
printf 'PASS: context handles repositories without commits\n'
test_shared_sensitive_policy_matches_repository_context_filter
printf 'PASS: shared sensitive policy matches repository context filter\n'
test_cproj_keeps_editor_output_out_of_path_selection
printf 'PASS: cproj keeps editor output out of path selection\n'
test_cwt_keeps_editor_output_out_of_path_selection
printf 'PASS: cwt keeps editor output out of path selection\n'
test_changed_picker_works_without_head
printf 'PASS: changed picker works without HEAD\n'
test_open_picker_searches_the_current_directory_outside_git
printf 'PASS: file picker searches the current directory outside Git\n'
test_palette_offers_the_file_picker_outside_git
printf 'PASS: global palette offers the file picker outside Git\n'
test_cwork_changes_to_the_configured_workplace
printf 'PASS: cwork changes to the configured workplace\n'
test_cvault_changes_to_the_configured_vault_path
printf 'PASS: cvault changes to the configured vault path\n'
test_context_rejects_a_zero_line_limit
printf 'PASS: context rejects a zero line limit\n'
test_file_analysis_rejects_a_zero_line_limit
printf 'PASS: file analysis rejects a zero line limit\n'
test_noninteractive_review_refuses_inferred_consent
printf 'PASS: non-interactive review refuses inferred consent\n'
test_noninteractive_review_all_invokes_ai_with_safe_changes
printf 'PASS: non-interactive review --all invokes AI with safe changes\n'
test_review_rejects_unknown_options
printf 'PASS: review rejects unknown options\n'
test_doctor_rejects_a_zero_context_line_limit
printf 'PASS: doctor rejects a zero context line limit\n'
test_doctor_reports_the_github_cli_integration
printf 'PASS: doctor reports the GitHub CLI integration\n'
test_install_requires_fzf_before_writing
printf 'PASS: installer requires fzf before writing\n'
test_doctor_reports_fzf_as_required_json_error
printf 'PASS: doctor reports fzf as a required JSON error\n'
test_install_requires_rg_before_writing
printf 'PASS: installer requires rg before writing\n'
test_doctor_reports_rg_as_required_json_error
printf 'PASS: doctor reports rg as a required JSON error\n'
test_install_requires_grepai_before_writing
printf 'PASS: installer requires grepai before writing\n'
test_doctor_reports_grepai_as_required_json_error
printf 'PASS: doctor reports grepai as a required JSON error\n'
test_doctor_errors_when_workplace_has_no_grepai_config
printf 'PASS: doctor errors when workplace has no grepai config\n'
test_doctor_warns_when_workplace_index_is_missing
printf 'PASS: doctor warns when workplace index is missing\n'
test_context_truncates_large_untracked_files_without_error
printf 'PASS: context safely truncates large untracked files\n'
