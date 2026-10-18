param([string]$OutputDirectory = (Join-Path $PSScriptRoot 'dist'))
$ErrorActionPreference = 'Stop'
$compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path -LiteralPath $compiler)) { throw 'The .NET Framework 4.x C# compiler is required.' }
[void](New-Item -ItemType Directory -Path $OutputDirectory -Force)
$exe = Join-Path $OutputDirectory 'WslGameMode.exe'
$source = Join-Path $PSScriptRoot 'src'
Add-Type -AssemblyName System.Drawing
$iconPath = Join-Path $OutputDirectory 'app.ico'
$bitmap = New-Object Drawing.Bitmap(64,64)
$graphics = [Drawing.Graphics]::FromImage($bitmap)
$graphics.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
$background = New-Object Drawing.SolidBrush([Drawing.ColorTranslator]::FromHtml('#0067C0'))
$foreground = New-Object Drawing.Pen([Drawing.Color]::White, 5)
$foreground.StartCap = [Drawing.Drawing2D.LineCap]::Round
$foreground.EndCap = [Drawing.Drawing2D.LineCap]::Round
$graphics.FillEllipse($background,2,2,60,60)
$graphics.DrawLine($foreground,17,22,28,32)
$graphics.DrawLine($foreground,28,32,17,42)
$graphics.DrawLine($foreground,35,41,47,41)
$icon = [Drawing.Icon]::FromHandle($bitmap.GetHicon())
$stream = [IO.File]::Create($iconPath)
try { $icon.Save($stream) } finally { $stream.Dispose(); $icon.Dispose(); $graphics.Dispose(); $bitmap.Dispose(); $background.Dispose(); $foreground.Dispose() }
$argsList = @('/nologo','/target:winexe','/platform:x64','/optimize+','/reference:System.Windows.Forms.dll',('/out:' + $exe),('/win32manifest:' + (Join-Path $source 'app.manifest')),('/win32icon:' + $iconPath),('/resource:' + $iconPath + ',app.app.ico'))
foreach ($name in @('Core.ps1','SettingsCore.ps1','Settings.ps1','GameMode.ps1','UI.ps1','config.json')) { $argsList += '/resource:' + (Join-Path $source $name) + ',app.' + $name }
$argsList += Join-Path $source 'Launcher.cs'
$info = New-Object Diagnostics.ProcessStartInfo
$info.FileName = $compiler
$info.Arguments = ($argsList | ForEach-Object { '"' + $_ + '"' }) -join ' '
$info.WorkingDirectory = $env:TEMP
$info.UseShellExecute = $false
$info.CreateNoWindow = $true
$info.RedirectStandardOutput = $true
$info.RedirectStandardError = $true
$process = New-Object Diagnostics.Process
$process.StartInfo = $info
[void]$process.Start()
$stdout = $process.StandardOutput.ReadToEndAsync()
$stderr = $process.StandardError.ReadToEndAsync()
$process.WaitForExit()
Write-Output $stdout.Result
if ($stderr.Result) { Write-Output $stderr.Result }
$compilerExitCode = $process.ExitCode
$process.Dispose()
if ($compilerExitCode -ne 0) { throw 'C# compilation failed.' }
Copy-Item (Join-Path $PSScriptRoot 'README.md') $OutputDirectory -Force
Copy-Item (Join-Path $PSScriptRoot 'LICENSE') $OutputDirectory -Force
Copy-Item (Join-Path $PSScriptRoot 'Install-ProgramFiles.ps1') $OutputDirectory -Force
$zip = Join-Path $OutputDirectory 'WslGameMode-v0.2.1-win-x64.zip'
Compress-Archive -Path @($exe,(Join-Path $OutputDirectory 'README.md'),(Join-Path $OutputDirectory 'LICENSE'),(Join-Path $OutputDirectory 'Install-ProgramFiles.ps1')) -DestinationPath $zip -Force
$checksums = foreach ($file in @($exe,$zip)) { $hash=Get-FileHash -LiteralPath $file -Algorithm SHA256; $hash.Hash.ToLowerInvariant() + '  ' + [IO.Path]::GetFileName($file) }
[IO.File]::WriteAllLines((Join-Path $OutputDirectory 'SHA256SUMS.txt'),$checksums,[Text.UTF8Encoding]::new($false))
Write-Output ('Built: ' + $exe)
