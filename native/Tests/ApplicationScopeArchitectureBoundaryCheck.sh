#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../.."

scope_files=(
  native/Sources/Infrastructure/Applications/ApplicationCatalog.swift
  native/Sources/Presentation/Main/Dialogs/ApplicationScopeEditorModel.swift
  native/Sources/Presentation/Main/Dialogs/ApplicationScopeViewController.swift
  native/Sources/Presentation/Main/Dialogs/ApplicationScopeWindowController.swift
)

for file in "${scope_files[@]}"; do
  [[ -e "$file" ]] || continue
  if rg -n \
    'SpeechSession|RealtimePreview|TranscriptionProvider|RecordingPanel|CandidatePreview|ShadowPreview' \
    "$file"; then
    echo "Application scope UI/catalog crossed realtime or capsule boundary: $file" >&2
    exit 1
  fi
done

paste_coordinator=native/Sources/Infrastructure/Paste/PasteCoordinator.swift
if [[ -e "$paste_coordinator" ]] &&
   rg -n 'UserDefaults|AutoSendSettingsStore' "$paste_coordinator"; then
  echo "PasteCoordinator must not read settings" >&2
  exit 1
fi

if [[ -e native/Sources/Presentation/Main/Dialogs/SmartRewriteAutoRuleDialog.swift ]]; then
  echo "Retired rewrite dialog must not remain after the unified editor ships" >&2
  exit 1
fi

echo "ApplicationScopeArchitectureBoundaryCheck passed"
