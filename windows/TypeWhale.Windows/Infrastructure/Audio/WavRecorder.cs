using System.IO;
using NAudio.Wave;
using TypeWhale.Windows.Infrastructure.ASR;

namespace TypeWhale.Windows.Infrastructure.Audio;

public sealed class WavRecorder : IDisposable
{
    private WaveInEvent? waveIn;
    private WaveFileWriter? writer;
    private DateTimeOffset startedAt;
    private string? activePath;

    public bool IsRecording => waveIn != null;

    public string Start(Guid taskId)
    {
        if (IsRecording)
        {
            throw new InvalidOperationException("录音已经开始");
        }

        string directory = Path.Combine(NativeSenseVoiceBridge.AppDataRoot, "Recordings");
        Directory.CreateDirectory(directory);
        activePath = Path.Combine(directory, $"recording_{DateTime.Now:yyyyMMdd_HHmmss}_{taskId:N}.wav");
        startedAt = DateTimeOffset.Now;

        waveIn = new WaveInEvent
        {
            WaveFormat = new WaveFormat(16000, 16, 1),
            BufferMilliseconds = 40
        };
        writer = new WaveFileWriter(activePath, waveIn.WaveFormat);
        waveIn.DataAvailable += (_, e) => writer?.Write(e.Buffer, 0, e.BytesRecorded);
        waveIn.StartRecording();
        return activePath;
    }

    public (string AudioPath, TimeSpan Duration)? Stop()
    {
        if (waveIn == null || activePath == null)
        {
            return null;
        }

        string path = activePath;
        TimeSpan duration = DateTimeOffset.Now - startedAt;
        activePath = null;
        waveIn.StopRecording();
        writer?.Dispose();
        writer = null;
        waveIn.Dispose();
        waveIn = null;
        string latestPath = Path.Combine(Path.GetDirectoryName(path)!, "latest.wav");
        File.Copy(path, latestPath, overwrite: true);
        return (path, duration);
    }

    public void Cancel()
    {
        if (waveIn != null)
        {
            waveIn.StopRecording();
            writer?.Dispose();
            writer = null;
            waveIn.Dispose();
            waveIn = null;
        }

        activePath = null;
    }

    public void Dispose()
    {
        Cancel();
        writer?.Dispose();
        waveIn?.Dispose();
    }
}
