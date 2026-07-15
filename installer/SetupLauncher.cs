using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Windows.Forms;
using Microsoft.Win32;

[assembly: AssemblyTitle("Unlimited Clipboard Setup")]
[assembly: AssemblyProduct("Unlimited Clipboard")]
[assembly: AssemblyVersion("1.0.1.0")]
[assembly: AssemblyFileVersion("1.0.1.0")]

namespace InfiniteClipboardSetup
{
    internal static class Program
    {
        static readonly string AppName = new string(new[] { (char)0x65E0, (char)0x9650, (char)0x526A, (char)0x8D34, (char)0x677F });

        [STAThread]
        static void Main()
        {
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            try
            {
                Install();
                MessageBox.Show(AppName + " \u5DF2\u5B89\u88C5\u5B8C\u6210\u3002\r\n\r\n\u7A0B\u5E8F\u5DF2\u542F\u52A8\uFF0C\u4EE5\u540E\u767B\u5F55 Windows \u65F6\u4F1A\u5B89\u9759\u5730\u8FD0\u884C\u5728\u7CFB\u7EDF\u6258\u76D8\u3002", AppName + " \u5B89\u88C5", MessageBoxButtons.OK, MessageBoxIcon.Information);
            }
            catch (Exception ex)
            {
                MessageBox.Show("\u5B89\u88C5\u5931\u8D25\u3002\r\n\r\n" + ex.Message, AppName + " \u5B89\u88C5", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }

        static void Install()
        {
            string packageDir = AppDomain.CurrentDomain.BaseDirectory;
            string sourceApp = Path.Combine(packageDir, "InfiniteClipboard.exe");
            string sourceUpdater = Path.Combine(packageDir, "UpdateLauncher.exe");
            if (!File.Exists(sourceApp)) throw new FileNotFoundException("The application payload is missing.", sourceApp);

            string installDir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Programs", "InfiniteClipboard");
            string appPath = Path.Combine(installDir, "InfiniteClipboard.exe");
            string updaterPath = Path.Combine(installDir, "UpdateLauncher.exe");
            Directory.CreateDirectory(installDir);

            try
            {
                File.Copy(sourceApp, appPath, true);
                if (File.Exists(sourceUpdater)) File.Copy(sourceUpdater, updaterPath, true);
            }
            catch (IOException)
            {
                throw new InvalidOperationException("\u7A0B\u5E8F\u6B63\u5728\u8FD0\u884C\u3002\u8BF7\u5148\u5728\u6258\u76D8\u83DC\u5355\u9009\u62E9\u201C\u9000\u51FA\u201D\uFF0C\u518D\u91CD\u65B0\u8FD0\u884C\u5B89\u88C5\u5305\u3002");
            }

            string programs = Environment.GetFolderPath(Environment.SpecialFolder.Programs);
            string menuDir = Path.Combine(programs, AppName);
            Directory.CreateDirectory(menuDir);
            CreateShortcut(Path.Combine(menuDir, AppName + ".lnk"), appPath, "", installDir, "Clipboard history manager");
            CreateShortcut(Path.Combine(menuDir, "Uninstall " + AppName + ".lnk"), appPath, "--uninstall", installDir, "Uninstall InfiniteClipboard");
            CreateShortcut(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory), AppName + ".lnk"), appPath, "", installDir, "Clipboard history manager");

            using (RegistryKey run = Registry.CurrentUser.CreateSubKey(@"Software\Microsoft\Windows\CurrentVersion\Run"))
            {
                run.SetValue("InfiniteClipboard", "\"" + appPath + "\" --background");
            }

            using (RegistryKey uninstall = Registry.CurrentUser.CreateSubKey(@"Software\Microsoft\Windows\CurrentVersion\Uninstall\InfiniteClipboard"))
            {
                uninstall.SetValue("DisplayName", AppName);
                uninstall.SetValue("DisplayVersion", "1.0.1");
                uninstall.SetValue("Publisher", "Unlimited Clipboard");
                uninstall.SetValue("InstallLocation", installDir);
                uninstall.SetValue("UninstallString", "\"" + appPath + "\" --uninstall");
                uninstall.SetValue("NoModify", 1, RegistryValueKind.DWord);
                uninstall.SetValue("NoRepair", 1, RegistryValueKind.DWord);
            }

            Process.Start(new ProcessStartInfo(appPath) { WorkingDirectory = installDir, UseShellExecute = true });
        }

        static void CreateShortcut(string shortcutPath, string targetPath, string arguments, string workingDirectory, string description)
        {
            Type shellType = Type.GetTypeFromProgID("WScript.Shell");
            object shell = Activator.CreateInstance(shellType);
            object shortcut = shell.GetType().InvokeMember("CreateShortcut", BindingFlags.InvokeMethod, null, shell, new object[] { shortcutPath });
            Type shortcutType = shortcut.GetType();
            shortcutType.InvokeMember("TargetPath", BindingFlags.SetProperty, null, shortcut, new object[] { targetPath });
            shortcutType.InvokeMember("Arguments", BindingFlags.SetProperty, null, shortcut, new object[] { arguments });
            shortcutType.InvokeMember("WorkingDirectory", BindingFlags.SetProperty, null, shortcut, new object[] { workingDirectory });
            shortcutType.InvokeMember("IconLocation", BindingFlags.SetProperty, null, shortcut, new object[] { targetPath + ",0" });
            shortcutType.InvokeMember("Description", BindingFlags.SetProperty, null, shortcut, new object[] { description });
            shortcutType.InvokeMember("Save", BindingFlags.InvokeMethod, null, shortcut, null);
        }
    }
}
