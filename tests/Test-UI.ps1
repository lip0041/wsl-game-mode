param([switch]$Image)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
Add-Type -AssemblyName System.Windows.Forms
. (Join-Path (Join-Path $PSScriptRoot '..\src') 'UI.ps1')
$dialog = New-GameModeDialog -GameNames '永劫无间' -Distros @('Ubuntu')
if (-not $dialog.Topmost -or -not $dialog.ShowInTaskbar) { throw 'Confirmation must remain visible and accessible.' }
if (-not $dialog.FindName('DeferButton').IsDefault -or -not $dialog.FindName('DeferButton').IsCancel) { throw 'Default action must be safe.' }
if ($Image) {
    $content = $dialog.Content
    $content.Measure([Windows.Size]::new(584,[double]::PositiveInfinity))
    $height = [Math]::Ceiling($content.DesiredSize.Height)
    $content.Arrange([Windows.Rect]::new(0,0,584,$height))
    $content.UpdateLayout()
    $bitmap = [Windows.Media.Imaging.RenderTargetBitmap]::new(584,[int]$height,96,96,[Windows.Media.PixelFormats]::Pbgra32)
    $bitmap.Render($content)
    $encoder = [Windows.Media.Imaging.PngBitmapEncoder]::new()
    $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
    $stream = [IO.MemoryStream]::new()
    $encoder.Save($stream)
    [Console]::WriteLine([Convert]::ToBase64String($stream.ToArray()))
    $stream.Dispose()
} else {
    Write-Output 'PASS: WPF dialog loads; topmost, taskbar entry, safe default and cancel actions verified.'
}
$dialog.Close()
