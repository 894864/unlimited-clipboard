param(
    [switch]$NoWindow,
    [switch]$CompileOnly
)

$ErrorActionPreference = "Stop"

$source = @"
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Net;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using System.Windows.Forms;
using System.Xml.Serialization;
using Microsoft.Win32;
using System.Reflection;

[assembly: AssemblyTitle("Unlimited Clipboard")]
[assembly: AssemblyProduct("Unlimited Clipboard")]
[assembly: AssemblyVersion("1.0.2.0")]
[assembly: AssemblyFileVersion("1.0.2.0")]

namespace InfiniteClipboard
{
    public class ClipItem
    {
        public string Id;
        public string Type;
        public DateTime CreatedUtc;
        public DateTime LastUsedUtc;
        public string Preview;
        public string DataFile;
        public string Hash;
        public long SizeBytes;
        public bool Favorite;
        public bool ArchivedFiles;
        public string ArchiveDir;
    }

    public class ClipIndex
    {
        public int SettingsVersion = 8;
        public List<ClipItem> Items = new List<ClipItem>();
        public int RetentionDays = 7; // 0 = forever
        public bool CaptureText = true;
        public bool CaptureImages = true;
        public bool CaptureFiles = true;
        public bool NotifyOnCapture = false;
        public int MaxItemMb = 1;
        public bool SaveMultipleFiles = false;
        public bool PauseCapture = false;
        public bool StartupConfigured = false;
        public bool AutoUpdate = true;
        public string UpdateFeedUrl = UpdateService.DefaultFeedUrl;
        public string LastNotifiedUpdateVersion = "";
        public int ContentSplitterDistance = 0;
        public int UiFontSize = 2; // 1=small, 2=standard, 3=large, 4=extra large
        public int CustomHotkeyModifiers = 0;
        public int CustomHotkeyKey = 0;
        public int MainWindowWidth = 0;
        public int ListColumn0Width = 0;
        public int ListColumn1Width = 0;
        public int ListColumn2Width = 0;
        public int ListColumn3Width = 0;
        public int ListColumn4Width = 0;
        public int ListColumn5Width = 0;
    }

    public class UpdateInfo
    {
        public Version Version;
        public Uri DownloadUrl;
        public string Sha256;
        public string Notes;
    }

    public static class UpdateService
    {
        // Build-Installer.ps1 replaces this placeholder with the public HTTPS release feed.
        public const string DefaultFeedUrl = "__UPDATE_FEED_URL__";

        public static string CurrentVersionText
        {
            get
            {
                Version version = Assembly.GetExecutingAssembly().GetName().Version;
                return version == null ? "1.0.2" : version.Major + "." + version.Minor + "." + Math.Max(0, version.Build);
            }
        }

        static string JsonValue(string json, string name)
        {
            Match match = Regex.Match(json ?? "", "\\\"" + Regex.Escape(name) + "\\\"\\s*:\\s*\\\"(?<value>(?:\\\\.|[^\\\"])*)\\\"", RegexOptions.IgnoreCase);
            if (!match.Success) return "";
            return Regex.Unescape(match.Groups["value"].Value).Replace("\\/", "/");
        }

        public static bool TryCheck(string feedUrl, out UpdateInfo update, out string message)
        {
            update = null;
            message = "";
            Uri feed;
            if (string.IsNullOrWhiteSpace(feedUrl))
            {
                message = "尚未配置更新发布地址。";
                return false;
            }
            if (!Uri.TryCreate(feedUrl.Trim(), UriKind.Absolute, out feed) || feed.Scheme != Uri.UriSchemeHttps)
            {
                message = "更新发布地址必须是 HTTPS 链接。";
                return false;
            }

            try
            {
                ServicePointManager.SecurityProtocol = (SecurityProtocolType)3072; // TLS 1.2
                using (var client = new WebClient())
                {
                    client.Headers[HttpRequestHeader.UserAgent] = "InfiniteClipboard/" + CurrentVersionText;
                    string json = client.DownloadString(feed);
                    Version latest;
                    string versionText = JsonValue(json, "version");
                    string downloadText = JsonValue(json, "downloadUrl");
                    string sha256 = JsonValue(json, "sha256");
                    Uri download;
                    if (!Version.TryParse(versionText, out latest) || !Uri.TryCreate(feed, downloadText, out download) || download.Scheme != Uri.UriSchemeHttps || !Regex.IsMatch(sha256 ?? "", "^[a-fA-F0-9]{64}$"))
                    {
                        message = "更新信息格式无效，已停止本次更新。";
                        return false;
                    }

                    Version current = Assembly.GetExecutingAssembly().GetName().Version;
                    if (latest.CompareTo(current) <= 0)
                    {
                        message = "已是最新版本 " + CurrentVersionText + "。";
                        return true;
                    }

                    update = new UpdateInfo { Version = latest, DownloadUrl = download, Sha256 = sha256.ToUpperInvariant(), Notes = JsonValue(json, "notes") };
                    message = "发现新版本 " + DisplayVersion(latest) + "。";
                    return true;
                }
            }
            catch
            {
                message = "暂时无法连接更新服务，请稍后重试。";
                return false;
            }
        }

        public static string DownloadPackage(UpdateInfo update)
        {
            if (update == null) throw new InvalidOperationException("没有可安装的更新。");
            string updateDir = Path.Combine(Path.GetTempPath(), "InfiniteClipboard", "updates");
            Directory.CreateDirectory(updateDir);
            string finalPath = Path.Combine(updateDir, "InfiniteClipboard-Setup-" + DisplayVersion(update.Version) + ".exe");
            string tempPath = finalPath + ".downloading";
            try { if (File.Exists(tempPath)) File.Delete(tempPath); } catch { }
            using (var client = new WebClient())
            {
                client.Headers[HttpRequestHeader.UserAgent] = "InfiniteClipboard/" + CurrentVersionText;
                client.DownloadFile(update.DownloadUrl, tempPath);
            }
            string hash;
            using (var sha = SHA256.Create())
            using (var stream = File.OpenRead(tempPath))
            {
                hash = BitConverter.ToString(sha.ComputeHash(stream)).Replace("-", "");
            }
            if (!string.Equals(hash, update.Sha256, StringComparison.OrdinalIgnoreCase))
            {
                try { File.Delete(tempPath); } catch { }
                throw new InvalidOperationException("更新文件校验失败，已取消安装。");
            }
            if (File.Exists(finalPath)) File.Delete(finalPath);
            File.Move(tempPath, finalPath);
            return finalPath;
        }

        public static string DisplayVersion(Version version)
        {
            return version.Major + "." + version.Minor + "." + Math.Max(0, version.Build);
        }
    }

    public static class Native
    {
        public const int WM_CLIPBOARDUPDATE = 0x031D;
        public const int WM_HOTKEY = 0x0312;
        public const int HWND_BROADCAST = 0xffff;
        public const int MOD_ALT = 0x0001;
        public const int MOD_CONTROL = 0x0002;
        public const int MOD_SHIFT = 0x0004;
        public const int MOD_NOREPEAT = 0x4000;
        public const int VK_0 = 0x30;
        public const int VK_1 = 0x31;
        public const int CF_UNICODETEXT = 13;
        public const int CF_HDROP = 15;
        public const int CF_DIB = 8;
        public const uint GMEM_MOVEABLE = 0x0002;
        public const uint GMEM_ZEROINIT = 0x0040;

        [DllImport("user32.dll", SetLastError = true)]
        public static extern bool AddClipboardFormatListener(IntPtr hwnd);

        [DllImport("user32.dll", SetLastError = true)]
        public static extern bool RemoveClipboardFormatListener(IntPtr hwnd);

        [DllImport("user32.dll", SetLastError = true)]
        public static extern bool OpenClipboard(IntPtr hWndNewOwner);

        [DllImport("user32.dll", SetLastError = true)]
        public static extern bool CloseClipboard();

        [DllImport("user32.dll", SetLastError = true)]
        public static extern bool EmptyClipboard();

        [DllImport("user32.dll", SetLastError = true)]
        public static extern IntPtr GetClipboardData(uint uFormat);

        [DllImport("user32.dll", SetLastError = true)]
        public static extern IntPtr SetClipboardData(uint uFormat, IntPtr hMem);

        [DllImport("user32.dll")]
        public static extern bool IsClipboardFormatAvailable(uint format);

        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern IntPtr GlobalAlloc(uint uFlags, UIntPtr dwBytes);

        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern IntPtr GlobalLock(IntPtr hMem);

        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern bool GlobalUnlock(IntPtr hMem);

        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern UIntPtr GlobalSize(IntPtr hMem);

        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern IntPtr GlobalFree(IntPtr hMem);

        [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
        public static extern uint DragQueryFile(IntPtr hDrop, uint iFile, StringBuilder lpszFile, uint cch);

        [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
        public static extern int SetCurrentProcessExplicitAppUserModelID(string appID);

        [DllImport("user32.dll", SetLastError = true)]
        public static extern bool RegisterHotKey(IntPtr hWnd, int id, int fsModifiers, int vk);

        [DllImport("user32.dll", SetLastError = true)]
        public static extern bool UnregisterHotKey(IntPtr hWnd, int id);

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        public static extern int RegisterWindowMessage(string lpString);

        [DllImport("user32.dll", SetLastError = true)]
        public static extern bool PostMessage(IntPtr hWnd, int msg, IntPtr wParam, IntPtr lParam);

        [DllImport("user32.dll", SetLastError = true)]
        public static extern bool DestroyIcon(IntPtr hIcon);
    }

    public static class AppIcon
    {
        public static Icon Create(string executablePath)
        {
            try
            {
                if (string.Equals(Path.GetFileName(executablePath), "InfiniteClipboard.exe", StringComparison.OrdinalIgnoreCase))
                {
                    using (var embedded = Icon.ExtractAssociatedIcon(executablePath))
                    {
                        if (embedded != null) return (Icon)embedded.Clone();
                    }
                }
            }
            catch { }

            using (var bitmap = new Bitmap(64, 64))
            using (var g = Graphics.FromImage(bitmap))
            {
                g.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
                g.Clear(Color.Transparent);
                using (var basePath = RoundedRect(new Rectangle(4, 4, 56, 56), 15))
                using (var baseBrush = new System.Drawing.Drawing2D.LinearGradientBrush(new Rectangle(4, 4, 56, 56), Color.FromArgb(255, 254, 249), Color.FromArgb(239, 233, 222), System.Drawing.Drawing2D.LinearGradientMode.Vertical))
                using (var edgePen = new Pen(Color.FromArgb(205, 220, 211, 196), 1f))
                {
                    g.FillPath(baseBrush, basePath);
                    g.DrawPath(edgePen, basePath);
                }
                using (var fold = new System.Drawing.Drawing2D.GraphicsPath())
                using (var foldBrush = new System.Drawing.Drawing2D.LinearGradientBrush(new Rectangle(42, 4, 18, 20), Color.FromArgb(255, 255, 252), Color.FromArgb(225, 216, 201), System.Drawing.Drawing2D.LinearGradientMode.ForwardDiagonal))
                using (var foldPen = new Pen(Color.FromArgb(150, 205, 194, 175), 1f))
                {
                    fold.StartFigure();
                    fold.AddLine(43, 4, 48, 4);
                    fold.AddBezier(48, 4, 54, 6, 58, 10, 60, 16);
                    fold.AddLine(60, 21, 51, 21);
                    fold.AddBezier(51, 21, 46, 21, 43, 18, 43, 13);
                    fold.CloseFigure();
                    g.FillPath(foldBrush, fold);
                    g.DrawPath(foldPen, fold);
                }
                using (var infinityPath = new System.Drawing.Drawing2D.GraphicsPath())
                using (var groovePen = new Pen(Color.FromArgb(150, 184, 171, 150), 8f))
                using (var paperPen = new Pen(Color.FromArgb(255, 250, 246, 237), 5.5f))
                {
                    infinityPath.StartFigure();
                    infinityPath.AddBezier(15, 34, 20, 23, 27, 23, 32, 34);
                    infinityPath.AddBezier(32, 34, 37, 45, 44, 45, 49, 34);
                    infinityPath.AddBezier(49, 34, 44, 23, 37, 23, 32, 34);
                    infinityPath.AddBezier(32, 34, 27, 45, 20, 45, 15, 34);
                    groovePen.StartCap = groovePen.EndCap = System.Drawing.Drawing2D.LineCap.Round;
                    groovePen.LineJoin = System.Drawing.Drawing2D.LineJoin.Round;
                    paperPen.StartCap = paperPen.EndCap = System.Drawing.Drawing2D.LineCap.Round;
                    paperPen.LineJoin = System.Drawing.Drawing2D.LineJoin.Round;
                    g.DrawPath(groovePen, infinityPath);
                    g.DrawPath(paperPen, infinityPath);
                }
                IntPtr handle = bitmap.GetHicon();
                try
                {
                    using (var icon = Icon.FromHandle(handle)) return (Icon)icon.Clone();
                }
                finally { Native.DestroyIcon(handle); }
            }
        }

        static System.Drawing.Drawing2D.GraphicsPath RoundedRect(Rectangle rect, int radius)
        {
            int d = radius * 2;
            var path = new System.Drawing.Drawing2D.GraphicsPath();
            path.AddArc(rect.Left, rect.Top, d, d, 180, 90);
            path.AddArc(rect.Right - d, rect.Top, d, d, 270, 90);
            path.AddArc(rect.Right - d, rect.Bottom - d, d, d, 0, 90);
            path.AddArc(rect.Left, rect.Bottom - d, d, d, 90, 90);
            path.CloseFigure();
            return path;
        }
    }

    public class Store
    {
        public readonly string Root;
        public readonly string ItemDir;
        public readonly string IndexPath;
        public ClipIndex Index;

        public Store()
        {
            Root = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "InfiniteClipboard");
            ItemDir = Path.Combine(Root, "items");
            IndexPath = Path.Combine(Root, "index.xml");
            Directory.CreateDirectory(ItemDir);
            Load();
        }

        public void Load()
        {
            if (!File.Exists(IndexPath))
            {
                Index = new ClipIndex();
                Save();
                return;
            }

            try
            {
                using (var fs = File.OpenRead(IndexPath))
                {
                    Index = (ClipIndex)new XmlSerializer(typeof(ClipIndex)).Deserialize(fs);
                }
                if (Index.Items == null) Index.Items = new List<ClipItem>();
                bool upgradeToV3 = Index.SettingsVersion < 3;
                bool upgradeToV4 = Index.SettingsVersion < 4;
                bool upgradeToV5 = Index.SettingsVersion < 5;
                if (Index.SettingsVersion < 2)
                {
                    if (Index.MaxItemMb <= 0 || Index.MaxItemMb == 100) Index.MaxItemMb = 1;
                }
                else if (Index.MaxItemMb <= 0) Index.MaxItemMb = 1;
                // This release adds the silent VBS startup launcher. Enable it once on upgrade;
                // the user can still turn it off later in Settings.
                if (upgradeToV3) Index.StartupConfigured = false;
                // Existing installs did not have this field. Enable safe update checks by default,
                // but never auto-install without the user's explicit click.
                if (upgradeToV4) Index.AutoUpdate = true;
                if (Index.UpdateFeedUrl == null || (upgradeToV5 && string.IsNullOrWhiteSpace(Index.UpdateFeedUrl))) Index.UpdateFeedUrl = UpdateService.DefaultFeedUrl;
                if (Index.LastNotifiedUpdateVersion == null) Index.LastNotifiedUpdateVersion = "";
                if (Index.ContentSplitterDistance < 0) Index.ContentSplitterDistance = 0;
                if (Index.UiFontSize < 1 || Index.UiFontSize > 4) Index.UiFontSize = 2;
                Index.SettingsVersion = 8;
            }
            catch
            {
                string backup = IndexPath + ".broken-" + DateTime.Now.ToString("yyyyMMdd-HHmmss");
                try { File.Copy(IndexPath, backup, true); } catch { }
                Index = new ClipIndex();
                Save();
            }
        }

        public void Save()
        {
            Directory.CreateDirectory(Root);
            Directory.CreateDirectory(ItemDir);
            string tmp = IndexPath + ".tmp";
            using (var fs = File.Create(tmp))
            {
                new XmlSerializer(typeof(ClipIndex)).Serialize(fs, Index);
            }
            if (File.Exists(IndexPath)) File.Delete(IndexPath);
            File.Move(tmp, IndexPath);
        }

        public string DataPath(ClipItem item)
        {
            return Path.Combine(ItemDir, item.DataFile);
        }

        public string ArchivePath(ClipItem item)
        {
            if (string.IsNullOrEmpty(item.ArchiveDir)) return "";
            return Path.Combine(ItemDir, item.ArchiveDir);
        }

        public ClipItem AddOrPromote(string type, byte[] bytes, string preview)
        {
            if (bytes == null || bytes.Length == 0) return null;
            if (Index.MaxItemMb > 0 && bytes.Length > Index.MaxItemMb * 1024L * 1024L) return null;

            string hash = HashBytes(Combine(Encoding.UTF8.GetBytes(type), bytes));
            ClipItem existing = Index.Items.FirstOrDefault(x => x.Hash == hash && x.Type == type);
            if (existing != null)
            {
                existing.CreatedUtc = DateTime.UtcNow;
                Index.Items.Remove(existing);
                Index.Items.Insert(0, existing);
                Save();
                return existing;
            }

            var item = new ClipItem();
            item.Id = Guid.NewGuid().ToString("N");
            item.Type = type;
            item.CreatedUtc = DateTime.UtcNow;
            item.LastUsedUtc = DateTime.MinValue;
            item.Preview = TrimPreview(preview);
            item.DataFile = item.Id + ".bin";
            item.Hash = hash;
            item.SizeBytes = bytes.LongLength;
            item.Favorite = false;
            File.WriteAllBytes(DataPath(item), bytes);
            Index.Items.Insert(0, item);
            Save();
            return item;
        }

        public ClipItem AddArchivedFiles(List<string> sourcePaths)
        {
            if (sourcePaths == null || sourcePaths.Count == 0) return null;
            long total = TotalPathBytes(sourcePaths);
            if (Index.MaxItemMb > 0 && total > Index.MaxItemMb * 1024L * 1024L) return null;

            string signature = FileSignature(sourcePaths);
            string hash = HashBytes(Encoding.UTF8.GetBytes("files-archive|" + signature));
            ClipItem existing = Index.Items.FirstOrDefault(x => x.Hash == hash && x.Type == "files" && x.ArchivedFiles);
            if (existing != null)
            {
                existing.CreatedUtc = DateTime.UtcNow;
                Index.Items.Remove(existing);
                Index.Items.Insert(0, existing);
                Save();
                return existing;
            }

            var item = new ClipItem();
            item.Id = Guid.NewGuid().ToString("N");
            item.Type = "files";
            item.CreatedUtc = DateTime.UtcNow;
            item.LastUsedUtc = DateTime.MinValue;
            item.DataFile = item.Id + ".files.txt";
            item.ArchivedFiles = true;
            item.ArchiveDir = item.Id + "_files";
            item.Hash = hash;
            item.SizeBytes = total;
            item.Favorite = false;

            string archiveRoot = ArchivePath(item);
            Directory.CreateDirectory(archiveRoot);
            var copied = new List<string>();
            foreach (string src in sourcePaths)
            {
                if (File.Exists(src))
                {
                    string dest = UniquePath(Path.Combine(archiveRoot, Path.GetFileName(src)));
                    File.Copy(src, dest, true);
                    copied.Add(dest);
                }
                else if (Directory.Exists(src))
                {
                    string dest = UniquePath(Path.Combine(archiveRoot, Path.GetFileName(src)));
                    CopyDirectory(src, dest);
                    copied.Add(dest);
                }
            }

            if (copied.Count == 0)
            {
                try { Directory.Delete(archiveRoot, true); } catch { }
                return null;
            }

            string manifest = string.Join(Environment.NewLine, copied.ToArray());
            item.Preview = TrimPreview("文件归档：" + copied.Count + " 项，" + FormatBytes(total) + Environment.NewLine + manifest);
            File.WriteAllText(DataPath(item), manifest, Encoding.UTF8);
            Index.Items.Insert(0, item);
            Save();
            return item;
        }

        public byte[] ReadBytes(ClipItem item)
        {
            string path = DataPath(item);
            if (!File.Exists(path)) return new byte[0];
            return File.ReadAllBytes(path);
        }

        public string ReadText(ClipItem item)
        {
            return Encoding.UTF8.GetString(ReadBytes(item));
        }

        public void Delete(ClipItem item)
        {
            Index.Items.Remove(item);
            DeleteItemFiles(item);
            Save();
        }

        public int CleanupExpired()
        {
            if (Index.RetentionDays == 0)
            {
                Save();
                return 0;
            }

            DateTime cutoff = DateTime.UtcNow.AddDays(-Index.RetentionDays);
            var expired = Index.Items.Where(x => !x.Favorite && x.CreatedUtc < cutoff).ToList();
            foreach (var item in expired)
            {
                DeleteItemFiles(item);
                Index.Items.Remove(item);
            }
            Save();
            return expired.Count;
        }

        public long TotalBytes()
        {
            long total = 0;
            foreach (var item in Index.Items) total += item.SizeBytes;
            return total;
        }

        static byte[] Combine(byte[] a, byte[] b)
        {
            byte[] c = new byte[a.Length + b.Length];
            Buffer.BlockCopy(a, 0, c, 0, a.Length);
            Buffer.BlockCopy(b, 0, c, a.Length, b.Length);
            return c;
        }

        static string HashBytes(byte[] bytes)
        {
            using (var sha = SHA256.Create())
            {
                return BitConverter.ToString(sha.ComputeHash(bytes)).Replace("-", "");
            }
        }

        void DeleteItemFiles(ClipItem item)
        {
            try { File.Delete(DataPath(item)); } catch { }
            try
            {
                string archive = ArchivePath(item);
                if (!string.IsNullOrEmpty(archive) && Directory.Exists(archive)) Directory.Delete(archive, true);
            }
            catch { }
        }

        static long TotalPathBytes(IEnumerable<string> paths)
        {
            long total = 0;
            foreach (string path in paths)
            {
                try
                {
                    if (File.Exists(path))
                    {
                        total += new FileInfo(path).Length;
                    }
                    else if (Directory.Exists(path))
                    {
                        foreach (string file in Directory.GetFiles(path, "*", SearchOption.AllDirectories))
                        {
                            total += new FileInfo(file).Length;
                        }
                    }
                }
                catch { }
            }
            return total;
        }

        static string FileSignature(IEnumerable<string> paths)
        {
            var parts = new List<string>();
            foreach (string path in paths)
            {
                try
                {
                    if (File.Exists(path))
                    {
                        var f = new FileInfo(path);
                        parts.Add(path + "|" + f.Length + "|" + f.LastWriteTimeUtc.Ticks);
                    }
                    else if (Directory.Exists(path))
                    {
                        parts.Add(path + "|dir|" + TotalPathBytes(new string[] { path }));
                    }
                    else
                    {
                        parts.Add(path + "|missing");
                    }
                }
                catch { parts.Add(path + "|unknown"); }
            }
            return string.Join("\n", parts.ToArray());
        }

        static string UniquePath(string path)
        {
            if (!File.Exists(path) && !Directory.Exists(path)) return path;
            string dir = Path.GetDirectoryName(path);
            string name = Path.GetFileNameWithoutExtension(path);
            string ext = Path.GetExtension(path);
            for (int i = 2; i < 10000; i++)
            {
                string candidate = Path.Combine(dir, name + " (" + i + ")" + ext);
                if (!File.Exists(candidate) && !Directory.Exists(candidate)) return candidate;
            }
            return Path.Combine(dir, name + " (" + Guid.NewGuid().ToString("N") + ")" + ext);
        }

        static void CopyDirectory(string sourceDir, string destDir)
        {
            Directory.CreateDirectory(destDir);
            foreach (string file in Directory.GetFiles(sourceDir))
            {
                File.Copy(file, Path.Combine(destDir, Path.GetFileName(file)), true);
            }
            foreach (string dir in Directory.GetDirectories(sourceDir))
            {
                CopyDirectory(dir, Path.Combine(destDir, Path.GetFileName(dir)));
            }
        }

        static string FormatBytes(long bytes)
        {
            string[] units = new string[] { "B", "KB", "MB", "GB" };
            double v = bytes;
            int i = 0;
            while (v >= 1024 && i < units.Length - 1) { v /= 1024; i++; }
            return v.ToString(i == 0 ? "0" : "0.0") + units[i];
        }

        static string TrimPreview(string s)
        {
            if (s == null) return "";
            s = s.Replace("\r\n", "\n").Replace("\r", "\n");
            // The list is intentionally a one-line summary. Skip leading blank lines so
            // copied text beginning with line breaks still has a useful preview.
            string first = s.Split(new char[] { '\n' }).FirstOrDefault(x => !string.IsNullOrWhiteSpace(x));
            if (string.IsNullOrEmpty(first)) return "（空白文本）";
            first = first.Trim();
            if (first.Length > 240) first = first.Substring(0, 240) + "…";
            return first;
        }
    }

    public class MainForm : Form
    {
        Store store;
        ListView list;
        TextBox search;
        ComboBox typeFilter;
        TextBox previewText;
        PictureBox previewImage;
        Label status;
        Panel toastPanel;
        Label toastLabel;
        Timer toastTimer;
        NotifyIcon tray;
        ContextMenuStrip trayMenu;
        Timer cleanupTimer;
        SplitContainer contentSplitter;
        Icon appIcon;
        Button settingsButton;
        Label updateBadge;
        Label mainHotkeyHint;
        UpdateInfo availableUpdate;
        bool checkingForUpdate = false;
        string lastUpdateStatus = "";
        readonly object updateLock = new object();
        bool isExiting = false;
        bool closeHintShown = false;
        bool suppressCapture = false;
        bool startHidden = false;
        bool hotkeyRegistered = false;
        int hotkeyErrorCode = 0;
        string activeHotkeyText = "";
        int activeHotkeyModifiers = 0;
        int activeHotkeyKey = 0;
        string hotkeyWarningText = "";
        bool listLayoutReady = false;
        bool suppressListColumnSync = false;
        int lastListClientWidth = 0;
        readonly int[] trackedListColumnWidths = new int[6];
        static readonly int[] MinimumListColumnWidths = new int[] { 32, 50, 140, 105, 55, 52 };
        int appliedUiFontSize = 2;
        string appScriptPath;
        const int HOTKEY_ID = 9417;
        static readonly int SHOW_MESSAGE = Native.RegisterWindowMessage("InfiniteClipboard.ShowMainWindow.v1");
        static readonly int EXIT_MESSAGE = Native.RegisterWindowMessage("InfiniteClipboard.Exit.v1");

        public MainForm(string scriptPath, bool startInBackground)
        {
            store = new Store();
            appScriptPath = scriptPath;
            startHidden = startInBackground;
            Text = "Unlimited Clipboard";
            int preferredWidth = store.Index.MainWindowWidth >= 780 ? store.Index.MainWindowWidth : 980;
            Width = Math.Max(780, Math.Min(Screen.PrimaryScreen.WorkingArea.Width, preferredWidth));
            Height = 680;
            MinimumSize = new Size(780, 520);
            StartPosition = FormStartPosition.CenterScreen;
            appIcon = AppIcon.Create(Application.ExecutablePath);
            Icon = appIcon;
            BackColor = Color.FromArgb(242, 246, 252);
            Font = new Font("Microsoft YaHei UI", 9f, FontStyle.Regular);

            BuildUi(scriptPath);
            ApplyUiFontSize();
            Native.AddClipboardFormatListener(Handle);
            TryRegisterHotkey();
            BuildTray();
            if (!string.IsNullOrWhiteSpace(hotkeyWarningText))
            {
                Shown += delegate { BeginInvoke(new Action(delegate { if (tray != null) tray.ShowBalloonTip(5000, "自定义快捷键冲突", hotkeyWarningText, ToolTipIcon.Warning); })); };
            }
            else if (!hotkeyRegistered)
            {
                Shown += delegate { BeginInvoke(new Action(delegate { if (tray != null) tray.ShowBalloonTip(5000, "快捷键未启用", HotkeyStatusText() + " 可在设置里重试。", ToolTipIcon.Warning); })); };
            }
            if (!store.Index.StartupConfigured)
            {
                SetStartup(scriptPath, true);
                store.Index.StartupConfigured = true;
                store.Save();
            }
            else if (IsStartupEnabled(scriptPath))
            {
                // Re-save the enabled entry so older versions are upgraded to the no-console launcher.
                SetStartup(scriptPath, true);
            }
            cleanupTimer = new Timer();
            cleanupTimer.Interval = 30 * 60 * 1000;
            cleanupTimer.Tick += delegate { store.CleanupExpired(); RefreshList(); };
            cleanupTimer.Start();
            store.CleanupExpired();
            RefreshList();
            CaptureCurrentClipboard();
            if (store.Index.AutoUpdate)
            {
                Shown += delegate { BeginInvoke(new Action(delegate { StartUpdateCheck(false, null); })); };
            }
            if (startHidden)
            {
                Shown += delegate { BeginInvoke(new Action(delegate { Hide(); })); };
            }
        }

        protected override void WndProc(ref Message m)
        {
            if (m.Msg == Native.WM_CLIPBOARDUPDATE)
            {
                if (!store.Index.PauseCapture && !suppressCapture) CaptureCurrentClipboard();
            }
            else if (m.Msg == Native.WM_HOTKEY && m.WParam.ToInt32() == HOTKEY_ID)
            {
                ShowAndActivate();
            }
            else if (m.Msg == SHOW_MESSAGE)
            {
                ShowAndActivate();
            }
            else if (m.Msg == EXIT_MESSAGE)
            {
                isExiting = true;
                Close();
            }
            base.WndProc(ref m);
        }

        protected override void OnFormClosing(FormClosingEventArgs e)
        {
            // The title-bar close button always keeps the clipboard listener alive.
            // Windows shutdown is deliberately allowed to continue so cleanup can run normally.
            if (!isExiting && e.CloseReason != CloseReason.WindowsShutDown && e.CloseReason != CloseReason.TaskManagerClosing)
            {
                e.Cancel = true;
                Hide();
                if (!closeHintShown)
                {
                    closeHintShown = true;
                    string shortcutHint = hotkeyRegistered ? "按 " + activeHotkeyText + " 或" : "可";
                    tray.ShowBalloonTip(1800, "无限剪贴板仍在运行", "窗口已隐藏到系统托盘。" + shortcutHint + "双击托盘图标重新打开。", ToolTipIcon.Info);
                }
                return;
            }
            Native.RemoveClipboardFormatListener(Handle);
            if (hotkeyRegistered) Native.UnregisterHotKey(Handle, HOTKEY_ID);
            if (tray != null) tray.Dispose();
            base.OnFormClosing(e);
        }

        protected override void OnResize(EventArgs e)
        {
            base.OnResize(e);
            PositionToast();
            if (WindowState == FormWindowState.Normal && store != null && Width >= MinimumSize.Width)
            {
                store.Index.MainWindowWidth = Width;
            }
        }

        protected override void OnResizeEnd(EventArgs e)
        {
            base.OnResizeEnd(e);
            if (store != null)
            {
                SaveListLayout(false);
                store.Save();
            }
        }

        bool TryRegisterHotkey()
        {
            hotkeyWarningText = "";
            if (store.Index.CustomHotkeyModifiers != 0 && store.Index.CustomHotkeyKey != 0)
            {
                ReleaseCurrentHotkey();
                string customText = FormatHotkey(store.Index.CustomHotkeyModifiers, store.Index.CustomHotkeyKey);
                if (RegisterHotkeyCandidate(store.Index.CustomHotkeyModifiers, store.Index.CustomHotkeyKey, customText))
                {
                    RefreshTrayMenu();
                    return true;
                }
                int customError = hotkeyErrorCode;
                bool fallback = TryRegisterAutomaticHotkey(false);
                hotkeyWarningText = fallback
                    ? "自定义快捷键 " + customText + " 已被占用，已临时改用 " + activeHotkeyText + "。"
                    : "自定义快捷键 " + customText + " 无法注册（Windows 错误 " + customError + "），自动分配也失败。";
                return fallback;
            }
            return TryRegisterAutomaticHotkey(false);
        }

        bool TryRegisterAutomaticHotkey(bool clearCustom)
        {
            if (clearCustom)
            {
                store.Index.CustomHotkeyModifiers = 0;
                store.Index.CustomHotkeyKey = 0;
                store.Save();
            }
            hotkeyWarningText = "";
            ReleaseCurrentHotkey();
            int[] keys = new int[] { Native.VK_1, Native.VK_1 + 1, Native.VK_1 + 2, Native.VK_1 + 3, Native.VK_1 + 4, Native.VK_1 + 5, Native.VK_1 + 6, Native.VK_1 + 7, Native.VK_1 + 8, Native.VK_0 };
            for (int i = 0; i < keys.Length; i++)
            {
                string label = FormatHotkey(Native.MOD_CONTROL, keys[i]);
                if (RegisterHotkeyCandidate(Native.MOD_CONTROL, keys[i], label)) break;
            }
            RefreshTrayMenu();
            return hotkeyRegistered;
        }

        void ReleaseCurrentHotkey()
        {
            if (hotkeyRegistered)
            {
                Native.UnregisterHotKey(Handle, HOTKEY_ID);
            }
            hotkeyRegistered = false;
            activeHotkeyText = "";
            activeHotkeyModifiers = 0;
            activeHotkeyKey = 0;
            hotkeyErrorCode = 0;
        }

        bool RegisterHotkeyCandidate(int modifiers, int key, string label)
        {
            if (Native.RegisterHotKey(Handle, HOTKEY_ID, modifiers | Native.MOD_NOREPEAT, key))
            {
                hotkeyRegistered = true;
                activeHotkeyModifiers = modifiers;
                activeHotkeyKey = key;
                activeHotkeyText = label;
                hotkeyErrorCode = 0;
                return true;
            }
            hotkeyErrorCode = Marshal.GetLastWin32Error();
            return false;
        }

        bool TryApplyCustomHotkey(int modifiers, int key, out string error)
        {
            string candidate = FormatHotkey(modifiers, key);
            int previousModifiers = activeHotkeyModifiers;
            int previousKey = activeHotkeyKey;
            string previousText = activeHotkeyText;
            ReleaseCurrentHotkey();
            if (RegisterHotkeyCandidate(modifiers, key, candidate))
            {
                store.Index.CustomHotkeyModifiers = modifiers;
                store.Index.CustomHotkeyKey = key;
                store.Save();
                hotkeyWarningText = "";
                RefreshTrayMenu();
                error = "";
                return true;
            }

            int candidateError = hotkeyErrorCode;
            if (previousKey != 0 && previousModifiers != 0)
            {
                RegisterHotkeyCandidate(previousModifiers, previousKey, previousText);
            }
            if (!hotkeyRegistered) TryRegisterAutomaticHotkey(false);
            RefreshTrayMenu();
            error = candidateError == 1409
                ? "快捷键 " + candidate + " 已被其他程序占用，请换一个组合。"
                : "快捷键 " + candidate + " 注册失败（Windows 错误 " + candidateError + "），原快捷键已恢复。";
            return false;
        }

        static int HotkeyModifiersFromKeys(Keys modifiers)
        {
            int result = 0;
            if ((modifiers & Keys.Control) == Keys.Control) result |= Native.MOD_CONTROL;
            if ((modifiers & Keys.Alt) == Keys.Alt) result |= Native.MOD_ALT;
            if ((modifiers & Keys.Shift) == Keys.Shift) result |= Native.MOD_SHIFT;
            return result;
        }

        static bool IsHotkeyKey(Keys key)
        {
            return key != Keys.None && key != Keys.ControlKey && key != Keys.LControlKey && key != Keys.RControlKey
                && key != Keys.Menu && key != Keys.LMenu && key != Keys.RMenu
                && key != Keys.ShiftKey && key != Keys.LShiftKey && key != Keys.RShiftKey
                && key != Keys.Escape && key != Keys.Tab && key != Keys.Enter;
        }

        static string FormatHotkey(int modifiers, int keyValue)
        {
            var parts = new List<string>();
            if ((modifiers & Native.MOD_CONTROL) != 0) parts.Add("Ctrl");
            if ((modifiers & Native.MOD_ALT) != 0) parts.Add("Alt");
            if ((modifiers & Native.MOD_SHIFT) != 0) parts.Add("Shift");
            Keys key = (Keys)keyValue;
            string keyText;
            if (key >= Keys.D0 && key <= Keys.D9) keyText = ((int)key - (int)Keys.D0).ToString();
            else if (key >= Keys.NumPad0 && key <= Keys.NumPad9) keyText = "Num" + ((int)key - (int)Keys.NumPad0);
            else keyText = new KeysConverter().ConvertToString(key);
            parts.Add(keyText);
            return string.Join("+", parts.ToArray());
        }

        string HotkeyStatusText()
        {
            if (hotkeyRegistered) return activeHotkeyText + " 已启用。";
            if (hotkeyErrorCode == 1409) return "Ctrl+1 至 Ctrl+0 均被占用（Windows 错误 1409）。";
            return "快捷键未启用：系统注册失败（Windows 错误 " + hotkeyErrorCode + "）。";
        }

        float UiFontDelta
        {
            get { return Math.Max(1, Math.Min(4, store.Index.UiFontSize)) - 2; }
        }

        void ApplyUiFontSize()
        {
            int target = Math.Max(1, Math.Min(4, store.Index.UiFontSize));
            float delta = target - appliedUiFontSize;
            if (Math.Abs(delta) < 0.01f) return;
            AdjustControlFonts(this, delta);
            appliedUiFontSize = target;
            if (list != null) list.Invalidate();
        }

        void AdjustControlFonts(Control control, float delta)
        {
            foreach (Control child in control.Controls) AdjustControlFonts(child, delta);
            Font oldFont = control.Font;
            if (oldFont != null)
            {
                control.Font = new Font(oldFont.FontFamily, Math.Max(6f, oldFont.Size + delta), oldFont.Style, oldFont.Unit);
            }
        }

        void BuildUi(string scriptPath)
        {
            var root = new TableLayoutPanel();
            root.Dock = DockStyle.Fill;
            root.BackColor = Color.FromArgb(242, 246, 252);
            root.Padding = new Padding(14, 12, 14, 12);
            root.RowCount = 3;
            root.ColumnCount = 1;
            root.RowStyles.Add(new RowStyle(SizeType.Absolute, 62));
            root.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
            root.RowStyles.Add(new RowStyle(SizeType.Absolute, 28));
            Controls.Add(root);

            var top = new TableLayoutPanel();
            top.Dock = DockStyle.Fill;
            top.BackColor = Color.White;
            top.ColumnCount = 6;
            top.RowCount = 1;
            top.Padding = new Padding(14, 10, 14, 10);
            top.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 50));
            top.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 10));
            top.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 10));
            top.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 10));
            top.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 10));
            top.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 10));
            top.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
            root.Controls.Add(top, 0, 0);

            search = new TextBox { Dock = DockStyle.Fill, Font = new Font("Microsoft YaHei UI", 10f), BorderStyle = BorderStyle.FixedSingle, BackColor = Color.FromArgb(248, 250, 253), ForeColor = Color.FromArgb(45, 55, 72), Margin = new Padding(0, 0, 4, 0) };
            search.TextChanged += delegate { RefreshList(); };
            top.Controls.Add(search, 0, 0);

            var btnSearch = MakeButton("⌕", delegate { search.Focus(); });
            btnSearch.Font = new Font("Segoe UI", 16f, FontStyle.Regular);
            var btnCopy = MakeButton("复制", delegate { RestoreSelected(); });
            var btnFav = MakeButton("收藏/取消", delegate { ToggleFavorite(); });
            var btnDelete = MakeButton("删除", delegate { DeleteSelected(); });
            var settingsHost = new Panel { Dock = DockStyle.Fill, Margin = new Padding(2, 0, 2, 0) };
            settingsButton = MakeButton("设置", delegate { ShowSettings(); });
            settingsButton.Margin = new Padding(0);
            settingsButton.Dock = DockStyle.Fill;
            settingsHost.Controls.Add(settingsButton);
            updateBadge = new Label { Visible = false, Width = 9, Height = 9, BackColor = Color.FromArgb(220, 61, 61), BorderStyle = BorderStyle.FixedSingle, Anchor = AnchorStyles.Top | AnchorStyles.Right, Location = new Point(52, 5) };
            new ToolTip().SetToolTip(updateBadge, "发现新版本，请在设置中更新");
            settingsHost.Controls.Add(updateBadge);
            top.Controls.Add(btnSearch, 1, 0);
            top.Controls.Add(btnCopy, 2, 0);
            top.Controls.Add(btnFav, 3, 0);
            top.Controls.Add(btnDelete, 4, 0);
            top.Controls.Add(settingsHost, 5, 0);

            contentSplitter = new SplitContainer();
            contentSplitter.Dock = DockStyle.Fill;
            contentSplitter.Orientation = Orientation.Horizontal;
            contentSplitter.IsSplitterFixed = false;
            contentSplitter.SplitterWidth = 9;
            contentSplitter.BackColor = Color.FromArgb(218, 229, 244);
            contentSplitter.Panel1MinSize = 150;
            contentSplitter.Panel2MinSize = 120;
            contentSplitter.SplitterMoved += delegate
            {
                if (contentSplitter.SplitterDistance > 0)
                {
                    store.Index.ContentSplitterDistance = contentSplitter.SplitterDistance;
                    store.Save();
                }
            };
            contentSplitter.HandleCreated += delegate
            {
                BeginInvoke(new Action(delegate
                {
                    int available = contentSplitter.Height - contentSplitter.SplitterWidth;
                    int preferred = store.Index.ContentSplitterDistance > 0 ? store.Index.ContentSplitterDistance : (available * 62 / 100);
                    int lower = contentSplitter.Panel1MinSize;
                    int upper = Math.Max(lower, available - contentSplitter.Panel2MinSize);
                    contentSplitter.SplitterDistance = Math.Max(lower, Math.Min(upper, preferred));
                }));
            };
            root.Controls.Add(contentSplitter, 0, 1);

            var listHost = new TableLayoutPanel();
            listHost.Dock = DockStyle.Fill;
            listHost.BackColor = Color.White;
            listHost.Padding = new Padding(12, 10, 12, 12);
            listHost.RowCount = 2;
            listHost.ColumnCount = 1;
            listHost.RowStyles.Add(new RowStyle(SizeType.Absolute, 34));
            listHost.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
            contentSplitter.Panel1.Controls.Add(listHost);

            var listFilterBar = new TableLayoutPanel();
            listFilterBar.Dock = DockStyle.Fill;
            listFilterBar.Padding = new Padding(0, 0, 0, 6);
            listFilterBar.ColumnCount = 6;
            listFilterBar.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
            listFilterBar.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 92));
            listFilterBar.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 18));
            listFilterBar.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
            listFilterBar.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 18));
            listFilterBar.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 126));
            listHost.Controls.Add(listFilterBar, 0, 0);

            var filterLabel = new Label { Text = "筛选：", AutoSize = true, Anchor = AnchorStyles.Left, TextAlign = ContentAlignment.MiddleLeft, ForeColor = Color.FromArgb(92, 105, 125), Margin = new Padding(0), Padding = new Padding(0, 2, 0, 0) };
            listFilterBar.Controls.Add(filterLabel, 0, 0);
            typeFilter = new ComboBox { DropDownStyle = ComboBoxStyle.DropDownList, Dock = DockStyle.Fill, FlatStyle = FlatStyle.Flat, BackColor = Color.FromArgb(248, 250, 253), ForeColor = Color.FromArgb(45, 55, 72), Margin = new Padding(0, 2, 0, 2) };
            typeFilter.Items.AddRange(new object[] { "全部", "文本", "图片", "文件", "收藏" });
            typeFilter.SelectedIndex = 0;
            typeFilter.SelectedIndexChanged += delegate { RefreshList(); };
            listFilterBar.Controls.Add(typeFilter, 1, 0);
            mainHotkeyHint = new Label { Text = "快捷键：未启用", Dock = DockStyle.Fill, TextAlign = ContentAlignment.MiddleLeft, AutoEllipsis = true, ForeColor = Color.FromArgb(92, 105, 125), Margin = new Padding(0), Padding = new Padding(0, 2, 0, 0) };
            listFilterBar.Controls.Add(mainHotkeyHint, 3, 0);
            var resetColumnWidths = new Button { Text = "恢复默认列宽", Dock = DockStyle.Fill, FlatStyle = FlatStyle.Flat, BackColor = Color.FromArgb(232, 238, 248), ForeColor = Color.FromArgb(47, 83, 142), FlatAppearance = { BorderSize = 0 }, Margin = new Padding(0) };
            resetColumnWidths.Click += delegate { RestoreDefaultListColumns(); };
            listFilterBar.Controls.Add(resetColumnWidths, 5, 0);

            list = new ListView();
            list.Dock = DockStyle.Fill;
            list.View = View.Details;
            list.FullRowSelect = true;
            list.HideSelection = false;
            list.MultiSelect = true;
            list.BorderStyle = BorderStyle.FixedSingle;
            list.BackColor = Color.White;
            list.ForeColor = Color.FromArgb(40, 51, 68);
            list.Font = new Font("Microsoft YaHei UI", 9f);
            list.GridLines = false;
            list.OwnerDraw = true;
            list.HeaderStyle = ColumnHeaderStyle.Nonclickable;
            list.Columns.Add("★", 36);
            list.Columns.Add("类型", 60);
            list.Columns.Add("内容预览", 260);
            list.Columns.Add("时间", 128);
            list.Columns.Add("大小", 70);
            list.Columns.Add("复制", 58);
            list.SelectedIndexChanged += delegate { UpdatePreview(); };
            list.DoubleClick += delegate { RestoreSelected(); };
            list.DrawColumnHeader += DrawListHeader;
            list.DrawSubItem += DrawListSubItem;
            list.KeyDown += ListKeyDown;
            list.MouseClick += ListMouseClick;
            list.ColumnWidthChanging += ListColumnWidthChanging;
            list.ColumnWidthChanged += ListColumnWidthChanged;
            list.Resize += ListResized;
            list.HandleCreated += delegate { BeginInvoke(new Action(InitializeListColumns)); };
            listHost.Controls.Add(list, 0, 1);

            var previewHost = new TableLayoutPanel();
            previewHost.Dock = DockStyle.Fill;
            previewHost.BackColor = Color.White;
            previewHost.Padding = new Padding(12, 8, 12, 12);
            previewHost.RowCount = 2;
            previewHost.ColumnCount = 1;
            previewHost.RowStyles.Add(new RowStyle(SizeType.Absolute, 26));
            previewHost.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
            var previewTitle = new Label { Text = "内容预览", Dock = DockStyle.Fill, ForeColor = Color.FromArgb(92, 105, 125), TextAlign = ContentAlignment.MiddleLeft, Font = new Font("Microsoft YaHei UI", 9f, FontStyle.Bold) };
            previewHost.Controls.Add(previewTitle, 0, 0);
            var previewPanel = new Panel();
            previewPanel.Dock = DockStyle.Fill;
            previewPanel.BackColor = Color.FromArgb(248, 250, 253);
            previewText = new TextBox();
            previewText.Multiline = true;
            previewText.ScrollBars = ScrollBars.Both;
            previewText.ReadOnly = true;
            previewText.BackColor = Color.FromArgb(248, 250, 253);
            previewText.ForeColor = Color.FromArgb(53, 65, 82);
            previewText.BorderStyle = BorderStyle.FixedSingle;
            previewText.Font = new Font("Microsoft YaHei UI", 9.5f);
            previewText.Dock = DockStyle.Fill;
            previewImage = new PictureBox();
            previewImage.Dock = DockStyle.Fill;
            previewImage.SizeMode = PictureBoxSizeMode.Zoom;
            previewImage.Visible = false;
            previewPanel.Controls.Add(previewText);
            previewPanel.Controls.Add(previewImage);
            previewHost.Controls.Add(previewPanel, 0, 1);
            contentSplitter.Panel2.Controls.Add(previewHost);

            status = new Label();
            status.Dock = DockStyle.Fill;
            status.TextAlign = ContentAlignment.MiddleLeft;
            status.Padding = new Padding(10, 0, 0, 0);
            status.ForeColor = Color.FromArgb(94, 106, 124);
            status.Font = new Font("Microsoft YaHei UI", 8.5f);
            root.Controls.Add(status, 0, 2);

            toastPanel = new Panel();
            toastPanel.Visible = false;
            toastPanel.BackColor = Color.FromArgb(35, 77, 151);
            toastPanel.Size = new Size(220, 54);
            toastPanel.BorderStyle = BorderStyle.FixedSingle;
            toastLabel = new Label();
            toastLabel.Dock = DockStyle.Fill;
            toastLabel.ForeColor = Color.White;
            toastLabel.TextAlign = ContentAlignment.MiddleCenter;
            toastLabel.Font = new Font(Font.FontFamily, 11f, FontStyle.Bold);
            toastPanel.Controls.Add(toastLabel);
            Controls.Add(toastPanel);
            toastPanel.BringToFront();
            toastTimer = new Timer();
            toastTimer.Interval = 1300;
            toastTimer.Tick += delegate { toastTimer.Stop(); toastPanel.Visible = false; };
            PositionToast();
        }

        Button MakeButton(string text, EventHandler handler)
        {
            var b = new Button { Text = text, Dock = DockStyle.Fill, FlatStyle = FlatStyle.Flat, FlatAppearance = { BorderSize = 0 }, Cursor = Cursors.Hand, Font = new Font("Microsoft YaHei UI", 8.5f, FontStyle.Bold), BackColor = Color.FromArgb(234, 240, 249), ForeColor = Color.FromArgb(47, 83, 142), Margin = new Padding(2, 0, 2, 0) };
            b.FlatAppearance.MouseOverBackColor = Color.FromArgb(216, 228, 246);
            b.Click += handler;
            return b;
        }

        void ShowToast(string message)
        {
            if (toastPanel == null || toastLabel == null) return;
            toastLabel.Text = message;
            PositionToast();
            toastPanel.Visible = true;
            toastPanel.BringToFront();
            toastTimer.Stop();
            toastTimer.Start();
        }

        void PositionToast()
        {
            if (toastPanel == null) return;
            toastPanel.Left = Math.Max(0, (ClientSize.Width - toastPanel.Width) / 2);
            toastPanel.Top = Math.Max(0, (ClientSize.Height - toastPanel.Height) / 2);
        }

        void ShowSettings()
        {
            using (var form = new Form())
            {
                form.Text = "设置";
                form.StartPosition = FormStartPosition.CenterParent;
                form.FormBorderStyle = FormBorderStyle.Sizable;
                form.MaximizeBox = true;
                form.MinimizeBox = false;
                form.ClientSize = new Size(700, 730);
                form.MinimumSize = new Size(640, 720);
                form.BackColor = Color.FromArgb(242, 246, 252);
                form.Font = new Font("Microsoft YaHei UI", 9f + UiFontDelta);

                var layout = new TableLayoutPanel();
                layout.Dock = DockStyle.Fill;
                layout.Padding = new Padding(18, 16, 18, 16);
                layout.ColumnCount = 1;
                layout.RowCount = 6;
                layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 80));
                layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 110));
                layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 110));
                layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 220));
                layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 130));
                layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 46));
                form.Controls.Add(layout);

                var captureGroup = new GroupBox { Text = "记录类型", Dock = DockStyle.Fill };
                var capturePanel = new FlowLayoutPanel { Dock = DockStyle.Fill, Padding = new Padding(14, 12, 14, 8), WrapContents = true };
                var capText = new CheckBox { Text = "文本", AutoSize = true, Checked = store.Index.CaptureText, Margin = new Padding(4, 7, 28, 4) };
                var capImage = new CheckBox { Text = "图片", AutoSize = true, Checked = store.Index.CaptureImages, Margin = new Padding(4, 7, 28, 4) };
                var capFiles = new CheckBox { Text = "文件", AutoSize = true, Checked = store.Index.CaptureFiles, Margin = new Padding(4, 7, 28, 4) };
                capturePanel.Controls.Add(capText);
                capturePanel.Controls.Add(capImage);
                capturePanel.Controls.Add(capFiles);
                captureGroup.Controls.Add(capturePanel);
                layout.Controls.Add(captureGroup, 0, 0);

                var retentionGroup = new GroupBox { Text = "保留时间", Dock = DockStyle.Fill };
                var retentionPanel = new TableLayoutPanel { Dock = DockStyle.Fill, Padding = new Padding(14, 12, 14, 8), ColumnCount = 2, RowCount = 2 };
                retentionPanel.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 150));
                retentionPanel.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
                retentionPanel.RowStyles.Add(new RowStyle(SizeType.Absolute, 32));
                retentionPanel.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
                retentionGroup.Controls.Add(retentionPanel);
                retentionPanel.Controls.Add(new Label { Text = "档位", Dock = DockStyle.Fill, TextAlign = ContentAlignment.MiddleLeft }, 0, 0);
                var retentionChoice = new ComboBox { DropDownStyle = ComboBoxStyle.DropDownList, Dock = DockStyle.Left, Width = 180, Margin = new Padding(0, 3, 0, 0) };
                retentionChoice.Items.AddRange(new object[] { "24小时", "48小时", "一周", "两周", "一月", "三月", "一年", "永久" });
                SelectRetentionChoice(retentionChoice);
                retentionPanel.Controls.Add(retentionChoice, 1, 0);
                var retentionHint = new Label { Text = "收藏项不会被过期清理；选择“永久”时，未收藏记录也不会自动删除。", ForeColor = Color.FromArgb(92, 105, 125), Dock = DockStyle.Fill, TextAlign = ContentAlignment.MiddleLeft, AutoEllipsis = false };
                retentionPanel.SetColumnSpan(retentionHint, 2);
                retentionPanel.Controls.Add(retentionHint, 0, 1);
                layout.Controls.Add(retentionGroup, 0, 1);

                var storageGroup = new GroupBox { Text = "文件与容量", Dock = DockStyle.Fill };
                var storagePanel = new TableLayoutPanel { Dock = DockStyle.Fill, Padding = new Padding(14, 12, 14, 8), ColumnCount = 2, RowCount = 2 };
                storagePanel.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 150));
                storagePanel.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
                storagePanel.RowStyles.Add(new RowStyle(SizeType.Absolute, 32));
                storagePanel.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
                storageGroup.Controls.Add(storagePanel);
                storagePanel.Controls.Add(new Label { Text = "单条保存上限（MB）", Dock = DockStyle.Fill, TextAlign = ContentAlignment.MiddleLeft }, 0, 0);
                var maxMb = new NumericUpDown();
                maxMb.Minimum = 1;
                maxMb.Maximum = 10240;
                maxMb.Value = Math.Max(1, store.Index.MaxItemMb);
                maxMb.Dock = DockStyle.Left;
                maxMb.Width = 110;
                maxMb.Margin = new Padding(0, 3, 0, 0);
                storagePanel.Controls.Add(maxMb, 1, 0);

                var saveMulti = new CheckBox();
                saveMulti.Text = "复制多个文件/文件夹时保存副本（默认关闭）";
                saveMulti.Checked = store.Index.SaveMultipleFiles;
                saveMulti.Dock = DockStyle.Fill;
                storagePanel.SetColumnSpan(saveMulti, 2);
                storagePanel.Controls.Add(saveMulti, 0, 1);
                layout.Controls.Add(storageGroup, 0, 2);

                var appGroup = new GroupBox { Text = "运行与提示", Dock = DockStyle.Fill };
                var appPanel = new TableLayoutPanel { Dock = DockStyle.Fill, Padding = new Padding(14, 10, 14, 10), ColumnCount = 2, RowCount = 5 };
                appPanel.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 50));
                appPanel.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 50));
                appPanel.RowStyles.Add(new RowStyle(SizeType.Absolute, 32));
                appPanel.RowStyles.Add(new RowStyle(SizeType.Absolute, 32));
                appPanel.RowStyles.Add(new RowStyle(SizeType.Absolute, 34));
                appPanel.RowStyles.Add(new RowStyle(SizeType.Absolute, 40));
                appPanel.RowStyles.Add(new RowStyle(SizeType.Absolute, 38));
                appGroup.Controls.Add(appPanel);
                var pause = new CheckBox { Text = "暂停记录剪贴板", AutoSize = true, Checked = store.Index.PauseCapture, Margin = new Padding(4, 7, 16, 4) };
                var startup = new CheckBox { Text = "开机后自动开启剪贴板记录（重要）", AutoSize = true, Checked = IsStartupEnabled(appScriptPath), Margin = new Padding(4, 7, 16, 4) };
                var notify = new CheckBox { Text = "记录新内容时系统通知", AutoSize = true, Checked = store.Index.NotifyOnCapture, Margin = new Padding(4, 7, 16, 4) };
                var autoUpdate = new CheckBox { Text = "自动更新软件版本", AutoSize = true, Checked = store.Index.AutoUpdate, Margin = new Padding(4, 7, 16, 4) };
                appPanel.Controls.Add(pause, 0, 0);
                appPanel.Controls.Add(startup, 1, 0);
                appPanel.Controls.Add(notify, 0, 1);
                appPanel.Controls.Add(autoUpdate, 1, 1);
                var fontLabel = new Label { Text = "界面字号", Dock = DockStyle.Fill, TextAlign = ContentAlignment.MiddleLeft, Padding = new Padding(4, 0, 0, 0) };
                var fontChoice = new ComboBox { DropDownStyle = ComboBoxStyle.DropDownList, Dock = DockStyle.Left, Width = 190, Margin = new Padding(4, 3, 0, 0) };
                fontChoice.Items.AddRange(new object[] { "小（8 磅）", "标准（9 磅，默认）", "大（10 磅）", "特大（11 磅）" });
                fontChoice.SelectedIndex = Math.Max(0, Math.Min(3, store.Index.UiFontSize - 1));
                appPanel.Controls.Add(fontLabel, 0, 2);
                appPanel.Controls.Add(fontChoice, 1, 2);

                var hotkeyRow = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 4, RowCount = 1, Margin = new Padding(0) };
                hotkeyRow.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 112));
                hotkeyRow.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 130));
                hotkeyRow.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
                hotkeyRow.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 116));
                var hotkeyLabel = new Label { Text = "快捷启动分配", Dock = DockStyle.Fill, TextAlign = ContentAlignment.MiddleLeft, Padding = new Padding(4, 0, 0, 0) };
                var hotkeyInput = new TextBox { Text = hotkeyRegistered ? activeHotkeyText : "未启用", ReadOnly = true, ShortcutsEnabled = false, Dock = DockStyle.Fill, TextAlign = HorizontalAlignment.Center, BackColor = Color.White, ForeColor = hotkeyRegistered ? Color.FromArgb(47, 83, 142) : Color.FromArgb(181, 72, 54), Margin = new Padding(0, 7, 6, 6) };
                var hotkeyHint = new Label { Text = "（软件自动选择首个可用组合）", Dock = DockStyle.Fill, TextAlign = ContentAlignment.MiddleLeft, AutoEllipsis = true, ForeColor = Color.FromArgb(92, 105, 125) };
                new ToolTip().SetToolTip(hotkeyInput, "点击输入框，然后按下包含 Ctrl 或 Alt 的快捷键组合");
                hotkeyInput.Enter += delegate { hotkeyInput.SelectAll(); };
                hotkeyInput.KeyDown += delegate(object sender, KeyEventArgs e)
                {
                    e.Handled = true;
                    e.SuppressKeyPress = true;
                    if (e.KeyCode == Keys.Escape)
                    {
                        hotkeyInput.Text = hotkeyRegistered ? activeHotkeyText : "未启用";
                        return;
                    }
                    if (!IsHotkeyKey(e.KeyCode)) return;
                    int modifiers = HotkeyModifiersFromKeys(e.Modifiers);
                    if ((modifiers & (Native.MOD_CONTROL | Native.MOD_ALT)) == 0)
                    {
                        hotkeyInput.Text = hotkeyRegistered ? activeHotkeyText : "未启用";
                        MessageBox.Show(form, "快捷键必须包含 Ctrl 或 Alt；可同时使用 Shift。", "快捷键无效", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                        return;
                    }
                    string error;
                    if (TryApplyCustomHotkey(modifiers, (int)e.KeyCode, out error))
                    {
                        hotkeyInput.Text = activeHotkeyText;
                        hotkeyInput.ForeColor = Color.FromArgb(45, 125, 82);
                    }
                    else
                    {
                        hotkeyInput.Text = hotkeyRegistered ? activeHotkeyText : "未启用";
                        hotkeyInput.ForeColor = hotkeyRegistered ? Color.FromArgb(47, 83, 142) : Color.FromArgb(181, 72, 54);
                        MessageBox.Show(form, error, "快捷键冲突", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                    }
                    hotkeyInput.SelectAll();
                };
                var retryHotkey = new Button { Text = "重新分配", Dock = DockStyle.Fill, FlatStyle = FlatStyle.Flat, BackColor = Color.FromArgb(232, 238, 248), ForeColor = Color.FromArgb(47, 83, 142), FlatAppearance = { BorderSize = 0 }, Margin = new Padding(4, 2, 0, 2) };
                retryHotkey.Click += delegate
                {
                    bool allocated = TryRegisterAutomaticHotkey(true);
                    hotkeyInput.Text = allocated ? activeHotkeyText : "未启用";
                    hotkeyInput.ForeColor = allocated ? Color.FromArgb(45, 125, 82) : Color.FromArgb(181, 72, 54);
                    if (!allocated) MessageBox.Show(form, HotkeyStatusText(), "快捷键分配失败", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                };
                hotkeyRow.Controls.Add(hotkeyLabel, 0, 0);
                hotkeyRow.Controls.Add(hotkeyInput, 1, 0);
                hotkeyRow.Controls.Add(hotkeyHint, 2, 0);
                hotkeyRow.Controls.Add(retryHotkey, 3, 0);
                appPanel.SetColumnSpan(hotkeyRow, 2);
                appPanel.Controls.Add(hotkeyRow, 0, 3);
                var clearUnfavorite = new Button { Text = "清空未收藏记录…", Dock = DockStyle.Left, Width = 158, FlatStyle = FlatStyle.Flat, BackColor = Color.FromArgb(254, 239, 239), ForeColor = Color.FromArgb(178, 62, 62), FlatAppearance = { BorderSize = 0 }, Margin = new Padding(3, 2, 0, 2) };
                clearUnfavorite.Click += delegate { ClearUnfavorite(); };
                appPanel.SetColumnSpan(clearUnfavorite, 2);
                appPanel.Controls.Add(clearUnfavorite, 0, 4);
                layout.Controls.Add(appGroup, 0, 3);

                var updateGroup = new GroupBox { Text = "软件更新", Dock = DockStyle.Fill };
                var updatePanel = new TableLayoutPanel { Dock = DockStyle.Fill, Padding = new Padding(14, 10, 14, 9), ColumnCount = 3, RowCount = 3 };
                updatePanel.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
                updatePanel.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 120));
                updatePanel.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 96));
                updatePanel.RowStyles.Add(new RowStyle(SizeType.Absolute, 28));
                updatePanel.RowStyles.Add(new RowStyle(SizeType.Absolute, 30));
                updatePanel.RowStyles.Add(new RowStyle(SizeType.Absolute, 26));
                var updateStatus = new Label { Text = UpdateStatusText(), Dock = DockStyle.Fill, TextAlign = ContentAlignment.MiddleLeft, ForeColor = Color.FromArgb(48, 61, 80) };
                updatePanel.Controls.Add(updateStatus, 0, 0);
                updatePanel.SetColumnSpan(updateStatus, 3);
                var updateFeed = new TextBox { Text = store.Index.UpdateFeedUrl ?? "", Dock = DockStyle.Fill, BorderStyle = BorderStyle.FixedSingle, BackColor = Color.White, ForeColor = Color.FromArgb(53, 65, 82), Font = new Font("Segoe UI", 8.5f + UiFontDelta) };
                new ToolTip().SetToolTip(updateFeed, "更新发布地址（HTTPS 的 releases.json 链接）");
                updatePanel.Controls.Add(updateFeed, 0, 1);
                var checkUpdate = new Button { Text = "检查更新", Dock = DockStyle.Fill, FlatStyle = FlatStyle.Flat, BackColor = Color.FromArgb(232, 238, 248), ForeColor = Color.FromArgb(47, 83, 142), FlatAppearance = { BorderSize = 0 }, Margin = new Padding(8, 0, 0, 0) };
                var installUpdate = new Button { Text = "更新本软件", Dock = DockStyle.Fill, Visible = availableUpdate != null, FlatStyle = FlatStyle.Flat, BackColor = Color.FromArgb(48, 104, 199), ForeColor = Color.White, FlatAppearance = { BorderSize = 0 }, Margin = new Padding(8, 2, 0, 0) };
                var uninstallButton = new Button { Text = "卸载", Dock = DockStyle.Fill, FlatStyle = FlatStyle.Flat, BackColor = Color.FromArgb(254, 239, 239), ForeColor = Color.FromArgb(178, 62, 62), FlatAppearance = { BorderSize = 0 }, Margin = new Padding(8, 0, 0, 0) };
                checkUpdate.Click += delegate { store.Index.UpdateFeedUrl = (updateFeed.Text ?? "").Trim(); store.Save(); lastUpdateStatus = ""; updateStatus.Text = "正在检查更新…"; StartUpdateCheck(true, delegate { if (!form.IsDisposed) { updateStatus.Text = UpdateStatusText(); installUpdate.Visible = availableUpdate != null; } }); };
                installUpdate.Click += delegate { InstallAvailableUpdate(form, updateStatus, installUpdate, checkUpdate); };
                uninstallButton.Click += delegate
                {
                    try { Process.Start(new ProcessStartInfo(Application.ExecutablePath, "--uninstall") { UseShellExecute = true, WorkingDirectory = Path.GetDirectoryName(Application.ExecutablePath) }); }
                    catch (Exception ex) { MessageBox.Show(form, "无法启动卸载程序：" + ex.Message, "卸载", MessageBoxButtons.OK, MessageBoxIcon.Error); }
                };
                updatePanel.Controls.Add(checkUpdate, 1, 1);
                updatePanel.Controls.Add(uninstallButton, 2, 1);
                updatePanel.Controls.Add(installUpdate, 2, 2);
                var updateHint = new Label { Text = "当前安装版本：" + UpdateService.CurrentVersionText + " · 更新包经 SHA-256 校验，完成后由安装向导启动。", Dock = DockStyle.Fill, ForeColor = Color.FromArgb(92, 105, 125), TextAlign = ContentAlignment.MiddleLeft, AutoEllipsis = true, Padding = new Padding(0) };
                updatePanel.SetColumnSpan(updateHint, 2);
                updatePanel.Controls.Add(updateHint, 0, 2);
                updateGroup.Controls.Add(updatePanel);
                layout.Controls.Add(updateGroup, 0, 4);

                var buttons = new FlowLayoutPanel();
                buttons.Dock = DockStyle.Fill;
                buttons.FlowDirection = FlowDirection.RightToLeft;
                buttons.Padding = new Padding(0, 6, 0, 0);
                var ok = new Button { Text = "确定", DialogResult = DialogResult.OK, Width = 90, Height = 30, FlatStyle = FlatStyle.Flat, BackColor = Color.FromArgb(48, 104, 199), ForeColor = Color.White, FlatAppearance = { BorderSize = 0 } };
                var cancel = new Button { Text = "取消", DialogResult = DialogResult.Cancel, Width = 90, Height = 30, FlatStyle = FlatStyle.Flat, BackColor = Color.FromArgb(232, 238, 248), ForeColor = Color.FromArgb(47, 83, 142), FlatAppearance = { BorderSize = 0 } };
                buttons.Controls.Add(ok);
                buttons.Controls.Add(cancel);
                layout.Controls.Add(buttons, 0, 5);
                form.AcceptButton = ok;
                form.CancelButton = cancel;

                if (form.ShowDialog(this) == DialogResult.OK)
                {
                    if (!capText.Checked && !capImage.Checked && !capFiles.Checked)
                    {
                        MessageBox.Show(this, "至少选择一种记录类型。", "设置未保存", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                        return;
                    }
                    store.Index.CaptureText = capText.Checked;
                    store.Index.CaptureImages = capImage.Checked;
                    store.Index.CaptureFiles = capFiles.Checked;
                    store.Index.RetentionDays = RetentionDaysFromChoice(retentionChoice);
                    store.Index.MaxItemMb = (int)maxMb.Value;
                    store.Index.SaveMultipleFiles = saveMulti.Checked;
                    store.Index.PauseCapture = pause.Checked;
                    store.Index.NotifyOnCapture = notify.Checked;
                    store.Index.AutoUpdate = autoUpdate.Checked;
                    store.Index.UpdateFeedUrl = (updateFeed.Text ?? "").Trim();
                    store.Index.UiFontSize = fontChoice.SelectedIndex + 1;
                    SetStartup(appScriptPath, startup.Checked);
                    store.Index.StartupConfigured = true;
                    store.Save();
                    ApplyUiFontSize();
                    store.CleanupExpired();
                    RefreshList();
                }
            }
        }

        string UpdateStatusText()
        {
            if (checkingForUpdate) return "正在检查更新…";
            if (availableUpdate != null) return "发现新版本 " + UpdateService.DisplayVersion(availableUpdate.Version) + "，可以下载安装。";
            if (!string.IsNullOrWhiteSpace(lastUpdateStatus)) return lastUpdateStatus;
            if (string.IsNullOrWhiteSpace(store.Index.UpdateFeedUrl)) return "尚未配置更新发布地址。";
            return "尚未检查更新；点击网址框右侧的“检查更新”。";
        }

        void StartUpdateCheck(bool userInitiated, Action completed)
        {
            lock (updateLock)
            {
                if (checkingForUpdate)
                {
                    if (userInitiated && completed != null) completed();
                    return;
                }
                checkingForUpdate = true;
            }

            string feedUrl = store.Index.UpdateFeedUrl ?? "";
            System.Threading.ThreadPool.QueueUserWorkItem(delegate
            {
                UpdateInfo result;
                string message;
                bool requestSucceeded = UpdateService.TryCheck(feedUrl, out result, out message);
                if (!IsDisposed && IsHandleCreated)
                {
                    BeginInvoke(new Action(delegate
                    {
                        checkingForUpdate = false;
                        if (!string.IsNullOrWhiteSpace(message)) lastUpdateStatus = message;
                        if (result != null)
                        {
                            availableUpdate = result;
                            if (updateBadge != null) updateBadge.Visible = true;
                            RefreshTrayMenu();
                            string version = UpdateService.DisplayVersion(result.Version);
                            if (store.Index.AutoUpdate && store.Index.LastNotifiedUpdateVersion != version)
                            {
                                store.Index.LastNotifiedUpdateVersion = version;
                                store.Save();
                                if (tray != null) tray.ShowBalloonTip(5000, "发现软件更新", "最新版本 " + version + " 已可用。请在“设置”中点击“更新本软件”。", ToolTipIcon.Info);
                            }
                        }
                        else if (requestSucceeded)
                        {
                            availableUpdate = null;
                            if (updateBadge != null) updateBadge.Visible = false;
                            RefreshTrayMenu();
                        }
                        if (userInitiated && result == null && requestSucceeded)
                        {
                            ShowToast(message);
                        }
                        if (userInitiated && !requestSucceeded && !string.IsNullOrEmpty(message))
                        {
                            ShowToast(message);
                        }
                        if (completed != null) completed();
                    }));
                }
            });
        }

        void InstallAvailableUpdate(Form settingsForm, Label updateStatus, Button installButton, Button checkButton)
        {
            UpdateInfo update = availableUpdate;
            if (update == null)
            {
                updateStatus.Text = "请先检查更新。";
                return;
            }
            installButton.Enabled = false;
            checkButton.Enabled = false;
            updateStatus.Text = "正在下载并校验新版本…";
            System.Threading.ThreadPool.QueueUserWorkItem(delegate
            {
                try
                {
                    string package = UpdateService.DownloadPackage(update);
                    string helper = Path.Combine(Path.GetDirectoryName(Application.ExecutablePath), "UpdateLauncher.exe");
                    if (!File.Exists(helper)) throw new InvalidOperationException("更新组件缺失，请重新下载安装包后再试。");
                    string args = "--wait-pid " + Process.GetCurrentProcess().Id + " --package \"" + package.Replace("\"", "\\\"") + "\"";
                    Process.Start(new ProcessStartInfo(helper, args) { UseShellExecute = false, CreateNoWindow = true, WorkingDirectory = Path.GetDirectoryName(helper) });
                    if (!IsDisposed && IsHandleCreated)
                    {
                        BeginInvoke(new Action(delegate
                        {
                            if (settingsForm != null && !settingsForm.IsDisposed) settingsForm.Close();
                            isExiting = true;
                            Close();
                        }));
                    }
                }
                catch (Exception ex)
                {
                    if (!IsDisposed && IsHandleCreated)
                    {
                        BeginInvoke(new Action(delegate
                        {
                            installButton.Enabled = true;
                            checkButton.Enabled = true;
                            updateStatus.Text = "更新未完成：" + ex.Message;
                        }));
                    }
                }
            });
        }

        void SelectRetentionChoice(ComboBox combo)
        {
            int d = store.Index.RetentionDays;
            if (d == 1) combo.SelectedIndex = 0;
            else if (d == 2) combo.SelectedIndex = 1;
            else if (d == 7) combo.SelectedIndex = 2;
            else if (d == 14) combo.SelectedIndex = 3;
            else if (d == 90) combo.SelectedIndex = 5;
            else if (d == 365) combo.SelectedIndex = 6;
            else if (d == 0) combo.SelectedIndex = 7;
            else combo.SelectedIndex = 4;
        }

        int RetentionDaysFromChoice(ComboBox combo)
        {
            switch (combo.SelectedIndex)
            {
                case 0: return 1;
                case 1: return 2;
                case 2: return 7;
                case 3: return 14;
                case 4: return 30;
                case 5: return 90;
                case 6: return 365;
                case 7: return 0;
                default: return 30;
            }
        }

        void BuildTray()
        {
            tray = new NotifyIcon();
            tray.Icon = appIcon;
            tray.Text = "Unlimited Clipboard";
            tray.Visible = true;
            trayMenu = new ContextMenuStrip();
            tray.ContextMenuStrip = trayMenu;
            RefreshTrayMenu();
            tray.DoubleClick += delegate { ShowAndActivate(); };
        }

        void RefreshTrayMenu()
        {
            UpdateMainHotkeyHint();
            if (trayMenu == null) return;
            trayMenu.Items.Clear();
            trayMenu.Items.Add(hotkeyRegistered ? "打开（" + activeHotkeyText + "）" : "打开（快捷键未启用）", null, delegate { ShowAndActivate(); });
            if (!hotkeyRegistered)
            {
                var retryItem = trayMenu.Items.Add("重试分配 Ctrl+数字快捷键", null, delegate
                {
                    bool ok = TryRegisterHotkey();
                    if (tray != null) tray.ShowBalloonTip(3500, ok ? "快捷键已启用" : "快捷键仍未启用", HotkeyStatusText(), ok ? ToolTipIcon.Info : ToolTipIcon.Warning);
                });
                retryItem.ForeColor = Color.FromArgb(181, 72, 54);
            }
            if (availableUpdate != null)
            {
                string version = UpdateService.DisplayVersion(availableUpdate.Version);
                var updateItem = trayMenu.Items.Add("新版本 " + version + " · 更新并重启", null, delegate { InstallAvailableUpdateFromTray(); });
                updateItem.ForeColor = Color.FromArgb(194, 52, 52);
                updateItem.Font = new Font("Microsoft YaHei UI", 9f + UiFontDelta, FontStyle.Bold);
            }
            trayMenu.Items.Add("暂停/继续记录", null, delegate { store.Index.PauseCapture = !store.Index.PauseCapture; store.Save(); RefreshList(); });
            trayMenu.Items.Add("打开数据目录", null, delegate { Process.Start(store.Root); });
            trayMenu.Items.Add("-");
            trayMenu.Items.Add("退出", null, delegate { isExiting = true; Close(); });
        }

        void InstallAvailableUpdateFromTray()
        {
            UpdateInfo update = availableUpdate;
            if (update == null) return;
            if (tray != null) tray.ShowBalloonTip(2500, "正在更新 Unlimited Clipboard", "正在下载并校验版本 " + UpdateService.DisplayVersion(update.Version) + "。", ToolTipIcon.Info);
            System.Threading.ThreadPool.QueueUserWorkItem(delegate
            {
                try
                {
                    string package = UpdateService.DownloadPackage(update);
                    string helper = Path.Combine(Path.GetDirectoryName(Application.ExecutablePath), "UpdateLauncher.exe");
                    if (!File.Exists(helper)) throw new InvalidOperationException("更新组件缺失，请重新下载安装包后再试。");
                    string args = "--wait-pid " + Process.GetCurrentProcess().Id + " --package \"" + package.Replace("\"", "\\\"") + "\"";
                    Process.Start(new ProcessStartInfo(helper, args) { UseShellExecute = false, CreateNoWindow = true, WorkingDirectory = Path.GetDirectoryName(helper) });
                    if (!IsDisposed && IsHandleCreated) BeginInvoke(new Action(delegate { isExiting = true; Close(); }));
                }
                catch
                {
                    if (!IsDisposed && IsHandleCreated) BeginInvoke(new Action(delegate { if (tray != null) tray.ShowBalloonTip(3500, "更新未完成", "下载或校验更新文件失败，请稍后重试。", ToolTipIcon.Warning); }));
                }
            });
        }

        void ShowAndActivate()
        {
            Show();
            if (WindowState == FormWindowState.Minimized) WindowState = FormWindowState.Normal;
            Activate();
            search.Focus();
        }

        void InitializeListColumns()
        {
            if (list == null || list.IsDisposed || list.Columns.Count < 6 || list.ClientSize.Width <= 0) return;
            suppressListColumnSync = true;
            try
            {
                int[] saved = GetSavedListColumnWidths();
                bool valid = true;
                for (int i = 0; i < saved.Length; i++)
                {
                    if (saved[i] < MinimumListColumnWidths[i]) { valid = false; break; }
                }
                if (valid)
                {
                    for (int i = 0; i < 6; i++) list.Columns[i].Width = saved[i];
                    FitSavedColumnsToCurrentList();
                }
                else
                {
                    ApplyDefaultListColumns();
                }
                CaptureCurrentListLayout();
                listLayoutReady = true;
                SaveListLayout(true);
            }
            finally { suppressListColumnSync = false; }
            UpdateMainHotkeyHint();
        }

        void ApplyDefaultListColumns()
        {
            int[] defaults = new int[] { 36, 60, 0, 128, 70, 58 };
            int fixedWidth = defaults[0] + defaults[1] + defaults[3] + defaults[4] + defaults[5];
            defaults[2] = Math.Max(MinimumListColumnWidths[2], list.ClientSize.Width - fixedWidth);
            for (int i = 0; i < 6; i++) list.Columns[i].Width = defaults[i];
        }

        void FitSavedColumnsToCurrentList()
        {
            int total = 0;
            for (int i = 0; i < 6; i++) total += list.Columns[i].Width;
            int difference = list.ClientSize.Width - total;
            if (difference >= 0)
            {
                list.Columns[2].Width += difference;
                return;
            }

            int remaining = -difference;
            int[] shrinkOrder = new int[] { 2, 3, 1, 4, 5, 0 };
            foreach (int index in shrinkOrder)
            {
                int available = Math.Max(0, list.Columns[index].Width - MinimumListColumnWidths[index]);
                int reduction = Math.Min(available, remaining);
                list.Columns[index].Width -= reduction;
                remaining -= reduction;
                if (remaining <= 0) break;
            }
        }

        void RestoreDefaultListColumns()
        {
            if (list == null || list.Columns.Count < 6) return;
            suppressListColumnSync = true;
            try
            {
                Rectangle working = Screen.FromControl(this).WorkingArea;
                Width = Math.Max(MinimumSize.Width, Math.Min(980, working.Width));
                PerformLayout();
                ApplyDefaultListColumns();
                CaptureCurrentListLayout();
                listLayoutReady = true;
                SaveListLayout(true);
            }
            finally { suppressListColumnSync = false; }
            ShowToast("已恢复默认列宽");
        }

        void ListColumnWidthChanging(object sender, ColumnWidthChangingEventArgs e)
        {
            if (!listLayoutReady || suppressListColumnSync || e.ColumnIndex < 0 || e.ColumnIndex >= 6) return;
            int current = trackedListColumnWidths[e.ColumnIndex];
            int minimumFromWindow = current - Math.Max(0, Width - MinimumSize.Width);
            int minimum = Math.Max(MinimumListColumnWidths[e.ColumnIndex], minimumFromWindow);
            int maximum = current + Math.Max(0, Screen.FromControl(this).WorkingArea.Width - Width);
            e.NewWidth = Math.Max(minimum, Math.Min(maximum, e.NewWidth));
        }

        void ListColumnWidthChanged(object sender, ColumnWidthChangedEventArgs e)
        {
            if (!listLayoutReady || suppressListColumnSync || e.ColumnIndex < 0 || e.ColumnIndex >= 6) return;
            int oldWidth = trackedListColumnWidths[e.ColumnIndex];
            int delta = list.Columns[e.ColumnIndex].Width - oldWidth;
            if (delta == 0) return;

            suppressListColumnSync = true;
            try
            {
                Rectangle working = Screen.FromControl(this).WorkingArea;
                int targetWidth = Math.Max(MinimumSize.Width, Math.Min(working.Width, Width + delta));
                int actualDelta = targetWidth - Width;
                if (actualDelta != delta) list.Columns[e.ColumnIndex].Width = oldWidth + actualDelta;
                Width = targetWidth;
                PerformLayout();
                CaptureCurrentListLayout();
                SaveListLayout(true);
            }
            finally { suppressListColumnSync = false; }
        }

        void ListResized(object sender, EventArgs e)
        {
            if (list == null || list.ClientSize.Width <= 0) return;
            if (!listLayoutReady || suppressListColumnSync)
            {
                lastListClientWidth = list.ClientSize.Width;
                return;
            }
            int delta = list.ClientSize.Width - lastListClientWidth;
            if (delta == 0) return;
            suppressListColumnSync = true;
            try
            {
                list.Columns[2].Width = Math.Max(MinimumListColumnWidths[2], list.Columns[2].Width + delta);
                CaptureCurrentListLayout();
                SaveListLayout(false);
            }
            finally { suppressListColumnSync = false; }
        }

        void CaptureCurrentListLayout()
        {
            if (list == null || list.Columns.Count < 6) return;
            for (int i = 0; i < 6; i++) trackedListColumnWidths[i] = list.Columns[i].Width;
            lastListClientWidth = list.ClientSize.Width;
        }

        int[] GetSavedListColumnWidths()
        {
            return new int[] {
                store.Index.ListColumn0Width, store.Index.ListColumn1Width, store.Index.ListColumn2Width,
                store.Index.ListColumn3Width, store.Index.ListColumn4Width, store.Index.ListColumn5Width
            };
        }

        void SaveListLayout(bool writeToDisk)
        {
            if (store == null || list == null || list.Columns.Count < 6) return;
            store.Index.MainWindowWidth = WindowState == FormWindowState.Normal ? Width : store.Index.MainWindowWidth;
            store.Index.ListColumn0Width = list.Columns[0].Width;
            store.Index.ListColumn1Width = list.Columns[1].Width;
            store.Index.ListColumn2Width = list.Columns[2].Width;
            store.Index.ListColumn3Width = list.Columns[3].Width;
            store.Index.ListColumn4Width = list.Columns[4].Width;
            store.Index.ListColumn5Width = list.Columns[5].Width;
            if (writeToDisk) store.Save();
        }

        void UpdateMainHotkeyHint()
        {
            if (mainHotkeyHint == null) return;
            mainHotkeyHint.Text = "快捷键：" + (hotkeyRegistered ? activeHotkeyText : "未启用");
            mainHotkeyHint.ForeColor = hotkeyRegistered ? Color.FromArgb(71, 91, 121) : Color.FromArgb(181, 72, 54);
        }

        void DrawListHeader(object sender, DrawListViewColumnHeaderEventArgs e)
        {
            using (var background = new SolidBrush(Color.FromArgb(241, 245, 251)))
            using (var divider = new Pen(Color.FromArgb(224, 231, 242)))
            {
                e.Graphics.FillRectangle(background, e.Bounds);
                e.Graphics.DrawLine(divider, e.Bounds.Left, e.Bounds.Bottom - 1, e.Bounds.Right, e.Bounds.Bottom - 1);
            }
            using (var font = new Font("Microsoft YaHei UI", 8.5f + UiFontDelta, FontStyle.Bold))
            {
                TextRenderer.DrawText(e.Graphics, e.Header.Text, font, Rectangle.Inflate(e.Bounds, -8, 0), Color.FromArgb(94, 108, 130), TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis);
            }
        }

        void DrawListSubItem(object sender, DrawListViewSubItemEventArgs e)
        {
            bool selected = e.Item.Selected;
            bool favorite = e.Item.Tag is ClipItem && ((ClipItem)e.Item.Tag).Favorite;
            Color background = selected ? Color.FromArgb(48, 104, 199) : (favorite ? Color.FromArgb(255, 250, 230) : Color.White);
            Color foreground = selected ? Color.White : (e.ColumnIndex == 0 && favorite ? Color.FromArgb(231, 163, 30) : Color.FromArgb(48, 61, 80));
            using (var brush = new SolidBrush(background))
            using (var divider = new Pen(selected ? Color.FromArgb(48, 104, 199) : Color.FromArgb(238, 242, 248)))
            {
                e.Graphics.FillRectangle(brush, e.Bounds);
                e.Graphics.DrawLine(divider, e.Bounds.Left, e.Bounds.Bottom - 1, e.Bounds.Right, e.Bounds.Bottom - 1);
            }
            var flags = TextFormatFlags.SingleLine | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.NoPrefix;
            if (e.ColumnIndex == 0 || e.ColumnIndex == 5) flags |= TextFormatFlags.HorizontalCenter;
            else flags |= TextFormatFlags.Left;
            Font font = (e.ColumnIndex == 0 || e.ColumnIndex == 5) ? new Font("Segoe UI Symbol", 10f + UiFontDelta, FontStyle.Regular) : new Font("Microsoft YaHei UI", 9f + UiFontDelta, FontStyle.Regular);
            TextRenderer.DrawText(e.Graphics, e.SubItem.Text, font, Rectangle.Inflate(e.Bounds, -8, 0), foreground, flags);
            font.Dispose();
        }

        void ListKeyDown(object sender, KeyEventArgs e)
        {
            if (e.KeyCode == Keys.Enter) { RestoreSelected(); e.Handled = true; }
            if (e.KeyCode == Keys.Delete) { DeleteSelected(); e.Handled = true; }
            if (e.Control && e.KeyCode == Keys.F) { search.Focus(); e.Handled = true; }
        }

        void ListMouseClick(object sender, MouseEventArgs e)
        {
            var hit = list.HitTest(e.X, e.Y);
            var itemView = hit == null ? null : hit.Item;
            if (itemView == null) return;
            if (GetColumnAtX(e.X) == 5)
            {
                itemView.Selected = true;
                RestoreItem((ClipItem)itemView.Tag);
            }
        }

        int GetColumnAtX(int x)
        {
            int left = 0;
            for (int i = 0; i < list.Columns.Count; i++)
            {
                left += list.Columns[i].Width;
                if (x < left) return i;
            }
            return -1;
        }

        void RefreshList()
        {
            string q = (search.Text ?? "").Trim().ToLowerInvariant();
            string tf = typeFilter.SelectedItem == null ? "全部" : typeFilter.SelectedItem.ToString();
            list.BeginUpdate();
            list.Items.Clear();
            foreach (var item in store.Index.Items.ToList())
            {
                if (!File.Exists(store.DataPath(item))) continue;
                if (tf == "文本" && item.Type != "text") continue;
                if (tf == "图片" && item.Type != "image") continue;
                if (tf == "文件" && item.Type != "files") continue;
                if (tf == "收藏" && !item.Favorite) continue;
                string hay = ((item.Preview ?? "") + " " + item.Type).ToLowerInvariant();
                if (q.Length > 0 && hay.IndexOf(q) < 0) continue;

                var lvi = new ListViewItem(item.Favorite ? "★" : "");
                lvi.SubItems.Add(TypeLabel(item.Type));
                lvi.SubItems.Add(item.Preview ?? "");
                lvi.SubItems.Add(ToLocal(item.CreatedUtc).ToString("yyyy-MM-dd HH:mm"));
                lvi.SubItems.Add(FormatBytes(item.SizeBytes));
                lvi.SubItems.Add("⧉");
                lvi.Tag = item;
                if (item.Favorite) lvi.BackColor = Color.FromArgb(255, 250, 225);
                list.Items.Add(lvi);
            }
            list.EndUpdate();
            status.Text = "共 " + store.Index.Items.Count + " 条，当前显示 " + list.Items.Count + " 条，占用 " + FormatBytes(store.TotalBytes()) + "。点“复制”列、双击或 Enter 可恢复到剪贴板；收藏项不会过期。";
        }

        void UpdatePreview()
        {
            if (previewImage.Image != null)
            {
                previewImage.Image.Dispose();
                previewImage.Image = null;
            }
            previewImage.Visible = false;
            previewText.Visible = true;
            if (list.SelectedItems.Count == 0)
            {
                previewText.Text = "";
                return;
            }
            var item = (ClipItem)list.SelectedItems[0].Tag;
            try
            {
                if (item.Type == "text")
                {
                    previewText.Text = store.ReadText(item);
                }
                else if (item.Type == "files")
                {
                    previewText.Text = store.ReadText(item);
                }
                else if (item.Type == "image")
                {
                    var bmp = DibToBitmap(store.ReadBytes(item));
                    if (bmp != null)
                    {
                        previewImage.Image = bmp;
                        previewText.Visible = false;
                        previewImage.Visible = true;
                    }
                    else
                    {
                        previewText.Text = "[图片预览不可用，但仍可恢复到剪贴板]";
                    }
                }
            }
            catch (Exception ex)
            {
                previewText.Text = "预览失败：" + ex.Message;
            }
        }

        void CaptureCurrentClipboard()
        {
            try
            {
                ClipItem item = ReadClipboardIntoStore();
                if (item != null)
                {
                    RefreshList();
                    if (store.Index.NotifyOnCapture && tray != null)
                    {
                        tray.ShowBalloonTip(600, "已保存剪贴板", TypeLabel(item.Type) + "：" + item.Preview, ToolTipIcon.None);
                    }
                }
            }
            catch { }
        }

        ClipItem ReadClipboardIntoStore()
        {
            if (!Native.OpenClipboard(Handle)) return null;
            try
            {
                if (store.Index.CaptureFiles && Native.IsClipboardFormatAvailable(Native.CF_HDROP))
                {
                    var paths = ReadHDrop();
                    if (paths.Count > 0)
                    {
                        if (paths.Count > 1)
                        {
                            if (!store.Index.SaveMultipleFiles) return null;
                            return store.AddArchivedFiles(paths);
                        }
                        string text = string.Join(Environment.NewLine, paths.ToArray());
                        return store.AddOrPromote("files", Encoding.UTF8.GetBytes(text), "文件：" + text);
                    }
                }
                if (store.Index.CaptureImages && Native.IsClipboardFormatAvailable(Native.CF_DIB))
                {
                    byte[] dib = ReadGlobalBytes(Native.GetClipboardData(Native.CF_DIB));
                    if (dib.Length > 0)
                    {
                        return store.AddOrPromote("image", dib, ImagePreview(dib));
                    }
                }
                if (store.Index.CaptureText && Native.IsClipboardFormatAvailable(Native.CF_UNICODETEXT))
                {
                    string text = ReadUnicodeText();
                    if (!string.IsNullOrEmpty(text))
                    {
                        return store.AddOrPromote("text", Encoding.UTF8.GetBytes(text), text);
                    }
                }
            }
            finally
            {
                Native.CloseClipboard();
            }
            return null;
        }

        string ReadUnicodeText()
        {
            IntPtr h = Native.GetClipboardData(Native.CF_UNICODETEXT);
            if (h == IntPtr.Zero) return "";
            IntPtr p = Native.GlobalLock(h);
            if (p == IntPtr.Zero) return "";
            try { return Marshal.PtrToStringUni(p) ?? ""; }
            finally { Native.GlobalUnlock(h); }
        }

        List<string> ReadHDrop()
        {
            var result = new List<string>();
            IntPtr h = Native.GetClipboardData(Native.CF_HDROP);
            if (h == IntPtr.Zero) return result;
            uint count = Native.DragQueryFile(h, 0xFFFFFFFF, null, 0);
            for (uint i = 0; i < count; i++)
            {
                uint len = Native.DragQueryFile(h, i, null, 0);
                var sb = new StringBuilder((int)len + 1);
                Native.DragQueryFile(h, i, sb, len + 1);
                result.Add(sb.ToString());
            }
            return result;
        }

        byte[] ReadGlobalBytes(IntPtr h)
        {
            if (h == IntPtr.Zero) return new byte[0];
            UIntPtr sizePtr = Native.GlobalSize(h);
            long size = (long)sizePtr.ToUInt64();
            if (size <= 0 || size > int.MaxValue) return new byte[0];
            IntPtr p = Native.GlobalLock(h);
            if (p == IntPtr.Zero) return new byte[0];
            try
            {
                byte[] bytes = new byte[(int)size];
                Marshal.Copy(p, bytes, 0, bytes.Length);
                return bytes;
            }
            finally { Native.GlobalUnlock(h); }
        }

        void RestoreSelected()
        {
            if (list.SelectedItems.Count == 0) return;
            RestoreItem((ClipItem)list.SelectedItems[0].Tag);
        }

        void RestoreItem(ClipItem item)
        {
            if (item == null) return;
            try
            {
                byte[] bytes = store.ReadBytes(item);
                suppressCapture = true;
                if (!Native.OpenClipboard(Handle)) throw new Exception("无法打开剪贴板");
                try
                {
                    Native.EmptyClipboard();
                    if (item.Type == "text")
                    {
                        SetUnicodeText(Encoding.UTF8.GetString(bytes));
                    }
                    else if (item.Type == "image")
                    {
                        SetGlobalData(Native.CF_DIB, bytes);
                    }
                    else if (item.Type == "files")
                    {
                        SetFileDrop(Encoding.UTF8.GetString(bytes).Split(new string[] { "\r\n", "\n" }, StringSplitOptions.RemoveEmptyEntries));
                    }
                }
                finally { Native.CloseClipboard(); }
                item.LastUsedUtc = DateTime.UtcNow;
                store.Save();
                status.Text = "已恢复到剪贴板：" + TypeLabel(item.Type) + "。现在可在目标位置粘贴。";
                ShowToast("复制成功");
                BeginInvoke(new Action(delegate { suppressCapture = false; }));
            }
            catch (Exception ex)
            {
                suppressCapture = false;
                MessageBox.Show("恢复失败：" + ex.Message, "无限剪贴板", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }

        void SetUnicodeText(string text)
        {
            byte[] bytes = Encoding.Unicode.GetBytes((text ?? "") + "\0");
            SetGlobalData(Native.CF_UNICODETEXT, bytes);
        }

        void SetGlobalData(uint format, byte[] bytes)
        {
            IntPtr h = Native.GlobalAlloc(Native.GMEM_MOVEABLE | Native.GMEM_ZEROINIT, (UIntPtr)bytes.Length);
            if (h == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error());
            IntPtr p = Native.GlobalLock(h);
            if (p == IntPtr.Zero)
            {
                Native.GlobalFree(h);
                throw new Win32Exception(Marshal.GetLastWin32Error());
            }
            Marshal.Copy(bytes, 0, p, bytes.Length);
            Native.GlobalUnlock(h);
            if (Native.SetClipboardData(format, h) == IntPtr.Zero)
            {
                Native.GlobalFree(h);
                throw new Win32Exception(Marshal.GetLastWin32Error());
            }
        }

        void SetFileDrop(string[] paths)
        {
            string joined = string.Join("\0", paths) + "\0\0";
            byte[] names = Encoding.Unicode.GetBytes(joined);
            byte[] data = new byte[20 + names.Length];
            BitConverter.GetBytes(20).CopyTo(data, 0);
            BitConverter.GetBytes(1).CopyTo(data, 16);
            Buffer.BlockCopy(names, 0, data, 20, names.Length);
            SetGlobalData(Native.CF_HDROP, data);
        }

        void ToggleFavorite()
        {
            foreach (ListViewItem lvi in list.SelectedItems)
            {
                var item = (ClipItem)lvi.Tag;
                item.Favorite = !item.Favorite;
            }
            store.Save();
            RefreshList();
        }

        void DeleteSelected()
        {
            if (list.SelectedItems.Count == 0) return;
            if (MessageBox.Show("删除选中的 " + list.SelectedItems.Count + " 条记录？", "确认删除", MessageBoxButtons.OKCancel, MessageBoxIcon.Question) != DialogResult.OK) return;
            var items = new List<ClipItem>();
            foreach (ListViewItem lvi in list.SelectedItems) items.Add((ClipItem)lvi.Tag);
            foreach (var item in items) store.Delete(item);
            RefreshList();
        }

        void ClearUnfavorite()
        {
            if (MessageBox.Show("清空所有未收藏记录？收藏项会保留。", "确认清空", MessageBoxButtons.OKCancel, MessageBoxIcon.Warning) != DialogResult.OK) return;
            var items = store.Index.Items.Where(x => !x.Favorite).ToList();
            foreach (var item in items) store.Delete(item);
            RefreshList();
        }

        static string TypeLabel(string type)
        {
            if (type == "text") return "文本";
            if (type == "image") return "图片";
            if (type == "files") return "文件";
            return type;
        }

        static string FormatBytes(long bytes)
        {
            string[] units = new string[] { "B", "KB", "MB", "GB" };
            double v = bytes;
            int i = 0;
            while (v >= 1024 && i < units.Length - 1) { v /= 1024; i++; }
            return v.ToString(i == 0 ? "0" : "0.0") + units[i];
        }

        static DateTime ToLocal(DateTime utc)
        {
            if (utc.Kind == DateTimeKind.Unspecified) utc = DateTime.SpecifyKind(utc, DateTimeKind.Utc);
            return utc.ToLocalTime();
        }

        static string ImagePreview(byte[] dib)
        {
            try
            {
                if (dib.Length >= 12)
                {
                    int headerSize = BitConverter.ToInt32(dib, 0);
                    if (headerSize >= 40 && dib.Length >= 12)
                    {
                        int w = BitConverter.ToInt32(dib, 4);
                        int h = Math.Abs(BitConverter.ToInt32(dib, 8));
                        return "图片 " + w + "×" + h;
                    }
                }
            }
            catch { }
            return "图片";
        }

        static Bitmap DibToBitmap(byte[] dib)
        {
            if (dib == null || dib.Length < 40) return null;
            int offset = DibPixelOffset(dib);
            int fileSize = 14 + dib.Length;
            byte[] bmp = new byte[fileSize];
            bmp[0] = (byte)'B';
            bmp[1] = (byte)'M';
            BitConverter.GetBytes(fileSize).CopyTo(bmp, 2);
            BitConverter.GetBytes(14 + offset).CopyTo(bmp, 10);
            Buffer.BlockCopy(dib, 0, bmp, 14, dib.Length);
            using (var ms = new MemoryStream(bmp))
            {
                return new Bitmap(ms);
            }
        }

        static int DibPixelOffset(byte[] dib)
        {
            int headerSize = BitConverter.ToInt32(dib, 0);
            if (headerSize < 12 || headerSize > dib.Length) return 40;
            if (headerSize == 12) return 12;
            ushort bitCount = BitConverter.ToUInt16(dib, 14);
            uint clrUsed = 0;
            if (headerSize >= 40) clrUsed = BitConverter.ToUInt32(dib, 32);
            int colors = 0;
            if (clrUsed != 0) colors = (int)clrUsed;
            else if (bitCount <= 8) colors = 1 << bitCount;
            return headerSize + colors * 4;
        }

        bool IsStartupEnabled(string scriptPath)
        {
            try
            {
                using (var key = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Run", false))
                {
                    string value = key == null ? null : key.GetValue("InfiniteClipboard") as string;
                    string launcher = Path.Combine(Path.GetDirectoryName(scriptPath), "启动无限剪贴板.vbs");
                    return value != null && (value.IndexOf(scriptPath, StringComparison.OrdinalIgnoreCase) >= 0 || value.IndexOf(launcher, StringComparison.OrdinalIgnoreCase) >= 0);
                }
            }
            catch { return false; }
        }

        void SetStartup(string scriptPath, bool enabled)
        {
            try
            {
                using (var key = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Run", true))
                {
                    if (enabled)
                    {
                        bool isNativeExe = string.Equals(Path.GetExtension(scriptPath), ".exe", StringComparison.OrdinalIgnoreCase);
                        string cmd;
                        if (isNativeExe)
                        {
                            cmd = "\"" + scriptPath + "\" --background";
                        }
                        else
                        {
                            string launcher = Path.Combine(Path.GetDirectoryName(scriptPath), "启动无限剪贴板.vbs");
                            // Legacy PowerShell distribution: use the VBS launcher without a console window.
                            cmd = "wscript.exe \"" + launcher + "\"";
                        }
                        key.SetValue("InfiniteClipboard", cmd);
                    }
                    else
                    {
                        key.DeleteValue("InfiniteClipboard", false);
                    }
                }
            }
            catch (Exception ex)
            {
                MessageBox.Show("设置开机启动失败：" + ex.Message);
            }
        }
    }

    public static class Program
    {
        static System.Threading.Mutex singleInstanceMutex;

        [STAThread]
        public static void Main(string[] args)
        {
            string exePath = Application.ExecutablePath;
            try { Native.SetCurrentProcessExplicitAppUserModelID("cn.cetle.UnlimitedClipboard"); } catch { }
            bool uninstall = args != null && args.Any(x => string.Equals(x, "--uninstall", StringComparison.OrdinalIgnoreCase));
            if (uninstall)
            {
                Uninstall(exePath);
                return;
            }
            bool background = args != null && args.Any(x => string.Equals(x, "--background", StringComparison.OrdinalIgnoreCase));
            Run(exePath, background);
        }

        public static void Run(string scriptPath)
        {
            Run(scriptPath, false);
        }

        public static void Run(string scriptPath, bool startInBackground)
        {
            bool createdNew;
            singleInstanceMutex = new System.Threading.Mutex(true, @"Global\InfiniteClipboard.SingleInstance.v1", out createdNew);
            if (!createdNew)
            {
                int msg = Native.RegisterWindowMessage("InfiniteClipboard.ShowMainWindow.v1");
                Native.PostMessage((IntPtr)Native.HWND_BROADCAST, msg, IntPtr.Zero, IntPtr.Zero);
                return;
            }

            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            try
            {
                Application.Run(new MainForm(scriptPath, startInBackground));
            }
            finally
            {
                try { singleInstanceMutex.ReleaseMutex(); } catch { }
                if (singleInstanceMutex != null) singleInstanceMutex.Dispose();
            }
        }

        static void Uninstall(string exePath)
        {
            string appName = "无限剪贴板";
            DialogResult answer = MessageBox.Show("确定要卸载本软件吗？", "卸载" + appName, MessageBoxButtons.YesNo, MessageBoxIcon.Question);
            if (answer != DialogResult.Yes) return;

            // Ask an existing tray instance to release the executable before cleanup starts.
            try
            {
                int exitMessage = Native.RegisterWindowMessage("InfiniteClipboard.Exit.v1");
                Native.PostMessage((IntPtr)Native.HWND_BROADCAST, exitMessage, IntPtr.Zero, IntPtr.Zero);
                System.Threading.Thread.Sleep(1200);
            }
            catch { }

            try
            {
                using (var runKey = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Run", true))
                {
                    if (runKey != null) runKey.DeleteValue("InfiniteClipboard", false);
                }
                Registry.CurrentUser.DeleteSubKeyTree(@"Software\Microsoft\Windows\CurrentVersion\Uninstall\InfiniteClipboard", false);
            }
            catch { }

            string installDir = Path.GetDirectoryName(exePath);
            try
            {
                string desktopLink = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory), appName + ".lnk");
                if (File.Exists(desktopLink)) File.Delete(desktopLink);
                string startMenu = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Programs), appName);
                if (Directory.Exists(startMenu)) Directory.Delete(startMenu, true);
            }
            catch { }

            try
            {
                string cleanup = Path.Combine(Path.GetTempPath(), "InfiniteClipboard-uninstall-" + Process.GetCurrentProcess().Id + ".cmd");
                string updaterPath = Path.Combine(installDir, "UpdateLauncher.exe");
                foreach (string name in new string[] { "UpdateLauncher.exe", "InfiniteClipboard.ps1", "Launch.vbs", "Uninstall.ps1", "启动无限剪贴板.vbs" })
                {
                    try
                    {
                        string knownFile = Path.Combine(installDir, name);
                        if (File.Exists(knownFile)) File.Delete(knownFile);
                    }
                    catch { }
                }
                string body = "@echo off\r\nfor /l %%i in (1,1,8) do (\r\n  del /f /q \"" + exePath + "\" >nul 2>nul\r\n  del /f /q \"" + updaterPath + "\" >nul 2>nul\r\n  if not exist \"" + exePath + "\" goto done\r\n  timeout /t 1 /nobreak >nul\r\n)\r\n:done\r\nrmdir \"" + installDir + "\" >nul 2>nul\r\ndel \"%~f0\"\r\n";
                File.WriteAllText(cleanup, body, Encoding.ASCII);
                var psi = new ProcessStartInfo("cmd.exe", "/c \"" + cleanup + "\"");
                psi.CreateNoWindow = true;
                psi.UseShellExecute = false;
                Process.Start(psi);
            }
            catch { }

            MessageBox.Show(appName + " 已卸载。剪贴板历史数据仍保留在 AppData 中。", "卸载完成", MessageBoxButtons.OK, MessageBoxIcon.Information);
        }
    }
}
"@

Add-Type -TypeDefinition $source -Language CSharp -ReferencedAssemblies @(
    "System.Windows.Forms",
    "System.Drawing",
    "System.Xml",
    "System.Core",
    "Microsoft.VisualBasic"
)

if ($CompileOnly) {
    Write-Host "compile ok"
    return
}

[InfiniteClipboard.Program]::Run($PSCommandPath)
