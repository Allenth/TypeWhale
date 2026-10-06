#!/usr/bin/env python3
import importlib.util
import math
from pathlib import Path


root = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location(
    "tts_benchmark_worker",
    root / "native/Resources/tts_benchmark_worker.py",
)
worker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(worker)

sample_rate = 24_000
duration = 0.25
count = int(sample_rate * duration)


def tone(frequency: float, amplitude: float = 0.5) -> list[float]:
    return [
        amplitude * math.sin(2 * math.pi * frequency * index / sample_rate)
        for index in range(count)
    ]


def rms(values: list[float]) -> float:
    return math.sqrt(sum(value * value for value in values) / len(values))


overloaded = [1.2, -1.2] + tone(1_000)
processed = worker.post_process_zipvoice_samples(overloaded, sample_rate)
assert len(processed) == len(overloaded), "post-processing must never trim speech"
assert max(abs(value) for value in processed) <= 0.95
assert all(abs(value) < 1.0 for value in processed)

voice = tone(1_000)
low_noise = tone(20)
high_noise = tone(11_900)
processed_voice = worker.post_process_zipvoice_samples(voice, sample_rate)
processed_low = worker.post_process_zipvoice_samples(low_noise, sample_rate)
processed_high = worker.post_process_zipvoice_samples(high_noise, sample_rate)
assert rms(processed_voice) >= rms(voice) * 0.90
assert rms(processed_low) <= rms(low_noise) * 0.60
assert rms(processed_high) <= rms(high_noise) * 0.60

print("TTSZipVoicePostProcessingCheck passed")
