#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Windows 11 Dev VM Setup Script
.DESCRIPTION
    Installs and configures Git, VS Code, Azure CLI, Podman, and other
    essential tools for admin and development use.
    Requires: Windows 11, PowerShell 5.1+, winget available
.NOTES
    Run from an elevated PowerShell prompt:
        Set-ExecutionPolicy Bypass -Scope Process -Force
        .\dev-vm-setup.ps1
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------
#  Config
# ---------------------------------------------
$LOG_FILE  = "$env:USERPROFILE\dev-vm-setup.log"
$SEPARATOR = "=" * 60

# ---------------------------------------------
#  Logging helpers
# ---------------------------------------------
function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $ts   = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[$ts] [$Level] $Message"
    Add-Content -Path $LOG_FILE -Value $line
    switch ($Level) {
        'INFO'    { Write-Host $line -ForegroundColor Cyan    }
        'SUCCESS' { Write-Host $line -ForegroundColor Green   }
        'WARN'    { Write-Host $line -ForegroundColor Yellow  }
        'ERROR'   { Write-Host $line -ForegroundColor Red     }
        default   { Write-Host $line }
    }
}

function Write-Section {
    param([string]$Title)
    Write-Log $SEPARATOR
    Write-Log "  $Title"
    Write-Log $SEPARATOR
}

# ---------------------------------------------
#  Winget wrapper
# ---------------------------------------------
function Install-WithWinget {
    param(
        [string]$Id,
        [string]$Name,
        [string[]]$ExtraArgs = @()
    )
    Write-Log "Installing: $Name ($Id)"
    # Native commands never throw on a non-zero exit, so try/catch can't detect
    # winget failures. Build the args as an array and inspect $LASTEXITCODE.
    $wingetArgs = @(
        'install', '--id', $Id, '--exact',
        '--silent',
        '--accept-package-agreements',
        '--accept-source-agreements'
    ) + $ExtraArgs

    winget @wingetArgs | Out-Null
    $code = $LASTEXITCODE

    # 0 = installed. winget reports "already installed / no upgrade available"
    # with non-zero codes that vary by version, so treat any non-zero as a WARN
    # (not a false SUCCESS) and surface the exact code for diagnosis.
    if ($code -eq 0) {
        Write-Log "$Name installed successfully." 'SUCCESS'
    } else {
        Write-Log "$Name not installed (winget exit code $code - may already be present or up to date)." 'WARN'
    }
}

# ---------------------------------------------
#  Prerequisite checks
# ---------------------------------------------
Write-Section "Pre-flight Checks"

# Confirm elevation
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
        ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Log "Script must be run as Administrator. Exiting." 'ERROR'
    exit 1
}

# Confirm winget is available
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Log "winget not found. Install App Installer from the Microsoft Store and re-run." 'ERROR'
    exit 1
}

Write-Log "Running as Administrator: OK" 'SUCCESS'
Write-Log "winget available: OK"         'SUCCESS'

# ---------------------------------------------
#  1. Core Dev Tools
# ---------------------------------------------
Write-Section "Core Dev Tools"

Install-WithWinget 'Git.Git'               'Git for Windows'
Install-WithWinget 'Microsoft.VisualStudioCode' 'VS Code'
Install-WithWinget 'Microsoft.AzureCLI'    'Azure CLI'
Install-WithWinget 'RedHat.Podman'         'Podman'
Install-WithWinget 'RedHat.Podman-Desktop' 'Podman Desktop'

# ---------------------------------------------
#  2. Runtimes & SDKs
# ---------------------------------------------
Write-Section "Runtimes & SDKs"

Install-WithWinget 'Microsoft.DotNet.SDK.8'  '.NET 8 SDK'
Install-WithWinget 'OpenJS.NodeJS.LTS'        'Node.js LTS'
Install-WithWinget 'Python.Python.3.12'       'Python 3.12'
Install-WithWinget 'Microsoft.PowerShell'     'PowerShell 7 (pwsh)'

# ---------------------------------------------
#  3. Cloud & Infrastructure
# ---------------------------------------------
Write-Section "Cloud & Infrastructure"

Install-WithWinget 'Hashicorp.Terraform'         'Terraform'
Install-WithWinget 'Kubernetes.kubectl'           'kubectl'
Install-WithWinget 'Helm.Helm'                    'Helm'
Install-WithWinget 'Microsoft.AzureStorageExplorer' 'Azure Storage Explorer'

# ---------------------------------------------
#  4. Productivity & Utilities
# ---------------------------------------------
Write-Section "Productivity & Utilities"

Install-WithWinget 'Microsoft.WindowsTerminal'   'Windows Terminal'
Install-WithWinget 'JanDeDobbeleer.OhMyPosh'     'Oh My Posh'
Install-WithWinget 'Notepad++.Notepad++'          'Notepad++'
Install-WithWinget '7zip.7zip'                    '7-Zip'
Install-WithWinget 'WinSCP.WinSCP'                'WinSCP'
Install-WithWinget 'WiresharkFoundation.Wireshark' 'Wireshark'
Install-WithWinget 'Microsoft.Sysinternals'       'Sysinternals Suite'
Install-WithWinget 'Postman.Postman'              'Postman'

# ---------------------------------------------
#  5. Browsers
# ---------------------------------------------
Write-Section "Browsers"

Install-WithWinget 'Mozilla.Firefox'         'Firefox'
Install-WithWinget 'Google.Chrome'           'Chrome'

# ---------------------------------------------
#  6. VS Code Extensions
# ---------------------------------------------
Write-Section "VS Code Extensions"

# Refresh PATH so 'code' is available in this session
$env:Path = [System.Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
            [System.Environment]::GetEnvironmentVariable('Path', 'User')

$extensions = @(
    'ms-vscode.powershell'           # PowerShell
    'ms-azuretools.vscode-docker'    # Docker / Podman
    'ms-vscode-remote.remote-ssh'    # Remote SSH
    'ms-vscode-remote.remote-containers' # Dev Containers
    'ms-azure-devops.azure-pipelines' # Azure Pipelines
    'ms-azuretools.vscode-azureterraform' # Terraform
    'hashicorp.terraform'            # Terraform (HashiCorp official)
    'ms-kubernetes-tools.vscode-kubernetes-tools' # Kubernetes
    'github.copilot'                 # GitHub Copilot (requires licence)
    'eamodio.gitlens'                # GitLens
    'esbenp.prettier-vscode'         # Prettier
    'streetsidesoftware.code-spell-checker' # Spell checker
    'ms-vscode.azure-account'        # Azure Account
    'ms-azuretools.vscode-azureresourcegroups' # Azure Resources
)

if (Get-Command code -ErrorAction SilentlyContinue) {
    foreach ($ext in $extensions) {
        Write-Log "Installing VS Code extension: $ext"
        # 'code' is a native command: don't use 2>&1 (it turns stderr into
        # terminating errors under ErrorActionPreference=Stop) and don't rely
        # on catch - check the exit code instead.
        & code --install-extension $ext --force | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Log "$ext installed." 'SUCCESS'
        } else {
            Write-Log "Extension failed: $ext (exit code $LASTEXITCODE)." 'WARN'
        }
    }
} else {
    Write-Log "'code' command not found in PATH. Re-run after reboot to install extensions." 'WARN'
}

# ---------------------------------------------
#  7. Git Global Config
# ---------------------------------------------
Write-Section "Git Global Configuration"

# Refresh PATH again in case Git just installed
$env:Path = [System.Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
            [System.Environment]::GetEnvironmentVariable('Path', 'User')

if (Get-Command git -ErrorAction SilentlyContinue) {
    git config --global core.autocrlf  input
    git config --global core.editor    "code --wait"
    git config --global init.defaultBranch main
    git config --global pull.rebase    false
    git config --global credential.helper manager
    Write-Log "Git global config applied." 'SUCCESS'
    Write-Log "NOTE: Set your identity with:" 'WARN'
    Write-Log "  git config --global user.name  'Your Name'"  'WARN'
    Write-Log "  git config --global user.email 'you@example.com'" 'WARN'
} else {
    Write-Log "git not in PATH yet. Run git config after reboot." 'WARN'
}

# ---------------------------------------------
#  8. PowerShell Modules
# ---------------------------------------------
Write-Section "PowerShell Modules"

$psModules = @(
    'Az'                    # Azure PowerShell
    'PSReadLine'            # Better shell history/completion
    'posh-git'              # Git prompt integration
    'Terminal-Icons'        # File icons in terminal
    'ImportExcel'           # Excel without Excel
)

foreach ($mod in $psModules) {
    Write-Log "Installing PS module: $mod"
    try {
        Install-Module -Name $mod -Scope CurrentUser -Force -AllowClobber -SkipPublisherCheck
        Write-Log "$mod installed." 'SUCCESS'
    } catch {
        Write-Log "Module failed: ${mod}: $_" 'WARN'
    }
}

# ---------------------------------------------
#  9. Windows Features
# ---------------------------------------------
Write-Section "Windows Optional Features"

$features = @(
    'Microsoft-Hyper-V-All'       # Hyper-V (needed for some container scenarios)
    'Microsoft-Windows-Subsystem-Linux'  # WSL
    'VirtualMachinePlatform'      # WSL 2 backend
)

foreach ($feat in $features) {
    Write-Log "Enabling feature: $feat"
    try {
        $result = Enable-WindowsOptionalFeature -Online -FeatureName $feat -All -NoRestart -ErrorAction Stop
        if ($result.RestartNeeded) {
            Write-Log "$feat enabled - restart required." 'WARN'
        } else {
            Write-Log "$feat enabled." 'SUCCESS'
        }
    } catch {
        Write-Log "Feature failed (may already be enabled or unavailable in VM): ${feat}: $_" 'WARN'
    }
}

# ---------------------------------------------
#  10. WSL 2 Setup
# ---------------------------------------------
Write-Section "WSL 2 + Ubuntu"

try {
    wsl --install --distribution Ubuntu --no-launch | Out-Null
    wsl --set-default-version 2 | Out-Null
    Write-Log "WSL 2 with Ubuntu queued for install." 'SUCCESS'
    Write-Log "Ubuntu will finish setup on first launch after reboot." 'WARN'
} catch {
    Write-Log "WSL install failed (may require reboot first): $_" 'WARN'
}

# ---------------------------------------------
#  Done
# ---------------------------------------------
Write-Section "Setup Complete"
Write-Log "Log saved to: $LOG_FILE" 'SUCCESS'
Write-Log ""
Write-Log "NEXT STEPS:"
Write-Log "  1. Reboot to finalise WSL 2, Hyper-V, and PATH changes."
Write-Log "  2. Set git identity (see warnings above)."
Write-Log "  3. Run 'az login' to authenticate with Azure."
Write-Log "  4. Run 'podman machine init && podman machine start' for Podman."
Write-Log "  5. Open Windows Terminal and select Ubuntu to complete WSL setup."
Write-Log ""
Write-Log "Optional - re-run this script after reboot to install VS Code extensions"
Write-Log "if 'code' was not yet in PATH during first run."

# Bonus: Configure Podman for Hyper-V backend (better performance than WSL 2 on Windows 11)
New-Item -Path "$env:APPDATA\containers" -ItemType Directory -Force
@"
[machine]
provider = "hyperv"
"@ | Set-Content "$env:APPDATA\containers\containers.conf"
podman machine init --rootful --now

$reboot = Read-Host "`nReboot now to apply all changes? (y/N)"
if ($reboot -match '^[Yy]$') {
    Write-Log "Rebooting..." 'WARN'
    Restart-Computer -Force
}