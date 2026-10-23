using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;
using System.Text;
using System.Web.Script.Serialization;

namespace ACTextureConverter
{
    [ComVisible(true)]
    [Guid("91A658F4-E8EC-4C52-8AD8-51D0FB40561D")]
    [ClassInterface(ClassInterfaceType.None)]
    public sealed class ShellExtension : IShellExtInit, IContextMenu
    {
        private const uint CfHDrop = 15;
        private const uint MfString = 0x00000000;
        private const uint MfPopup = 0x00000010;
        private const uint MfSeparator = 0x00000800;
        private const uint CmfDefaultOnly = 0x00000001;
        private const uint CmfVerbsOnly = 0x00000002;
        private const uint EInvalidArg = 0x80070057;
        private const uint EFail = 0x80004005;
        private const uint ENotImpl = 0x80004001;

        private sealed class ActionItem
        {
            public string Mode;
            public string Format;
            public string Label;
        }

        private string[] selectedPaths = new string[0];
        private readonly Dictionary<uint, ActionItem> actions = new Dictionary<uint, ActionItem>();

        public void Initialize(IntPtr pidlFolder, IDataObject dataObject, IntPtr hkeyProgID)
        {
            selectedPaths = new string[0];
            if (dataObject == null) return;
            FORMATETC format = new FORMATETC();
            format.cfFormat = (short)CfHDrop;
            format.ptd = IntPtr.Zero;
            format.dwAspect = DVASPECT.DVASPECT_CONTENT;
            format.lindex = -1;
            format.tymed = TYMED.TYMED_HGLOBAL;
            STGMEDIUM medium;
            dataObject.GetData(ref format, out medium);
            try
            {
                uint count = DragQueryFile(medium.unionmember, 0xffffffff, null, 0);
                List<string> paths = new List<string>();
                for (uint i = 0; i < count; i++)
                {
                    uint length = DragQueryFile(medium.unionmember, i, null, 0);
                    StringBuilder path = new StringBuilder((int)length + 1);
                    if (DragQueryFile(medium.unionmember, i, path, (uint)path.Capacity) > 0)
                        paths.Add(path.ToString());
                }
                selectedPaths = paths.ToArray();
            }
            finally { ReleaseStgMedium(ref medium); }
        }

        public uint QueryContextMenu(IntPtr menu, uint indexMenu, uint idCmdFirst, uint idCmdLast, uint flags)
        {
            actions.Clear();
            commandOffset = idCmdFirst;
            if ((flags & CmfDefaultOnly) != 0 || selectedPaths.Length == 0) return 0;
            bool isDds = String.Equals(Path.GetExtension(selectedPaths[0]), ".dds", StringComparison.OrdinalIgnoreCase);
            uint nextId = idCmdFirst;
            IntPtr root = CreatePopupMenu();
            if (root == IntPtr.Zero) return EFail;
            try
            {
                List<KeyValuePair<string, string>> formats = LoadFormats();
                if (isDds)
                {
                    AddFormatSubmenu(root, ref nextId, formats, "Overwrite with Backup", "Backup");
                    AppendMenu(root, MfSeparator, UIntPtr.Zero, null);
                    AddFormatSubmenu(root, ref nextId, formats, "Overwrite original", "Overwrite");
                }
                else
                {
                    AddFormatSubmenu(root, ref nextId, formats, "Convert to DDS-Converted", "Copy");
                }
                AppendMenu(root, MfSeparator, UIntPtr.Zero, null);
                AddAction(root, ref nextId, "Open AC Texture Converter", "Open", "");
                if (nextId - idCmdFirst > idCmdLast - idCmdFirst + 1) return EFail;
                if (!InsertMenu(menu, indexMenu, MfPopup | 0x00000400, new UIntPtr(unchecked((ulong)root.ToInt64())), "AC Texture Converter")) return EFail;
                IntPtr owned = root;
                root = IntPtr.Zero;
                return nextId - idCmdFirst;
            }
            finally { if (root != IntPtr.Zero) DestroyMenu(root); }
        }

        private void AddFormatSubmenu(IntPtr root, ref uint nextId, List<KeyValuePair<string, string>> formats, string label, string mode)
        {
            IntPtr submenu = CreatePopupMenu();
            if (submenu == IntPtr.Zero) throw new COMException("Could not create the AC Texture Converter menu.", unchecked((int)EFail));
            try
            {
                foreach (KeyValuePair<string, string> format in formats)
                    AddAction(submenu, ref nextId, format.Key, mode, format.Value);
                if (!AppendMenu(root, MfPopup, new UIntPtr(unchecked((ulong)submenu.ToInt64())), label))
                    throw new COMException("Could not add a conversion submenu.", unchecked((int)EFail));
                submenu = IntPtr.Zero;
            }
            finally { if (submenu != IntPtr.Zero) DestroyMenu(submenu); }
        }

        private void AddAction(IntPtr menu, ref uint nextId, string label, string mode, string format)
        {
            if (!AppendMenu(menu, MfString, new UIntPtr(nextId), label))
                throw new COMException("Could not add a conversion format.", unchecked((int)EFail));
            actions[nextId] = new ActionItem { Mode = mode, Format = format, Label = label };
            nextId++;
        }

        public void InvokeCommand(ref CMINVOKECOMMANDINFO info)
        {
            if (info.lpVerb.ToInt64() >> 16 != 0) throw new COMException("Unknown AC Texture Converter command.", unchecked((int)EInvalidArg));
            uint id = unchecked((uint)(info.lpVerb.ToInt64() & 0xffff)) + commandOffset;
            ActionItem action;
            if (!actions.TryGetValue(id, out action)) throw new COMException("Unknown AC Texture Converter command.", unchecked((int)EInvalidArg));
            string appRoot = Path.GetDirectoryName(typeof(ShellExtension).Assembly.Location);
            string exe = Path.Combine(appRoot, "AC Texture Converter.exe");
            if (!File.Exists(exe)) throw new COMException("AC Texture Converter.exe is missing from the installation folder.", unchecked((int)EFail));

            string selectionFile = Path.Combine(Path.GetTempPath(), "ACTC-selection-" + Guid.NewGuid().ToString("N") + ".txt");
            File.WriteAllLines(selectionFile, selectedPaths, new UTF8Encoding(false));
            List<string> args = new List<string>();
            if (action.Mode == "Open") args.Add("-OpenWith");
            else
            {
                args.Add("-ShellMode"); args.Add(action.Mode);
                args.Add("-Format"); args.Add(action.Format);
            }
            args.Add("-InputListFile");
            args.Add(selectionFile);
            ProcessStartInfo start = new ProcessStartInfo();
            start.FileName = exe;
            start.WorkingDirectory = appRoot;
            start.UseShellExecute = true;
            start.Arguments = String.Join(" ", args.ConvertAll(QuoteArgument).ToArray());
            try { Process.Start(start); }
            catch { try { File.Delete(selectionFile); } catch { } throw; }
        }

        private uint commandOffset;

        public void GetCommandString(UIntPtr idCmd, uint type, IntPtr reserved, StringBuilder name, uint max)
        {
            throw new COMException("Command strings are not supported.", unchecked((int)ENotImpl));
        }

        private static List<KeyValuePair<string, string>> LoadFormats()
        {
            string[] labels = {
                "BC1 (DXT1, opaque RGB; ignores alpha)", "BC2 (DXT3, alpha)", "BC3 (DXT5, alpha)",
                "BC7 RGBA (preserve alpha)", "BC7 (opaque; remove transparency)", "Uncompressed RGBA8 (32-bit)",
                "A8L8 (R=luminance, A=alpha)", "BC4 (grayscale/channel)", "BC5 (normal maps/RG)", "BC6H (HDR, no alpha)"
            };
            string[] values = { "BC1_UNORM", "BC2_UNORM", "BC3_UNORM", "BC7_UNORM", "BC7_OPAQUE", "R8G8B8A8_UNORM", "A8L8", "BC4_UNORM", "BC5_UNORM", "BC6H_UF16" };
            HashSet<string> enabled = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            for (int i = 0; i < 7; i++) enabled.Add(values[i]);
            try
            {
                string settings = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "DDSForge", "settings.json");
                if (File.Exists(settings))
                {
                    Dictionary<string, object> json = new JavaScriptSerializer().Deserialize<Dictionary<string, object>>(File.ReadAllText(settings));
                    object raw;
                    if (json != null && json.TryGetValue("enabledFormats", out raw))
                    {
                        enabled.Clear();
                        object[] selected = raw as object[];
                        if (selected != null) foreach (object item in selected) enabled.Add(Convert.ToString(item));
                    }
                    else if (json != null && json.TryGetValue("enabledOptionalFormats", out raw))
                    {
                        object[] selected = raw as object[];
                        if (selected != null) foreach (object item in selected) enabled.Add(Convert.ToString(item));
                    }
                }
            }
            catch { }
            List<KeyValuePair<string, string>> result = new List<KeyValuePair<string, string>>();
            for (int i = 0; i < values.Length; i++) if (enabled.Contains(values[i])) result.Add(new KeyValuePair<string, string>(labels[i], values[i]));
            if (result.Count == 0) for (int i = 0; i < 7; i++) result.Add(new KeyValuePair<string, string>(labels[i], values[i]));
            return result;
        }

        private static string QuoteArgument(string value)
        {
            StringBuilder quoted = new StringBuilder("\"");
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

        [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern IntPtr CreatePopupMenu();
        [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern bool AppendMenu(IntPtr menu, uint flags, UIntPtr item, string text);
        [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern bool InsertMenu(IntPtr menu, uint position, uint flags, UIntPtr item, string text);
        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool DestroyMenu(IntPtr menu);
        [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
        private static extern uint DragQueryFile(IntPtr drop, uint file, StringBuilder fileName, uint maxFileName);
        [DllImport("ole32.dll")]
        private static extern void ReleaseStgMedium(ref STGMEDIUM medium);
    }

    [Guid("000214E8-0000-0000-C000-000000000046"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IShellExtInit
    {
        void Initialize(IntPtr pidlFolder, [MarshalAs(UnmanagedType.Interface)] IDataObject dataObject, IntPtr hkeyProgID);
    }

    [Guid("000214E4-0000-0000-C000-000000000046"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IContextMenu
    {
        [PreserveSig] uint QueryContextMenu(IntPtr menu, uint indexMenu, uint idCmdFirst, uint idCmdLast, uint flags);
        void InvokeCommand(ref CMINVOKECOMMANDINFO info);
        void GetCommandString(UIntPtr idCmd, uint type, IntPtr reserved, StringBuilder name, uint max);
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct CMINVOKECOMMANDINFO
    {
        public uint cbSize;
        public uint fMask;
        public IntPtr hwnd;
        public IntPtr lpVerb;
        public IntPtr lpParameters;
        public IntPtr lpDirectory;
        public int nShow;
        public uint dwHotKey;
        public IntPtr hIcon;
        public IntPtr lpTitle;
    }
}

