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
    "paraformer-hotword-contextual",
    "paraformer-zh",
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


def evaluate_case(
    *,
    case: dict[str, Any],
    provider: str,
    manifest_path: Path,
    model_dir: str,
    hotwords: list[str],
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
        status = "error"
        error = (
            f"provider_runtime_not_wired: {provider}; "
            "install FunASR runtime wiring before running real model evaluation"
        )

    hits, missing = hotword_hits(raw_text, required_hotwords)
    elapsed_ms = max(0, int((time.monotonic() - started) * 1000))

    return {
        "caseId": case_id,
        "provider": provider,
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
            )
            handle.write(json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
