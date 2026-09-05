[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]] $InstallerArguments
)

$ErrorActionPreference = 'Stop'

function Find-GitBash {
    $gitCommand = Get-Command git.exe -ErrorAction SilentlyContinue
    if ($gitCommand) {
        $gitRoot = Split-Path (Split-Path $gitCommand.Source -Parent) -Parent
        $candidate = Join-Path $gitRoot 'bin\bash.exe'
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return $candidate
        }
    }

    $knownCandidates = @(
        (Join-Path $env:ProgramFiles 'Git\bin\bash.exe'),
        $(if (${env:ProgramFiles(x86)}) { Join-Path ${env:ProgramFiles(x86)} 'Git\bin\bash.exe' }),
        $(if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'Programs\Git\bin\bash.exe' })
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) }

    if ($knownCandidates.Count -gt 0) {
        return $knownCandidates[0]
    }

    throw 'Git Bash was not found. Install Git for Windows and try again.'
}

$bashPath = Find-GitBash
$windowsScriptPath = Join-Path $PSScriptRoot 'install.sh'
if (-not (Test-Path -LiteralPath $windowsScriptPath -PathType Leaf)) {
    throw "Installer not found: $windowsScriptPath"
}

$unixScriptPath = (& $bashPath -lc 'cygpath -u "$1"' -- $windowsScriptPath).Trim()
if ($LASTEXITCODE -ne 0 -or -not $unixScriptPath) {
    throw 'Git Bash could not resolve the installer path.'
}

$bashArguments = @($unixScriptPath) + $InstallerArguments
& $bashPath -lc 'exec "$@"' -- @bashArguments
exit $LASTEXITCODE
