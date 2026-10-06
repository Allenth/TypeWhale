#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
import plistlib
import tempfile
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
MODULE_PATH = REPO_ROOT / "tools" / "tts_zipvoice_cleanup.py"


def load_module():
    spec = importlib.util.spec_from_file_location("tts_zipvoice_cleanup", MODULE_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError("unable to load cleanup module")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def write_bytes(path: Path, count: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(b"x" * count)


def main() -> None:
    cleanup = load_module()
    with tempfile.TemporaryDirectory(prefix="typewhale-tts-cleanup-check-") as raw:
        root = Path(raw)
        models = root / "TypeWhale Pro" / "Models" / "tts"
        runtimes = root / "TypeWhale Pro" / "Runtimes" / "tts"
        reader = root / "Reader Demo"
        trash = root / ".Trash"
        retained = models / cleanup.RETAINED_MODEL_ID
        retired = models / "kokoro-int8-multi-lang-v1_1"
        other = models / "qwen3-tts-06b-coreml"
        staging = models / ".staging" / "kokoro-fp32"
        runtime = runtimes / "cosyvoice3-main-py310"

        write_bytes(retained / "decoder.int8.onnx", 11)
        for voice in cleanup.RETAINED_VOICE_IDS:
            write_bytes(retained / "references" / voice / "reference.wav", 3)
        write_bytes(retired / "model.int8.onnx", 13)
        write_bytes(other / "model.mlmodelc" / "weights.bin", 17)
        write_bytes(staging / "partial.bin", 19)
        write_bytes(runtime / "bin" / "python3.10", 23)
        (runtime / "bin" / "python3").symlink_to("python3.10")
        write_bytes(reader / "Models" / "tts" / retired.name / "model.int8.onnx", 29)

        plan = cleanup.build_plan(
            models_root=models,
            runtimes_root=runtimes,
            protected_roots=[reader],
        )
        by_path = {entry["path"]: entry for entry in plan["entries"]}
        assert by_path[str(retained.resolve())]["disposition"] == "retain"
        assert by_path[str(retired.resolve())]["disposition"] == "retire"
        assert by_path[str(other.resolve())]["disposition"] == "retire"
        assert by_path[str(staging.resolve())]["disposition"] == "retire"
        assert by_path[str(runtime.resolve())]["disposition"] == "retire"
        assert all(not path.startswith(str(reader.resolve())) for path in by_path)
        assert plan["reclaimableBytes"] == 13 + 17 + 19 + 23
        assert set(plan["retainedVoiceIDs"]) == set(cleanup.RETAINED_VOICE_IDS)
        assert json.dumps(plan, sort_keys=True) == json.dumps(
            cleanup.build_plan(models, runtimes, [reader]),
            sort_keys=True,
        )

        escaped = models / "escaped-model"
        escaped.symlink_to(reader, target_is_directory=True)
        try:
            cleanup.build_plan(models, runtimes, [reader])
        except cleanup.CleanupSafetyError as error:
            assert "symlink" in str(error)
        else:
            raise AssertionError("symlink target must be rejected")
        escaped.unlink()

        report = cleanup.execute_to_trash(
            plan=plan,
            trash_root=trash,
            verification_record=None,
        )
        assert report["executed"] is False
        assert report["reason"] == "verification-required"
        assert retired.exists()

        app = root / "Applications" / "TypeWhale Pro.app"
        app_worker = app / "Contents" / "Resources" / "tts_benchmark_worker.py"
        source_worker = root / "source-worker.py"
        write_bytes(app_worker, 31)
        write_bytes(source_worker, 31)
        info = app / "Contents" / "Info.plist"
        info.parent.mkdir(parents=True, exist_ok=True)
        info.write_bytes(plistlib.dumps({
            "CFBundleVersion": "test-build",
            "CFBundleShortVersionString": "test-version",
        }))
        qualification = root / "qualification.json"
        qualification.write_text(json.dumps({
            "modelID": cleanup.RETAINED_MODEL_ID,
            "fingerprint": "zipvoice-distill-int8-reference-voices-v2",
            "voices": {voice: "passed" for voice in cleanup.RETAINED_VOICE_IDS},
        }))
        verification = {
            "schemaVersion": 1,
            "cleanupAuthorized": True,
            "modelID": cleanup.RETAINED_MODEL_ID,
            "voiceIDs": list(cleanup.RETAINED_VOICE_IDS),
            "build": "test-build",
            "version": "test-version",
            "installedAppPath": str(app),
            "sourceWorkerPath": str(source_worker),
            "workerSHA256": cleanup.file_sha256(app_worker),
            "modelPath": str(retained),
            "modelInventorySHA256": cleanup.inventory_sha256(retained),
            "qualificationPath": str(qualification),
            "protectedInventorySHA256": {
                str(reader.resolve()): cleanup.inventory_sha256(reader),
            },
            "checks": {
                "automatedTests": True,
                "installedPlayback": True,
                "openClawBoundary": True,
                "signatureValid": True,
                "packageResidueFree": True,
            },
        }
        assert cleanup.validate_verification_record(verification)
        tampered = dict(verification, workerSHA256="0" * 64)
        assert not cleanup.validate_verification_record(tampered)
        report = cleanup.execute_to_trash(
            plan=plan,
            trash_root=trash,
            verification_record=verification,
        )
        assert report["executed"] is True
        assert report["reclaimedBytes"] == plan["reclaimableBytes"]
        assert retained.exists()
        assert not retired.exists()
        assert (reader / "Models" / "tts" / retired.name / "model.int8.onnx").exists()
        assert all(
            Path(item["trashPath"]).is_relative_to(trash.resolve())
            for item in report["entries"]
        )

        try:
            cleanup._validate_retirement_target(models, models, [reader])
        except cleanup.CleanupSafetyError as error:
            assert "root" in str(error)
        else:
            raise AssertionError("approved root must never be a retirement target")

    print("TTSZipVoiceCleanupCheck passed")


if __name__ == "__main__":
    main()
