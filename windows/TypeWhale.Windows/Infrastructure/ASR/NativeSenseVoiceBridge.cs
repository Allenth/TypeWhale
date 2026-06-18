using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Runtime.InteropServices;
using TypeWhale.Windows.Domain;

namespace TypeWhale.Windows.Infrastructure.ASR;

public sealed class NativeSenseVoiceBridge : IDisposable
{
    private const string NativeLibraryName = "TypeSpeakerNativeASR";
    private static readonly string[] NativeDependencyNames =
    [
        "sherpa-onnx-c-api.dll",
        "onnxruntime.dll",
        "onnxruntime_providers_shared.dll"
    ];

    private readonly object sync = new();
    private IntPtr recognizer;
    private string? loadedModelPath;

    static NativeSenseVoiceBridge()
    {
        NativeLibrary.SetDllImportResolver(typeof(NativeSenseVoiceBridge).Assembly, ResolveNativeLibrary);
        if (Directory.Exists(NativeLibraryDirectory))
        {
            SetDllDirectory(NativeLibraryDirectory);
        }
    }

    public bool IsAvailable => MissingSetupFiles.Count == 0;
    public bool IsVoiceActivityDetectionAvailable => File.Exists(VadModelPath) && RuntimeFilesAvailable;

    public static IReadOnlyList<string> MissingSetupFiles
    {
        get
        {
            List<string> missing = [];
            AddIfMissing(missing, ModelPath);
            AddIfMissing(missing, TokensPath);
            AddIfMissing(missing, VadModelPath);
            AddIfMissing(missing, NativeLibraryPath);
            foreach (string dependency in NativeDependencyPaths)
            {
                AddIfMissing(missing, dependency);
            }

            return missing;
        }
    }

    public static string MissingSetupDescription
    {
        get
        {
            IReadOnlyList<string> missing = MissingSetupFiles;
            return missing.Count == 0
                ? "模型和 Windows native DLL 已就绪"
                : "缺少：" + string.Join(", ", missing.Select(path => Path.GetFileName(path)));
        }
    }

    public static string AppDataRoot =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "TypeWhale");

    public static string ModelRoot =>
        Path.Combine(AppContext.BaseDirectory, "Models");

    public static string ModelPath =>
        Path.Combine(ModelRoot, "sensevoice-native", "model.onnx");

    public static string TokensPath =>
        Path.Combine(ModelRoot, "sensevoice-native", "tokens.txt");

    public static string VadModelPath =>
        Path.Combine(ModelRoot, "vad", "silero_vad.onnx");

    public static string NativeLibraryPath =>
        Path.Combine(NativeLibraryDirectory, $"{NativeLibraryName}.dll");

    public static string NativeLibraryDirectory =>
        Path.Combine(AppContext.BaseDirectory, "runtimes", "win-x64", "native");

    private static IEnumerable<string> NativeDependencyPaths =>
        NativeDependencyNames.Select(name => Path.Combine(NativeLibraryDirectory, name));

    private static bool RuntimeFilesAvailable =>
        File.Exists(NativeLibraryPath) && NativeDependencyPaths.All(File.Exists);

    private static void AddIfMissing(List<string> missing, string path)
    {
        if (!File.Exists(path))
        {
            missing.Add(path);
        }
    }

    public Task<bool> ContainsSpeechAsync(string audioPath, CancellationToken cancellationToken = default)
    {
        return Task.Run(() =>
        {
            cancellationToken.ThrowIfCancellationRequested();
            IntPtr error = IntPtr.Zero;
            int result = TypeSpeakerNativeVadHasSpeech(audioPath, VadModelPath, ref error);
            try
            {
                ThrowIfNativeError(error, result < 0 ? "人声检测失败" : null);
                return result == 1;
            }
            finally
            {
                FreeIfNeeded(error);
            }
        }, cancellationToken);
    }

    public Task<(string Text, double DurationSeconds)> TranscribeAsync(
        string audioPath,
        ASRConfiguration configuration,
        CancellationToken cancellationToken = default)
    {
        return Task.Run(() =>
        {
            cancellationToken.ThrowIfCancellationRequested();
            Stopwatch stopwatch = Stopwatch.StartNew();
            IntPtr recognizerHandle = LoadRecognizer();
            IntPtr error = IntPtr.Zero;
            IntPtr text = TypeSpeakerNativeRecognizerTranscribe(
                recognizerHandle,
                audioPath,
                configuration.SenseVoiceLanguage,
                ref error);
            try
            {
                ThrowIfNativeError(error, text == IntPtr.Zero ? "原生语音识别模型未返回识别结果" : null);
                string result = Marshal.PtrToStringUTF8(text) ?? string.Empty;
                return (result, stopwatch.Elapsed.TotalSeconds);
            }
            finally
            {
                FreeIfNeeded(text);
                FreeIfNeeded(error);
            }
        }, cancellationToken);
    }

    public void WarmUp()
    {
        if (!IsAvailable)
        {
            return;
        }

        _ = Task.Run(() =>
        {
            try
            {
                _ = LoadRecognizer();
            }
            catch
            {
                // The UI reports availability from files; actual native load errors surface on recognition.
            }
        });
    }

    public void Reload()
    {
        lock (sync)
        {
            DestroyRecognizer();
        }
    }

    private IntPtr LoadRecognizer()
    {
        lock (sync)
        {
            if (recognizer != IntPtr.Zero && loadedModelPath == ModelPath)
            {
                return recognizer;
            }

            DestroyRecognizer();
            IntPtr error = IntPtr.Zero;
            recognizer = TypeSpeakerNativeRecognizerCreate(ModelPath, TokensPath, string.Empty, ref error);
            loadedModelPath = ModelPath;
            try
            {
                ThrowIfNativeError(error, recognizer == IntPtr.Zero ? "无法初始化原生语音识别模型" : null);
                return recognizer;
            }
            finally
            {
                FreeIfNeeded(error);
            }
        }
    }

    private static void ThrowIfNativeError(IntPtr error, string? fallback)
    {
        if (error != IntPtr.Zero)
        {
            throw new InvalidOperationException(Marshal.PtrToStringUTF8(error) ?? fallback ?? "原生 ASR 调用失败");
        }

        if (!string.IsNullOrWhiteSpace(fallback))
        {
            throw new InvalidOperationException(fallback);
        }
    }

    private void DestroyRecognizer()
    {
        if (recognizer != IntPtr.Zero)
        {
            TypeSpeakerNativeRecognizerDestroy(recognizer);
            recognizer = IntPtr.Zero;
            loadedModelPath = null;
        }
    }

    private static void FreeIfNeeded(IntPtr value)
    {
        if (value != IntPtr.Zero)
        {
            TypeSpeakerNativeStringFree(value);
        }
    }

    private static IntPtr ResolveNativeLibrary(string libraryName, Assembly assembly, DllImportSearchPath? searchPath)
    {
        if (libraryName == NativeLibraryName && File.Exists(NativeLibraryPath))
        {
            return NativeLibrary.Load(NativeLibraryPath);
        }

        return IntPtr.Zero;
    }

    public void Dispose()
    {
        lock (sync)
        {
            DestroyRecognizer();
        }
    }

    [DllImport(NativeLibraryName, CallingConvention = CallingConvention.Cdecl)]
    private static extern IntPtr TypeSpeakerNativeRecognizerCreate(
        [MarshalAs(UnmanagedType.LPUTF8Str)]
        string modelPath,
        [MarshalAs(UnmanagedType.LPUTF8Str)]
        string tokensPath,
        [MarshalAs(UnmanagedType.LPUTF8Str)]
        string hotwords,
        ref IntPtr errorMessage);

    [DllImport(NativeLibraryName, CallingConvention = CallingConvention.Cdecl)]
    private static extern IntPtr TypeSpeakerNativeRecognizerTranscribe(
        IntPtr recognizer,
        [MarshalAs(UnmanagedType.LPUTF8Str)]
        string audioPath,
        [MarshalAs(UnmanagedType.LPUTF8Str)]
        string language,
        ref IntPtr errorMessage);

    [DllImport(NativeLibraryName, CallingConvention = CallingConvention.Cdecl)]
    private static extern int TypeSpeakerNativeVadHasSpeech(
        [MarshalAs(UnmanagedType.LPUTF8Str)]
        string audioPath,
        [MarshalAs(UnmanagedType.LPUTF8Str)]
        string modelPath,
        ref IntPtr errorMessage);

    [DllImport(NativeLibraryName, CallingConvention = CallingConvention.Cdecl)]
    private static extern void TypeSpeakerNativeRecognizerDestroy(IntPtr recognizer);

    [DllImport(NativeLibraryName, CallingConvention = CallingConvention.Cdecl)]
    private static extern void TypeSpeakerNativeStringFree(IntPtr value);

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern bool SetDllDirectory(string lpPathName);
}
