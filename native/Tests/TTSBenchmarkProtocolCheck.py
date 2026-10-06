#!/usr/bin/env python3
import json
import subprocess
import sys
import tempfile
import time
import wave
from pathlib import Path


root = Path(__file__).resolve().parents[2]
worker = root / "native/Resources/tts_benchmark_worker.py"

with tempfile.TemporaryDirectory() as temporary:
    output = Path(temporary) / "sample.wav"
    process = subprocess.Popen(
        [sys.executable, str(worker), "--engine", "fake"],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )

    ready = json.loads(process.stdout.readline())
    assert ready["ok"] and ready["phase"] == "ready"

    def send(payload):
        process.stdin.write(json.dumps(payload, ensure_ascii=False) + "\n")
        process.stdin.flush()
        return json.loads(process.stdout.readline())

    prepared = send({"id": "prepare", "type": "prepare"})
    assert prepared["ok"] and prepared["metrics"]["cold"] is True

    synthesized = send(
        {
            "id": "synthesize",
            "type": "synthesize",
            "text": "你好 TypeWhale",
            "output": str(output),
            "voiceID": "test-voice",
        }
    )
    assert synthesized["ok"] and synthesized["phase"] == "completed"
    assert synthesized["voiceID"] == "test-voice"
    assert synthesized["metrics"]["audioSeconds"] > 0
    assert synthesized["metrics"]["rtf"] >= 0
    with wave.open(str(output), "rb") as audio:
        assert audio.getnframes() > 0

    malformed = send({"id": "bad", "type": "synthesize", "text": "missing output"})
    assert not malformed["ok"] and "output" in malformed["error"]

    unknown = send(
        {
            "id": "unknown",
            "type": "synthesize",
            "text": "unknown voice",
            "output": str(output),
            "voiceID": "",
        }
    )
    assert not unknown["ok"] and "voiceID" in unknown["error"]

    shutdown = send({"id": "shutdown", "type": "shutdown"})
    assert shutdown["ok"]
    assert process.wait(timeout=5) == 0

    slow = subprocess.Popen(
        [sys.executable, str(worker), "--engine", "fake", "--fake-delay", "10"],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    json.loads(slow.stdout.readline())
    started = time.monotonic()
    slow.terminate()
    slow.wait(timeout=2)
    assert time.monotonic() - started < 2

print("TTSBenchmarkProtocolCheck passed")
