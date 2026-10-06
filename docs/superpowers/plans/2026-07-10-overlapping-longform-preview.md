# Overlapping Long-Form Preview Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an opt-in SenseVoice boundary-reconciled preview and dependent long-form incremental-output mode while preserving the current preview/final path when disabled.

**Architecture:** A new pure preview domain owns time-ranged recognition results, boundary planning, immutable confirmed segments, and mutable tail reduction. `ExperimentalRealtimePreviewPipeline`（实验实时预览管线） admits one native request at a time and projects bounded capsule state; `IncrementalTranscriptStore`（增量转录存储器） persists confirmed segments. Existing `SpeechInputCoordinator` only selects the old or experimental path.

**Tech Stack:** Swift 6, AppKit, AVFAudio, C/sherpa-onnx C API, standalone Swift checks, shell boundary checks, existing `native/build_and_log.sh` release workflow.

## Global Constraints

- Branch must remain `codex/typewhale-pro-asr-hotwords`.
- Both experimental settings default off; disabled behavior is byte-for-byte routed through the existing preview/final path.
- Long-form mode depends on and automatically enables corrected preview.
- SenseVoice only; Qwen3-ASR must not enter the experimental pipeline.
- Confirmed text is immutable; only mutable tail may be replaced.
- Native callback results require `sessionID + epoch + requestID` validation.
- Full audio is retained; long-form stop does not run whole-recording final ASR.
- Every production behavior starts with a failing test and observed RED result.
- Every vertical slice may build/install after concurrency and worktree checks; do not wait for the whole experiment.
- English architecture terms in user-facing docs receive adjacent Chinese meanings.

---

### Task 1: Pure preview domain and reducer

**Files:**
- Create: `native/Sources/Domain/RealtimePreview/PreviewRecognitionResult.swift`
- Create: `native/Sources/Domain/RealtimePreview/BoundaryCenteredPreviewPlanner.swift`
- Create: `native/Sources/Domain/RealtimePreview/PreviewTranscriptReducer.swift`
- Create: `native/Tests/PreviewTranscriptReducerCheck.swift`

**Interfaces:**
- Produces: `PreviewAudioRange`, `PreviewRecognitionResult`, `PreviewBoundary`, `PreviewWindowPlan`, `PreviewTranscriptState`, `PreviewTranscriptReducer.apply(_:)`.
- Invariant: `confirmedSegments` never mutate; `displayRevision` advances only when bounded display text changes.

- [ ] **Step 1: Write the failing standalone check**

The check constructs timestamped results around a boundary, verifies VAD and hard-boundary planning, confirms matching text, replaces only mutable tail, rejects stale epochs, suppresses identical display revisions, and requests a recovery window after the first material conflict.

- [ ] **Step 2: Run RED**

```bash
xcrun swiftc native/Sources/Domain/RealtimePreview/*.swift native/Tests/PreviewTranscriptReducerCheck.swift -o /tmp/PreviewTranscriptReducerCheck
```

Expected: FAIL because the new domain types do not exist.

- [ ] **Step 3: Implement the minimal pure domain**

Use value types only. Planner constants are `softBoundarySeconds = 10`, `hardBoundarySeconds = 18`, `correctionWindowSeconds = 22.5`, and `recoveryWindowSeconds = 22.5`. The 22.5-second regular window is the post-review value required to keep consecutive 18-second hard-boundary windows overlapping. Reducer alignment order is valid timestamps → tokens → `Character`; it never confirms past the first mismatch.

- [ ] **Step 4: Run GREEN**

```bash
xcrun swiftc native/Sources/Domain/RealtimePreview/*.swift native/Tests/PreviewTranscriptReducerCheck.swift -o /tmp/PreviewTranscriptReducerCheck && /tmp/PreviewTranscriptReducerCheck
```

Expected: `PreviewTranscriptReducerCheck passed`.

- [ ] **Step 5: Review checkpoint**

Run `git diff --check` and confirm Task 1 imports neither AppKit nor AVFAudio.

### Task 2: Settings, dependency policy, and visible experiment controls

**Files:**
- Modify: `native/Sources/Infrastructure/Settings/AppSettings.swift`
- Modify: `native/Sources/Presentation/Main/MainViewController.swift`
- Modify: `native/Sources/Presentation/Main/MainViewController+Configuration.swift`
- Modify: `native/Sources/Presentation/Main/MainViewController+PanelLayout.swift`
- Modify: `native/Sources/Presentation/Main/MainViewController+Actions.swift`
- Create: `native/Tests/ExperimentalPreviewSettingsCheck.swift`
- Create: `native/Tests/ExperimentalPreviewSettingsBoundaryCheck.sh`

**Interfaces:**
- Produces: `ExperimentalPreviewSettings`, `ExperimentalPreviewSettingsStore`, `correctedPreviewEnabled`, `longFormIncrementalOutputEnabled`.
- Rule: enabling long-form enables base realtime and corrected preview; disabling either prerequisite disables long-form.

- [ ] **Step 1: Write failing settings and source-boundary checks**

Test defaults, normalization, persistence keys, SenseVoice capability gating, both Chinese labels, accessibility labels, and row order beneath “胶囊实时预览”.

- [ ] **Step 2: Run RED**

```bash
xcrun swiftc native/Sources/Domain/ASRDomain.swift native/Sources/Infrastructure/Settings/AppSettings.swift native/Tests/ExperimentalPreviewSettingsCheck.swift -o /tmp/ExperimentalPreviewSettingsCheck
bash native/Tests/ExperimentalPreviewSettingsBoundaryCheck.sh
```

Expected: FAIL because experimental settings and controls are absent.

- [ ] **Step 3: Implement settings and controls**

Add two `BrandSwitch` controls. Normalize dependencies before saving and immediately update enabled states/tooltips. Qwen3 selection disables both experiment controls without deleting the saved preference.

- [ ] **Step 4: Run GREEN**

Run both commands from Step 2; expect both checks to print `passed`.

- [ ] **Step 5: Build checkpoint**

Run source-boundary checks and `git diff --check`; defer version bump to Task 7 unless a real install is needed for UI inspection.

### Task 3: Structured SenseVoice result bridge

**Files:**
- Modify: `native/TypeSpeakerNativeASR.h`
- Modify: `native/TypeSpeakerNativeASR.c`
- Modify: `native/Sources/Infrastructure/ASR/SenseVoiceASR.swift`
- Create: `native/Tests/NativeStructuredRecognitionBoundaryCheck.sh`

**Interfaces:**
- Produces: `TypeSpeakerNativeRecognitionResult`, `TypeSpeakerNativeRecognizerTranscribeDetailed`, `TypeSpeakerNativeRecognitionResultFree`, and Swift `transcribeDetailed`.
- Keeps: existing text-only API unchanged for old callers.

- [ ] **Step 1: Write failing C/Swift source-boundary check**

Assert the owned result copies text, token strings, optional timestamps and count before sherpa result destruction; assert a matching free function and validation of timestamp count/monotonicity in Swift.

- [ ] **Step 2: Run RED**

```bash
bash native/Tests/NativeStructuredRecognitionBoundaryCheck.sh
```

Expected: FAIL because detailed bridge symbols are absent.

- [ ] **Step 3: Implement owned structured bridge**

Allocate and deep-copy all fields while the sherpa result is alive. Free partial allocations safely. Swift copies values into `PreviewRecognitionResult`; invalid timestamps become `nil`, not a failed recognition.

- [ ] **Step 4: Run GREEN and compile native app without install**

```bash
bash native/Tests/NativeStructuredRecognitionBoundaryCheck.sh
TYPESPEAKER_SKIP_INSTALL=1 ./native/build_native_app.sh
```

Expected: check passes and Swift/C compilation succeeds.

### Task 4: Boundary-centered audio snapshots and scheduler

**Files:**
- Modify: `native/Sources/Infrastructure/Audio/AudioRecorder.swift`
- Create: `native/Sources/Application/RealtimePreview/ExperimentalRealtimePreviewPipeline.swift`
- Create: `native/Sources/Application/RealtimePreview/PreviewRequestScheduler.swift`
- Create: `native/Tests/PreviewRequestSchedulerCheck.swift`
- Create: `native/Tests/BoundaryCenteredAudioSourceCheck.sh`

**Interfaces:**
- Audio emits `PreviewAudioSnapshot` with session, chunk, lane, absolute frame range and boundary metadata.
- Scheduler exposes `enqueueFast`, `enqueueCorrection`, `beginStopFinalization`, `complete`, and `reset`.

- [ ] **Step 1: Write failing scheduler and audio-boundary checks**

Verify latest-only fast coalescing, FIFO correction preservation, stop-tail priority, epoch reset, left-context retention across a chunk boundary, and no experimental buffers when disabled.

- [ ] **Step 2: Run RED**

```bash
xcrun swiftc native/Sources/Domain/RealtimePreview/*.swift native/Sources/Application/RealtimePreview/PreviewRequestScheduler.swift native/Tests/PreviewRequestSchedulerCheck.swift -o /tmp/PreviewRequestSchedulerCheck
bash native/Tests/BoundaryCenteredAudioSourceCheck.sh
```

Expected: FAIL because scheduler and experimental audio path do not exist.

- [ ] **Step 3: Implement bounded dual-lane capture and admission**

Reuse current fast snapshots. Under the experiment flag retain only the context required for a 22.5-second boundary-centered correction/recovery window. Submit exactly one native request; pause fast work while correction backlog exists.

- [ ] **Step 4: Run GREEN**

Run Step 2 commands; expect both checks to pass.

### Task 5: Coordinator integration with old-path isolation

**Files:**
- Modify: `native/Sources/Application/SpeechInputState.swift`
- Modify: `native/Sources/Application/SpeechInputCoordinator.swift`
- Create: `native/Tests/ExperimentalPreviewCoordinatorBoundaryCheck.sh`
- Modify: `native/Tests/SpeechInputCoordinatorBoundaryCheck.sh`

**Interfaces:**
- `SpeechSession` captures immutable experiment mode at recording start.
- Coordinator selects old apply/commit logic or pipeline state projection; it never mixes them within a session.

- [ ] **Step 1: Write failing isolation check**

Assert default-off sessions call the existing callback and final ASR; corrected-preview sessions route detailed results through the pipeline; stale callbacks are rejected; Qwen3 never enables the experiment.

- [ ] **Step 2: Run RED**

```bash
bash native/Tests/ExperimentalPreviewCoordinatorBoundaryCheck.sh
```

Expected: FAIL because the integration markers and session mode are absent.

- [ ] **Step 3: Implement the smallest integration**

Keep old methods intact. Add a separate experimental callback and bounded capsule projection. On stop in preview-only mode, discard the experiment pipeline and continue the current VAD/final path unchanged.

- [ ] **Step 4: Run GREEN and regress existing boundaries**

```bash
bash native/Tests/ExperimentalPreviewCoordinatorBoundaryCheck.sh
bash native/Tests/SpeechInputCoordinatorBoundaryCheck.sh
bash native/Tests/PauseAutoFinishSettingsBoundaryCheck.sh
```

Expected: all checks pass.

### Task 6: Incremental persistence and long-form final source

**Files:**
- Create: `native/Sources/Infrastructure/Transcription/IncrementalTranscriptStore.swift`
- Create: `native/Sources/Application/RealtimePreview/LongFormTranscriptionSession.swift`
- Modify: `native/Sources/Application/SpeechInputCoordinator.swift`
- Create: `native/Tests/IncrementalTranscriptStoreCheck.swift`
- Create: `native/Tests/LongFormTranscriptionSessionCheck.swift`
- Create: `native/Tests/LongFormCoordinatorBoundaryCheck.sh`

**Interfaces:**
- Store: `begin`, `appendConfirmed`, `markDegraded`, `finalize`, `recover`.
- Long-form session: 4-hour cap, manual/route/disk/write termination, no pause/no-text auto-finish, tail finalization, final transcript assembly.

- [ ] **Step 1: Write failing persistence and long-duration checks**

Use a temporary directory. Verify append-only replay, interrupted-write survival, 65-minute deterministic segment simulation, bounded capsule projection, stop-tail assembly, degraded-tail evidence, and no call to whole-recording final ASR in long-form mode.

- [ ] **Step 2: Run RED**

```bash
xcrun swiftc native/Sources/Domain/RealtimePreview/*.swift native/Sources/Infrastructure/Transcription/IncrementalTranscriptStore.swift native/Tests/IncrementalTranscriptStoreCheck.swift -o /tmp/IncrementalTranscriptStoreCheck
xcrun swiftc native/Sources/Domain/RealtimePreview/*.swift native/Sources/Application/RealtimePreview/LongFormTranscriptionSession.swift native/Tests/LongFormTranscriptionSessionCheck.swift -o /tmp/LongFormTranscriptionSessionCheck
bash native/Tests/LongFormCoordinatorBoundaryCheck.sh
```

Expected: FAIL because persistence and long-form session types are absent.

- [ ] **Step 3: Implement append-only storage and stop assembly**

Persist under Application Support by stable session ID. Confirmed events are JSON lines written via a serial utility queue. At stop, drain correction descriptors, reconcile the bounded tail, finalize text, then feed it into the existing downstream raw-text path. Keep full audio and evidence on failure.

- [ ] **Step 4: Run GREEN**

Run all Step 2 commands; expect three checks to pass.

### Task 7: Documentation, version, UI review, build, install, and commit

**Files:**
- Modify: `docs/开发日志.md`
- Modify: `docs/ARCHITECTURE.md`
- Modify: `docs/PREVIEW_ARCHITECTURE_COMMUNICATION_LOG.md`
- Modify: `native/Sources/Presentation/VersionHistory/VersionHistoryViewController.swift`
- Modify: version records selected by `native/build_and_log.sh`
- Modify: this plan, marking completed checkboxes.

**Interfaces:**
- Produces a traceable installed build with both experiment switches default off and a clean rollback.

- [ ] **Step 1: Run complete automated verification**

Run every new check plus existing preview, final, VAD, settings and release checks. Run `git diff --check` and inspect `git status --short` for unrelated files.

- [ ] **Step 2: Update documentation before release build**

Record behavior boundaries, experimental status, build/version, automatic dependency, 4-hour cap, final-source change, known limits, validation performed and rollback.

- [ ] **Step 3: Perform design-review（设计质量复核）**

Inspect setting hierarchy, dependency/disabled states, labels, tooltips, accessibility, and the installed capsule behavior. Fix actionable issues before release.

- [ ] **Step 4: Build and install**

After branch/status/process/mtime checks, run:

```bash
./native/build_and_log.sh
```

Expected: build/version bump succeeds, `/Applications/TypeWhale Pro.app` is replaced and opened, Info.plist matches repository values, and deep codesign verification passes.

- [ ] **Step 5: Manual smoke test**

Verify both switches off, corrected preview only, long-form dependency, manual stop, a sentence crossing 18 seconds, and rollback. Record that a true 65-minute microphone run remains a user acceptance step if it cannot be completed during the coding session.

- [ ] **Step 6: Commit reviewed scope**

```bash
git status --short
git add native/TypeSpeakerNativeASR.h native/TypeSpeakerNativeASR.c native/Sources native/Tests docs/ARCHITECTURE.md docs/开发日志.md docs/PREVIEW_ARCHITECTURE_COMMUNICATION_LOG.md docs/superpowers
git commit -m "feat(preview): add overlapping long-form transcription experiment"
```

Expected: commit succeeds and unrelated work remains untouched.
