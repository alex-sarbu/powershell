# PowerShell Profile - Unix-style Commands

Auto-loaded on shell startup via `setup/Install-Profile.ps1`.  
Scripts are dot-sourced in order: `unix-file.ps1` -> `unix-system.ps1` -> `unix-network.ps1` -> `navigation.ps1`.

---

## File & Text (`unix-file.ps1`)

### `head`
Show the first N lines of a file or pipeline input.

```powershell
head file.txt           # first 10 lines
head -n 20 file.txt     # first 20 lines
cat file.txt | head     # from pipeline
```

**Limitations:** No `-q`/`-v` (quiet/verbose filename headers) for multiple files.

---

### `tail`
Show the last N lines of a file or pipeline input. Supports live following.

```powershell
tail file.txt           # last 10 lines
tail -n 20 file.txt     # last 20 lines
tail -f app.log         # follow (stream new lines as they appear)
cat file.txt | tail     # from pipeline
```

**Limitations:** `-f` only works with a file path, not pipeline input.

---

### `touch`
Create a file if it doesn't exist, or update its last-write timestamp.

```powershell
touch newfile.txt
touch a.txt b.txt c.txt   # multiple files
```

---

### `wc`
Count lines, words, and characters.

```powershell
wc file.txt             # all three counts
wc -l file.txt          # lines only
wc -w file.txt          # words only
wc -c file.txt          # chars only
cat file.txt | wc -l    # from pipeline
```

**Limitations:** `-c` counts characters, not bytes. No multi-file summary line.

---

### `sed`
Stream editor - find-and-replace using regex. Supports any single-character delimiter.

```powershell
'hello world' | sed 's/world/PowerShell/'     # basic replace
cat file.txt  | sed 's/foo/bar/g'             # replace all occurrences
sed 's/foo/bar/g' file.txt                    # from file
sed 's/FOO/bar/i' file.txt                    # case-insensitive
sed 's|path/a|path/b|g' file.txt             # alternate delimiter
sed 's/old/new/' file.txt -InPlace           # edit file in place
```

**Limitations:** Only the `s` command is supported. No address ranges, no `d`/`p`/`a`/`i` commands.

---

### `grep`
Search for a regex pattern in files or pipeline input.

```powershell
grep 'error' app.log                    # basic search
grep 'error' *.log                      # multiple files (shows filename:line)
grep -r 'TODO' .                        # recursive
grep -i 'error' app.log                 # case-insensitive
grep -v 'debug' app.log                 # invert match (exclude)
grep -l 'error' *.log                   # only print filenames
grep -c 'error' app.log                 # count matches
cat app.log | grep 'error'              # from pipeline
```

**Limitations:** No `-A`/`-B`/`-C` context lines. No `-n` line-number flag (shown automatically for multi-file searches). No `--include`/`--exclude` glob filtering.

---

### `find`
Recursively search for files and directories.

```powershell
find .                          # all items under current directory
find . -Name *.ps1              # by name pattern (supports wildcards)
find . -Type f                  # files only
find . -Type d                  # directories only
find . -Mtime -7                # modified in the last 7 days
find . -Mtime 30                # not modified in the last 30 days
find . -Name *.log -Depth 2     # limit recursion depth
```

**Limitations:** No `-size`, `-perm`, `-exec`, or `-not` support. `-Name` uses PowerShell wildcards (`*`, `?`), not glob patterns.

---

## System (`unix-system.ps1`)

### `which`
Print the full path of a command.

```powershell
which git
which python
```

**Limitations:** Returns the first match only (same as `Get-Command`). Does not distinguish between aliases, functions, and executables.

---

### `df`
Show disk space for all mounted FileSystem drives.

```powershell
df          # sizes in 1K-blocks
df -h       # human-readable (K/M/G/T)
```

**Limitations:** Shows PowerShell `PSDrive` entries only - network shares appear only if mapped as a drive. `Use%` can show `N/A` for drives reporting 0 total size (e.g. virtual drives).

---

### `du`
Show disk usage of a directory.

```powershell
du                  # sizes of each item in current directory (1K-blocks)
du C:\Logs          # specific path
du -h .             # human-readable
du -s .             # summary (total only)
du -s -h C:\Logs    # human-readable summary
```

**Limitations:** Can be slow on large trees (no kernel-level caching). No `-d` depth limit in non-summary mode.

---

### `uptime`
Show how long the system has been running since last boot.

```powershell
uptime
# up 3 days, 04:22:11
```

---

### `env`
List all environment variables, or print the value of one.

```powershell
env                 # all variables (sorted, table format)
env PATH            # value of a specific variable
```

---

### `export`
Set an environment variable for the current PowerShell session.

```powershell
export DEBUG=true
export MY_TOKEN=abc123
```

**Limitations:** Session-scoped only - does not persist after the shell closes. Use `[System.Environment]::SetEnvironmentVariable(name, value, 'User')` to persist.

---

### `pkill`
Kill all processes matching a name.

```powershell
pkill notepad
pkill chrome
```

**Limitations:** Matches by exact process name (no regex). Use `pgrep` first to confirm targets.

---

### `pgrep`
List processes whose name matches a regex pattern.

```powershell
pgrep node
pgrep 'chrome|edge'
```

**Limitations:** Matches against `.Name` only, not command-line arguments.

---

## Network (`unix-network.ps1`)

### `curl`
Wrapper around `curl.exe` that accepts both PowerShell-style and native curl arguments.

| PowerShell param | Translates to |
|------------------|---------------|
| `-Verbose`       | `-v`          |
| `-Uri <url>`     | `<url>`       |
| `-Method <m>`    | `-X <m>`      |
| `-Body <data>`   | `-d <data>`   |
| `-OutFile <p>`   | `-o <p>`      |
| anything else    | passed as-is  |

```powershell
curl https://example.com                              # basic GET
curl -Verbose https://example.com                     # verbose output (mapped to -v)
curl -Uri https://example.com                         # Invoke-WebRequest style
curl -Method POST -Uri https://api.example.com        # POST request
curl -Method POST -Body '{}' -Uri https://api.example.com
curl -OutFile file.zip https://example.com/file.zip
curl -X POST -H 'Content-Type: application/json' -d '{}' https://api.example.com  # native curl flags
curl -v https://example.com                           # native curl verbose
curl --version
```

**Note:** Implemented as a plain function (no `[CmdletBinding()]`) so PowerShell never silently consumes arguments. Without this, `-Verbose` is stripped before reaching `$args`, and a `Set-Alias` passes it raw to `curl.exe`, where `-V` means `--version`.  
**Limitations:** Requires `curl.exe` on `PATH` (ships with Windows 10 1803+). `-Headers` (hashtable) is not mapped - use native `-H 'Name: Value'` instead.

---

### `wget`
Download a URL to a file.

```powershell
wget https://example.com/file.zip              # saves as file.zip
wget https://example.com/file.zip -O out.zip   # custom output filename
wget https://example.com/file.zip -q           # quiet (no progress message)
```

**Limitations:** No resume (`-c`), no recursive download. Progress display depends on `Invoke-WebRequest` internals.

---

### `ifconfig`
Show active network adapters with IPs and MAC address.

```powershell
ifconfig
```

**Limitations:** Shows only adapters with `Status -eq 'Up'`. No ability to configure interfaces (read-only).

---

### `dig`
DNS lookup for a hostname.

```powershell
dig example.com           # A record (default)
dig example.com MX        # mail records
dig example.com AAAA      # IPv6
dig example.com TXT       # text records
dig example.com NS        # name servers
```

**Limitations:** Wraps `Resolve-DnsName` - output format differs from BIND `dig`. No `+short` or custom resolver support.

---

### `ports`
Show open ports and the processes using them.

```powershell
ports           # all TCP/UDP entries
ports 8080      # filter to a specific port number
```

**Limitations:** Parses `netstat -ano` text output - may miss entries on busy systems or show stale TIME_WAIT entries.

---

## Navigation (`navigation.ps1` + `cd-aliases.ps1`)

Persistent `cd` shortcuts, similar to bash aliases like `alias myrepo.home="cd /path/to/repo"`.  
Aliases are stored as PowerShell functions in `cd-aliases.ps1` (auto-generated, do not edit by hand) and loaded on every shell start.

---

### `Quick-CdAlias`
Register the current directory as a named navigation alias. The alias is active immediately and persists across sessions.

```powershell
cd C:\dev\ps\my-project
Quick-CdAlias my-project        # creates my-project.home

# From anywhere afterwards:
my-project.home                 # jumps to C:\dev\ps\my-project
```

The alias name may contain letters, numbers, hyphens, and underscores. The `.home` suffix is always appended automatically.

---

### `Remove-CdAlias`
Delete a navigation alias by name (without the `.home` suffix).

```powershell
Remove-CdAlias my-project       # removes my-project.home
```

---

### `List-CdAliases`
Show all registered navigation aliases and their target paths.

```powershell
List-CdAliases

# Alias              Path
# -----              ----
# my-project.home    C:\dev\ps\my-project
# api-service.home   C:\dev\services\api
```

---

### `git` (wrapper)
Transparent wrapper around `git.exe`. After a successful `git clone`, automatically registers a `.home` alias for the cloned repository.

```powershell
git clone https://github.com/user/my-repo
# clones into ./my-repo/
# registers my-repo.home -> C:\current\path\my-repo   (printed in cyan)

my-repo.home        # jump to it from anywhere
```

**How it detects the clone directory:** Snapshots subdirectories before the clone and diffs afterwards. If exactly one new directory appears, it is registered.  
**Limitations:** Does not auto-alias if the clone target already existed, if `--bare` or `--separate-git-dir` was used, or if multiple directories were created concurrently. In those cases, use `Quick-CdAlias` manually.

---

## Shell Helpers (`profile.ps1`)

| Command | Description |
|---------|-------------|
| `ll [args]` | `Get-ChildItem -Force` - shows hidden files |
| `la [args]` | Same as `ll` |
| `mkcd <path>` | Create directory and `cd` into it |
| `path` | Print each `$env:PATH` entry on its own line, sorted |
| `reload` | Re-source `$PROFILE` without restarting the shell |

---

## Installation

Run once from any PowerShell prompt (no elevation required):

```powershell
.\setup\Install-Profile.ps1
```

Then restart PowerShell or run `. $PROFILE`. The profile dot-sources directly from the repo path, so pulling updates takes effect on the next shell start.
