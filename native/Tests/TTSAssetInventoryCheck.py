#!/usr/bin/env python3
import hashlib
import json
import subprocess
import sys
import tempfile
from pathlib import Path


root = Path(__file__).resolve().parents[2]
tool = root / "tools/tts_asset_inventory.py"

with tempfile.TemporaryDirectory() as temporary:
    sandbox = Path(temporary)
    protected = sandbox / "Reader Demo"
    protected.mkdir()
    protected_model = protected / "kokoro" / "model.onnx"
    protected_model.parent.mkdir()
    protected_model.write_bytes(b"protected")

    regular = sandbox / "LocalTTSLab" / "models" / "kokoro"
    regular.mkdir(parents=True)
    regular_model = regular / "model.int8.onnx"
    regular_model.write_bytes(b"model")

    result = subprocess.run(
        [
            sys.executable,
            str(tool),
            "--scan-root",
            str(sandbox),
            "--protected-root",
            str(protected),
            "--json",
        ],
        check=True,
        capture_output=True,
        text=True,
    )
    rows = json.loads(result.stdout)
    by_path = {row["path"]: row for row in rows}

    protected_row = by_path[str(protected_model)]
    assert protected_row["protected"] is True
    assert protected_row["sha256"] == ""

    regular_row = by_path[str(regular_model)]
    assert regular_row["protected"] is False
    assert regular_row["sha256"] == hashlib.sha256(b"model").hexdigest()
    assert regular_row["category"] == "kokoro"

print("TTSAssetInventoryCheck passed")
