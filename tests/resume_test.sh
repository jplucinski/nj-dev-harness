#!/usr/bin/env bash
set -euo pipefail

source_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/dev-harness-resume-test.XXXXXX")"
original_dir="$PWD"
trap 'cd "$original_dir" || true; rm -rf -- "$test_root" || true' EXIT
mkdir -p "$test_root/run"
cd "$test_root/run"

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

assert_repo_under_test_root() {
  local actual="$1" repo="$2" relative
  actual="${actual%$'\r'}"
  relative="${repo#"$test_root"/}"
  [[ "$actual" == *"$relative" ]] || fail "Expected path to contain '$relative', got '$actual'"
}

install_clipboard_stub() {
  local dir="$1"
  printf '%s\n' '#!/usr/bin/env bash' 'cat > "$CLIP_LOG"' > "$dir/pbcopy"
  cp "$dir/pbcopy" "$dir/clip.exe"
  chmod +x "$dir/pbcopy" "$dir/clip.exe"
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

stage_index_only_path() {
  local repo="$1" path="$2" content="$3" blob
  blob="$(printf '%s' "$content" | git -C "$repo" hash-object -w --stdin)"
  git -C "$repo" update-index --add --cacheinfo "100644,$blob,$path"
}

canonical_git_path() {
  local raw
  raw="$(git -C "$1" rev-parse --show-toplevel 2>/dev/null | tr -d '\r')"
  [ -n "$raw" ] || {
    raw="$(cd "$1" && pwd -P)"
  }
  case "$raw" in
    [A-Za-z]:[\\/]*)
      if command -v cygpath >/dev/null 2>&1; then
        cygpath -u "$raw"
      else
        printf '%s\n' "$raw"
      fi
      ;;
    *) printf '%s\n' "$raw" ;;
  esac
}

test_recent_atuin_directories_are_collapsed_to_one_repository() {
  local workplace="$test_root/work place" repo="$test_root/work place/payments api"
  local fake_bin="$test_root/fake-bin" output count expected_path
  create_repo "$repo"
  mkdir -p "$repo/src/deep" "$fake_bin"
  printf '%s\n' '#!/usr/bin/env bash' 'printf "%b" "$ATUIN_TEST_OUTPUT"' > "$fake_bin/atuin"
  chmod +x "$fake_bin/atuin"
  expected_path="$(canonical_git_path "$repo")"

  output="$(
    PATH="$fake_bin:$PATH" \
    DEV_WORKPLACE="$workplace" \
    ATUIN_TEST_OUTPUT=$'2 minutes ago\t'"$repo/src/deep"$'\t0\n5 minutes ago\t'"$repo"$'\t0\n' \
      bash "$source_dir/scripts/resume.sh" candidates
  )"

  assert_contains "$output" $'payments api\tmain\t2 minutes ago\t'
  count="$(printf '%s\n' "$output" | awk -F '\t' -v path="$expected_path" '$1 == "payments api" && $4 == path { n++ } END { print n+0 }')"
  assert_equals "$count" 1
}

test_repeated_atuin_directory_is_resolved_only_once() {
  local repo="$test_root/atuin performance/catalog" fake_bin="$test_root/atuin-performance-bin"
  local git_log="$test_root/git-resolution.log" real_git calls
  create_repo "$repo"
  mkdir -p "$fake_bin" "$repo/src/a" "$repo/src/b"
  real_git="$(command -v git)"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'for index in $(seq 1 50); do if [ $((index % 2)) -eq 0 ]; then suffix=a; else suffix=b; fi; printf "recent\t%s/src/%s\t0\n" "$ATUIN_DIRECTORY" "$suffix"; done' > "$fake_bin/atuin"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'case "$*" in *"rev-parse --show-toplevel"*) printf "call\n" >> "$GIT_RESOLUTION_LOG" ;; esac' \
    'exec "$REAL_GIT" "$@"' > "$fake_bin/git"
  chmod +x "$fake_bin/atuin" "$fake_bin/git"

  (
    cd "$test_root"
    PATH="$fake_bin:$PATH" REAL_GIT="$real_git" GIT_RESOLUTION_LOG="$git_log" ATUIN_DIRECTORY="$repo" \
      bash "$source_dir/scripts/resume.sh" candidates >/dev/null
  )
  calls="$(wc -l < "$git_log" | tr -d ' ')"

  [ "$calls" -le 3 ] || fail "Repeated Atuin directory triggered $calls Git root resolutions"
}

test_workplace_discovery_includes_linked_worktrees() {
  local workplace="$test_root/worktree-place" repo="$test_root/worktree-place/inventory"
  local worktree="$test_root/linked trees/inventory feature" fake_bin="$test_root/no-atuin-bin"
  local output
  create_repo "$repo"
  mkdir -p "$(dirname "$worktree")" "$fake_bin"
  printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$fake_bin/atuin"
  chmod +x "$fake_bin/atuin"
  git -C "$repo" worktree add -q -b feature/resume "$worktree" main

  output="$(
    PATH="$fake_bin:$PATH" DEV_WORKPLACE="$workplace" \
      bash "$source_dir/scripts/resume.sh" candidates
  )"

  assert_contains "$output" $'inventory\tmain\tproject\t'
  assert_contains "$output" $'inventory\tfeature/resume\tworktree\t'
  assert_contains "$output" "$(canonical_git_path "$worktree")"
}

test_preview_summarizes_branch_and_working_tree_state() {
  local repo="$test_root/preview place/catalog" output
  create_repo "$repo"
  git -C "$repo" switch -q -c feature/preview
  printf 'feature\n' > "$repo/feature.txt"
  git -C "$repo" add feature.txt
  git -C "$repo" commit -q -m 'Add preview feature'
  printf 'changed\n' >> "$repo/README.md"
  printf 'staged\n' > "$repo/staged.txt"
  git -C "$repo" add staged.txt
  printf 'untracked\n' > "$repo/untracked.txt"

  output="$(DEV_MAIN_BRANCH=main bash "$source_dir/scripts/resume.sh" preview "$repo")"

  assert_contains "$output" 'Project:    catalog'
  assert_contains "$output" 'Branch:     feature/preview'
  assert_contains "$output" 'Base:       main'
  assert_contains "$output" 'Changes:    1 staged · 1 unstaged · 1 untracked'
  assert_contains "$output" 'Commits:    1 since base'
  assert_contains "$output" 'Add preview feature'
}

test_preview_shows_the_highest_priority_project_todo_when_available() {
  local repo="$test_root/todo preview place/payments" fake_bin="$test_root/todo-preview-bin" output
  create_repo "$repo"
  mkdir -p "$fake_bin"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'case "$*" in' \
    '  *"file path=TODO/TODO.base"*) exit 0 ;;' \
    '  *"base:query"*)' \
    '    printf "Path\tTitle\tProject\tPriority\tStatus\tCreated\tCompleted\n"' \
    '    printf "TODO/one.md\tFix payment retry\tpayments\tp1\topen\t2026-09-01T08:00:00+02:00\t\n"' \
    '    ;;' \
    'esac' > "$fake_bin/obsidian.com"
  chmod +x "$fake_bin/obsidian.com"

  output="$(PATH="$fake_bin:$PATH" DEV_MAIN_BRANCH=main bash "$source_dir/scripts/resume.sh" preview "$repo")"

  assert_contains "$output" 'Next TODO:'
  assert_contains "$output" 'P1  [payments'
  assert_contains "$output" 'Fix payment retry'
}

test_select_returns_the_chosen_path_without_losing_spaces() {
  local workplace="$test_root/select place" repo="$test_root/select place/orders api"
  local fake_bin="$test_root/select-bin" output
  create_repo "$repo"
  mkdir -p "$fake_bin"
  printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$fake_bin/atuin"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'IFS= read -r first' \
    'printf "\n%s\n" "$first"' > "$fake_bin/fzf"
  chmod +x "$fake_bin/atuin" "$fake_bin/fzf"

  output="$(PATH="$fake_bin:$PATH" DEV_WORKPLACE="$workplace" bash "$source_dir/scripts/resume.sh" select)"

  assert_repo_under_test_root "$output" "$repo"
}

test_resume_shell_function_changes_the_current_directory() {
  local workplace="$test_root/function place" repo="$test_root/function place/billing api"
  local fake_bin="$test_root/function-bin" final_directory
  create_repo "$repo"
  mkdir -p "$fake_bin"
  printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$fake_bin/atuin"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'IFS= read -r first' \
    'printf "\n%s\n" "$first"' > "$fake_bin/fzf"
  chmod +x "$fake_bin/atuin" "$fake_bin/fzf"

  final_directory="$(
    PATH="$fake_bin:$PATH"
    DEV_WORKPLACE="$workplace"
    DEV_HARNESS_HOME="$source_dir"
    DEV_HARNESS_CONFIG="$test_root/missing-config.env"
    export PATH DEV_WORKPLACE DEV_HARNESS_HOME DEV_HARNESS_CONFIG
    # shellcheck source=../shell/dev-harness.bash
    . "$source_dir/shell/dev-harness.bash"
    cd "$test_root"
    resume
    printf '%s\n' "$PWD"
  )"

  assert_repo_under_test_root "$final_directory" "$repo"
}

test_ctrl_o_opens_the_selected_worktree_in_the_configured_editor() {
  local workplace="$test_root/open place" repo="$test_root/open place/customer portal"
  local fake_bin="$test_root/open-bin" editor_log="$test_root/editor.log"
  create_repo "$repo"
  mkdir -p "$fake_bin"
  printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$fake_bin/atuin"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'IFS= read -r first' \
    'printf "ctrl-o\n%s\n" "$first"' > "$fake_bin/fzf"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'printf "%s\n" "$1" > "$EDITOR_LOG"' > "$fake_bin/test-editor"
  chmod +x "$fake_bin/atuin" "$fake_bin/fzf" "$fake_bin/test-editor"

  PATH="$fake_bin:$PATH" DEV_WORKPLACE="$workplace" DEV_EDITOR=test-editor EDITOR_LOG="$editor_log" \
    bash "$source_dir/scripts/resume.sh" manage >/dev/null

  assert_repo_under_test_root "$(tr -d '\r' < "$editor_log")" "$repo"
}

test_resume_function_reports_success_for_a_picker_action() {
  local workplace="$test_root/function action place" repo="$test_root/function action place/search"
  local fake_bin="$test_root/function-action-bin" status=0
  create_repo "$repo"
  mkdir -p "$fake_bin"
  printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$fake_bin/atuin"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'IFS= read -r first' \
    'printf "ctrl-o\n%s\n" "$first"' > "$fake_bin/fzf"
  printf '%s\n' '#!/usr/bin/env bash' 'printf "EDITOR RESPONSE\n"' > "$fake_bin/test-editor"
  chmod +x "$fake_bin/atuin" "$fake_bin/fzf" "$fake_bin/test-editor"

  PATH="$fake_bin:$PATH"
  DEV_WORKPLACE="$workplace"
  DEV_EDITOR=test-editor
  DEV_HARNESS_HOME="$source_dir"
  DEV_HARNESS_CONFIG="$test_root/missing-action-config.env"
  export PATH DEV_WORKPLACE DEV_EDITOR DEV_HARNESS_HOME DEV_HARNESS_CONFIG
  # shellcheck source=../shell/dev-harness.bash
  . "$source_dir/shell/dev-harness.bash"
  resume >/dev/null 2>&1 || status=$?

  assert_equals "$status" 0
}

test_resume_function_does_not_treat_ai_output_as_a_directory() {
  local workplace="$test_root/function ai place" repo="$test_root/function ai place/pricing"
  local fake_bin="$test_root/function-ai-bin" action_output="$test_root/function-ai-output.txt" status=0 before
  create_repo "$repo"
  printf 'work\n' > "$repo/pricing.txt"
  mkdir -p "$fake_bin"
  printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$fake_bin/atuin"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'IFS= read -r first' \
    'printf "ctrl-a\n%s\n" "$first"' > "$fake_bin/fzf"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'cat >/dev/null' \
    'printf "AI RESPONSE\n"' > "$fake_bin/ai-response"
  chmod +x "$fake_bin/atuin" "$fake_bin/fzf" "$fake_bin/ai-response"

  PATH="$fake_bin:$PATH"
  DEV_WORKPLACE="$workplace"
  DEV_MAIN_BRANCH=main
  DEV_AI_RESUME_COMMAND=ai-response
  DEV_HARNESS_HOME="$source_dir"
  DEV_HARNESS_CONFIG="$test_root/missing-function-ai-config.env"
  export PATH DEV_WORKPLACE DEV_MAIN_BRANCH DEV_AI_RESUME_COMMAND DEV_HARNESS_HOME DEV_HARNESS_CONFIG
  # shellcheck source=../shell/dev-harness.bash
  . "$source_dir/shell/dev-harness.bash"
  cd "$test_root"
  before="$PWD"
  resume >"$action_output" 2>&1 || status=$?

  assert_equals "$status" 0
  assert_equals "$PWD" "$before"
  assert_contains "$(tr -d '\r' < "$action_output")" 'AI RESPONSE'
}

test_resume_function_does_not_treat_review_output_as_a_directory() {
  local workplace="$test_root/function review place" repo="$test_root/function review place/offers"
  local fake_bin="$test_root/function-review-bin" action_output="$test_root/function-review-output.txt" status=0 before
  create_repo "$repo"
  printf 'review\n' > "$repo/offers.txt"
  mkdir -p "$fake_bin"
  printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$fake_bin/atuin"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'IFS= read -r first' \
    'printf "ctrl-r\n%s\n" "$first"' > "$fake_bin/fzf"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'cat >/dev/null' \
    'printf "REVIEW RESPONSE\n"' > "$fake_bin/review-response"
  chmod +x "$fake_bin/atuin" "$fake_bin/fzf" "$fake_bin/review-response"

  PATH="$fake_bin:$PATH"
  DEV_WORKPLACE="$workplace"
  DEV_MAIN_BRANCH=main
  DEV_AI_REVIEW_COMMAND=review-response
  DEV_HARNESS_HOME="$source_dir"
  DEV_HARNESS_CONFIG="$test_root/missing-function-review-config.env"
  export PATH DEV_WORKPLACE DEV_MAIN_BRANCH DEV_AI_REVIEW_COMMAND DEV_HARNESS_HOME DEV_HARNESS_CONFIG
  # shellcheck source=../shell/dev-harness.bash
  . "$source_dir/shell/dev-harness.bash"
  cd "$test_root"
  before="$PWD"
  (DEV_HARNESS_INPUT=--all; export DEV_HARNESS_INPUT; resume >"$action_output" 2>&1) || status=$?

  assert_equals "$status" 0
  assert_equals "$PWD" "$before"
  assert_contains "$(tr -d '\r' < "$action_output")" 'REVIEW RESPONSE'
}

test_resume_context_excludes_sensitive_changes() {
  local repo="$test_root/context place/payments" output
  create_repo "$repo"
  git -C "$repo" switch -q -c feature/context
  printf 'safe\n' > "$repo/service.txt"
  printf 'secret\n' > "$repo/.env"

  output="$(DEV_MAIN_BRANCH=main bash "$source_dir/scripts/resume.sh" context "$repo")"

  assert_contains "$output" 'Resume the work in this repository.'
  assert_contains "$output" 'Repository: payments'
  assert_contains "$output" 'service.txt'
  if [[ "$output" == *'.env'* ]]; then
    fail 'Sensitive .env path leaked into resume context'
  fi
}

test_resume_context_handles_a_repository_without_commits() {
  local repo="$test_root/empty place/prototype" output
  create_empty_repo "$repo"
  printf 'first draft\n' > "$repo/prototype.txt"

  output="$(bash "$source_dir/scripts/resume.sh" context "$repo")"

  assert_contains "$output" 'Repository: prototype'
  assert_contains "$output" 'Base:       no commits yet'
  assert_contains "$output" 'prototype.txt'
}

test_unborn_resume_context_excludes_all_representative_sensitive_paths() {
  local repo="$test_root/unborn-sensitive place/prototype" output
  create_empty_repo "$repo"
  mkdir -p "$repo/.ssh" "$repo/credentials" "$repo/Secrets-prod" "$repo/src"
  printf 'PRIVATE_KEY_MARKER\n' > "$repo/.ssh/custom_key"
  printf 'ED25519_MARKER\n' > "$repo/id_ed25519"
  printf 'JKS_MARKER\n' > "$repo/development.jks"
  printf 'CREDENTIAL_DESCENDANT_MARKER\n' > "$repo/credentials/token.txt"
  printf 'SECRET_DESCENDANT_MARKER\n' > "$repo/Secrets-prod/config.txt"
  printf 'APP_MARKER\n' > "$repo/src/App.java"
  git -C "$repo" add .ssh/custom_key id_ed25519 development.jks credentials/token.txt Secrets-prod/config.txt src/App.java
  stage_index_only_path "$repo" ID_ED25519 'UPPER_ED25519_MARKER'
  stage_index_only_path "$repo" DEVELOPMENT.JKS 'UPPER_JKS_MARKER'
  stage_index_only_path "$repo" .SSH/custom_key 'UPPER_SSH_MARKER'

  output="$(bash "$source_dir/scripts/resume.sh" context "$repo")"

  assert_contains "$output" 'src/App.java'
  assert_not_contains "$output" '.ssh/custom_key'
  assert_not_contains "$output" 'id_ed25519'
  assert_not_contains "$output" 'development.jks'
  assert_not_contains "$output" 'ID_ED25519'
  assert_not_contains "$output" 'DEVELOPMENT.JKS'
  assert_not_contains "$output" '.SSH/custom_key'
  assert_not_contains "$output" 'Secrets-prod'
  assert_not_contains "$output" 'credentials/token.txt'
  assert_not_contains "$output" 'Secrets-prod/config.txt'
}

test_ctrl_y_copies_resume_context() {
  local workplace="$test_root/copy place" repo="$test_root/copy place/risk engine"
  local fake_bin="$test_root/copy-bin" clip_log="$test_root/clipboard.txt" copied
  create_repo "$repo"
  printf 'changed\n' > "$repo/risk.txt"
  mkdir -p "$fake_bin"
  printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$fake_bin/atuin"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'IFS= read -r first' \
    'printf "ctrl-y\n%s\n" "$first"' > "$fake_bin/fzf"
  chmod +x "$fake_bin/atuin" "$fake_bin/fzf"
  install_clipboard_stub "$fake_bin"

  PATH="$fake_bin:$PATH" DEV_WORKPLACE="$workplace" DEV_MAIN_BRANCH=main CLIP_LOG="$clip_log" \
    bash "$source_dir/scripts/resume.sh" manage >/dev/null 2>&1
  copied="$(tr -d '\r' < "$clip_log")"

  assert_contains "$copied" 'Resume the work in this repository.'
  assert_contains "$copied" 'Repository: risk engine'
  assert_contains "$copied" 'risk.txt'
}

test_ctrl_a_sends_resume_context_to_ai_from_the_selected_worktree() {
  local workplace="$test_root/ai place" repo="$test_root/ai place/ledger"
  local fake_bin="$test_root/ai-bin" ai_log="$test_root/ai-context.txt" pwd_log="$test_root/ai-pwd.txt" prompt
  create_repo "$repo"
  printf 'pending\n' > "$repo/ledger.txt"
  mkdir -p "$fake_bin"
  printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$fake_bin/atuin"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'IFS= read -r first' \
    'printf "ctrl-a\n%s\n" "$first"' > "$fake_bin/fzf"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'cat > "$AI_LOG"' \
    'pwd > "$AI_PWD_LOG"' > "$fake_bin/ai-capture"
  chmod +x "$fake_bin/atuin" "$fake_bin/fzf" "$fake_bin/ai-capture"

  PATH="$fake_bin:$PATH" DEV_WORKPLACE="$workplace" DEV_MAIN_BRANCH=main \
    DEV_AI_RESUME_COMMAND=ai-capture AI_LOG="$ai_log" AI_PWD_LOG="$pwd_log" \
    bash "$source_dir/scripts/resume.sh" manage >/dev/null
  prompt="$(tr -d '\r' < "$ai_log")"

  assert_contains "$prompt" 'Resume the work in this repository.'
  assert_contains "$prompt" 'ledger.txt'
  assert_repo_under_test_root "$(tr -d '\r' < "$pwd_log")" "$repo"
}

test_ctrl_r_reviews_changes_from_the_selected_worktree() {
  local workplace="$test_root/review place" repo="$test_root/review place/gateway"
  local fake_bin="$test_root/review-bin" review_log="$test_root/review-context.txt" pwd_log="$test_root/review-pwd.txt" prompt
  create_repo "$repo"
  printf 'review me\n' > "$repo/gateway.txt"
  mkdir -p "$fake_bin"
  printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$fake_bin/atuin"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'IFS= read -r first' \
    'printf "ctrl-r\n%s\n" "$first"' > "$fake_bin/fzf"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'cat > "$REVIEW_LOG"' \
    'pwd > "$REVIEW_PWD_LOG"' > "$fake_bin/review-capture"
  chmod +x "$fake_bin/atuin" "$fake_bin/fzf" "$fake_bin/review-capture"

  PATH="$fake_bin:$PATH" DEV_WORKPLACE="$workplace" DEV_MAIN_BRANCH=main DEV_HARNESS_INPUT=--all \
    DEV_AI_REVIEW_COMMAND=review-capture REVIEW_LOG="$review_log" REVIEW_PWD_LOG="$pwd_log" \
    bash "$source_dir/scripts/resume.sh" manage >/dev/null
  prompt="$(tr -d '\r' < "$review_log")"

  assert_contains "$prompt" 'Review the following repository changes'
  assert_contains "$prompt" 'gateway.txt'
  assert_repo_under_test_root "$(tr -d '\r' < "$pwd_log")" "$repo"
}

test_global_task_exposes_the_resume_picker() {
  local workplace="$test_root/task place" repo="$test_root/task place/notifications"
  local fake_bin="$test_root/task-bin" output
  create_repo "$repo"
  mkdir -p "$fake_bin"
  printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$fake_bin/atuin"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'IFS= read -r first' \
    'printf "\n%s\n" "$first"' > "$fake_bin/fzf"
  chmod +x "$fake_bin/atuin" "$fake_bin/fzf"

  output="$(
    cd "$test_root"
    PATH="$fake_bin:$PATH" HOME="$test_root" DEV_HARNESS_HOME="$source_dir" DEV_WORKPLACE="$workplace" \
      task --taskfile "$source_dir/Taskfile.global.yml" resume
  )"

  assert_repo_under_test_root "$output" "$repo"
}

test_global_palette_discovers_resume_from_outside_a_repository() {
  local workplace="$test_root/palette place" repo="$test_root/palette place/reporting"
  local fake_bin="$test_root/palette-bin" output
  create_repo "$repo"
  mkdir -p "$fake_bin"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'row="$(awk -F "\t" '\''$1 == "resume" { print; exit }'\'')"' \
    '[ -n "$row" ] || exit 9' \
    'printf "%s\n" "$row"' > "$fake_bin/fzf"
  chmod +x "$fake_bin/fzf"

  output="$(
    cd "$test_root"
    PATH="$fake_bin:$PATH" DEV_WORKPLACE="$workplace" \
      bash "$source_dir/scripts/palette.sh" select
  )"

  assert_equals "$output" resume
}

test_help_and_alias_reference_explain_resume() {
  local help_output aliases_output
  help_output="$(bash "$source_dir/scripts/help.sh" help)"
  aliases_output="$(bash "$source_dir/scripts/help.sh" aliases)"

  assert_contains "$help_output" 'resume'
  assert_contains "$help_output" 'recent project or worktree'
  assert_contains "$aliases_output" 'resume'
  assert_contains "$aliases_output" 'select recent context and cd'
}

test_doctor_rejects_an_invalid_resume_limit() {
  local output status=0
  output="$(
    DEV_RESUME_LIMIT=0 DEV_TODO_DEFAULT_PRIORITY=p2 DEV_AI_COMMAND=git \
      bash "$source_dir/scripts/doctor.sh" --json
  )" || status=$?

  assert_equals "$status" 1
  assert_contains "$output" '"name":"DEV_RESUME_LIMIT","status":"error"'
}

test_doctor_reports_an_unavailable_configured_resume_command() {
  local output
  output="$(
    DEV_RESUME_LIMIT=10 DEV_TODO_DEFAULT_PRIORITY=p2 DEV_AI_COMMAND=git \
    DEV_AI_RESUME_COMMAND=dev-harness-command-that-does-not-exist \
      bash "$source_dir/scripts/doctor.sh" --json
  )" || true

  assert_contains "$output" '"name":"DEV_AI_RESUME_COMMAND","status":"warn"'
  assert_contains "$output" 'configured command is unavailable'
}

test_recent_atuin_directories_are_collapsed_to_one_repository
printf 'PASS: recent Atuin directories collapse to one repository\n'
test_repeated_atuin_directory_is_resolved_only_once
printf 'PASS: repeated Atuin directories are resolved once\n'
test_workplace_discovery_includes_linked_worktrees
printf 'PASS: workplace discovery includes linked worktrees\n'
test_preview_summarizes_branch_and_working_tree_state
printf 'PASS: preview summarizes branch and working tree state\n'
test_preview_shows_the_highest_priority_project_todo_when_available
printf 'PASS: preview shows highest-priority TODO\n'
test_select_returns_the_chosen_path_without_losing_spaces
printf 'PASS: select returns paths with spaces intact\n'
test_resume_shell_function_changes_the_current_directory
printf 'PASS: resume changes the current shell directory\n'
test_ctrl_o_opens_the_selected_worktree_in_the_configured_editor
printf 'PASS: Ctrl-O opens the selected worktree\n'
test_resume_function_reports_success_for_a_picker_action
printf 'PASS: resume reports successful picker actions\n'
test_resume_function_does_not_treat_ai_output_as_a_directory
printf 'PASS: resume keeps AI output separate from path selection\n'
test_resume_function_does_not_treat_review_output_as_a_directory
printf 'PASS: resume keeps review output separate from path selection\n'
test_resume_context_excludes_sensitive_changes
printf 'PASS: resume context excludes sensitive changes\n'
test_resume_context_handles_a_repository_without_commits
printf 'PASS: resume context handles repositories without commits\n'
test_unborn_resume_context_excludes_all_representative_sensitive_paths
printf 'PASS: unborn resume context excludes representative sensitive paths\n'
test_ctrl_y_copies_resume_context
printf 'PASS: Ctrl-Y copies resume context\n'
test_ctrl_a_sends_resume_context_to_ai_from_the_selected_worktree
printf 'PASS: Ctrl-A sends resume context to AI\n'
test_ctrl_r_reviews_changes_from_the_selected_worktree
printf 'PASS: Ctrl-R reviews the selected worktree\n'
test_global_task_exposes_the_resume_picker
printf 'PASS: global Taskfile exposes resume\n'
test_global_palette_discovers_resume_from_outside_a_repository
printf 'PASS: global palette discovers resume\n'
test_help_and_alias_reference_explain_resume
printf 'PASS: help explains resume\n'
test_doctor_rejects_an_invalid_resume_limit
printf 'PASS: doctor validates resume limit\n'
test_doctor_reports_an_unavailable_configured_resume_command
printf 'PASS: doctor validates configured resume command\n'
