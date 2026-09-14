# Dev Harness: tutorial

Install Dev Harness, pick a project, create a worktree, build AI context, and
keep notes and TODOs in Obsidian.

> Dev Harness ships general developer tools. Build, test, run, deploy, and
> release stay in each project's local `Taskfile.yml`.

## 1. Requirements

Required:

- Bash — system Bash on macOS, or Git Bash on Windows
- [Task](https://taskfile.dev/)
- Git
- `fzf`
- `rg` (ripgrep)
- `grepai`

Optional:

- Ollama for local embeddings used by `gtask index` / `gtask semantic`
- VS Code with `code` on `PATH`
- Atuin for a richer recent-context list
- Obsidian 1.12.7+ with CLI and Bases enabled
- an AI CLI such as Codex, Claude, Gemini, Copilot CLI, or OpenCode
- Docker, if you want `gtask logs` and `gtask shell`

## Demo without installing — Docker

From an extracted release or source checkout:

```bash
docker build -f demo/Dockerfile -t dev-harness-demo .
docker run --rm -it dev-harness-demo
```

The container starts Bash in `payments-demo` with one modified file and one
untracked file:

```bash
gtask
gtask open
gtask changed
gtask search -- retry
gtask semantic -- retry
gtask index
gtask changes
gtask context
why
```

In the demo, files open in `less`; press `q` to return to the picker.
The container mounts no host directories and receives no secrets. VS Code,
Obsidian, Docker-in-Docker, and external AI CLIs are not connected.
`exit` ends the session; `--rm` removes the container.

## 2. Install Dev Harness

Run the installer from the source checkout or extracted release.

### macOS or Git Bash

```bash
./install.sh --configure-shell
```

### Windows PowerShell

PowerShell runs the installer in Git Bash:

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1 --configure-shell
```

The installer checks required tools before writing files. Managed files go to
`~/.dev-harness`, configuration to `~/.config/dev-harness`, and
`--configure-shell` appends a marked block to `~/.bashrc`.

Restart the terminal or reload:

```bash
source ~/.bashrc
```

## 3. Configure the workplace

`DEV_WORKPLACE` is the directory that holds your Git projects. Example layout:

```text
~/Workplace/
├── payments/
├── orders/
└── notifications/
```

Open:

```text
~/.config/dev-harness/config.env
```

Minimum:

```bash
export DEV_WORKPLACE="$HOME/Workplace"
export DEV_EDITOR="code"
```

A fuller example:

```bash
export DEV_WORKPLACE="$HOME/Workplace"
export DEV_EDITOR="code"

# Optional shared worktree directory. If unset, Dev Harness uses a sibling
# .worktrees directory next to the repository.
# export DEV_WORKTREE_ROOT="$HOME/Worktrees"

# Empty value means the active Obsidian vault.
export DEV_OBSIDIAN_VAULT=""

# Vault directory used by the cvault shortcut.
# export DEV_OBSIDIAN_VAULT_PATH="$HOME/Documents/Obsidian/My Vault"

export DEV_AI_COMMAND="codex"
export DEV_AI_REVIEW_COMMAND="codex exec -"
export DEV_AI_RESUME_COMMAND="codex exec -"

export DEV_CONTEXT_MAX_LINES="4000"
export DEV_RESUME_LIMIT="10"
export DEV_TODO_DEFAULT_PRIORITY="p2"

# Set this if Git cannot detect the main branch.
# export DEV_MAIN_BRANCH="main"
```

After changing config, open a new terminal or run `source ~/.bashrc` again.

## 4. Check the install

```bash
gtask doctor
```

Default mode reports errors separately from missing optional integrations.
`--all` also treats missing optional tools as errors:

```bash
gtask doctor -- --all
```

Help commands:

```bash
gtask help
gtask aliases
gtask --list
```

## 5. Find — locate work context

### Command palette

`gtask` with no arguments opens the `fzf` palette:

```bash
gtask
```

Type part of a command name or description, for example `project`, `file`,
`note`, or `todo`. The chosen command is written to Bash history, and to Atuin
history when Atuin is active.

### Pick a project

```bash
cproj    # select a project and cd into it
oproj    # select a project and open it in DEV_EDITOR
cwork    # cd to DEV_WORKPLACE
cvault   # cd to DEV_OBSIDIAN_VAULT_PATH
```

`cproj` and `oproj` list directories directly under `DEV_WORKPLACE`.

### Return to recent work

```bash
resume
```

The list includes projects, worktrees, and Atuin history directories when
available. Preview shows the branch, changes relative to the base, and the
highest-priority TODO.

`resume` picker keys:

```text
Enter    cd to the selected directory
Ctrl-O   open in DEV_EDITOR
Ctrl-Y   copy resume context
Ctrl-A   send context to the configured AI
Ctrl-R   start a worktree change review
```

The Task variant prints the selected path; it cannot change the parent
process directory:

```bash
gtask resume
```

### Fast paths and handoff

```bash
gr                  # cd to the current worktree root
dirty               # jump to a repository with unfinished changes
why                 # show branch, base, changes, commits, and next TODO
focus p0            # pick the highest-priority TODO and cd to its project
handoff --copy      # copy secret-filtered context
standup --day       # append local status to today's Daily note
```

In the `dirty` and `focus` pickers, Enter changes directory only for the shell
function. `gtask dirty` and `gtask focus -- p0` print the path because a child
process cannot change the terminal directory. Ctrl-O opens the worktree in
`DEV_EDITOR` or the TODO note in Obsidian.

`focus` does not guess the project. It checks the current repository first,
then direct children of `DEV_WORKPLACE`. No match or multiple matches fail with
an error. You can still open the TODO with Ctrl-O.

Default modes write nothing. `handoff --copy` and `standup --copy` use the
clipboard. `standup --day` is the only automatic Daily write in this set.
None of these commands start AI. Commit subjects and TODO titles are your
text; read the report before copying or saving it.

### Find a file or symbol

```bash
gtask open
gtask changed
gtask search -- OrderService
gtask semantic -- authentication
gtask index
```

`gtask open` searches recursively from the current directory and does not
require Git. `gtask changed` also works in a repository with no first commit.
Pickers can open a result in the editor or send selected files to AI.

## 6. Do — work in an isolated worktree

Go to the base repository and create a worktree:

```bash
cd "$DEV_WORKPLACE/payments"
gtask wt -- feature/retry-policy
```

The path includes a date and time. If that path already exists, a numeric
suffix is added.

Find the worktree:

```bash
gtask worktrees
cwt     # select and cd
owt     # select and open in DEV_EDITOR
```

Worktree picker keys:

```text
Enter    select the path
Ctrl-O   open in DEV_EDITOR
Ctrl-Y   copy the path
Ctrl-A   start AI inside the worktree
Ctrl-X   status, then confirmed delete
```

## 7. Build filtered AI context

Summarize and select context:

```bash
gtask changes
gtask context
```

`gtask context` lets you pick files. Variants:

```bash
gtask context -- --all
gtask context -- --staged
gtask context -- --copy
```

Context includes a bounded diff and repository info. Common secrets — `.env`,
private keys, `.ssh`, keystores, and `credentials*` / `secrets*` trees — are
dropped by the shared path filter.

> The filter reduces risk; it does not replace a human check. Review the
> selected paths before sending them to an external model.

### Interactive review

```bash
gtask review
```

`fzf` selects files. Without an interactive terminal the command fails and
does not start AI.

### Review every path that passed the filter

```bash
gtask review -- --all
```

`--all` is an explicit opt-in for every remaining change. Use it after
`git status` and `gtask changes`.

If `DEV_AI_REVIEW_COMMAND` is unset, Dev Harness prints the prompt locally
instead of sending it to an AI process.

## 8. Remember — notes

Notes land in three directories:

```text
Notes/    ordinary notes
Daily/    what happened today
Weekly/   weekly summaries
```

### Ordinary note

```bash
gtask note -- "Idea for simplifying the retry policy"
```

The note is created under `Notes/`. Run from a repository and it also gets
project metadata from the Git root directory name.

### Daily entry

```bash
gtask day -- "Fixed the payment timeout and added a regression test"
```

Text is appended to today's note. Point Obsidian's Daily notes plugin at
`Daily/`.

### Weekly summary

```bash
gtask week -- "Finished the payments migration; production monitoring remains"
```

Weekly entries live under `Weekly/`.

### Tags and properties

A tag names a topic, not work status. Useful tags:

```text
java
security
backend
kafka
architecture
```

`project`, `status`, `priority`, `created`, and `completed` are Obsidian
properties. Do not duplicate them as tags. Bases can then filter on stable
fields, and tags stay topical.

## 9. TODO — one task, one file

TODOs are global Markdown notes under:

```text
TODO/<year>/<month>/<timestamp>-<slug>.md
```

Creating a TODO requires a Git repository; the root name becomes `project`.

```bash
gtask todo -- "Check retry policy"          # P2 by default
gtask todo -- p0 "Fix data leak"
gtask todo -- p1 "Prepare migration plan"
gtask todo -- p3 "Clean up test names"
```

Priorities:

```text
P0  critical
P1  high
P2  medium — default
P3  low
```

List the current project:

```bash
gtask todo
gtask todo -- p1
```

List the whole vault:

```bash
gtask todos
gtask todos -- p0
gtask todos -- done
```

Complete or reopen:

```bash
gtask done
gtask done -- p0
gtask reopen
```

The picker selects an existing note. Only `status` and `completed` change; the
path stays the same, so Obsidian links remain valid.

Example TODO properties:

```yaml
type: todo
title: Fix retry policy
status: open
priority: p1
project: payments
created: 2026-09-03T10:30:00+02:00
completed:
tags:
  - backend
  - resilience
```

## 10. Example workday

```bash
# Find the project
cproj

# Isolated task environment
gtask wt -- feature/retry-policy
cwt

# Project-local commands
task test

# Inspect the change set and review selected files
gtask changes
gtask review

# Record the day and the next action
gtask day -- "Added retry with backoff and a timeout-scenario test"
gtask todo -- p1 "Check retry metrics in the test environment"

# Next day, one command back
dirty
why
focus p1
```

## 11. Add a personal global tool

Do not edit `~/.dev-harness`; an update may replace managed files. Add a
personal task to:

```text
~/.config/dev-harness/Taskfile.yml
```

Example:

```yaml
version: '3'

tasks:
  ports:
    desc: Show listening ports
    dir: '{{.USER_WORKING_DIR}}'
    cmds:
      - your-command-here
```

Run it:

```bash
gtask ports
```

To show it in the palette, add a tab-separated row to:

```text
~/.config/dev-harness/palette.tsv
```

```text
ports<TAB>show listening ports<TAB>network ports sockets
```

Pick the extension type by what it does:

- alias — shorten one command
- Bash function — the operation must change the current shell, for example `cd`
- global task — a general, discoverable tool
- script — multi-step logic
- project Taskfile — build, test, run, deploy, and release

Show the built-in guide:

```bash
gtask extend
```

## 12. Update, diagnose, uninstall

Update from a new source directory or release:

```bash
./install.sh update
```

Preview without writing:

```bash
./install.sh --dry-run --configure-shell
./install.sh uninstall --dry-run
```

Uninstall removes only files recorded in the install manifest:

```bash
./install.sh uninstall
```

Also remove known personal config files:

```bash
./install.sh uninstall --purge-config
```

Unknown files in the config directory, notes, and the Obsidian vault stay.

## Cheat sheet

```bash
gtask                    # palette
gtask help               # workflow map
gtask aliases            # aliases
resume                   # return to recent work
gr                       # current repository root
.. / ... / ....          # up one or more directories
-                        # previous directory
ll / la                  # listing
mkcd DIR                 # create a directory and cd into it
dirty                    # jump to a dirty repository
why                      # explain current context
handoff --copy           # copy filtered handoff context
standup / standup --copy # show / copy status
standup --day            # append status to Daily
focus p0                 # pick a TODO and cd to its project
cproj / oproj            # project: cd / editor
cwork / cvault           # workplace / vault
cwt / owt                # worktree: cd / editor
gtask open               # pick a file under the current directory
gtask changed            # pick a changed file
gtask search -- TEXT     # search DEV_WORKPLACE
gtask semantic -- TEXT   # search by meaning
gtask index              # build the semantic index
gtask wt -- BRANCH       # create a worktree
gtask context            # pick local context
gtask review             # interactive AI review
gtask review -- --all    # every remaining filtered change
gtask note -- TITLE      # ordinary note
gtask day -- TEXT        # daily entry
gtask week -- TEXT       # weekly entry
gtask todo -- p1 TEXT    # new TODO
gtask todo               # project TODOs
gtask todos              # vault TODOs
gtask done / reopen      # complete / reopen
gtask doctor             # diagnostics
```
