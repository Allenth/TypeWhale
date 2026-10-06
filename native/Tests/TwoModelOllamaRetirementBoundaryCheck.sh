#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SOURCES="$ROOT/native/Sources"
APP_ENTRY="$ROOT/native/TypeSpeakerApp.swift"

test ! -e "$SOURCES/Infrastructure/SmartRewrite/OllamaRewriteEngine.swift"
test ! -e "$SOURCES/Infrastructure/SmartRewrite/OllamaServiceSupervisor.swift"

if rg -n \
  'OllamaRewriteEngine|OllamaServiceSupervisor|OllamaServerHealthProbe|updateOllamaCapsuleHealth|updateOllamaHealth|ollamaHealthy|ollamaHealthProbe|ollama ok_toast|本地 Ollama 已就绪' \
  "$SOURCES" "$APP_ENTRY" \
  --glob '!**/Presentation/VersionHistory/VersionHistoryViewController.swift' \
  --glob '!**/Presentation/Capsule/Concepts/**' \
  --glob '!**/Presentation/Capsule/PreviewPresenting.swift' \
  --glob '!**/Core/SmartInput/DeveloperLexiconStore.swift' \
  --glob '!**/Core/SmartInput/SmartRewritePromptStore.swift'; then
  echo "Active TypeWhale sources must not retain Ollama runtime or capsule-health behavior." >&2
  exit 1
fi

echo "TwoModelOllamaRetirementBoundaryCheck passed"
