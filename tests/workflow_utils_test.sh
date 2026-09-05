#!/usr/bin/env bash
set -euo pipefail

source_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/dev-harness-workflow-utils-test.XXXXXX")"

cleanup() {
  case "$test_root" in
    "${TMPDIR:-/tmp}"/dev-harness-workflow-utils-test.*) rm -rf -- "$test_root" ;;
    *) printf 'Refusing unsafe test cleanup: %s\n' "$test_root" >&2 ;;
  esac
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_equals() {
  local actual="$1" expected="$2"
  [ "$actual" = "$expected" ] || fail "Expected '$expected', got '$actual'"
}

assert_contains() {
  local haystack="$1" needle="$2"
  [[ "$haystack" == *"$needle"* ]] || fail "Expected value to contain: $needle"
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

create_unborn_repo() {
  local path="$1"
  mkdir -p "$path"
  git -C "$path" init -q
  git -C "$path" symbolic-ref HEAD refs/heads/main
  git -C "$path" config user.email test@example.com
  git -C "$path" config user.name 'Dev Harness Test'
  git -C "$path" config core.autocrlf false
}

create_fake_obsidian() {
  local bin="$1"
  mkdir -p "$bin"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    ': "${OBS_STATE:?}"' \
    ': "${OBS_LOG:?}"' \
    '{ for argument in "$@"; do printf "%s\t" "$argument"; done; printf "\n"; } >> "$OBS_LOG"' \
    'value_for() {' \
    '  local key="$1" argument' \
    '  shift' \
    '  for argument in "$@"; do case "$argument" in "$key"=*) printf "%s\n" "${argument#*=}"; return 0 ;; esac; done' \
    '  return 1' \
    '}' \
    'if [[ "${1:-}" == vault=* ]]; then shift; fi' \
    'command="${1:?}"' \
    'shift' \
    'case "$command" in' \
    '  file)' \
    '    path="$(value_for path "$@")"' \
    '    [ -f "$OBS_STATE/files/$path" ]' \
    '    ;;' \
    '  base:query)' \
    '    cat "${OBS_ROWS:?}"' \
    '    ;;' \
    '  daily:append)' \
    '    content="$(value_for content "$@")"' \
    '    printf "%s" "$content" > "$OBS_STATE/daily-append.txt"' \
    '    ;;' \
    '  read)' \
    '    path="$(value_for path "$@")"' \
    '    printf "Preview: %s\n" "$path"' \
    '    ;;' \
    '  open|create|append|property:set|property:remove) exit 0 ;;' \
    '  *) printf "Unexpected Obsidian command: %s\n" "$command" >&2; exit 64 ;;' \
    'esac' > "$bin/obsidian.com"
  chmod +x "$bin/obsidian.com"
}

setup_obsidian_state() {
  local state="$1" rows="$2"
  mkdir -p "$state/files/TODO"
  : > "$state/files/TODO/TODO.base"
  printf '%s\n' $'Path\tTitle\tProject\tPriority\tStatus\tCreated\tCompleted' > "$rows"
}

write_fake_fzf() {
  local bin="$1" action="$2"
  mkdir -p "$bin"
  case "$action" in
    enter)
      printf '%s\n' '#!/usr/bin/env bash' 'IFS= read -r first' 'printf "\n%s\n" "$first"' > "$bin/fzf"
      ;;
    ctrl-o)
      printf '%s\n' '#!/usr/bin/env bash' 'IFS= read -r first' 'printf "ctrl-o\n%s\n" "$first"' > "$bin/fzf"
      ;;
    cancel)
      printf '%s\n' '#!/usr/bin/env bash' 'exit 130' > "$bin/fzf"
      ;;
    *) fail "Unknown fake fzf action: $action" ;;
  esac
  chmod +x "$bin/fzf"
}

mkdir -p "$test_root/home" "$test_root/xdg"
export HOME="$test_root/home"
export XDG_CONFIG_HOME="$test_root/xdg"
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_SYSTEM=/dev/null
export GIT_TEMPLATE_DIR="$test_root/templates"
mkdir -p "$GIT_TEMPLATE_DIR"

test_gr_changes_to_repository_root_with_spaces() {
  local repo="$test_root/gr place/repository with spaces" output
  create_repo "$repo"
  mkdir -p "$repo/src/nested"

  output="$(
    cd "$repo/src/nested"
    DEV_HARNESS_HOME="$source_dir" bash -c \
      'source "$DEV_HARNESS_HOME/shell/dev-harness.bash"; gr; pwd -P'
  )"

  assert_equals "$output" "$(cd "$repo" && pwd -P)"
}

test_gr_fails_outside_git_without_changing_directory() {
  local outside="$test_root/outside" output
  mkdir -p "$outside"

  output="$(
    cd "$outside"
    DEV_HARNESS_HOME="$source_dir" bash -c \
      'source "$DEV_HARNESS_HOME/shell/dev-harness.bash"; before="$(pwd -P)"; if gr; then result=0; else result=$?; fi; printf "status=%s\nbefore=%s\nafter=%s\n" "$result" "$before" "$(pwd -P)"' 2>&1
  )"

  assert_contains "$output" 'Not inside a Git repository.'
  assert_contains "$output" 'status=1'
  assert_contains "$output" "before=$(cd "$outside" && pwd -P)"
  assert_contains "$output" "after=$(cd "$outside" && pwd -P)"
}

test_dirty_discovers_only_unique_dirty_worktrees_with_exact_counts() {
  local workplace="$test_root/dirty discovery/workplace"
  local repo="$workplace/ledger" clean="$workplace/clean" linked="$test_root/linked worktree"
  local outside="$test_root/current outside workplace" rows duplicate_count
  create_repo "$repo"
  create_repo "$clean"
  create_repo "$outside"
  git -C "$repo" worktree add -q -b feature/linked "$linked"

  printf 'staged\n' > "$repo/staged.txt"
  git -C "$repo" add staged.txt
  printf 'changed\n' >> "$repo/README.md"
  printf 'untracked\n' > "$repo/untracked.txt"
  printf 'linked\n' > "$linked/linked.txt"
  printf 'outside\n' > "$outside/outside.txt"

  rows="$(
    cd "$outside"
    DEV_WORKPLACE="$workplace" bash "$source_dir/scripts/dirty.sh" candidates
  )"

  assert_contains "$rows" $'ledger\tmain\t+1\t~1\t?1\t'
  assert_contains "$rows" "$(cd "$repo" && pwd -P)"
  assert_contains "$rows" "$(cd "$linked" && pwd -P)"
  assert_contains "$rows" "$(cd "$outside" && pwd -P)"
  [[ "$rows" != *"$(cd "$clean" && pwd -P)"* ]] || fail 'A clean repository was included'
  duplicate_count="$(printf '%s\n' "$rows" | cut -f6- | sort | uniq -d | wc -l | tr -d ' ')"
  assert_equals "$duplicate_count" 0
}

test_dirty_select_returns_a_path_with_spaces_and_opens_exact_path() {
  local workplace="$test_root/dirty picker" repo
  local fake_bin="$test_root/dirty picker bin" editor_log="$test_root/dirty-editor.log" selected
  repo="$workplace/repository with spaces"
  create_repo "$repo"
  printf 'dirty\n' > "$repo/with spaces.txt"
  mkdir -p "$fake_bin"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'IFS= read -r first' \
    'printf "\n%s\n" "$first"' > "$fake_bin/fzf"
  chmod +x "$fake_bin/fzf"

  selected="$(
    cd "$test_root"
    PATH="$fake_bin:$PATH" DEV_WORKPLACE="$workplace" \
      bash "$source_dir/scripts/dirty.sh" select
  )"
  assert_equals "$selected" "$(cd "$repo" && pwd -P)"

  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'IFS= read -r first' \
    'printf "ctrl-o\n%s\n" "$first"' > "$fake_bin/fzf"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'printf "%s\n" "$1" > "$EDITOR_LOG"' > "$fake_bin/editor-capture"
  chmod +x "$fake_bin/fzf" "$fake_bin/editor-capture"

  selected="$(
    cd "$test_root"
    PATH="$fake_bin:$PATH" DEV_WORKPLACE="$workplace" DEV_EDITOR=editor-capture EDITOR_LOG="$editor_log" \
      bash "$source_dir/scripts/dirty.sh" select
  )"
  assert_equals "$selected" ''
  assert_equals "$(cat "$editor_log")" "$(cd "$repo" && pwd -P)"
}

test_dirty_handles_preview_cancel_clean_and_missing_workplace() {
  local fixture="$test_root/dirty edges" current="$test_root/dirty edges/current"
  local workplace="$test_root/dirty edges/clean workplace" clean
  local fake_bin="$test_root/dirty edges/bin" output status=0 expected_root
  clean="$workplace/clean"
  create_repo "$current"
  create_repo "$clean"
  printf 'current\n' > "$current/current.txt"
  mkdir -p "$fake_bin"
  printf '%s\n' '#!/usr/bin/env bash' 'exit 130' > "$fake_bin/fzf"
  chmod +x "$fake_bin/fzf"

  output="$(cd "$current" && DEV_WORKPLACE= bash "$source_dir/scripts/dirty.sh" candidates)"
  expected_root="$(cd "$current" && pwd -P)"
  assert_contains "$output" "$expected_root"

  output="$(
    cd "$test_root"
    PATH="$fake_bin:$PATH" DEV_WORKPLACE="$workplace" bash "$source_dir/scripts/dirty.sh" select 2>&1
  )"
  assert_equals "$output" 'No dirty repositories.'

  output="$(
    cd "$current"
    PATH="$fake_bin:$PATH" DEV_WORKPLACE= bash "$source_dir/scripts/dirty.sh" select
  )"
  assert_equals "$output" ''

  output="$(cd "$current" && bash "$source_dir/scripts/dirty.sh" preview "$current")"
  assert_contains "$output" 'Project:    current'
  assert_contains "$output" "Worktree:   $expected_root"
  assert_contains "$output" 'Branch:     main'
  assert_contains "$output" 'Changes:    0 staged · 0 unstaged · 1 untracked'

  status=0
  output="$(
    cd "$test_root"
    DEV_WORKPLACE="$test_root/not-there" bash "$source_dir/scripts/dirty.sh" select 2>&1
  )" || status=$?
  [ "$status" -ne 0 ] || fail 'dirty succeeded without a current repository or valid workplace'
  assert_contains "$output" 'Set DEV_WORKPLACE'
}

test_why_delegates_to_resume_preview_without_ai() {
  local repo="$test_root/why/repository" unborn="$test_root/why/unborn"
  local fake_bin="$test_root/why/bin" ai_marker="$test_root/why/ai-called" actual
  create_repo "$repo"
  create_unborn_repo "$unborn"
  printf 'changed\n' > "$repo/change.txt"
  printf 'new\n' > "$unborn/new.txt"
  mkdir -p "$fake_bin"
  printf '%s\n' '#!/usr/bin/env bash' ': > "$AI_MARKER"' > "$fake_bin/ai-capture"
  chmod +x "$fake_bin/ai-capture"

  actual="$(
    cd "$repo"
    PATH="$fake_bin:$PATH" AI_MARKER="$ai_marker" DEV_AI_COMMAND=ai-capture DEV_AI_RESUME_COMMAND=ai-capture \
      bash "$source_dir/scripts/workflow.sh" why
  )"
  assert_contains "$actual" 'Project:    repository'
  assert_contains "$actual" "Worktree:   $(cd "$repo" && pwd -P)"
  assert_contains "$actual" 'Branch:     main'
  assert_contains "$actual" 'Base:       main'
  assert_contains "$actual" 'Changes:    0 staged · 0 unstaged · 1 untracked'
  assert_contains "$actual" 'Commits:    0 since base'
  assert_contains "$actual" 'Last commit:'
  assert_contains "$actual" 'Initial commit'
  assert_contains "$actual" 'Changed files:'
  assert_contains "$actual" 'change.txt'
  [ ! -e "$ai_marker" ] || fail 'why invoked AI'

  actual="$(cd "$unborn" && bash "$source_dir/scripts/workflow.sh" why)"
  assert_contains "$actual" 'Project:    unborn'
  assert_contains "$actual" "Worktree:   $(cd "$unborn" && pwd -P)"
  assert_contains "$actual" 'Branch:     main'
  assert_contains "$actual" 'Changes:    0 staged · 0 unstaged · 1 untracked'
}

test_why_fails_outside_git() {
  local outside="$test_root/why-outside" output status=0
  mkdir -p "$outside"
  output="$(cd "$outside" && bash "$source_dir/scripts/workflow.sh" why 2>&1)" || status=$?
  [ "$status" -ne 0 ] || fail 'why succeeded outside Git'
  assert_contains "$output" 'inside a Git repository'
}

test_handoff_prints_and_copies_the_same_secret_filtered_context() {
  local repo="$test_root/handoff/repository" fake_bin="$test_root/handoff/bin"
  local clip_log="$test_root/handoff/clipboard.txt" ai_marker="$test_root/handoff/ai-called"
  local default_output copy_output copied errors="$test_root/handoff/errors.txt" sensitive
  create_repo "$repo"
  mkdir -p "$repo/src" "$repo/.ssh" "$repo/nested" "$repo/secrets" "$fake_bin"
  printf 'safe marker\n' > "$repo/src/Safe.java"
  printf 'secret env\n' > "$repo/.env"
  printf 'secret env case\n' > "$repo/.ENV.local"
  printf 'secret ssh\n' > "$repo/.ssh/custom_key"
  printf 'secret credentials\n' > "$repo/nested/credentials.json"
  printf 'secret jks\n' > "$repo/development.jks"
  printf 'secret key\n' > "$repo/id_ed25519"
  printf 'secret nested\n' > "$repo/secrets/config.yml"
  printf '%s\n' '#!/usr/bin/env bash' 'cat > "$CLIP_LOG"' > "$fake_bin/clip.exe"
  printf '%s\n' '#!/usr/bin/env bash' ': > "$AI_MARKER"' > "$fake_bin/ai-capture"
  chmod +x "$fake_bin/clip.exe" "$fake_bin/ai-capture"

  default_output="$(
    cd "$repo"
    PATH="$fake_bin:$PATH" CLIP_LOG="$clip_log" AI_MARKER="$ai_marker" DEV_AI_RESUME_COMMAND=ai-capture \
      bash "$source_dir/scripts/workflow.sh" handoff
  )"
  assert_contains "$default_output" 'Resume the work in this repository.'
  assert_contains "$default_output" 'src/Safe.java'
  [ ! -e "$clip_log" ] || fail 'Default handoff touched the clipboard'
  [ ! -e "$ai_marker" ] || fail 'handoff invoked AI'
  for sensitive in '.env' '.ENV.local' '.ssh/custom_key' 'nested/credentials.json' 'development.jks' 'id_ed25519' 'secrets/config.yml' 'secret env' 'secret ssh'; do
    [[ "$default_output" != *"$sensitive"* ]] || fail "Handoff disclosed sensitive data: $sensitive"
  done

  copy_output="$(
    cd "$repo"
    PATH="$fake_bin:$PATH" CLIP_LOG="$clip_log" AI_MARKER="$ai_marker" \
      bash "$source_dir/scripts/workflow.sh" handoff --copy 2> "$errors"
  )"
  assert_equals "$copy_output" ''
  copied="$(tr -d '\r' < "$clip_log")"
  assert_equals "$copied" "$default_output"
  assert_contains "$(cat "$errors")" 'Handoff context copied.'
  [ ! -e "$ai_marker" ] || fail 'handoff --copy invoked AI'
}

test_handoff_rejects_invalid_options_before_side_effects() {
  local repo="$test_root/handoff-invalid/repository" fake_bin="$test_root/handoff-invalid/bin"
  local clip_log="$test_root/handoff-invalid/clipboard.txt" output status arguments
  create_repo "$repo"
  mkdir -p "$fake_bin"
  printf '%s\n' '#!/usr/bin/env bash' 'cat > "$CLIP_LOG"' > "$fake_bin/clip.exe"
  chmod +x "$fake_bin/clip.exe"

  for arguments in '--unknown' '--copy --copy' 'text'; do
    rm -f -- "$clip_log"
    status=0
    output="$(
      cd "$repo"
      PATH="$fake_bin:$PATH" CLIP_LOG="$clip_log" \
        bash "$source_dir/scripts/workflow.sh" handoff $arguments 2>&1
    )" || status=$?
    [ "$status" -ne 0 ] || fail "Invalid handoff options succeeded: $arguments"
    assert_contains "$output" "Use 'handoff [--copy]'."
    [ ! -e "$clip_log" ] || fail "Invalid handoff options touched clipboard: $arguments"
  done

  status=0
  output="$(
    cd "$repo"
    PATH="$fake_bin:$PATH" CLIP_LOG="$clip_log" DEV_HARNESS_INPUT=--copy \
      bash "$source_dir/scripts/workflow.sh" handoff --copy 2>&1
  )" || status=$?
  [ "$status" -ne 0 ] || fail 'handoff accepted duplicate argument sources'
  assert_contains "$output" 'both as arguments and through DEV_HARNESS_INPUT'
  [ ! -e "$clip_log" ] || fail 'Duplicate handoff argument sources touched clipboard'
}

test_standup_renders_recent_safe_activity_and_sorted_project_todos() {
  local fixture="$test_root/standup" repo="$test_root/standup/tracker" bin="$test_root/standup/bin"
  local state="$test_root/standup/state" rows="$test_root/standup/todos.tsv" log="$test_root/standup/obsidian.log"
  local ai_marker="$test_root/standup/ai-called" output p0_line p1_line p2_line sensitive
  mkdir -p "$fixture"
  create_unborn_repo "$repo"
  printf 'old\n' > "$repo/old.txt"
  git -C "$repo" add old.txt
  GIT_AUTHOR_DATE='2000-01-01T00:00:00+0000' GIT_COMMITTER_DATE='2000-01-01T00:00:00+0000' \
    git -C "$repo" commit -q -m 'Old private subject'
  printf 'older recent\n' > "$repo/recent-older.txt"
  git -C "$repo" add recent-older.txt
  git -C "$repo" commit -q -m 'Older recent subject' -m 'PRIVATE COMMIT BODY'
  printf 'newest recent\n' > "$repo/recent-newest.txt"
  git -C "$repo" add recent-newest.txt
  git -C "$repo" commit -q -m 'Newest recent subject'
  mkdir -p "$repo/src" "$repo/secrets"
  printf 'safe\n' > "$repo/src/Safe.java"
  printf 'SECRET ENV CONTENT\n' > "$repo/.env"
  printf 'SECRET NESTED CONTENT\n' > "$repo/secrets/config.yml"

  create_fake_obsidian "$bin"
  setup_obsidian_state "$state" "$rows"
  : > "$log"
  printf '%s\n' \
    $'TODO/p2.md\tMedium task\ttracker\tp2\topen\t2026-09-01T10:00:00+02:00\t' \
    $'TODO/other.md\tOther project\tother\tp0\topen\t2026-09-04T11:00:00+02:00\t' \
    $'TODO/p0.md\tCritical task\ttracker\tp0\topen\t2026-09-04T10:00:00+02:00\t' \
    $'TODO/p1.md\tHigh task\ttracker\tp1\topen\t2026-09-03T10:00:00+02:00\t' >> "$rows"
  printf '%s\n' '#!/usr/bin/env bash' ': > "$AI_MARKER"' > "$bin/ai-capture"
  chmod +x "$bin/ai-capture"

  output="$(
    cd "$repo"
    PATH="$bin:$PATH" OBS_STATE="$state" OBS_ROWS="$rows" OBS_LOG="$log" AI_MARKER="$ai_marker" DEV_AI_COMMAND=ai-capture \
      bash "$source_dir/scripts/workflow.sh" standup
  )"

  assert_contains "$output" '## tracker · main'
  assert_contains "$output" '### Commits in the last 24 hours'
  assert_contains "$output" 'Newest recent subject'
  assert_contains "$output" 'Older recent subject'
  assert_contains "$output" '### Current changes'
  assert_contains "$output" '- src/Safe.java'
  assert_contains "$output" '### Open TODOs'
  assert_contains "$output" '- P0 Critical task'
  assert_contains "$output" '- P1 High task'
  assert_contains "$output" '- P2 Medium task'
  p0_line="$(printf '%s\n' "$output" | grep -nF -- '- P0 Critical task' | cut -d: -f1)"
  p1_line="$(printf '%s\n' "$output" | grep -nF -- '- P1 High task' | cut -d: -f1)"
  p2_line="$(printf '%s\n' "$output" | grep -nF -- '- P2 Medium task' | cut -d: -f1)"
  [ "$p0_line" -lt "$p1_line" ] && [ "$p1_line" -lt "$p2_line" ] || fail 'Standup TODOs are not priority sorted'
  for sensitive in 'Old private subject' 'PRIVATE COMMIT BODY' 'test@example.com' '.env' 'secrets/config.yml' 'SECRET ENV CONTENT' 'Other project'; do
    [[ "$output" != *"$sensitive"* ]] || fail "Standup disclosed excluded text: $sensitive"
  done
  [ ! -e "$ai_marker" ] || fail 'standup invoked AI'
}

test_standup_handles_empty_and_unavailable_obsidian_sections() {
  local repo="$test_root/standup-empty/empty" minimal_path output none_count
  create_unborn_repo "$repo"
  minimal_path="$(dirname "$(command -v git)"):/usr/bin:/bin"

  output="$(cd "$repo" && PATH="$minimal_path" bash "$source_dir/scripts/workflow.sh" standup)"
  assert_contains "$output" '## empty · main'
  assert_contains "$output" '- unavailable (Obsidian CLI not configured)'
  none_count="$(printf '%s\n' "$output" | grep -Fxc -- '- none')"
  assert_equals "$none_count" 2
}

test_standup_copy_and_day_use_the_exact_report() {
  local repo="$test_root/standup-actions/tracker" bin="$test_root/standup-actions/bin"
  local state="$test_root/standup-actions/state" rows="$test_root/standup-actions/todos.tsv"
  local log="$test_root/standup-actions/obsidian.log" clip_log="$test_root/standup-actions/clipboard.txt"
  local errors="$test_root/standup-actions/errors.txt" expected output copied daily
  create_repo "$repo"
  printf 'safe\n' > "$repo/safe.txt"
  create_fake_obsidian "$bin"
  setup_obsidian_state "$state" "$rows"
  : > "$log"
  printf '%s\n' '#!/usr/bin/env bash' 'cat > "$CLIP_LOG"' > "$bin/clip.exe"
  chmod +x "$bin/clip.exe"

  expected="$(
    cd "$repo"
    PATH="$bin:$PATH" OBS_STATE="$state" OBS_ROWS="$rows" OBS_LOG="$log" \
      bash "$source_dir/scripts/workflow.sh" standup
  )"
  output="$(
    cd "$repo"
    PATH="$bin:$PATH" OBS_STATE="$state" OBS_ROWS="$rows" OBS_LOG="$log" CLIP_LOG="$clip_log" \
      bash "$source_dir/scripts/workflow.sh" standup --copy 2> "$errors"
  )"
  assert_equals "$output" ''
  copied="$(tr -d '\r' < "$clip_log")"
  assert_equals "$copied" "$expected"
  assert_contains "$(cat "$errors")" 'Standup copied.'

  : > "$log"
  output="$(
    cd "$repo"
    PATH="$bin:$PATH" OBS_STATE="$state" OBS_ROWS="$rows" OBS_LOG="$log" \
      bash "$source_dir/scripts/workflow.sh" standup --day 2> "$errors"
  )"
  assert_equals "$output" ''
  daily="$(cat "$state/daily-append.txt")"
  assert_equals "$daily" "$expected"
  assert_contains "$(cat "$errors")" 'Standup appended to today.'
  [ "$(grep -c '^daily:append' "$log")" -eq 1 ] || fail 'standup --day did not make exactly one Daily append'
  ! grep -Eq '^(create|append|property:set|property:remove)' "$log" || fail 'standup --day performed an unrelated Obsidian mutation'
}

test_standup_rejects_invalid_actions_before_side_effects() {
  local repo="$test_root/standup-invalid/tracker" bin="$test_root/standup-invalid/bin"
  local state="$test_root/standup-invalid/state" rows="$test_root/standup-invalid/todos.tsv"
  local log="$test_root/standup-invalid/obsidian.log" clip_log="$test_root/standup-invalid/clipboard.txt"
  local output status arguments
  create_repo "$repo"
  create_fake_obsidian "$bin"
  setup_obsidian_state "$state" "$rows"
  printf '%s\n' '#!/usr/bin/env bash' 'cat > "$CLIP_LOG"' > "$bin/clip.exe"
  chmod +x "$bin/clip.exe"

  for arguments in '--copy --day' '--copy --copy' '--day --day' '--unknown'; do
    : > "$log"
    rm -f -- "$clip_log" "$state/daily-append.txt"
    status=0
    output="$(
      cd "$repo"
      PATH="$bin:$PATH" OBS_STATE="$state" OBS_ROWS="$rows" OBS_LOG="$log" CLIP_LOG="$clip_log" \
        bash "$source_dir/scripts/workflow.sh" standup $arguments 2>&1
    )" || status=$?
    [ "$status" -ne 0 ] || fail "Invalid standup action succeeded: $arguments"
    assert_contains "$output" "Use 'standup [--copy|--day]'."
    [ ! -e "$clip_log" ] || fail "Invalid standup action touched clipboard: $arguments"
    [ ! -e "$state/daily-append.txt" ] || fail "Invalid standup action wrote Daily: $arguments"
    [ ! -s "$log" ] || fail "Invalid standup action invoked Obsidian: $arguments"
  done
}

test_focus_candidates_preserve_priority_order_and_filter() {
  local fixture="$test_root/focus-candidates" bin="$test_root/focus-candidates/bin"
  local state="$test_root/focus-candidates/state" rows="$test_root/focus-candidates/todos.tsv"
  local log="$test_root/focus-candidates/obsidian.log" output expected status=0
  mkdir -p "$fixture"
  create_fake_obsidian "$bin"
  setup_obsidian_state "$state" "$rows"
  : > "$log"
  printf '%s\n' \
    $'TODO/p2.md\tMedium task\tbeta\tp2\topen\t2026-09-01T10:00:00+02:00\t' \
    $'TODO/p0.md\tCritical task\talpha\tp0\topen\t2026-09-04T10:00:00+02:00\t' \
    $'TODO/p3.md\tLow task\tdelta\tp3\topen\t2026-08-30T10:00:00+02:00\t' \
    $'TODO/p1.md\tHigh task\tgamma\tp1\topen\t2026-09-03T10:00:00+02:00\t' >> "$rows"

  output="$(
    cd "$fixture"
    PATH="$bin:$PATH" OBS_STATE="$state" OBS_ROWS="$rows" OBS_LOG="$log" \
      bash "$source_dir/scripts/focus.sh" candidates
  )"
  expected=$'P0\talpha\tCritical task\t2026-09-04T10:00:00+02:00\tTODO/p0.md\nP1\tgamma\tHigh task\t2026-09-03T10:00:00+02:00\tTODO/p1.md\nP2\tbeta\tMedium task\t2026-09-01T10:00:00+02:00\tTODO/p2.md\nP3\tdelta\tLow task\t2026-08-30T10:00:00+02:00\tTODO/p3.md'
  assert_equals "$output" "$expected"

  output="$(
    cd "$fixture"
    PATH="$bin:$PATH" OBS_STATE="$state" OBS_ROWS="$rows" OBS_LOG="$log" \
      bash "$source_dir/scripts/focus.sh" candidates p1
  )"
  assert_equals "$output" $'P1\tgamma\tHigh task\t2026-09-03T10:00:00+02:00\tTODO/p1.md'

  : > "$log"
  output="$(
    cd "$fixture"
    PATH="$bin:$PATH" OBS_STATE="$state" OBS_ROWS="$rows" OBS_LOG="$log" \
      bash "$source_dir/scripts/focus.sh" candidates p4 2>&1
  )" || status=$?
  [ "$status" -ne 0 ] || fail 'focus accepted p4'
  assert_contains "$output" "Use 'focus [p0|p1|p2|p3]'."
  [ ! -s "$log" ] || fail 'Invalid focus filter queried Obsidian'
}

test_focus_resolves_current_then_single_workplace_project() {
  local main="$test_root/focus-resolution/shared" workplace="$test_root/focus-resolution/workplace"
  local linked_one="$test_root/focus-resolution/workplace/linked one" linked_two="$test_root/focus-resolution/workplace/linked two"
  local single_workplace="$test_root/focus single/workplace with spaces" single="$test_root/focus single/workplace with spaces/ledger"
  local bin="$test_root/focus-resolution/bin" state="$test_root/focus-resolution/state"
  local rows="$test_root/focus-resolution/todos.tsv" log="$test_root/focus-resolution/obsidian.log" output
  create_repo "$main"
  mkdir -p "$workplace"
  git -C "$main" worktree add -q -b feature/one "$linked_one"
  git -C "$main" worktree add -q -b feature/two "$linked_two"
  create_fake_obsidian "$bin"
  write_fake_fzf "$bin" enter
  setup_obsidian_state "$state" "$rows"
  : > "$log"
  printf '%s\n' $'TODO/shared.md\tShared task\tshared\tp0\topen\t2026-09-04T10:00:00+02:00\t' >> "$rows"

  output="$(
    cd "$main"
    PATH="$bin:$PATH" DEV_WORKPLACE="$workplace" OBS_STATE="$state" OBS_ROWS="$rows" OBS_LOG="$log" \
      bash "$source_dir/scripts/focus.sh" select
  )"
  assert_equals "$output" "$(cd "$main" && pwd -P)"

  create_repo "$single"
  setup_obsidian_state "$state" "$rows"
  printf '%s\n' $'TODO/ledger.md\tLedger task\tledger\tp1\topen\t2026-09-03T10:00:00+02:00\t' >> "$rows"
  output="$(
    cd "$test_root"
    PATH="$bin:$PATH" DEV_WORKPLACE="$single_workplace" OBS_STATE="$state" OBS_ROWS="$rows" OBS_LOG="$log" \
      bash "$source_dir/scripts/focus.sh" select
  )"
  assert_equals "$output" "$(cd "$single" && pwd -P)"
}

test_focus_fails_closed_for_missing_and_ambiguous_projects() {
  local main="$test_root/focus-ambiguous/shared" workplace="$test_root/focus-ambiguous/workplace"
  local linked_one="$test_root/focus-ambiguous/workplace/linked one" linked_two="$test_root/focus-ambiguous/workplace/linked two"
  local bin="$test_root/focus-ambiguous/bin" state="$test_root/focus-ambiguous/state"
  local rows="$test_root/focus-ambiguous/todos.tsv" log="$test_root/focus-ambiguous/obsidian.log" output status=0
  create_repo "$main"
  mkdir -p "$workplace"
  git -C "$main" worktree add -q -b feature/one "$linked_one"
  git -C "$main" worktree add -q -b feature/two "$linked_two"
  create_fake_obsidian "$bin"
  write_fake_fzf "$bin" enter
  setup_obsidian_state "$state" "$rows"
  : > "$log"
  printf '%s\n' $'TODO/shared.md\tShared task\tshared\tp0\topen\t2026-09-04T10:00:00+02:00\t' >> "$rows"

  output="$(
    cd "$test_root"
    PATH="$bin:$PATH" DEV_WORKPLACE="$workplace" OBS_STATE="$state" OBS_ROWS="$rows" OBS_LOG="$log" \
      bash "$source_dir/scripts/focus.sh" select 2>&1
  )" || status=$?
  [ "$status" -ne 0 ] || fail 'focus guessed between ambiguous worktrees'
  assert_contains "$output" "Ambiguous project 'shared'"
  assert_contains "$output" "$(cd "$linked_one" && pwd -P)"
  assert_contains "$output" "$(cd "$linked_two" && pwd -P)"

  setup_obsidian_state "$state" "$rows"
  printf '%s\n' $'TODO/missing.md\tMissing task\tmissing\tp0\topen\t2026-09-04T10:00:00+02:00\t' >> "$rows"
  status=0
  output="$(
    cd "$test_root"
    PATH="$bin:$PATH" DEV_WORKPLACE="$workplace" OBS_STATE="$state" OBS_ROWS="$rows" OBS_LOG="$log" \
      bash "$source_dir/scripts/focus.sh" select 2>&1
  )" || status=$?
  [ "$status" -ne 0 ] || fail 'focus guessed a missing project'
  assert_contains "$output" "No repository named 'missing' found."
  assert_contains "$output" 'Ctrl-O'
}

test_focus_open_preview_cancel_and_empty_are_non_mutating() {
  local fixture="$test_root/focus-actions" bin="$test_root/focus-actions/bin"
  local state="$test_root/focus-actions/state" rows="$test_root/focus-actions/todos.tsv"
  local log="$test_root/focus-actions/obsidian.log" output
  mkdir -p "$fixture"
  create_fake_obsidian "$bin"
  setup_obsidian_state "$state" "$rows"
  printf '%s\n' $'TODO/path with spaces.md\tOpen me\tmissing\tp0\topen\t2026-09-04T10:00:00+02:00\t' >> "$rows"
  : > "$log"
  write_fake_fzf "$bin" ctrl-o

  output="$(
    cd "$fixture"
    PATH="$bin:$PATH" DEV_WORKPLACE="$fixture/no-workplace" DEV_OBSIDIAN_VAULT='Work Vault' \
      OBS_STATE="$state" OBS_ROWS="$rows" OBS_LOG="$log" bash "$source_dir/scripts/focus.sh" select
  )"
  assert_equals "$output" ''
  assert_contains "$(cat "$log")" $'vault=Work Vault\topen\tpath=TODO/path with spaces.md'
  ! grep -Eq '(^|\t)(create|append|daily:append|property:set|property:remove)(\t|$)' "$log" \
    || fail 'focus Ctrl-O mutated TODO metadata'

  : > "$log"
  output="$(
    PATH="$bin:$PATH" DEV_OBSIDIAN_VAULT='Work Vault' OBS_STATE="$state" OBS_ROWS="$rows" OBS_LOG="$log" \
      bash "$source_dir/scripts/focus.sh" preview 'TODO/path with spaces.md'
  )"
  assert_equals "$output" 'Preview: TODO/path with spaces.md'
  assert_contains "$(cat "$log")" $'vault=Work Vault\tread\tpath=TODO/path with spaces.md'

  write_fake_fzf "$bin" cancel
  output="$(
    cd "$fixture"
    PATH="$bin:$PATH" OBS_STATE="$state" OBS_ROWS="$rows" OBS_LOG="$log" \
      bash "$source_dir/scripts/focus.sh" select 2>&1
  )"
  assert_equals "$output" ''

  setup_obsidian_state "$state" "$rows"
  output="$(
    cd "$fixture"
    PATH="$bin:$PATH" OBS_STATE="$state" OBS_ROWS="$rows" OBS_LOG="$log" \
      bash "$source_dir/scripts/focus.sh" select 2>&1
  )"
  assert_equals "$output" 'No matching TODOs.'
}

test_shell_dirty_and_focus_change_the_parent_directory_safely() {
  local dirty_workplace="$test_root/shell-dirty/workplace" dirty_repo="$test_root/shell-dirty/workplace/repo with spaces"
  local focus_workplace="$test_root/shell-focus/workplace with spaces" focus_repo="$test_root/shell-focus/workplace with spaces/ledger"
  local bin="$test_root/shell-functions/bin" state="$test_root/shell-functions/state"
  local rows="$test_root/shell-functions/todos.tsv" log="$test_root/shell-functions/obsidian.log" output
  create_repo "$dirty_repo"
  printf 'dirty\n' > "$dirty_repo/change.txt"
  create_repo "$focus_repo"
  create_fake_obsidian "$bin"
  write_fake_fzf "$bin" enter
  setup_obsidian_state "$state" "$rows"
  : > "$log"
  printf '%s\n' $'TODO/ledger.md\tLedger task\tledger\tp1\topen\t2026-09-03T10:00:00+02:00\t' >> "$rows"

  output="$(
    cd "$test_root"
    PATH="$bin:$PATH" DEV_HARNESS_HOME="$source_dir" DEV_WORKPLACE="$dirty_workplace" \
      bash -c 'source "$DEV_HARNESS_HOME/shell/dev-harness.bash"; dirty; pwd -P'
  )"
  assert_equals "$output" "$(cd "$dirty_repo" && pwd -P)"

  output="$(
    cd "$test_root"
    PATH="$bin:$PATH" DEV_HARNESS_HOME="$source_dir" DEV_WORKPLACE="$focus_workplace" \
      OBS_STATE="$state" OBS_ROWS="$rows" OBS_LOG="$log" \
      bash -c 'source "$DEV_HARNESS_HOME/shell/dev-harness.bash"; focus p1; pwd -P'
  )"
  assert_equals "$output" "$(cd "$focus_repo" && pwd -P)"
}

test_shell_picker_empty_results_do_not_become_directories() {
  local workplace="$test_root/shell-empty/workplace" clean="$test_root/shell-empty/workplace/clean"
  local bin="$test_root/shell-empty/bin" state="$test_root/shell-empty/state"
  local rows="$test_root/shell-empty/todos.tsv" log="$test_root/shell-empty/obsidian.log" output before
  create_repo "$clean"
  create_fake_obsidian "$bin"
  setup_obsidian_state "$state" "$rows"
  write_fake_fzf "$bin" cancel
  : > "$log"
  before="$(cd "$test_root" && pwd -P)"

  output="$(
    cd "$test_root"
    PATH="$bin:$PATH" DEV_HARNESS_HOME="$source_dir" DEV_WORKPLACE="$workplace" \
      OBS_STATE="$state" OBS_ROWS="$rows" OBS_LOG="$log" \
      bash -c 'source "$DEV_HARNESS_HOME/shell/dev-harness.bash"; dirty; focus; pwd -P' 2>&1
  )"
  assert_contains "$output" 'No dirty repositories.'
  assert_contains "$output" 'No matching TODOs.'
  assert_contains "$output" "$before"
  assert_equals "$(printf '%s\n' "$output" | tail -n 1)" "$before"
}

test_shell_workflow_functions_forward_quoted_arguments() {
  local harness="$test_root/shell-forward/harness" log="$test_root/shell-forward/arguments.log" output
  mkdir -p "$harness/scripts"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'printf "argc=%s" "$#" >> "$WORKFLOW_LOG"' \
    'for argument in "$@"; do printf "|%s" "$argument" >> "$WORKFLOW_LOG"; done' \
    'printf "\n" >> "$WORKFLOW_LOG"' > "$harness/scripts/workflow.sh"
  chmod +x "$harness/scripts/workflow.sh"
  : > "$log"

  output="$(
    DEV_HARNESS_HOME="$harness" WORKFLOW_LOG="$log" SOURCE_SHELL="$source_dir/shell/dev-harness.bash" bash -c \
      'source "$SOURCE_SHELL"; why; handoff --copy; standup --day'
  )"
  assert_equals "$output" ''
  assert_equals "$(cat "$log")" $'argc=1|why\nargc=2|handoff|--copy\nargc=2|standup|--day'
}

test_taskfile_exposes_workflow_tasks_aliases_and_cli_input() {
  local harness="$test_root/task-integration/harness" log="$test_root/task-integration/task.log" work="$test_root/task-integration/work dir"
  local list_output
  mkdir -p "$harness/scripts" "$work"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'printf "workflow|%s|%s|%s\n" "$1" "${DEV_HARNESS_INPUT:-}" "$(pwd -P)" >> "$TASK_LOG"' > "$harness/scripts/workflow.sh"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'printf "dirty|%s|%s\n" "$1" "$(pwd -P)" >> "$TASK_LOG"' > "$harness/scripts/dirty.sh"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'printf "focus|%s|%s|%s\n" "$1" "${DEV_HARNESS_INPUT:-}" "$(pwd -P)" >> "$TASK_LOG"' > "$harness/scripts/focus.sh"
  chmod +x "$harness/scripts/"*.sh
  : > "$log"

  (
    cd "$work"
    DEV_HARNESS_HOME="$harness" TASK_LOG="$log" task --taskfile "$source_dir/Taskfile.global.yml" dirty
    DEV_HARNESS_HOME="$harness" TASK_LOG="$log" task --taskfile "$source_dir/Taskfile.global.yml" y
    DEV_HARNESS_HOME="$harness" TASK_LOG="$log" task --taskfile "$source_dir/Taskfile.global.yml" hf -- --copy
    DEV_HARNESS_HOME="$harness" TASK_LOG="$log" task --taskfile "$source_dir/Taskfile.global.yml" stp -- --day
    DEV_HARNESS_HOME="$harness" TASK_LOG="$log" task --taskfile "$source_dir/Taskfile.global.yml" foc -- p1
  )

  assert_contains "$(cat "$log")" "dirty|manage|$(cd "$work" && pwd -P)"
  assert_contains "$(cat "$log")" "workflow|why||$(cd "$work" && pwd -P)"
  assert_contains "$(cat "$log")" "workflow|handoff|--copy|$(cd "$work" && pwd -P)"
  assert_contains "$(cat "$log")" "workflow|standup|--day|$(cd "$work" && pwd -P)"
  assert_contains "$(cat "$log")" "focus|manage|p1|$(cd "$work" && pwd -P)"

  list_output="$(task --taskfile "$source_dir/Taskfile.global.yml" --list)"
  assert_contains "$list_output" 'dirty:'
  assert_contains "$list_output" 'why:'
  assert_contains "$list_output" 'handoff:'
  assert_contains "$list_output" 'standup:'
  assert_contains "$list_output" 'focus:'
}

test_palette_contextually_exposes_workflow_utilities() {
  local fixture="$test_root/palette-context" repo="$test_root/palette-context/repo"
  local workplace="$test_root/palette-context/workplace" bin="$test_root/palette-context/bin"
  local palette_log="$test_root/palette-context/palette.tsv" minimal_path output
  mkdir -p "$fixture" "$workplace" "$bin"
  create_repo "$repo"
  printf '%s\n' '#!/usr/bin/env bash' 'cat > "$PALETTE_LOG"' 'exit 130' > "$bin/fzf"
  printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$bin/task"
  chmod +x "$bin/fzf" "$bin/task"
  minimal_path="$bin:$(dirname "$(command -v git)"):/usr/bin:/bin"

  output="$(
    cd "$test_root"
    PATH="$minimal_path" DEV_WORKPLACE="$workplace" PALETTE_LOG="$palette_log" \
      bash "$source_dir/scripts/palette.sh" select
  )"
  assert_equals "$output" ''
  assert_contains "$(cat "$palette_log")" $'dirty\t'
  assert_contains "$(cat "$palette_log")" 'dirty brudne zmiany'
  ! grep -Eq '^(why|handoff|standup|focus)\t' "$palette_log" || fail 'Repository-only palette rows leaked outside Git'

  output="$(
    cd "$repo"
    PATH="$minimal_path" DEV_WORKPLACE= PALETTE_LOG="$palette_log" \
      bash "$source_dir/scripts/palette.sh" select
  )"
  assert_equals "$output" ''
  assert_contains "$(cat "$palette_log")" $'dirty\t'
  assert_contains "$(cat "$palette_log")" $'why\t'
  assert_contains "$(cat "$palette_log")" $'handoff\t'
  assert_contains "$(cat "$palette_log")" $'standup\t'
  ! grep -Eq '^focus\t' "$palette_log" || fail 'focus appeared without Obsidian'

  create_fake_obsidian "$bin"
  output="$(
    cd "$test_root"
    PATH="$minimal_path" DEV_WORKPLACE= PALETTE_LOG="$palette_log" \
      bash "$source_dir/scripts/palette.sh" select
  )"
  assert_equals "$output" ''
  assert_contains "$(cat "$palette_log")" $'focus\t'
  assert_contains "$(cat "$palette_log")" 'focus priorytet skupienie'
}

test_help_lists_every_workflow_fast_path_and_task_alias() {
  local help_output aliases_output
  help_output="$(bash "$source_dir/scripts/help.sh" help)"
  aliases_output="$(bash "$source_dir/scripts/help.sh" aliases)"
  for command in gr dirty why handoff standup focus mkcd; do
    assert_contains "$help_output" "$command"
    assert_contains "$aliases_output" "$command"
  done
  assert_contains "$help_output" 'none of these commands starts AI'
  assert_contains "$aliases_output" 'gtask y'
  assert_contains "$aliases_output" 'gtask hf'
  assert_contains "$aliases_output" 'gtask stp'
  assert_contains "$aliases_output" 'gtask foc'
  assert_contains "$aliases_output" '..'
  assert_contains "$aliases_output" 'cd ../..'
  assert_contains "$aliases_output" 'll'
  assert_contains "$aliases_output" 'ls -lah'
  assert_contains "$aliases_output" 'la'
  assert_contains "$aliases_output" 'ls -A'
}

test_console_navigation_aliases_change_directory() {
  local base="$test_root/console nav/root" output
  mkdir -p "$base/one/two/three"

  output="$(
    NAV_ROOT="$(cd "$base" && pwd -P)" \
    NAV_ONE="$(cd "$base/one" && pwd -P)" \
    NAV_TWO="$(cd "$base/one/two" && pwd -P)" \
    NAV_THREE="$(cd "$base/one/two/three" && pwd -P)" \
    DEV_HARNESS_HOME="$source_dir" bash --noprofile --norc -c '
      shopt -s expand_aliases
      source "$DEV_HARNESS_HOME/shell/dev-harness.bash"
      cd "$NAV_THREE"
      ..
      printf "up1=%s\n" "$(pwd -P)"
      cd "$NAV_THREE"
      ...
      printf "up2=%s\n" "$(pwd -P)"
      cd "$NAV_THREE"
      ....
      printf "up3=%s\n" "$(pwd -P)"
      cd "$NAV_TWO"
      cd "$NAV_THREE"
      - >/dev/null
      printf "back=%s\n" "$(pwd -P)"
      printf "ll=%s\n" "$(alias ll)"
      printf "la=%s\n" "$(alias la)"
    '
  )"

  assert_contains "$output" "up1=$(cd "$base/one/two" && pwd -P)"
  assert_contains "$output" "up2=$(cd "$base/one" && pwd -P)"
  assert_contains "$output" "up3=$(cd "$base" && pwd -P)"
  assert_contains "$output" "back=$(cd "$base/one/two" && pwd -P)"
  assert_contains "$output" "ll='ls -lah'"
  assert_contains "$output" "la='ls -A'"
}

test_mkcd_creates_and_enters_directory_with_spaces() {
  local base="$test_root/mkcd nav/parent" target output
  mkdir -p "$base"
  target="$(cd "$base" && pwd -P)/new dir/nested"

  output="$(
    cd "$base"
    DEV_HARNESS_HOME="$source_dir" bash --noprofile --norc -c '
      source "$DEV_HARNESS_HOME/shell/dev-harness.bash"
      mkcd "new dir/nested"
      printf "cwd=%s\n" "$(pwd -P)"
    '
  )"
  assert_contains "$output" "cwd=$target"
  [ -d "$target" ] || fail "mkcd did not create $target"

  output="$(
    cd "$base"
    DEV_HARNESS_HOME="$source_dir" bash --noprofile --norc -c '
      source "$DEV_HARNESS_HOME/shell/dev-harness.bash"
      if mkcd; then printf "status=0\n"; else printf "status=%s\n" "$?"; fi
      if mkcd a b; then printf "multi=0\n"; else printf "multi=%s\n" "$?"; fi
      pwd -P
    ' 2>&1
  )"
  assert_contains "$output" 'usage: mkcd DIR'
  assert_contains "$output" 'status=1'
  assert_contains "$output" 'multi=1'
  assert_contains "$output" "$(cd "$base" && pwd -P)"
}

test_gr_changes_to_repository_root_with_spaces
printf 'PASS: gr changes to a repository root containing spaces\n'
test_gr_fails_outside_git_without_changing_directory
printf 'PASS: gr fails outside Git without changing directory\n'
test_dirty_discovers_only_unique_dirty_worktrees_with_exact_counts
printf 'PASS: dirty discovers unique dirty worktrees with exact counts\n'
test_dirty_select_returns_a_path_with_spaces_and_opens_exact_path
printf 'PASS: dirty selection preserves paths and editor channel safety\n'
test_dirty_handles_preview_cancel_clean_and_missing_workplace
printf 'PASS: dirty handles preview, cancellation, clean results, and missing workplace\n'
test_why_delegates_to_resume_preview_without_ai
printf 'PASS: why delegates to resume preview without invoking AI\n'
test_why_fails_outside_git
printf 'PASS: why fails outside Git\n'
test_handoff_prints_and_copies_the_same_secret_filtered_context
printf 'PASS: handoff prints and copies identical secret-filtered context\n'
test_handoff_rejects_invalid_options_before_side_effects
printf 'PASS: handoff rejects invalid options before side effects\n'
test_standup_renders_recent_safe_activity_and_sorted_project_todos
printf 'PASS: standup renders recent safe activity and sorted project TODOs\n'
test_standup_handles_empty_and_unavailable_obsidian_sections
printf 'PASS: standup handles empty sections and unavailable Obsidian\n'
test_standup_copy_and_day_use_the_exact_report
printf 'PASS: standup copy and Daily actions preserve exact report content\n'
test_standup_rejects_invalid_actions_before_side_effects
printf 'PASS: standup rejects invalid actions before side effects\n'
test_focus_candidates_preserve_priority_order_and_filter
printf 'PASS: focus candidates preserve priority order and filtering\n'
test_focus_resolves_current_then_single_workplace_project
printf 'PASS: focus resolves the current project before a single workplace match\n'
test_focus_fails_closed_for_missing_and_ambiguous_projects
printf 'PASS: focus fails closed for missing and ambiguous projects\n'
test_focus_open_preview_cancel_and_empty_are_non_mutating
printf 'PASS: focus open, preview, cancellation, and empty flows are non-mutating\n'
test_shell_dirty_and_focus_change_the_parent_directory_safely
printf 'PASS: shell dirty and focus change the parent directory safely\n'
test_shell_picker_empty_results_do_not_become_directories
printf 'PASS: shell picker messages never become directory paths\n'
test_shell_workflow_functions_forward_quoted_arguments
printf 'PASS: shell workflow functions forward quoted arguments\n'
test_taskfile_exposes_workflow_tasks_aliases_and_cli_input
printf 'PASS: Taskfile exposes workflow tasks, aliases, and CLI input\n'
test_palette_contextually_exposes_workflow_utilities
printf 'PASS: palette exposes workflow utilities contextually\n'
test_help_lists_every_workflow_fast_path_and_task_alias
printf 'PASS: help lists workflow fast paths and Task aliases\n'
test_console_navigation_aliases_change_directory
printf 'PASS: console navigation aliases change directory\n'
test_mkcd_creates_and_enters_directory_with_spaces
printf 'PASS: mkcd creates and enters a directory with spaces\n'
