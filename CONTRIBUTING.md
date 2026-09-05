# Contributing to Dev Harness

Thank you for helping improve Dev Harness. Contributions should keep the tool
small, portable, safe to run globally, and useful across many projects.

## Supported development environments

- macOS with the system Bash-compatible environment (Bash 3.2).
- Windows with Git Bash for runtime behavior and PowerShell for `install.ps1`.

Changes that affect either environment must preserve its documented behavior.

## Required tools

Install Bash, Task, Git, `fzf`, `rg`, and `grepai` before developing. Use Git Bash on Windows
when running the Bash test suites. PowerShell is required when changing or
checking the Windows installer.

## Development and verification

For every pull request, run:

```bash
bash tests/run.sh
```

Use test-driven development for behavior changes: first add or update a focused
test that describes the expected behavior, then implement the smallest change
that makes it pass. Keep regression coverage with the behavior it protects.

Write portable Bash 3.2: do not use Bash 4+ features such as associative arrays,
`mapfile`, or `globstar`; avoid platform-specific `sed`, `readlink`, and `date`
assumptions; and quote paths and shell variables carefully.

Dev Harness is a global, cross-project utility. Do not add project-specific
build, test, run, or release commands to `Taskfile.global.yml` or the installed
global command surface. Project-local automation belongs in the project that
owns it.

Tests must use isolated temporary fixtures. Never read or modify real secrets,
vaults, shell configuration files, home directories, personal Git repositories,
or other user data.

## Pull requests

Keep each pull request focused on one coherent change. Explain the user-visible
behavior, include tests for behavior changes, update documentation when the
contract changes, and describe macOS and Windows impact. Do not include
credentials, private source, or AI prompts containing private source material.
