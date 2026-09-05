# Workplace Search Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace repo-scoped `gtask search` with live ripgrep across immediate `DEV_WORKPLACE` children, then add `gtask index` / `gtask semantic` on required local `grepai`.

**Architecture:** Shared `workplace_root` / `workplace_project_dirs` in `scripts/lib.sh`. New `scripts/search.sh` owns modes `reload`, `live`, `semantic`, and `index`. `open.sh` loses search. Results stay workplace-relative so `file:line:column` parsing never hits a Windows drive letter. Ctrl-A/R call `analyze-files` with absolute paths, never `changes.sh`.

**Tech Stack:** Bash, Task, fzf, ripgrep, grepai (slice 2), Ollama as grepai’s default embedder (not installed by the harness).

## Global Constraints

- Die copy for a missing workplace matches `cproj`: `Set DEV_WORKPLACE in ~/.config/dev-harness/config.env.` / `DEV_WORKPLACE does not exist: $workplace` / `No project directories found in $workplace`
- Corpus: `find -mindepth 1 -maxdepth 1 -type d` only. No `git worktree list`. Current repo does not narrow.
- `query="${DEV_HARNESS_INPUT:-$*}"` (Taskfile sets `DEV_HARNESS_INPUT` from `CLI_ARGS`)
- `rg --path-separator` matches `open.sh` (`/` normally, `//` on MINGW/MSYS/CYGWIN)
- Reload: `${#query} < 2` → empty stdout, exit 0
- Slice 1 never requires or mentions `grepai`. Slice 2 adds `grepai` to installer/doctor.
- Installer never installs third-party binaries (`grepai`, Ollama, models)
- Tests: no real Ollama, no interactive fzf; fake bins on PATH. Host `rg` may exist; tests that assert “rg missing” must use a PATH without it.
- `need` messages stay `Missing command: $1`

---

## File map

| File | Role |
|---|---|
| Create `scripts/search.sh` | `reload` / `live` / `semantic` / `index` |
| Create `tests/search_test.sh` | Enumerator, reload, live open, index, semantic |
| Modify `scripts/lib.sh` | `workplace_root`, `workplace_project_dirs` |
| Modify `scripts/project.sh` | Use the enumerator |
| Modify `scripts/open.sh` | Delete mode `search` |
| Modify `scripts/preview.sh` | Search preview from workplace; hide sensitive paths |
| Modify `scripts/palette.sh` | `search` (then `semantic`/`index`) when workplace exists, not Git-only |
| Modify `Taskfile.global.yml` | Point `search` at `search.sh live`; add `semantic` / `index` in slice 2 |
| Modify `scripts/help.sh` | Find section + aliases |
| Modify `scripts/doctor.sh` | `rg` required (slice 1); `grepai` required + workplace index checks (slice 2) |
| Modify `install.sh` | Required-tool lists |
| Modify `tests/run.sh` | Register `search_test.sh` |
| Modify `tests/release_test.sh` | Archive entry `scripts/search.sh` |
| Modify `tests/review_fixes_test.sh` | Installer/doctor required-tool tests |
| Modify `tests/install_test.sh` | Fake `grepai` on PATH in slice 2 |
| Modify `.github/workflows/ci.yml` | Install ripgrep (slice 1) |
| Modify README, TUTORIAL, PRD, CHANGELOG, `docs/site/*`, demo | Copy + requirements |

---

### Task 1: Workplace enumerator

**Files:**
- Modify: `scripts/lib.sh` (append after `to_shell_path`)
- Modify: `scripts/project.sh` (replace inline `DEV_WORKPLACE` checks + `find`)
- Create: `tests/search_test.sh`
- Modify: `tests/run.sh` (add `search_test.sh` to the suite list after `resume_test.sh`)

**Interfaces:**
- Consumes: `to_shell_path`, `die` from `lib.sh`
- Produces:
  - `workplace_root` — prints canonical workplace path on stdout; dies if unset or not a directory
  - `workplace_project_dirs` — prints one absolute/shell path per line, `LC_ALL=C sort`; dies if empty; no Git, no worktrees

- [ ] **Step 1: Write the failing enumerator tests**

Create `tests/search_test.sh` with the same header/helpers as `tests/review_fixes_test.sh` (`set -euo pipefail`, `source_dir`, `test_root`, `cleanup`, `fail`, `assert_contains`, `assert_equals`, `create_repo`). Add:

```bash
create_command_wrapper() {
  local destination="$1" command_name="$2" resolved
  resolved="$(command -v "$command_name")"
  printf '#!/bin/sh\nexec "%s" "$@"\n' "$resolved" > "$destination/$command_name"
  chmod +x "$destination/$command_name"
}

test_workplace_root_requires_config() {
  local output status=0
  output="$(DEV_WORKPLACE= bash -c '. "'"$source_dir"'/scripts/lib.sh"; workplace_root' 2>&1)" || status=$?
  [ "$status" -ne 0 ] || fail 'workplace_root accepted an empty DEV_WORKPLACE'
  assert_contains "$output" 'Set DEV_WORKPLACE in ~/.config/dev-harness/config.env.'
}

test_workplace_root_requires_a_directory() {
  local missing="$test_root/missing-workplace" output status=0
  output="$(DEV_WORKPLACE="$missing" bash -c '. "'"$source_dir"'/scripts/lib.sh"; workplace_root' 2>&1)" || status=$?
  [ "$status" -ne 0 ] || fail 'workplace_root accepted a missing directory'
  assert_contains "$output" "DEV_WORKPLACE does not exist: $missing"
}

test_workplace_project_dirs_lists_sorted_children_including_spaces() {
  local workplace="$test_root/function action place" output
  mkdir -p "$workplace/zeta" "$workplace/alpha project"
  printf 'skip\n' > "$workplace/file.txt"
  output="$(DEV_WORKPLACE="$workplace" bash -c '. "'"$source_dir"'/scripts/lib.sh"; workplace_project_dirs')"
  assert_equals "$output" "$(printf '%s\n' "$(cd "$workplace/alpha project" && pwd -P)" "$(cd "$workplace/zeta" && pwd -P)")"
}

test_workplace_project_dirs_dies_when_empty() {
  local workplace="$test_root/empty-workplace" output status=0
  mkdir -p "$workplace"
  output="$(DEV_WORKPLACE="$workplace" bash -c '. "'"$source_dir"'/scripts/lib.sh"; workplace_project_dirs' 2>&1)" || status=$?
  [ "$status" -ne 0 ] || fail 'workplace_project_dirs accepted an empty workplace'
  assert_contains "$output" "No project directories found in $workplace"
}

test_workplace_root_requires_config
printf 'PASS: workplace_root requires DEV_WORKPLACE\n'
test_workplace_root_requires_a_directory
printf 'PASS: workplace_root requires a directory\n'
test_workplace_project_dirs_lists_sorted_children_including_spaces
printf 'PASS: workplace_project_dirs lists sorted children\n'
test_workplace_project_dirs_dies_when_empty
printf 'PASS: workplace_project_dirs dies when empty\n'
```

In `tests/run.sh`, add `search_test.sh` to the `for suite in` list.

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/search_test.sh`

Expected: FAIL with `workplace_root: command not found` (or equivalent).

- [ ] **Step 3: Implement enumerator and switch `project.sh`**

Append to `scripts/lib.sh` after `to_shell_path`:

```bash
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
```

Note: the `found=true` inside a `while` that is not the last pipeline element is **not** lost here because the while is in the current shell (`< <(...)`).

Replace `scripts/project.sh` lines 9–20 with:

```bash
mode="${1:-print}"
workplace="$(workplace_root)"
need fzf

rows="$(
  while IFS= read -r path; do
    printf '%s\t%s\n' "$(basename "$path")" "$path"
  done < <(workplace_project_dirs)
)"
```

Keep the rest of `project.sh` unchanged (`fzf` delimiter, Ctrl-O/Y, print/open).

- [ ] **Step 4: Run enumerator tests and existing project tests**

Run: `bash tests/search_test.sh`

Expected: four PASS lines.

Run: `bash tests/review_fixes_test.sh` (covers `cproj`)

Expected: existing PASS lines, including `cproj keeps editor output out of path selection`.

- [ ] **Step 5: Commit**

```bash
git add scripts/lib.sh scripts/project.sh tests/search_test.sh tests/run.sh
git commit -m "$(cat <<'EOF'
Share a DEV_WORKPLACE child enumerator for search and cproj.

EOF
)"
```

---

### Task 2: `search.sh reload`

**Files:**
- Create: `scripts/search.sh` (reload mode only for now; other modes may `die "Unknown search mode"`)
- Modify: `tests/search_test.sh`
- Modify: `tests/release_test.sh` (`expected_archive_files` — add `scripts/search.sh` next to `scripts/resume.sh`)

**Interfaces:**
- Consumes: `workplace_root`, `workplace_project_dirs`, `need`, `die`
- Produces: `bash scripts/search.sh reload <query>` — rg hits relative to workplace, or empty stdout

- [ ] **Step 1: Write failing reload tests**

Append to `tests/search_test.sh` (before the runner calls at the bottom, then add the runner calls):

```bash
search_reload() {
  DEV_WORKPLACE="$1" bash "$source_dir/scripts/search.sh" reload "$2"
}

test_reload_ignores_short_queries() {
  local workplace="$test_root/short-query" output
  mkdir -p "$workplace/payments"
  printf 'OrderService\n' > "$workplace/payments/A.java"
  output="$(search_reload "$workplace" '')"
  assert_equals "$output" ''
  output="$(search_reload "$workplace" 'O')"
  assert_equals "$output" ''
}

test_reload_finds_a_sibling_project_not_just_cwd() {
  local workplace="$test_root/function action place" output
  mkdir -p "$workplace/notes vault" "$workplace/payments/src"
  printf 'nothing\n' > "$workplace/notes vault/readme.md"
  printf 'public class OrderService {}\n' > "$workplace/payments/src/OrderService.java"
  output="$(
    cd "$workplace/notes vault"
    search_reload "$workplace" 'OrderService'
  )"
  assert_contains "$output" 'payments/src/OrderService.java'
  assert_contains "$output" 'OrderService'
}

test_reload_respects_child_gitignore() {
  local workplace="$test_root/ignore-child" output
  create_repo "$workplace/payments"
  printf 'secret-token\n' > "$workplace/payments/ignored.txt"
  printf 'ignored.txt\n' > "$workplace/payments/.gitignore"
  git -C "$workplace/payments" add .gitignore
  git -C "$workplace/payments" commit -q -m 'Ignore ignored.txt'
  printf 'visible-token\n' > "$workplace/payments/visible.txt"
  output="$(search_reload "$workplace" 'token')"
  assert_contains "$output" 'payments/visible.txt'
  [[ "$output" != *payments/ignored.txt* ]] || fail 'rg searched a gitignored file'
}

test_reload_searches_a_non_git_child() {
  local workplace="$test_root/plain-child" output
  mkdir -p "$workplace/scratch"
  printf 'OrderService\n' > "$workplace/scratch/notes.md"
  output="$(search_reload "$workplace" 'OrderService')"
  assert_contains "$output" 'scratch/notes.md'
}
```

Call them at the bottom with `PASS:` lines.

- [ ] **Step 2: Run reload tests to verify they fail**

Run: `bash tests/search_test.sh`

Expected: FAIL (`search.sh` missing or unknown mode).

- [ ] **Step 3: Implement `reload`**

Create `scripts/search.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$script_dir/lib.sh"

mode="${1:-live}"
shift || true

path_separator='/'
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) path_separator='//' ;;
esac

rg_roots() {
  local path
  while IFS= read -r path; do
    printf '%s\n' "$(basename "$path")"
  done < <(workplace_project_dirs)
}

reload_search() {
  local query="$1" workplace
  need rg
  [ "${#query}" -ge 2 ] || return 0
  workplace="$(workplace_root)"
  (
    cd "$workplace"
    roots=()
    while IFS= read -r root; do
      roots+=("$root")
    done < <(rg_roots)
    rg --line-number --column --no-heading --smart-case --hidden -g '!.git' \
      --path-separator "$path_separator" -- "$query" "${roots[@]}" || true
  )
}

case "$mode" in
  reload)
    reload_search "${DEV_HARNESS_INPUT:-$*}"
    ;;
  live|semantic|index)
    die "Search mode '$mode' is not implemented yet."
    ;;
  *) die "Unknown search mode: $mode" ;;
esac
```

- [ ] **Step 4: Run tests**

Run: `bash tests/search_test.sh`

Expected: all PASS, including sibling / gitignore / non-git / short query.

If gitignore test fails because `ignored.txt` was committed before `.gitignore`, keep the file untracked (do not `git add ignored.txt`). The test above writes `ignored.txt` after the gitignore commit and never adds it; `rg` still respects gitignore for untracked files. If it still matches, add `git -C ... add -f` is wrong — leave untracked.

- [ ] **Step 5: Commit**

```bash
git add scripts/search.sh tests/search_test.sh tests/release_test.sh
git commit -m "$(cat <<'EOF'
Add workplace-wide rg reload with gitignore-aware roots.

EOF
)"
```

---

### Task 3: Live picker wiring

**Files:**
- Modify: `scripts/search.sh` (implement `live`; keep `semantic`/`index` unimplemented)
- Modify: `scripts/open.sh` (delete the `search)` branch; keep `need rg` for `file`)
- Modify: `scripts/preview.sh` (`search)` case)
- Modify: `scripts/palette.sh` (move `search` into the workplace block; remove from Git-only block)
- Modify: `Taskfile.global.yml` (`search` task)
- Modify: `scripts/help.sh`
- Modify: `tests/search_test.sh`
- Modify: `tests/workflow_utils_test.sh` (palette with workplace outside Git must include `search`)

**Interfaces:**
- Consumes: `reload_search`, `workplace_root`, `clip_copy`, `ai.sh analyze-files`
- Produces: `gtask search` → `bash scripts/search.sh live`

- [ ] **Step 1: Write failing live-open and palette tests**

Live open (fake fzf, fake editor) in `tests/search_test.sh`:

```bash
test_live_search_opens_a_workplace_relative_match() {
  local workplace="$test_root/live-open" fake_bin editor_record output status=0
  fake_bin="$workplace/bin"
  editor_record="$workplace/editor-argument"
  mkdir -p "$workplace/payments/src" "$fake_bin"
  printf 'public class OrderService {}\n' > "$workplace/payments/src/OrderService.java"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'printf "\n%s\n" "payments/src/OrderService.java:1:8:OrderService"' \
    > "$fake_bin/fzf"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'printf "%s\n" "$*" > "$EDITOR_RECORD"' \
    > "$fake_bin/code"
  chmod +x "$fake_bin/fzf" "$fake_bin/code"

  output="$(
    PATH="$fake_bin:$PATH" DEV_WORKPLACE="$workplace" DEV_EDITOR=code EDITOR_RECORD="$editor_record" \
      bash "$source_dir/scripts/search.sh" live
  )" || status=$?

  [ "$status" -eq 0 ] || fail "live search failed: $output"
  assert_contains "$(cat "$editor_record")" "--goto"
  assert_contains "$(cat "$editor_record")" "payments/src/OrderService.java:1:8"
}

test_open_search_mode_is_removed() {
  local output status=0
  output="$(bash "$source_dir/scripts/open.sh" search 2>&1)" || status=$?
  [ "$status" -ne 0 ] || fail 'open.sh still accepts search'
  assert_contains "$output" 'Unknown open mode: search'
}

test_palette_offers_search_outside_git_when_workplace_exists() {
  local fixture="$test_root/palette-search" workplace bin palette_log
  workplace="$fixture/workplace"
  bin="$fixture/bin"
  palette_log="$fixture/palette.tsv"
  mkdir -p "$workplace/payments" "$bin"
  printf '%s\n' '#!/usr/bin/env bash' 'cat > "$PALETTE_LOG"' 'exit 130' > "$bin/fzf"
  printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$bin/task"
  chmod +x "$bin/fzf" "$bin/task"
  PATH="$bin:$(dirname "$(command -v git)"):/usr/bin:/bin" \
    DEV_WORKPLACE="$workplace" PALETTE_LOG="$palette_log" \
    bash "$source_dir/scripts/palette.sh" select || true
  assert_contains "$(cat "$palette_log")" $'search\t'
}

test_palette_hides_search_without_workplace() {
  local fixture="$test_root/palette-no-workplace" bin palette_log
  bin="$fixture/bin"
  palette_log="$fixture/palette.tsv"
  mkdir -p "$bin"
  printf '%s\n' '#!/usr/bin/env bash' 'cat > "$PALETTE_LOG"' 'exit 130' > "$bin/fzf"
  printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$bin/task"
  chmod +x "$bin/fzf" "$bin/task"
  PATH="$bin:$(dirname "$(command -v git)"):/usr/bin:/bin" \
    DEV_WORKPLACE= PALETTE_LOG="$palette_log" \
    bash -c 'cd "$1"; bash "$2/scripts/palette.sh" select' _ "$fixture" "$source_dir" \
    || true
  if grep -Eq '^search\t' "$palette_log"; then
    fail 'search appeared without DEV_WORKPLACE'
  fi
}
```

Add a preview assertion: `preview.sh search` with `DEV_WORKPLACE` set shows the Java file, not `repo_root`.

```bash
test_search_preview_reads_the_workplace_file() {
  local workplace="$test_root/preview-workplace" output
  mkdir -p "$workplace/payments"
  printf 'alpha-line\nOrderService\n' > "$workplace/payments/A.java"
  output="$(
    DEV_WORKPLACE="$workplace" \
      bash "$source_dir/scripts/preview.sh" search 'payments/A.java:2:1:OrderService'
  )"
  assert_contains "$output" 'OrderService'
}
```

- [ ] **Step 2: Run the new tests to verify they fail**

Run: `bash tests/search_test.sh`

Expected: FAIL on live mode not implemented / open.sh still has search / palette missing search.

- [ ] **Step 3: Implement live mode and wiring**

In `scripts/search.sh`, add (same helpers as `open.sh`, workplace as root):

```bash
open_match() {
  local match="$1" file line column editor editor_name
  editor="${DEV_EDITOR:-code}"
  need "$editor"
  IFS=: read -r file line column _ <<<"$match"
  editor_name="$(basename "$editor")"
  case "$editor_name" in
    code|code.cmd|code-insiders|code-insiders.cmd)
      "$editor" --goto "$(workplace_root)/$file:$line:$column"
      ;;
    *)
      "$editor" "$(workplace_root)/$file"
      ;;
  esac
}

parse_selection() {
  local raw="$1" item
  selection_key="$(printf '%s\n' "$raw" | sed -n '1p')"
  selection_items=()
  while IFS= read -r item; do
    [ -n "$item" ] && selection_items+=("$item")
  done < <(printf '%s\n' "$raw" | sed '1d')
}

match_files() {
  local item file
  files=()
  for item in "$@"; do
    IFS=: read -r file _ <<<"$item"
    files+=("$(workplace_root)/$file")
  done
}

run_live() {
  local query raw
  need fzf
  need rg
  need "${DEV_EDITOR:-code}"
  workplace_project_dirs >/dev/null
  query="${DEV_HARNESS_INPUT:-$*}"
  raw="$(
    fzf \
      --disabled \
      --multi \
      --query="$query" \
      --bind "start:reload:bash \"$script_dir/search.sh\" reload {q}" \
      --bind "change:reload:bash \"$script_dir/search.sh\" reload {q}" \
      --expect=ctrl-o,ctrl-y,ctrl-a,ctrl-r \
      --header='Tab: multi · Enter/Ctrl-O: open · Ctrl-Y: copy · Ctrl-A: AI · Ctrl-R: review' \
      --preview="bash \"$script_dir/preview.sh\" search {}" \
      --preview-window='right,65%,wrap' \
      --prompt='match > '
  )" || exit 0
  parse_selection "$raw"
  [ "${#selection_items[@]}" -gt 0 ] || exit 0
  case "$selection_key" in
    ctrl-y) printf '%s\n' "${selection_items[@]}" | clip_copy ;;
    ctrl-a|ctrl-r)
      match_files "${selection_items[@]}"
      bash "$script_dir/ai.sh" analyze-files "${files[@]}"
      ;;
    ''|ctrl-o)
      local item
      for item in "${selection_items[@]}"; do open_match "$item"; done
      ;;
  esac
}
```

Point `live)` to `run_live "$@"`. Delete the “not implemented” die for `live`.

`scripts/open.sh`: remove the entire `search)` case.

`scripts/preview.sh` `search)`:

```bash
  search)
    IFS=: read -r file line _ <<<"$target"
    root="$(workplace_root)"
    if is_sensitive_path "$file"; then
      printf 'Sensitive file preview is hidden: %s\n' "$file"
    else
      show_file "$root/$file" "$line"
    fi
    ;;
```

`scripts/palette.sh`: inside the existing `DEV_WORKPLACE` directory block (with `projects`/`resume`/`dirty`), add:

```bash
  add_row search 'search workplace text' 'szukaj tekst grep rg s workplace'
```

Remove `add_row search ...` from the Git-only block.

`Taskfile.global.yml` `search` task:

```yaml
  search:
    aliases: [s]
    desc: Search workplace text and open a selected match
    dir: '{{.USER_WORKING_DIR}}'
    env:
      DEV_HARNESS_INPUT: '{{.CLI_ARGS}}'
    cmds:
      - bash "${DEV_HARNESS_HOME:-$HOME/.dev-harness}/scripts/search.sh" live
```

`scripts/help.sh` Find line:

```bash
    '  gtask search -- TEXT  search workplace contents' \
```

- [ ] **Step 4: Run tests**

Run: `bash tests/search_test.sh`

Expected: all PASS.

Run: `bash tests/workflow_utils_test.sh`

Expected: palette tests still PASS (search may now appear in the workplace log; that is required, not a leak).

- [ ] **Step 5: Commit**

```bash
git add scripts/search.sh scripts/open.sh scripts/preview.sh scripts/palette.sh \
  Taskfile.global.yml scripts/help.sh tests/search_test.sh
git commit -m "$(cat <<'EOF'
Wire live workplace search into gtask search and drop repo-only rg.

EOF
)"
```

---

### Task 4: Make `rg` required (slice 1 docs)

**Files:**
- Modify: `scripts/doctor.sh` (`check_command rg true`; remove `rg` from optional)
- Modify: `install.sh` (`usage` required list, `validate_required_tools`, `report_optional_tools`)
- Modify: `tests/review_fixes_test.sh` (installer/doctor tests for `rg`)
- Modify: `.github/workflows/ci.yml` (install ripgrep on macOS/Windows like fzf)
- Modify: `README.md`, `TUTORIAL.md`, `PRD.md` §§8.1 / 8.6 / §10, `CHANGELOG.md`, `docs/site/index.html`, `docs/site/tutorial.html`, `demo/entrypoint.sh`

**Interfaces:**
- Consumes: existing `check_command` / `validate_required_tools`
- Produces: installer dies without `rg`; doctor JSON `"name":"rg","status":"error"` when absent

- [ ] **Step 1: Write failing installer/doctor tests**

In `tests/review_fixes_test.sh`, copy `test_install_requires_fzf_before_writing` to `test_install_requires_rg_before_writing`: wrap `bash`, `task`, `git`, `fzf`, `dirname`, `tr`; **do not** wrap `rg`. Assert status ≠ 0, no `~/.dev-harness`, output contains `Required tool not found in PATH: rg`.

Copy `test_doctor_reports_fzf_as_required_json_error` to `test_doctor_reports_rg_as_required_json_error`: PATH with bash/task/git/fzf/dirname/sed, no `rg`. Assert `"name":"rg","status":"error"`.

Call both at the bottom.

- [ ] **Step 2: Run those tests to verify they fail**

Run: `bash tests/review_fixes_test.sh`

Expected: FAIL (`rg` still optional / installer succeeds without `rg`).

- [ ] **Step 3: Promote `rg` and update copy**

`install.sh`:

- usage: `bash, task, git, fzf, rg`
- `validate_required_tools`: `for tool in bash task git fzf rg`
- `report_optional_tools`: drop `rg` from `rg code gh docker atuin`

`scripts/doctor.sh`: `check_command rg true`

CI `ci.yml`: after fzf install steps, install ripgrep (`brew install ripgrep` / `choco install ripgrep -y --no-progress`).

Docs (slice 1 only — no grepai yet):

- README Requirements: move `rg` to Required; optional list without `rg`
- TUTORIAL §1: `rg` under required, not optional
- PRD §8.1: `gtask search -- <query>` searches immediate `DEV_WORKPLACE` children with live `rg`; Git is not required
- PRD §8.6: `rg` is required; optional list without `rg`
- PRD §10 diagram: `required: bash · task · git · fzf · rg`
- CHANGELOG Unreleased Added: workplace-wide live `gtask search`; `rg` required
- `docs/site/index.html` install sentence includes `rg`
- `docs/site/tutorial.html` requirements list includes `rg`; search caption “search workplace content”
- `demo/entrypoint.sh`: `gtask search -- retry search workplace code and notes` (rg already in the image)

TUTORIAL/README command blurbs: `gtask search -- OrderService` = search across `DEV_WORKPLACE`. Help already updated in Task 3.

- [ ] **Step 4: Run tests**

Run: `bash tests/review_fixes_test.sh`

Expected: new rg tests PASS; fzf tests still PASS.

Run: `bash tests/pages_test.sh`

Expected: PASS (anchors unchanged).

- [ ] **Step 5: Commit**

```bash
git add install.sh scripts/doctor.sh tests/review_fixes_test.sh .github/workflows/ci.yml \
  README.md TUTORIAL.md PRD.md CHANGELOG.md docs/site/index.html docs/site/tutorial.html \
  demo/entrypoint.sh
git commit -m "$(cat <<'EOF'
Require ripgrep now that workplace search is a core command.

EOF
)"
```

---

### Task 5: `gtask index` and `gtask semantic`

**Files:**
- Modify: `scripts/search.sh` (implement `index` and `semantic`; add JSON formatter)
- Modify: `Taskfile.global.yml`
- Modify: `scripts/palette.sh`
- Modify: `scripts/help.sh`
- Modify: `tests/search_test.sh`

**Interfaces:**
- Consumes: `need grepai`, `workplace_root`, live picker helpers (`parse_selection`, `open_match`, `match_files`)
- Produces:
  - `bash scripts/search.sh index`
  - `bash scripts/search.sh semantic`
  - `format_grepai_json` reads stdin JSON, prints `rel:line:1:score snippet`

Semantic JSON mapping (full `--json`, not compact):

```json
{
  "query": "authentication",
  "results": [
    {
      "score": 0.92,
      "file": "payments/src/Auth.java",
      "start_line": 15,
      "end_line": 45,
      "content": "class Auth {\n    void login() {}\n"
    }
  ],
  "total": 1
}
```

becomes `payments/src/Auth.java:15:1:0.92 class Auth {`

If `file` is absolute and starts with `workplace_root` + `/`, strip that prefix. Column is always `1`. Snippet is the first line of `content` with `\n` collapsed.

Index algorithm (cwd = workplace root):

1. `need grepai`
2. If `.grepai/config.yaml` missing: `grepai init --yes --provider ollama --backend gob`
3. If `grepai index --help` succeeds: `grepai index`
4. Else if `grepai watch --status` exits 0: no-op
5. Else: `grepai watch --background`

Semantic: empty query (no CLI, empty prompt) → exit 0. Missing config.yaml or index.gob → `die` containing `gtask index`. Then `grepai search --json --limit 50 -- "$query"`. Zero results → `die "No matches for: $query"`. Non-empty → same fzf keys as live, **not** `--disabled` / reload (one-shot list).

- [ ] **Step 1: Write failing grepai tests**

Use a logging fake `grepai` in `tests/search_test.sh`:

```bash
install_fake_grepai() {
  local bin="$1" log="$2" behavior="${3:-full}"
  mkdir -p "$bin"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    "log='$log'" \
    'printf "%s\n" "$*" >> "$log"' \
    "behavior='$behavior'" \
    'case "$1" in' \
    '  init) mkdir -p .grepai; printf "init\n" > .grepai/config.yaml; exit 0 ;;' \
    '  index)' \
    '    if [ "${2:-}" = --help ]; then' \
    '      [ "$behavior" = has-index ] || exit 1' \
    '      exit 0' \
    '    fi' \
    '    printf "indexed\n" > .grepai/index.gob' \
    '    exit 0' \
    '    ;;' \
    '  watch)' \
    '    case "${2:-}" in' \
    '      --help) exit 0 ;;' \
    '      --status) [ "$behavior" = watch-running ] && exit 0; exit 1 ;;' \
    '      --background) printf "watched\n" > .grepai/index.gob; exit 0 ;;' \
    '      *) exit 1 ;;' \
    '    esac' \
    '    ;;' \
    '  search)' \
    '    cat <<EOF' \
    '{' \
    '  "query": "authentication",' \
    '  "results": [' \
    '    {' \
    '      "score": 0.92,' \
    '      "file": "payments/src/Auth.java",' \
    '      "start_line": 15,' \
    '      "end_line": 45,' \
    '      "content": "class Auth {\n    void login() {}\n"' \
    '    }' \
    '  ],' \
    '  "total": 1' \
    '}' \
    'EOF' \
    '    ;;' \
    '  *) exit 1 ;;' \
    'esac' \
    > "$bin/grepai"
  chmod +x "$bin/grepai"
}
```

Tests:

- missing `grepai` on PATH → `search.sh index` dies `Missing command: grepai`
- workplace with children, no `.grepai/config.yaml`, fake with `has-index` → `index` writes config via `init --yes --provider ollama --backend gob` (assert log) and `index.gob`
- second `index` does **not** append another `init` line
- fake `watch-only` (`index --help` fails) → log contains `watch --background`
- fake `watch-running` with existing config+index.gob → log contains `watch --status`, not `--background`
- semantic without config.yaml → die mentioning `gtask index`
- semantic without index.gob (config present) → die mentioning `gtask index`
- semantic + fake fzf selecting the formatted line → editor `--goto` `.../payments/src/Auth.java:15:1`
- `format_grepai_json` can be tested through semantic; also assert the fzf stub received `payments/src/Auth.java:15:1:0.92 class Auth {`

Empty semantic query: `DEV_HARNESS_INPUT=` and no argv, with stdin closed (`</dev/null`) so `read -p` fails/empty → exit 0.

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/search_test.sh`

Expected: FAIL (`index`/`semantic` not implemented).

- [ ] **Step 3: Implement index, JSON format, semantic**

JSON formatter in `search.sh` (no `jq`). This awk is the contract; tests lock it:

```bash
format_grepai_json() {
  local workplace="$1"
  awk -v workplace="$workplace" '
    function trim(s) {
      sub(/^[[:space:]]+/, "", s)
      sub(/[[:space:]]+$/, "", s)
      return s
    }
    function unquote(s) {
      sub(/^"/, "", s)
      sub(/"$/, "", s)
      gsub(/\\n/, "\n", s)
      return s
    }
    function emit() {
      if (file == "" || line == "") return
      rel = file
      prefix = workplace "/"
      if (index(rel, prefix) == 1) rel = substr(rel, length(prefix) + 1)
      snippet = content
      sub(/\n.*/, "", snippet)
      printf "%s:%s:1:%s %s\n", rel, line, score, snippet
      file = ""; line = ""; score = ""; content = ""
    }
    {
      line_text = $0
      if (line_text ~ /"file":/) {
        emit()
        sub(/.*"file":[[:space:]]*/, "", line_text)
        sub(/,.*/, "", line_text)
        file = unquote(trim(line_text))
      }
      if ($0 ~ /"start_line":/) {
        line_text = $0
        sub(/.*"start_line":[[:space:]]*/, "", line_text)
        sub(/,.*/, "", line_text)
        line = trim(line_text)
      }
      if ($0 ~ /"score":/) {
        line_text = $0
        sub(/.*"score":[[:space:]]*/, "", line_text)
        sub(/,.*/, "", line_text)
        score = trim(line_text)
      }
      if ($0 ~ /"content":/) {
        line_text = $0
        sub(/.*"content":[[:space:]]*/, "", line_text)
        sub(/"$/, "", line_text)
        content = unquote(trim(line_text))
      }
    }
    END { emit() }
  '
}
```

`run_index`:

```bash
run_index() {
  local workplace
  need grepai
  workplace="$(workplace_root)"
  workplace_project_dirs >/dev/null
  cd "$workplace"
  if [ ! -f .grepai/config.yaml ]; then
    grepai init --yes --provider ollama --backend gob
  fi
  if grepai index --help >/dev/null 2>&1; then
    grepai index
  elif grepai watch --status >/dev/null 2>&1; then
    return 0
  else
    grepai watch --background
  fi
}
```

`run_semantic`: `need fzf`; `need grepai`; `need "${DEV_EDITOR:-code}"`. Require `.grepai/config.yaml` and `.grepai/index.gob` or die `Run gtask index before semantic search.` Prompt if query empty (`read -r -p 'Search: ' query`). `json="$(grepai search --json --limit 50 -- "$query")"`; format; if empty die `No matches for: $query`. fzf **without** `--disabled`/`reload`, same expect keys and preview as live; same action cases using `analyze-files`.

Taskfile:

```yaml
  semantic:
    aliases: [sem]
    desc: Search workplace code by meaning and open a selected match
    dir: '{{.USER_WORKING_DIR}}'
    env:
      DEV_HARNESS_INPUT: '{{.CLI_ARGS}}'
    cmds:
      - bash "${DEV_HARNESS_HOME:-$HOME/.dev-harness}/scripts/search.sh" semantic

  index:
    desc: Initialize and build the workplace semantic index
    dir: '{{.USER_WORKING_DIR}}'
    cmds:
      - bash "${DEV_HARNESS_HOME:-$HOME/.dev-harness}/scripts/search.sh" index
```

Palette workplace block:

```bash
  add_row semantic 'search workplace code by meaning' 'semantic grepai szukaj znaczenie sem'
  add_row index 'initialize workplace semantic index' 'grepai index ollama embeddings'
```

Help Find section: add `gtask semantic -- TEXT` and `gtask index`. Aliases: `gtask sem`.

- [ ] **Step 4: Run tests**

Run: `bash tests/search_test.sh`

Expected: all PASS, including init-once, watch fallback, semantic goto.

- [ ] **Step 5: Commit**

```bash
git add scripts/search.sh Taskfile.global.yml scripts/palette.sh scripts/help.sh tests/search_test.sh
git commit -m "$(cat <<'EOF'
Add gtask index and one-shot grepai semantic search.

EOF
)"
```

---

### Task 6: Require `grepai` and finish product copy

**Files:**
- Modify: `install.sh`, `scripts/doctor.sh`
- Modify: `tests/review_fixes_test.sh`, `tests/install_test.sh`, `tests/search_test.sh` (doctor workplace checks)
- Modify: `demo/Dockerfile`, `demo/entrypoint.sh`
- Modify: README, TUTORIAL, PRD, CHANGELOG, `docs/site/index.html`, `docs/site/tutorial.html`

**Interfaces:**
- Consumes: `check_command`, workplace path
- Produces: end-state requirements from the spec

Doctor when `DEV_WORKPLACE` is a directory:

- missing `.grepai/config.yaml` → **error** (`grepai init has not been run; run gtask index`)
- missing `.grepai/index.gob` → **warn**, **error** if `strict` (`--all`)
- `check_command ollama false` (warn; error with `--all`)

Installer: `validate_required_tools` includes `grepai`. Optional list still has no `rg`. Usage required: `bash, task, git, fzf, rg, grepai`.

`tests/install_test.sh` `create_fake_tools`: add `printf '#!/usr/bin/env bash\nexit 0\n' > "$bin/grepai"` and chmod. Otherwise install tests fail on hosts without grepai.

Demo: install a **pinned** grepai release into `/usr/local/bin` the same way Task is installed (look up current `yoanbernabeu/grepai` linux amd64/arm64 asset, `ARG GREPAI_VERSION`, sha256sum check). Do not pipe an unpinned `install.sh`. After `prepare_repository`, if `command -v grepai` succeeds: `(cd "$workplace" && grepai init --yes --provider ollama --backend gob)` — never `watch`.

CI does **not** need a real grepai binary; tests use fakes. Do not add Ollama to CI or the demo image.

- [ ] **Step 1: Write failing doctor/installer tests**

- `test_install_requires_grepai_before_writing` — PATH has bash/task/git/fzf/rg, no grepai
- `test_doctor_reports_grepai_as_required_json_error`
- `test_doctor_errors_when_workplace_has_no_grepai_config` — workplace dir exists, no `.grepai/config.yaml`, grepai on PATH; JSON `"name":"grepai-init"` or `"name":"grepai index"` — **use check name `grepai-config`** with detail `run gtask index`
- `test_doctor_warns_when_workplace_index_is_missing` — config.yaml present, no index.gob; without `--all` status warn; with `--all` error

Pick one doctor check name and stick to it: `grepai-config` and `grepai-index`.

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/review_fixes_test.sh`

Expected: FAIL (grepai still optional).

- [ ] **Step 3: Implement doctor/installer/demo/docs**

Doctor after the existing `DEV_WORKPLACE` check:

```bash
if [ -n "${DEV_WORKPLACE:-}" ] && [ -d "$DEV_WORKPLACE" ]; then
  if [ -f "$DEV_WORKPLACE/.grepai/config.yaml" ]; then
    add_check grepai-config ok "$DEV_WORKPLACE/.grepai/config.yaml"
  else
    add_check grepai-config error "run gtask index"
  fi
  if [ -f "$DEV_WORKPLACE/.grepai/index.gob" ]; then
    add_check grepai-index ok "$DEV_WORKPLACE/.grepai/index.gob"
  elif [ "$strict" = true ]; then
    add_check grepai-index error "run gtask index"
  else
    add_check grepai-index warn "run gtask index"
  fi
fi
check_command ollama false
check_command grepai true
```

Place `check_command grepai true` with the other required commands. Keep `check_command rg true` from Task 4.

Docs end state:

- Required: Bash, Task, Git, fzf, `rg`, `grepai`
- Optional: Ollama (needed for `gtask index` / semantic), VS Code, Docker, gh, Atuin, bat, Obsidian, AI CLIs
- Commands: `gtask semantic`, `gtask index`
- PRD §8.1 table rows for semantic + index
- PRD §10: `required: bash · task · git · fzf · rg · grepai`
- CHANGELOG: semantic search + grepai required
- Site install + tutorial requirements + Find cheatsheet

- [ ] **Step 4: Run verification**

Run: `bash tests/run.sh`

Expected: `PASS: complete Dev Harness verification`

If demo Dockerfile grepai checksum is wrong, fix the pin; do not skip the checksum.

- [ ] **Step 5: Commit**

```bash
git add install.sh scripts/doctor.sh tests/review_fixes_test.sh tests/install_test.sh \
  tests/search_test.sh demo/Dockerfile demo/entrypoint.sh README.md TUTORIAL.md PRD.md \
  CHANGELOG.md docs/site/index.html docs/site/tutorial.html
git commit -m "$(cat <<'EOF'
Require grepai and document workplace semantic search.

EOF
)"
```

---

## Self-review (plan vs spec)

| Spec item | Task |
|---|---|
| Immediate children only, no worktrees | 1 |
| Live rg, min 2 chars, gitignore, non-git child, spaces | 2 |
| Results workplace-relative, `path-separator` | 2–3 |
| Live fzf `--disabled` reload, prefill query, no Search: prompt | 3 |
| Ctrl-A/R → `analyze-files` absolute, not `changes.sh` | 3 |
| Sensitive preview hidden | 3 |
| Palette search outside Git when workplace exists | 3 |
| `open.sh search` removed | 3 |
| `rg` required installer/doctor/docs; no grepai yet | 4 |
| `gtask index` init `--yes --provider ollama --backend gob`, index or watch --background, idempotent watcher | 5 |
| Semantic one-shot JSON, die without config/index.gob, hint `gtask index` | 5 |
| `grepai` required; config error; index.gob warn / `--all` error; ollama warn | 6 |
| Demo installs grepai binary, init without watch, no Ollama | 6 |
| Installer never installs grepai/Ollama | 6 (docs + no install.sh downloader) |
| `tests/search_test.sh` + `run.sh` + release archive | 1–2 |
| No Serena / merged picker / live semantic / grepai workspace | out of scope, no task |
