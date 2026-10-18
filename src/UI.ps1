Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

function New-GameModeDialog([string]$GameNames, [string[]]$Distros) {
    $dark = $false
    try {
        $key = Get-Item 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
        $dark = $key.GetValue('AppsUseLightTheme', 1) -eq 0
    } catch { }
    $palette = if ($dark) {
        @{BackgroundColor='#202020'; SurfaceColor='#2B2B2B'; TextColor='#FFFFFF'; SecondaryColor='#C5C5C5'; BorderColor='#454545'; AccentColor='#60CDFF'; AccentTextColor='#00243D'; HoverColor='#383838'; AccentHoverColor='#83D9FF'; NoticeColor='#FCE100'}
    } else {
        @{BackgroundColor='#F3F3F3'; SurfaceColor='#FFFFFF'; TextColor='#1A1A1A'; SecondaryColor='#606060'; BorderColor='#E5E5E5'; AccentColor='#0067C0'; AccentTextColor='#FFFFFF'; HoverColor='#F7F7F7'; AccentHoverColor='#005A9E'; NoticeColor='#9D5D00'}
    }
    $xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="WSL 游戏模式" Width="600" SizeToContent="Height" ResizeMode="NoResize"
        WindowStartupLocation="CenterScreen" Topmost="True" ShowInTaskbar="True"
        FontFamily="Segoe UI, Microsoft YaHei UI" FontSize="14"
        Background="{BackgroundColor}" Foreground="{TextColor}" UseLayoutRounding="True">
  <Window.Resources>
    <Style x:Key="QuietButton" TargetType="Button">
      <Setter Property="Background" Value="{SurfaceColor}"/>
      <Setter Property="Foreground" Value="{TextColor}"/>
      <Setter Property="BorderBrush" Value="{BorderColor}"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Padding" Value="16,9"/>
      <Setter Property="MinHeight" Value="38"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="ButtonBorder" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="4" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="ButtonBorder" Property="Opacity" Value="0.92"/></Trigger>
              <Trigger Property="IsPressed" Value="True"><Setter TargetName="ButtonBorder" Property="Opacity" Value="0.8"/></Trigger>
              <Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="ButtonBorder" Property="BorderBrush" Value="{AccentColor}"/><Setter TargetName="ButtonBorder" Property="BorderThickness" Value="2"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="PrimaryButton" TargetType="Button" BasedOn="{StaticResource QuietButton}">
      <Setter Property="Background" Value="{AccentColor}"/>
      <Setter Property="Foreground" Value="{AccentTextColor}"/>
      <Setter Property="BorderBrush" Value="{AccentColor}"/>
      <Style.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter Property="Opacity" Value="0.9"/></Trigger></Style.Triggers>
    </Style>
  </Window.Resources>
  <Grid Background="{BackgroundColor}">
    <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
    <StackPanel Margin="28,24,28,26">
      <TextBlock Text="切换到游戏模式" FontSize="24" FontWeight="SemiBold"/>
      <TextBlock x:Name="GameLabel" Margin="0,8,0,22" TextWrapping="Wrap" Foreground="{SecondaryColor}"/>
      <Border Background="{SurfaceColor}" BorderBrush="{BorderColor}" BorderThickness="1" CornerRadius="8" Padding="18,16">
        <Grid>
          <Grid.ColumnDefinitions><ColumnDefinition Width="90"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
          <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
          <TextBlock Text="即将关闭" Foreground="{SecondaryColor}" VerticalAlignment="Center"/>
          <TextBlock x:Name="DistroLabel" Grid.Column="1" TextWrapping="Wrap"/>
          <TextBlock Text="关闭前保存" Grid.Row="1" Margin="0,14,0,0" Foreground="{SecondaryColor}" VerticalAlignment="Center"/>
          <TextBlock Text="进程清单、工作目录，并刷新磁盘" Grid.Row="1" Grid.Column="1" Margin="0,14,0,0" TextWrapping="Wrap"/>
        </Grid>
      </Border>
      <Grid Margin="0,22,0,0">
        <Grid.ColumnDefinitions><ColumnDefinition Width="28"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
        <TextBlock FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" Text="&#xE7BA;" Foreground="{NoticeColor}" FontSize="18" Margin="0,2,0,0"/>
        <StackPanel Grid.Column="1">
          <TextBlock Text="请先保存正在进行的工作" FontWeight="SemiBold"/>
          <TextBlock Text="视频生成、推理进度及未保存内容无法自动恢复。关闭后，WSL 中的终端和 Codex 会话将断开。" Margin="0,6,0,0" TextWrapping="Wrap" Foreground="{SecondaryColor}" LineHeight="22"/>
        </StackPanel>
      </Grid>
    </StackPanel>
    <Border Grid.Row="1" BorderBrush="{BorderColor}" BorderThickness="0,1,0,0" Padding="28,18">
      <Grid>
        <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
        <Button x:Name="DeferButton" Content="暂不关闭" Width="120" HorizontalAlignment="Left" IsCancel="True" IsDefault="True" Style="{StaticResource QuietButton}"/>
        <Button x:Name="ConfirmButton" Content="保存状态并关闭 WSL" Grid.Column="1" Style="{StaticResource PrimaryButton}"/>
      </Grid>
    </Border>
  </Grid>
</Window>
'@
    foreach ($name in $palette.Keys) { $xaml = $xaml.Replace(('{' + $name + '}'), $palette[$name]) }
    $reader = [Xml.XmlNodeReader]::new([xml]$xaml)
    $dialog = [Windows.Markup.XamlReader]::Load($reader)
    $reader.Close()
    $iconPath = Join-Path $PSScriptRoot 'app.ico'
    if (Test-Path -LiteralPath $iconPath) { $dialog.Icon = [Windows.Media.Imaging.BitmapFrame]::Create([Uri]::new($iconPath)) }
    $dialog.FindName('GameLabel').Text = '检测到 ' + $GameNames + '，可关闭 WSL 释放系统资源。'
    $dialog.FindName('DistroLabel').Text = $Distros -join '、'
    # Resolve the owner through the sender; no dependency on a function-local event closure.
    $dialog.FindName('ConfirmButton').add_Click({ param($sender,$eventArgs); [Windows.Window]::GetWindow($sender).DialogResult = $true })
    $dialog.FindName('DeferButton').add_Click({ param($sender,$eventArgs); [Windows.Window]::GetWindow($sender).DialogResult = $false })
    $dialog.add_ContentRendered({ param($sender,$eventArgs); $null = $sender.Activate(); $null = $sender.FindName('DeferButton').Focus() })
    return $dialog
}

function Show-GameModeConfirmation([string]$GameNames, [string[]]$Distros) {
    $dialog = New-GameModeDialog -GameNames $GameNames -Distros $Distros
    try {
        if ($dialog.ShowDialog() -eq $true) { return [Windows.Forms.DialogResult]::Yes }
        return [Windows.Forms.DialogResult]::No
    } finally { $dialog.Close() }
}
