#!/usr/bin/env python3
import importlib.util
import json
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("cleanup", ROOT / "tools/tts_verified_cleanup.py")
cleanup = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(cleanup)


def write_model(root: Path, status: str = "passed") -> Path:
    model = root / "model"
    model.mkdir(parents=True)
    (model / "asset.bin").write_bytes(b"same")
    (model / "typewhale-model.json").write_text(
        json.dumps({"qualification": {"status": status}}), encoding="utf-8"
    )
    return model


def rejected(entry, source_root, target_root):
    try:
        cleanup.validate_entry(entry, source_root, target_root)
    except cleanup.CleanupRejected:
        return True
    return False


def main():
    with tempfile.TemporaryDirectory() as temporary:
        base = Path(temporary)
        source_root = base / "LocalTTSLab" / "models"
        target_root = base / "TypeWhale Pro" / "Models" / "tts"
        source = source_root / "legacy"
        source.mkdir(parents=True)
        (source / "asset.bin").write_bytes(b"same")
        model = write_model(target_root)
        entry = {
            "modelID": "model",
            "source": str(source),
            "target": str(model),
            "modelDirectory": str(model),
        }
        result = cleanup.validate_entry(entry, source_root, target_root)
        assert result["files"] == 1 and result["bytes"] == 4

        (model / "asset.bin").write_bytes(b"different")
        assert rejected(entry, source_root, target_root)
        (model / "asset.bin").write_bytes(b"same")

        manifest = model / "typewhale-model.json"
        manifest.write_text(json.dumps({"qualification": {"status": "failed"}}))
        assert rejected(entry, source_root, target_root)
        manifest.write_text(json.dumps({"qualification": {"status": "passed"}}))

        broad = dict(entry, source=str(source_root))
        assert rejected(broad, source_root, target_root)
        reader = dict(entry, source=str(base / "Reader Demo" / "model"))
        assert rejected(reader, source_root, target_root)
        missing = dict(entry, target=str(model / "missing"))
        assert rejected(missing, source_root, target_root)

        symlink = source_root / "link"
        symlink.symlink_to(source, target_is_directory=True)
        assert rejected(dict(entry, source=str(symlink)), source_root, target_root)
    print("TTSVerifiedCleanupCheck passed")


if __name__ == "__main__":
    main()
