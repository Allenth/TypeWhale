#!/usr/bin/env python3
import importlib.util
import tempfile
from pathlib import Path


root = Path(__file__).resolve().parents[1]
engine_path = root / "Resources/tts_engines/moss_tts_engine.py"
spec = importlib.util.spec_from_file_location("moss_tts_engine", engine_path)
assert spec and spec.loader
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

with tempfile.TemporaryDirectory() as temporary:
    pack = Path(temporary)
    try:
        module.MossTTSEngine(pack)
    except RuntimeError as error:
        assert "runtime_unavailable" in str(error)
        assert "audio-tokenizer-v2" in str(error)
    else:
        raise AssertionError("missing codec assets must be rejected")

print("test_moss_tts_engine passed")
