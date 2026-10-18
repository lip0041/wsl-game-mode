$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$source = Join-Path $PSScriptRoot '..\src'
. (Join-Path $source 'Core.ps1')
. (Join-Path $source 'SettingsCore.ps1')
Add-Type -AssemblyName System.Windows.Forms
. (Join-Path $source 'UI.ps1')
. (Join-Path $source 'Settings.ps1')
function Assert($Condition,[string]$Message){if(-not $Condition){throw $Message}}
$testRoot=Join-Path $env:TEMP ('WslGameModeSettings-'+[guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $testRoot)
$window=$null
try {
    $path=Join-Path $testRoot 'config.json'
    $config=Get-Content (Join-Path $source 'config.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $config.PSObject.Properties.Remove('Resources')
    [IO.File]::WriteAllText($path,($config|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
    $config=Read-GameModeConfig $path
    Assert $config.Resources.CloseWsl 'Legacy config must retain WSL shutdown by default'
    Assert (@($config.Resources.WindowsApps).Count -eq 0) 'Legacy config must not opt into closing Windows apps'
    Assert (-not (Test-SafeAppTarget 'C:\Windows\System32\notepad.exe')) 'Windows directory must be protected'
    Assert (-not (Test-SafeAppTarget 'C:\Apps\WslGameMode.exe')) 'Own application must be protected'
    Assert (-not (Test-SafeAppTarget 'C:\Apps\powershell.exe')) 'Shell must be protected'
    $config.Resources.WslMode='Selected'
    $config.Resources.WslDistros=@('Ubuntu')
    $config.Resources.WindowsApps=@([pscustomobject]@{Name='Editor';ExecutablePath='C:\Apps\Editor\editor.exe'})
    $start=[datetime]'2026-10-18T01:00:00Z'
    $fake=[pscustomobject]@{Id=98765;Path='C:\Apps\Editor\editor.exe';StartTime=$start;MainWindowHandle=1;Requests=0}
    $fake|Add-Member -MemberType ScriptMethod -Name CloseMainWindow -Value {$this.Requests++;return $true}
    $fake|Add-Member -MemberType ScriptMethod -Name WaitForExit -Value {param($Timeout) return $true}
    $plan=Get-ResourcePlan $config @('Ubuntu','Debian') @($fake) @()
    Assert ((@($plan.Distros)-join ',') -eq 'Ubuntu') 'Only explicitly selected distro should be included'
    Assert (@($plan.WindowsApps).Count -eq 1) 'Exact executable path should match'
    $protectedPlan=Get-ResourcePlan $config @('Ubuntu') @($fake) @([pscustomobject]@{PID=98765})
    Assert (@($protectedPlan.WindowsApps).Count -eq 0) 'Detected game must never be a close target'
    $getter={param($Identifier) return $fake}.GetNewClosure()
    Assert ((Request-GracefulAppExit $plan.WindowsApps[0] $getter) -eq 'exited') 'Normal window close should succeed'
    Assert ($fake.Requests -eq 1) 'Exactly one graceful close request expected'
    $fake.StartTime=$start.AddMinutes(1)
    Assert ((Request-GracefulAppExit $plan.WindowsApps[0] $getter) -eq 'process-changed') 'PID reuse must not close a replacement process'
    Assert ($fake.Requests -eq 1) 'PID reuse must not request a close'
    $script:commands=New-Object 'Collections.Generic.List[string]'
    Invoke-WslResourceRelease $plan {param($Arguments) $script:commands.Add(($Arguments -join '|'))}
    Assert ($script:commands[0] -eq '--terminate|Ubuntu') 'Selected mode must not shut down every distro'
    $plan.WslMode='All'
    Invoke-WslResourceRelease $plan {param($Arguments) $script:commands.Add(($Arguments -join '|'))}
    Assert ($script:commands[1] -eq '--shutdown') 'All mode must request one shutdown'
    Save-GameModeConfig $config $path
    $window=New-GameModeSettingsWindow $path $testRoot
    Assert ($window.FindName('GamesGrid').Items.Count -eq 2) 'Settings must show migrated games'
    Assert ($window.FindName('AppsGrid').Items.Count -eq 1) 'Settings must show configured resources'
    $window.FindName('PollSeconds').Text='12'
    $window.FindName('SaveSettings').RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
    Assert $window.Tag.Saved 'Save button must persist settings'
    $saved=Read-GameModeConfig $path
    Assert ($saved.PollSeconds -eq 12) 'Saved detection interval must update'
    Assert ($saved.Resources.WslDistros[0] -eq 'Ubuntu') 'Selected distro must survive save'
    $window.Close()
    foreach($name in @('Core.ps1','game-mode.log','config.json')){[IO.File]::WriteAllText((Join-Path $testRoot $name),'test')}
    [void](New-Item -ItemType Directory -Path (Join-Path $testRoot 'migration-backup-test'))
    $legacy=@(Get-LegacyCleanupCandidates $testRoot)
    Assert (@($legacy|Where-Object {$_.Name -in @('config.json','game-mode.log')}).Count -eq 0) 'Cleanup must preserve configuration and current log'
    Assert ($legacy.Count -eq 2) 'Only known legacy files should be cleanup candidates'
    Write-Output 'PASS: config migration/save UI, resource selection, graceful close, PID reuse guard, WSL scope, and cleanup boundaries. No real process closed.'
} finally {
    if($window){$window.Close()}
    if(Test-Path $testRoot){Remove-Item -LiteralPath $testRoot -Recurse -Force}
}
