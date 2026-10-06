#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PANEL_LAYOUT="$ROOT/native/Sources/Presentation/Main/MainViewController+PanelLayout.swift"
PREFERENCES="$ROOT/native/Sources/Presentation/Main/MainViewController+Preferences.swift"
SOURCES="$ROOT/native/Sources"

if grep -q "hasHorizontalScroller = true" "$PANEL_LAYOUT"; then
  echo "Main window settings must not use a horizontal panel scroller." >&2
  exit 1
fi

if grep -q "panelScrollView" "$PANEL_LAYOUT"; then
  echo "Main panel layout must not depend on panelScrollView." >&2
  exit 1
fi

if grep -q "scrollToConfigPanels" "$PREFERENCES"; then
  echo "Preferences must select a stable inspector tab, not scroll horizontally." >&2
  exit 1
fi

if grep -R -q "scrollToConfigPanels" "$SOURCES"; then
  echo "Source must not keep the removed horizontal settings navigation hook." >&2
  exit 1
fi

grep -q "buildInspectorTabs" "$PANEL_LAYOUT" || {
  echo "Main panel layout must expose stable inspector tabs." >&2
  exit 1
}

grep -q "func panelTitleLabel" "$ROOT/native/Sources/Presentation/Shared/UIComponents.swift" || {
  echo "Main window titles must use shared typography helpers." >&2
  exit 1
}

grep -q "func inspectorGroupTitleLabel" "$ROOT/native/Sources/Presentation/Shared/UIComponents.swift" || {
  echo "Inspector group headings must use shared typography helpers." >&2
  exit 1
}

grep -q "func controlRowLabel" "$ROOT/native/Sources/Presentation/Shared/UIComponents.swift" || {
  echo "Control row labels must use shared typography helpers." >&2
  exit 1
}

if grep -q "controller.resetInspectorReadingPosition()" "$ROOT/native/Sources/Application/AppLifecycleCoordinator.swift"; then
  echo "Opening the main window must preserve the user's inspector scroll position." >&2
  exit 1
fi

grep -q "func inspectorGroupBox" "$ROOT/native/Sources/Presentation/Shared/UIComponents.swift" || {
  echo "Inspector groups must use shared spacing surfaces, not one-off rounded boxes." >&2
  exit 1
}

python3 - "$PANEL_LAYOUT" <<'PY'
import re
import sys

source = open(sys.argv[1], encoding="utf-8").read()
match = re.search(r"case \.common:\s*return inspectorPage\(\[(.*?)\]\)", source, re.S)
if not match:
    print("Common inspector page must declare its group order explicitly.", file=sys.stderr)
    sys.exit(1)

groups = re.findall(r'inspectorGroup\("([^"]+)"', match.group(1))
expected = ["状态", "录音与预览", "截图", "系统", "预览主题"]
if groups != expected:
    print(f"Common inspector groups must keep status, recording preview, screenshot, system, and theme settings in order. Found: {groups}", file=sys.stderr)
    sys.exit(1)

voice_match = re.search(r"case \.voice:\s*return inspectorPage\(\[(.*?)\]\)", source, re.S)
if not voice_match:
    print("Voice inspector page must declare its group order explicitly.", file=sys.stderr)
    sys.exit(1)

voice_groups = re.findall(r'inspectorGroup\("([^"]+)"', voice_match.group(1))
voice_expected = ["麦克风", "麦克风策略", "小龙虾声音"]
if voice_groups != voice_expected:
    print(f"Voice inspector groups must separate microphone device, microphone policy, and OpenClaw voice settings. Found: {voice_groups}", file=sys.stderr)
    sys.exit(1)
PY

if grep -q 'inspectorGroup("快捷设置"' "$PANEL_LAYOUT"; then
  echo "Common tab must not keep the old quick smart settings group; smart processing controls belong in the Intelligence tab." >&2
  exit 1
fi

common_block="$(
  awk '
    /case \.common:/ { in_block=1 }
    in_block { print }
    in_block && /case \.intelligence:/ { exit }
  ' "$PANEL_LAYOUT"
)"

for forbidden in \
  'buildQuickSettingsCardContent' \
  'optionRow("归档整理", screenshotArchiveMode)' \
  'compactOptionRow("整理模式", smartRewriteMode)' \
  'compactOptionRow("自动翻译", autoTranslate)' \
  'compactOptionRow("翻译方向", translationDirectionMode)'; do
  if grep -q "$forbidden" <<<"$common_block"; then
    echo "Common tab must not expose smart processing control: $forbidden" >&2
    exit 1
  fi
done

smart_block="$(
  awk '
    /private func buildSmartRewritePanelContent\(\)/ { in_block=1 }
    in_block { print }
    in_block && /private func buildHotkeysPanelContent/ { exit }
  ' "$PANEL_LAYOUT"
)"

for required in \
  'optionRow("整理模式", smartRewriteMode)' \
  'optionRow("闪念整理", ideaPillRewriteMode)' \
  'optionRow("归档整理", screenshotArchiveMode)' \
  'optionRow("自动翻译", autoTranslate)' \
  'optionRow("翻译方向", translationDirectionMode)'; do
  if ! grep -q "$required" <<<"$smart_block"; then
    echo "Intelligence tab must expose smart processing control: $required" >&2
    exit 1
  fi
done

grep -q "static let controlLabelWidth" "$ROOT/native/Sources/Presentation/Shared/UIComponents.swift" || {
  echo "Control row labels need a shared width to stabilize long Chinese labels." >&2
  exit 1
}

if grep -q 'let header = label(title, size:' "$PANEL_LAYOUT"; then
  echo "Panel layout must not hand-code title label sizes." >&2
  exit 1
fi

echo "MainWindowLayoutBoundaryCheck passed"
