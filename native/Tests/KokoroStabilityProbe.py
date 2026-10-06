#!/usr/bin/env python3
"""Deterministic repeated-process Kokoro stability probe."""

from __future__ import annotations

import argparse
import json
import math
import os
import platform
import subprocess
import sys
import tempfile
import wave
from pathlib import Path


SAMPLES = (
    "你好，欢迎使用 TypeWhale 本地朗读测试。",
    "The quick brown fox jumps over the lazy dog.",
    "TypeWhale 使用 Core ML、GitHub 和 ChatGPT 完成本地测试。",
)


def wav_metrics(path: Path) -> dict:
    with wave.open(str(path), "rb") as source:
        frames = source.readframes(source.getnframes())
        width = source.getsampwidth()
        channels = source.getnchannels()
        frame_count = source.getnframes()
    if width != 2:
        raise RuntimeError(f"unexpected sample width: {width}")
    values = [
        int.from_bytes(frames[index : index + 2], "little", signed=True) / 32768.0
        for index in range(0, len(frames), 2)
    ]
    finite = all(math.isfinite(value) for value in values)
    peak = max((abs(value) for value in values), default=0.0)
    rms = math.sqrt(sum(value * value for value in values) / max(1, len(values)))
    return {
        "finite": finite,
        "silent": peak < 0.0001,
        "peak": peak,
        "rms": rms,
        "frames": frame_count,
        "channels": channels,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--python", type=Path, required=True)
    parser.add_argument("--worker", type=Path, required=True)
    parser.add_argument("--pack", type=Path, required=True)
    parser.add_argument("--runs", type=int, default=12)
    parser.add_argument("--voice-id", type=int, default=0)
    parser.add_argument("--sample-id", type=int, choices=range(len(SAMPLES)))
    parser.add_argument("--report", type=Path)
    arguments = parser.parse_args()

    environment = os.environ.copy()
    environment.update(
        {
            "HF_HUB_OFFLINE": "1",
            "TRANSFORMERS_OFFLINE": "1",
            "NO_PROXY": "*",
        }
    )
    process = subprocess.Popen(
        [
            str(arguments.python),
            str(arguments.worker),
            "--engine",
            "sherpa-kokoro",
            "--pack",
            str(arguments.pack),
        ],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        env=environment,
    )
    assert process.stdin and process.stdout and process.stderr
    ready = json.loads(process.stdout.readline())
    if not ready.get("ok"):
        raise RuntimeError(f"worker did not start: {ready}")

    def send(payload: dict) -> dict:
        process.stdin.write(json.dumps(payload, ensure_ascii=False) + "\n")
        process.stdin.flush()
        line = process.stdout.readline()
        if not line:
            raise RuntimeError(process.stderr.read() or "worker ended")
        return json.loads(line)

    prepared = send({"id": "prepare", "type": "prepare"})
    results = [{"phase": "prepare", "response": prepared}]
    failures = 0
    with tempfile.TemporaryDirectory(prefix="typewhale-kokoro-probe-") as temporary:
        root = Path(temporary)
        for index in range(arguments.runs):
            sample_id = (
                arguments.sample_id
                if arguments.sample_id is not None
                else index % len(SAMPLES)
            )
            output = root / f"run-{index + 1:02d}.wav"
            response = send(
                {
                    "id": f"run-{index + 1:02d}",
                    "type": "synthesize",
                    "text": SAMPLES[sample_id],
                    "speakerID": arguments.voice_id,
                    "output": str(output),
                }
            )
            row = {
                "iteration": index + 1,
                "sampleID": sample_id,
                "voiceID": arguments.voice_id,
                "response": response,
            }
            if response.get("ok") and output.exists():
                row["validation"] = wav_metrics(output)
                if (
                    response.get("speakerID") != arguments.voice_id
                    or not row["validation"]["finite"]
                    or row["validation"]["silent"]
                ):
                    failures += 1
            else:
                failures += 1
            results.append(row)

    try:
        send({"id": "shutdown", "type": "shutdown"})
    finally:
        process.wait(timeout=5)

    report = {
        "runtime": str(arguments.python),
        "runtimeVersion": platform.python_version(),
        "offline": True,
        "model": str(arguments.pack),
        "runs": arguments.runs,
        "failures": failures,
        "results": results,
    }
    rendered = json.dumps(report, ensure_ascii=False, indent=2)
    if arguments.report:
        arguments.report.parent.mkdir(parents=True, exist_ok=True)
        arguments.report.write_text(rendered + "\n", encoding="utf-8")
    print(rendered)
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
