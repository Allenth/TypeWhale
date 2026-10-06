#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SPEECH="$ROOT/native/Sources/Application/SpeechInputCoordinator.swift"
APP="$ROOT/native/TypeSpeakerApp.swift"
MAIN="$ROOT/native/Sources/Presentation/Main/MainViewController.swift"
ACTION="$ROOT/native/Sources/Presentation/Main/MainViewController+Actions.swift"

require_text() {
  local needle="$1"
  local file="$2"
  local message="$3"
  if ! grep -Fq "$needle" "$file"; then
    echo "$message" >&2
    exit 1
  fi
}

require_text "private var isFinalRewriteInFlight = false" "$SPEECH" \
  "Final rewrite activity must explicitly guard managed-model release"
require_text "private var isTranslationInFlight = false" "$SPEECH" \
  "Voice translation activity must explicitly guard managed-model release"
require_text "private func prewarmManagedLLMIfNeeded(reason: String)" "$SPEECH" \
  "Managed Qwen must have a lifecycle-owned prewarm path"
require_text "Task.detached(priority: .utility)" "$SPEECH" \
  "Managed model verification and prewarm must not block the main actor"
require_text "registry.readiness(for: modelID)" "$SPEECH" \
  "Managed Qwen may prewarm only after the complete model is ready"
require_text "case .ready = service.runtimeState" "$SPEECH" \
  "Managed Qwen may prewarm only after its runtime is ready"
require_text "private func cancelActiveSmartAIWork(reason: String)" "$SPEECH" \
  "Final-input cancellation must also cancel managed Qwen work"
require_text "private var managedLLMRecoveryWorkItem: DispatchWorkItem?" "$SPEECH" \
  "Managed Qwen cancellation recovery must be cancellable"
require_text "private var managedLLMWakeRecoveryWorkItem: DispatchWorkItem?" "$SPEECH" \
  "Managed Qwen wake recovery must be cancellable"
require_text "managedLLMRecoveryWorkItem?.cancel()" "$SPEECH" \
  "Sleep, stop, and model changes must cancel delayed Qwen recovery"
require_text "managedLLMWakeRecoveryWorkItem?.cancel()" "$SPEECH" \
  "Sleep, stop, and model changes must cancel delayed wake recovery"
require_text "guard !self.isSystemSleeping, !self.isCoordinatorStopping" "$SPEECH" \
  "Delayed Qwen recovery must not restart during sleep or shutdown"
require_text "ManagedLLMRuntimeService.shared.runtime.cancelCurrentRequest()" "$SPEECH" \
  "Managed Qwen cancellation must reach the owned runtime"
require_text "private func stopManagedLLM(reason: String)" "$SPEECH" \
  "Sleep, power-off, and app stop must have an owned-helper shutdown path"
require_text 'stopManagedLLM(reason: "system_sleep")' "$SPEECH" \
  "System sleep must stop the managed Qwen helper"
require_text 'stopManagedLLM(reason: "system_power_off")' "$SPEECH" \
  "System power-off must stop the managed Qwen helper"
require_text "coldPrewarmAllowed: true" "$SPEECH" \
  "Wake recovery must respect memory policy before restoring Qwen"
require_text "workerSnapshot.footprintMB" "$SPEECH" \
  "Request cancellation must preserve the Worker footprint for safe recovery"
if grep -Fq "guard managedLLMMemoryRecoveryNotBefore != nil else { return }" "$SPEECH"; then
  echo "Explicit wake cold-prewarm eligibility must not be discarded after policy evaluation" >&2
  exit 1
fi
require_text "ManagedLLMRuntimeService.shared.stop()" "$APP" \
  "App termination must explicitly stop the managed Qwen helper"
require_text "onSmartAIModelChange" "$MAIN" \
  "The model switch must notify the lifecycle owner"
require_text "onSmartAIModelChange?(model)" "$ACTION" \
  "Unified model changes must notify the lifecycle owner"

idle_guard="$(sed -n '/private var isIdleForASRResourceRelease: Bool/,/^    }/p' "$SPEECH")"
if ! grep -Fq "isFinalRewriteInFlight" <<<"$idle_guard" ||
   ! grep -Fq "isTranslationInFlight" <<<"$idle_guard"; then
  echo "High-memory release must not run during final rewrite or voice translation" >&2
  exit 1
fi

require_text 'stopManagedLLM(reason: "memory_warn")' "$SPEECH" \
  "High-memory protection must flush the managed Qwen helper"
require_text "ManagedLLMLifecyclePolicy.recoveryCooldown" "$SPEECH" \
  "Managed Qwen must use the lifecycle cooldown after a high-memory stop"
require_text "coldPrewarmAllowed: Bool = false" "$SPEECH" \
  "Normal memory checks must not duplicate the startup prewarm"
require_text "nativeASR.reload()" "$SPEECH" \
  "ASR must still reload immediately after its high-memory arena flush"

if grep -Fq 'prewarmManagedLLMIfNeeded(reason: "memory_warn_reload")' "$SPEECH"; then
  echo "Managed Qwen must not immediately reload after a high-memory stop" >&2
  exit 1
fi

if grep -Eq "managedLLMIdleUnload|idleLLMUnload|managedLLMUnloadTimer" "$SPEECH"; then
  echo "Managed Qwen must not use an idle unload timer" >&2
  exit 1
fi

echo "ManagedLLMLifecycleBoundaryCheck passed"
