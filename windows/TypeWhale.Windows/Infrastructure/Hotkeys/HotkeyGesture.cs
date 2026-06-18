namespace TypeWhale.Windows.Infrastructure.Hotkeys;

public sealed record HotkeyGesture(int[] VirtualKeys)
{
    public static HotkeyGesture Default { get; } = new([0x11, 0x12, 0x20]);

    public IReadOnlySet<int> KeySet => VirtualKeys.ToHashSet();

    public string DisplayText => string.Join(" + ", VirtualKeys.Select(DisplayName));

    public bool Contains(int virtualKey) => KeySet.Contains(NormalizeModifier(virtualKey));

    public bool IsPressed(Func<int, bool> isKeyDown) => KeySet.All(isKeyDown);

    public static HotkeyGesture Create(IEnumerable<int> virtualKeys)
    {
        int[] normalized = virtualKeys
            .Select(NormalizeModifier)
            .Distinct()
            .OrderBy(SortOrder)
            .ThenBy(value => value)
            .ToArray();

        return normalized.Length == 0 ? Default : new HotkeyGesture(normalized);
    }

    private static int NormalizeModifier(int virtualKey)
    {
        return virtualKey switch
        {
            0xA0 or 0xA1 => 0x10,
            0xA2 or 0xA3 => 0x11,
            0xA4 or 0xA5 => 0x12,
            0x5B or 0x5C => 0x5B,
            _ => virtualKey
        };
    }

    private static int SortOrder(int virtualKey)
    {
        return virtualKey switch
        {
            0x11 => 0,
            0x12 => 1,
            0x10 => 2,
            0x5B => 3,
            _ => 4
        };
    }

    private static string DisplayName(int virtualKey)
    {
        return virtualKey switch
        {
            0x08 => "Backspace",
            0x09 => "Tab",
            0x0D => "Enter",
            0x10 => "Shift",
            0x11 => "Ctrl",
            0x12 => "Alt",
            0x1B => "Esc",
            0x20 => "Space",
            0x25 => "Left",
            0x26 => "Up",
            0x27 => "Right",
            0x28 => "Down",
            0x2D => "Insert",
            0x2E => "Delete",
            0x5B => "Win",
            >= 0x30 and <= 0x39 => ((char)virtualKey).ToString(),
            >= 0x41 and <= 0x5A => ((char)virtualKey).ToString(),
            >= 0x70 and <= 0x7B => $"F{virtualKey - 0x6F}",
            _ => $"VK {virtualKey:X2}"
        };
    }
}
