<#
.SYNOPSIS
    Wires up the custom PowerShell profile to load on every shell start.
.DESCRIPTION
    Adds a single dot-source line to $PROFILE.CurrentUserCurrentHost that
    loads setup\profile\profile.ps1 from this repo.  Safe to re-run —
    idempotent.
.NOTES
    After running, restart PowerShell or execute '. $PROFILE' to activate.
#>

$loaderPath = Join-Path $PSScriptRoot 'profile\profile.ps1'

if (-not (Test-Path $loaderPath)) {
    Write-Error "Profile loader not found: $loaderPath"
    exit 1
}

$targetProfile = $PROFILE.CurrentUserCurrentHost

if (-not (Test-Path $targetProfile)) {
    New-Item -Path $targetProfile -ItemType File -Force | Out-Null
    Write-Host "Created profile file: $targetProfile" -ForegroundColor Green
}

$existing = Get-Content $targetProfile -Raw -ErrorAction SilentlyContinue
$dotSource = ". `"$loaderPath`""

if ($existing -and $existing -match [regex]::Escape($loaderPath)) {
    Write-Host "Already installed in: $targetProfile" -ForegroundColor Yellow
} else {
    Add-Content -Path $targetProfile -Value "`n# Custom shell profile (loaded from repo)`n$dotSource"
    Write-Host "Installed into: $targetProfile" -ForegroundColor Green
    Write-Host "  $dotSource"                   -ForegroundColor Cyan
    Write-Host "`nRestart PowerShell or run '. `$PROFILE' to activate." -ForegroundColor Yellow
}
