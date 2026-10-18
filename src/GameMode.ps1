param([switch]$CheckOnly, [string]$DataDirectory = $PSScriptRoot, [string]$ExecutablePath)
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
. (Join-Path $PSScriptRoot 'Core.ps1')
. (Join-Path $PSScriptRoot 'SettingsCore.ps1')
$config = Read-GameModeConfig (Join-Path $DataDirectory 'config.json')
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
. (Join-Path $PSScriptRoot 'Settings.ps1')
$stateDirectory = Join-Path $DataDirectory 'state'
[void](New-Item -ItemType Directory -Path $stateDirectory -Force)
$script:paused = $false
$script:handled = $false
$script:detectedAt = $null
$script:emptySince = $null
$script:settingsOpen = $false
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
$configItem = $menu.Items.Add('设置 · 游戏与资源')
[void]$menu.Items.Add('-')
$exitItem = $menu.Items.Add('退出监控')
$tray.ContextMenuStrip = $menu
$tray.Visible = $true

function Request-GameMode($Games, [switch]$Manual) {
    $plan = Get-ResourcePlan $config @(Get-RunningDistros) @(Get-Process) $Games
    if (-not @($plan.Distros).Count -and -not @($plan.WindowsApps).Count) { return }
    $names = if (@($Games).Count) { (@($Games | ForEach-Object { $_.Name } | Select-Object -Unique) -join '、') } else { '手动切换' }
    Write-Log ('Confirmation shown for ' + $names)
    $tray.ShowBalloonTip(8000, '检测到游戏', '请查看游戏模式确认窗口；确认前不会释放资源。', [Windows.Forms.ToolTipIcon]::Info)
    $answer = Show-GameModeConfirmation -GameNames $names -Distros $plan.Distros -Applications @($plan.WindowsApps | ForEach-Object {$_.Name} | Select-Object -Unique)
    if ($answer -ne [Windows.Forms.DialogResult]::Yes) { Write-Log 'User declined resource release.'; return }
    $running = @(Get-RunningDistros)
    if ($plan.WslMode -eq 'All' -and @($plan.Distros).Count -and @($running | Where-Object {$plan.Distros -notcontains $_}).Count) { throw 'A new WSL distribution started; resource release cancelled.' }
    $plan.Distros = @($plan.Distros | Where-Object {$running -contains $_})
    if (-not $Manual -and -not @(Find-RunningGames $config $script:steamGames @(Get-Process)).Count) { Write-Log 'Game exited; release cancelled.'; return }
    $folder = Save-WslSnapshot -Distros $plan.Distros -Games $Games -StateDirectory $stateDirectory
    $recordPath = Join-Path $folder 'session.json'
    $record = Get-Content $recordPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $record | Add-Member -NotePropertyName ResourcePlan -NotePropertyValue $plan
    [IO.File]::WriteAllText($recordPath, ($record | ConvertTo-Json -Depth 12), [Text.UTF8Encoding]::new($false))
    $appResults = @()
    foreach ($target in $plan.WindowsApps) {
        $status = Request-GracefulAppExit $target
        $appResults += [pscustomobject]@{Name=$target.Name;PID=$target.PID;Status=$status}
        Write-Log ('App release: ' + $target.Name + ' -> ' + $status)
    }
    $record | Add-Member -NotePropertyName WindowsResults -NotePropertyValue $appResults
    $record.State = 'resource-release-requested'
    [IO.File]::WriteAllText($recordPath, ($record | ConvertTo-Json -Depth 12), [Text.UTF8Encoding]::new($false))
    $now = @(Get-RunningDistros)
    if ($plan.WslMode -eq 'All' -and @($plan.Distros).Count -and @($now | Where-Object {$plan.Distros -notcontains $_}).Count) { throw 'A new WSL distribution started during saving; WSL shutdown cancelled.' }
    Invoke-WslResourceRelease $plan
    $runningAfter = @(Get-RunningDistros)
    $stillRunning = @($plan.Distros | Where-Object {$runningAfter -contains $_})
    $record.State = if ($stillRunning.Count) {'wsl-running-after-release-command'} else {'resource-release-completed'}
    [IO.File]::WriteAllText($recordPath, ($record | ConvertTo-Json -Depth 12), [Text.UTF8Encoding]::new($false))
    if ($stillRunning.Count) {
        Write-Log 'WSL target is running after release command. No automatic retry.'
        $tray.ShowBalloonTip(8000, 'WSL 仍在运行', '所选 WSL 又在运行。请检查会自动启动 WSL 的应用。', [Windows.Forms.ToolTipIcon]::Warning)
    } else {
        Write-Log 'Configured resource release completed.'
        $pending = @($appResults | Where-Object {$_.Status -notin @('exited','already-exited')})
        $message = if($pending.Count){'已处理所选资源；部分 Windows 应用仍需手动保存或退出。'}else{'已处理所选资源，状态已保存。'}
        $tray.ShowBalloonTip(6000, '游戏模式', $message, [Windows.Forms.ToolTipIcon]::Info)
    }
}

function Invoke-Detection([switch]$Manual) {
    if ($script:busy -or $script:settingsOpen -or ($script:paused -and -not $Manual)) { return }
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
        $resourcePlan = Get-ResourcePlan $config @(Get-RunningDistros) @(Get-Process) $games
        if (-not @($resourcePlan.Distros).Count -and -not @($resourcePlan.WindowsApps).Count) { return }
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

function Open-GameModeSettings {
    if ($script:busy -or $script:settingsOpen) { return }
    $script:settingsOpen = $true
    try {
        $saved = Show-GameModeSettings (Join-Path $DataDirectory 'config.json') $DataDirectory
        if ($saved) {
            $script:config = Read-GameModeConfig (Join-Path $DataDirectory 'config.json')
            $timer.Interval = [Math]::Max(2000,[int]$script:config.PollSeconds * 1000)
            $script:steamGames = @(Get-SteamGames $script:config)
            $script:lastSteamRefresh = Get-Date
            Write-Log 'Settings saved and applied.'
        }
    } catch { Write-Log ('Settings error: ' + $_.Exception.Message) }
    finally { $script:settingsOpen = $false }
}

function Read-SettingsRequest {
    $request = Join-Path $DataDirectory 'open-settings.request'
    if (-not $script:busy -and -not $script:settingsOpen -and (Test-Path -LiteralPath $request)) {
        Remove-Item -LiteralPath $request
        Open-GameModeSettings
    }
}

$pauseItem.add_Click({ $script:paused = -not $script:paused; $pauseItem.Text = if ($script:paused) {'恢复自动检测'} else {'暂停自动检测'}; $tray.Text = if ($script:paused) {'WSL 游戏模式：已暂停'} else {'WSL 游戏模式：监控中'} })
$startupItem.add_Click({
    try {
        if ($startupItem.Checked) {
            $exe = $ExecutablePath
            if (-not $exe) { $exe = Join-Path $DataDirectory 'WslGameMode.exe' }
            if (-not (Test-Path -LiteralPath $exe)) { throw 'Run the EXE build before enabling automatic startup.' }
            [void](New-Item -Path $runKey -Force)
            Set-ItemProperty -Path $runKey -Name 'WslGameMode' -Value ('"' + $exe + '" --background')
        } else { Remove-ItemProperty -Path $runKey -Name 'WslGameMode' -ErrorAction SilentlyContinue }
    } catch { $startupItem.Checked = -not $startupItem.Checked; Write-Log ('Startup setting failed: ' + $_.Exception.Message) }
})
$manualItem.add_Click({ Invoke-Detection -Manual })
$stateItem.add_Click({ Start-Process explorer.exe -ArgumentList ('"' + $stateDirectory + '"') })
$configItem.add_Click({ Open-GameModeSettings })
$tray.add_DoubleClick({ Open-GameModeSettings })
$exitItem.add_Click({ [Windows.Forms.Application]::Exit() })
$timer = New-Object Windows.Forms.Timer
$timer.Interval = [Math]::Max(2000, [int]$config.PollSeconds * 1000)
$timer.add_Tick({ Read-SettingsRequest; Invoke-Detection })
$timer.Start()
Write-Log 'Watcher started. Shutdown always requires a fresh Yes confirmation.'
try { Read-SettingsRequest; [Windows.Forms.Application]::Run() }
finally { $timer.Stop(); $timer.Dispose(); $tray.Visible=$false; $tray.Dispose(); $menu.Dispose(); $mutex.ReleaseMutex(); $mutex.Dispose() }
