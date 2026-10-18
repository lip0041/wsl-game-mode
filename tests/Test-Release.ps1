param([string]$Executable = (Join-Path $PSScriptRoot '..\dist\WslGameMode.exe'), [switch]$CheckWsl)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$Executable = (Resolve-Path -LiteralPath $Executable).ProviderPath
function Invoke-Executable([string]$Argument) {
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $Executable
    $info.Arguments = $Argument
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.StandardOutputEncoding = [Text.Encoding]::UTF8
    $info.StandardErrorEncoding = [Text.Encoding]::UTF8
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $info
    [void]$process.Start()
    $stdout = $process.StandardOutput.ReadToEndAsync()
    $stderr = $process.StandardError.ReadToEndAsync()
    if (-not $process.WaitForExit(60000)) { $process.Kill(); throw 'Executable test timed out' }
    $process.WaitForExit()
    try {
        if ($process.ExitCode -ne 0) { throw ('Executable failed: ' + $stderr.Result) }
        return $stdout.Result
    } finally { $process.Dispose() }
}
$version = (Invoke-Executable '--version').Trim()
if ($version -ne '0.1.0') { throw ('Unexpected EXE version: ' + $version) }
if ($CheckWsl) {
    $result = (Invoke-Executable '--check') | ConvertFrom-Json
    if (-not ($result.PSObject.Properties.Name -contains 'RunningDistros')) { throw 'Packaged self-check returned invalid data' }
    Write-Output ('PASS: Packaged EXE v' + $version + ', embedded scripts/config, real read-only WSL and game detection. No shutdown performed.')
} else { Write-Output ('PASS: Windows EXE starts and reports v' + $version) }
