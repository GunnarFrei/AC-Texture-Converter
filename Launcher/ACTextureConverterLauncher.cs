using System;
using System.Diagnostics;
using System.IO;
using System.Windows.Forms;

internal static class ACTextureConverterLauncher
{
    private static string Quote(string value)
    {
        var quoted = new System.Text.StringBuilder("\"");
        int slashes = 0;
        foreach (char c in value)
        {
            if (c == '\\') { slashes++; continue; }
            if (c == '"') quoted.Append('\\', slashes * 2 + 1);
            else quoted.Append('\\', slashes);
            quoted.Append(c);
            slashes = 0;
        }
        quoted.Append('\\', slashes * 2);
        quoted.Append('"');
        return quoted.ToString();
    }

    [STAThread]
    private static int Main(string[] args)
    {
        string script = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "ACTextureConverter.ps1");
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
        string[] prefix = { "-NoProfile", "-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden", "-File", script };
        string[] allArgs = new string[prefix.Length + args.Length];
        Array.Copy(prefix, allArgs, prefix.Length);
        Array.Copy(args, 0, allArgs, prefix.Length, args.Length);
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

