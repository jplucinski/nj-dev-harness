# Workplace search (live rg + grepai)

Status: approved design  
Date: 2026-09-05

Replace repo-scoped `gtask search` with workplace-wide live ripgrep, and add a separate semantic command backed by required `grepai` initialized in `DEV_WORKPLACE`.

## Goal

From any directory, `gtask search` finds exact text across every immediate child of `DEV_WORKPLACE`. `gtask semantic` finds code by meaning in the same corpus. Current Git repository, cwd, and linked worktrees do not change the corpus.

## Out of scope

- Installing `grepai`, Ollama, or embedding models from `install.sh` (installer still never installs third-party tools).
- `grepai workspace` / PostgreSQL / Qdrant.
- Walking `git worktree list` (a worktree is searched only if it is itself an immediate child of `DEV_WORKPLACE`).
- Merging rg and semantic hits in one picker.
- Live-reloading semantic search on each keystroke.
- Serena, CodeGraph, or any other code-intel MCP.

## Commands

| Command | Alias | Behavior |
|---|---|---|
| `gtask search [-- <query>]` | `s` | Live `rg` in fzf over workplace children. CLI query prefills fzf. |
| `gtask semantic [-- <query>]` | `sem` | Prompt or CLI query, then `grepai search --json` into the same picker. |
| `gtask index` | none | `grepai init` when missing, then one-shot index / background watch. |

All three require `DEV_WORKPLACE` set to an existing directory with at least one immediate child directory. Failure copy matches `cproj`.

## Architecture

```text
gtask search|semantic|index
        ↓
scripts/search.sh  (live | semantic | index | reload)
        ↓
lib.sh workplace_root / workplace_project_dirs
        ↓
rg | grepai | DEV_EDITOR / analyze-files
```

- `scripts/open.sh` drops mode `search`. File and changed pickers stay there.
- `scripts/project.sh` lists children through the shared enumerator.
- Results are **relative to `DEV_WORKPLACE`** (`payments/src/Foo.java:12:3:…`) so `IFS=:` parsing does not hit Windows drive letters. `rg --path-separator` stays as in `open.sh`.
- Preview and `--goto` resolve `$DEV_WORKPLACE/$file`.
- Ctrl-A / Ctrl-R pass unique **absolute** files to `ai.sh analyze-files`. They must not call `changes.sh` (that diff is the current repo).

## Workplace enumerator

`workplace_root` dies if `DEV_WORKPLACE` is unset or not a directory.

`workplace_project_dirs` prints immediate children (`find -mindepth 1 -maxdepth 1 -type d`, `LC_ALL=C sort`, paths through `to_shell_path`). Dies if the list is empty. Does not require Git. Does not add linked worktrees.

## Live search

1. Enumerate roots.
2. Open fzf `--disabled --multi` with the current picker keys: Enter / Ctrl-O open, Ctrl-Y copy, Ctrl-A AI, Ctrl-R review. Prefill `--query` from `query="${DEV_HARNESS_INPUT:-$*}"` (same as today's search; Taskfile sets `DEV_HARNESS_INPUT` from `CLI_ARGS`).
3. Bind `start` and `change` to `bash "$script_dir/search.sh" reload {q}`.
4. `reload`: if `${#query} < 2`, print nothing and exit 0. Otherwise run one `rg` from the workplace root:

   ```bash
   rg --line-number --column --no-heading --smart-case --hidden -g '!.git' \
     --path-separator "$path_separator" -- "$query" "${roots[@]}"
   ```

5. Cancel fzf: exit 0, no side effects.
6. Zero hits: empty picker, do not die (the query is still live).

`rg` uses each child's `.gitignore` when that child is a Git work tree. Non-Git children are searched in full aside from `-g '!.git'`.

## Semantic search

Not live. Empty query (no CLI/prompt text): exit 0.

Requires `grepai` on PATH, `$DEV_WORKPLACE/.grepai/config.yaml`, and `$DEV_WORKPLACE/.grepai/index.gob`. Otherwise die and tell the user to run `gtask index`.

Run from the workplace root:

```bash
grepai search --json --limit 50 -- "$query"
```

Use **full** JSON (not `--compact`) so fzf can show a snippet. Map `results[]`:

- `file` → path relative to `DEV_WORKPLACE` (strip the workplace prefix if grepai emits an absolute path)
- `start_line` → line (column `1`)
- first line of `content` → snippet
- `score` → prefix in the displayed line

Picker line: `rel:line:1:score snippet`. Same open / copy / AI contract as live search. Zero grepai hits: die `No matches for: <query>` (one-shot, not live).

## `gtask index`

`need grepai`. Cwd = workplace root.

1. If `.grepai/config.yaml` is missing: `grepai init --yes --provider ollama --backend gob`.
2. If `grepai index --help` succeeds: run `grepai index`.
3. Else if `grepai watch --status` reports a running watcher: do nothing (idempotent).
4. Else: `grepai watch --background` (official initial scan; returns after the first build).

Do not invent extra `.gitignore` rules. Do not start a second watcher.

## Palette, help, Taskfile

When `DEV_WORKPLACE` exists as a directory, palette shows `search`, `semantic`, and `index` even outside Git. Remove `search` from the Git-only block.

`gtask semantic` stays visible if `grepai` is missing; `need grepai` fails closed at runtime (unlike Docker rows).

Update `scripts/help.sh`, `Taskfile.global.yml`, README, TUTORIAL, PRD §8.1, CHANGELOG, demo copy, and `docs/site` mirrors.

## Requirements and doctor

Installer `validate_required_tools` and doctor required errors: `bash`, `task`, `git`, `fzf`, `rg`, `grepai`.

`rg` and `grepai` leave the optional list.

Doctor, when the workplace path is a directory:

- missing `.grepai/config.yaml` → **error** (init is required)
- missing `.grepai/index.gob` → **warn**, **error** with `--all` (install/demo can finish before the first index build)
- missing `ollama` → **warn**, **error** with `--all`

`gtask semantic` still dies without `index.gob`. Installer still does not run `grepai init` (workplace may not exist; init mutates it).

## Demo

`demo/Dockerfile` installs the `grepai` binary so `install.sh` can require it. It does not install Ollama. Live search remains the demo path. `entrypoint.sh` may run `grepai init --yes --provider ollama --backend gob` once the sample workplace exists; it must not run `watch` (no embedder).

## Error handling

| Condition | Result |
|---|---|
| Unset / missing workplace, zero children | die like `cproj` |
| Missing `fzf` (all three) or `rg` (live/reload) | `need` |
| Missing `grepai` (semantic/index) | `need` |
| Semantic without config or `index.gob` | die, hint `gtask index` |
| fzf cancel | exit 0 |
| Live rg zero hits | empty picker |
| Semantic zero hits | die `No matches` |
| Sensitive path in preview | hide contents; open still allowed |
| Installer PATH missing `rg` or `grepai` | die, write nothing |

## Testing

New `tests/search_test.sh` wired from `tests/run.sh`. `tests/release_test.sh` archive list includes `scripts/search.sh`. No real Ollama, no interactive fzf.

Reload / enumerator (no TTY):

- unset / non-directory / empty workplace → die
- two children, one name with spaces; reload `OrderService` hits the sibling, not only cwd
- query length 0 and 1 → empty stdout, exit 0
- child `.gitignore` suppresses a match
- non-Git child is still searched

Semantic / index with a fake `grepai` on PATH:

- missing binary → `need grepai`
- missing config.yaml or index.gob → die with `gtask index`
- `index` runs `init --yes --provider ollama --backend gob` only when config is missing
- stub with `index` subcommand → that command; otherwise `watch --background`
- `watch --status` already running → no second daemon
- `search --json` fixture (`results[].file`, `start_line`, `score`, `content`) → picker lines `rel:line:1:…`

Product contract:

- doctor JSON: `rg` and `grepai` error when absent; workplace dir without config.yaml → error; without index.gob → warn
- installer without `rg` or `grepai` → die, no files written (same shape as the fzf test)
- palette with workplace, outside Git: `search`, `semantic`, `index` rows; without workplace those rows are absent
- `open.sh search` is gone

## Implementation slices

End state is the Requirements section. Ship in two slices in one plan:

1. Enumerator + live `gtask search` + palette/docs. Promote `rg` to installer/doctor required. Do not mention or require `grepai` yet. `open.sh search` is removed in this slice.
2. `gtask index` + `gtask semantic` + grepai doctor/demo/docs. Promote `grepai` to installer/doctor required.

Live search never calls `grepai`. Installer does not require `grepai` until slice 2.
