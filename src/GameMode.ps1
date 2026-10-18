param([switch]$CheckOnly, [string]$DataDirectory = $PSScriptRoot)
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
. (Join-Path $PSScriptRoot 'Core.ps1')
$config = Get-Content (Join-Path $DataDirectory 'config.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$steamGames = @(Get-SteamGames $config)
if ($CheckOnly) {
    [pscustomobject]@{SteamGames=$steamGames; StandaloneGames=$config.StandaloneGames; RunningDistros=@(Get-RunningDistros); RunningGames=@(Find-RunningGames $config $steamGames @(Get-Process))} | ConvertTo-Json -Depth 7
    exit
}

$mutex = New-Object Threading.Mutex($false, 'Local\WslGameMode.monitor')
if (-not $mutex.WaitOne(0)) { $mutex.Dispose(); exit }
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
. (Join-Path $PSScriptRoot 'UI.ps1')
$stateDirectory = Join-Path $DataDirectory 'state'
[void](New-Item -ItemType Directory -Path $stateDirectory -Force)
$script:paused = $false
$script:handled = $false
$script:detectedAt = $null
$script:emptySince = $null
$script:busy = $false
$script:currentKey = ''
$script:lastError = ''
$script:lastSteamRefresh = Get-Date

function Write-Log([string]$Message) {
    $log = Join-Path $DataDirectory 'game-mode.log'
    if ((Test-Path $log) -and (Get-Item $log).Length -gt 2MB) { Move-Item $log ($log + '.old') -Force }
    Add-Content -LiteralPath $log -Value ((Get-Date).ToString('o') + ' ' + $Message) -Encoding UTF8
}

$tray = New-Object Windows.Forms.NotifyIcon
$appIcon = Join-Path $PSScriptRoot 'app.ico'
$tray.Icon = if (Test-Path -LiteralPath $appIcon) { [Drawing.Icon]::new($appIcon) } else { [Drawing.SystemIcons]::Application }
$tray.Text = 'WSL 游戏模式：监控中'
$menu = New-Object Windows.Forms.ContextMenuStrip
$pauseItem = $menu.Items.Add('暂停自动检测')
$startupItem = $menu.Items.Add('登录 Windows 后自动启动')
$startupItem.CheckOnClick = $true
$runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$startupItem.Checked = $null -ne (Get-ItemProperty -Path $runKey -Name 'WslGameMode' -ErrorAction SilentlyContinue)
$manualItem = $menu.Items.Add('现在检测并询问关闭 WSL')
$stateItem = $menu.Items.Add('查看保存的状态')
$configItem = $menu.Items.Add('编辑游戏名单')
[void]$menu.Items.Add('-')
$exitItem = $menu.Items.Add('退出监控')
$tray.ContextMenuStrip = $menu
$tray.Visible = $true

function Request-GameMode($Games, [switch]$Manual) {
    $distros = @(Get-RunningDistros)
    if (-not $distros.Count) { return }
    $names = if (@($Games).Count) { (@($Games | ForEach-Object { $_.Name } | Select-Object -Unique) -join '、') } else { '手动切换' }
    Write-Log ('Confirmation shown for ' + $names)
    $tray.ShowBalloonTip(8000, '检测到游戏', '请查看置顶的游戏模式确认窗口；确认前不会关闭 WSL。', [Windows.Forms.ToolTipIcon]::Info)
    $answer = Show-GameModeConfirmation -GameNames $names -Distros $distros
    if ($answer -ne [Windows.Forms.DialogResult]::Yes) { Write-Log 'User declined shutdown.'; return }
    # Do not wake a distro that was stopped while the user was reading the dialog.
    $distros = @(Get-RunningDistros)
    if (-not $distros.Count) { return }
    $folder = Save-WslSnapshot -Distros $distros -Games $Games -StateDirectory $stateDirectory
    $now = @(Get-RunningDistros)
    if (@($now | Where-Object { $distros -notcontains $_ }).Count) { throw 'A new distribution started during saving; shutdown cancelled.' }
    if (-not $Manual -and -not @(Find-RunningGames $config $script:steamGames @(Get-Process)).Count) {
        Write-Log 'Game exited while saving; shutdown cancelled.'
        return
    }
    Write-Log ('Confirmed shutdown; state saved at ' + $folder)
    $null = Invoke-Wsl -Arguments @('--shutdown') -TimeoutSeconds 45
    $runningAfterShutdown = @(Get-RunningDistros)
    $recordPath = Join-Path $folder 'session.json'
    $record = Get-Content $recordPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $record.State = if ($runningAfterShutdown.Count) { 'running-after-shutdown-command' } else { 'shutdown-confirmed' }
    [IO.File]::WriteAllText($recordPath, ($record | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
    if ($runningAfterShutdown.Count) {
        Write-Log 'Shutdown command completed, but WSL is running again. No automatic retry.'
        $tray.ShowBalloonTip(8000, 'WSL 又在运行', '关闭命令已完成，但 WSL 又在运行。请检查会自动启动 WSL 的应用。', [Windows.Forms.ToolTipIcon]::Warning)
        return
    }
    Write-Log 'WSL shutdown confirmed.'
    $tray.ShowBalloonTip(6000, '游戏模式已开启', 'WSL 已关闭，状态已保存。需要工作时照常启动 WSL。', [Windows.Forms.ToolTipIcon]::Info)
}

function Invoke-Detection([switch]$Manual) {
    if ($script:busy -or ($script:paused -and -not $Manual)) { return }
    $script:busy = $true
    try {
        if (((Get-Date) - $script:lastSteamRefresh).TotalDays -ge 7) {
            $script:steamGames = @(Get-SteamGames $config)
            $script:lastSteamRefresh = Get-Date
        }
        $games = @(Find-RunningGames $config $script:steamGames @(Get-Process) | Sort-Object Name,PID -Unique)
        if ($Manual) { $script:handled = $true; Request-GameMode $games -Manual; return }
        if (-not $games.Count) {
            if ($null -eq $script:emptySince) { $script:emptySince = Get-Date }
            # Ignore brief gaps when a launcher hands off to the real game process.
            if (((Get-Date) - $script:emptySince).TotalSeconds -ge 30) {
                $script:handled = $false; $script:detectedAt = $null; $script:currentKey = ''
            }
            return
        }
        $script:emptySince = $null
        if ($null -eq $script:detectedAt) { $script:detectedAt = Get-Date }
        if ($script:handled -or ((Get-Date) - $script:detectedAt).TotalSeconds -lt $config.DetectionGraceSeconds) { return }
        if (-not @(Get-RunningDistros).Count) { return }
        $script:handled = $true
        Request-GameMode $games
    } catch {
        Write-Log ('ERROR: ' + $_.Exception.Message)
        if ($script:lastError -ne $_.Exception.Message) {
            $tray.ShowBalloonTip(8000, '游戏模式未完成', '未完成保存或检查，已停止本次切换。详情见 game-mode.log。', [Windows.Forms.ToolTipIcon]::Warning)
            $script:lastError = $_.Exception.Message
        }
    } finally { $script:busy = $false }
}

$pauseItem.add_Click({ $script:paused = -not $script:paused; $pauseItem.Text = if ($script:paused) {'恢复自动检测'} else {'暂停自动检测'}; $tray.Text = if ($script:paused) {'WSL 游戏模式：已暂停'} else {'WSL 游戏模式：监控中'} })
$startupItem.add_Click({
    try {
        if ($startupItem.Checked) {
            $exe = Join-Path $DataDirectory 'WslGameMode.exe'
            if (-not (Test-Path -LiteralPath $exe)) { throw 'Run the EXE build before enabling automatic startup.' }
            [void](New-Item -Path $runKey -Force)
            Set-ItemProperty -Path $runKey -Name 'WslGameMode' -Value ('"' + $exe + '"')
        } else { Remove-ItemProperty -Path $runKey -Name 'WslGameMode' -ErrorAction SilentlyContinue }
    } catch { $startupItem.Checked = -not $startupItem.Checked; Write-Log ('Startup setting failed: ' + $_.Exception.Message) }
})
$manualItem.add_Click({ Invoke-Detection -Manual })
$stateItem.add_Click({ Start-Process explorer.exe -ArgumentList ('"' + $stateDirectory + '"') })
$configItem.add_Click({ Start-Process notepad.exe -ArgumentList ('"' + (Join-Path $DataDirectory 'config.json') + '"') })
$exitItem.add_Click({ [Windows.Forms.Application]::Exit() })
$timer = New-Object Windows.Forms.Timer
$timer.Interval = [Math]::Max(2000, [int]$config.PollSeconds * 1000)
$timer.add_Tick({ Invoke-Detection })
$timer.Start()
Write-Log 'Watcher started. Shutdown always requires a fresh Yes confirmation.'
try { [Windows.Forms.Application]::Run() }
finally { $timer.Stop(); $timer.Dispose(); $tray.Visible=$false; $tray.Dispose(); $menu.Dispose(); $mutex.ReleaseMutex(); $mutex.Dispose() }
