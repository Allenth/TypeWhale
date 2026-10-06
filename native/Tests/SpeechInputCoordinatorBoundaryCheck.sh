#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SPEECH="$ROOT/native/Sources/Application/SpeechInputCoordinator.swift"
STATE="$ROOT/native/Sources/Application/SpeechInputState.swift"
AUDIO="$ROOT/native/Sources/Infrastructure/Audio/AudioRecorder.swift"

if ! grep -Fq "static let autoFinishPauseSeconds: TimeInterval = 2.0" "$SPEECH"; then
  echo "Pause auto-finish must preserve natural pauses before completing" >&2
  exit 1
fi

if ! grep -Fq "var onVoiceProbe: ((UUID, [Float], Int) -> Void)?" "$AUDIO"; then
  echo "AudioRecorder voice probes must carry their recording task ID" >&2
  exit 1
fi

if ! grep -Fq "self?.onVoiceProbe?(taskID, window, rate)" "$AUDIO"; then
  echo "AudioRecorder must emit the current task ID with every voice probe" >&2
  exit 1
fi

if ! grep -Fq "receiveVoiceProbe(taskID: UUID, samples: [Float], sampleRate: Int)" "$SPEECH"; then
  echo "SpeechInputCoordinator must accept task-scoped voice probes" >&2
  exit 1
fi

if ! grep -Fq "activeSession?.id == taskID" "$SPEECH"; then
  echo "SpeechInputCoordinator must reject VAD callbacks from an old recording task" >&2
  exit 1
fi

if ! grep -Fq "vad_probe_ignored reason=stale_task" "$SPEECH"; then
  echo "Stale VAD callbacks must be observable" >&2
  exit 1
fi

if ! grep -Fq "recording_auto_finish reason=pause" "$SPEECH"; then
  echo "Pause auto-finish must log its decision reason" >&2
  exit 1
fi

if ! grep -Fq "recording_auto_finish reason=initial_silence" "$SPEECH"; then
  echo "Initial-silence cancellation must log its decision reason" >&2
  exit 1
fi

if ! grep -Fq "pendingVoiceProbes" "$SPEECH" || ! grep -Fq "voiceProbeSequence" "$SPEECH"; then
  echo "Voice probes arriving during inference must enter a task-scoped FIFO" >&2
  exit 1
fi

if grep -Fq "pendingVoiceProbe = request" "$SPEECH"; then
  echo "A latest-only pending probe can overwrite short speech evidence" >&2
  exit 1
fi

if ! grep -Fq "vad_probe_backpressure_disable" "$SPEECH"; then
  echo "Probe backlog overflow must safely disable auto-finish instead of dropping evidence" >&2
  exit 1
fi

if ! grep -Fq "canCommitDecision: self.pendingVoiceProbes.isEmpty" "$SPEECH"; then
  echo "Auto-finish must not commit while newer audio is still waiting for VAD" >&2
  exit 1
fi

if ! grep -Fq "vad_probe_finish_deferred reason=newer_audio_pending" "$SPEECH"; then
  echo "Deferred finish decisions must be observable" >&2
  exit 1
fi

if ! grep -Fq "vad_probe_no_speech_pending_confirmation" "$SPEECH"; then
  echo "A qualifying no-speech result must wait for a second probe before finishing" >&2
  exit 1
fi

if ! grep -Fq "case .idle = self.inputState" "$SPEECH"; then
  echo "Initial-silence feedback must not hide a new recording or final-recognition capsule" >&2
  exit 1
fi

if ! grep -Fq "decision_delay_ms=" "$SPEECH" || ! grep -Fq "probe_ms=" "$SPEECH"; then
  echo "Pause decisions must expose VAD inference and sample-to-decision latency" >&2
  exit 1
fi

if ! grep -q "let channel: SpeechInputChannel" "$STATE"; then
  echo "SpeechSession must remember which input channel started the recording" >&2
  exit 1
fi

if ! grep -q "matchesTrigger(channel: SpeechInputChannel, purpose: SpeechInputPurpose)" "$STATE"; then
  echo "SpeechSession must expose same-trigger matching for hotkey up isolation" >&2
  exit 1
fi

if ! grep -q "submittedTaskIDs" "$ROOT/native/Sources/Application/SpeechWorkflowState.swift"; then
  echo "SpeechWorkflowState must keep multiple submitted tasks so a new recording does not stale an older background result" >&2
  exit 1
fi

hotkey_up_block="$(
  awk '
    /private func handleHotkeyUp\(/ { in_block=1 }
    in_block { print }
    in_block && /^    }$/ { exit }
  ' "$SPEECH"
)"

if ! grep -q "shouldReplaceActiveRecording(channel: channel, purpose: purpose)" <<<"$hotkey_up_block"; then
  echo "Hotkey up must decide whether it is replacing the active recording with a new one" >&2
  exit 1
fi

if ! grep -q "if shouldStartReplacement" <<<"$hotkey_up_block"; then
  echo "A different recording shortcut key-up must finish the old recording and immediately start the new one" >&2
  exit 1
fi

hotkey_down_block="$(
  awk '
    /private func handleHotkeyDown\(/ { in_block=1 }
    in_block { print }
    in_block && /private func handleHotkeyUp/ { exit }
  ' "$SPEECH"
)"

if ! grep -q "if let activeSession" <<<"$hotkey_down_block"; then
  echo "Hotkey down must handle an already active recording instead of ignoring it" >&2
  exit 1
fi

if ! grep -q "activeSession.matchesTrigger(channel: channel, purpose: purpose)" <<<"$hotkey_down_block"; then
  echo "Same recording shortcut key-down must leave finish handling to key-up: 我开、我关" >&2
  exit 1
fi

if ! grep -q "suppressNextHotkeyUp = true" <<<"$hotkey_down_block"; then
  echo "Replacement recording started on key-down must suppress the paired key-up: 我开、他开；先关我，再开他" >&2
  exit 1
fi

non_media_active_block="$(
  awk '
    /let displayName = binding.displayName/ { in_block=1 }
    in_block { print }
    in_block && /guard !recorder.isRecording/ { exit }
  ' "$SPEECH"
)"

same_trigger_line="$(grep -n "activeSession.matchesTrigger(channel: channel, purpose: purpose)" <<<"$non_media_active_block" | head -n 1 | cut -d: -f1)"
finish_line="$(grep -n "finishRecording()" <<<"$non_media_active_block" | head -n 1 | cut -d: -f1)"

if [[ -z "$same_trigger_line" || -z "$finish_line" || "$same_trigger_line" -ge "$finish_line" ]]; then
  echo "Non-media same-trigger key-down must be checked before finishRecording, otherwise key-up can reopen the capsule" >&2
  exit 1
fi

if ! grep -q "smartRewritePreference(for purpose: SpeechInputPurpose)" "$SPEECH"; then
  echo "SpeechInputCoordinator must choose smart rewrite preference by purpose" >&2
  exit 1
fi

idea_pill_preference_block="$(
  awk '
    /private func smartRewritePreference\(for purpose: SpeechInputPurpose\)/ { in_block=1 }
    in_block { print }
    in_block && /^    }$/ { exit }
  ' "$SPEECH"
)"

if ! grep -q "case \\.ideaPill:" <<<"$idea_pill_preference_block" || ! grep -q "return IdeaPillRewriteModeStore.load()" <<<"$idea_pill_preference_block"; then
  echo "Idea pill recordings must use the dedicated idea pill rewrite mode setting, independent of the global smart rewrite preference" >&2
  exit 1
fi

if ! grep -q "static let defaultMode: SmartRewritePreference = \\.instantSummary" "$ROOT/native/Sources/Infrastructure/Settings/AppSettings.swift"; then
  echo "Idea pill rewrite mode must default to 即时归纳" >&2
  exit 1
fi

if ! grep -q "configureIdeaPillRewriteModeMenu(IdeaPillRewriteModeStore.load())" "$ROOT/native/Sources/Presentation/Main/MainViewController.swift"; then
  echo "Main smart settings must load the dedicated idea pill rewrite mode menu" >&2
  exit 1
fi

if ! grep -q "IdeaPillRewriteModeStore.save(ideaPillRewritePreference)" "$ROOT/native/Sources/Presentation/Main/MainViewController+Actions.swift"; then
  echo "Main smart settings must save the dedicated idea pill rewrite mode" >&2
  exit 1
fi

if ! grep -q "optionRow(\"闪念整理\", ideaPillRewriteMode)" "$ROOT/native/Sources/Presentation/Main/MainViewController+PanelLayout.swift"; then
  echo "Intelligence settings must expose a 闪念整理 row" >&2
  exit 1
fi

idea_pill_save_block="$(
  awk '
    /private func saveIdeaPill\(_ result: PendingPasteResult\)/ { in_block=1 }
    in_block { print }
    in_block && /private func saveBacklogIfRequested/ { exit }
  ' "$SPEECH"
)"

if grep -q "modeName: controller.smartRewritePreference.displayName" <<<"$idea_pill_save_block"; then
  echo "Idea pill Markdown mode must record the purpose-specific rewrite preference, not the global smart rewrite preference" >&2
  exit 1
fi

if ! grep -Fq "modeName: result.rewriteMode?.displayName ?? smartRewritePreference(for: result.task.purpose).displayName" <<<"$idea_pill_save_block"; then
  echo "Idea pill Markdown mode must record the actual rewrite mode used for that task" >&2
  exit 1
fi

echo "SpeechInputCoordinatorBoundaryCheck passed"
