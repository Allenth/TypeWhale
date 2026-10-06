#!/usr/bin/env python3
import importlib.util
import tempfile
from pathlib import Path


root = Path(__file__).resolve().parents[1]
engine_path = root / "Resources/tts_engines/cosyvoice3_engine.py"
spec = importlib.util.spec_from_file_location("cosyvoice3_engine", engine_path)
assert spec and spec.loader
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

with tempfile.TemporaryDirectory() as temporary:
    try:
        module.CosyVoice3Engine(Path(temporary))
    except RuntimeError as error:
        assert "runtime_unavailable" in str(error)
        assert "CosyVoice3" in str(error)
    else:
        raise AssertionError("missing CosyVoice3 assets must be rejected")

print("test_cosyvoice3_engine passed")
