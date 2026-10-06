#!/usr/bin/env python3
import importlib.util
import math
import struct
import tempfile
import wave
from pathlib import Path


worker_path = Path(__file__).parents[1] / "Resources/openclaw_tts_worker.py"
spec = importlib.util.spec_from_file_location("openclaw_tts_worker", worker_path)
worker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(worker)

with tempfile.NamedTemporaryFile(suffix=".wav") as output:
    with wave.open(output.name, "wb") as wav:
        wav.setparams((1, 2, 44_100, 0, "NONE", "not compressed"))
        samples = [int(math.sin(index / 20) * 4_000) for index in range(4_410)]
        wav.writeframes(struct.pack(f"<{len(samples)}h", *samples))

    gain = worker.normalize_wav_peak(output.name)
    with wave.open(output.name, "rb") as wav:
        frames = wav.readframes(wav.getnframes())
    normalized = struct.unpack(f"<{len(frames) // 2}h", frames)

    assert gain > 6.0
    assert 29_000 <= max(abs(value) for value in normalized) <= 29_500

print("OpenClawTTSWorkerLoudnessCheck passed")
