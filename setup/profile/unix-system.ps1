# Private helper used by df and du
function Format-HumanBytes {
    param([long]$Bytes)
    if     ($Bytes -ge 1TB) { '{0:F1}T' -f ($Bytes / 1TB) }
    elseif ($Bytes -ge 1GB) { '{0:F1}G' -f ($Bytes / 1GB) }
    elseif ($Bytes -ge 1MB) { '{0:F1}M' -f ($Bytes / 1MB) }
    elseif ($Bytes -ge 1KB) { '{0:F1}K' -f ($Bytes / 1KB) }
    else                    { "${Bytes}B" }
}

# which — print the full path of a command
function which {
    param([Parameter(Mandatory, Position=0)][string]$Command)
    $cmd = Get-Command $Command -ErrorAction SilentlyContinue
    if ($cmd) { $cmd.Source }
    else       { Write-Error "which: $Command not found" }
}

# df — disk space for all FileSystem drives
# -h  human-readable sizes
function df {
    param([Alias('h')][switch]$HumanReadable)
    Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Root } |
    Select-Object `
        @{N='Filesystem'; E={ $_.Name }},
        @{N='Size';        E={ $s = $_.Used + $_.Free
                               if ($HumanReadable) { Format-HumanBytes $s } else { [long]($s / 1KB) } }},
        @{N='Used';        E={ if ($HumanReadable) { Format-HumanBytes $_.Used } else { [long]($_.Used / 1KB) } }},
        @{N='Avail';       E={ if ($HumanReadable) { Format-HumanBytes $_.Free } else { [long]($_.Free / 1KB) } }},
        @{N='Use%';        E={ $t = $_.Used + $_.Free
                               if ($t -gt 0) { '{0:P0}' -f ($_.Used / $t) } else { 'N/A' } }},
        @{N='Mounted on';  E={ $_.Root }}
}

# du — disk usage for a directory tree
# -h  human-readable sizes    -s  summary (total only)
function du {
    param(
        [Parameter(Position=0)][string]$Path = '.',
        [Alias('h')][switch]$HumanReadable,
        [Alias('s')][switch]$Summary
    )
    $resolved = (Resolve-Path $Path).Path

    $sizeOf = {
        param($p)
        $s = (Get-ChildItem -Path $p -Recurse -Force -ErrorAction SilentlyContinue |
              Measure-Object -Property Length -Sum).Sum
        if ($null -eq $s) { 0L } else { [long]$s }
    }

    $display = {
        param($bytes)
        if ($HumanReadable) { Format-HumanBytes $bytes } else { [long]($bytes / 1KB) }
    }

    if ($Summary) {
        "$(&$display (&$sizeOf $resolved))`t$resolved"
    } else {
        Get-ChildItem -Path $resolved -ErrorAction SilentlyContinue | ForEach-Object {
            $size = if ($_.PSIsContainer) { &$sizeOf $_.FullName } else { [long]$_.Length }
            "$(&$display $size)`t$($_.Name)"
        }
    }
}

# uptime — time since last boot
function uptime {
    $span = (Get-Date) - (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
    'up {0} days, {1:D2}:{2:D2}:{3:D2}' -f $span.Days, $span.Hours, $span.Minutes, $span.Seconds
}

# env — list all environment variables, or print one by name
function env {
    param([Parameter(Position=0)][string]$Name)
    if ($Name) { [System.Environment]::GetEnvironmentVariable($Name) }
    else        { Get-ChildItem Env: | Sort-Object Name | Format-Table -AutoSize }
}

# export — set an environment variable in the current session
# Usage: export NAME=VALUE
function export {
    param([Parameter(Mandatory, Position=0)][string]$Assignment)
    if ($Assignment -match '^([^=]+)=(.*)$') {
        Set-Item "Env:$($Matches[1])" $Matches[2]
    } else {
        Write-Error "export: usage: export NAME=VALUE"
    }
}

# pkill — kill all processes matching a name
function pkill {
    param([Parameter(Mandatory, Position=0)][string]$Name)
    $procs = Get-Process -Name $Name -ErrorAction SilentlyContinue
    if ($procs) { $procs | Stop-Process -Force }
    else         { Write-Warning "pkill: no process named '$Name'" }
}

# pgrep — list processes whose name matches a regex
function pgrep {
    param([Parameter(Mandatory, Position=0)][string]$Pattern)
    Get-Process | Where-Object { $_.Name -match $Pattern } |
        Select-Object Id, Name,
            @{N='CPU(s)'; E={ [math]::Round($_.CPU, 2) }},
            @{N='RSS(MB)'; E={ [math]::Round($_.WorkingSet64 / 1MB, 1) }}
}
