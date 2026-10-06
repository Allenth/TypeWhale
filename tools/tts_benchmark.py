#!/usr/bin/env python3
"""Run repeatable local TTS benchmarks through the TypeWhale JSONL worker."""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import time
import uuid
from pathlib import Path


ENGINE_BY_MODEL = {
    "sherpa-vits-melo-tts-zh_en": "sherpa-vits",
    "kokoro-int8-multi-lang-v1_1": "sherpa-kokoro",
    "zipvoice-distill-int8-zh-en-emilia": "sherpa-zipvoice",
}


def worker_python() -> str:
    for candidate in ("/usr/local/bin/python3", sys.executable):
        completed = subprocess.run(
            [candidate, "-c", "import sherpa_onnx"],
            capture_output=True,
        )
        if completed.returncode == 0:
            return candidate
    return sys.executable


def read_rss(process: subprocess.Popen) -> int:
    completed = subprocess.run(
        ["ps", "-o", "rss=", "-p", str(process.pid)],
        capture_output=True,
        text=True,
    )
    try:
        return int(completed.stdout.strip()) * 1024
    except ValueError:
        return 0


def request(process: subprocess.Popen, payload: dict) -> dict:
    process.stdin.write(json.dumps(payload, ensure_ascii=False) + "\n")
    process.stdin.flush()
    line = process.stdout.readline()
    if not line:
        error = process.stderr.read()
        raise RuntimeError(error or "worker closed stdout")
    return json.loads(line)


def benchmark_model(
    model_id: str,
    model_root: Path,
    corpus: list[dict],
    runs: int,
    output_root: Path,
) -> list[dict]:
    engine = ENGINE_BY_MODEL.get(model_id)
    if not engine:
        return [{"modelID": model_id, "status": "unsupported-runtime"}]
    worker = Path(__file__).resolve().parents[1] / "native/Resources/tts_benchmark_worker.py"
    process = subprocess.Popen(
        [
            worker_python(),
            str(worker),
            "--engine",
            engine,
            "--pack",
            str(model_root / model_id),
        ],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        env={**os.environ, "HF_HUB_OFFLINE": "1", "TRANSFORMERS_OFFLINE": "1"},
    )
    ready = json.loads(process.stdout.readline())
    if not ready.get("ok"):
        raise RuntimeError(f"{model_id} did not become ready")
    prepare = request(process, {"id": str(uuid.uuid4()), "type": "prepare"})
    if not prepare.get("ok"):
        process.terminate()
        return [{"modelID": model_id, "status": "failed", "error": prepare.get("error", "")}]
    rows = []
    peak_rss = read_rss(process)
    for run_index in range(runs):
        for sample in corpus:
            output = output_root / model_id / f"{sample['id']}-{run_index + 1}.wav"
            response = request(
                process,
                {
                    "id": str(uuid.uuid4()),
                    "type": "synthesize",
                    "text": sample["text"],
                    "output": str(output),
                },
            )
            peak_rss = max(peak_rss, read_rss(process))
            rows.append(
                {
                    "modelID": model_id,
                    "corpusID": sample["id"],
                    "run": run_index + 1,
                    "status": "passed" if response.get("ok") else "failed",
                    "prepare": prepare.get("metrics", {}),
                    "metrics": {**response.get("metrics", {}), "peakRSSBytes": peak_rss},
                    "output": str(output),
                    "error": response.get("error"),
                }
            )
            if not response.get("ok"):
                break
    request(process, {"id": str(uuid.uuid4()), "type": "shutdown"})
    process.wait(timeout=10)
    return rows


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--all", action="store_true")
    parser.add_argument("--model", action="append", default=[])
    parser.add_argument("--runs", type=int, default=3)
    parser.add_argument("--corpus", required=True, type=Path)
    parser.add_argument(
        "--models-root",
        type=Path,
        default=Path.home() / "Library/Application Support/TypeWhale Pro/Models/tts",
    )
    parser.add_argument(
        "--output-root",
        type=Path,
        default=Path.home() / "Library/Application Support/TypeWhale Pro/TTSLab/Outputs",
    )
    parser.add_argument("--results", type=Path)
    return parser.parse_args()


def main() -> int:
    arguments = parse_arguments()
    corpus = json.loads(arguments.corpus.read_text(encoding="utf-8"))
    models = sorted(ENGINE_BY_MODEL) if arguments.all else arguments.model
    if not models:
        raise SystemExit("pass --all or --model")
    started = time.time()
    rows = []
    for model in models:
        rows.extend(
            benchmark_model(
                model,
                arguments.models_root,
                corpus,
                arguments.runs,
                arguments.output_root,
            )
        )
    payload = {"generatedAtUnix": started, "results": rows}
    text = json.dumps(payload, ensure_ascii=False, indent=2) + "\n"
    if arguments.results:
        arguments.results.parent.mkdir(parents=True, exist_ok=True)
        arguments.results.write_text(text, encoding="utf-8")
    else:
        print(text, end="")
    return 0 if all(row["status"] == "passed" for row in rows) else 1


if __name__ == "__main__":
    raise SystemExit(main())
