#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import importlib.util
import json
import tempfile
import wave
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "tts_benchmark_worker",
    ROOT / "native/Resources/tts_benchmark_worker.py",
)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader
SPEC.loader.exec_module(MODULE)


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def create_pack(root: Path, voice_id: str, duration_seconds: int = 2) -> Path:
    directory = root / "references" / voice_id
    directory.mkdir(parents=True)
    audio = directory / "reference.wav"
    with wave.open(str(audio), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(24000)
        output.writeframes(b"\x00\x10" * 24000 * duration_seconds)
    text = directory / "reference.txt"
    text.write_text("完全匹配的文字\n")
    manifest = {
        "schemaVersion": 1,
        "voiceID": voice_id,
        "sampleRate": 24000,
        "channels": 1,
        "audioSHA256": digest(audio),
        "textSHA256": digest(text),
    }
    (directory / "reference.json").write_text(json.dumps(manifest))
    return directory


with tempfile.TemporaryDirectory(prefix="ZipVoiceWorkerVoiceCheck-") as directory:
    pack = Path(directory)
    reference = create_pack(pack, "zipvoice-test")
    loaded = MODULE.load_zipvoice_reference(pack, "zipvoice-test")
    assert loaded.voice_id == "zipvoice-test"
    assert loaded.text == "完全匹配的文字"
    assert loaded.sample_rate == 24000
    assert len(loaded.samples) == 24000 * 2

    create_pack(pack, "zipvoice-overlong", duration_seconds=4)
    try:
        MODULE.load_zipvoice_reference(pack, "zipvoice-overlong")
        raise AssertionError("overlong single-speaker reference should fail")
    except ValueError as error:
        assert "1-3 seconds" in str(error)

    create_pack(pack, "zipvoice-video-reference", duration_seconds=4)
    video_reference = MODULE.load_zipvoice_reference(pack, "zipvoice-video-reference")
    assert len(video_reference.samples) == 24000 * 4

    for voice_id in ("../escape", "missing"):
        try:
            MODULE.load_zipvoice_reference(pack, voice_id)
            raise AssertionError(f"{voice_id} should fail")
        except ValueError:
            pass

    (reference / "reference.txt").write_text("已篡改\n")
    try:
        MODULE.load_zipvoice_reference(pack, "zipvoice-test")
        raise AssertionError("tampered transcript should fail")
    except ValueError:
        pass

print("ZipVoiceWorkerVoiceCheck passed")
