$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$root = Join-Path $env:TEMP ('WslGameModeStartup-' + [guid]::NewGuid().ToString('N'))
$instance = 'WslGameModeTest' + [guid]::NewGuid().ToString('N')
$source = Join-Path $PSScriptRoot '..\src'
$process = $null
$signal = $null
$hotProcess = $null
$hotData = Join-Path $env:LOCALAPPDATA $instance
[void](New-Item -ItemType Directory -Path $root)
try {
    # A separate named instance cannot interact with an installed watcher.
    Copy-Item (Join-Path $source '*.ps1') $root
    $scriptPath = Join-Path $root 'GameMode.ps1'
    $text = [IO.File]::ReadAllText($scriptPath).Replace('Local\WslGameMode.',('Local\' + $instance + '.'))
    [IO.File]::WriteAllText($scriptPath,$text,[Text.UTF8Encoding]::new($true))
    # A deliberately slow library scan must not delay the first window.
    Add-Content (Join-Path $root 'Core.ps1') "`nfunction Get-SteamGames { Start-Sleep -Seconds 20 }"
    $config = Get-Content (Join-Path $source 'config.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $config.StandaloneGames = @()
    $config.Resources.CloseWsl = $false
    $config.Resources.WindowsApps = @()
    [IO.File]::WriteAllText((Join-Path $root 'config.json'),($config | ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $root 'open-settings.request'),[datetime]::UtcNow.ToString('o'))
    $clock = [Diagnostics.Stopwatch]::StartNew()
    $process = Start-Process powershell.exe -ArgumentList ('-NoProfile -STA -ExecutionPolicy Bypass -File "' + $scriptPath + '" -DataDirectory "' + $root + '"') -PassThru -WindowStyle Hidden
    $log = Join-Path $root 'game-mode.log'
    do {
        Start-Sleep -Milliseconds 100
        if ($process.HasExited) { throw 'Isolated watcher exited before showing settings' }
        $rendered = (Test-Path $log) -and ((Get-Content $log -Raw) -match 'Settings rendered; request latency ms=(\d+)')
    } while (-not $rendered -and $clock.Elapsed.TotalSeconds -lt 15)
    if (-not $rendered) { throw 'Settings blocked by startup work or failed to render' }
    $coldMs = $clock.ElapsedMilliseconds
    $signal = [Threading.EventWaitHandle]::OpenExisting(('Local\' + $instance + '.settings'))
    # Compile the actual launcher with only its instance name isolated. No embedded
    # resources are supplied: a warm launch must return before extracting any.
    $launcher = [IO.File]::ReadAllText((Join-Path $source 'Launcher.cs')).Replace('WslGameMode',$instance)
    $launcherPath = Join-Path $root 'Launcher.cs'
    [IO.File]::WriteAllText($launcherPath,$launcher)
    $exe = Join-Path $root 'launcher.exe'
    $compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
    $compileInfo = New-Object Diagnostics.ProcessStartInfo
    $compileInfo.FileName = $compiler
    $compileInfo.Arguments = '/nologo /target:winexe /reference:System.Windows.Forms.dll "/out:' + $exe + '" "' + $launcherPath + '"'
    $compileInfo.WorkingDirectory = $env:TEMP
    $compileInfo.UseShellExecute = $false
    $compileInfo.CreateNoWindow = $true
    $compileInfo.RedirectStandardOutput = $true
    $compileInfo.RedirectStandardError = $true
    $compilerProcess = [Diagnostics.Process]::Start($compileInfo)
    $stdout = $compilerProcess.StandardOutput.ReadToEndAsync()
    $stderr = $compilerProcess.StandardError.ReadToEndAsync()
    $compilerProcess.WaitForExit()
    $code = $compilerProcess.ExitCode
    $compilerProcess.Dispose()
    if ($code -ne 0) { throw ('Isolated launcher build failed: ' + $stdout.Result + $stderr.Result) }
    $clock.Restart()
    $hotProcess = Start-Process $exe -PassThru
    if (-not $hotProcess.WaitForExit(5000) -or $hotProcess.ExitCode -ne 0) { throw 'Warm launcher did not take the signal-only path' }
    $hotMs = $clock.ElapsedMilliseconds
    $request = Join-Path $hotData 'open-settings.request'
    if (-not (Test-Path $request)) { throw 'Launcher did not create settings request' }
    # The fixture uses its own data path; deliver the generated request there.
    Move-Item $request (Join-Path $root 'open-settings.request') -Force
    $signal.Set() | Out-Null
    $clock.Restart()
    do { Start-Sleep -Milliseconds 20 } while ((Test-Path (Join-Path $root 'open-settings.request')) -and $clock.Elapsed.TotalSeconds -lt 2)
    if (Test-Path (Join-Path $root 'open-settings.request')) { throw 'Settings IPC waited for the game detection interval' }
    Write-Output ('PASS: isolated cold render {0}ms despite 20s scan; warm EXE {1}ms; UI request handled {2}ms. No user resources closed.' -f $coldMs,$hotMs,$clock.ElapsedMilliseconds)
} finally {
    if ($hotProcess -and -not $hotProcess.HasExited) { $hotProcess.Kill(); $hotProcess.WaitForExit() }
    if ($process -and -not $process.HasExited) { $process.Kill(); $process.WaitForExit() }
    if ($signal) { $signal.Dispose() }
    foreach ($path in @($root,$hotData)) { if (Test-Path $path) { Remove-Item $path -Recurse -Force } }
}
