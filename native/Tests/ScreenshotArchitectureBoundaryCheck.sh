#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCREENSHOT="$ROOT/native/Sources/Presentation/Screenshot/ScreenshotCoordinator.swift"
SPEECH="$ROOT/native/Sources/Application/SpeechInputCoordinator.swift"
MAIN_PANEL="$ROOT/native/Sources/Presentation/Main/MainViewController+PanelLayout.swift"
MAIN_CONFIG="$ROOT/native/Sources/Presentation/Main/MainViewController+Configuration.swift"
MAIN_ACTIONS="$ROOT/native/Sources/Presentation/Main/MainViewController+Actions.swift"
MAIN_VIEW="$ROOT/native/Sources/Presentation/Main/MainViewController.swift"

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

archive_block="$(
  awk '
    /private func archiveKnowledge\(in image: NSImage\)/ { in_block=1 }
    in_block { print }
    in_block && /private func translateText\(/ { exit }
  ' "$SCREENSHOT"
)"

if ! grep -q 'emit(.init("归档整理中"' <<<"$archive_block"; then
  echo "Screenshot archive processing must use a persistent in-page status titled 归档整理中" >&2
  exit 1
fi

if grep -q 'showTransientStatus("归档整理中"' <<<"$archive_block"; then
  echo "Screenshot archive processing status must not be a transient toast" >&2
  exit 1
fi

if ! grep -q 'ToastPresenter.shared.show("归档整理中"' <<<"$archive_block"; then
  echo "Screenshot archive processing must also show a top toast titled 归档整理中" >&2
  exit 1
fi

if ! grep -q 'ToastPresenter.shared.show("归档整理中".*duration: nil' <<<"$archive_block"; then
  echo "Screenshot archive processing toast must persist until completion replaces it" >&2
  exit 1
fi

if grep -q 'operationTokens' <<<"$archive_block"; then
  echo "Screenshot archive must not depend on global screenshot operation tokens" >&2
  echo "A later screenshot must not be able to invalidate an already-started archive save." >&2
  exit 1
fi

if ! grep -q 'finishArchiveProcessingStatus("归档已保存"' <<<"$archive_block"; then
  echo "Screenshot archive success must switch to 归档已保存 and then clear transiently" >&2
  exit 1
fi

if ! grep -q 'ScreenshotArchiveModeStore.load()' <<<"$archive_block"; then
  echo "Screenshot archive must load its rewrite mode from screenshot settings" >&2
  exit 1
fi

if grep -q 'preference: \\.developerRequirement' <<<"$archive_block" || grep -q 'preference: \\.exhaustiveSummary' <<<"$archive_block"; then
  echo "Screenshot archive must not hard-code 开发需求 or 极致归纳; it must use the screenshot archive mode setting" >&2
  exit 1
fi

if ! grep -q "ScreenshotCoordinator()" "$SPEECH"; then
  echo "SpeechInputCoordinator must not inject main UI status/reopen callbacks into ScreenshotCoordinator" >&2
  exit 1
fi

if ! grep -q 'optionRow("归档整理", screenshotArchiveMode)' "$MAIN_PANEL"; then
  echo "Screenshot settings must expose the archive rewrite mode picker" >&2
  exit 1
fi

if ! grep -q 'configureScreenshotArchiveModeMenu(ScreenshotArchiveModeStore.load())' "$MAIN_VIEW"; then
  echo "Main settings must initialize the screenshot archive mode picker from persisted settings" >&2
  exit 1
fi

if ! grep -q 'ScreenshotArchiveModeStore.supportedModes' "$MAIN_CONFIG"; then
  echo "Screenshot archive mode menu must use the supported archive modes from the settings store" >&2
  exit 1
fi

if ! grep -q 'ScreenshotArchiveModeStore.save(screenshotArchivePreference)' "$MAIN_ACTIONS"; then
  echo "Saving settings must persist the screenshot archive rewrite mode" >&2
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
