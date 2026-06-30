# TypeWhale Architecture

Last updated: 2026-06-30

This document is the single current architecture source for TypeWhale. Older architecture notes and ADR files are historical context only. If code or product behavior changes an architecture boundary, update this file and record the concrete work in `docs/开发日志.md`.

## Product Main Path

TypeWhale is a resident macOS input productivity app. The main path is:

```text
global hotkey
-> record complete microphone audio
-> show realtime capsule preview as confidence feedback
-> run final ASR on the complete recording
-> optional smart rewrite or translation
-> paste final text into the original target app
```

The main path must remain stable while architecture is improved. Realtime preview is never the source of final paste. Final paste, recent history, and backlog records use final ASR output plus approved smart processing.

## Layers

TypeWhale uses lightweight Clean Architecture with AppKit-friendly coordinators. Do not introduce a broad framework rewrite.

```text
Presentation
- AppKit views, panels, popovers, dialogs, drawing, visual state.
- User-event forwarding.
- Local visual animation and display buffers.

Application
- Coordinators, use cases, workflow state, command dispatch.
- Recording, screenshot, lifecycle, finalization, paste orchestration.
- Product workflow policies that span multiple infrastructure services.

Domain
- Stable product concepts and pure rules.
- ASR configuration, recording task identity, hotkey bindings, paste outcomes.
- Text normalization and pure gates such as final speech gating.

Infrastructure
- macOS and external capabilities: audio, ASR, VAD, OCR, AI provider APIs, hotkeys, pasteboard, permissions, keychain, model files, diagnostics, observability, build/distribution resources.
```

Boundary rule: views should not decide final paste safety, provider routing, cross-window lifecycle, or ASR/VAD product policy. Infrastructure should not know product workflow state beyond small ports/adapters.

## Current Source Map

- `native/Sources/Presentation`: main window, recording capsule, notch preview, screenshot overlay UI, shared AppKit components, version history.
- `native/Sources/Application`: `SpeechInputCoordinator`, `SpeechInputState`, `AppLifecycleCoordinator`.
- `native/Sources/Domain`: ASR, hotkey, paste, final speech gate, recognition text normalization/filtering.
- `native/Sources/Core`: smart input domain services, prompt building, usage ledger, developer lexicon, backlog.
- `native/Sources/Infrastructure`: audio recorder, ASR bridge/router, hotkey monitor, paste coordinator, model installer, permissions, settings, diagnostics, observability, AI provider clients.

Known concentration points:

- `SpeechInputCoordinator` still owns too many application concerns: hotkeys, recording, VAD, realtime preview, final ASR, smart rewrite/translation, paste, screenshot entry, memory safety.
- `ScreenshotCoordinator` / overlay view still mix UI rendering, toolbar action policy, annotation, OCR/translation callbacks, and window recapture state.

These files should be split through explicit state models, use cases, commands, and adapter ports, not through an app-wide rewrite.

## Stable Invariants

### Voice Input

- Final inserted text comes from full-recording ASR, not realtime preview.
- Realtime preview is a confidence anchor: it should appear quickly, remain readable through natural pauses, and avoid obvious jumping or duplication.
- Existing good capsule behavior must be preserved or compared against historical good versions before changing animation or preview strategy.
- Recording task identity must be explicit. Do not couple finalization to `latest.wav`.
- Recording, recognition, smart processing, and paste must ignore stale callbacks from older tasks.
- Empty-recording protection is allowed, but VAD must not silently discard speech when realtime evidence exists.

### Preview Pipeline

Current active preview direction, as of 2026-06-29/2026-06-30, is the 1.5 chunk-commit preview path:

- Audio is divided into preview chunks.
- Only the current chunk is repeatedly recognized for realtime preview.
- When a chunk reaches the soft target and Silero reports a pause, or when it reaches the hard limit, the chunk text is frozen into `committedPreviewText`.
- Display text is `committedPreviewText + latestPreviewText`.
- Final chunk snapshots use a dedicated queue and should not be dropped.
- Final paste still uses complete-recording ASR.

This supersedes the older ADR-010 rule that `committedPreviewText` must be removed. The older rule was correct for the failed short-pause reset/sliding-window path, but it is no longer the current source of truth. The current line keeps the key guardrail: never reset already displayed text on ordinary short pauses.

Preview non-goals:

- Do not use preview text as final paste text.
- Do not add language-model correction to realtime preview by default.
- Do not make `RecordingCapsuleView` merge ASR text or infer language-specific strategy.

### VAD, ASR, And Memory

- Silero VAD is the authoritative recording-time voice signal.
- Energy bands and peak level are visual/readout signals, not final voice truth.
- Final VAD is a soft gate: if realtime preview or recording-time VAD shows speech evidence, final ASR must still run even when final VAD says `no_speech`.
- ASR/VAD resources stay warm during normal use.
- Do not reintroduce idle timer unloading.
- High-memory safety may flush and immediately warm-load the native ASR/VAD arena only when the app is idle and above the warning threshold.
- Never release model resources while recording, recognizing, smart-processing, or pasting.

### Screenshot, OCR, And Translation

- Screenshot mode observes the desktop; entering it must not show, hide, restore, or otherwise manage the TypeWhale main window.
- Screenshot overlay may become key enough to receive input without activating the main TypeWhale app window.
- Window-level capture may raise the explicitly selected target window and recapture in place.
- During screenshot OCR/translation pending state, actions that export or mutate unstable output must be disabled or guarded. Cancel remains allowed.
- Stale OCR/translation callbacks must be ignored after cancel or superseding operations.
- Screenshot translation layout and product acceptance details live in `docs/SCREENSHOT_TRANSLATION_SPEC.md`.

### Main Window Lifecycle

- Main-window visibility is governed only by explicit user actions, the configured main-window shortcut, status-item/menu commands, and approved first-install/default-open behavior.
- Login-item/background launch must not unexpectedly surface the main window.
- Screenshot and recording flows must not take ownership of main-window visibility.

### AI Providers

- DeepSeek v4 flash is the only active user-facing AI text provider.
- The provider boundary stays in code through `SelectedSmartAITextEngine`.
- MiniMax remains non-user-facing unless it later passes intent-preservation tests.
- Future providers must enter through adapter/strategy boundaries and pass smart rewrite, voice translation, and screenshot translation quality fixtures before becoming visible.
- Observability must never upload audio, screenshots, OCR text, clipboard contents, API keys, file paths, or raw transcripts.

## Accepted Architecture Decisions

### Architecture Governance

- Use lightweight Clean Architecture plus Coordinator / Use Case, Strategy, State Machine, Command, and Adapter / Port.
- Do not do a broad rewrite.
- Refactor one stable workflow boundary at a time.
- Extract abstractions from verified product behavior, not speculation.

### Workflow Patterns

- Coordinator / Use Case: speech input, screenshot capture, app lifecycle, permission checks, paste submission.
- Strategy: ASR providers, AI text providers, translation direction, paste behavior, OCR/screenshot translation providers, preview-theme variations.
- State Machine: long-running or cancelable workflows such as screenshot selection/translation and speech recording/finalization/paste.
- Command: toolbar actions, screenshot annotation actions, global hotkey actions, recent-transcription copy/save, undoable operations.
- Adapter / Port: macOS APIs, model runtimes, keychain, pasteboard, observability, network providers, screen capture.

### Historical Decisions Still Active

- Final transcription is independent from realtime preview.
- Screenshot overlay must not activate or reorder the TypeWhale main window.
- Automatic smart rewrite rules may match target context and content text separately.
- Capsule preview is a presentation pipeline with bounded realtime work and stale-callback protection.
- AI provider work must preserve user intent over model novelty.
- ASR/VAD memory safety must prefer response latency over aggressive unloading.

## Historical Or Superseded Decisions

Historical records remain in `docs/开发日志.md`. These decisions should not be copied back into active code without a fresh review:

- The `PreviewComposer` / committed-volatile preview experiment failed the real capsule experience and was removed.
- The old short-pause segment reset / sliding-window preview path was rejected because it caused visible jumps and lost context.
- ADR-010's blanket removal of `committedPreviewText` is superseded by the current chunk-commit preview path. The rejected part is reset-on-pause / sliding-window behavior, not every form of frozen preview prefix.
- ADR-002's "MVVM + Coordinator" wording is narrowed by the current governance rule: use AppKit-friendly coordinators and small view models where useful, but do not convert the app to a heavy MVVM rewrite.

## Architecture Governance Plan

Each version must preserve the stable main path unless a behavior change is explicitly approved.

### Review Action Items: 2026-06-30

These items come from the code review before the next refactor pass. They are concrete blockers or ambiguity sources that must be addressed by the staged plan below.

#### Version A Blockers

- `TypeSpeakerApp.applicationDidFinishLaunching` currently calls `lifecycle.showMainWindow()` unconditionally. This violates the main-window lifecycle invariant for login-item/background launches. Action: introduce an explicit launch visibility policy before showing the main window.
- `SpeechInputCoordinator.beginScreenshotFromHotkey(...)` currently calls `hideMainWindow()` before entering screenshot mode. This violates the screenshot invariant that screenshot entry observes the desktop and does not manage TypeWhale's main window. Action: remove screenshot ownership of main-window visibility.
- `ScreenshotOverlayView` only disables the translate button while `isTranslating == true`; copy, save, OCR, annotation, undo, and done remain available against unstable output. Action: add a pending-state action policy that allows cancel and blocks or guards all unstable-output actions.
- Screenshot translation callbacks have no overlay-local generation token. `replaceScreenshot(...)` resets `isTranslating`, and a stale callback can still mutate markups/status after cancel or recapture. Action: generation-gate OCR/translation callbacks and invalidate them on cancel, replace, recapture, and close.

#### Version B Blockers

- Screenshot toolbar availability is still computed ad hoc in drawing and mouse handling. Action: introduce `ScreenshotSessionState` plus command availability checks before adding more screenshot tools.
- Screenshot overlay view still owns both rendering and product action policy. Action: keep drawing/annotation rendering in Presentation, but move state transition and action dispatch policy into a testable command/state model.

#### Version C Blockers

- `SpeechInputCoordinator` remains the main concentration point for hotkeys, recording, VAD, realtime preview, final ASR, smart rewrite/translation, paste, screenshot entry, and memory safety. Action: split through speech workflow state/use cases after Version A/B stabilize user-visible state.
- Final ASR, smart processing, paste, target tracking, and ASR memory safety are interleaved in one coordinator. Action: define use cases for final recognition, smart processing, paste submission, and idle memory safety before moving logic.

#### Preview Pipeline Blocker

- `AudioRecorder` advances chunk state and clears `realtimeBuffers` before the final chunk snapshot has been successfully written. If `writeRealtimeSnapshot` fails, the coordinator never receives that final chunk, while the recorder has already discarded the buffers and advanced `realtimeChunkIndex`. Action: make final chunk commit two-phase or otherwise recoverable so the "final chunk snapshots should not be dropped" invariant is true in failure paths.

### Version A: State And Window-Lifecycle Corrections

Purpose: repair product-semantics regressions before adding more abstractions.

Scope:

- Screenshot entry observes the desktop without managing TypeWhale main-window visibility.
- Main-window visibility is governed by explicit user actions and approved launch behavior only.
- Screenshot translation pending state allows cancel but disables or guards copy, save, OCR, annotation, undo, and other unstable-output actions.
- Stale translation callbacks after cancel or superseding operations are ignored.
- UI controls that promise unwired runtime behavior are either wired or hidden.

Verification:

- Manual screenshot QA with TypeWhale main window hidden, behind another app, and visible in front.
- Pending screenshot translation QA: copy/save do not export unstable images.
- Relevant checks for changed state policy.
- Build/local install only when explicitly requested under repository build rules.

### Version B: Screenshot Session State Machine And Toolbar Commands

Purpose: reduce screenshot coordinator/view state coupling without changing the user-visible workflow.

Scope:

- Introduce `ScreenshotSessionState` for idle, selecting, selected, window-recapture-pending, translating, completed, cancelled, and failed.
- Convert toolbar actions to command-style dispatch with per-state availability.
- Keep annotation rendering in presentation; move action policy out of mouse handlers.
- Make window recapture and translation cancellation generation-based and testable.

Verification:

- Lightweight checks for allowed actions per screenshot state.
- Manual QA: region selection, window selection, Esc cancel, translate, copy, save, undo.

### Version C: Speech Workflow State Machine And Use Cases

Purpose: keep voice input stable while making recording/finalization/paste states explicit.

Scope:

- Extract speech recording state transitions from `SpeechInputCoordinator` into a state model or reducer.
- Separate use cases for start recording, finish recording, final recognition, smart processing, paste, and recovery.
- Keep realtime preview as presentation feedback only.
- Preserve ASR/VAD warm-resource policy and high-memory flush boundary.

Verification:

- Long press, toggle recording, auto-finish, quiet speech, empty recording, wake recovery, paste target regression.
- Existing ASR/VAD and `FinalSpeechGate` checks continue to pass.

### Version D: Provider, Adapter, And Observability Hardening

Purpose: make external systems swappable and diagnosable without leaking experiments into the product path.

Scope:

- Keep DeepSeek as the only active AI provider until another provider passes intent-preservation tests.
- Keep AI, OCR, ASR, paste, keychain, observability, and screen-capture APIs behind adapters.
- Add provider-quality validation fixtures before future providers return to UI.
- Enforce observability privacy boundaries.

Verification:

- Provider route tests.
- Privacy checklist for observability events.
- Manual main-path QA after behavior-affecting changes.

## Verification Gates

For architecture work, choose the narrowest meaningful checks, but do not declare a workflow refactor done without proving the affected path.

Minimum for docs-only architecture changes:

- Links and references point to `docs/ARCHITECTURE.md`.
- Current behavior and historical behavior are separated.
- No old architecture document still presents superseded behavior as current.

Minimum for code architecture changes:

- `git diff --check`.
- Relevant unit/lightweight Swift checks.
- Main voice path remains valid: hotkey, recording, realtime preview, final ASR, paste.
- Screenshot path remains valid when touched: region selection, window selection, cancel, copy/save, OCR/translation.
- UI/interaction changes receive design review or a clearly stated verification gap.
- Build/local install only when explicitly requested by the user according to `AGENTS.md`.

## Documentation Rules

- Current architecture belongs here.
- Chronological implementation details belong in `docs/开发日志.md`.
- UI/visual rules belong in `DESIGN.md`.
- Screenshot translation product specifics belong in `docs/SCREENSHOT_TRANSLATION_SPEC.md`.
- Model setup belongs in `docs/MODEL_SETUP.md`.
- Security/privacy policy belongs in `SECURITY.md` and relevant architecture privacy notes here.
- Old architecture files are migration stubs and must not become current sources again.
