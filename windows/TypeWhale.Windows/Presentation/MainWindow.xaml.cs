using System.Windows;
using System.Windows.Input;
using TypeWhale.Windows.Application;
using TypeWhale.Windows.Infrastructure.Hotkeys;

namespace TypeWhale.Windows.Presentation;

public partial class MainWindow : Window
{
    private readonly SpeechInputCoordinator coordinator;
    private bool isRecording;
    private bool isCapturingHotkey;

    public MainWindow()
    {
        InitializeComponent();
        coordinator = new SpeechInputCoordinator(Dispatcher);
        coordinator.StatusChanged += (status, detail) =>
        {
            StatusText.Text = status;
            DetailText.Text = detail;
        };
        coordinator.RecordingChanged += recording =>
        {
            isRecording = recording;
            RecordButton.Content = recording ? "停止" : coordinator.HotkeyDisplay;
        };
        HistoryList.ItemsSource = coordinator.RecentTranscriptions;
        Loaded += (_, _) =>
        {
            coordinator.Start();
            UpdateHotkeyLabels();
        };
        Closed += (_, _) => coordinator.Dispose();
        PreviewKeyDown += MainWindow_PreviewKeyDown;
    }

    private void RecordButton_Click(object sender, RoutedEventArgs e)
    {
        coordinator.ToggleFromButton();
    }

    private void ChangeHotkeyButton_Click(object sender, RoutedEventArgs e)
    {
        isCapturingHotkey = true;
        ChangeHotkeyButton.Content = "按下组合键";
        RecordButton.Content = "等待组合键";
        DetailText.Text = "请按下一个包含 Ctrl、Alt、Shift 或 Win 的组合键，Esc 取消";
        Focus();
    }

    private void MainWindow_PreviewKeyDown(object sender, KeyEventArgs e)
    {
        if (!isCapturingHotkey)
        {
            return;
        }

        e.Handled = true;
        Key key = e.Key == Key.System ? e.SystemKey : e.Key;
        if (key == Key.Escape)
        {
            StopHotkeyCapture();
            return;
        }

        int primaryVirtualKey = KeyInterop.VirtualKeyFromKey(key);
        List<int> virtualKeys = ModifierVirtualKeys().ToList();
        if (primaryVirtualKey > 0 && !IsModifierKey(key))
        {
            virtualKeys.Add(primaryVirtualKey);
        }

        if (virtualKeys.Count < 2 || !virtualKeys.Any(IsModifierVirtualKey))
        {
            ChangeHotkeyButton.Content = "继续按键";
            DetailText.Text = "需要至少一个修饰键，再加一个普通键";
            return;
        }

        HotkeyGesture gesture = HotkeyGesture.Create(virtualKeys);
        coordinator.UpdateHotkey(gesture);
        StopHotkeyCapture();
        UpdateHotkeyLabels();
        DetailText.Text = $"快捷键已设置为 {gesture.DisplayText}";
    }

    private void StopHotkeyCapture()
    {
        isCapturingHotkey = false;
        ChangeHotkeyButton.Content = "更改";
        RecordButton.Content = isRecording ? "停止" : coordinator.HotkeyDisplay;
    }

    private void UpdateHotkeyLabels()
    {
        string display = coordinator.HotkeyDisplay;
        MainShortcutText.Text = display;
        SidebarShortcutText.Text = display;
        RecordButton.Content = isRecording ? "停止" : display;
    }

    private static IEnumerable<int> ModifierVirtualKeys()
    {
        ModifierKeys modifiers = Keyboard.Modifiers;
        if (modifiers.HasFlag(ModifierKeys.Control))
        {
            yield return 0x11;
        }

        if (modifiers.HasFlag(ModifierKeys.Alt))
        {
            yield return 0x12;
        }

        if (modifiers.HasFlag(ModifierKeys.Shift))
        {
            yield return 0x10;
        }

        if (modifiers.HasFlag(ModifierKeys.Windows))
        {
            yield return 0x5B;
        }
    }

    private static bool IsModifierVirtualKey(int virtualKey)
    {
        return virtualKey is 0x10 or 0x11 or 0x12 or 0x5B;
    }

    private static bool IsModifierKey(Key key)
    {
        return key is Key.LeftCtrl
            or Key.RightCtrl
            or Key.LeftAlt
            or Key.RightAlt
            or Key.LeftShift
            or Key.RightShift
            or Key.LWin
            or Key.RWin
            or Key.System;
    }

}
