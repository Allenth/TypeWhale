#!/usr/bin/env python3
"""Plan and perform recoverable ZipVoice-only TTS asset cleanup."""

from __future__ import annotations

import argparse
import json
import os
import plistlib
import sys
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterable


RETAINED_MODEL_ID = "zipvoice-distill-int8-zh-en-emilia"
RETAINED_VOICE_IDS = (
    "zipvoice-default",
    "zipvoice-serena",
    "zipvoice-cosy",
    "zipvoice-video-reference",
)
SCHEMA_VERSION = 1


class CleanupSafetyError(RuntimeError):
    pass


def file_sha256(path: Path) -> str:
    return __import__("hashlib").sha256(path.read_bytes()).hexdigest()


def inventory_sha256(root: Path) -> str:
    hasher = __import__("hashlib").sha256()
    root = root.resolve()
    if not root.is_dir():
        raise CleanupSafetyError(f"inventory root is missing: {root}")
    for path in sorted(root.rglob("*"), key=lambda item: item.relative_to(root).as_posix()):
        relative = path.relative_to(root).as_posix()
        if path.is_symlink():
            hasher.update(f"L\0{relative}\0{os.readlink(path)}\0".encode())
        elif path.is_file():
            hasher.update(f"F\0{relative}\0{path.stat().st_size}\0".encode())
            hasher.update(path.read_bytes())
    return hasher.hexdigest()


def _contained(path: Path, root: Path) -> bool:
    try:
        path.relative_to(root)
        return True
    except ValueError:
        return False


def _tree_bytes(path: Path) -> int:
    total = 0
    for current_root, directory_names, file_names in os.walk(path, followlinks=False):
        current = Path(current_root)
        directory_names[:] = [
            name for name in directory_names if not (current / name).is_symlink()
        ]
        for name in file_names:
            candidate = current / name
            if candidate.is_symlink():
                continue
            total += candidate.stat().st_size
    return total


def _validate_retirement_target(
    target: Path,
    approved_root: Path,
    protected_roots: Iterable[Path],
) -> Path:
    if target.is_symlink():
        raise CleanupSafetyError(f"symlink is not allowed: {target}")
    resolved_target = target.resolve()
    resolved_root = approved_root.resolve()
    if resolved_target == resolved_root:
        raise CleanupSafetyError(f"approved root cannot be retired: {resolved_root}")
    if not _contained(resolved_target, resolved_root):
        raise CleanupSafetyError(f"target escapes approved root: {resolved_target}")
    for protected in protected_roots:
        resolved_protected = protected.resolve()
        if (
            _contained(resolved_target, resolved_protected)
            or _contained(resolved_protected, resolved_target)
        ):
            raise CleanupSafetyError(f"target overlaps protected root: {resolved_target}")
    _tree_bytes(resolved_target)
    return resolved_target


def _entry(path: Path, disposition: str, reason: str) -> dict:
    return {
        "path": str(path.resolve()),
        "bytes": _tree_bytes(path),
        "disposition": disposition,
        "reason": reason,
    }


def build_plan(
    models_root: Path,
    runtimes_root: Path,
    protected_roots: Iterable[Path],
) -> dict:
    models_root = models_root.resolve()
    runtimes_root = runtimes_root.resolve()
    protected = tuple(Path(item).resolve() for item in protected_roots)
    entries: list[dict] = []

    if models_root.is_dir():
        for child in sorted(models_root.iterdir(), key=lambda item: item.name):
            if child.is_symlink():
                raise CleanupSafetyError(f"symlink is not allowed: {child}")
            if not child.is_dir():
                continue
            if child.name == ".staging":
                for staged in sorted(child.iterdir(), key=lambda item: item.name):
                    if not staged.is_dir():
                        continue
                    target = _validate_retirement_target(staged, models_root, protected)
                    entries.append(_entry(target, "retire", "incomplete-staging"))
                continue
            target = child.resolve()
            if child.name == RETAINED_MODEL_ID:
                entries.append(_entry(target, "retain", "sole-qualified-model"))
            else:
                target = _validate_retirement_target(child, models_root, protected)
                entries.append(_entry(target, "retire", "retired-tts-model"))

    if runtimes_root.is_dir():
        for child in sorted(runtimes_root.iterdir(), key=lambda item: item.name):
            if not child.is_dir():
                continue
            target = _validate_retirement_target(child, runtimes_root, protected)
            entries.append(_entry(target, "retire", "retired-model-exclusive-runtime"))

    entries.sort(key=lambda item: item["path"])
    return {
        "schemaVersion": SCHEMA_VERSION,
        "retainedModelID": RETAINED_MODEL_ID,
        "retainedVoiceIDs": list(RETAINED_VOICE_IDS),
        "modelsRoot": str(models_root),
        "runtimesRoot": str(runtimes_root),
        "protectedRoots": sorted(str(item) for item in protected),
        "entries": entries,
        "reclaimableBytes": sum(
            item["bytes"] for item in entries if item["disposition"] == "retire"
        ),
    }


def validate_verification_record(record: dict | None) -> bool:
    try:
        if not (
            isinstance(record, dict)
            and record.get("schemaVersion") == SCHEMA_VERSION
            and record.get("cleanupAuthorized") is True
            and record.get("modelID") == RETAINED_MODEL_ID
            and tuple(record.get("voiceIDs", ())) == RETAINED_VOICE_IDS
            and isinstance(record.get("build"), str)
            and record["build"]
            and isinstance(record.get("version"), str)
            and record["version"]
        ):
            return False
        checks = record.get("checks")
        required_checks = {
            "automatedTests",
            "installedPlayback",
            "openClawBoundary",
            "signatureValid",
            "packageResidueFree",
        }
        if not isinstance(checks, dict) or any(
            checks.get(key) is not True for key in required_checks
        ):
            return False

        app = Path(record["installedAppPath"]).resolve()
        info = plistlib.loads((app / "Contents" / "Info.plist").read_bytes())
        if (
            str(info.get("CFBundleVersion")) != record["build"]
            or str(info.get("CFBundleShortVersionString")) != record["version"]
        ):
            return False
        installed_worker = app / "Contents" / "Resources" / "tts_benchmark_worker.py"
        source_worker = Path(record["sourceWorkerPath"]).resolve()
        expected_worker_hash = record["workerSHA256"]
        if (
            file_sha256(installed_worker) != expected_worker_hash
            or file_sha256(source_worker) != expected_worker_hash
        ):
            return False

        model = Path(record["modelPath"]).resolve()
        if model.name != RETAINED_MODEL_ID:
            return False
        if inventory_sha256(model) != record["modelInventorySHA256"]:
            return False

        qualification = json.loads(
            Path(record["qualificationPath"]).resolve().read_text()
        )
        if (
            qualification.get("modelID") != RETAINED_MODEL_ID
            or qualification.get("fingerprint")
            != "zipvoice-distill-int8-reference-voices-v2"
            or any(
                qualification.get("voices", {}).get(voice) != "passed"
                for voice in RETAINED_VOICE_IDS
            )
        ):
            return False
        protected_hashes = record.get("protectedInventorySHA256")
        if not isinstance(protected_hashes, dict) or not protected_hashes:
            return False
        return all(
            inventory_sha256(Path(path)) == digest
            for path, digest in protected_hashes.items()
        )
    except (KeyError, OSError, ValueError, TypeError, CleanupSafetyError):
        return False


def execute_to_trash(
    plan: dict,
    trash_root: Path,
    verification_record: dict | None,
) -> dict:
    if not validate_verification_record(verification_record):
        return {
            "schemaVersion": SCHEMA_VERSION,
            "executed": False,
            "reason": "verification-required",
            "entries": [],
            "reclaimedBytes": 0,
        }

    models_root = Path(plan["modelsRoot"]).resolve()
    runtimes_root = Path(plan["runtimesRoot"]).resolve()
    protected = [Path(item).resolve() for item in plan.get("protectedRoots", [])]
    trash_root = trash_root.expanduser().resolve()
    trash_root.mkdir(parents=True, exist_ok=True)
    moved: list[dict] = []

    for item in plan["entries"]:
        if item["disposition"] != "retire":
            continue
        target = Path(item["path"])
        if not target.exists():
            raise CleanupSafetyError(f"planned target is missing: {target}")
        approved_root = (
            models_root if _contained(target.resolve(), models_root) else runtimes_root
        )
        resolved = _validate_retirement_target(target, approved_root, protected)
        current_bytes = _tree_bytes(resolved)
        if current_bytes != item["bytes"]:
            raise CleanupSafetyError(f"planned byte count changed: {resolved}")
        destination = trash_root / (
            f"TypeWhale-TTS-{resolved.name}-{uuid.uuid4().hex[:12]}"
        )
        resolved.rename(destination)
        moved.append(
            {
                "path": str(resolved),
                "trashPath": str(destination),
                "bytes": current_bytes,
                "reason": item["reason"],
            }
        )

    return {
        "schemaVersion": SCHEMA_VERSION,
        "executed": True,
        "executedAt": datetime.now(timezone.utc).isoformat(),
        "build": verification_record["build"],
        "entries": moved,
        "reclaimedBytes": sum(item["bytes"] for item in moved),
        "recoverability": "macOS Trash",
    }


def _write_json(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.{uuid.uuid4().hex}.tmp")
    temporary.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    )
    temporary.replace(path)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--models-root", type=Path, required=True)
    parser.add_argument("--runtimes-root", type=Path, required=True)
    parser.add_argument("--protected-root", type=Path, action="append", default=[])
    parser.add_argument("--plan-output", type=Path)
    parser.add_argument("--verification-record", type=Path)
    parser.add_argument("--report-output", type=Path)
    parser.add_argument("--trash-root", type=Path, default=Path.home() / ".Trash")
    parser.add_argument(
        "--mode",
        choices=("plan", "execute-to-trash"),
        default="plan",
    )
    return parser.parse_args()


def main() -> int:
    arguments = parse_args()
    plan = build_plan(
        arguments.models_root,
        arguments.runtimes_root,
        arguments.protected_root,
    )
    if arguments.plan_output:
        _write_json(arguments.plan_output, plan)
    if arguments.mode == "plan":
        print(json.dumps(plan, ensure_ascii=False, sort_keys=True))
        return 0

    verification = None
    if arguments.verification_record and arguments.verification_record.is_file():
        verification = json.loads(arguments.verification_record.read_text())
    report = execute_to_trash(plan, arguments.trash_root, verification)
    if arguments.report_output:
        _write_json(arguments.report_output, report)
    print(json.dumps(report, ensure_ascii=False, sort_keys=True))
    return 0 if report["executed"] else 2


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except CleanupSafetyError as error:
        print(f"cleanup refused: {error}", file=sys.stderr)
        raise SystemExit(3)
