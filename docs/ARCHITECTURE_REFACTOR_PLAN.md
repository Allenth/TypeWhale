# TypeWhale Architecture Refactor Plan

## Goal

Use the current English experiment branch as an architecture sandbox. Validate a cleaner architecture first, then migrate the proven design back to stable product lines.

Current sandbox line:

- `experiment/english-edition`

Recommended refactor branch:

- `refactor/architecture-preview-pipeline`

Stable branches and release tags should not be rewritten. If the refactor succeeds, stable product lines should absorb the new architecture in a new release.

## Current Progress

Last updated: 2026-06-25

- Phase 0 completed: safety branch and architecture documents are in place.
- Phase 1 completed: core domain models were moved into `native/Sources/Domain`.
- Phase 2 completed: audio recording, paste coordination, hotkey monitoring, model manifests/installing, and ASR bridges were moved into `native/Sources/Infrastructure`.
- Phase 3 completed: main window, recording capsule, version history, and shared UI helpers were moved into `native/Sources/Presentation`.
- Phase 4 completed: lifecycle coordination and speech input coordination were extracted from `AppDelegate`.
- Phase 5 experiment result: `PreviewComposer` / committed-volatile preview did not improve the real capsule experience and was removed.
- Current preview baseline: restored the v1.1.1-style capsule visual cache while keeping the refactored folder structure.
- Current next step: keep extracting stable behavior from large presentation/coordinator files. Prefer Strategy for replaceable engines and policies, Coordinator/Use Case for workflows, and Command for shortcut/annotation actions.

## Target Architecture

```text
Presentation
- AppKit views
- ViewModels

Application
- Coordinators
- Use cases
- Workflow commands

Domain
- Pure product models
- Preview rules
- Recording session state

Infrastructure
- Audio recording
- ASR engines
- OCR / translation providers
- Hotkeys
- Pasteboard and target app handling
- Permissions
- Model manifests
```

## Phase 0: Safety Line

Purpose: create a safe baseline before moving code.

Tasks:

- Commit the current experiment branch state.
- Create `refactor/architecture-preview-pipeline`.
- Create architecture documents:
  - `docs/ARCHITECTURE_REFACTOR_PLAN.md`
  - `docs/ARCHITECTURE_DECISIONS.md`
  - `docs/PREVIEW_PIPELINE_DESIGN.md`
- Record the current functional baseline:
  - Chinese hotkey input
  - English hotkey input
  - Recording
  - Realtime preview
  - Final transcription
  - Auto paste
  - Recent transcript history
  - Menu bar background mode
  - Hotkey editing
  - Permission diagnostics

Done when:

- Current state is committed.
- Refactor branch exists.
- Documents exist.
- Baseline checklist is recorded.

Rollback point:

- Current `experiment/english-edition` commit.

## Phase 1: Extract Domain

Purpose: move pure models and product concepts first without behavior changes.

Move to `native/Sources/Domain`:

- `ASRConfiguration`
- `RecordingTask`
- `RecentTranscription`
- `RecognitionLanguageMode`
- `SpeechInputChannel`
- `HotkeyBinding`
- `HotkeyKeyCodes`
- `PasteOutcome`

Preview domain models were intentionally deferred. The first committed refactor keeps preview strategy out of the domain layer until a tested reducer/typing-buffer design is ready.

Done when:

- App builds.
- App launches.
- Chinese input works.
- English input works.
- Paste works.
- Behavior is unchanged.

## Phase 2: Extract Infrastructure

Purpose: move system capabilities out of the large app file.

Suggested directories:

```text
native/Sources/Infrastructure/Audio
native/Sources/Infrastructure/ASR
native/Sources/Infrastructure/Hotkey
native/Sources/Infrastructure/Paste
native/Sources/Infrastructure/Permissions
native/Sources/Infrastructure/Models
```

Move:

- `AudioRecorder`
- `LockedRecordingState`
- `NativeSenseVoiceBridge`
- `SenseVoiceRouter`
- `HotkeyMonitor`
- `PasteCoordinator`
- `PasteboardSnapshot`
- `SenseVoiceModelManifest`
- `ParakeetModelManifest`
- `SenseVoiceModelInstaller`

Done when:

- Each moved module builds.
- No product behavior changes are introduced.
- Final recording, transcription, and paste still work.

## Phase 3: Extract Presentation

Purpose: separate UI from product flow and infrastructure.

Suggested directories:

```text
native/Sources/Presentation/Main
native/Sources/Presentation/Capsule
native/Sources/Presentation/VersionHistory
```

Move:

- `MainViewController`
- `RecordingCapsuleView`
- `RecordingPanel`
- `VersionHistoryViewController`
- `FlippedStackView`
- `label` helper

Add lightweight ViewModels:

- `MainViewModel`
- `CapsulePreviewViewModel`
- `PermissionViewModel`
- `HotkeySettingsViewModel`

Done when:

- Main window renders normally.
- Capsule renders normally.
- Version history popover works.
- No obvious UI regression is introduced.

## Phase 4: Introduce Application Coordinators

Purpose: make `AppDelegate` responsible only for lifecycle and dependency wiring.

Add:

- `SpeechInputCoordinator`
- `AppLifecycleCoordinator`

`SpeechInputCoordinator` owns:

- Hotkey down/up events
- Start recording
- Stop recording
- Realtime snapshot routing
- Realtime preview scheduling
- Final transcription
- Paste result handling

Introduce a centralized state machine:

```swift
enum SpeechInputState {
    case idle
    case recording(RecordingSession)
    case stopping(RecordingSession)
    case finalizing(RecordingTask)
    case pasting(RecordingTask)
    case failed(String)
}
```

Done when:

- `AppDelegate` is visibly smaller.
- Recording task state is centralized.
- Stopped recordings cannot keep polluting preview.
- Final transcription and realtime preview have clear boundaries.

## Phase 5: Preview Pipeline Experiment

Purpose: validate whether a formal preview pipeline improves the capsule experience without affecting final transcription.

Experimented flow:

```text
PreviewHypothesis
-> PreviewComposer
-> TranscriptPreviewState
-> CapsulePreviewViewModel
-> RecordingCapsuleView
```

Result:

- This approach added latency and still produced visible jumping in real recording.
- The code was removed from the active product path.
- The app currently uses cumulative realtime snapshots and the capsule's local visual cache.
- Final transcription still never depends on preview.

Future rules if this phase is reopened:

- Add a reducer before any typing animation.
- Keep reducer and visual typing buffer independently testable.
- Do not bind raw rolling snapshot text directly to per-character animation.
- Do not let `RecordingCapsuleView` own ASR text strategy.

Test scenarios:

- Chinese continuous sentence
- Chinese repeated fragments
- English continuous sentence
- English partial words
- English repeated tails
- Mixed Chinese and English
- Disconnected snapshot
- Pending snapshot after stop

Done when reopened:

- Preview does not visibly repeat.
- Preview does not heavily jump backward.
- Preview latency is acceptable.
- Final paste still uses full audio transcription.
- Reducer and visual typing buffer can be tested independently.

## Phase 6: Improve Paste Flow

Purpose: move closer to input-method quality.

Add abstractions:

- `InputTarget`
- `InputTargetSnapshot`
- `InputTargetRestorer`

Current retained behavior:

- Restore the target app.
- Paste through pasteboard and `Cmd+V`.

Future enhancement:

- Capture AX focused element at recording start.
- Restore focused element before paste.
- Fall back to app activation plus `Cmd+V` if AX restore fails.

Done when:

- Original app can be restored.
- Clipboard can be restored.
- Paste failure has a clear message.
- Input-field-level restore can be added later.

## Phase 7: Cleanup And Migration

Purpose: turn the experiment into a reusable migration path.

Tasks:

- Update architecture docs.
- Update decision records.
- Remove dead code.
- Remove old preview buffer code.
- Update README.
- Update version history.
- Decide target migration line:
  - `main`
  - `lite`
  - `pro`
  - `english`
- Migrate by phase, not by copying the entire sandbox branch.

Done when:

- Refactor branch is stable.
- Design docs are complete.
- Target product line is selected.
- New release can absorb the architecture without rewriting old tags.

## Per-Phase Verification Checklist

Every phase must pass:

- App builds.
- App launches.
- Chinese hotkey can record.
- English hotkey can record.
- Final transcription works.
- Auto paste works.
- Recent transcript history works.
- Menu bar entry works.
- Hotkey editing works.
- Permission state works.
- No obvious UI regression.

## Execution Principles

- Document first.
- Commit before risky movement.
- Move in small steps.
- Keep every step runnable.
- Do not casually change product behavior during structural refactor.
- Rebuild preview logic only in Phase 5.
