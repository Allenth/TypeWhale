#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
RUNNER="$ROOT_DIR/tools/asr-eval/run_funasr_eval.py"
MANIFEST="$ROOT_DIR/docs/asr-eval/pro-hotword-eval-cases.json"
HOTWORDS="$ROOT_DIR/tools/asr-eval/hotwords-dev.txt"
OUTPUT="$(mktemp "${TMPDIR:-/tmp}/typewhale-funasr-eval.XXXXXX.jsonl")"
trap 'rm -f "$OUTPUT"' EXIT

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
