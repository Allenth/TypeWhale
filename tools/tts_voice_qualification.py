#!/usr/bin/env python3
"""Qualify every bundled preset voice with offline Chinese, English and mixed text."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import struct
import subprocess
import tempfile
import time
import wave
from pathlib import Path


SAMPLES = {
    "zh-short-v1": "今天阳光很好，我们一起测试本地朗读的清晰度和自然度。",
    "en-short-v1": "TypeWhale reads this English sentence clearly and naturally.",
    "mixed-v1": "TypeWhale 本地朗读测试，version two runs fast and stays private.",
}
ZIPVOICE_SAMPLES = {
    **SAMPLES,
    "zh-long-v1": (
        "2026年7月28日上午9点30分，TypeWhale 将读取一段包含数字、日期、"
        "英文缩写和标点的长文本。我们先比较启动速度、声音自然度和稳定性，"
        "再观察连续朗读是否完整。"
    ),
}
QWEN_VOICES = [
    "ryan", "aiden", "ono-anna", "sohee", "eric", "dylan", "serena",
    "vivian", "uncle-fu",
]
KOKORO_VOICES = [
    "af_maple", "af_sol", "bf_vale",
    "zf_001", "zf_002", "zf_003", "zf_004", "zf_005", "zf_006", "zf_007",
    "zf_008", "zf_017", "zf_018", "zf_019", "zf_021", "zf_022", "zf_023",
    "zf_024", "zf_026", "zf_027", "zf_028", "zf_032", "zf_036", "zf_038",
    "zf_039", "zf_040", "zf_042", "zf_043", "zf_044", "zf_046", "zf_047",
    "zf_048", "zf_049", "zf_051", "zf_059", "zf_060", "zf_067", "zf_070",
    "zf_071", "zf_072", "zf_073", "zf_074", "zf_075", "zf_076", "zf_077",
    "zf_078", "zf_079", "zf_083", "zf_084", "zf_085", "zf_086", "zf_087",
    "zf_088", "zf_090", "zf_092", "zf_093", "zf_094", "zf_099", "zm_009",
    "zm_010", "zm_011", "zm_012", "zm_013", "zm_014", "zm_015", "zm_016",
    "zm_020", "zm_025", "zm_029", "zm_030", "zm_031", "zm_033", "zm_034",
    "zm_035", "zm_037", "zm_041", "zm_045", "zm_050", "zm_052", "zm_053",
    "zm_054", "zm_055", "zm_056", "zm_057", "zm_058", "zm_061", "zm_062",
    "zm_063", "zm_064", "zm_065", "zm_066", "zm_068", "zm_069", "zm_080",
    "zm_081", "zm_082", "zm_089", "zm_091", "zm_095", "zm_096", "zm_097",
    "zm_098", "zm_100",
]
MODELS = {
    "qwen3-tts-06b-coreml": ("qwen3-tts-coreml-0.6b-v1", QWEN_VOICES, "0.6b"),
    "qwen3-tts-17b-coreml": ("qwen3-tts-coreml-1.7b-v1", QWEN_VOICES, "1.7b"),
    "kokoro-int8-multi-lang-v1_1": (
        "sherpa-kokoro-int8-v1.1-voice-v1", KOKORO_VOICES, "kokoro"
    ),
    "zipvoice-distill-int8-zh-en-emilia": (
        "zipvoice-distill-int8-reference-voices-v2",
        [
            "zipvoice-default",
            "zipvoice-serena",
            "zipvoice-cosy",
            "zipvoice-video-reference",
        ],
        "zipvoice",
    ),
}


class Worker:
    def __init__(self, command: list[str]):
        environment = os.environ.copy()
        environment.update({"HF_HUB_OFFLINE": "1", "TRANSFORMERS_OFFLINE": "1", "NO_PROXY": "*"})
        self.process = subprocess.Popen(
            command, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, text=True, bufsize=1, env=environment,
        )
        self.sequence = 0
        ready = self._read()
        if not ready.get("ok"):
            raise RuntimeError(ready.get("error", "worker failed to start"))

    def request(self, kind: str, **values):
        self.sequence += 1
        request_id = str(self.sequence)
        payload = {"id": request_id, "type": kind, **values}
        assert self.process.stdin
        self.process.stdin.write(json.dumps(payload, ensure_ascii=False) + "\n")
        self.process.stdin.flush()
        response = self._read()
        if response.get("id") != request_id or not response.get("ok"):
            raise RuntimeError(response.get("error", f"invalid worker response: {response}"))
        return response

    def close(self):
        try:
            self.request("shutdown")
        except (BrokenPipeError, RuntimeError):
            pass
        finally:
            self.process.terminate()
            self.process.wait(timeout=5)

    def _read(self):
        assert self.process.stdout
        line = self.process.stdout.readline()
        if not line:
            assert self.process.stderr
            raise RuntimeError(self.process.stderr.read() or "worker exited")
        return json.loads(line)


def inspect_wave(path: Path) -> dict:
    with wave.open(str(path), "rb") as source:
        if source.getsampwidth() != 2:
            raise ValueError("not 16-bit PCM")
        channels, rate, frames = source.getnchannels(), source.getframerate(), source.getnframes()
        raw = source.readframes(frames)
    values = struct.unpack(f"<{len(raw) // 2}h", raw)
    if not values or rate <= 0 or channels <= 0:
        raise ValueError("empty WAV")
    rms = math.sqrt(sum(value * value for value in values) / len(values)) / 32768
    clipped = sum(abs(value) >= 32767 for value in values) / len(values)
    duration = frames / rate
    if duration < 0.08 or rms < 0.0001:
        raise ValueError(f"silent/short WAV duration={duration:.3f} rms={rms:.6f}")
    if clipped > 0.02:
        raise ValueError(f"clipped WAV ratio={clipped:.4f}")
    return {
        "durationSeconds": round(duration, 4),
        "rms": round(rms, 6),
        "clippedRatio": round(clipped, 6),
        "pcmSHA256": hashlib.sha256(raw).hexdigest(),
    }


def command_for(model_id: str, variant: str, args) -> list[str]:
    pack = args.models_root / model_id
    if variant == "kokoro":
        return [
            str(args.python), str(args.python_worker), "--engine", "sherpa-kokoro",
            "--pack", str(pack),
        ]
    if variant == "zipvoice":
        return [
            str(args.python), str(args.python_worker), "--engine", "sherpa-zipvoice",
            "--pack", str(pack),
        ]
    return [str(args.qwen_worker), "--model-root", str(pack), "--variant", variant]


def qualify(model_id: str, args) -> dict:
    fingerprint, voices, variant = MODELS[model_id]
    samples = ZIPVOICE_SAMPLES if variant == "zipvoice" else SAMPLES
    worker = Worker(command_for(model_id, variant, args))
    results, statuses = {}, {}
    try:
        worker.request("prepare")
        with tempfile.TemporaryDirectory(prefix=f"typewhale-voice-{model_id}-") as directory:
            root = Path(directory)
            for index, voice_id in enumerate(voices, 1):
                voice_results = {}
                failure = None
                for sample_id, text in samples.items():
                    output = root / f"{voice_id}-{sample_id}.wav"
                    try:
                        response = worker.request(
                            "synthesize", text=text, output=str(output), voiceID=voice_id
                        )
                        if response.get("voiceID") != voice_id:
                            raise ValueError("worker returned a different voiceID")
                        voice_results[sample_id] = {
                            **inspect_wave(output),
                            "metrics": response.get("metrics", {}),
                        }
                    except Exception as error:
                        failure = str(error)
                        break
                stability_results = []
                if failure is None and variant == "zipvoice":
                    for repeat in range(1, 6):
                        output = root / f"{voice_id}-mixed-repeat-{repeat}.wav"
                        try:
                            response = worker.request(
                                "synthesize",
                                text=samples["mixed-v1"],
                                output=str(output),
                                voiceID=voice_id,
                            )
                            stability_results.append({
                                "repeat": repeat,
                                **inspect_wave(output),
                                "metrics": response.get("metrics", {}),
                            })
                        except Exception as error:
                            failure = f"stability repeat {repeat}: {error}"
                            break
                statuses[voice_id] = "passed" if failure is None else "failed"
                results[voice_id] = {
                    "samples": voice_results,
                    "stability": stability_results,
                    "error": failure,
                }
                print(
                    f"[{model_id}] {index}/{len(voices)} {voice_id}: {statuses[voice_id]}",
                    flush=True,
                )
    finally:
        worker.close()

    # Exact duplicate PCM for the same sample is treated as a broken voice mapping.
    for sample_id in samples:
        hashes = {}
        for voice_id, result in results.items():
            sample = result["samples"].get(sample_id)
            if statuses[voice_id] == "passed" and sample:
                hashes.setdefault(sample["pcmSHA256"], []).append(voice_id)
        for duplicate_ids in hashes.values():
            if len(duplicate_ids) > 1:
                for voice_id in duplicate_ids:
                    statuses[voice_id] = "failed"
                    results[voice_id]["error"] = f"identical audio mapping: {', '.join(duplicate_ids)}"

    return {
        "schemaVersion": 1,
        "generatedAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "modelID": model_id,
        "fingerprint": fingerprint,
        "suite": list(samples),
        "voices": statuses,
        "results": results,
    }


def atomic_write(path: Path, payload: dict):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(".json.tmp")
    temporary.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n")
    os.replace(temporary, path)


def parse_args():
    home = Path.home()
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", action="append", choices=MODELS)
    parser.add_argument(
        "--models-root", type=Path,
        default=home / "Library/Application Support/TypeWhale Pro/Models/tts",
    )
    parser.add_argument(
        "--output-root", type=Path,
        default=home / "Library/Application Support/TypeWhale Pro/TTSLab/VoiceQualifications",
    )
    parser.add_argument("--python", type=Path, default=Path("/usr/local/bin/python3"))
    parser.add_argument(
        "--python-worker", type=Path,
        default=Path("native/Resources/tts_benchmark_worker.py"),
    )
    parser.add_argument(
        "--qwen-worker", type=Path,
        default=Path("native/Helpers/TTSKitBridge/.build/arm64-apple-macosx/release/typewhale-ttskit-worker"),
    )
    return parser.parse_args()


def main():
    args = parse_args()
    model_ids = args.model or list(MODELS)
    for model_id in model_ids:
        evidence = qualify(model_id, args)
        atomic_write(args.output_root / f"{model_id}.json", evidence)
        passed = sum(status == "passed" for status in evidence["voices"].values())
        print(f"[{model_id}] qualified {passed}/{len(evidence['voices'])}", flush=True)


if __name__ == "__main__":
    main()
