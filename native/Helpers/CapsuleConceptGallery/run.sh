#!/bin/zsh
# 独立编译并运行三套概念胶囊预览（真实 fan-out 分发 + 悬浮面板 + 模拟数据源）。
# 拉取：自包含概念视图/面板/分发器 + 数据源契约（PreviewPresenting / PreviewDisplaySnapshot）+ main。
# 刻意排除 +Standard.swift（它引用生产 RecordingPanel），与主程序完全隔离。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CONCEPTS="$ROOT/native/Helpers/CapsuleConceptGallery/Concepts"
CONTRACT_SNAPSHOT="$ROOT/native/Sources/Domain/RealtimePreview/PreviewDisplaySnapshot.swift"
CONTRACT_PRESENT="$ROOT/native/Sources/Presentation/Capsule/PreviewPresenting.swift"
OUT="$(mktemp -d /tmp/capsule-gallery.XXXXXX)"
BIN="$OUT/CapsuleConceptGallery"

echo "编译中…"
swiftc -O \
  "$CONTRACT_SNAPSHOT" \
  "$CONTRACT_PRESENT" \
  "$CONCEPTS/CapsuleConceptKit.swift" \
  "$CONCEPTS/InkwellCapsuleView.swift" \
  "$CONCEPTS/MistlineCapsuleView.swift" \
  "$CONCEPTS/JadeArcCapsuleView.swift" \
  "$CONCEPTS/ConceptCapsulePanel.swift" \
  "$CONCEPTS/MultiCapsulePreviewPresenter.swift" \
  "$ROOT/native/Helpers/CapsuleConceptGallery/main.swift" \
  -framework AppKit \
  -o "$BIN"

echo "启动悬浮预览（三套胶囊将出现在屏幕底部中央，自下而上堆叠）…"
"$BIN"
