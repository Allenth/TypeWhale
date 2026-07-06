#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$ROOT/native/package_dmg.sh"

if grep -Eq 'rm -rf .*/Contents/Resources/Models"?$' "$SCRIPT"; then
  echo "package_dmg.sh must not remove the entire Resources/Models directory" >&2
  exit 1
fi

if ! grep -q 'sensevoice-native/model.onnx' "$SCRIPT"; then
  echo "package_dmg.sh must verify bundled ASR model presence" >&2
  exit 1
fi

if ! grep -q 'vad/silero_vad.onnx' "$SCRIPT"; then
  echo "package_dmg.sh must verify bundled VAD model presence" >&2
  exit 1
fi

if ! grep -q 'LLM_EXCLUDE_DIRS' "$SCRIPT"; then
  echo "package_dmg.sh must keep LLM exclusion explicit" >&2
  exit 1
fi

echo "PackageDmgModelPolicyCheck passed"
