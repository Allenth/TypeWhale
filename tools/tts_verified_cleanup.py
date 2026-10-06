#!/usr/bin/env python3
"""Move only hash-verified, qualified legacy TTS assets to macOS Trash."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import time
from pathlib import Path


class CleanupRejected(RuntimeError):
    pass


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def contained(path: Path, root: Path) -> bool:
    try:
        path.resolve(strict=True).relative_to(root.resolve(strict=True))
        return True
    except (FileNotFoundError, ValueError):
        return False


def validate_entry(entry: dict, source_root: Path, target_root: Path) -> dict:
    source = Path(entry["source"]).expanduser()
    target = Path(entry["target"]).expanduser()
    model = Path(entry["modelDirectory"]).expanduser()
    if "Reader Demo" in str(source):
        raise CleanupRejected("Reader Demo paths are protected")
    if source == source_root or not contained(source, source_root):
        raise CleanupRejected(f"source escapes or is too broad: {source}")
    if not contained(target, target_root) or not contained(model, target_root):
        raise CleanupRejected("target/model escapes managed TTS root")
    manifest = model / "typewhale-model.json"
    if not manifest.is_file():
        raise CleanupRejected("qualified manifest missing")
    qualification = json.loads(manifest.read_text(encoding="utf-8")).get("qualification", {})
    if qualification.get("status") != "passed":
        raise CleanupRejected("model qualification is not passed")
    if source.is_symlink() or target.is_symlink():
        raise CleanupRejected("symlink cleanup targets are forbidden")

    if source.is_file():
        if not target.is_file() or sha256(source) != sha256(target):
            raise CleanupRejected("source/target hash mismatch")
        bytes_count = source.stat().st_size
        files_count = 1
    elif source.is_dir():
        bytes_count = 0
        files_count = 0
        for source_file in source.rglob("*"):
            if source_file.is_symlink():
                raise CleanupRejected("symlink inside source is forbidden")
            if not source_file.is_file():
                continue
            relative = source_file.relative_to(source)
            target_file = target / relative
            if not target_file.is_file() or sha256(source_file) != sha256(target_file):
                raise CleanupRejected(f"source/target hash mismatch: {relative}")
            bytes_count += source_file.stat().st_size
            files_count += 1
    else:
        raise CleanupRejected("source missing")
    return {
        "modelID": entry["modelID"],
        "source": str(source),
        "target": str(target),
        "bytes": bytes_count,
        "files": files_count,
        "recoverability": "macOS Trash",
    }


def unique_trash_path(trash: Path, source: Path) -> Path:
    candidate = trash / source.name
    if not candidate.exists():
        return candidate
    return trash / f"{source.name}-{int(time.time())}"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--plan", required=True)
    parser.add_argument("--source-root", required=True)
    parser.add_argument("--target-root", required=True)
    parser.add_argument("--report", required=True)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--dry-run", action="store_true")
    mode.add_argument("--execute", action="store_true")
    args = parser.parse_args()

    plan = json.loads(Path(args.plan).read_text(encoding="utf-8"))
    source_root = Path(args.source_root).expanduser()
    target_root = Path(args.target_root).expanduser()
    if "Reader Demo" in str(source_root) or source_root == Path.home():
        raise CleanupRejected("unsafe source root")
    validated = [
        validate_entry(entry, source_root=source_root, target_root=target_root)
        for entry in plan["entries"]
    ]
    if args.execute:
        trash = Path.home() / ".Trash"
        trash.mkdir(exist_ok=True)
        for item in validated:
            source = Path(item["source"])
            destination = unique_trash_path(trash, source)
            shutil.move(str(source), str(destination))
            item["trashPath"] = str(destination)
            item["state"] = "moved-to-trash"
    else:
        for item in validated:
            item["state"] = "verified-dry-run"
    report = {
        "executed": bool(args.execute),
        "totalBytes": sum(item["bytes"] for item in validated),
        "entries": validated,
    }
    report_path = Path(args.report)
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
