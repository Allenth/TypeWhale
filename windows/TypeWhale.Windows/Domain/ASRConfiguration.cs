namespace TypeWhale.Windows.Domain;

public enum RecognitionLanguageMode
{
    Chinese
}

public sealed record ASRConfiguration(RecognitionLanguageMode LanguageMode)
{
    public static ASRConfiguration Current { get; } = new(RecognitionLanguageMode.Chinese);

    public string SenseVoiceLanguage => LanguageMode switch
    {
        RecognitionLanguageMode.Chinese => "auto",
        _ => "auto"
    };
}

public sealed record RecordingTask(
    Guid Id,
    string AudioPath,
    ASRConfiguration Configuration,
    TimeSpan Duration);

public sealed record RecentTranscription(string Text, double? RecognitionSeconds);
