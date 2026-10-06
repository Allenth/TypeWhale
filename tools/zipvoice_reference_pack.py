#!/usr/bin/env python3
"""Build validated, machine-local ZipVoice reference packs."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import re
import shutil
import struct
import subprocess
import tempfile
import wave
from pathlib import Path


SAFE_ID = re.compile(r"^[A-Za-z0-9._-]+$")


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def inspect_wave(path: Path) -> dict:
    with wave.open(str(path), "rb") as source:
        channels = source.getnchannels()
        sample_rate = source.getframerate()
        sample_width = source.getsampwidth()
        frame_count = source.getnframes()
        raw = source.readframes(frame_count)
    if channels != 1 or sample_rate != 24000 or sample_width != 2:
        raise ValueError("reference WAV must be mono PCM16 at 24 kHz")
    values = struct.unpack(f"<{len(raw) // 2}h", raw)
    duration = frame_count / sample_rate
    if not 1 <= duration <= 3:
        raise ValueError(f"reference duration must be 1-3 seconds, got {duration:.2f}")
    rms = math.sqrt(sum(value * value for value in values) / len(values)) / 32768
    clipped_ratio = sum(abs(value) >= 32767 for value in values) / len(values)
    if rms < 0.0001:
        raise ValueError("reference WAV is silent")
    if clipped_ratio > 0.02:
        raise ValueError("reference WAV is materially clipped")
    return {
        "durationSeconds": round(duration, 6),
        "sampleRate": sample_rate,
        "channels": channels,
        "sampleWidthBytes": sample_width,
        "rms": round(rms, 8),
        "clippedRatio": round(clipped_ratio, 8),
    }


def build_pack(
    source_audio: Path,
    transcript: str,
    voice_id: str,
    output_root: Path,
) -> Path:
    source_audio = Path(source_audio).expanduser().resolve()
    output_root = Path(output_root).expanduser().resolve()
    transcript = transcript.strip()
    if not SAFE_ID.fullmatch(voice_id):
        raise ValueError("unsafe ZipVoice voice ID")
    if not transcript:
        raise ValueError("reference transcript is required")
    if not source_audio.is_file():
        raise FileNotFoundError(source_audio)

    output_root.mkdir(parents=True, exist_ok=True)
    staging = Path(tempfile.mkdtemp(prefix=f".{voice_id}.", dir=output_root))
    destination = output_root / voice_id
    try:
        audio = staging / "reference.wav"
        subprocess.run(
            [
                "ffmpeg", "-v", "error", "-y", "-i", str(source_audio),
                "-vn", "-ac", "1", "-ar", "24000", "-c:a", "pcm_s16le",
                "-af",
                (
                    "silenceremove=start_periods=1:start_duration=0.1:"
                    "start_threshold=-50dB,areverse,"
                    "silenceremove=start_periods=1:start_duration=0.2:"
                    "start_threshold=-50dB,areverse,loudnorm=I=-22:TP=-2:LRA=11"
                ),
                str(audio),
            ],
            check=True,
        )
        text = staging / "reference.txt"
        text.write_text(f"{transcript}\n", encoding="utf-8")
        metrics = inspect_wave(audio)
        manifest = {
            "schemaVersion": 1,
            "voiceID": voice_id,
            "experimental": True,
            **metrics,
            "audioSHA256": sha256(audio),
            "textSHA256": sha256(text),
        }
        (staging / "reference.json").write_text(
            json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
        backup = output_root / f".{voice_id}.backup"
        if backup.exists():
            shutil.rmtree(backup)
        if destination.exists():
            os.replace(destination, backup)
        try:
            os.replace(staging, destination)
        except Exception:
            if backup.exists():
                os.replace(backup, destination)
            raise
        if backup.exists():
            shutil.rmtree(backup)
        return destination
    finally:
        if staging.exists():
            shutil.rmtree(staging)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-audio", type=Path, required=True)
    parser.add_argument("--transcript", required=True)
    parser.add_argument("--voice-id", required=True)
    parser.add_argument("--output-root", type=Path, required=True)
    arguments = parser.parse_args()
    path = build_pack(
        arguments.source_audio,
        arguments.transcript,
        arguments.voice_id,
        arguments.output_root,
    )
    print(path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
