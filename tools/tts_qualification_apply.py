#!/usr/bin/env python3
"""Promote local TTS manifests only after the complete fixed suite succeeds."""

from __future__ import annotations

import argparse
import json
import os
import tempfile
from pathlib import Path


REQUIRED_SAMPLES = {
    "zh-short-v1",
    "en-short-v1",
    "mixed-v1",
    "zh-long-v1",
}
EXPECTED_MODEL_COUNT = 8


class QualificationRejected(RuntimeError):
    pass


def apply_qualification(run_root: Path, model_root: Path) -> int:
    reports = json.loads((run_root / "metrics.json").read_text(encoding="utf-8"))
    if len(reports) != EXPECTED_MODEL_COUNT:
        raise QualificationRejected(
            f"expected {EXPECTED_MODEL_COUNT} models, got {len(reports)}"
        )
    model_ids = [report.get("modelID") for report in reports]
    if len(set(model_ids)) != EXPECTED_MODEL_COUNT or None in model_ids:
        raise QualificationRejected("model IDs must be unique and complete")

    manifests: list[tuple[Path, dict]] = []
    for report in reports:
        completed = {
            row.get("sampleID")
            for row in report.get("results", [])
            if row.get("response", {}).get("ok") is True
            and row.get("response", {}).get("phase") == "completed"
        }
        if completed != REQUIRED_SAMPLES:
            raise QualificationRejected(
                f"{report['modelID']} did not pass the complete fixed suite"
            )
        manifest_path = model_root / report["modelID"] / "typewhale-model.json"
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        if manifest.get("id") != report["modelID"]:
            raise QualificationRejected(f"manifest ID mismatch: {report['modelID']}")
        manifests.append((manifest_path, manifest))

    for manifest_path, manifest in manifests:
        manifest["qualification"] = {
            "status": "passed",
            "evidence": run_root.name,
            "suite": sorted(REQUIRED_SAMPLES),
        }
        if manifest["id"] == "kokoro-int8-multi-lang-v1_1":
            manifest["defaultSpeakerID"] = 50
        _atomic_json_write(manifest_path, manifest)
    return len(manifests)


def _atomic_json_write(path: Path, payload: dict) -> None:
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{path.name}.",
        dir=path.parent,
    )
    temporary = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            json.dump(payload, handle, ensure_ascii=False, indent=2)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        temporary.replace(path)
    finally:
        temporary.unlink(missing_ok=True)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--run-root", type=Path, required=True)
    parser.add_argument("--model-root", type=Path, required=True)
    arguments = parser.parse_args()
    count = apply_qualification(
        arguments.run_root.expanduser().resolve(),
        arguments.model_root.expanduser().resolve(),
    )
    print(f"qualified {count} models")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
