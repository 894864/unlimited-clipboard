using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows.Forms;
using Microsoft.Win32;

[assembly: AssemblyTitle("Unlimited Clipboard Setup")]
[assembly: AssemblyProduct("Unlimited Clipboard")]
[assembly: AssemblyVersion("1.0.2.0")]
[assembly: AssemblyFileVersion("1.0.2.0")]

namespace InfiniteClipboardSetup
{
    internal static class Program
    {
        [STAThread]
        static void Main()
        {
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            Application.Run(new InstallerForm());
        }
    }

    internal sealed class InstallerForm : Form
    {
        const string VersionText = "1.0.2";
        const string UninstallKeyPath = @"Software\Microsoft\Windows\CurrentVersion\Uninstall\InfiniteClipboard";
        const string RunKeyPath = @"Software\Microsoft\Windows\CurrentVersion\Run";
        static readonly string AppName = "无限剪贴板";

        TextBox pathBox;
        Button browseButton;
        Button installButton;
        Button cancelButton;
        Label statusLabel;
        ProgressBar progress;
        CheckBox launchCheck;
        bool installing;
        bool installed;
        string installedAppPath = "";

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        static extern int RegisterWindowMessage(string lpString);

        [DllImport("user32.dll", SetLastError = true)]
        static extern bool PostMessage(IntPtr hWnd, int msg, IntPtr wParam, IntPtr lParam);

        public InstallerForm()
        {
            Text = AppName + " 安装向导";
            StartPosition = FormStartPosition.CenterScreen;
            FormBorderStyle = FormBorderStyle.FixedDialog;
            MaximizeBox = false;
            MinimizeBox = false;
            ClientSize = new Size(660, 390);
            BackColor = Color.FromArgb(244, 247, 252);
            Font = new Font("Microsoft YaHei UI", 9f);
            try { Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath); } catch { }
            BuildUi();
        }

        void BuildUi()
        {
            var root = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 1, RowCount = 2, Margin = new Padding(0), Padding = new Padding(0) };
            root.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
            root.RowStyles.Add(new RowStyle(SizeType.Absolute, 92));
            root.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
            Controls.Add(root);

            var header = new Panel { Dock = DockStyle.Fill, BackColor = Color.FromArgb(43, 103, 202), Padding = new Padding(28, 16, 28, 12), Margin = new Padding(0) };
            var title = new Label { Text = "安装 " + AppName, Dock = DockStyle.Top, Height = 36, Font = new Font("Microsoft YaHei UI", 17f, FontStyle.Bold), ForeColor = Color.White, TextAlign = ContentAlignment.MiddleLeft };
            var subtitle = new Label { Text = "版本 " + VersionText + " · 选择安装位置后开始安装", Dock = DockStyle.Fill, ForeColor = Color.FromArgb(218, 233, 255), TextAlign = ContentAlignment.MiddleLeft };
            header.Controls.Add(subtitle);
            header.Controls.Add(title);
            root.Controls.Add(header, 0, 0);

            var body = new Panel { Dock = DockStyle.Fill, Padding = new Padding(28, 22, 28, 18), Margin = new Padding(0) };
            root.Controls.Add(body, 0, 1);

            var locationLabel = new Label { Text = "安装位置", AutoSize = true, Location = new Point(28, 22), ForeColor = Color.FromArgb(48, 61, 80), Font = new Font("Microsoft YaHei UI", 9f, FontStyle.Bold) };
            body.Controls.Add(locationLabel);

            pathBox = new TextBox { Location = new Point(28, 52), Width = 510, Height = 30, Text = DefaultInstallDirectory(), BorderStyle = BorderStyle.FixedSingle };
            browseButton = new Button { Text = "浏览…", Location = new Point(548, 50), Size = new Size(84, 31), FlatStyle = FlatStyle.Flat, BackColor = Color.FromArgb(232, 238, 248), ForeColor = Color.FromArgb(47, 83, 142) };
            browseButton.FlatAppearance.BorderSize = 0;
            browseButton.Click += BrowseClicked;
            body.Controls.Add(pathBox);
            body.Controls.Add(browseButton);

            var locationHint = new Label { Text = "默认安装到当前用户的软件目录；无需管理员权限。升级时会沿用现有安装位置。", AutoSize = false, Location = new Point(28, 90), Size = new Size(604, 34), ForeColor = Color.FromArgb(92, 105, 125), TextAlign = ContentAlignment.MiddleLeft };
            body.Controls.Add(locationHint);

            statusLabel = new Label { Text = "准备安装", Location = new Point(28, 142), Size = new Size(604, 30), ForeColor = Color.FromArgb(48, 61, 80), TextAlign = ContentAlignment.MiddleLeft };
            progress = new ProgressBar { Location = new Point(28, 176), Size = new Size(604, 12), Style = ProgressBarStyle.Blocks, Minimum = 0, Maximum = 100, Value = 0 };
            body.Controls.Add(statusLabel);
            body.Controls.Add(progress);

            launchCheck = new CheckBox { Text = "完成后启动 " + AppName, AutoSize = true, Checked = true, Location = new Point(28, 216), ForeColor = Color.FromArgb(48, 61, 80) };
            body.Controls.Add(launchCheck);

            installButton = new Button { Text = "安装", Size = new Size(104, 36), Location = new Point(528, 250), Anchor = AnchorStyles.Right | AnchorStyles.Bottom, FlatStyle = FlatStyle.Flat, BackColor = Color.FromArgb(48, 104, 199), ForeColor = Color.White };
            installButton.FlatAppearance.BorderSize = 0;
            installButton.Click += InstallClicked;
            cancelButton = new Button { Text = "取消", Size = new Size(104, 36), Location = new Point(414, 250), Anchor = AnchorStyles.Right | AnchorStyles.Bottom, FlatStyle = FlatStyle.Flat, BackColor = Color.FromArgb(232, 238, 248), ForeColor = Color.FromArgb(47, 83, 142) };
            cancelButton.FlatAppearance.BorderSize = 0;
            cancelButton.Click += delegate { Close(); };
            body.Controls.Add(cancelButton);
            body.Controls.Add(installButton);
            AcceptButton = installButton;
            CancelButton = cancelButton;
        }

        void BrowseClicked(object sender, EventArgs e)
        {
            using (var dialog = new FolderBrowserDialog())
            {
                dialog.Description = "选择“无限剪贴板”的安装文件夹";
                dialog.SelectedPath = pathBox.Text;
                dialog.ShowNewFolderButton = true;
                if (dialog.ShowDialog(this) == DialogResult.OK) pathBox.Text = dialog.SelectedPath;
            }
        }

        void InstallClicked(object sender, EventArgs e)
        {
            if (installed)
            {
                Close();
                return;
            }
            if (installing) return;

            string installDir;
            try { installDir = ValidateInstallDirectory(pathBox.Text); }
            catch (Exception ex)
            {
                MessageBox.Show(this, ex.Message, "安装位置无效", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }

            installing = true;
            SetControlsEnabled(false);
            statusLabel.Text = "正在准备安装…";
            statusLabel.ForeColor = Color.FromArgb(48, 61, 80);
            progress.Style = ProgressBarStyle.Marquee;
            progress.MarqueeAnimationSpeed = 24;

            ThreadPool.QueueUserWorkItem(delegate
            {
                try
                {
                    string appPath = Install(installDir);
                    BeginInvoke(new Action(delegate { ShowCompleted(appPath); }));
                }
                catch (Exception ex)
                {
                    BeginInvoke(new Action(delegate { ShowFailure(ex.Message); }));
                }
            });
        }

        string Install(string installDir)
        {
            string packageDir = AppDomain.CurrentDomain.BaseDirectory;
            string sourceApp = Path.Combine(packageDir, "InfiniteClipboard.exe");
            string sourceUpdater = Path.Combine(packageDir, "UpdateLauncher.exe");
            if (!File.Exists(sourceApp)) throw new FileNotFoundException("安装包缺少主程序文件。", sourceApp);
            if (!File.Exists(sourceUpdater)) throw new FileNotFoundException("安装包缺少更新组件。", sourceUpdater);

            string previousInstallDir = ExistingInstallDirectory();
            bool isUpgrade = !string.IsNullOrWhiteSpace(previousInstallDir) || File.Exists(Path.Combine(installDir, "InfiniteClipboard.exe"));
            bool startupEnabled = IsStartupEnabled();
            StopRunningApplication();

            Directory.CreateDirectory(installDir);
            string appPath = Path.Combine(installDir, "InfiniteClipboard.exe");
            string updaterPath = Path.Combine(installDir, "UpdateLauncher.exe");
            CopyWithRetry(sourceApp, appPath);
            CopyWithRetry(sourceUpdater, updaterPath);

            string programs = Environment.GetFolderPath(Environment.SpecialFolder.Programs);
            string menuDir = Path.Combine(programs, AppName);
            Directory.CreateDirectory(menuDir);
            CreateShortcut(Path.Combine(menuDir, AppName + ".lnk"), appPath, "", installDir, "Clipboard history manager");
            CreateShortcut(Path.Combine(menuDir, "卸载" + AppName + ".lnk"), appPath, "--uninstall", installDir, "Uninstall InfiniteClipboard");
            CreateShortcut(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory), AppName + ".lnk"), appPath, "", installDir, "Clipboard history manager");

            using (RegistryKey run = Registry.CurrentUser.CreateSubKey(RunKeyPath))
            {
                bool shouldEnableStartup = isUpgrade ? startupEnabled : true;
                if (shouldEnableStartup) run.SetValue("InfiniteClipboard", "\"" + appPath + "\" --background");
                else run.DeleteValue("InfiniteClipboard", false);
            }

            long estimatedSizeKb = Math.Max(1, (new FileInfo(appPath).Length + new FileInfo(updaterPath).Length) / 1024);
            using (RegistryKey uninstall = Registry.CurrentUser.CreateSubKey(UninstallKeyPath))
            {
                uninstall.SetValue("DisplayName", AppName);
                uninstall.SetValue("DisplayVersion", VersionText);
                uninstall.SetValue("Publisher", "Unlimited Clipboard");
                uninstall.SetValue("InstallLocation", installDir);
                uninstall.SetValue("DisplayIcon", appPath + ",0");
                uninstall.SetValue("UninstallString", "\"" + appPath + "\" --uninstall");
                uninstall.SetValue("EstimatedSize", (int)Math.Min(int.MaxValue, estimatedSizeKb), RegistryValueKind.DWord);
                uninstall.SetValue("InstallDate", DateTime.Now.ToString("yyyyMMdd"));
                uninstall.SetValue("NoModify", 1, RegistryValueKind.DWord);
                uninstall.SetValue("NoRepair", 1, RegistryValueKind.DWord);
            }

            if (!string.IsNullOrWhiteSpace(previousInstallDir) && !SamePath(previousInstallDir, installDir)) CleanPreviousInstallation(previousInstallDir);
            return appPath;
        }

        void ShowCompleted(string appPath)
        {
            installing = false;
            installed = true;
            installedAppPath = appPath;
            progress.Style = ProgressBarStyle.Blocks;
            progress.Value = 100;
            statusLabel.Text = "安装完成。点击“完成”后关闭安装向导。";
            statusLabel.ForeColor = Color.FromArgb(45, 125, 82);
            pathBox.Enabled = false;
            browseButton.Enabled = false;
            cancelButton.Visible = false;
            installButton.Enabled = true;
            installButton.Text = "完成";
            installButton.Focus();
        }

        void ShowFailure(string message)
        {
            installing = false;
            progress.Style = ProgressBarStyle.Blocks;
            progress.Value = 0;
            statusLabel.Text = "安装未完成：" + message;
            statusLabel.ForeColor = Color.FromArgb(181, 72, 54);
            SetControlsEnabled(true);
            installButton.Text = "重试";
        }

        void SetControlsEnabled(bool enabled)
        {
            pathBox.Enabled = enabled;
            browseButton.Enabled = enabled;
            installButton.Enabled = enabled;
            cancelButton.Enabled = enabled;
        }

        protected override void OnFormClosing(FormClosingEventArgs e)
        {
            if (installing)
            {
                e.Cancel = true;
                System.Media.SystemSounds.Beep.Play();
                return;
            }
            base.OnFormClosing(e);
        }

        protected override void OnFormClosed(FormClosedEventArgs e)
        {
            base.OnFormClosed(e);
            if (installed && launchCheck.Checked && File.Exists(installedAppPath))
            {
                try { Process.Start(new ProcessStartInfo(installedAppPath) { WorkingDirectory = Path.GetDirectoryName(installedAppPath), UseShellExecute = true }); }
                catch { }
            }
        }

        static string ValidateInstallDirectory(string value)
        {
            string trimmed = (value ?? "").Trim().Trim('"');
            if (trimmed.Length == 0) throw new InvalidOperationException("请选择安装位置。");
            string full = Path.GetFullPath(trimmed).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
            string root = Path.GetPathRoot(full).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
            if (string.Equals(full, root, StringComparison.OrdinalIgnoreCase)) throw new InvalidOperationException("不能直接安装到磁盘根目录，请选择一个独立文件夹。");
            return full;
        }

        static string DefaultInstallDirectory()
        {
            string existing = ExistingInstallDirectory();
            if (!string.IsNullOrWhiteSpace(existing)) return existing;
            return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Programs", "InfiniteClipboard");
        }

        static string ExistingInstallDirectory()
        {
            try
            {
                using (RegistryKey key = Registry.CurrentUser.OpenSubKey(UninstallKeyPath, false))
                {
                    return key == null ? "" : Convert.ToString(key.GetValue("InstallLocation"));
                }
            }
            catch { return ""; }
        }

        static bool IsStartupEnabled()
        {
            try
            {
                using (RegistryKey key = Registry.CurrentUser.OpenSubKey(RunKeyPath, false))
                {
                    return key != null && key.GetValue("InfiniteClipboard") != null;
                }
            }
            catch { return false; }
        }

        static void StopRunningApplication()
        {
            Process[] running = Process.GetProcessesByName("InfiniteClipboard");
            if (running.Length == 0) return;
            int message = RegisterWindowMessage("InfiniteClipboard.Exit.v1");
            PostMessage((IntPtr)0xffff, message, IntPtr.Zero, IntPtr.Zero);
            DateTime deadline = DateTime.UtcNow.AddSeconds(10);
            while (DateTime.UtcNow < deadline)
            {
                if (Process.GetProcessesByName("InfiniteClipboard").Length == 0) return;
                Thread.Sleep(200);
            }
            throw new InvalidOperationException("程序仍在运行。请从系统托盘退出后重试。");
        }

        static void CopyWithRetry(string source, string destination)
        {
            Exception last = null;
            for (int i = 0; i < 8; i++)
            {
                try
                {
                    File.Copy(source, destination, true);
                    return;
                }
                catch (IOException ex) { last = ex; Thread.Sleep(250); }
                catch (UnauthorizedAccessException ex) { last = ex; Thread.Sleep(250); }
            }
            throw new InvalidOperationException("无法写入安装目录。请确认目录可写，并关闭正在运行的旧版本。", last);
        }

        static void CleanPreviousInstallation(string directory)
        {
            try
            {
                foreach (string name in new string[] { "InfiniteClipboard.exe", "UpdateLauncher.exe", "InfiniteClipboard.ps1", "Launch.vbs", "Uninstall.ps1", "启动无限剪贴板.vbs" })
                {
                    string path = Path.Combine(directory, name);
                    if (File.Exists(path)) File.Delete(path);
                }
                if (Directory.Exists(directory) && Directory.GetFileSystemEntries(directory).Length == 0) Directory.Delete(directory, false);
            }
            catch { }
        }

        static bool SamePath(string left, string right)
        {
            try { return string.Equals(Path.GetFullPath(left).TrimEnd('\\'), Path.GetFullPath(right).TrimEnd('\\'), StringComparison.OrdinalIgnoreCase); }
            catch { return false; }
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
