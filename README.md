# WSL Game Mode

Windows 游戏模式助手：识别游戏启动，确认后保存 WSL 状态信息、关闭选定 WSL，并尝试正常退出你选择的 Windows 应用。

## 使用

从 Releases 下载 EXE 或 Windows x64 ZIP，双击打开设置窗口。程序会驻留托盘，再次双击 EXE 或托盘图标可重新打开设置。

| 页面 | 功能 |
|---|---|
| 游戏 | 自动识别 Steam；通过 EXE 选择器添加游戏，编辑名称、精确进程名和目录 |
| 资源 | 选择全部或指定 WSL 发行版；添加需要尝试正常退出的 Windows 应用 |
| 历史 | 查看记录；把关闭记录、旧脚本和备份移入回收站 |
| 常规 | 调整检测间隔与持续识别时间 |

默认每 10 秒检测，游戏持续运行 15 秒后提醒。Steam 名单启动时读取，之后每 7 天刷新。保存设置后关闭窗口即可应用，不需要重启监控。

每次释放资源都需要确认，默认按钮与 Esc 都是取消。拒绝后本轮游戏不再自动询问；所有游戏退出至少 30 秒后重新启用。托盘支持暂停、手动触发、查看记录、登录自动启动和退出。

## 资源与安全边界

- 默认只关闭 WSL；旧配置不自动增加 Windows 退出目标。
- 全部 WSL 使用 shutdown；指定范围只终止所选发行版。其他实例仍运行时，WSL 虚拟机可能保留。
- Windows 应用必须按完整 EXE 路径配置。只对有窗口的匹配进程请求正常退出，按路径和启动时间校验以避免 PID 复用误伤，不强杀后台服务。
- 系统程序、终端和游戏模式自身不能作为目标；本次识别到的游戏也会被保护。
- Windows 应用可能显示保存对话框或继续驻留托盘，仍需自行处理。
- 关闭 WSL 前记录进程名称/PID、工作目录、Linux 启动标识并刷新磁盘。保存失败则取消释放资源。

**这些记录不是进程检查点，不能恢复未保存内容、视频生成、推理、训练或终端变量。** 确认关闭前请先保存或结束任务。WSL 内的终端、编辑器连接和 agent 会话会断开。

如果 Docker、编辑器等又启动 WSL，程序会提示，不会循环强杀。

## 历史清理

「历史」页的清理操作需确认，会移入回收站，并保留当前 config.json 与运行日志。旧安装文件使用固定范围识别，清理前检查是否仍被运行程序引用。记录仅用于事后查看，不是任务恢复文件。

## 安装与数据位置

- 系统目录安装：C:\Program Files\WslGameMode。
- 便携启动默认位置：%LOCALAPPDATA%\Programs\WslGameMode。
- 配置与记录：%LOCALAPPDATA%\WslGameMode，与程序目录分离。

ZIP 附带 Install-ProgramFiles.ps1。在管理员 PowerShell 中进入解压目录执行：

```powershell
$hash = (Get-FileHash .\WslGameMode.exe -Algorithm SHA256).Hash
.\Install-ProgramFiles.ps1 -SourceExecutable (Resolve-Path .\WslGameMode.exe).Path -ExpectedSHA256 $hash
```

启动 EXE 后会建立当前用户的开始菜单入口。安装到 Program Files 需要管理员权限，日常运行不需要。升级前从托盘退出旧版本；配置会保留。

登录自动启动默认关闭，可在托盘勾选。自启使用 --background，不会弹出设置。运行 EXE --uninstall 可移除自启，再从托盘退出即可停用，配置和记录保留。

## 兼容与隐私

要求 Windows 11 x64、WSL 2。使用自带 Windows PowerShell 5.1、.NET Framework 4.8、WPF、WinForms，无需 Python、Node.js 或 .NET SDK 运行环境。

EXE 为包含全部应用脚本的 .NET 启动器，只对子进程使用 ExecutionPolicy Bypass，不修改系统执行策略。当前未签名，下载可对照 SHA256SUMS.txt 校验。企业应用控制策略可能限制运行。

程序不发送网络请求，不注入或读取游戏内存，不保存命令行参数、环境变量或文件内容。数据只保存在本机。

## 构建与测试

```powershell
.\Build.ps1
.\tests\Test-Core.ps1
.\tests\Test-UI.ps1
.\tests\Test-Settings.ps1
.\tests\Test-Release.ps1
```

构建使用 Windows 自带 .NET Framework C# 编译器，无需联网安装依赖。产物为 dist 中的 EXE、ZIP、安装脚本与 SHA256SUMS.txt。

Settings 测试使用临时配置和模拟进程验证配置保存、资源范围、PID 复用保护与清理边界，不关闭实际资源。Test-Release.ps1 -CheckWsl 可做真实只读检测；Test-Windows.ps1 只读状态、刷新磁盘，不关闭 WSL。

EXE 支持 --check、--version、--background、--uninstall。图形程序的终端输出需通过带重定向的 Start-Process -Wait 捕获。

MIT License.
