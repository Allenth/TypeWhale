#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

grep -q 'case voice' "$ROOT/native/Sources/Presentation/Main/MainViewController.swift"
grep -q 'case \.voice: return "声音"' "$ROOT/native/Sources/Presentation/Main/MainViewController.swift"
grep -q 'buildOpenClawVoicePanelContent' "$ROOT/native/Sources/Presentation/Main/MainViewController+PanelLayout.swift"
grep -q 'OpenClawVoiceSettingsStore.standard.save' "$ROOT/native/Sources/Presentation/Main/MainViewController+Actions.swift"
grep -q 'openClawVoiceMode' "$ROOT/native/Sources/Presentation/Main/MainViewController.swift"
grep -q 'openClawVoiceVolumeSlider' "$ROOT/native/Sources/Presentation/Main/MainViewController.swift"
grep -q 'openClawVoiceRateSlider' "$ROOT/native/Sources/Presentation/Main/MainViewController.swift"
grep -q 'optionRow("音色"' "$ROOT/native/Sources/Presentation/Main/MainViewController+PanelLayout.swift"
! grep -q 'optionRow("朗读引擎"' "$ROOT/native/Sources/Presentation/Main/MainViewController+PanelLayout.swift"
! grep -q 'optionRow("TTS 模型"' "$ROOT/native/Sources/Presentation/Main/MainViewController+PanelLayout.swift"
! grep -q 'optionRow("角色"' "$ROOT/native/Sources/Presentation/Main/MainViewController+PanelLayout.swift"
grep -Fq 'voice=\(settings.voiceID)' "$ROOT/native/Sources/Presentation/Main/MainViewController+Actions.swift"
