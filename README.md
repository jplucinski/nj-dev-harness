# Dev Harness

Dev Harness is a global Taskfile plus Bash utilities for repository navigation,
Git worktrees, AI context, Docker, and Obsidian. It runs on macOS and Windows
Git Bash. Build, test, run, deploy, and release commands stay in each project.

Version `0.3.0` is a preview. See [PRD.md](./PRD.md) for requirements,
[TUTORIAL.md](./TUTORIAL.md) for the tutorial, and the
[GitHub Pages site](https://jplucinski.github.io/nj-dev-harness/).
Site source lives in [`docs/site`](./docs/site).

## Quick start

```bash
gtask          # search the command palette
resume         # return to a recent project or worktree
dirty          # jump to a repository with unfinished changes
why            # explain the current repository context
focus          # jump to the project behind the next TODO
cproj          # choose a project and change directory
cwork          # change directory to DEV_WORKPLACE
cvault         # change directory to the Obsidian vault path
cwt            # choose a worktree and change directory
gtask review   # interactively select safe changes for AI review
gtask todo     # list open TODOs for the current project
```

Run `gtask help` for the command map.

## Scope

```text
Find       recent and dirty contexts, projects, files, repository text, priority TODOs
Do         timestamped worktrees, filtered handoffs, local standups, selective AI review
Remember   Obsidian notes, daily entries, weekly summaries, TODO
Validate   read-only installation and configuration checks
```

## Requirements

Required:

- Bash (macOS or Git Bash on Windows)
- [Task](https://taskfile.dev/)
- Git
- `fzf`
- `rg` (ripgrep)
- `grepai`

Optional feature dependencies:

- Ollama (needed for `gtask index` / `gtask semantic` embeddings)
- the VS Code CLI, Docker, the GitHub CLI, and Atuin
- `bat` for syntax-highlighted picker previews
- Obsidian 1.12.7+ with Command line interface and the Bases core plugin enabled
- any desired AI CLI for AI and review commands

No shipped command currently requires the GitHub CLI. `fzf` is required because
the default `gtask` command and interactive selectors use it. `rg` is required
because workplace file pickers and `gtask search` use it. `grepai` is required
because `gtask semantic` and `gtask index` use it. The installer never installs
third-party binaries.

## Try the interactive Docker demo

From an extracted release or source checkout:

```bash
docker build -f demo/Dockerfile -t dev-harness-demo .
docker run --rm -it dev-harness-demo
```

The container starts Bash in `payments-demo`, which contains one modified file
and one untracked file. Try `gtask`, `gtask open`, `gtask changed`,
`gtask search -- retry`, `gtask semantic -- retry`, `gtask index`, or
`gtask context`. Files open in `less`; press `q` to
return to the picker.

The command mounts no host directories and passes no credentials. VS Code,
Obsidian, Docker-in-Docker, and external AI CLIs are not connected. `exit` stops
the session; `--rm` removes the container.

## Install from a release archive or source checkout

Download a release archive and `SHA256SUMS`, verify it, and extract it. You can
also use a source checkout. Run the installer from that directory.

On macOS or in Git Bash:

```bash
./install.sh --configure-shell
```

From Windows PowerShell:

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1 --configure-shell
```

The installer validates Bash, Task, Git, `fzf`, and `rg` before writing anything. It then:

- installs versioned, managed files in `~/.dev-harness`;
- creates `~/.config/dev-harness/config.env` only when missing and preserves it on updates;
- creates a small `$HOME/Taskfile.yml` loader that points at the managed Taskfile;
- adds an identifiable block to `~/.bashrc` only with `--configure-shell`;
- warns about missing optional integrations and runs `doctor` after installation.

Updates replace the managed Taskfile without changing the loader:

```bash
./install.sh update
```

Preview any install, update, or removal without changing user files:

```bash
./install.sh --dry-run --configure-shell
./install.sh uninstall --dry-run
```

Uninstall removes only paths recorded in the installation manifest. It preserves
personal configuration, unknown files, notes, and the Obsidian vault:

```bash
./install.sh uninstall
```

To also remove known Dev Harness configuration files:

```bash
./install.sh uninstall --purge-config
```

Purge accepts only a directory named `dev-harness`. It removes `config.env`,
`Taskfile.yml`, and `palette.tsv`, leaving unknown files in place.

If a different global Taskfile already exists, the installer leaves it unchanged
and prints the include entry to add. It migrates an unchanged older Dev Harness
Taskfile automatically.

Without `--configure-shell`, add the printed source line to `~/.bashrc` yourself.
For the first run, restart the terminal, review
`~/.config/dev-harness/config.env`, and validate the installation with:

```bash
gtask doctor
```

## Usage

```bash
gtask                         # searchable palette with history recording
gtask help                    # workflow cheat sheet
gtask aliases                 # all aliases and fast paths
gtask extend                  # how to add personal commands
gtask --list                  # all global Task commands
cproj                         # select project and cd
oproj                         # select project and open DEV_EDITOR
cwork                         # cd to DEV_WORKPLACE
cvault                        # cd to DEV_OBSIDIAN_VAULT_PATH
.. / ... / ....               # cd up 1 / 2 / 3 directories
-                             # cd to the previous directory
ll / la                       # ls -lah / ls -A
mkcd DIR                      # mkdir -p DIR and cd into it
cwt                           # select worktree and cd
owt                           # select worktree and open DEV_EDITOR
resume                        # select recent project/worktree and cd
gtask resume                  # inspect recent contexts and choose an action
gr                            # cd to the current Git worktree root
dirty                         # select a dirty repository/worktree and cd
gtask dirty                   # select a dirty context and print its path
why                           # explain the current repository context
handoff --copy                # copy secret-filtered resume context
standup                       # print a local status
standup --copy                # copy that status
standup --day                 # append that status to today's Obsidian note
focus p0                      # select a P0 TODO and cd to its project
gtask focus -- p0             # select a P0 TODO and print the project path

gtask open                    # select a file below the current directory
gtask changed
gtask search -- OrderService
gtask semantic -- authentication
gtask index

gtask wt -- feature/my-change
gtask worktrees
gtask changes
gtask context
gtask context -- --all
gtask context -- --copy
gtask context -- --staged
gtask ai
gtask review
gtask review -- --all

gtask logs
gtask shell

gtask note -- "Retry design"
gtask day -- "Fixed payment timeout"
gtask week -- "Migration completed"
gtask todo -- "Check retry policy"
gtask todo -- p0 "Fix data leak"
gtask todo -- p1 "Check retry policy"
gtask todo -- p3 "Clean up test names"
gtask todo                         # list current-project TODOs
gtask todo -- p1                   # list current-project P1 TODOs
gtask todos                        # list TODOs from the entire vault
gtask todos -- p1                  # list P1 TODOs from the entire vault
gtask todos -- done                # list completed TODOs
gtask done                         # select and complete an open TODO
gtask done -- p0                   # complete a selected P0 TODO
gtask reopen                       # select and reopen a completed TODO
```

Project-specific operations remain local:

```bash
task test
task build
task run
```

Dev Harness does not define these tasks globally.

## Help and aliases

`gtask help` prints the command map. `gtask aliases` lists shell aliases,
directory-changing functions, and Task aliases. Both are available in the
`gtask` palette.

Short forms are available after installation:

```bash
gtask h       # gtask help
gtask aka     # gtask aliases
gtask ext     # gtask extend
gtask y       # gtask why
gtask hf      # gtask handoff
gtask stp     # gtask standup
gtask foc     # gtask focus
```

Selecting a command from the palette records its public form, for example
`gtask review`, in Bash history and `$HISTFILE`. With an active Atuin session,
it also records the directory, duration, and exit status. Direct commands use
the shell's normal history hooks.

History recording requires using the `gtask` shell function installed by `shell/dev-harness.bash`. Invoking `task -g` directly still opens the palette, but a child process cannot update its parent shell history.

## Workflow utilities

Shell fast paths:

```bash
gr                  # return to this worktree's root
dirty               # find unfinished work across DEV_WORKPLACE and linked worktrees
why                 # show branch, base, changes, commits, and the next project TODO
handoff --copy      # copy secret-filtered context
standup --day       # append a local status to today's native Obsidian Daily note
focus p1            # choose a P1 TODO and enter its project
```

`dirty` and `focus` use `fzf`. Enter changes directory when the shell fast path is
used; the corresponding `gtask dirty` and `gtask focus` commands print the path
because a child process cannot change its parent shell. Ctrl-O opens the selected
worktree in `DEV_EDITOR` or opens the selected TODO in Obsidian without changing
directory. `dirty` includes the current worktree, direct-child repositories under
`DEV_WORKPLACE`, and their linked worktrees, while excluding clean results.

`focus` reads open TODOs in P0 → P3 order. It prefers the current matching Git
project, otherwise resolves the TODO's project against direct children of
`DEV_WORKPLACE`. Missing and ambiguous matches fail closed; Ctrl-O remains
available for opening the TODO note itself.

These commands are read-only unless an action says otherwise. `handoff --copy`
and `standup --copy` are the only
clipboard actions, and `standup --day` is the only automatic Daily write in this
utility set. None of these commands invokes AI. Handoff paths and standup change
paths use the shared sensitive-path filter. Commit subjects and TODO titles are
user-authored text, so review a standup before copying or writing it to Daily.

## Extending Dev Harness

Dev Harness includes an optional personal Taskfile:

```text
~/.config/dev-harness/Taskfile.yml
```

Tasks are flattened into the global namespace. A `ports` task is invoked as
`gtask ports`. Custom tasks need unique names and must not define `default`.

To add a personal command to the searchable palette, add a tab-separated row to:

```text
~/.config/dev-harness/palette.tsv
```

```text
ports<TAB>show listening ports<TAB>network ports sockets
```

The third column holds hidden search terms. Built-in entries use the same
format.

Use an alias to shorten one command, a shell function for operations such as
`cd`, a global custom task for general utilities, and a script for multi-step
logic. Keep project-specific behavior in the local Taskfile. Run `gtask extend`
for examples.

## Pickers

Running `gtask` inside a repository shows its branch, staged/unstaged/untracked counts, and worktree count. Tasks that need a repository are hidden outside one.

`gtask open` recursively searches the current directory and works outside Git
repositories. File, search, project, worktree, and container pickers provide a
preview pane. Where relevant, the controls are:

```text
Tab      select multiple entries
Enter    primary action
Ctrl-O   open in DEV_EDITOR
Ctrl-Y   copy paths or generated context
Ctrl-A   analyze selected files with AI
Ctrl-R   review only selected changes
```

`gtask review` and `gtask context` let you select the included files. `Ctrl-A`
selects all files in the context picker. Untracked files that pass the sensitive
path filter contribute content up to `DEV_CONTEXT_MAX_LINES`. Repositories without
a first commit are supported.

The worktree picker supports:

```text
Enter    print/select worktree
Ctrl-O   open in DEV_EDITOR
Ctrl-Y   copy path
Ctrl-A   start configured AI inside the worktree
Ctrl-X   show status and ask before removal
```

### Resume

`resume` combines recent Atuin directories, the current repository, projects
under `DEV_WORKPLACE`, and linked worktrees. It also works without Atuin.

The preview calculates Git status, commits relative to the base, changed files,
and the highest-priority project TODO only for the highlighted entry.

```text
Enter    cd into the selected context (`resume`) or print its path (`gtask resume`)
Ctrl-O   open in DEV_EDITOR
Ctrl-Y   copy a compact, secret-filtered resume context
Ctrl-A   send resume context to the configured stdin-based AI command
Ctrl-R   review changes from the selected worktree
```

Atuin contributes only directory and relative time. Command text is not included
in resume context or sent to AI.

## AI adapters

Configure an interactive AI command and optional stdin commands for review and
resume:

```bash
export DEV_AI_COMMAND="codex"
export DEV_AI_REVIEW_COMMAND="codex exec -"
export DEV_AI_RESUME_COMMAND="codex exec -"
export DEV_CONTEXT_MAX_LINES="4000"
export DEV_RESUME_LIMIT="10"
```

These values are trusted shell commands. `DEV_AI_RESUME_COMMAND` falls back to
`DEV_AI_REVIEW_COMMAND`. Without a configured stdin command, Dev Harness prints
the prompt.

`gtask review` requires an interactive terminal and explicit `fzf` selection.
When interactive selection is unavailable, it exits with an error and does not
invoke `DEV_AI_REVIEW_COMMAND`. `gtask review -- --all` is the explicit
non-interactive consent path: it includes every changed path that survives the
sensitive-path policy. Use `--all` only after reviewing the repository state;
the filter removes common secret paths, but all remaining changed content may be
sent to the configured command.

## Obsidian

Enable **Settings → General → Command line interface** in Obsidian. On Windows the scripts prefer `Obsidian.com`, the official terminal redirector, when it is available.

Knowledge categories are rooted in the vault:

```text
Daily/
Weekly/
Notes/
TODO/
├── TODO.base
└── 2026/
    └── 08/
        └── 20260830-143012-retry-policy.md
```

Each TODO is a standalone Markdown note under `TODO/<year>/<month>/`. Its timestamped filename avoids collisions, while the file's properties are the source of truth:

```yaml
type: todo
title: Fix retry policy
status: open
priority: p1
project: payments
created: 2026-08-30T14:30:12+02:00
completed:
tags:
  - backend
```

`completed` is absent or empty while the TODO is open and is populated when the item is completed.

`status`, `priority`, and `project` are properties, not tags. Tags are reserved for themes such as `backend`, `security`, or `java`. TODO priorities are:

```text
P0  critical
P1  high
P2  medium (default)
P3  low
```

Change the default with `DEV_TODO_DEFAULT_PRIORITY`. Creating or listing project
TODOs requires a Git repository; its root name becomes `project`. TODOs also
record the branch, short commit SHA, and `[[Projects/<project>]]` link.

`gtask todo` lists open items for the current project, while `gtask todos` lists open items from the entire vault. Both accept an optional `p0`–`p3` filter and display results from highest to lowest priority. `gtask done` and `gtask reopen` use `fzf` and update `status`/`completed` in place, so note paths and links remain stable. Read commands never create or mutate notes.

The first TODO creation also creates `TODO/TODO.base` with native Open, Done, By project, and By priority views. Dev Harness queries this Base through the official Obsidian CLI and maintains no parallel index.

Configure Obsidian's Daily notes core plugin to store daily files under `Daily/`. Dev Harness uses the plugin's configured daily path instead of maintaining a competing daily-note convention.

## Contributing and project policies

Run the complete repository gate before proposing a change:

```bash
bash tests/run.sh
```

See the [contributing guide](./CONTRIBUTING.md), [MIT license](./LICENSE),
[security policy](./SECURITY.md), [code of conduct](./CODE_OF_CONDUCT.md), and
[changelog](./CHANGELOG.md).
