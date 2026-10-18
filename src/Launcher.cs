using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Security.Cryptography;
using System.Text;
using System.Windows.Forms;
using Microsoft.Win32;

[assembly: AssemblyTitle("WSL Game Mode")]
[assembly: AssemblyDescription("Confirm, save WSL metadata, and shut down WSL when a game starts.")]
[assembly: AssemblyCompany("WSL Game Mode contributors")]
[assembly: AssemblyProduct("WSL Game Mode")]
[assembly: AssemblyVersion("0.1.0.0")]
[assembly: AssemblyFileVersion("0.1.0.0")]

internal static class Launcher
{
    private const string Version = "0.1.0";
    private const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";

    [STAThread]
    private static int Main(string[] args)
    {
        bool check = args.Length == 1 && args[0] == "--check";
        try
        {
            if (args.Length > 1 || (args.Length == 1 && !check && args[0] != "--version" && args[0] != "--uninstall"))
                throw new ArgumentException("Usage: WslGameMode.exe [--check | --version | --uninstall]");
            if (args.Length == 1 && args[0] == "--version")
            {
                Console.WriteLine(Version);
                return 0;
            }
            if (args.Length == 1 && args[0] == "--uninstall")
            {
                using (RegistryKey key = Registry.CurrentUser.OpenSubKey(RunKey, true))
                    if (key != null) key.DeleteValue("WslGameMode", false);
                MessageBox.Show("Automatic startup removed. Exit the watcher from the tray. Saved state and settings are retained.", "WSL Game Mode");
                return 0;
            }

            string dataDirectory = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "WslGameMode");
            string scriptDirectory = Path.Combine(dataDirectory, "releases", Version);
            Directory.CreateDirectory(scriptDirectory);
            foreach (string name in new string[] { "Core.ps1", "GameMode.ps1", "UI.ps1", "app.ico" })
                Extract(name, Path.Combine(scriptDirectory, name), true);
            Extract("config.json", Path.Combine(dataDirectory, "config.json"), false);

            string stableExecutable = Path.Combine(dataDirectory, "WslGameMode.exe");
            string currentExecutable = Assembly.GetExecutingAssembly().Location;
            if (!check && !String.Equals(currentExecutable, stableExecutable, StringComparison.OrdinalIgnoreCase))
                File.Copy(currentExecutable, stableExecutable, true);

            ProcessStartInfo info = new ProcessStartInfo();
            info.FileName = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "WindowsPowerShell", "v1.0", "powershell.exe");
            info.Arguments = "-NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File "
                + Quote(Path.Combine(scriptDirectory, "GameMode.ps1")) + " -DataDirectory " + Quote(dataDirectory)
                + (check ? " -CheckOnly" : "");
            info.WorkingDirectory = dataDirectory;
            info.UseShellExecute = false;
            info.CreateNoWindow = true;
            info.RedirectStandardOutput = true;
            info.RedirectStandardError = true;
            info.StandardOutputEncoding = Encoding.UTF8;
            info.StandardErrorEncoding = Encoding.UTF8;
            using (Process process = Process.Start(info))
            {
                // Drain both pipes concurrently: the long-running tray must never block on a full pipe.
                var stdout = process.StandardOutput.ReadToEndAsync();
                var stderr = process.StandardError.ReadToEndAsync();
                process.WaitForExit();
                if (check)
                {
                    Console.Write(stdout.Result);
                    Console.Error.Write(stderr.Result);
                }
                else if (process.ExitCode != 0)
                {
                    File.AppendAllText(Path.Combine(dataDirectory, "launcher-error.log"), DateTime.Now.ToString("o") + "\r\n" + stderr.Result + "\r\n", Encoding.UTF8);
                    MessageBox.Show("The watcher could not start. See launcher-error.log in " + dataDirectory, "WSL Game Mode", MessageBoxButtons.OK, MessageBoxIcon.Error);
                }
                return process.ExitCode;
            }
        }
        catch (Exception ex)
        {
            if (check) Console.Error.WriteLine(ex.Message);
            else MessageBox.Show(ex.Message, "WSL Game Mode", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
    }

    private static string Quote(string value)
    {
        if (value.IndexOf('"') >= 0 || value.EndsWith("\\")) throw new ArgumentException("Unsupported path.");
        return "\"" + value + "\"";
    }

    private static void Extract(string name, string destination, bool replace)
    {
        if (!replace && File.Exists(destination)) return;
        using (Stream input = Assembly.GetExecutingAssembly().GetManifestResourceStream("app." + name))
        {
            if (input == null) throw new InvalidOperationException("Missing resource: " + name);
            byte[] content;
            using (MemoryStream buffer = new MemoryStream()) { input.CopyTo(buffer); content = buffer.ToArray(); }
            if (File.Exists(destination))
            {
                using (SHA256 hash = SHA256.Create())
                    if (Convert.ToBase64String(hash.ComputeHash(File.ReadAllBytes(destination))) == Convert.ToBase64String(hash.ComputeHash(content))) return;
            }
            File.WriteAllBytes(destination, content);
        }
    }
}
