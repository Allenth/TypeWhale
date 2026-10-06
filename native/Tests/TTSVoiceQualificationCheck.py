#!/usr/bin/env python3
import importlib.util
import json
import tempfile
import wave
from pathlib import Path

root = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location(
    "tts_voice_qualification", root / "tools/tts_voice_qualification.py"
)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

with tempfile.TemporaryDirectory() as directory:
    path = Path(directory) / "valid.wav"
    with wave.open(str(path), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(24000)
        output.writeframes((b"\x00\x10" * 2400))
    metrics = module.inspect_wave(path)
    assert metrics["durationSeconds"] == 0.1
    assert metrics["rms"] > 0

    silent = Path(directory) / "silent.wav"
    with wave.open(str(silent), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(24000)
        output.writeframes((b"\x00\x00" * 2400))
    try:
        module.inspect_wave(silent)
        raise AssertionError("silent WAV should fail")
    except ValueError:
        pass

    evidence = Path(directory) / "nested/evidence.json"
    module.atomic_write(evidence, {"voices": {"a": "passed"}})
    assert json.loads(evidence.read_text())["voices"]["a"] == "passed"
    assert not evidence.with_suffix(".json.tmp").exists()

assert len(module.QWEN_VOICES) == 9
assert len(module.KOKORO_VOICES) == 103
assert len(set(module.KOKORO_VOICES)) == 103
zip_voices = module.MODELS["zipvoice-distill-int8-zh-en-emilia"][1]
assert zip_voices == [
    "zipvoice-default",
    "zipvoice-serena",
    "zipvoice-cosy",
    "zipvoice-video-reference",
]
assert set(module.ZIPVOICE_SAMPLES) == {
    "zh-short-v1", "en-short-v1", "mixed-v1", "zh-long-v1"
}
print("TTSVoiceQualificationCheck passed")
