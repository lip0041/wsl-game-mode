$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
. (Join-Path (Join-Path $PSScriptRoot '..\src') 'Core.ps1')
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$icon = New-Object Windows.Forms.NotifyIcon
$icon.Icon = [Drawing.SystemIcons]::Application
$icon.Dispose()
$distros = @(Get-RunningDistros)
if (-not $distros.Count) { throw 'This smoke test needs an already running distro.' }
$testRoot = Join-Path $env:TEMP ('WslGameModeSmoke-' + [guid]::NewGuid().ToString('N'))
try {
    $folder = Save-WslSnapshot -Distros $distros -Games @() -StateDirectory $testRoot
    $record = Get-Content (Join-Path $folder 'session.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($record.State -ne 'prepared') { throw 'Unexpected snapshot status' }
    if (-not @(Get-RunningDistros).Count) { throw 'WSL should still be running' }
    Write-Output ('PASS: Windows tray dependencies, real WSL enumeration, metadata snapshot and disk sync for ' + ($distros -join ', ') + '. No shutdown performed.')
} finally {
    if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}
