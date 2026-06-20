# head - show first N lines
function head {
    param(
        [Parameter(Position=0)][string]$Path,
        [Alias('n')][int]$Lines = 10,
        [Parameter(ValueFromPipeline)][string]$InputObject
    )
    begin   { $buf = @() }
    process { if ($InputObject) { $buf += $InputObject } }
    end {
        if ($Path) { Get-Content $Path -TotalCount $Lines }
        else        { $buf | Select-Object -First $Lines }
    }
}

# tail - show last N lines; -f follows the file like tail -f
function tail {
    param(
        [Parameter(Position=0)][string]$Path,
        [Alias('n')][int]$Lines = 10,
        [Alias('f')][switch]$Follow,
        [Parameter(ValueFromPipeline)][string]$InputObject
    )
    begin   { $buf = @() }
    process { if ($InputObject) { $buf += $InputObject } }
    end {
        if ($Path) {
            if ($Follow) { Get-Content $Path -Tail $Lines -Wait }
            else          { Get-Content $Path -Tail $Lines }
        } else {
            $buf | Select-Object -Last $Lines
        }
    }
}

# touch - create file or update its last-write timestamp
function touch {
    param([Parameter(Mandatory, Position=0)][string[]]$Path)
    foreach ($p in $Path) {
        if (Test-Path $p) { (Get-Item $p).LastWriteTime = Get-Date }
        else               { New-Item -ItemType File -Path $p | Out-Null }
    }
}

# wc - line / word / character count
function wc {
    param(
        [Parameter(Position=0)][string]$Path,
        [Alias('l')][switch]$Lines,
        [Alias('w')][switch]$Words,
        [Alias('c')][switch]$Chars,
        [Parameter(ValueFromPipeline)][string]$InputObject
    )
    begin   { $buf = @() }
    process { if ($InputObject) { $buf += $InputObject } }
    end {
        $content = if ($Path) { Get-Content $Path } else { $buf }
        $lc = $content.Count
        $wc_ = ($content -join ' ' -split '\s+' | Where-Object { $_ }).Count
        $cc  = ($content -join "`n").Length
        if (-not ($Lines -or $Words -or $Chars)) {
            '{0,8}{1,8}{2,8}' -f $lc, $wc_, $cc
        } else {
            $out = @()
            if ($Lines) { $out += $lc }
            if ($Words) { $out += $wc_ }
            if ($Chars) { $out += $cc }
            $out -join '  '
        }
    }
}

# sed - stream editor; supports s<delim>pattern<delim>replacement<delim>[gi]
# Delimiter can be any single character, e.g. s/foo/bar/g or s|foo|bar|g
function sed {
    param(
        [Parameter(Mandatory, Position=0)][string]$Expression,
        [Parameter(Position=1)][string]$Path,
        [switch]$InPlace,
        [Parameter(ValueFromPipeline)][string]$InputObject
    )
    begin {
        $buf = @()
        if ($Expression -notmatch '^s(.)(.+)\1(.*)\1([gi]*)$') {
            throw "Unsupported expression. Syntax: s<delim>pattern<delim>replacement<delim>[gi]"
        }
        $flags  = $Matches[4]
        $rxOpts = [System.Text.RegularExpressions.RegexOptions]::None
        if ($flags -match 'i') { $rxOpts = $rxOpts -bor [System.Text.RegularExpressions.RegexOptions]::IgnoreCase }
        $rx     = [System.Text.RegularExpressions.Regex]::new($Matches[2], $rxOpts)
        $repl   = $Matches[3]
        $global = $flags -match 'g'
    }
    process { if ($InputObject) { $buf += $InputObject } }
    end {
        $lines  = if ($Path) { Get-Content $Path } else { $buf }
        $result = foreach ($line in $lines) {
            if ($global) { $rx.Replace($line, $repl) }
            else          { $rx.Replace($line, $repl, 1) }
        }
        if ($InPlace -and $Path) { $result | Set-Content $Path }
        else                      { $result }
    }
}

# grep - pattern search; wraps Select-String with Linux-like output
function grep {
    param(
        [Parameter(Mandatory, Position=0)][string]$Pattern,
        [Parameter(Position=1)][string[]]$Path,
        [Alias('i')][switch]$IgnoreCase,
        [Alias('r')][switch]$Recurse,
        [Alias('l')][switch]$FilesWithMatches,
        [Alias('v')][switch]$InvertMatch,
        [Alias('c')][switch]$Count,
        [Parameter(ValueFromPipeline)][string]$InputObject
    )
    begin   { $buf = @() }
    process { if ($InputObject) { $buf += $InputObject } }
    end {
        if ($InvertMatch) {
            $src = if ($Path) { $Path | ForEach-Object { Get-Content $_ } } else { $buf }
            $out = $src | Where-Object { $_ -notmatch $Pattern }
            if ($Count) { ($out | Measure-Object).Count } else { $out }
            return
        }

        $sslArgs = @{ Pattern = $Pattern; CaseSensitive = (-not $IgnoreCase) }
        if ($Recurse) { $sslArgs['Recurse'] = $true }

        $results = if ($Path) { Select-String -Path $Path @sslArgs }
                   else        { $buf | Select-String @sslArgs }

        if ($Count)            { ($results | Measure-Object).Count; return }
        if ($FilesWithMatches) { $results | Select-Object -ExpandProperty Path -Unique; return }

        $multiFile = $Path -and ($Recurse -or $Path.Count -gt 1)
        foreach ($m in $results) {
            if ($multiFile) { "$($m.Path):$($m.LineNumber):$($m.Line)" }
            else             { $m.Line }
        }
    }
}

# find - recursive file/directory search
# Usage: find [path] [-Name *.ps1] [-Type f|d] [-Mtime -7] [-Depth 2]
function find {
    param(
        [Parameter(Position=0)][string]$Path = '.',
        [string]$Name,
        [ValidateSet('f', 'd')][string]$Type,
        [int]$Mtime,
        [int]$Depth
    )
    $gciArgs = @{ Path = $Path; Recurse = $true; Force = $true; ErrorAction = 'SilentlyContinue' }
    if ($PSBoundParameters.ContainsKey('Depth')) { $gciArgs['Depth'] = $Depth }

    $items = Get-ChildItem @gciArgs
    if ($Type -eq 'f') { $items = $items | Where-Object { -not $_.PSIsContainer } }
    if ($Type -eq 'd') { $items = $items | Where-Object { $_.PSIsContainer } }
    if ($Name)         { $items = $items | Where-Object { $_.Name -like $Name } }
    if ($PSBoundParameters.ContainsKey('Mtime')) {
        $cutoff = (Get-Date).AddDays(-[Math]::Abs($Mtime))
        if ($Mtime -lt 0) { $items = $items | Where-Object { $_.LastWriteTime -ge $cutoff } }
        else               { $items = $items | Where-Object { $_.LastWriteTime -lt $cutoff } }
    }

    $items | ForEach-Object { $_.FullName }
}
