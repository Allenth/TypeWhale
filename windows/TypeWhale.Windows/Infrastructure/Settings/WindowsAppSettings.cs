using System.IO;
using System.Text.Json;
using TypeWhale.Windows.Infrastructure.ASR;
using TypeWhale.Windows.Infrastructure.Hotkeys;

namespace TypeWhale.Windows.Infrastructure.Settings;

public sealed class WindowsAppSettings
{
    private static readonly JsonSerializerOptions JsonOptions = new() { WriteIndented = true };

    public int[] HotkeyVirtualKeys { get; set; } = HotkeyGesture.Default.VirtualKeys;

    public HotkeyGesture HotkeyGesture => HotkeyGesture.Create(HotkeyVirtualKeys);

    private static string SettingsPath =>
        Path.Combine(NativeSenseVoiceBridge.AppDataRoot, "windows-settings.json");

    public static WindowsAppSettings Load()
    {
        try
        {
            if (File.Exists(SettingsPath))
            {
                string json = File.ReadAllText(SettingsPath);
                return JsonSerializer.Deserialize<WindowsAppSettings>(json) ?? new WindowsAppSettings();
            }
        }
        catch
        {
            // A corrupt settings file should not prevent the app from launching.
        }

        return new WindowsAppSettings();
    }

    public void Save()
    {
        Directory.CreateDirectory(Path.GetDirectoryName(SettingsPath)!);
        File.WriteAllText(SettingsPath, JsonSerializer.Serialize(this, JsonOptions));
    }
}
