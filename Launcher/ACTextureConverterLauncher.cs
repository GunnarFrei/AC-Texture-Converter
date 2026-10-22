using System;
using System.Diagnostics;
using System.IO;
using System.Windows.Forms;

internal static class ACTextureConverterLauncher
{
    private static string Quote(string value)
    {
        return "\"" + value.Replace("\\", "\\\\").Replace("\"", "\\\"") + "\"";
    }

    [STAThread]
    private static int Main(string[] args)
    {
        string root = AppDomain.CurrentDomain.BaseDirectory;
        string script = Path.Combine(root, "ACTextureConverter.ps1");
        if (!File.Exists(script))
        {
            MessageBox.Show("ACTextureConverter.ps1 is missing from the application folder.",
                "AC Texture Converter", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 2;
        }

        ProcessStartInfo start = new ProcessStartInfo
        {
            FileName = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "WindowsPowerShell\\v1.0\\powershell.exe"),
            UseShellExecute = false,
            CreateNoWindow = true,
            WindowStyle = ProcessWindowStyle.Hidden
        };
        string[] powershellArgs = new string[] { "-NoProfile", "-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden", "-File", script };
        string[] allArgs = new string[powershellArgs.Length + args.Length];
        Array.Copy(powershellArgs, allArgs, powershellArgs.Length);
        Array.Copy(args, 0, allArgs, powershellArgs.Length, args.Length);
        start.Arguments = String.Join(" ", Array.ConvertAll(allArgs, Quote));

        try
        {
            using (Process child = Process.Start(start))
            {
                child.WaitForExit();
                return child.ExitCode;
            }
        }
        catch (Exception ex)
        {
            MessageBox.Show("Could not start Windows PowerShell.\r\n\r\n" + ex.Message,
                "AC Texture Converter", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
    }
}
