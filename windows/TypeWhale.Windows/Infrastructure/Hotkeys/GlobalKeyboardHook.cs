using System.Diagnostics;
using System.Runtime.InteropServices;

namespace TypeWhale.Windows.Infrastructure.Hotkeys;

public sealed class GlobalKeyboardHook : IDisposable
{
    private const int WhKeyboardLl = 13;
    private const int WmKeyDown = 0x0100;
    private const int WmKeyUp = 0x0101;
    private const int WmSysKeyDown = 0x0104;
    private const int WmSysKeyUp = 0x0105;
    private readonly LowLevelKeyboardProc proc;
    private IntPtr hookId;
    private bool hotkeyDown;
    private HotkeyGesture gesture = HotkeyGesture.Default;

    public event Action? HotkeyPressed;
    public event Action? HotkeyReleased;

    public HotkeyGesture Gesture
    {
        get => gesture;
        set
        {
            gesture = value;
            hotkeyDown = false;
        }
    }

    public GlobalKeyboardHook()
    {
        proc = HookCallback;
    }

    public void Start()
    {
        if (hookId != IntPtr.Zero)
        {
            return;
        }

        using Process currentProcess = Process.GetCurrentProcess();
        IntPtr moduleHandle = currentProcess.MainModule?.ModuleName is string moduleName
            ? GetModuleHandle(moduleName)
            : IntPtr.Zero;

        hookId = SetWindowsHookEx(WhKeyboardLl, proc, moduleHandle, 0);
        if (hookId == IntPtr.Zero)
        {
            throw new InvalidOperationException($"无法安装全局热键，Win32 error {Marshal.GetLastWin32Error()}");
        }
    }

    public void Stop()
    {
        if (hookId != IntPtr.Zero)
        {
            UnhookWindowsHookEx(hookId);
            hookId = IntPtr.Zero;
        }
    }

    private IntPtr HookCallback(int nCode, IntPtr wParam, IntPtr lParam)
    {
        if (nCode >= 0)
        {
            int message = wParam.ToInt32();
            bool keyDownMessage = message == WmKeyDown || message == WmSysKeyDown;
            bool keyUpMessage = message == WmKeyUp || message == WmSysKeyUp;
            KbdLlHookStruct key = Marshal.PtrToStructure<KbdLlHookStruct>(lParam);
            bool keyBelongsToHotkey = gesture.Contains(key.vkCode);
            bool configuredHotkeyDown = gesture.IsPressed(IsKeyDown);

            if (keyDownMessage && configuredHotkeyDown)
            {
                if (!hotkeyDown)
                {
                    hotkeyDown = true;
                    HotkeyPressed?.Invoke();
                }

                return new IntPtr(1);
            }
            else if (keyUpMessage && hotkeyDown && keyBelongsToHotkey)
            {
                hotkeyDown = false;
                HotkeyReleased?.Invoke();

                return new IntPtr(1);
            }
        }

        return CallNextHookEx(hookId, nCode, wParam, lParam);
    }

    private static bool IsKeyDown(int virtualKey)
    {
        return (GetAsyncKeyState(virtualKey) & 0x8000) != 0;
    }

    public void Dispose()
    {
        Stop();
    }

    private delegate IntPtr LowLevelKeyboardProc(int nCode, IntPtr wParam, IntPtr lParam);

    [StructLayout(LayoutKind.Sequential)]
    private struct KbdLlHookStruct
    {
        public int vkCode;
        public int scanCode;
        public int flags;
        public int time;
        public IntPtr dwExtraInfo;
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr SetWindowsHookEx(int idHook, LowLevelKeyboardProc lpfn, IntPtr hMod, uint dwThreadId);

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Auto)]
    private static extern IntPtr GetModuleHandle(string lpModuleName);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool UnhookWindowsHookEx(IntPtr hhk);

    [DllImport("user32.dll")]
    private static extern IntPtr CallNextHookEx(IntPtr hhk, int nCode, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll")]
    private static extern short GetAsyncKeyState(int vKey);
}
