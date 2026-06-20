# Remove the built-in curl/wget aliases (both point to Invoke-WebRequest in PS 5.1;
# PS 7 already dropped them, so these are silently no-ops there).
Remove-Item Alias:curl -ErrorAction SilentlyContinue
Remove-Item Alias:wget -ErrorAction SilentlyContinue

# curl - remap PowerShell-style params to curl flags, pass everything else through.
# Must be a plain function (no [CmdletBinding()]) so $args is available and PS
# never silently absorbs flags. Mapping table:
#   -Verbose     -> -v   (PS common param; curl -V means --version, not verbose)
#   -Uri <url>   -> <url> (Invoke-WebRequest style; positional in curl)
#   -Method <m>  -> -X <m>
#   -Body <data> -> -d <data>
#   -OutFile <p> -> -o <p>
# Everything else is forwarded verbatim.
function curl {
    $curlArgs = @()
    for ($i = 0; $i -lt $args.Count; $i++) {
        switch ($args[$i]) {
            '-Verbose'  { $curlArgs += '-v' }
            '-Uri'      { $i++; if ($i -lt $args.Count) { $curlArgs += $args[$i] } }
            '-Method'   { $i++; if ($i -lt $args.Count) { $curlArgs += '-X', $args[$i] } }
            '-Body'     { $i++; if ($i -lt $args.Count) { $curlArgs += '-d', $args[$i] } }
            '-OutFile'  { $i++; if ($i -lt $args.Count) { $curlArgs += '-o', $args[$i] } }
            default     { $curlArgs += $args[$i] }
        }
    }
    curl.exe @curlArgs
}

# wget - download a URL to a file, defaulting to the URL's basename
function wget {
    param(
        [Parameter(Mandatory, Position=0)][string]$Url,
        [Alias('O')][string]$OutFile,
        [Alias('q')][switch]$Quiet
    )
    $dest = if ($OutFile) { $OutFile } else { Split-Path $Url -Leaf }
    if (-not $Quiet) { Write-Host "Downloading: $Url => $dest" -ForegroundColor Cyan }
    Invoke-WebRequest -Uri $Url -OutFile $dest
}

# ifconfig - show active network adapters, IPs, and MAC addresses
function ifconfig {
    Get-NetAdapter | Where-Object { $_.Status -eq 'Up' } | ForEach-Object {
        $iface = $_
        $ips   = Get-NetIPAddress -InterfaceIndex $iface.InterfaceIndex -ErrorAction SilentlyContinue
        Write-Host "$($iface.Name):" -ForegroundColor Cyan -NoNewline
        Write-Host "  $($iface.InterfaceDescription)"
        foreach ($ip in $ips) {
            $family = if ($ip.AddressFamily -eq 'IPv4') { 'inet ' } else { 'inet6' }
            Write-Host "    $family  $($ip.IPAddress)/$($ip.PrefixLength)"
        }
        Write-Host "    ether  $($iface.MacAddress)"
        Write-Host
    }
}

# dig - DNS lookup; wraps Resolve-DnsName with a Linux-style interface
# Usage: dig <name> [A|AAAA|MX|NS|TXT|CNAME|...]
function dig {
    param(
        [Parameter(Mandatory, Position=0)][string]$Name,
        [Parameter(Position=1)][string]$Type = 'A'
    )
    Resolve-DnsName -Name $Name -Type $Type
}

# ports - show open ports and the owning processes
# Usage: ports        - all listening/established TCP/UDP
#        ports 8080   - only entries involving port 8080
function ports {
    param([Parameter(Position=0)][int]$Port)
    $pattern = if ($PSBoundParameters.ContainsKey('Port')) { ":$Port(\s|$)" } else { '.' }
    netstat -ano | Select-Object -Skip 4 |
        Where-Object { $_ -match $pattern } |
        ForEach-Object {
            $cols = $_.Trim() -split '\s+'
            $pid_ = $cols[-1]
            $proc = Get-Process -Id $pid_ -ErrorAction SilentlyContinue
            [PSCustomObject]@{
                Proto      = $cols[0]
                LocalAddr  = $cols[1]
                RemoteAddr = $cols[2]
                State      = if ($cols.Count -ge 4) { $cols[3] } else { '-' }
                PID        = $pid_
                Process    = if ($proc) { $proc.Name } else { 'N/A' }
            }
        }
}
