Set-StrictMode -Version 2
$ErrorActionPreference = 'Stop'

function Test-ChildPath([string]$Path, [string]$Root) {
    if (-not $Path -or -not $Root) { return $false }
    $prefix = $Root.Replace('/', '\').TrimEnd('\') + '\'
    return $Path.Replace('/', '\').StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)
}

function Get-SteamGames($Config) {
    if (-not $Config.EnableSteam) { return }
    $steam = Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue
    if (-not $steam -or -not $steam.SteamPath) { return }
    $libraries = @($steam.SteamPath)
    $vdf = Join-Path $steam.SteamPath 'steamapps\libraryfolders.vdf'
    if (Test-Path -LiteralPath $vdf) {
        $content = Get-Content -LiteralPath $vdf -Raw
        foreach ($match in [regex]::Matches($content, '"path"\s+"([^"]+)"')) {
            $libraries += $match.Groups[1].Value.Replace('\\', '\')
        }
    }
    foreach ($library in ($libraries | Select-Object -Unique)) {
        $apps = Join-Path $library 'steamapps'
        foreach ($manifest in @(Get-ChildItem -LiteralPath $apps -Filter 'appmanifest_*.acf' -ErrorAction SilentlyContinue)) {
            $text = Get-Content -LiteralPath $manifest.FullName -Raw
            $id = [regex]::Match($text, '"appid"\s+"([^"]+)"').Groups[1].Value
            $name = [regex]::Match($text, '"name"\s+"([^"]+)"').Groups[1].Value
            $dir = [regex]::Match($text, '"installdir"\s+"([^"]+)"').Groups[1].Value
            if (-not $id -or -not $dir -or $Config.SteamExcludedAppIds -contains $id -or $name -match $Config.SteamExcludedNamePattern) { continue }
            [pscustomobject]@{Name=$name; AppId=$id; Root=(Join-Path $apps ('common\' + $dir))}
        }
    }
}

function Find-RunningGames($Config, $SteamGames, $Processes) {
    $helper = '(?i)launcher|crash|report|unins|setup|redist|cef|webview|browser|helper|recorder|ffmpeg|ffprobe|anti.?cheat|ACE-|SGuard|UnityCrash|steamservice|updater|patcher'
    foreach ($process in $Processes) {
        foreach ($game in $Config.StandaloneGames) {
            if ($game.ProcessNames -contains $process.ProcessName) {
                # Protected anti-cheat processes can hide their path; only exact game names are a fallback.
                if (-not $process.Path -or -not $game.Root -or (Test-ChildPath $process.Path $game.Root)) {
                    [pscustomobject]@{Name=$game.Name; PID=$process.Id; Process=$process.ProcessName}
                }
            }
        }
        if ($process.ProcessName -match $helper -or -not $process.Path -or $process.MainWindowHandle -eq 0) { continue }
        foreach ($game in $SteamGames) {
            if (Test-ChildPath $process.Path $game.Root) {
                [pscustomobject]@{Name=$game.Name; PID=$process.Id; Process=$process.ProcessName}
            }
        }
    }
}

function Invoke-Wsl([string[]]$Arguments, [switch]$Unicode, [int]$TimeoutSeconds=30) {
    # All arguments are fixed switches, known distro names, or one fixed shell script.
    $quoted = foreach ($argument in $Arguments) {
        if ($argument.Contains('"') -or $argument.EndsWith('\')) { throw 'Unsupported WSL argument quoting.' }
        if ($argument -match '^[A-Za-z0-9_.:/-]+$') { $argument } else { '"' + $argument + '"' }
    }
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = Join-Path $env:WINDIR 'System32\wsl.exe'
    $info.Arguments = $quoted -join ' '
    $info.WorkingDirectory = $env:USERPROFILE
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $encoding = if ($Unicode) { [Text.Encoding]::Unicode } else { [Text.Encoding]::UTF8 }
    $info.StandardOutputEncoding = $encoding
    $info.StandardErrorEncoding = [Text.Encoding]::UTF8
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $info
    try {
        [void]$process.Start()
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            $process.Kill()
            throw 'WSL command timed out; shutdown was not authorized by this step.'
        }
        $process.WaitForExit()
        if ($process.ExitCode -ne 0) { throw ('WSL command failed (exit ' + $process.ExitCode + '): ' + $stderr.Result + ' ' + $stdout.Result) }
        return $stdout.Result.Replace([string][char]0, '').Trim()
    } finally { $process.Dispose() }
}

function Get-RunningDistros {
    $all = @( (Invoke-Wsl -Arguments @('--list','--quiet') -Unicode) -split '\r?\n' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    $running = @( (Invoke-Wsl -Arguments @('--list','--running','--quiet') -Unicode) -split '\r?\n' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    # Match against installed names: localized 'no running distributions' text is not a distro.
    @($all | Where-Object { $running -contains $_ })
}

function Save-WslSnapshot([string[]]$Distros, $Games, [string]$StateDirectory) {
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
    $folder = Join-Path $StateDirectory $stamp
    [void](New-Item -ItemType Directory -Path $folder -Force)
    $entries = @()
    # Metadata only. No command arguments, environment values, file contents, or credentials.
    $script = 'set -eu; date -u; uname -sr; cat /proc/sys/kernel/random/boot_id; printf ''\nPROCESSES\n''; ps -eo pid,ppid,comm; printf ''\nWORKING_DIRECTORIES\n''; for p in /proc/[0-9]*; do c=$(readlink $p/cwd 2>/dev/null) || continue; printf ''%s %s\n'' "${p##*/}" "$c"; done; sync; printf ''\n__GAME_MODE_SYNC_OK__\n'''
    $encodedScript = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($script))
    $transport = 'printf %s ' + $encodedScript + ' | base64 -d | sh'
    $index = 0
    foreach ($distro in $Distros) {
        $index++
        $result = Invoke-Wsl -Arguments @('--distribution',$distro,'--exec','sh','-c',$transport)
        if (-not $result.EndsWith('__GAME_MODE_SYNC_OK__')) { throw ('Disk sync not confirmed for ' + $distro) }
        $file = 'distro-' + $index + '.txt'
        [IO.File]::WriteAllText((Join-Path $folder $file), $result, [Text.UTF8Encoding]::new($false))
        $entries += [pscustomobject]@{Name=$distro; Snapshot=$file; Synced=$true}
    }
    $record = [ordered]@{Time=(Get-Date).ToString('o'); State='prepared'; Games=@($Games); Distros=$entries; Note='Metadata and disk sync only. No process-memory checkpoint or unsaved editor content.'}
    $path = Join-Path $folder 'session.json'
    [IO.File]::WriteAllText($path, ($record | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $StateDirectory 'latest.txt'), $folder, [Text.UTF8Encoding]::new($false))
    return $folder
}
