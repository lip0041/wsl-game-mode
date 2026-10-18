function Read-GameModeConfig([string]$Path) {
    $value = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not ($value.PSObject.Properties.Name -contains 'Resources')) {
        $value | Add-Member -NotePropertyName Resources -NotePropertyValue ([pscustomobject]@{CloseWsl=$true;WslMode='All';WslDistros=@();WindowsApps=@()})
    }
    return $value
}

function Test-GameModeConfig($Config) {
    if ([int]$Config.PollSeconds -lt 2 -or [int]$Config.PollSeconds -gt 300) { throw '检测间隔需要在 2～300 秒之间。' }
    if ([int]$Config.DetectionGraceSeconds -lt 0 -or [int]$Config.DetectionGraceSeconds -gt 300) { throw '确认延迟需要在 0～300 秒之间。' }
    if ($Config.Resources.WslMode -notin @('All','Selected')) { throw '请选择有效的 WSL 关闭范围。' }
    if ($Config.Resources.CloseWsl -and $Config.Resources.WslMode -eq 'Selected' -and @($Config.Resources.WslDistros).Count -eq 0) { throw '请填写要关闭的 WSL 发行版名称。' }
    foreach ($game in $Config.StandaloneGames) {
        if (-not $game.Name.Trim() -or @($game.ProcessNames).Count -eq 0) { throw '游戏需要名称和至少一个进程名。' }
        foreach ($name in $game.ProcessNames) { if ($name -match '[\\/:*?"<>|\r\n]' -or -not $name.Trim()) { throw '进程名应填写 EXE 文件名，不包含路径、通配符或 .exe 后缀。' } }
    }
    foreach ($app in $Config.Resources.WindowsApps) {
        if (-not (Test-SafeAppTarget $app.ExecutablePath)) { throw ('不能添加该资源：' + $app.Name + '。请选择普通应用的完整 EXE 路径，不能选择系统程序、终端或游戏模式自身。') }
    }
}

function Save-GameModeConfig($Config, [string]$Path) {
    Test-GameModeConfig $Config
    $temporary = $Path + '.tmp-' + [guid]::NewGuid().ToString('N')
    try {
        [IO.File]::WriteAllText($temporary, ($Config | ConvertTo-Json -Depth 12), [Text.UTF8Encoding]::new($false))
        $null = Get-Content -LiteralPath $temporary -Raw -Encoding UTF8 | ConvertFrom-Json
        if (Test-Path -LiteralPath $Path) { [IO.File]::Replace($temporary,$Path,($Path + '.previous')) }
        else { [IO.File]::Move($temporary,$Path) }
    } finally { if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary } }
}

function Test-SafeAppTarget([string]$Path) {
    if (-not $Path -or -not [IO.Path]::IsPathRooted($Path) -or [IO.Path]::GetExtension($Path) -ne '.exe') { return $false }
    $name = [IO.Path]::GetFileNameWithoutExtension($Path)
    if ($name -match '^(?i:WslGameMode|powershell|pwsh|cmd|conhost|wsl|wslhost|wslservice|vmmemWSL|explorer|svchost|csrss|wininit|winlogon|lsass|services|smss|dwm|taskmgr|sihost|RuntimeBroker|SearchHost|SecurityHealthSystray|MsMpEng|System)$') { return $false }
    if ($env:WINDIR -and (Test-ChildPath $Path $env:WINDIR)) { return $false }
    return $true
}

function Get-ResourcePlan($Config, $RunningDistros, $Processes, $Games) {
    $distros = @()
    if ($Config.Resources.CloseWsl) {
        $distros = @($RunningDistros | Where-Object { $Config.Resources.WslMode -eq 'All' -or $Config.Resources.WslDistros -contains $_ })
    }
    $applications = @()
    foreach ($target in $Config.Resources.WindowsApps) {
        if (-not (Test-SafeAppTarget $target.ExecutablePath)) { continue }
        foreach ($process in $Processes) {
            if ($process.MainWindowHandle -eq 0 -or $process.Id -eq $PID -or @($Games | ForEach-Object {$_.PID}) -contains $process.Id) { continue }
            if ($process.Path -and [string]::Equals($process.Path,$target.ExecutablePath,[StringComparison]::OrdinalIgnoreCase)) {
                try {
                    $applications += [pscustomobject]@{Name=$target.Name;PID=$process.Id;ExecutablePath=$process.Path;Started=$process.StartTime.ToUniversalTime().ToString('o')}
                } catch { }
            }
        }
    }
    [pscustomobject]@{WslMode=$Config.Resources.WslMode;Distros=@($distros);WindowsApps=@($applications | Sort-Object PID -Unique)}
}

function Request-GracefulAppExit($Target, [scriptblock]$GetProcessById = {param($Identifier) Get-Process -Id $Identifier -ErrorAction SilentlyContinue}) {
    if (-not (Test-SafeAppTarget $Target.ExecutablePath)) { return 'blocked' }
    $process = & $GetProcessById $Target.PID
    if (-not $process) { return 'already-exited' }
    try {
        if (-not [string]::Equals($process.Path,$Target.ExecutablePath,[StringComparison]::OrdinalIgnoreCase) -or $process.StartTime.ToUniversalTime().ToString('o') -ne $Target.Started) { return 'process-changed' }
        if ($process.MainWindowHandle -eq 0) { return 'no-window' }
        if (-not $process.CloseMainWindow()) { return 'not-accepted' }
        if ($process.WaitForExit(2000)) { return 'exited' }
        return 'close-requested'
    } catch { return 'not-closed' }
}

function Invoke-WslResourceRelease($Plan, [scriptblock]$RunWsl = {param($Arguments) Invoke-Wsl -Arguments $Arguments -TimeoutSeconds 45}) {
    if (-not @($Plan.Distros).Count) { return }
    if ($Plan.WslMode -eq 'All') { $null = & $RunWsl -Arguments @('--shutdown') }
    else { foreach ($distro in $Plan.Distros) { $null = & $RunWsl -Arguments @('--terminate',$distro) } }
}

function Get-LegacyCleanupCandidates([string]$DataDirectory) {
    $fixedNames = @('Core.ps1','GameMode.ps1','UI.ps1','Uninstall.ps1','README.md','releases')
    foreach ($item in @(Get-ChildItem -LiteralPath $DataDirectory -Force -ErrorAction SilentlyContinue)) {
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
        if ($fixedNames -contains $item.Name -or $item.Name -match '^(migration-backup-|programfiles-migration-backup-|install-staging-)') { $item }
    }
}

function Move-GameModeHistoryToRecycleBin([string]$DataDirectory, [ValidateSet('State','Legacy')][string]$Kind) {
    Add-Type -AssemblyName Microsoft.VisualBasic
    $items = if ($Kind -eq 'State') {
        @(Get-Item -LiteralPath (Join-Path $DataDirectory 'state') -ErrorAction SilentlyContinue)
    } else { @(Get-LegacyCleanupCandidates $DataDirectory) }
    $processes = @(Get-CimInstance Win32_Process -ErrorAction Stop)
    foreach ($item in $items) {
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw '清理对象包含链接，已取消。' }
        foreach ($process in $processes) {
            if ($process.ProcessId -ne $PID -and $process.CommandLine -and $process.CommandLine.IndexOf($item.FullName,[StringComparison]::OrdinalIgnoreCase) -ge 0) { throw ('文件仍被运行中的程序使用，未清理：' + $item.Name) }
        }
    }
    foreach ($item in $items) {
        if ($item.PSIsContainer) { [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory($item.FullName,'OnlyErrorDialogs','SendToRecycleBin','ThrowException') }
        else { [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($item.FullName,'OnlyErrorDialogs','SendToRecycleBin','ThrowException') }
    }
    [void](New-Item -ItemType Directory -Path (Join-Path $DataDirectory 'state') -Force)
    return @($items).Count
}
