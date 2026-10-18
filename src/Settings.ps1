function ConvertTo-SettingsWindow([string]$Xaml) {
    $palette = Get-GameModePalette
    $Xaml = $Xaml.Replace('__STYLES__',(Get-GameModeStyles))
    foreach ($name in $palette.Keys) { $Xaml = $Xaml.Replace(('{' + $name + '}'),$palette[$name]) }
    $reader = [Xml.XmlNodeReader]::new([xml]$Xaml)
    try { $window = [Windows.Markup.XamlReader]::Load($reader) } finally { $reader.Close() }
    $icon = Join-Path $PSScriptRoot 'app.ico'
    if (Test-Path -LiteralPath $icon) { $window.Icon = [Windows.Media.Imaging.BitmapFrame]::Create([Uri]::new($icon)) }
    return $window
}

function Show-SettingsError($Owner, [string]$Message) {
    [void][Windows.MessageBox]::Show($Owner,$Message,'请检查设置','OK','Warning')
}

function Show-GameModeEntryDialog($Owner, [ValidateSet('Game','Application')][string]$Kind, $Entry=$null) {
    $window = ConvertTo-SettingsWindow @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
 Title="添加应用" Width="580" SizeToContent="Height" ResizeMode="NoResize" WindowStartupLocation="CenterOwner"
 FontFamily="Segoe UI, Microsoft YaHei UI" FontSize="14" Background="{BackgroundColor}" Foreground="{TextColor}">
__STYLES__
 <StackPanel Margin="24">
  <TextBlock x:Name="EntryHeading" FontSize="22" FontWeight="SemiBold" Margin="0,0,0,18"/>
  <TextBlock Text="显示名称"/><TextBox x:Name="EntryName" Padding="10,8" Margin="0,6,0,14"/>
  <TextBlock Text="应用 EXE"/>
  <Grid Margin="0,6,0,14"><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
   <TextBox x:Name="EntryPath" Padding="10,8" VerticalContentAlignment="Center"/>
   <Button x:Name="BrowseExe" Grid.Column="1" Content="浏览…" Margin="8,0,0,0" Style="{StaticResource QuietButton}"/>
  </Grid>
  <StackPanel x:Name="GameFields">
   <TextBlock Text="进程名（多个名称用英文逗号分隔）"/><TextBox x:Name="EntryProcesses" Padding="10,8" Margin="0,6,0,14"/>
   <TextBlock Text="安装目录（可选）"/><TextBox x:Name="EntryRoot" Padding="10,8" Margin="0,6,0,14"/>
  </StackPanel>
  <TextBlock x:Name="EntryHint" TextWrapping="Wrap" Foreground="{SecondaryColor}" Margin="0,0,0,20"/>
  <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
   <Button Content="取消" IsCancel="True" Width="90" Margin="0,0,10,0" Style="{StaticResource QuietButton}"/>
   <Button x:Name="SaveEntry" Content="确定" Width="90" IsDefault="True" Style="{StaticResource PrimaryButton}"/>
  </StackPanel>
 </StackPanel>
</Window>
'@
    $window.Owner = $Owner
    $window.Tag = [pscustomobject]@{Kind=$Kind;Result=$null}
    $window.FindName('EntryHeading').Text = if ($Kind -eq 'Game') {'添加要检测的游戏'} else {'添加要退出的应用'}
    $window.FindName('EntryHint').Text = if ($Kind -eq 'Game') {'请选择游戏本体的 EXE，避免选择启动器。也可以只填写精确进程名。'} else {'只尝试正常退出；应用的保存提示仍需你处理，不会强制结束进程。'}
    if ($Kind -eq 'Application') { $window.FindName('GameFields').Visibility = 'Collapsed' }
    if ($Entry) {
        $window.FindName('EntryName').Text = $Entry.Name
        if ($Kind -eq 'Game') {
            $window.FindName('EntryProcesses').Text = $Entry.ProcessNames -join ', '
            $window.FindName('EntryRoot').Text = $Entry.Root
        } else { $window.FindName('EntryPath').Text = $Entry.ExecutablePath }
    }
    $window.FindName('BrowseExe').add_Click({
        param($sender,$eventArgs)
        $ownerWindow = [Windows.Window]::GetWindow($sender)
        $picker = New-Object Microsoft.Win32.OpenFileDialog
        $picker.Filter = '应用程序 (*.exe)|*.exe'
        if ($picker.ShowDialog($ownerWindow)) {
            $ownerWindow.FindName('EntryPath').Text = $picker.FileName
            if (-not $ownerWindow.FindName('EntryName').Text.Trim()) { $ownerWindow.FindName('EntryName').Text = [IO.Path]::GetFileNameWithoutExtension($picker.FileName) }
            if ($ownerWindow.Tag.Kind -eq 'Game') {
                $ownerWindow.FindName('EntryProcesses').Text = [IO.Path]::GetFileNameWithoutExtension($picker.FileName)
                $ownerWindow.FindName('EntryRoot').Text = [IO.Path]::GetDirectoryName($picker.FileName)
            }
        }
    })
    $window.FindName('SaveEntry').add_Click({
        param($sender,$eventArgs)
        $entryWindow = [Windows.Window]::GetWindow($sender)
        try {
            $name = $entryWindow.FindName('EntryName').Text.Trim()
            if (-not $name) { throw '请填写显示名称。' }
            if ($entryWindow.Tag.Kind -eq 'Game') {
                $names = @($entryWindow.FindName('EntryProcesses').Text -split ',' | ForEach-Object { $_.Trim() -replace '(?i)\.exe$','' } | Where-Object { $_ } | Select-Object -Unique)
                if (-not $names.Count -or @($names | Where-Object { $_ -match '[\\/:*?"<>|\r\n]' }).Count) { throw '请填写有效的精确进程名。' }
                $entryWindow.Tag.Result = [pscustomobject]@{Name=$name;ProcessNames=$names;Root=$entryWindow.FindName('EntryRoot').Text.Trim()}
            } else {
                $path = $entryWindow.FindName('EntryPath').Text.Trim()
                if (-not (Test-SafeAppTarget $path)) { throw '请选择普通应用的完整 EXE 路径。系统程序、终端和游戏模式自身不能作为退出目标。' }
                if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw '该 EXE 文件不存在。' }
                $entryWindow.Tag.Result = [pscustomobject]@{Name=$name;ExecutablePath=$path}
            }
            $entryWindow.DialogResult = $true
        } catch { Show-SettingsError $entryWindow $_.Exception.Message }
    })
    try { if ($window.ShowDialog()) { return $window.Tag.Result } } finally { $window.Close() }
}

function New-GameModeSettingsWindow([string]$ConfigPath, [string]$DataDirectory) {
    $config = Read-GameModeConfig $ConfigPath
    $window = ConvertTo-SettingsWindow @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
 Title="WSL Game Mode · 设置" Width="860" Height="660" MinWidth="740" MinHeight="570" WindowStartupLocation="CenterScreen"
 FontFamily="Segoe UI, Microsoft YaHei UI" FontSize="14" Background="{BackgroundColor}" Foreground="{TextColor}" UseLayoutRounding="True">
__STYLES__
 <Grid Margin="28,24" Background="{BackgroundColor}">
  <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
  <StackPanel Margin="0,0,0,22"><TextBlock Text="WSL Game Mode" FontSize="26" FontWeight="SemiBold"/>
   <TextBlock Text="游戏开始，按你的选择释放资源。关闭前始终需要确认。" Margin="0,6,0,0" Foreground="{SecondaryColor}"/>
  </StackPanel>
  <TabControl Grid.Row="1" Background="{SurfaceColor}" Foreground="{TextColor}" BorderBrush="{BorderColor}">
   <TabItem Header="游戏">
    <Grid Margin="18"><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
     <CheckBox x:Name="SteamEnabled" Content="自动识别 Steam 游戏（名单每周刷新）" Margin="0,0,0,14"/>
     <TextBlock Grid.Row="1" Text="独立游戏名单" FontWeight="SemiBold" Margin="0,0,0,10"/>
     <DataGrid x:Name="GamesGrid" Grid.Row="2" AutoGenerateColumns="False" IsReadOnly="True" CanUserAddRows="False" SelectionMode="Single" HeadersVisibility="Column" GridLinesVisibility="Horizontal" HorizontalGridLinesBrush="{BorderColor}" Background="{SurfaceColor}" Foreground="{TextColor}" BorderBrush="{BorderColor}" RowBackground="{SurfaceColor}" AlternatingRowBackground="{SurfaceColor}">
      <DataGrid.Columns><DataGridTextColumn ElementStyle="{StaticResource GridText}" Header="名称" Binding="{Binding Name}" Width="160"/><DataGridTextColumn ElementStyle="{StaticResource GridText}" Header="进程名" Binding="{Binding ProcessText}" Width="2*" MinWidth="250"/><DataGridTextColumn ElementStyle="{StaticResource GridText}" Header="安装目录" Binding="{Binding Root}" Width="*" MinWidth="220"/></DataGrid.Columns>
     </DataGrid>
     <StackPanel Grid.Row="3" Orientation="Horizontal" Margin="0,14,0,0"><Button x:Name="AddGame" Content="添加游戏" Style="{StaticResource QuietButton}"/><Button x:Name="EditGame" Content="编辑" Margin="10,0,0,0" Style="{StaticResource QuietButton}"/><Button x:Name="RemoveGame" Content="移除" Margin="10,0,0,0" Style="{StaticResource QuietButton}"/></StackPanel>
    </Grid>
   </TabItem>
   <TabItem Header="资源">
    <Grid Margin="18"><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
     <CheckBox x:Name="CloseWsl" Content="关闭 WSL" Margin="0,0,0,10"/>
     <StackPanel Grid.Row="1" Orientation="Horizontal" Margin="0,0,0,12"><RadioButton x:Name="AllDistros" Content="全部发行版" GroupName="WslScope" Margin="0,0,24,0"/><RadioButton x:Name="SelectedDistros" Content="指定发行版" GroupName="WslScope"/></StackPanel>
     <StackPanel Grid.Row="2" Margin="0,0,0,16"><TextBox x:Name="DistroNames" Padding="10,7"/><TextBlock Text="指定时填写准确名称，用英文逗号分隔。其他 WSL 仍运行时，虚拟机可能保留。" TextWrapping="Wrap" Foreground="{SecondaryColor}" Margin="0,6,0,12"/><TextBlock Text="Windows 应用 · 仅正常关闭有窗口的应用，不强杀后台进程" FontWeight="SemiBold"/></StackPanel>
     <DataGrid x:Name="AppsGrid" Grid.Row="3" AutoGenerateColumns="False" IsReadOnly="True" CanUserAddRows="False" SelectionMode="Single" HeadersVisibility="Column" GridLinesVisibility="Horizontal" HorizontalGridLinesBrush="{BorderColor}" Background="{SurfaceColor}" Foreground="{TextColor}" BorderBrush="{BorderColor}" RowBackground="{SurfaceColor}">
      <DataGrid.Columns><DataGridTextColumn ElementStyle="{StaticResource GridText}" Header="名称" Binding="{Binding Name}" Width="170"/><DataGridTextColumn ElementStyle="{StaticResource GridText}" Header="EXE 路径" Binding="{Binding ExecutablePath}" Width="*" MinWidth="420"/></DataGrid.Columns>
     </DataGrid>
     <StackPanel Grid.Row="4" Orientation="Horizontal" Margin="0,14,0,0"><Button x:Name="AddApp" Content="添加应用" Style="{StaticResource QuietButton}"/><Button x:Name="RemoveApp" Content="移除" Margin="10,0,0,0" Style="{StaticResource QuietButton}"/></StackPanel>
    </Grid>
   </TabItem>
   <TabItem Header="历史">
    <StackPanel Margin="20">
     <TextBlock Text="关闭记录与旧安装文件" FontSize="20" FontWeight="SemiBold"/>
     <TextBlock Text="历史记录只用于事后查看，不是可恢复任务的检查点。清理会移入回收站，保留当前配置和运行日志。" TextWrapping="Wrap" Foreground="{SecondaryColor}" Margin="0,10,0,22"/>
     <TextBlock x:Name="HistorySummary" Margin="0,0,0,18"/>
     <StackPanel Orientation="Horizontal"><Button x:Name="OpenHistory" Content="打开记录目录" Style="{StaticResource QuietButton}"/><Button x:Name="ClearHistory" Content="清空关闭记录" Margin="10,0,0,0" Style="{StaticResource QuietButton}"/></StackPanel>
     <TextBlock x:Name="LegacySummary" Margin="0,28,0,12"/>
     <Button x:Name="ClearLegacy" Content="清理旧安装文件和备份" HorizontalAlignment="Left" Style="{StaticResource QuietButton}"/>
    </StackPanel>
   </TabItem>
   <TabItem Header="常规">
    <StackPanel Margin="20">
     <TextBlock Text="检测设置" FontSize="20" FontWeight="SemiBold" Margin="0,0,0,20"/>
     <TextBlock Text="检测间隔（秒，2～300）"/><TextBox x:Name="PollSeconds" Width="160" HorizontalAlignment="Left" Padding="10,8" Margin="0,6,0,20"/>
     <TextBlock Text="游戏持续运行多久后提醒（秒，0～300）"/><TextBox x:Name="GraceSeconds" Width="160" HorizontalAlignment="Left" Padding="10,8" Margin="0,6,0,20"/>
     <TextBlock Text="保存设置后立即生效。关闭此窗口会保留托盘监控。登录自动启动可在托盘菜单设置。" TextWrapping="Wrap" Foreground="{SecondaryColor}"/>
    </StackPanel>
   </TabItem>
  </TabControl>
  <Grid Grid.Row="2" Margin="0,18,0,0"><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
   <TextBlock x:Name="SettingsStatus" VerticalAlignment="Center" Foreground="{SecondaryColor}" Text="未保存的更改只保留在此窗口中"/>
   <Button Content="关闭" Grid.Column="1" IsCancel="True" Width="90" Margin="0,0,10,0" Style="{StaticResource QuietButton}"/>
   <Button x:Name="SaveSettings" Content="保存设置" Grid.Column="2" Width="120" Style="{StaticResource PrimaryButton}"/>
  </Grid>
 </Grid>
</Window>
'@
    $games = New-Object 'Collections.ObjectModel.ObservableCollection[object]'
    foreach ($game in $config.StandaloneGames) { $games.Add([pscustomobject]@{Name=$game.Name;ProcessNames=@($game.ProcessNames);ProcessText=($game.ProcessNames -join ', ');Root=$game.Root}) }
    $apps = New-Object 'Collections.ObjectModel.ObservableCollection[object]'
    foreach ($app in $config.Resources.WindowsApps) { $apps.Add($app) }
    $window.Tag = [pscustomobject]@{Config=$config;ConfigPath=$ConfigPath;DataDirectory=$DataDirectory;Games=$games;Apps=$apps;Saved=$false}
    $window.FindName('GamesGrid').ItemsSource = $games
    $window.FindName('AppsGrid').ItemsSource = $apps
    $window.FindName('SteamEnabled').IsChecked = [bool]$config.EnableSteam
    $window.FindName('CloseWsl').IsChecked = [bool]$config.Resources.CloseWsl
    $window.FindName('AllDistros').IsChecked = $config.Resources.WslMode -eq 'All'
    $window.FindName('SelectedDistros').IsChecked = $config.Resources.WslMode -eq 'Selected'
    $window.FindName('DistroNames').Text = $config.Resources.WslDistros -join ', '
    $window.FindName('PollSeconds').Text = [string]$config.PollSeconds
    $window.FindName('GraceSeconds').Text = [string]$config.DetectionGraceSeconds
    Update-GameModeHistorySummary $window
    $window.FindName('AddGame').add_Click({param($sender,$e) $w=[Windows.Window]::GetWindow($sender);$entry=Show-GameModeEntryDialog $w 'Game';if($entry){$w.Tag.Games.Add([pscustomobject]@{Name=$entry.Name;ProcessNames=$entry.ProcessNames;ProcessText=($entry.ProcessNames -join ', ');Root=$entry.Root})}})
    $window.FindName('EditGame').add_Click({param($sender,$e) $w=[Windows.Window]::GetWindow($sender);$old=$w.FindName('GamesGrid').SelectedItem;if($old){$entry=Show-GameModeEntryDialog $w 'Game' $old;if($entry){$index=$w.Tag.Games.IndexOf($old);$w.Tag.Games[$index]=[pscustomobject]@{Name=$entry.Name;ProcessNames=$entry.ProcessNames;ProcessText=($entry.ProcessNames -join ', ');Root=$entry.Root}}}})
    $window.FindName('RemoveGame').add_Click({param($sender,$e) $w=[Windows.Window]::GetWindow($sender);$entry=$w.FindName('GamesGrid').SelectedItem;if($entry){$null=$w.Tag.Games.Remove($entry)}})
    $window.FindName('AddApp').add_Click({param($sender,$e) $w=[Windows.Window]::GetWindow($sender);$entry=Show-GameModeEntryDialog $w 'Application';if($entry){if(@($w.Tag.Apps | Where-Object {$_.ExecutablePath -eq $entry.ExecutablePath}).Count -eq 0){$w.Tag.Apps.Add($entry)}}})
    $window.FindName('RemoveApp').add_Click({param($sender,$e) $w=[Windows.Window]::GetWindow($sender);$entry=$w.FindName('AppsGrid').SelectedItem;if($entry){$null=$w.Tag.Apps.Remove($entry)}})
    $window.FindName('OpenHistory').add_Click({param($sender,$e) $w=[Windows.Window]::GetWindow($sender);Start-Process explorer.exe -ArgumentList ('"'+(Join-Path $w.Tag.DataDirectory 'state')+'"')})
    foreach ($buttonName in @('ClearHistory','ClearLegacy')) {
        $window.FindName($buttonName).add_Click({
            param($sender,$e)
            $w=[Windows.Window]::GetWindow($sender)
            $kind=if($sender.Name -eq 'ClearHistory'){'State'}else{'Legacy'}
            $question=if($kind -eq 'State'){'将所有关闭记录移入回收站？当前配置和运行日志会保留。'}else{'将已停用的旧脚本、安装临时文件和迁移备份移入回收站？当前程序和配置会保留。'}
            if([Windows.MessageBox]::Show($w,$question,'确认清理','YesNo','Question','No') -eq 'Yes'){
                try{$count=Move-GameModeHistoryToRecycleBin $w.Tag.DataDirectory $kind;$w.FindName('SettingsStatus').Text='已将 '+$count+' 项移入回收站';Update-GameModeHistorySummary $w}catch{Show-SettingsError $w $_.Exception.Message}
            }
        })
    }
    $window.FindName('SaveSettings').add_Click({
        param($sender,$e)
        $w=[Windows.Window]::GetWindow($sender)
        try {
            $value=$w.Tag.Config
            $value.PollSeconds=[int]$w.FindName('PollSeconds').Text
            $value.DetectionGraceSeconds=[int]$w.FindName('GraceSeconds').Text
            $value.EnableSteam=[bool]$w.FindName('SteamEnabled').IsChecked
            $value.StandaloneGames=@($w.Tag.Games | ForEach-Object {[pscustomobject]@{Name=$_.Name;ProcessNames=@($_.ProcessNames);Root=$_.Root}})
            $value.Resources.CloseWsl=[bool]$w.FindName('CloseWsl').IsChecked
            $value.Resources.WslMode=if($w.FindName('SelectedDistros').IsChecked){'Selected'}else{'All'}
            $value.Resources.WslDistros=@($w.FindName('DistroNames').Text -split ',' | ForEach-Object {$_.Trim()} | Where-Object {$_} | Select-Object -Unique)
            $value.Resources.WindowsApps=@($w.Tag.Apps)
            Save-GameModeConfig $value $w.Tag.ConfigPath
            $w.Tag.Saved=$true
            $w.FindName('SettingsStatus').Text='已保存，关闭窗口后应用新设置'
        } catch { Show-SettingsError $w $_.Exception.Message }
    })
    return $window
}

function Update-GameModeHistorySummary($Window) {
    $state = Join-Path $Window.Tag.DataDirectory 'state'
    $sessions = @(Get-ChildItem -LiteralPath $state -Directory -ErrorAction SilentlyContinue)
    $Window.FindName('HistorySummary').Text = '关闭记录：' + $sessions.Count + ' 次'
    $legacy = @(Get-LegacyCleanupCandidates $Window.Tag.DataDirectory)
    $Window.FindName('LegacySummary').Text = '可清理的旧安装文件与备份：' + $legacy.Count + ' 项'
}

function Show-GameModeSettings([string]$ConfigPath, [string]$DataDirectory) {
    $window=New-GameModeSettingsWindow $ConfigPath $DataDirectory
    try { $null=$window.ShowDialog(); return $window.Tag.Saved } finally { $window.Close() }
}
