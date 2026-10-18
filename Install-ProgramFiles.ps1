param(
    [Parameter(Mandatory=$true)][string]$SourceExecutable,
    [Parameter(Mandatory=$true)][string]$ExpectedSHA256
)
$ErrorActionPreference = 'Stop'
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Program Files installation requires Windows administrator approval.'
}
if ((Get-FileHash -LiteralPath $SourceExecutable -Algorithm SHA256).Hash -ne $ExpectedSHA256) { throw 'Source checksum mismatch' }
$destination = Join-Path $env:ProgramFiles 'WslGameMode'
[void](New-Item -ItemType Directory -Path $destination -Force)
$assembly = [Reflection.Assembly]::Load([IO.File]::ReadAllBytes($SourceExecutable))
$version = $assembly.GetName().Version.ToString(3)
$scripts = Join-Path $destination ('releases\' + $version)
[void](New-Item -ItemType Directory -Path $scripts -Force)
foreach ($name in @('Core.ps1','SettingsCore.ps1','Settings.ps1','GameMode.ps1','UI.ps1','app.ico')) {
    $resource = $assembly.GetManifestResourceStream('app.' + $name)
    if (-not $resource) { throw ('Missing packaged resource: ' + $name) }
    $output = [IO.File]::Create((Join-Path $scripts $name))
    try { $resource.CopyTo($output) } finally { $output.Dispose(); $resource.Dispose() }
}
$exe = Join-Path $destination 'WslGameMode.exe'
Copy-Item -LiteralPath $SourceExecutable -Destination $exe -Force
if ((Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash -ne $ExpectedSHA256) { throw 'Installed EXE checksum mismatch' }
[pscustomobject]@{Installed=$exe;Version=$version;Scripts=$scripts} | ConvertTo-Json
