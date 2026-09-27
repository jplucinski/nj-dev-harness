# Required tools

Dev Harness does not install these binaries. Install them, open a new terminal, then run the harness installer.

Required on `PATH`: `bash`, `task`, `git`, `fzf`, `rg`.

macOS uses the system Bash (scripts stay compatible with Bash 3.2). Windows uses Git Bash from Git for Windows. PowerShell is only for `install.ps1`.

## macOS

From this checkout or a release archive:

```bash
./brew-macos.sh
```

That installs, with Homebrew:

- required: Git, Taskfile (`go-task` → `task`), `fzf`, `rg`
- from the README: `bat`, lazygit, lazydocker, k9s, GitHub CLI, Atuin, Ollama, `grepai`, VS Code (`code`), Docker Desktop, Obsidian
- Ghostty

System Bash stays in place. Scripts target Bash 3.2.

Afterward, in Obsidian: **Settings → General → Command line interface**, enable the Bases core plugin, and point Daily notes at `Daily/`. For semantic search: `ollama pull nomic-embed-text`, then `gtask index`.

## Windows

Git for Windows includes Git Bash. In PowerShell:

```powershell
winget install --id Git.Git -e --source winget
winget install --id Task.Task -e --source winget
winget install --id junegunn.fzf -e --source winget
winget install --id BurntSushi.ripgrep.MSVC -e --source winget
```

Chocolatey matches CI (`fzf`, `ripgrep`):

```powershell
choco install git go-task fzf ripgrep -y
```

Close PowerShell and open **Git Bash**. Harness commands run there, not in `cmd`.

## Check

```bash
bash --version
task --version
git --version
fzf --version
rg --version
```

Each command must resolve. Then, from a release archive or this checkout:

```bash
./install.sh --configure-shell
```

On Windows, from PowerShell in the same directory:

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1 --configure-shell
```

Restart the terminal and run `gtask doctor`.
