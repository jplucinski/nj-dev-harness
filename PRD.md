# Dev Harness: Product Requirements Document

Status: `0.3.0` preview specification  
Last updated: 2026-09-05

## 1. Product summary

Dev Harness provides global commands for repository navigation, Git worktrees,
AI context, Docker, and Obsidian on macOS and Windows Git Bash. Project-specific
commands stay in each project's `Taskfile.yml`.

> Find → Do → Remember

It composes existing CLIs through a global Taskfile, Bash aliases, functions,
and scripts. It does not replace those tools.

## 2. Product principles

1. One command performs one understandable action.
2. A single native command is shortened with an alias, not wrapped in another program.
3. Interactive selection uses `fzf` only when a choice is genuinely needed.
4. Project-specific build, test, run, deploy, and release commands stay in the project.
5. Existing official CLIs are preferred over reimplementing their behavior.
6. Destructive operations show their target and require confirmation.
7. The MVP contains no custom application and no persistent database.

## 3. Vision

A developer can use the same commands to navigate repositories, create
worktrees, prepare AI context, inspect containers, and write Obsidian notes on
both supported operating systems.

## 4. Goals

- Provide one global command catalogue available from every directory.
- Select projects and files with `fzf`, `rg`, and `DEV_EDITOR`.
- Make returning to an interrupted repository or worktree a single action without maintaining a new activity database.
- Make Git worktree creation safe and conflict-resistant.
- Build useful, review-oriented Git context for any configured AI CLI.
- Provide quick access to Docker logs and container shells.
- Support ordinary notes, daily logs, weekly summaries, and TODO items through the official Obsidian CLI.
- Validate installation and configuration without modifying the machine.
- Work on macOS and Windows through Git Bash.

## 5. Non-goals

- Implementing project build, test, run, deploy, or release workflows.
- Detecting Maven or Gradle commands and guessing project behavior.
- Replacing local project Taskfiles.
- Replacing Git, Docker, Obsidian, VS Code, Atuin, mise, or AI agents.
- Providing a graphical interface.
- Implementing a custom note store or Obsidian parser.
- Automatically installing missing dependencies.
- Uploading telemetry or collecting usage data.
- Building an application in Go before shell-based implementation proves insufficient.

## 6. Primary user

A developer working across multiple repositories, primarily on Java systems but also on other stacks, who uses a terminal, Git, VS Code, Docker, AI coding agents, and Obsidian on macOS or Windows.

Java-specific behavior belongs to the repository's Taskfile, Maven or Gradle
configuration, or mise configuration.

## 7. User experience

### 7.1 Entry points

```bash
gtask                  # global command palette
gtask <utility>        # named global utility
task <project-task>    # local project workflow
```

`gtask` is a shell function. With arguments it delegates directly to `task -g`; without arguments it opens the palette, records the selected replayable command in history, and dispatches it.

Fast paths may be added only for frequently used commands:

```bash
alias gs='git status -sb'
alias gd='git diff'
alias gds='git diff --staged'
alias gl='git log --oneline --graph --decorate -20'
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias -- -='cd -'
alias ll='ls -lah'
alias la='ls -A'
```

Changing the parent shell directory requires a function:

```bash
mkcd DIR # mkdir -p DIR and cd into it
resume   # select a recent project or worktree and cd into it
cproj    # select a project and cd into it
oproj    # select a project and open it in DEV_EDITOR
```

### 7.2 Command palette

Running `gtask` without a task opens an `fzf` list of available global
utilities. Inside Git, the header shows repository, branch,
staged/unstaged/untracked counts, and worktree count. Repository-only actions
are hidden outside a repository.

Every utility is directly callable. `fzf` remains required because the default
`gtask` command and other selectors depend on it.

After selection, Dev Harness records the public command, for example
`gtask review`, in Bash history and `$HISTFILE`. With an initialized Atuin
session it also records the directory, duration, and exit status. Direct commands
use normal shell history hooks. Cancellation records nothing.

These commands work from any directory:

| Command | Behavior |
|---|---|
| `gtask help` (`gtask h`) | Show commands grouped by Find, Do, Remember, and Validate. |
| `gtask aliases` (`gtask aka`) | Show shell aliases, shell functions, and Task aliases with their expansions. |
| `gtask extend` (`gtask ext`) | Show the extension decision rule, supported customization files, and minimal examples. |
| `gtask --list` | Show the Task-generated global command list. |

`help`, `aliases`, and `extend` must not require Git, `fzf`, Obsidian, Docker, or an AI CLI. All are present in the command palette from every directory.

Palette matching covers the command, visible description, aliases, and hidden search keywords. Personal palette entries may be added as tab-separated `task`, `description`, and `keywords` rows in `~/.config/dev-harness/palette.tsv`.

Picker controls, where applicable:

```text
Tab      select multiple entries
Enter    perform the primary action
Ctrl-O   open in DEV_EDITOR
Ctrl-Y   copy the selected path or generated context
Ctrl-A   analyze selected files with AI
Ctrl-R   review selected changes with AI
```

## 8. Functional requirements

### 8.1 Find: projects and files

| Command | Behavior |
|---|---|
| `cproj` | Select an immediate child of `DEV_WORKPLACE` and change the current shell directory. |
| `oproj` | Select a project and open it with `DEV_EDITOR`. |
| `cwork` | Change the current shell directory to `DEV_WORKPLACE`. |
| `cvault` | Change the current shell directory to `DEV_OBSIDIAN_VAULT_PATH`. |
| `..` / `...` / `....` | Change directory up 1, 2, or 3 levels. |
| `-` | Change directory to the previous directory (`cd -`). |
| `ll` / `la` | `ls -lah` / `ls -A`. |
| `mkcd DIR` | Create `DIR` if needed and change the current shell directory into it. |
| `resume` | Select a recent repository or linked worktree and change the current shell directory. |
| `gtask resume` | Open the same resume picker from the global Task catalogue; Enter prints the selected path because a child process cannot change its parent shell. |
| `gtask open` | Recursively select a file below the current directory using `rg --files` and open it; Git is not required. |
| `gtask changed` | Select a modified, staged, or untracked file and open it. |
| `gtask search -- <query>` | Live-search immediate `DEV_WORKPLACE` children with `rg` and open a selected match. Git is not required. VS Code receives the exact line and column. |
| `gtask semantic -- <query>` | One-shot semantic search of the workplace `grepai` index and open a selected match. Requires `gtask index` first. |
| `gtask index` | Initialize `.grepai/config.yaml` if missing, then build or refresh the workplace semantic index. |

Search utilities must respect `.gitignore`. File and directory names containing spaces must work.

File and search pickers must support multi-selection. Their preview pane shows file contents, line context, or Git diff. `bat` may provide syntax highlighting but is optional.

The resume candidate set combines, in order:

1. the current Git worktree;
2. recent Atuin directories collapsed to their Git worktree root;
3. immediate Git projects under `DEV_WORKPLACE` and all linked worktrees reported by those repositories.

Candidates are deduplicated by canonical worktree path and limited by `DEV_RESUME_LIMIT`, defaulting to 10. Atuin is optional. Dev Harness reads only directory and relative time for ranking; it must not include command text in previews or AI context.

The list shows project, branch, and activity source/time. The preview calculates
base branch, change counts, commits, changed paths, and the highest-priority open
project TODO only for the highlighted entry.

Resume actions:

```text
Enter    select/print the worktree path
Ctrl-O   open the selected path with DEV_EDITOR
Ctrl-Y   copy compact resume context
Ctrl-A   send resume context to DEV_AI_RESUME_COMMAND
Ctrl-R   run the normal selective AI review in the selected worktree
```

Resume uses the shared sensitive-path filter and change summary.
`DEV_AI_RESUME_COMMAND` reads stdin and falls back to `DEV_AI_REVIEW_COMMAND`.
If neither is set, the prompt is printed.

### 8.2 Do: Git and worktrees

Single Git commands remain aliases. Dev Harness scripts handle selection, naming,
or context assembly.

```bash
gtask wt -- feature/my-change
```

The worktree utility must:

- verify that the current directory belongs to a Git repository;
- determine the repository name and default branch;
- create a safe directory slug from the requested branch name;
- include local date and time in the directory name;
- add a numeric suffix if a path still collides;
- create the branch when it does not exist or attach an existing local branch;
- save the base branch and base commit in a hidden metadata directory beside the worktrees, outside tracked files and Git internals;
- print the created worktree path.

Example directory:

```text
payments-feature-my-change-20260829-143522
```

`gtask changes` must summarize committed, staged, unstaged, and untracked changes relative to the saved base commit when available, otherwise relative to the repository's default branch.

The worktree picker provides:

```bash
cwt                 # select a worktree and change directory
owt                 # select a worktree and open DEV_EDITOR
gtask worktrees     # inspect or act on worktrees
```

The picker previews status and recent commits. It can copy a path, open
`DEV_EDITOR`, start the configured AI in the selected worktree, or request
removal. Removal shows the target and status, requires confirmation, refuses the
active worktree, and does not force-delete dirty worktrees.

### 8.3 Do: AI

| Command | Behavior |
|---|---|
| `gtask ai` | Start the configured interactive AI CLI in the current directory. |
| `gtask context` | Select changed files and print bounded repository context. |
| `gtask context -- --copy` | Select changed files and copy the generated context. |
| `gtask context -- --all` | Generate context for all safe changes without a picker. |
| `gtask context -- --staged` | Limit the picker to staged files. |
| `gtask review` | Select changes, build a review prompt, and pipe it to the configured non-interactive AI command, or print it when none is configured. |
| `gtask review -- --all` | Explicitly review every changed path that survives the sensitive-path policy without an interactive picker. |

The context must include:

- repository and branch identity;
- selected base ref and SHA;
- recent commits since the base;
- committed name/status and statistics;
- staged, unstaged, and untracked changes;
- bounded diffs with file paths and line context.

Untracked files that pass the sensitive-path filter contribute content up to the
configured line limit. Context generation also works before the first commit.

The changed-file picker detects whether `HEAD` exists. With `HEAD`, it combines
tracked changes relative to that commit with untracked files. Before the first
commit, it combines staged and untracked files without trying to resolve
`HEAD`.

AI configuration may point to Codex, Claude, Gemini, Copilot, OpenCode, or
another local command. Credentials and authentication remain the provider's
responsibility.

Only selected files, or files covered by an explicit `--all`, may be included.
Environment values and filtered paths must not enter AI context.

AI review fails closed. Without an interactive terminal and `fzf` selection,
`gtask review` exits non-zero and does not invoke the configured review command.
Only `gtask review -- --all` provides explicit non-interactive consent. Unknown
review options fail with an actionable error.

The filter excludes `.env`, credential and secret files, extensionless SSH
private keys, Java keystores, certificate bundles, and configured sensitive
directories. Generated context reports its line limit.

The individual-path predicate and Git exclusion pathspecs are defined by one
shared sensitive-path policy in `scripts/lib.sh`. Repository summaries, resume
context, selected-file AI flows, and review consume that policy rather than
duplicating secret lists.

### 8.4 Do: Docker

| Command | Behavior |
|---|---|
| `gtask logs` | Select a running container and follow its recent logs. |
| `gtask shell` | Select a running container and open `bash`, falling back to `sh`. |

Docker Compose commands remain project-specific or are used directly.

The repository includes a Docker demo that installs Dev Harness as a non-root
user and creates a sample repository. Its documented run command mounts no host
directories and passes no credentials.

### 8.5 Remember: Obsidian

Dev Harness must use the official `obsidian` CLI. It must not implement its own Markdown database or link updater.

| Command | Behavior |
|---|---|
| `gtask note -- <title>` | Create and open a normal note. No AI is required. |
| `gtask day` | Open today's daily note. |
| `gtask day -- <text>` | Append a timestamped project-aware entry to today's note. |
| `gtask week [-- <text>]` | Open or append to the current weekly summary. |
| `gtask todo -- <text>` | Create a TODO note for the current project with the configured default priority. |
| `gtask todo -- p0..p3 <text>` | Create a TODO note with an explicit critical, high, medium, or low priority. |
| `gtask todo` | List open TODO notes for the current project, sorted from P0 to P3. |
| `gtask todo -- p0..p3` | List open current-project TODO notes with the selected priority. |
| `gtask todos` | List open TODO notes from the entire vault, sorted from P0 to P3. |
| `gtask todos -- p0..p3` | List open vault-wide TODO notes with the selected priority. |
| `gtask todos -- done` | List completed TODO notes from the entire vault. |
| `gtask done [-- p0..p3]` | Select an open TODO in `fzf`, mark it done, and record its completion time. |
| `gtask reopen` | Select a completed TODO and return it to the open state. |

The vault layout uses root-level knowledge categories:

```text
Vault/
├── Daily/
├── Weekly/
├── Notes/
└── TODO/
    ├── TODO.base
    └── 2026/
        └── 08/
            └── 20260830-143012-retry-policy.md
```

Each TODO is a Markdown note under `TODO/<year>/<month>/`. Its filename starts
with local creation time (`YYYYMMDD-HHMMSS`) followed by a title slug.

The note frontmatter is the task record:

```markdown
---
type: todo
title: Fix retry policy
status: open
priority: p1
project: payments
created: 2026-08-30T14:30:12+02:00
completed:
tags:
  - backend
---

# Fix retry policy

Optional description, links, commands, and analysis notes.
```

Required properties are `type`, `title`, `status`, `priority`, `project`, and
`created`. `status` accepts `open` or `done`; `priority` accepts `p0` through
`p3`. `completed` is empty while open and receives an ISO 8601 timestamp when
done. Git-aware notes also record `branch`, short `commit`, and
`[[Projects/<project-slug>]]`. `project` comes from the repository root name.

`gtask done` sets `status: done` and `completed`; `gtask reopen` sets
`status: open` and clears `completed`. Neither command moves the file. Selection
uses the note path.

`TODO/TODO.base` provides views for open, completed, project, and priority. The
CLI and Base use the same properties; there is no separate index.

Inside Git, notes receive `branch` and `commit`. Daily and weekly entries also
include `[[Projects/<project-slug>]]` and a nested project tag. No AI command is
run.

Properties and tags follow Obsidian conventions:

- YAML `tags` is a list property;
- property tags do not include a leading `#`;
- inline tags include `#`, for example `#project/payments`;
- project tags used in shared daily or weekly notes are nested tags;
- internal links use `[[Note name]]` without `.md`;
- `type`, `created`, and `project` are properties, not duplicated free-form tags.

`status`, `priority`, and `project` are properties, not tags. Tags describe
themes such as `backend`, `security`, or `java`. `DEV_TODO_DEFAULT_PRIORITY`
defaults to `p2`. Read commands must not create files or change metadata.

### 8.6 Validate

```bash
gtask doctor
gtask doctor -- --all
gtask doctor -- --json
```

The validator must check:

- Bash, Task, Git, `fzf`, `rg`, and `grepai` as required dependencies;
- `DEV_WORKPLACE` and relevant directory access;
- workplace `.grepai/config.yaml` (error if missing) and `.grepai/index.gob` (warn, error with `--all`);
- optional VS Code, Docker, `gh`, Ollama, Obsidian CLI, and configured AI commands;
- whether the current directory is a Git repository when repository-specific checks are requested.

Missing required dependencies produce an error. Missing optional integrations produce a warning unless `--all` is used. The validator never installs or changes anything.

### 8.7 Install and lifecycle

Dev Harness has one Bash installer and two entry points:

```bash
./install.sh --configure-shell
./install.sh update
./install.sh uninstall
```

```powershell
.\install.ps1 --configure-shell
```

`install.ps1` is a thin Windows launcher that finds Git Bash and delegates to the same Bash installer; it does not create a second implementation.

The installer must:

- validate Bash, Task, Git, `fzf`, and `rg` before changing user files;
- report missing optional integrations without installing them;
- support `install`, `update`, `uninstall`, `--dry-run`, and `--configure-shell`;
- keep a version and installation manifest under `~/.dev-harness`;
- replace managed files during update while preserving `~/.config/dev-harness/config.env` and personal extension files;
- install `$HOME/Taskfile.yml` as a stable, flattened include of `~/.dev-harness/Taskfile.yml` rather than copying all managed tasks there;
- automatically migrate an unchanged legacy Dev Harness global Taskfile to the stable loader;
- leave an unrelated existing global Taskfile unchanged and print the one include entry required to connect Dev Harness;
- edit `~/.bashrc` only when `--configure-shell` is passed, using an identifiable, idempotent managed block;
- run the read-only validator after a successful non-dry-run install or update;
- remove only manifest-owned files during uninstall and preserve unknown files, personal configuration, notes, and the Obsidian vault;
- remove known personal configuration files only through the explicit `uninstall --purge-config` option;
- refuse unsafe purge targets and preserve unknown files inside the personal configuration directory.

## 9. Configuration

Configuration uses environment variables:

```bash
export DEV_WORKPLACE="$HOME/Workplace"
export DEV_EDITOR="code"
export DEV_WORKTREE_ROOT="$HOME/Worktrees"
export DEV_OBSIDIAN_VAULT="My Vault"
export DEV_OBSIDIAN_VAULT_PATH="$HOME/Documents/Obsidian/My Vault"
export DEV_AI_COMMAND="codex"
export DEV_AI_REVIEW_COMMAND="codex exec -"
export DEV_AI_RESUME_COMMAND="codex exec -"
export DEV_CONTEXT_MAX_LINES="4000"
export DEV_RESUME_LIMIT="10"
export DEV_TODO_DEFAULT_PRIORITY="p2"
```

The shell integration loads `~/.config/dev-harness/config.env` when it exists. Environment variables override defaults. No configuration database is used.

Local project configuration remains in the project's `Taskfile.yml`, `.mise.toml`, Maven/Gradle files, and tool-native configuration.

## 10. Architecture

```text
shell aliases/functions
          ↓
global loader ($HOME/Taskfile.yml)
          ↓
managed Taskfile (~/.dev-harness/Taskfile.yml)
          ↓
small Bash scripts (~/.dev-harness/scripts)
          ↓
required: bash · task · git · fzf · rg · grepai
optional: code · docker · obsidian · ollama · AI CLI
```

Responsibilities:

- Shell aliases shorten single commands.
- Shell functions handle state that must affect the current shell, including `cd` and palette history recording.
- The global loader is stable and includes the managed Taskfile with `flatten: true`.
- The managed Taskfile provides discovery, descriptions, aliases, and dispatch.
- The managed Taskfile optionally includes and flattens `~/.config/dev-harness/Taskfile.yml` for personal general-purpose tasks.
- Bash scripts contain multi-step logic.
- Existing CLIs own their domains.
- Local Taskfiles own project-specific workflows.

Go is not part of the MVP. It may be reconsidered only after concrete portability, quoting, performance, or distribution problems are demonstrated.

## 11. Cross-platform requirements

- Supported: macOS Bash-compatible shell and Windows Git Bash.
- Windows PowerShell may launch installation through `install.ps1`; runtime commands still execute in Git Bash.
- Paths with spaces must work.
- Scripts must avoid Linux-only flags unless both supported environments provide them.
- Windows Obsidian integration should prefer the `Obsidian.com` terminal redirector when available.
- All external executables must be discovered through `PATH`.
- The global Taskfile must run tasks from `USER_WORKING_DIR`, not from the home directory.

Native PowerShell support is outside the initial MVP. Task itself may work there, but shell functions and scripts are guaranteed only for the supported shells.

### 11.1 Repository verification and release

`bash tests/run.sh` is the local and CI test entry point. CI runs on macOS and
Windows Git Bash, parses `install.ps1`, checks installer help on Windows, and
runs ShellCheck. Actions use commit pins and read-only repository permissions.

For a pushed `v*` tag, the release workflow verifies that the tag equals
`v$(cat VERSION)`, runs the tests, packages the runtime allowlist as `.tar.gz`
and `.zip`, and writes `SHA256SUMS`. Only the publishing job has
`contents: write`.

## 12. Security and privacy

- No telemetry is collected.
- No data is sent anywhere except through an explicitly configured AI command.
- Resume never sends Atuin command history to AI; only Git/Obsidian context produced by existing safe adapters is eligible.
- Environment variable values, `.env` contents, credentials, extensionless SSH keys, Java keystores, and common secret files are excluded from AI context.
- AI review commands are treated as trusted local configuration.
- Destructive actions require confirmation and display exact targets.
- `doctor` is read-only.
- Installer behavior must not overwrite an unrelated global Taskfile or edit shell configuration without an explicit opt-in.
- Updates may replace only paths listed in the Dev Harness installation manifest.
- Uninstall preserves personal configuration and Obsidian content by default.

## 13. Error handling

- Errors are short, actionable, and written to stderr.
- Missing tools identify the command that must be installed or enabled.
- Canceling `fzf` exits without side effects.
- Running a repository command outside Git fails before creating files.
- Worktree collisions are resolved rather than overwriting existing directories.
- An unavailable AI command causes the generated prompt to remain visible locally.

## 14. Performance

- The global palette should appear in under 300 ms after Task starts on a typical workstation.
- File selection should begin streaming results rather than pre-indexing the repository.
- AI context is bounded by `DEV_CONTEXT_MAX_LINES`, defaulting to 4000 lines.
- Dev Harness maintains no background service or index.

## 15. Acceptance criteria

The MVP is accepted when:

- `gtask`, help, aliases, extension help, and direct Task commands work from any
  directory; palette selection is recorded in Bash and, when active, Atuin.
- Project, file, search, worktree, resume, TODO, and Docker selectors handle
  paths containing spaces and expose the documented keys and previews.
- Worktrees use unique timestamped paths, record the base SHA, and are never
  force-removed while dirty.
- Git summaries and AI context cover committed, staged, unstaged, and untracked
  changes, including repositories without a first commit.
- AI review includes only selected files unless the user passes `--all`.
  Sensitive paths are excluded and Atuin command text is never included.
- AI commands are configurable; without a review or resume command, the prompt
  is printed locally.
- Notes, Daily, Weekly, TODO lifecycle, priorities, properties, tags, and
  `TODO.base` use the official Obsidian CLI and the documented vault layout.
- Docker log and shell selectors require no project configuration. The Docker
  demo builds and starts without mounting host files or passing credentials.
- `doctor` distinguishes required errors from optional warnings and supports
  JSON output.
- Global configuration contains no project build, test, run, deploy, or release
  commands.
- Install, update, dry-run, migration, and uninstall preserve files outside the
  managed manifest and require explicit purge for known personal configuration.
- The test suite passes on macOS and Windows Git Bash. A matching version tag
  creates allowlisted archives and SHA-256 sums.

## 16. MVP roadmap

### Phase 1 — foundation

- global Taskfile;
- versioned, manifest-based installer with a stable global Taskfile loader;
- Git Bash installer plus thin Windows PowerShell launcher;
- shell alias and project functions;
- environment configuration;
- installation validator.

### Phase 2 — Find and Git

- project selection;
- recent-context resume picker;
- file open, changed files, and search;
- timestamped worktree creation;
- change summary and bounded context.

### Phase 3 — AI, Docker, Remember

- vendor-neutral interactive AI and review commands;
- Docker logs and shell selection;
- Obsidian note, daily, weekly, metadata-backed TODO, completion, and reopen commands;
- native `TODO.base` view over the TODO metadata model.

### Phase 4 — `0.3.0` preview hardening

- tests on macOS and Windows Git Bash;
- quoting and unusual-path fixtures;
- clearer diagnostics;
- documentation and shell completion;
- fail-closed AI review, shared sensitive-path filtering, and unborn-repository safety;
- immutable-pinned CI and versioned, checksummed release archives.

## 17. Risks

| Risk | Mitigation |
|---|---|
| Shell quoting differs across systems | Support macOS and Git Bash explicitly; add fixtures with spaces and non-ASCII characters. |
| AI vendors use different invocation syntax | Configure complete interactive and stdin commands instead of hard-coding providers. |
| Global Taskfile conflicts with an existing one | Installer refuses overwrite and prints a one-time flattened include; managed updates never require merging copied tasks. |
| Obsidian CLI version or PATH differs | `doctor` checks the CLI and Windows redirector; documentation states the minimum installer version. |
| Many TODO notes accumulate over time | Partition files by creation year/month and query canonical properties through a Base or CLI. |
| TODO metadata and tags drift apart | Keep status, priority, and project only as canonical properties; reserve tags for topics. |
| Too many wrappers create overhead | Apply the alias/function/task/script decision rule and keep the accepted command list small. |
| Context accidentally exposes secrets | Exclude environment and secret files; bound and preview context. |

## 18. Open questions

- Is native PowerShell support valuable enough for a later phase?
