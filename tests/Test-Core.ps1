$ErrorActionPreference = 'Stop'
. (Join-Path (Join-Path $PSScriptRoot '..\src') 'Core.ps1')
function Assert($Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
$errorsFound = @()
foreach ($file in Get-ChildItem (Join-Path $PSScriptRoot '..') -Filter '*.ps1' -Recurse) {
    $tokens = $null; $parseErrors = $null
    $null = [Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$parseErrors)
    $errorsFound += @($parseErrors)
}
Assert ($errorsFound.Count -eq 0) ($errorsFound | Out-String)
$config = Get-Content (Join-Path (Join-Path $PSScriptRoot '..\src') 'config.json') -Raw -Encoding UTF8 | ConvertFrom-Json
Assert (Test-ChildPath 'D:\Games\Test\game.exe' 'd:/games/test') 'Expected child path match'
Assert (-not (Test-ChildPath 'D:\Games\Testing\game.exe' 'D:\Games\Test')) 'Sibling directory must not match'
$config.StandaloneGames[0].Root = 'D:\Naraka\program'
$config.StandaloneGames[1].Root = 'D:\Delta Force\Delta Force'
$steam = @([pscustomobject]@{Name='Test game'; AppId='123'; Root='D:\Games\Test'})
$fixtures = @(
    [pscustomobject]@{Id=1;ProcessName='Test';Path='D:\Games\Test\Test.exe';MainWindowHandle=12},
    [pscustomobject]@{Id=2;ProcessName='UnityCrashHandler64';Path='D:\Games\Test\UnityCrashHandler64.exe';MainWindowHandle=10},
    [pscustomobject]@{Id=3;ProcessName='TestLauncher';Path='D:\Games\Test\TestLauncher.exe';MainWindowHandle=10},
    [pscustomobject]@{Id=4;ProcessName='Test';Path='D:\Games\Test2\Test.exe';MainWindowHandle=10},
    [pscustomobject]@{Id=5;ProcessName='NarakaBladepoint';Path=$null;MainWindowHandle=0},
    [pscustomobject]@{Id=6;ProcessName='DeltaForceClient-Win64-Shipping';Path='D:\Delta Force\Delta Force\DeltaForce\Binaries\Win64\DeltaForceClient-Win64-Shipping.exe';MainWindowHandle=10},
    [pscustomobject]@{Id=7;ProcessName='NarakaBladepoint';Path='C:\Wrong\NarakaBladepoint.exe';MainWindowHandle=10},
    [pscustomobject]@{Id=8;ProcessName='Test';Path='D:\Games\Test\Test.exe';MainWindowHandle=0}
)
$found = @(Find-RunningGames $config $steam $fixtures)
Assert ($found.Count -eq 3) 'Only game executable, protected Naraka and Delta should match'
Assert ((@($found.PID | Sort-Object) -join ',') -eq '1,5,6') 'Wrong detected processes'

# Snapshot failure must throw and never mark a successful shutdown; all WSL calls here are mocked.
$testRoot = Join-Path $env:TEMP ('WslGameModeTest-' + [guid]::NewGuid().ToString('N'))
function Invoke-Wsl { param($Arguments,[switch]$Unicode,[int]$TimeoutSeconds=30); return 'sync did not finish' }
$failed = $false
try { $null = Save-WslSnapshot @('TestDistro') $found $testRoot } catch { $failed = $true }
Assert $failed 'Missing sync acknowledgement must abort saving'
Assert (-not (Test-Path (Join-Path $testRoot 'latest.txt'))) 'Failed snapshot must not become latest'
function Invoke-Wsl { param($Arguments,[switch]$Unicode,[int]$TimeoutSeconds=30); return "test metadata`n__GAME_MODE_SYNC_OK__" }
$folder = Save-WslSnapshot @('TestDistro') $found $testRoot
$saved = Get-Content (Join-Path $folder 'session.json') -Raw -Encoding UTF8 | ConvertFrom-Json
Assert ($saved.State -eq 'prepared') 'Snapshot state must not claim shutdown'
Assert ($saved.Distros[0].Synced -eq $true) 'Sync status missing'
Assert (Test-Path (Join-Path $folder 'distro-1.txt')) 'Metadata file missing'
Remove-Item -LiteralPath $testRoot -Recurse -Force
Write-Output 'PASS: PowerShell parsing, game detection, path boundaries, helper exclusions, and fail-closed snapshot persistence.'
