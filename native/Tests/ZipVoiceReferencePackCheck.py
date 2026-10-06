#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import importlib.util
import json
import math
import struct
import tempfile
import wave
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "zipvoice_reference_pack",
    ROOT / "tools/zipvoice_reference_pack.py",
)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader
SPEC.loader.exec_module(MODULE)


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


with tempfile.TemporaryDirectory(prefix="ZipVoiceReferencePackCheck-") as directory:
    root = Path(directory)
    source = root / "source.wav"
    with wave.open(str(source), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(44100)
        samples = [
            int(math.sin(2 * math.pi * 220 * index / 44100) * 5000)
            for index in range(44100 * 2)
        ]
        output.writeframes(struct.pack(f"<{len(samples)}h", *samples))

    pack = MODULE.build_pack(
        source_audio=source,
        transcript="完全匹配的参考文字",
        voice_id="zipvoice-test",
        output_root=root / "references",
    )
    manifest = json.loads((pack / "reference.json").read_text())
    assert manifest["voiceID"] == "zipvoice-test"
    assert manifest["sampleRate"] == 24000
    assert manifest["channels"] == 1
    assert manifest["audioSHA256"] == sha256(pack / "reference.wav")
    assert manifest["textSHA256"] == sha256(pack / "reference.txt")
    assert (pack / "reference.txt").read_text() == "完全匹配的参考文字\n"

    try:
        MODULE.build_pack(source, "文字", "../escape", root / "references")
        raise AssertionError("unsafe voice ID should fail")
    except ValueError:
        pass

    try:
        MODULE.build_pack(source, "   ", "empty-text", root / "references")
        raise AssertionError("blank transcript should fail")
    except ValueError:
        pass

    overlong = root / "overlong.wav"
    with wave.open(str(overlong), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(44100)
        samples = [
            int(math.sin(2 * math.pi * 220 * index / 44100) * 5000)
            for index in range(44100 * 4)
        ]
        output.writeframes(struct.pack(f"<{len(samples)}h", *samples))
    try:
        MODULE.build_pack(overlong, "四秒参考音频过长", "overlong", root / "references")
        raise AssertionError("single-speaker reference longer than 3 seconds should fail")
    except ValueError as error:
        assert "3 seconds" in str(error)

print("ZipVoiceReferencePackCheck passed")
