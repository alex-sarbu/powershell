# PowerShell profile loader - dot-source this file from $PROFILE.
# See setup/Install-Profile.ps1 for the one-time installer.

$ProfileDir            = $PSScriptRoot
$global:PSProfileDir   = $PSScriptRoot   # exposed so navigation helpers know where to write cd-aliases.ps1

. "$ProfileDir\unix-file.ps1"      # head, tail, touch, wc, sed, grep, find
. "$ProfileDir\unix-system.ps1"    # which, df, du, uptime, env, export, pkill, pgrep
. "$ProfileDir\unix-network.ps1"   # curl, wget, ifconfig, dig, ports
. "$ProfileDir\navigation.ps1"     # Quick-CdAlias, Remove-CdAlias, List-CdAliases, git wrapper

# Load persisted navigation aliases (file may not exist on a fresh install)
$cdAliasFile = Join-Path $ProfileDir "cd-aliases.ps1"
if (Test-Path $cdAliasFile) { . $cdAliasFile }

# ll / la - long listing including hidden items
function ll { Get-ChildItem -Force @args }
function la { Get-ChildItem -Force @args }

# mkcd - create a directory and immediately enter it
function mkcd {
    param([Parameter(Mandatory, Position=0)][string]$Path)
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
    Set-Location $Path
}

# path - print each PATH entry on its own line
function path {
    $env:PATH -split [System.IO.Path]::PathSeparator | Where-Object { $_ } | Sort-Object
}

# reload - re-source the active PowerShell profile
function reload { . $PROFILE }
