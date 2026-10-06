#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root"

source_file="native/Sources/Application/SpeechInputCoordinator.swift"

if rg -n 'session\.latestPreviewText = state\.displayText' "$source_file"; then
  echo "displayText must not become recording evidence" >&2
  exit 1
fi

grep -Fq 'session.committedPreviewText = state.confirmedText' "$source_file"
grep -Fq 'session.latestPreviewText = state.mutableTailText' "$source_file"

echo "ExperimentalPreviewEvidenceBoundaryCheck passed"
