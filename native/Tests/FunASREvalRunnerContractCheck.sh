#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
RUNNER="$ROOT_DIR/tools/asr-eval/run_funasr_eval.py"
MANIFEST="$ROOT_DIR/docs/asr-eval/pro-hotword-eval-cases.json"
HOTWORDS="$ROOT_DIR/tools/asr-eval/hotwords-dev.txt"
OUTPUT="$(mktemp "${TMPDIR:-/tmp}/typewhale-funasr-eval.XXXXXX.jsonl")"
PROVIDER_OUTPUT="$(mktemp "${TMPDIR:-/tmp}/typewhale-funasr-provider.XXXXXX.jsonl")"
FIXTURE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/typewhale-funasr-fixture.XXXXXX")"
trap 'rm -f "$OUTPUT" "$PROVIDER_OUTPUT"; rm -rf "$FIXTURE_ROOT"' EXIT

if [[ ! -x "$RUNNER" ]]; then
  echo "Missing executable FunASR eval runner: $RUNNER" >&2
  exit 1
fi

python3 "$RUNNER" \
  --manifest "$MANIFEST" \
  --provider dry-run \
  --hotwords "$HOTWORDS" \
  --output "$OUTPUT"

python3 - "$MANIFEST" "$OUTPUT" <<'PY'
import json
import sys
from pathlib import Path

manifest_path = Path(sys.argv[1])
output_path = Path(sys.argv[2])

manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
rows = [
    json.loads(line)
    for line in output_path.read_text(encoding="utf-8").splitlines()
    if line.strip()
]

if len(rows) != len(manifest["cases"]):
    raise SystemExit(f"Expected {len(manifest['cases'])} rows, got {len(rows)}")

required_fields = {
    "caseId",
    "provider",
    "status",
    "rawText",
    "elapsedMs",
    "requiredHotwordHits",
    "missingHotwords",
    "error",
}

case_ids = {case["id"] for case in manifest["cases"]}
seen_ids = set()
skipped_count = 0

for row in rows:
    missing = sorted(required_fields - set(row))
    if missing:
        raise SystemExit(f"Row missing fields: {missing}")
    if row["caseId"] not in case_ids:
        raise SystemExit(f"Unexpected caseId: {row['caseId']}")
    if row["caseId"] in seen_ids:
        raise SystemExit(f"Duplicate caseId: {row['caseId']}")
    seen_ids.add(row["caseId"])
    if row["provider"] != "dry-run":
        raise SystemExit(f"Unexpected provider: {row['provider']}")
    if not isinstance(row["elapsedMs"], int) or row["elapsedMs"] < 0:
        raise SystemExit("elapsedMs must be a non-negative integer")
    if not isinstance(row["requiredHotwordHits"], list):
        raise SystemExit("requiredHotwordHits must be a list")
    if not isinstance(row["missingHotwords"], list):
        raise SystemExit("missingHotwords must be a list")
    if row["status"] == "skipped":
        skipped_count += 1
        if not row["error"]:
            raise SystemExit("Skipped rows must explain why they were skipped")

if skipped_count == 0:
    raise SystemExit("Contract check expects missing local audio to produce skipped rows")

print("FunASREvalRunnerContractCheck passed")
PY

mkdir -p "$FIXTURE_ROOT/funasr" "$FIXTURE_ROOT/model"
cat > "$FIXTURE_ROOT/funasr/__init__.py" <<'PY'
class AutoModel:
    def __init__(self, **kwargs):
        self.kwargs = kwargs

    def generate(self, **kwargs):
        return [{"text": "把 Qwen3-ASR 接到 SpeechInputCoordinator"}]
PY

python3 - "$FIXTURE_ROOT" <<'PY'
import json
import sys
import wave
from pathlib import Path

root = Path(sys.argv[1])
audio = root / "sample.wav"
with wave.open(str(audio), "wb") as handle:
    handle.setnchannels(1)
    handle.setsampwidth(2)
    handle.setframerate(16000)
    handle.writeframes(b"\0\0" * 1600)

(root / "manifest.json").write_text(json.dumps({
    "cases": [{
        "id": "provider-contract",
        "audioPath": str(audio),
        "requiredHotwords": ["Qwen3-ASR", "SpeechInputCoordinator"]
    }]
}), encoding="utf-8")
PY

PYTHONPATH="$FIXTURE_ROOT" python3 "$RUNNER" \
  --manifest "$FIXTURE_ROOT/manifest.json" \
  --provider fun-asr-nano-2512 \
  --model-dir "$FIXTURE_ROOT/model" \
  --hotwords "$HOTWORDS" \
  --output "$PROVIDER_OUTPUT"

python3 - "$PROVIDER_OUTPUT" <<'PY'
import json
import sys
from pathlib import Path

rows = [json.loads(line) for line in Path(sys.argv[1]).read_text(encoding="utf-8").splitlines() if line]
if len(rows) != 1:
    raise SystemExit(f"Expected one provider row, got {len(rows)}")
row = rows[0]
if row["status"] != "ok":
    raise SystemExit(f"Expected wired provider status=ok, got {row['status']}: {row['error']}")
if row["rawText"] != "把 Qwen3-ASR 接到 SpeechInputCoordinator":
    raise SystemExit(f"Unexpected provider text: {row['rawText']!r}")
if row.get("engine") != "fun-asr-nano-2512/funasr-python":
    raise SystemExit(f"Unexpected provider engine: {row.get('engine')!r}")

print("FunASR provider contract passed")
PY
