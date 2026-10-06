#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h:h}"
OUTPUT_DIR="${1:-${TMPDIR:-/tmp}/typewhale-remote-guide-snapshots}"
BINARY_PATH="${TMPDIR:-/tmp}/RemoteButtonGuideSnapshotCheck"

swiftc \
  -parse-as-library \
  "$ROOT_DIR/native/Tests/RemoteButtonGuideSnapshotCheck.swift" \
  "$ROOT_DIR/native/Sources/Domain/Remote/RemoteButton.swift" \
  "$ROOT_DIR/native/Sources/Domain/Remote/RemoteActionID.swift" \
  "$ROOT_DIR/native/Sources/Domain/Remote/RemoteActionDescriptor.swift" \
  "$ROOT_DIR/native/Sources/Domain/Remote/RemoteTrigger.swift" \
  "$ROOT_DIR/native/Sources/Domain/Remote/RemoteBinding.swift" \
  "$ROOT_DIR/native/Sources/Domain/Remote/RemoteButtonAction.swift" \
  "$ROOT_DIR/native/Sources/Domain/Remote/RemoteActionCatalog.swift" \
  "$ROOT_DIR/native/Sources/Domain/Remote/RemoteButtonMapping.swift" \
  "$ROOT_DIR/native/Sources/Domain/Remote/RemoteMappingMigration.swift" \
  "$ROOT_DIR/native/Sources/Infrastructure/Remote/RemoteHIDEventReducer.swift" \
  "$ROOT_DIR/native/Sources/Infrastructure/Remote/XiaomiRemote2ProHIDProfile.swift" \
  "$ROOT_DIR/native/Sources/Presentation/Shared/UIHelpers.swift" \
  "$ROOT_DIR/native/Sources/Presentation/Shared/UIComponents.swift" \
  "$ROOT_DIR/native/Sources/Presentation/Remote/RemoteButtonPresentation.swift" \
  "$ROOT_DIR/native/Sources/Presentation/Remote/RemoteButtonActionPresentation.swift" \
  "$ROOT_DIR/native/Sources/Presentation/Remote/RemoteButtonPreviewPopUpButton.swift" \
  "$ROOT_DIR/native/Sources/Presentation/Remote/XiaomiRemote2ProDiagramSpec.swift" \
  "$ROOT_DIR/native/Sources/Presentation/Remote/RemoteButtonPressVisualSpec.swift" \
  "$ROOT_DIR/native/Sources/Presentation/Remote/RemoteControlPhotoResource.swift" \
  "$ROOT_DIR/native/Sources/Presentation/Remote/RemoteControlIllustrationView.swift" \
  "$ROOT_DIR/native/Sources/Presentation/Remote/RemoteButtonGuideView.swift" \
  "$ROOT_DIR/native/Sources/Presentation/Remote/RemoteInspectorSectionFactory.swift" \
  "$ROOT_DIR/native/Sources/Presentation/Remote/RemoteButtonMappingView.swift" \
  -o "$BINARY_PATH"

"$BINARY_PATH" "$OUTPUT_DIR"
