#!/usr/bin/env python3
"""Run the fixed TypeWhale TTS corpus and create anonymized listening files."""

from __future__ import annotations

import argparse
import json
import os
import secrets
import subprocess
from datetime import datetime
from pathlib import Path


SAMPLES = {
    "zh-short-v1": "你好，欢迎使用 TypeWhale 本地朗读测试。",
    "en-short-v1": "The quick brown fox jumps over the lazy dog.",
    "mixed-v1": "TypeWhale 使用 Core ML、GitHub 和 ChatGPT 完成本地测试。",
    "zh-long-v1": (
        "2026年7月28日上午9点30分，TypeWhale 将读取一段包含数字、日期、英文缩写和标点的长文本。"
        "我们先比较启动速度、首段声音出现的时间与自然度，再观察连续朗读时是否稳定，最后记录内存占用，"
        "在体验与资源之间找到平衡。"
    ),
}


def labels(count: int) -> list[str]:
    return [chr(ord("A") + index) for index in range(count)]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", type=Path, required=True)
    parser.add_argument("--model-root", type=Path, required=True)
    parser.add_argument("--runtime-root", type=Path, required=True)
    parser.add_argument("--output-root", type=Path, required=True)
    arguments = parser.parse_args()

    repo = arguments.repo.resolve()
    model_root = arguments.model_root.expanduser().resolve()
    runtime_root = arguments.runtime_root.expanduser().resolve()
    run_root = arguments.output_root.expanduser().resolve() / datetime.now().strftime(
        "%Y%m%d-%H%M%S"
    )
    audio_root = run_root / "audio"
    audio_root.mkdir(parents=True)
    python_worker = repo / "native/Resources/tts_benchmark_worker.py"
    qwen_worker = (
        repo
        / "native/Helpers/TTSKitBridge/.build/release/typewhale-ttskit-worker"
    )
    source = runtime_root / "cosyvoice3-main-py310/src/CosyVoice"
    candidates = [
        ("sherpa-vits-melo-tts-zh_en", Path("/usr/local/bin/python3"), [
            str(python_worker), "--engine", "sherpa-vits", "--pack",
            str(model_root / "sherpa-vits-melo-tts-zh_en"),
        ], 0, {}),
        ("zipvoice-distill-int8-zh-en-emilia", Path("/usr/local/bin/python3"), [
            str(python_worker), "--engine", "sherpa-zipvoice", "--pack",
            str(model_root / "zipvoice-distill-int8-zh-en-emilia"),
        ], 0, {}),
        ("kokoro-int8-multi-lang-v1_1", Path("/usr/local/bin/python3"), [
            str(python_worker), "--engine", "sherpa-kokoro", "--pack",
            str(model_root / "kokoro-int8-multi-lang-v1_1"),
        ], 50, {}),
        ("qwen3-tts-06b-coreml", qwen_worker, [
            "--model-root", str(model_root / "qwen3-tts-06b-coreml"),
            "--variant", "0.6b",
        ], 0, {}),
        ("qwen3-tts-17b-coreml", qwen_worker, [
            "--model-root", str(model_root / "qwen3-tts-17b-coreml"),
            "--variant", "1.7b",
        ], 0, {}),
        ("moss-tts-local-transformer-v1.5", runtime_root / "moss-python-mps-system-v1/bin/python3", [
            str(python_worker), "--engine", "moss-python-mps", "--pack",
            str(model_root / "moss-tts-local-transformer-v1.5"),
        ], 0, {}),
        ("voxcpm2", runtime_root / "voxcpm2-2.0.3-py312/bin/python3", [
            str(python_worker), "--engine", "voxcpm2-python-mps", "--pack",
            str(model_root / "voxcpm2"),
        ], 0, {}),
        ("fun-cosyvoice3-0.5b-2512", runtime_root / "cosyvoice3-main-py310/bin/python3", [
            str(python_worker), "--engine", "cosyvoice3-python-cpu", "--pack",
            str(model_root / "fun-cosyvoice3-0.5b-2512"),
        ], 0, {
            "TYPEWHALE_COSYVOICE_SOURCE": str(source),
            "PYTHONPATH": f"{source}:{source / 'third_party/Matcha-TTS'}",
        }),
    ]
    secrets.SystemRandom().shuffle(candidates)
    mapping = {}
    reports = []
    environment = os.environ.copy()
    environment.update({
        "HF_HUB_OFFLINE": "1",
        "TRANSFORMERS_OFFLINE": "1",
        "NO_PROXY": "*",
    })
    for label, (model_id, executable, command, speaker_id, extra_env) in zip(
        labels(len(candidates)), candidates
    ):
        mapping[label] = model_id
        process = subprocess.Popen(
            [str(executable), *command],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            env=environment | extra_env,
        )
        assert process.stdin and process.stdout
        ready = json.loads(process.stdout.readline())
        rows = [{"phase": "ready", "response": ready}]

        def send(payload: dict) -> dict:
            process.stdin.write(json.dumps(payload, ensure_ascii=False) + "\n")
            process.stdin.flush()
            return json.loads(process.stdout.readline())

        rows.append({"phase": "prepare", "response": send({"id": "prepare", "type": "prepare"})})
        for sample_id, text in SAMPLES.items():
            output = audio_root / f"{label}-{sample_id}.wav"
            response = send({
                "id": sample_id,
                "type": "synthesize",
                "text": text,
                "speakerID": speaker_id,
                "output": str(output),
            })
            rows.append({"sampleID": sample_id, "response": response})
        send({"id": "shutdown", "type": "shutdown"})
        process.wait(timeout=10)
        reports.append({"label": label, "modelID": model_id, "results": rows})
        print(f"{label}: {model_id}", flush=True)

    (run_root / "mapping.json").write_text(
        json.dumps(mapping, ensure_ascii=False, indent=2) + "\n"
    )
    (run_root / "metrics.json").write_text(
        json.dumps(reports, ensure_ascii=False, indent=2) + "\n"
    )
    print(run_root)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
