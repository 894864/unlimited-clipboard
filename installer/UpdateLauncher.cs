using System;
using System.Diagnostics;
using System.IO;
using System.Threading;

[assembly: System.Reflection.AssemblyTitle("InfiniteClipboard Update Launcher")]
[assembly: System.Reflection.AssemblyProduct("InfiniteClipboard")]
[assembly: System.Reflection.AssemblyVersion("1.0.1.0")]
[assembly: System.Reflection.AssemblyFileVersion("1.0.1.0")]

namespace InfiniteClipboardUpdate
{
    internal static class Program
    {
        [STAThread]
        static int Main(string[] args)
        {
            int pid = 0;
            string package = "";
            for (int i = 0; args != null && i < args.Length; i++)
            {
                if (string.Equals(args[i], "--wait-pid", StringComparison.OrdinalIgnoreCase) && i + 1 < args.Length) int.TryParse(args[++i], out pid);
                else if (string.Equals(args[i], "--package", StringComparison.OrdinalIgnoreCase) && i + 1 < args.Length) package = args[++i];
            }
            if (pid <= 0 || string.IsNullOrEmpty(package) || !File.Exists(package)) return 2;

            try
            {
                Process process = Process.GetProcessById(pid);
                process.WaitForExit(45000);
            }
            catch (ArgumentException) { }
            catch { return 3; }

            if (Process.GetProcessesByName("InfiniteClipboard").Length > 0) return 4;
            try
            {
                Process.Start(new ProcessStartInfo(package) { UseShellExecute = true, WorkingDirectory = Path.GetDirectoryName(package) });
                return 0;
            }
            catch { return 5; }
        }
    }
}
