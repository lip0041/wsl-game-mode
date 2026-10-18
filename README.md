# WSL Game Mode

启动游戏时，提醒你保存工作，然后关闭 WSL 释放资源。Windows 托盘小工具，支持 Steam、永劫无间和三角洲行动。

## 使用

1. 从本仓库的 Releases 下载 `WslGameMode.exe`，或解压 Windows x64 ZIP。
2. 双击运行，程序驻留系统托盘。无需管理员权限。
3. 游戏启动后，程序每 10 秒检测一次，持续识别 15 秒后弹出置顶确认窗口。
4. 保存正在进行的工作，再点击「保存状态并关闭 WSL」。默认按钮是「暂不关闭」，Esc 也会取消。

托盘右键可暂停、手动触发、查看状态、编辑名单、设置登录自动启动或退出。便携运行默认不添加启动项。Steam 名单启动时读取，之后每 7 天刷新。游戏全部退出至少 30 秒后重新启用提醒。

Windows 11 风格的确认界面跟随系统浅色/深色主题，并提供任务栏入口。全屏游戏下如看不到窗口，可用 Alt+Tab 切换。

## 能保存什么

关闭前记录运行发行版、进程名称/PID、可读取的工作目录、Linux 启动标识，并执行磁盘刷新。任何保存或刷新失败都会取消关闭。

**这些记录不是进程检查点，不能自动恢复未保存文件、视频生成、模型推理、训练或终端变量。** 关闭前请在应用里保存或结束任务。全部 WSL 发行版都会关闭，WSL 内的编辑器连接、终端和 agent 会话会断开。

关闭后如果 WSL 被 Docker、编辑器或其他程序重新启动，会提示「WSL 又在运行」，不会连续重复关闭。Windows 原生 Ollama/ComfyUI 不受影响。

## 配置与隐私

数据位于 `%LOCALAPPDATA%\WslGameMode`：

| 文件 | 用途 |
|---|---|
| `config.json` | 检测间隔、游戏白名单、Steam 排除名单 |
| `state/` | 关闭前的本地状态记录 |
| `game-mode.log` | 启动、确认和关闭日志 |
| `releases/0.1.0/` | EXE 解包的应用脚本 |

配置保留已有设置。程序不发送网络请求，不读取游戏内存，不注入游戏，也不保存命令行参数、环境变量或文件内容。状态与日志仅保存在本机，请按需删除。

Steam 匹配游戏目录中有窗口的进程，排除常见桌面工具、启动器、安装器和崩溃上报器。独立游戏默认使用精确进程名：`NarakaBladepoint`、`DeltaForceClient-Win64-Shipping`、`DeltaForceClient`。`Root` 留空不限制路径；填写后会限制可读路径，受保护进程路径不可读时仍按精确进程名匹配。新游戏可加入 `StandaloneGames`。编辑配置后重启托盘程序生效。

## 技术与系统要求

- Windows 11 x64、WSL 2；使用系统自带 Windows PowerShell 5.1、.NET Framework 4.8、WPF 和 WinForms。
- EXE 是包含全部应用脚本的 .NET 启动器，首次运行解包到当前用户目录。没有额外的 Python、Node.js 或 .NET SDK 运行依赖。
- 不更改系统 PowerShell 执行策略；只对子进程使用 `-ExecutionPolicy Bypass` 来运行本程序内置脚本。受企业应用控制策略限制的设备可能无法运行。
- 当前版本未做代码签名，Windows 可能显示未知发布者或 SmartScreen 提示。可对照 Release 的 SHA256SUMS.txt 校验下载。
- 从早期脚本版升级：先退出旧托盘程序，并移除旧的 `Startup\WSL Game Mode.lnk`，再启动 EXE，避免重复监控。

登录启动项由托盘菜单控制，保存在当前用户的 Run 注册表项。运行 `WslGameMode.exe --uninstall` 可移除该启动项；随后从托盘退出即可停用。设置和状态会保留。

## 开发与构建

在 Windows PowerShell 中执行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Build.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-Core.ps1
powershell -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\Test-UI.ps1
```

产物位于 `dist/`：EXE、ZIP 和 SHA256SUMS.txt。构建使用 Windows 自带的 .NET Framework C# 编译器，无需联网安装依赖。

只读自检：`WslGameMode.exe --check`；版本：`WslGameMode.exe --version`。EXE 为图形程序，在终端捕获输出时应使用带输出重定向的 `Start-Process -Wait`。真实 WSL 保存测试为 `tests/Test-Windows.ps1`，只对已运行的发行版读取状态、刷新磁盘，不执行关闭。

MIT License.
