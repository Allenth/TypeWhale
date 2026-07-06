#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
MANIFEST="$ROOT_DIR/docs/asr-eval/pro-hotword-eval-cases.json"

if [[ ! -f "$MANIFEST" ]]; then
  echo "Missing Pro ASR eval manifest: $MANIFEST" >&2
  exit 1
fi

python3 - "$MANIFEST" <<'PY'
import json
import sys
from pathlib import Path

manifest_path = Path(sys.argv[1])
with manifest_path.open("r", encoding="utf-8") as handle:
    data = json.load(handle)

required_top = {"version", "updatedAt", "defaultHotwords", "cases"}
missing_top = sorted(required_top - set(data))
if missing_top:
    raise SystemExit(f"Manifest missing top-level fields: {missing_top}")

if not isinstance(data["defaultHotwords"], list) or not data["defaultHotwords"]:
    raise SystemExit("defaultHotwords must be a non-empty list")

cases = data["cases"]
if not isinstance(cases, list) or len(cases) < 12:
    raise SystemExit("Manifest must contain at least 12 eval cases")

required_case_fields = {
    "id",
    "priority",
    "languageProfile",
    "expectedText",
    "requiredHotwords",
    "protectedTerms",
    "audioPath",
    "recordingStatus",
}
allowed_profiles = {"zh", "en", "mixed", "noise"}
allowed_priorities = {"P0", "P1", "P2"}
allowed_recording_statuses = {"needs_recording", "recorded", "blocked"}

ids = set()
mixed_count = 0
covered_hotwords = set()
required_hotwords = {
    "Codex",
    "Obsidian",
    "Qwen3-ASR",
    "SpeechInputCoordinator",
    "sherpa-onnx",
    "FunASR",
    "Paraformer Contextual",
    "ModelScope",
}

for index, case in enumerate(cases, start=1):
    missing = sorted(required_case_fields - set(case))
    if missing:
        raise SystemExit(f"Case #{index} missing fields: {missing}")

    case_id = case["id"]
    if not isinstance(case_id, str) or not case_id:
        raise SystemExit(f"Case #{index} id must be a non-empty string")
    if case_id in ids:
        raise SystemExit(f"Duplicate case id: {case_id}")
    ids.add(case_id)

    if case["priority"] not in allowed_priorities:
        raise SystemExit(f"{case_id} has invalid priority: {case['priority']}")
    if case["languageProfile"] not in allowed_profiles:
        raise SystemExit(f"{case_id} has invalid languageProfile: {case['languageProfile']}")
    if case["recordingStatus"] not in allowed_recording_statuses:
        raise SystemExit(f"{case_id} has invalid recordingStatus: {case['recordingStatus']}")

    expected = case["expectedText"]
    if not isinstance(expected, str) or len(expected.strip()) < 8:
        raise SystemExit(f"{case_id} expectedText is too short")

    for field in ("requiredHotwords", "protectedTerms"):
        value = case[field]
        if not isinstance(value, list) or not all(isinstance(item, str) and item for item in value):
            raise SystemExit(f"{case_id} {field} must be a list of non-empty strings")

    audio_path = case["audioPath"]
    if audio_path is not None and not isinstance(audio_path, str):
        raise SystemExit(f"{case_id} audioPath must be a string or null")

    if case["languageProfile"] == "mixed":
        mixed_count += 1
    covered_hotwords.update(case["requiredHotwords"])

if mixed_count < 8:
    raise SystemExit("Manifest must contain at least 8 mixed-language cases")

missing_hotwords = sorted(required_hotwords - covered_hotwords)
if missing_hotwords:
    raise SystemExit(f"Manifest does not cover required hotwords: {missing_hotwords}")

print("ProASREvalManifestCheck passed")
PY
