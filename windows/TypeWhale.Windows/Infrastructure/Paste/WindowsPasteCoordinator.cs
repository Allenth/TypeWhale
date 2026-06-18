using System.Runtime.InteropServices;
using System.Windows;

namespace TypeWhale.Windows.Infrastructure.Paste;

public sealed class WindowsPasteCoordinator
{
    public async Task PasteTextAsync(string text)
    {
        IDataObject? previousClipboard = null;
        try
        {
            previousClipboard = Clipboard.GetDataObject();
        }
        catch
        {
            previousClipboard = null;
        }

        Clipboard.SetText(text);
        await Task.Delay(80);
        SendCtrlV();
        await Task.Delay(180);

        if (previousClipboard != null)
        {
            try
            {
                Clipboard.SetDataObject(previousClipboard);
            }
            catch
            {
                // Clipboard ownership can legitimately fail when the target app is busy.
            }
        }
    }

    private static void SendCtrlV()
    {
        INPUT[] inputs =
        [
            KeyInput(VirtualKey.Control, false),
            KeyInput(VirtualKey.V, false),
            KeyInput(VirtualKey.V, true),
            KeyInput(VirtualKey.Control, true)
        ];
        SendInput((uint)inputs.Length, inputs, Marshal.SizeOf<INPUT>());
    }

    private static INPUT KeyInput(VirtualKey key, bool keyUp)
    {
        return new INPUT
        {
            type = 1,
            U = new InputUnion
            {
                ki = new KEYBDINPUT
                {
                    wVk = (ushort)key,
                    dwFlags = keyUp ? 0x0002u : 0u
                }
            }
        };
    }

    private enum VirtualKey : ushort
    {
        Control = 0x11,
        V = 0x56
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct INPUT
    {
        public uint type;
        public InputUnion U;
    }

    [StructLayout(LayoutKind.Explicit)]
    private struct InputUnion
    {
        [FieldOffset(0)] public KEYBDINPUT ki;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct KEYBDINPUT
    {
        public ushort wVk;
        public ushort wScan;
        public uint dwFlags;
        public uint time;
        public IntPtr dwExtraInfo;
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);
}
