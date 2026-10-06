#!/usr/bin/env python3
import importlib.util
import tempfile
from pathlib import Path


root = Path(__file__).resolve().parents[1]
engine_path = root / "Resources/tts_engines/voxcpm2_engine.py"
spec = importlib.util.spec_from_file_location("voxcpm2_engine", engine_path)
assert spec and spec.loader
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

with tempfile.TemporaryDirectory() as temporary:
    try:
        module.VoxCPM2Engine(Path(temporary))
    except RuntimeError as error:
        assert "runtime_unavailable" in str(error)
        assert "VoxCPM2" in str(error)
    else:
        raise AssertionError("missing VoxCPM2 assets must be rejected")

print("test_voxcpm2_engine passed")
