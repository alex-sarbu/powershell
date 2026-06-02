<#
.SYNOPSIS
Decode HTTP request/response payloads from an Apache HttpClient wire-log dump.

.DESCRIPTION
Parses lines of the form
    ... DEBUG wire - http-outgoing-N >> "..."   (request bytes)
    ... DEBUG wire - http-outgoing-N << "..."   (response bytes)
where binary bytes are encoded as [0xHH] and CR/LF/TAB as [\r] [\n] [\t].

For every HTTP message on every connection it:
  1. Reassembles the raw bytes.
  2. Splits headers from body at the first CRLF CRLF.
  3. Decodes Transfer-Encoding: chunked.
  4. Decompresses Content-Encoding: gzip or deflate.
  5. Writes <seq>_conn<N>_<req|resp>_<first-line>.headers.txt and .body.bin
     into the output directory.
cd
Note: GZIP compressed payloads can be identified by the first two bytes 0x1F 0x8B ([0x1f][0x8b]). Deflate streams are trickier since raw deflate and zlib-wrapped deflate have the same prefix bytes. The script tries raw first, then retries skipping a 2-byte zlib header if the first attempt fails.

.PARAMETER InputPath
Path to the wire log. Defaults to .\appd-trace-log.txt in the script's folder.

.PARAMETER OutputDir
Where to drop decoded files. Defaults to .\decoded.
#>

[CmdletBinding()]
param(
    [string]$InputPath = (Join-Path $PSScriptRoot 'appd-trace-log.txt'),
    [string]$OutputDir = (Join-Path $PSScriptRoot 'decoded')
)

# Resolve to absolute paths before any .NET calls
$InputPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($InputPath)
$OutputDir = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputDir)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $InputPath)) { throw "Input file not found: $InputPath" }
if (-not (Test-Path $OutputDir)) { New-Item -ItemType Directory -Path $OutputDir | Out-Null }

# ---------- helpers ----------

$script:WireEscapeRegex = [regex]'\G\[(?:\\r|\\n|\\t|0x([0-9A-Fa-f]{1,2}))\]'

function ConvertFrom-WireString {
    param([string]$Text)
    $out = New-Object System.Collections.Generic.List[byte]
    $i = 0
    $len = $Text.Length
    while ($i -lt $len) {
        $c = $Text[$i]
        if ($c -eq '[') {
            $m = $script:WireEscapeRegex.Match($Text, $i)
            if ($m.Success -and $m.Index -eq $i) {
                $inner = $Text.Substring($i + 1, $m.Length - 2)
                switch -CaseSensitive ($inner) {
                    '\r' { $out.Add(0x0D); break }
                    '\n' { $out.Add(0x0A); break }
                    '\t' { $out.Add(0x09); break }
                    default {
                        # 0xH or 0xHH
                        $out.Add([byte][Convert]::ToInt32($m.Groups[1].Value, 16))
                    }
                }
                $i += $m.Length
                continue
            }
            # Not a recognized escape — emit literal '[' and advance one char
            $out.Add([byte]0x5B)
            $i++
        } else {
            $out.Add([byte][char]$c)
            $i++
        }
    }
    return ,$out.ToArray()
}

function Get-HeaderBodySplit {
    param([byte[]]$Data)
    for ($i = 0; $i -le $Data.Length - 4; $i++) {
        if ($Data[$i] -eq 0x0D -and $Data[$i+1] -eq 0x0A -and
            $Data[$i+2] -eq 0x0D -and $Data[$i+3] -eq 0x0A) {
            return $i
        }
    }
    return -1
}

function Convert-FromChunked {
    param([byte[]]$Data)
    $ms = New-Object System.IO.MemoryStream
    $pos = 0
    while ($pos -lt $Data.Length) {
        # Read chunk-size line up to CRLF
        $eol = -1
        for ($j = $pos; $j -lt $Data.Length - 1; $j++) {
            if ($Data[$j] -eq 0x0D -and $Data[$j+1] -eq 0x0A) { $eol = $j; break }
        }
        if ($eol -lt 0) { break }
        $sizeLine = [System.Text.Encoding]::ASCII.GetString($Data, $pos, $eol - $pos)
        # strip chunk extensions after ';'
        $sizeHex = ($sizeLine -split ';')[0].Trim()
        if ([string]::IsNullOrEmpty($sizeHex)) { break }
        try { $size = [Convert]::ToInt32($sizeHex, 16) } catch { break }
        $pos = $eol + 2
        if ($size -eq 0) { break }
        if ($pos + $size -gt $Data.Length) {
            # truncated chunk - take what we have
            $ms.Write($Data, $pos, $Data.Length - $pos)
            break
        }
        $ms.Write($Data, $pos, $size)
        $pos += $size
        # skip trailing CRLF after chunk
        if ($pos + 1 -lt $Data.Length -and $Data[$pos] -eq 0x0D -and $Data[$pos+1] -eq 0x0A) {
            $pos += 2
        }
    }
    return ,$ms.ToArray()
}

function Expand-GzipBytes {
    param([byte[]]$Data)
    $in  = New-Object System.IO.MemoryStream(,$Data)
    $gz  = New-Object System.IO.Compression.GZipStream($in, [System.IO.Compression.CompressionMode]::Decompress)
    $out = New-Object System.IO.MemoryStream
    try { $gz.CopyTo($out) } finally { $gz.Dispose(); $in.Dispose() }
    return ,$out.ToArray()
}

function Expand-DeflateBytes {
    param([byte[]]$Data)
    # HTTP "deflate" is usually zlib-wrapped (RFC 1950). Try raw first, then skip 2-byte zlib header.
    foreach ($skip in 0, 2) {
        try {
            if ($skip -eq 0) {
                $slice = $Data
            } else {
                $slice = New-Object byte[] ($Data.Length - $skip)
                [Array]::Copy($Data, $skip, $slice, 0, $slice.Length)
            }
            $in  = New-Object System.IO.MemoryStream(,$slice)
            $df  = New-Object System.IO.Compression.DeflateStream($in, [System.IO.Compression.CompressionMode]::Decompress)
            $out = New-Object System.IO.MemoryStream
            $df.CopyTo($out); $df.Dispose(); $in.Dispose()
            return ,$out.ToArray()
        } catch { }
    }
    throw "Could not inflate deflate stream."
}

function Get-SafeFileNamePart {
    param([string]$Text, [int]$Max = 60)
    $s = ($Text -replace '[^A-Za-z0-9._-]', '_')
    if ($s.Length -gt $Max) { $s = $s.Substring(0, $Max) }
    return $s
}

# ---------- state ----------

$wireRegex = [regex]'http-outgoing-(\d+)\s+(>>|<<)\s+"(.*)"\s*$'
$active = @{}   # key "connId:dir" -> List[byte]
$script:msgIndex = 0
$summary = New-Object System.Collections.Generic.List[object]

function Save-Message {
    param([string]$Key, $Buffer)
    if ($null -eq $Buffer -or $Buffer.Count -eq 0) { return }
    $data = $Buffer.ToArray()

    $sep = Get-HeaderBodySplit -Data $data
    if ($sep -lt 0) {
        Write-Warning "Skipping $Key - no header/body separator."
        return
    }
    $headerBytes = New-Object byte[] $sep
    [Array]::Copy($data, 0, $headerBytes, 0, $sep)
    $bodyLen = $data.Length - ($sep + 4)
    if ($bodyLen -lt 0) { $bodyLen = 0 }
    $bodyBytes = New-Object byte[] $bodyLen
    if ($bodyLen -gt 0) {
        [Array]::Copy($data, $sep + 4, $bodyBytes, 0, $bodyLen)
    }
    $headers = [System.Text.Encoding]::ASCII.GetString($headerBytes)

    $isChunked = $headers -match '(?im)^Transfer-Encoding:\s*chunked'
    $contentEncoding = $null
    if ($headers -match '(?im)^Content-Encoding:\s*(\S+)') { $contentEncoding = $Matches[1].ToLower() }

    $rawBody = $bodyBytes
    if ($isChunked -and $bodyBytes.Length -gt 0) {
        try { $bodyBytes = Convert-FromChunked -Data $bodyBytes }
        catch { Write-Warning "Dechunk failed for $Key - keeping raw body. $_" }
    }

    $decodeNote = ''
    if ($contentEncoding -eq 'gzip') {
        try { $bodyBytes = Expand-GzipBytes -Data $bodyBytes; $decodeNote = 'gunzipped' }
        catch { Write-Warning "Gunzip failed for $Key - keeping compressed body. $_" ; $decodeNote = 'gzip-FAILED' }
    } elseif ($contentEncoding -eq 'deflate') {
        try { $bodyBytes = Expand-DeflateBytes -Data $bodyBytes; $decodeNote = 'inflated' }
        catch { Write-Warning "Inflate failed for $Key. $_" ; $decodeNote = 'deflate-FAILED' }
    }

    $firstLine = ($headers -split "`r`n")[0]
    $parts = $Key -split ':'
    $connId = $parts[0]
    $dir = if ($parts[1] -eq '>>') { 'req' } else { 'resp' }

    $script:msgIndex++
    $safe = Get-SafeFileNamePart -Text $firstLine
    $base = '{0:D4}_conn{1}_{2}_{3}' -f $script:msgIndex, $connId, $dir, $safe

    [System.IO.File]::WriteAllBytes((Join-Path $OutputDir "$base.headers.txt"), $headerBytes)
    [System.IO.File]::WriteAllBytes((Join-Path $OutputDir "$base.body.bin"), $bodyBytes)

    $summary.Add([pscustomobject]@{
        Seq             = $script:msgIndex
        Connection      = $connId
        Direction       = $dir
        FirstLine       = $firstLine
        Chunked         = [bool]$isChunked
        ContentEncoding = $contentEncoding
        BodyBytes       = $bodyBytes.Length
        Note            = $decodeNote
        File            = "$base.body.bin"
    })
}

# ---------- main loop ----------

Write-Host "Reading $InputPath ..."
$reader = [System.IO.File]::OpenText($InputPath)
try {
    while ($null -ne ($line = $reader.ReadLine())) {
        $m = $wireRegex.Match($line)
        if (-not $m.Success) { continue }

        $connId = $m.Groups[1].Value
        $direction = $m.Groups[2].Value
        $content = $m.Groups[3].Value
        $key = "${connId}:${direction}"

        # Detect message start
        $startsNew = $false
        if ($direction -eq '<<' -and $content -match '^HTTP/\d') { $startsNew = $true }
        elseif ($direction -eq '>>' -and $content -match '^(GET|POST|PUT|DELETE|HEAD|OPTIONS|PATCH|CONNECT|TRACE) ') { $startsNew = $true }

        if ($startsNew -and $active.ContainsKey($key)) {
            Save-Message -Key $key -Buffer $active[$key]
            $active.Remove($key)
        }
        if (-not $active.ContainsKey($key)) {
            $active[$key] = New-Object System.Collections.Generic.List[byte]
        }

        $bytes = ConvertFrom-WireString -Text $content
        if ($bytes.Length -gt 0) { $active[$key].AddRange($bytes) }
    }
} finally {
    $reader.Dispose()
}

# Flush remaining open messages
foreach ($key in @($active.Keys)) {
    Save-Message -Key $key -Buffer $active[$key]
}

# ---------- report ----------

$indexCsv = Join-Path $OutputDir 'index.csv'
$summary | Export-Csv -Path $indexCsv -NoTypeInformation -Encoding utf8

Write-Host ""
Write-Host ("Decoded {0} messages into {1}" -f $summary.Count, $OutputDir)
Write-Host ("Index:  {0}" -f $indexCsv)
$summary | Format-Table Seq, Connection, Direction, ContentEncoding, Chunked, BodyBytes, Note, FirstLine -AutoSize
