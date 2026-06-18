using System.Collections.ObjectModel;
using System.Windows.Threading;
using TypeWhale.Windows.Domain;
using TypeWhale.Windows.Infrastructure.ASR;
using TypeWhale.Windows.Infrastructure.Audio;
using TypeWhale.Windows.Infrastructure.Hotkeys;
using TypeWhale.Windows.Infrastructure.Paste;
using TypeWhale.Windows.Infrastructure.Settings;

namespace TypeWhale.Windows.Application;

public sealed class SpeechInputCoordinator : IDisposable
{
    private readonly WavRecorder recorder = new();
    private readonly GlobalKeyboardHook hotkey = new();
    private readonly NativeSenseVoiceBridge asr = new();
    private readonly WindowsPasteCoordinator paste = new();
    private readonly WindowsAppSettings settings = WindowsAppSettings.Load();
    private readonly Dispatcher dispatcher;
    private Guid? activeTaskId;
    private bool hotkeyIsPressed;
    private string? hotkeyStartError;
    private CancellationTokenSource? currentTaskCancellation;
    private DispatcherTimer? longPressTimer;

    public event Action<string, string>? StatusChanged;
    public event Action<bool>? RecordingChanged;
    public ObservableCollection<RecentTranscription> RecentTranscriptions { get; } = [];
    public string HotkeyDisplay => hotkey.Gesture.DisplayText;

    public SpeechInputCoordinator(Dispatcher dispatcher)
    {
        this.dispatcher = dispatcher;
        hotkey.Gesture = settings.HotkeyGesture;
        hotkey.HotkeyPressed += HandleHotkeyPressed;
        hotkey.HotkeyReleased += HandleHotkeyReleased;
    }

    public void UpdateHotkey(HotkeyGesture gesture)
    {
        settings.HotkeyVirtualKeys = gesture.VirtualKeys;
        settings.Save();
        hotkey.Gesture = gesture;
        ReportReadyState();
    }

    public void Start()
    {
        try
        {
            hotkey.Start();
            hotkeyStartError = null;
        }
        catch (Exception ex)
        {
            hotkeyStartError = ex.Message;
        }

        asr.WarmUp();
        ReportReadyState();
    }

    private void HandleHotkeyPressed()
    {
        dispatcher.Invoke(() =>
        {
            hotkeyIsPressed = true;
            if (recorder.IsRecording)
            {
                return;
            }

            longPressTimer?.Stop();
            longPressTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(280) };
            longPressTimer.Tick += (_, _) =>
            {
                longPressTimer?.Stop();
                if (hotkeyIsPressed && !recorder.IsRecording)
                {
                    StartRecording($"松开 {HotkeyDisplay} 完成录音");
                }
            };
            longPressTimer.Start();
        });
    }

    private void HandleHotkeyReleased()
    {
        dispatcher.Invoke(async () =>
        {
            hotkeyIsPressed = false;
            bool wasWaitingForLongPress = longPressTimer?.IsEnabled == true;
            longPressTimer?.Stop();

            if (recorder.IsRecording)
            {
                await FinishRecordingAsync();
                return;
            }

            if (wasWaitingForLongPress)
            {
                StartRecording($"再次按下 {HotkeyDisplay} 完成录音");
            }
        });
    }

    public void ToggleFromButton()
    {
        if (recorder.IsRecording)
        {
            _ = FinishRecordingAsync();
        }
        else
        {
            StartRecording("点击停止按钮完成录音");
        }
    }

    private void StartRecording(string instruction)
    {
        if (!asr.IsAvailable)
        {
            StatusChanged?.Invoke("需要安装本地模型", NativeSenseVoiceBridge.MissingSetupDescription);
            return;
        }

        activeTaskId = Guid.NewGuid();
        currentTaskCancellation?.Cancel();
        currentTaskCancellation = new CancellationTokenSource();
        recorder.Start(activeTaskId.Value);
        RecordingChanged?.Invoke(true);
        StatusChanged?.Invoke("录音中", instruction);
    }

    private async Task FinishRecordingAsync()
    {
        Guid? taskId = activeTaskId;
        activeTaskId = null;
        (string AudioPath, TimeSpan Duration)? result = recorder.Stop();
        RecordingChanged?.Invoke(false);

        if (taskId == null || result == null)
        {
            StatusChanged?.Invoke("没有录到声音", "请再试一次");
            return;
        }

        RecordingTask task = new(taskId.Value, result.Value.AudioPath, ASRConfiguration.Current, result.Value.Duration);
        StatusChanged?.Invoke("正在检测人声", $"已完整录制 {task.Duration.TotalSeconds:F1} 秒");

        try
        {
            CancellationToken cancellationToken = currentTaskCancellation?.Token ?? CancellationToken.None;
            bool hasSpeech = await asr.ContainsSpeechAsync(task.AudioPath, cancellationToken);
            if (!hasSpeech)
            {
                StatusChanged?.Invoke("没有检测到人声", "不会粘贴空文本");
                return;
            }

            StatusChanged?.Invoke("正在识别", "本地 SenseVoice final 识别中");
            (string text, double seconds) = await asr.TranscribeAsync(task.AudioPath, task.Configuration, cancellationToken);
            text = text.Trim();
            if (string.IsNullOrWhiteSpace(text))
            {
                StatusChanged?.Invoke("识别结果为空", "不会粘贴空文本");
                return;
            }

            RecentTranscriptions.Insert(0, new RecentTranscription(text, seconds));
            while (RecentTranscriptions.Count > 5)
            {
                RecentTranscriptions.RemoveAt(RecentTranscriptions.Count - 1);
            }

            await paste.PasteTextAsync(text);
            StatusChanged?.Invoke("已粘贴", $"识别时间 {seconds:F2} 秒");
        }
        catch (Exception ex)
        {
            StatusChanged?.Invoke("处理失败", ex.Message);
        }
        finally
        {
            ReportReadyState();
        }
    }

    private void ReportReadyState()
    {
        if (asr.IsAvailable)
        {
            if (hotkeyStartError != null)
            {
                StatusChanged?.Invoke("热键初始化失败", $"{hotkeyStartError}。仍可使用按钮录音。");
            }
            else
            {
                StatusChanged?.Invoke("等待录音", $"{HotkeyDisplay} 录音");
            }
        }
        else
        {
            StatusChanged?.Invoke("需要安装本地模型", NativeSenseVoiceBridge.MissingSetupDescription);
        }
    }

    public void Dispose()
    {
        currentTaskCancellation?.Cancel();
        recorder.Dispose();
        hotkey.Dispose();
        asr.Dispose();
    }
}
