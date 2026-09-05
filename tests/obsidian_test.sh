#!/usr/bin/env bash
set -euo pipefail

source_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/dev-harness-obsidian-test.XXXXXX")"

cleanup() {
  case "$test_root" in
    "${TMPDIR:-/tmp}"/dev-harness-obsidian-test.*) rm -rf -- "$test_root" ;;
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
  [[ "$haystack" == *"$needle"* ]] || fail "Expected value to contain: $needle"
}

assert_equals() {
  local actual="$1" expected="$2"
  [ "$actual" = "$expected" ] || fail "Expected '$expected', got '$actual'"
}

assert_logged() {
  local log="$1" invocation="$2" expected
  printf -v expected '%s\t' "$invocation"
  grep -Fqx "$expected" "$log" || fail "Expected Obsidian invocation: $invocation"
}

assert_no_mutations() {
  local log="$1" mutations
  mutations="$(grep -E '^(create|append|daily:append|property:set|property:remove)' "$log" || true)"
  [ -z "$mutations" ] || fail "Expected a read-only operation, got: $mutations"
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

create_date_wrapper() {
  local bin="$1" real_date
  real_date="$(command -v date)"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'case "$1" in' \
    "  '+%Y-%m-%d-%H%M') printf '%s\\n' '2026-09-02-1234' ;;" \
    "  '+%Y-%m-%dT%H:%M:%S') printf '%s\\n' '2026-09-02T12:34:56' ;;" \
    "  '+%z') printf '%s\\n' '+0200' ;;" \
    "  '+%H:%M') printf '%s\\n' '12:34' ;;" \
    "  '+%G-W%V') printf '%s\\n' '2026-W36' ;;" \
    "  '+%Y/%m/%Y%m%d-%H%M%S') printf '%s\\n' '2026/09/20260902-123456' ;;" \
    "  *) exec \"$real_date\" \"\$@\" ;;" \
    'esac' > "$bin/date"
  chmod +x "$bin/date"
}

create_fake_obsidian() {
  local bin="$1"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    ': "${OBS_STATE:?}"' \
    ': "${OBS_LOG:?}"' \
    '{ for argument in "$@"; do printf "%s\\t" "$argument"; done; printf "\\n"; } >> "$OBS_LOG"' \
    'value_for() {' \
    '  local key="$1" argument' \
    '  shift' \
    '  for argument in "$@"; do' \
    '    case "$argument" in "$key"=*) printf "%s\\n" "${argument#*=}"; return 0 ;; esac' \
    '  done' \
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
    '  create)' \
    '    path="$(value_for path "$@")"' \
    '    mkdir -p "$(dirname "$OBS_STATE/files/$path")"' \
    '    : > "$OBS_STATE/files/$path"' \
    '    ;;' \
    '  daily)' \
    '    mkdir -p "$OBS_STATE/files/Daily"' \
    '    : > "$OBS_STATE/files/Daily/2026-09-02.md"' \
    '    exit 0' \
    '    ;;' \
    '  daily:append)' \
    '    content="$(value_for content "$@")"' \
    '    mkdir -p "$OBS_STATE/files/Daily"' \
    '    printf "%s" "$content" > "$OBS_STATE/daily-append.txt"' \
    '    : > "$OBS_STATE/files/Daily/2026-09-02.md"' \
    '    exit 0' \
    '    ;;' \
    '  property:set|property:remove|append|open)' \
    '    exit 0' \
    '    ;;' \
    '  base:query)' \
    '    view="$(value_for view "$@")"' \
    '    printf "Path\\tTitle\\tProject\\tPriority\\tStatus\\tCreated\\tCompleted\\n"' \
    '    if [ "$view" = Done ]; then' \
    '      printf "TODO/2026/09/20260902-123456-fix-build-pipeline.md\\tFix build pipeline\\ttracker\\tp1\\tdone\\t2026-09-02T12:34:56+02:00\\t2026-09-02T13:00:00+02:00\\n"' \
    '    else' \
    '      printf "TODO/2026/09/20260902-123456-fix-build-pipeline.md\\tFix build pipeline\\ttracker\\tp1\\topen\\t2026-09-02T12:34:56+02:00\\t\\n"' \
    '    fi' \
    '    ;;' \
    '  *) printf "Unexpected Obsidian command: %s\\n" "$command" >&2; exit 64 ;;' \
    'esac' > "$bin/obsidian.com"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'IFS= read -r selection || exit 1' \
    'printf "%s\\n" "$selection"' > "$bin/fzf"
  chmod +x "$bin/obsidian.com" "$bin/fzf"
}

setup_fixture() {
  local fixture="$1" repo="$2" bin="$3" state="$4" log="$5"
  mkdir -p "$bin" "$state/files"
  create_repo "$repo"
  : > "$log"
  create_date_wrapper "$bin"
  create_fake_obsidian "$bin"
}

run_obsidian() {
  local repo="$1" bin="$2" state="$3" log="$4" mode="$5"
  shift 5
  (
    cd "$repo"
    PATH="$bin:$PATH" OBS_STATE="$state" OBS_LOG="$log" \
      bash "$source_dir/scripts/obsidian.sh" "$mode" "$@"
  )
}

test_note_is_created_under_notes_with_canonical_properties() {
  local fixture repo bin state log path
  fixture="$test_root/note"
  repo="$fixture/ledger"
  bin="$fixture/bin"
  state="$fixture/state"
  log="$fixture/obsidian.log"
  path='Notes/2026-09-02-1234 Architecture Decision.md'
  setup_fixture "$fixture" "$repo" "$bin" "$state" "$log"

  run_obsidian "$repo" "$bin" "$state" "$log" note 'Architecture Decision' >/dev/null

  assert_logged "$log" "create	path=$path	content=# Architecture Decision"
  assert_logged "$log" "property:set	name=type	value=note	type=text	path=$path"
  assert_logged "$log" "property:set	name=created	value=2026-09-02T12:34:56+02:00	type=datetime	path=$path"
  assert_logged "$log" "property:set	name=project	value=ledger	type=text	path=$path"
  assert_logged "$log" "property:set	name=tags	value=note,project/ledger	type=list	path=$path"
  assert_logged "$log" "open	path=$path"
}

test_daily_and_weekly_use_their_root_flows() {
  local fixture repo bin state log weekly
  fixture="$test_root/calendar"
  repo="$fixture/ledger"
  bin="$fixture/bin"
  state="$fixture/state"
  log="$fixture/obsidian.log"
  weekly='Weekly/2026-W36.md'
  setup_fixture "$fixture" "$repo" "$bin" "$state" "$log"

  run_obsidian "$repo" "$bin" "$state" "$log" day >/dev/null
  assert_logged "$log" 'daily'
  [ -f "$state/files/Daily/2026-09-02.md" ] || fail 'Daily flow did not select a note under Daily/'
  run_obsidian "$repo" "$bin" "$state" "$log" day 'Standup' >/dev/null
  assert_contains "$(cat "$log")" $'daily:append\tcontent=- 12:34 Standup'
  [ -f "$state/files/Daily/2026-09-02.md" ] || fail 'Daily append did not target Daily/'
  run_obsidian "$repo" "$bin" "$state" "$log" week 'Plan release' >/dev/null
  assert_logged "$log" "create	path=$weekly	content=# 2026-W36"
  assert_logged "$log" "property:set	name=type	value=weekly	type=text	path=$weekly"
  assert_logged "$log" "open	path=$weekly"
}

test_todo_uses_timestamped_path_and_canonical_metadata() {
  local fixture repo bin state log path
  fixture="$test_root/todo"
  repo="$fixture/tracker"
  bin="$fixture/bin"
  state="$fixture/state"
  log="$fixture/obsidian.log"
  path='TODO/2026/09/20260902-123456-fix-build-pipeline.md'
  setup_fixture "$fixture" "$repo" "$bin" "$state" "$log"

  run_obsidian "$repo" "$bin" "$state" "$log" todo p1 'Fix build pipeline' >/dev/null

  assert_logged "$log" "create	path=$path	content=# Fix build pipeline"
  assert_logged "$log" "property:set	name=status	value=open	type=text	path=$path"
  assert_logged "$log" "property:set	name=priority	value=p1	type=text	path=$path"
  assert_logged "$log" "property:set	name=project	value=tracker	type=text	path=$path"
  assert_logged "$log" "property:set	name=created	value=2026-09-02T12:34:56+02:00	type=datetime	path=$path"
}

test_listing_todos_is_read_only() {
  local fixture repo bin state log output
  fixture="$test_root/list"
  repo="$fixture/reader"
  bin="$fixture/bin"
  state="$fixture/state"
  log="$fixture/obsidian.log"
  setup_fixture "$fixture" "$repo" "$bin" "$state" "$log"
  mkdir -p "$state/files/TODO"
  : > "$state/files/TODO/TODO.base"
  : > "$log"

  output="$(run_obsidian "$repo" "$bin" "$state" "$log" todos open)"

  assert_contains "$output" 'Fix build pipeline'
  assert_logged "$log" 'file	path=TODO/TODO.base'
  assert_logged "$log" 'base:query	path=TODO/TODO.base	view=Open	format=tsv'
  assert_no_mutations "$log"
}

test_wildcard_like_todo_filter_is_not_expanded_as_a_filename() {
  local fixture repo bin state log output status=0
  fixture="$test_root/wildcard-filter"
  repo="$fixture/reader"
  bin="$fixture/bin"
  state="$fixture/state"
  log="$fixture/obsidian.log"
  setup_fixture "$fixture" "$repo" "$bin" "$state" "$log"
  printf 'filename that resembles a valid filter\n' > "$repo/p1"
  : > "$log"

  output="$(run_obsidian "$repo" "$bin" "$state" "$log" todos 'p*' 2>&1)" || status=$?

  [ "$status" -ne 0 ] || fail 'Wildcard-like TODO filter was expanded into the p1 filename'
  assert_contains "$output" "Use 'gtask todos -- [open|done] [p0..p3]'."
  assert_no_mutations "$log"
}

test_completion_and_reopen_only_change_status_and_completed() {
  local fixture repo bin state log path mutations expected
  fixture="$test_root/transitions"
  repo="$fixture/tracker"
  bin="$fixture/bin"
  state="$fixture/state"
  log="$fixture/obsidian.log"
  path='TODO/2026/09/20260902-123456-fix-build-pipeline.md'
  setup_fixture "$fixture" "$repo" "$bin" "$state" "$log"
  mkdir -p "$state/files/TODO"
  : > "$state/files/TODO/TODO.base"
  : > "$log"

  run_obsidian "$repo" "$bin" "$state" "$log" done >/dev/null
  mutations="$(grep -E '^(create|append|daily:append|property:set|property:remove)' "$log" || true)"
  expected="$(printf 'property:set\tname=status\tvalue=done\ttype=text\tpath=%s\t\nproperty:set\tname=completed\tvalue=2026-09-02T12:34:56+02:00\ttype=datetime\tpath=%s\t' "$path" "$path")"
  assert_equals "$mutations" "$expected"

  : > "$log"
  run_obsidian "$repo" "$bin" "$state" "$log" reopen >/dev/null
  mutations="$(grep -E '^(create|append|daily:append|property:set|property:remove)' "$log" || true)"
  expected="$(printf 'property:set\tname=status\tvalue=open\ttype=text\tpath=%s\t\nproperty:remove\tname=completed\tpath=%s\t' "$path" "$path")"
  assert_equals "$mutations" "$expected"
}

test_todos_tsv_has_stable_columns_order_and_filters() {
  local fixture repo bin state log all_rows project_rows expected
  fixture="$test_root/todos-tsv"
  repo="$fixture/tracker"
  bin="$fixture/bin"
  state="$fixture/state"
  log="$fixture/obsidian.log"
  setup_fixture "$fixture" "$repo" "$bin" "$state" "$log"
  mkdir -p "$state/files/TODO"
  : > "$state/files/TODO/TODO.base"
  : > "$log"

  all_rows="$(run_obsidian "$repo" "$bin" "$state" "$log" todos-tsv all open)"
  project_rows="$(run_obsidian "$repo" "$bin" "$state" "$log" todos-tsv project open p1)"
  expected=$'TODO/2026/09/20260902-123456-fix-build-pipeline.md\tFix build pipeline\ttracker\tp1\topen\t2026-09-02T12:34:56+02:00\t'

  assert_equals "$all_rows" "$expected"
  assert_equals "$project_rows" "$expected"
  assert_no_mutations "$log"
}

test_todos_tsv_rejects_invalid_contracts() {
  local fixture repo bin state log arguments output status
  fixture="$test_root/todos-tsv-invalid"
  repo="$fixture/tracker"
  bin="$fixture/bin"
  state="$fixture/state"
  log="$fixture/obsidian.log"
  setup_fixture "$fixture" "$repo" "$bin" "$state" "$log"

  for arguments in 'invalid open' 'all pending' 'all open p9' 'all open p1 extra'; do
    : > "$log"
    status=0
    output="$(
      cd "$repo"
      PATH="$bin:$PATH" OBS_STATE="$state" OBS_LOG="$log" \
        bash "$source_dir/scripts/obsidian.sh" todos-tsv $arguments 2>&1
    )" || status=$?
    [ "$status" -ne 0 ] || fail "Invalid todos-tsv contract succeeded: $arguments"
    assert_contains "$output" "Use 'obsidian.sh todos-tsv <project|all> <open|done> [p0|p1|p2|p3]'."
    assert_no_mutations "$log"
  done
}

test_day_append_preserves_exact_markdown_and_rejects_invalid_arity() {
  local fixture repo bin state log report output status
  fixture="$test_root/day-append"
  repo="$fixture/tracker"
  bin="$fixture/bin"
  state="$fixture/state"
  log="$fixture/obsidian.log"
  report=$'## tracker · main\n\n### Current changes\n- src/App.java'
  setup_fixture "$fixture" "$repo" "$bin" "$state" "$log"

  run_obsidian "$repo" "$bin" "$state" "$log" day-append "$report" >/dev/null
  assert_equals "$(cat "$state/daily-append.txt")" "$report"

  : > "$log"
  status=0
  output="$(run_obsidian "$repo" "$bin" "$state" "$log" day-append 2>&1)" || status=$?
  [ "$status" -ne 0 ] || fail 'day-append accepted an empty report'
  assert_contains "$output" "Use 'obsidian.sh day-append <markdown>'."
  [ ! -s "$log" ] || fail 'Invalid day-append invoked Obsidian'

  : > "$log"
  status=0
  output="$(run_obsidian "$repo" "$bin" "$state" "$log" day-append one two 2>&1)" || status=$?
  [ "$status" -ne 0 ] || fail 'day-append accepted more than one report argument'
  assert_contains "$output" "Use 'obsidian.sh day-append <markdown>'."
  [ ! -s "$log" ] || fail 'Invalid day-append invoked Obsidian'
}

test_note_is_created_under_notes_with_canonical_properties
printf 'PASS: normal notes use Notes with canonical metadata\n'
test_daily_and_weekly_use_their_root_flows
printf 'PASS: daily and weekly notes use their root flows\n'
test_todo_uses_timestamped_path_and_canonical_metadata
printf 'PASS: TODO notes use timestamped paths and canonical metadata\n'
test_listing_todos_is_read_only
printf 'PASS: TODO listing is read-only\n'
test_wildcard_like_todo_filter_is_not_expanded_as_a_filename
printf 'PASS: wildcard-like TODO filters are handled literally\n'
test_completion_and_reopen_only_change_status_and_completed
printf 'PASS: TODO completion and reopen only mutate lifecycle metadata\n'
test_todos_tsv_has_stable_columns_order_and_filters
printf 'PASS: internal TODO TSV API preserves its stable contract\n'
test_todos_tsv_rejects_invalid_contracts
printf 'PASS: internal TODO TSV API rejects invalid contracts\n'
test_day_append_preserves_exact_markdown_and_rejects_invalid_arity
printf 'PASS: internal Daily append preserves exact Markdown\n'
