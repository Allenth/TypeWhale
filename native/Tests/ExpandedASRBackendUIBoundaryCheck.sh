#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SELECTOR="$ROOT/native/Sources/Presentation/Main/ASRBackendSegmentedSelector.swift"
CONFIG="$ROOT/native/Sources/Presentation/Main/MainViewController+Configuration.swift"
DOMAIN="$ROOT/native/Sources/Domain/ASRDomain.swift"
grep -q 'ASRButtonFlowLayout.layout' "$SELECTOR"
grep -q 'override func layout()' "$SELECTOR"
grep -q 'override var intrinsicContentSize: NSSize' "$SELECTOR"
if grep -Eq 'NSScrollView|hasHorizontalScroller|scrollToVisible' "$SELECTOR"; then
  echo "ASR model selector must not scroll" >&2
  exit 1
fi
grep -q 'ASRBackend.allCases' "$CONFIG"
grep -q 'isEnabled:' "$CONFIG"
grep -q '自动换行' "$CONFIG"
test "$(grep -c 'case \.' "$DOMAIN" | tr -d ' ')" -ge 10
grep -q 'Sherpa int8' "$DOMAIN"; grep -q 'MLX 8-bit' "$DOMAIN"
echo "ExpandedASRBackendUIBoundaryCheck passed"
