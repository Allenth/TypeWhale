#!/usr/bin/env python3
"""Offline evaluation harness for TypeWhale Pro ASR candidates.

The first version intentionally supports a dependency-free dry-run mode so the
manifest, JSONL contract, and later model runners can be tested before Python
FunASR/PyTorch runtime wiring is installed.
"""

from __future__ import annotations

import argparse
import json
import time
from pathlib import Path
from typing import Any


SUPPORTED_PROVIDERS = {
    "dry-run",
    "fun-asr-nano-2512",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run local ASR eval cases and write JSONL results.")
    parser.add_argument("--manifest", required=True, help="Path to pro-hotword-eval-cases.json")
    parser.add_argument("--provider", required=True, choices=sorted(SUPPORTED_PROVIDERS))
    parser.add_argument("--model-dir", default="", help="Provider model directory for non dry-run providers")
    parser.add_argument("--hotwords", default="", help="Optional hotword text file, one term per line")
    parser.add_argument("--output", required=True, help="Output JSONL path")
    return parser.parse_args()


def load_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as handle:
        value = json.load(handle)
    if not isinstance(value, dict):
        raise ValueError(f"Manifest must be a JSON object: {path}")
    return value


def load_hotwords(path_text: str) -> list[str]:
    if not path_text:
        return []
    path = Path(path_text)
    if not path.exists():
        raise FileNotFoundError(f"Hotwords file not found: {path}")
    return [
        line.strip()
        for line in path.read_text(encoding="utf-8").splitlines()
        if line.strip() and not line.strip().startswith("#")
    ]


def resolve_audio_path(manifest_path: Path, audio_path: str | None) -> Path | None:
    if not audio_path:
        return None
    candidate = Path(audio_path)
    if candidate.is_absolute():
        return candidate
    repo_root = manifest_path.parents[2]
    return repo_root / candidate


def hotword_hits(raw_text: str, required_hotwords: list[str]) -> tuple[list[str], list[str]]:
    lower_text = raw_text.lower()
    hits = [term for term in required_hotwords if term.lower() in lower_text]
    missing = [term for term in required_hotwords if term not in hits]
    return hits, missing


def dry_run_text(case: dict[str, Any], audio_exists: bool) -> str:
    if not audio_exists:
        return ""
    return str(case.get("expectedText", ""))


def build_provider_model(provider: str, model_dir: str) -> Any:
    if not model_dir:
        raise ValueError(f"model_dir_required: {provider}")
    from funasr import AutoModel

    common: dict[str, Any] = {
        "model": model_dir,
        "device": "cpu",
        "disable_update": True,
    }
    common["trust_remote_code"] = True
    return AutoModel(**common)


def transcribe_with_provider(
    *,
    model: Any,
    provider: str,
    audio_path: Path,
    hotwords: list[str],
) -> str:
    arguments: dict[str, Any] = {
        "input": [str(audio_path)],
        "cache": {},
        "batch_size": 1,
    }
    arguments.update({"hotwords": hotwords, "language": "中文", "itn": True})

    result = model.generate(**arguments)
    if not isinstance(result, list) or not result or not isinstance(result[0], dict):
        raise ValueError(f"provider_invalid_result: {provider}")
    return str(result[0].get("text", "")).strip()


def evaluate_case(
    *,
    case: dict[str, Any],
    provider: str,
    manifest_path: Path,
    model_dir: str,
    hotwords: list[str],
    model: Any | None = None,
) -> dict[str, Any]:
    started = time.monotonic()
    case_id = str(case.get("id", ""))
    required_hotwords = [str(item) for item in case.get("requiredHotwords", [])]
    audio_path = resolve_audio_path(manifest_path, case.get("audioPath"))
    audio_exists = audio_path is not None and audio_path.exists()

    status = "ok"
    raw_text = ""
    error = ""

    if not audio_exists:
        status = "skipped"
        error = f"audio_missing: {case.get('audioPath') or 'null'}"
    elif provider == "dry-run":
        raw_text = dry_run_text(case, audio_exists=True)
    else:
        try:
            if model is None:
                raise RuntimeError(f"provider_model_not_loaded: {provider}")
            raw_text = transcribe_with_provider(
                model=model,
                provider=provider,
                audio_path=audio_path,
                hotwords=hotwords,
            )
            if not raw_text:
                status = "error"
                error = f"provider_empty_result: {provider}"
        except Exception as exc:
            status = "error"
            error = f"{type(exc).__name__}: {exc}"

    hits, missing = hotword_hits(raw_text, required_hotwords)
    elapsed_ms = max(0, int((time.monotonic() - started) * 1000))

    return {
        "caseId": case_id,
        "provider": provider,
        "engine": "dry-run" if provider == "dry-run" else f"{provider}/funasr-python",
        "status": status,
        "rawText": raw_text,
        "elapsedMs": elapsed_ms,
        "requiredHotwordHits": hits,
        "missingHotwords": missing,
        "error": error,
        "audioPath": str(audio_path) if audio_path is not None else None,
        "modelDir": model_dir or None,
        "hotwordsUsed": hotwords,
    }


def main() -> int:
    args = parse_args()
    manifest_path = Path(args.manifest)
    manifest = load_json(manifest_path)
    cases = manifest.get("cases")
    if not isinstance(cases, list):
        raise ValueError("Manifest field 'cases' must be a list")

    hotwords = load_hotwords(args.hotwords)
    model = None if args.provider == "dry-run" else build_provider_model(args.provider, args.model_dir)
    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)

    with output_path.open("w", encoding="utf-8") as handle:
        for case in cases:
            if not isinstance(case, dict):
                raise ValueError("Each manifest case must be a JSON object")
            row = evaluate_case(
                case=case,
                provider=args.provider,
                manifest_path=manifest_path,
                model_dir=args.model_dir,
                hotwords=hotwords,
                model=model,
            )
            handle.write(json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
