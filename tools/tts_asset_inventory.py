#!/usr/bin/env python3
"""Create a read-only inventory of local TTS artifacts."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Iterable


def contained(path: Path, root: Path) -> bool:
    try:
        path.resolve(strict=False).relative_to(root.resolve(strict=False))
        return True
    except ValueError:
        return False


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def classify(path: Path) -> str:
    lowered = str(path).lower()
    for name, markers in {
        "qwen3-tts": ("qwen3-tts", "qwen--qwen3-tts"),
        "kokoro": ("kokoro",),
        "zipvoice": ("zipvoice",),
        "vocos": ("vocos",),
        "cosyvoice": ("cosyvoice",),
        "moss-tts": ("moss-tts", "moss_tts"),
        "voxcpm": ("voxcpm",),
        "spark-tts": ("spark-tts",),
        "piper": ("piper",),
        "sherpa-vits": ("sherpa-vits", "vits-melo"),
        "melotts": ("melotts", "melo-tts"),
    }.items():
        if any(marker in lowered for marker in markers):
            return name
    return "other"


def is_relevant(path: Path) -> bool:
    return classify(path) != "other"


def inventory(
    scan_roots: Iterable[Path],
    protected_roots: Iterable[Path],
) -> list[dict[str, object]]:
    protected = [root.resolve(strict=False) for root in protected_roots]
    rows: list[dict[str, object]] = []
    seen: set[str] = set()
    for scan_root in scan_roots:
        if not scan_root.exists():
            continue
        for path in scan_root.rglob("*"):
            if not path.is_file() or not is_relevant(path):
                continue
            path_text = str(path)
            if path_text in seen:
                continue
            seen.add(path_text)
            is_protected = any(contained(path, root) for root in protected)
            rows.append(
                {
                    "path": path_text,
                    "bytes": path.stat().st_size,
                    "sha256": "" if is_protected else sha256(path),
                    "category": classify(path),
                    "protected": is_protected,
                }
            )
    return sorted(rows, key=lambda row: str(row["path"]))


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--scan-root", action="append", default=[], type=Path)
    parser.add_argument("--protected-root", action="append", default=[], type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--json", action="store_true")
    return parser.parse_args()


def main() -> int:
    arguments = parse_arguments()
    rows = inventory(arguments.scan_root, arguments.protected_root)
    payload = json.dumps(rows, ensure_ascii=False, indent=2) + "\n"
    if arguments.output:
        arguments.output.parent.mkdir(parents=True, exist_ok=True)
        arguments.output.write_text(payload, encoding="utf-8")
    if arguments.json or not arguments.output:
        print(payload, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
