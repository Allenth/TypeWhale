#!/usr/bin/env python3
"""Validate TypeWhale's checked-in local ASR admission evidence."""
import json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
path=ROOT/"native/Resources/local-candidate-admission.json"
data=json.loads(path.read_text())
expected={"sensevoice-int8","parakeet-tdt-0.6b-v2-sherpa-int8","fun-asr-nano-2512","qwen3-asr-0.6b-mlx-8bit","qwen3-asr-1.7b-mlx-8bit"}
rows=data["candidates"];actual={row["candidate_id"] for row in rows}
assert actual==expected,(expected-actual,actual-expected)
for row in rows:
    assert row["admitted"] is True
    assert row["nonempty"] is True and row["text"].strip()
    assert row["hotword_strategy"] in {"unsupported","native_list"}
print(f"Local ASR candidate matrix valid: {len(rows)} admitted")
