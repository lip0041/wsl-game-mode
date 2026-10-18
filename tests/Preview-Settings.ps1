$ErrorActionPreference='Stop'
[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
$source=Join-Path $PSScriptRoot '..\src'
. (Join-Path $source 'Core.ps1')
. (Join-Path $source 'SettingsCore.ps1')
. (Join-Path $source 'UI.ps1')
. (Join-Path $source 'Settings.ps1')
$temporary=Join-Path $env:TEMP ('WslGameModePreview-'+[guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $temporary)
Copy-Item (Join-Path $source 'config.json') $temporary
$window=New-GameModeSettingsWindow (Join-Path $temporary 'config.json') $temporary
try{
 $content=$window.Content
 $content.Measure([Windows.Size]::new(844,622))
 $content.Arrange([Windows.Rect]::new(0,0,844,622))
 $content.UpdateLayout()
 $bitmap=[Windows.Media.Imaging.RenderTargetBitmap]::new(900,680,96,96,[Windows.Media.PixelFormats]::Pbgra32)
 $visual=[Windows.Media.DrawingVisual]::new()
 $drawing=$visual.RenderOpen()
 $drawing.DrawRectangle($window.Background,$null,[Windows.Rect]::new(0,0,900,680))
 $drawing.Close()
 $bitmap.Render($visual)
 $bitmap.Render($content)
 $encoder=[Windows.Media.Imaging.PngBitmapEncoder]::new()
 $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
 $stream=[IO.MemoryStream]::new()
 $encoder.Save($stream)
 [Console]::WriteLine([Convert]::ToBase64String($stream.ToArray()))
 $stream.Dispose()
}finally{$window.Close();Remove-Item -LiteralPath $temporary -Recurse -Force}
