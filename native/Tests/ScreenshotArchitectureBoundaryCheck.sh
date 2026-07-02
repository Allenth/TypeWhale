#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCREENSHOT="$ROOT/native/Sources/Presentation/Screenshot/ScreenshotCoordinator.swift"
SPEECH="$ROOT/native/Sources/Application/SpeechInputCoordinator.swift"

for forbidden in \
  "MainViewController" \
  "onSuppressReopen" \
  "screenshot_overlay_close" \
  "application_reopen_suppress"; do
  if grep -q "$forbidden" "$SCREENSHOT"; then
    echo "ScreenshotCoordinator must not depend on $forbidden" >&2
    exit 1
  fi
done

if ! grep -q "ScreenshotOverlayWindow: NSPanel" "$SCREENSHOT"; then
  echo "Screenshot overlay must stay a non-activating panel boundary, not a main app window" >&2
  exit 1
fi

if ! grep -q "\\.nonactivatingPanel" "$SCREENSHOT"; then
  echo "Screenshot overlay must include .nonactivatingPanel" >&2
  exit 1
fi

if ! grep -q "截图翻译模式" "$SCREENSHOT"; then
  echo "Screenshot translation entry must visibly identify translation mode on the overlay" >&2
  exit 1
fi

if ! grep -q "松开后自动 OCR 并翻译覆盖" "$SCREENSHOT"; then
  echo "Screenshot translation overlay must explain the automatic OCR and translation behavior" >&2
  exit 1
fi

if ! grep -q "drawTranslationLoadingHintIfNeeded" "$SCREENSHOT"; then
  echo "Screenshot translation pending state must draw an in-selection loading hint" >&2
  exit 1
fi

if ! grep -q "startTranslationLoadingAnimation" "$SCREENSHOT"; then
  echo "Screenshot translation loading hint must animate only while translation is pending" >&2
  exit 1
fi

ocr_block="$(
  awk '
    /private func recognizeText\(in image: NSImage\)/ { in_block=1 }
    in_block { print }
    in_block && /^    }$/ { exit }
  ' "$SCREENSHOT"
)"

ocr_status_line="$(grep -n 'showTransientStatus("OCR 识别中"' <<<"$ocr_block" | head -1 | cut -d: -f1 || true)"
ocr_token_line="$(grep -n 'operationTokens.start(.ocr)' <<<"$ocr_block" | head -1 | cut -d: -f1 || true)"
if [ -z "$ocr_status_line" ] || [ -z "$ocr_token_line" ] || [ "$ocr_status_line" -ge "$ocr_token_line" ]; then
  echo "OCR processing status must be emitted before starting the OCR operation token" >&2
  echo "Otherwise the transient status token invalidates the OCR result before it can copy text." >&2
  exit 1
fi

if ! grep -q "ScreenshotCoordinator()" "$SPEECH"; then
  echo "SpeechInputCoordinator must not inject main UI status/reopen callbacks into ScreenshotCoordinator" >&2
  exit 1
fi

entry_block="$(
  awk '
    /private func beginScreenshotFromHotkey\(translateAfterSelection:/ { in_block=1 }
    in_block { print }
    in_block && /^    }$/ { exit }
  ' "$SPEECH"
)"

for forbidden in \
  "showMainWindow" \
  "hideMainWindow" \
  "suppressNextReopen" \
  "NSApp.activate" \
  "setPrimaryStatus"; do
  if grep -q "$forbidden" <<<"$entry_block"; then
    echo "Screenshot hotkey entry must not touch main-window or main-panel state via $forbidden" >&2
    exit 1
  fi
done

echo "ScreenshotArchitectureBoundaryCheck passed"
