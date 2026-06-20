# Internal helper - writes/updates one alias in cd-aliases.ps1 and defines it in the current session.
function Set-CdAlias {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Path
    )
    $aliasFile = Join-Path $global:PSProfileDir "cd-aliases.ps1"
    $funcName  = "$Name.home"
    $marker    = "# cd-alias:$funcName"
    $funcLine  = "function global:$funcName { Set-Location `"$Path`" }  $marker"

    if (-not (Test-Path $aliasFile)) {
        "# Navigation aliases - managed by Quick-CdAlias. Do not edit by hand." |
            Set-Content $aliasFile
    }

    # Remove stale entry for this name (if any), then append the updated one
    $lines = @(Get-Content $aliasFile | Where-Object { $_ -notmatch [regex]::Escape($marker) })
    ($lines + $funcLine) | Set-Content $aliasFile

    # Define immediately so the alias is usable without reloading the profile
    Invoke-Expression "function global:$funcName { Set-Location `"$Path`" }"
}

# Quick-CdAlias <name>
# Persistently add a navigation alias for the current directory.
# Creates <name>.home that cd's back here from anywhere.
function Quick-CdAlias {
    param([Parameter(Mandatory, Position=0)][string]$Name)

    if (-not $global:PSProfileDir) {
        Write-Error "PSProfileDir not set - make sure the profile is loaded."
        return
    }

    $path = (Get-Location).Path
    Set-CdAlias -Name $Name -Path $path
    Write-Host "Added:  $Name.home  ->  $path" -ForegroundColor Green
    Write-Host "(active now; persists across sessions)" -ForegroundColor DarkGray
}

# Remove-CdAlias <name>
# Remove a navigation alias by name (without the .home suffix).
function Remove-CdAlias {
    param([Parameter(Mandatory, Position=0)][string]$Name)

    $aliasFile = Join-Path $global:PSProfileDir "cd-aliases.ps1"
    $funcName  = "$Name.home"
    $marker    = "# cd-alias:$funcName"

    if (-not (Test-Path $aliasFile)) { Write-Warning "No aliases file found."; return }

    $before = @(Get-Content $aliasFile)
    $after  = @($before | Where-Object { $_ -notmatch [regex]::Escape($marker) })

    if ($before.Count -eq $after.Count) {
        Write-Warning "Alias not found: $funcName"
    } else {
        $after | Set-Content $aliasFile
        Remove-Item "Function:$funcName" -ErrorAction SilentlyContinue
        Write-Host "Removed: $funcName" -ForegroundColor Yellow
    }
}

# List-CdAliases
# Show all registered navigation aliases and their target paths.
function List-CdAliases {
    $aliasFile = Join-Path $global:PSProfileDir "cd-aliases.ps1"
    if (-not (Test-Path $aliasFile)) { Write-Host "No navigation aliases defined yet."; return }

    $results = Get-Content $aliasFile | ForEach-Object {
        if ($_ -match 'function global:(.+) \{ Set-Location "(.+)" \}') {
            [PSCustomObject]@{ Alias = $Matches[1]; Path = $Matches[2] }
        }
    }

    if ($results) { $results | Format-Table -AutoSize }
    else           { Write-Host "No navigation aliases defined yet." }
}

# git wrapper - transparent pass-through to git.exe.
# After a successful clone, auto-registers a <reponame>.home navigation alias.
function git {
    # Snapshot current subdirectories so we can detect what clone created
    $dirsBefore = @(Get-ChildItem -Directory -ErrorAction SilentlyContinue |
                    Select-Object -ExpandProperty Name)

    git.exe @args

    if ($args.Count -ge 2 -and $args[0] -eq 'clone' -and $LASTEXITCODE -eq 0) {
        $dirsAfter = @(Get-ChildItem -Directory -ErrorAction SilentlyContinue |
                       Select-Object -ExpandProperty Name)
        $newDirs   = @($dirsAfter | Where-Object { $dirsBefore -notcontains $_ })

        if ($newDirs.Count -eq 1) {
            $dir     = $newDirs[0]
            $absPath = Join-Path (Get-Location).Path $dir
            Set-CdAlias -Name $dir -Path $absPath
            Write-Host "  [nav] $dir.home -> $absPath" -ForegroundColor DarkCyan
        }
    }
}
