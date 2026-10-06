#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$(mktemp -d "${TMPDIR:-/tmp}/typewhale-remote-guide.XXXXXX")"
trap 'rm -rf "$OUT"' EXIT

REMOTE_DIR="$ROOT/native/Sources/Presentation/Remote"
MAIN_REMOTE="$ROOT/native/Sources/Presentation/Main/MainViewController+Remote.swift"
required_files=(
  RemoteButtonPresentation.swift
  RemoteButtonActionPresentation.swift
  RemoteButtonPreviewPopUpButton.swift
  RemoteInspectorPresentation.swift
  RemoteInspectorSectionFactory.swift
  RemoteConnectionOverviewView.swift
  RemoteVoicePipelineView.swift
  RemoteButtonMappingView.swift
  RemoteSupportView.swift
  XiaomiRemote2ProDiagramSpec.swift
  RemoteButtonPressVisualSpec.swift
  RemoteControlPhotoResource.swift
  RemoteControlIllustrationView.swift
  RemoteButtonGuideView.swift
  RemoteInspectorView.swift
)

for filename in "${required_files[@]}"; do
  if [[ ! -f "$REMOTE_DIR/$filename" ]]; then
    print -u2 "Missing focused Remote presentation file: $filename"
    exit 1
  fi
done

if (( $(wc -l < "$MAIN_REMOTE") > 70 )); then
  print -u2 "MainViewController+Remote.swift must remain wiring-only"
  exit 1
fi

grep -Fq '设备与按键说明' "$REMOTE_DIR/RemoteInspectorView.swift"
grep -Fq 'RemoteButtonPresentation.editableButtons' "$REMOTE_DIR/RemoteButtonMappingView.swift"
grep -Fq 'setAccessibilityLabel' "$REMOTE_DIR/RemoteButtonGuideView.swift"
grep -Fq 'override func mouseDown' "$REMOTE_DIR/RemoteButtonPreviewPopUpButton.swift"
grep -Fq 'mappingView.onButtonPreview' "$REMOTE_DIR/RemoteInspectorView.swift"

PHOTO="$ROOT/native/Resources/Remote/RC003-remote-photo.png"
if [[ -e "$PHOTO" ]]; then
  print -u2 "The public source snapshot must not bundle the restricted RC003 photo"
  exit 1
fi
grep -Fq 'intentionally omits this photo' "$ROOT/THIRD_PARTY_NOTICES.md"
grep -Fq 'RemoteControlPhotoResource.swift' "$ROOT/native/Tests/TypeWhaleRemoteButtonGuideSnapshotCheck.sh"
grep -Fq 'RemoteControlPhotoResource.image' "$REMOTE_DIR/RemoteControlIllustrationView.swift"
grep -Fq '遥控器图片不可用' "$REMOTE_DIR/RemoteControlIllustrationView.swift"

if rg -n 'drawControls|drawRoundButton|systemSymbolName' "$REMOTE_DIR/RemoteControlIllustrationView.swift"; then
  print -u2 "Remote illustration must not invent a misleading replacement for the omitted product photo"
  exit 1
fi

if rg -n 'IOHID|UserDefaults|RemoteBluetooth|SpeechInputCoordinator|https?://' \
  "$REMOTE_DIR/RemoteControlPhotoResource.swift" \
  "$REMOTE_DIR/RemoteControlIllustrationView.swift"; then
  print -u2 "Remote photo presentation must not own runtime or network behavior"
  exit 1
fi

xcrun swiftc \
  -framework AppKit \
  "$ROOT/native/Sources/Domain/Remote/RemoteButton.swift" \
  "$ROOT/native/Sources/Domain/Remote/RemoteActionID.swift" \
  "$ROOT/native/Sources/Domain/Remote/RemoteActionDescriptor.swift" \
  "$ROOT/native/Sources/Domain/Remote/RemoteTrigger.swift" \
  "$ROOT/native/Sources/Domain/Remote/RemoteBinding.swift" \
  "$ROOT/native/Sources/Domain/Remote/RemoteButtonAction.swift" \
  "$ROOT/native/Sources/Domain/Remote/RemoteActionCatalog.swift" \
  "$ROOT/native/Sources/Domain/Remote/RemoteButtonMapping.swift" \
  "$ROOT/native/Sources/Domain/Remote/RemoteMappingMigration.swift" \
  "$ROOT/native/Sources/Infrastructure/Remote/RemoteHIDEventReducer.swift" \
  "$ROOT/native/Sources/Infrastructure/Remote/XiaomiRemote2ProHIDProfile.swift" \
  "$REMOTE_DIR/RemoteButtonPresentation.swift" \
  "$REMOTE_DIR/RemoteButtonActionPresentation.swift" \
  "$REMOTE_DIR/RemoteButtonPreviewPopUpButton.swift" \
  "$REMOTE_DIR/XiaomiRemote2ProDiagramSpec.swift" \
  "$REMOTE_DIR/RemoteButtonPressVisualSpec.swift" \
  "$ROOT/native/Tests/RemoteButtonGuideSpecCheck.swift" \
  -o "$OUT/RemoteButtonGuideSpecCheck"
"$OUT/RemoteButtonGuideSpecCheck"
"$ROOT/native/Tests/TypeWhaleRemoteButtonGuideSnapshotCheck.sh" "$OUT/snapshots"

print "TypeWhaleRemoteButtonGuideFeatureCheck passed"
