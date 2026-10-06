#!/usr/bin/env bash
set -euo pipefail

SOURCE_DIR="native/Sources/Application/RealtimeTranscription"

test ! -f "$SOURCE_DIR/LegacyRealtimePreviewDeliveryCache.swift"
test -f "$SOURCE_DIR/RealtimePreviewDeliveryCache.swift"

if rg -n 'LegacyRealtimePreviewDeliveryCache' "$SOURCE_DIR"; then
    echo "Legacy realtime preview delivery cache type must be retired from runtime sources" >&2
    exit 1
fi

if test -f "native/Tests/LegacyRealtimePreviewDeliveryCacheCheck.swift"; then
    echo "LegacyRealtimePreviewDeliveryCacheCheck must be migrated or removed" >&2
    exit 1
fi

echo "RealtimePreviewDeliveryCacheRetirementCheck passed"
