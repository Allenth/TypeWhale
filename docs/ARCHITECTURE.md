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
- Screenshot Version B has completed its first architecture pass: toolbar command policy, pending-state rules, operation-token invalidation, and translation layout policy now have explicit state/command models and checks. `ScreenshotOverlayView` still owns AppKit rendering and side-effect execution, but this is the accepted boundary for the current pass.

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
- High-memory safety may flush and immediately warm-load the native ASR/VAD arena only when the app is idle and above the dynamic warning threshold.
- Current memory warning threshold source of truth is `MemoryMonitor.warnThresholdMB = min(20GB, max(2GB, totalPhysicalMemoryMB * 25%))`; the high threshold follows that value by about 20% and is capped at 24GB.
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

#### Version A Resolved In First Pass

- `TypeSpeakerApp.applicationDidFinishLaunching` no longer calls `lifecycle.showMainWindow()` unconditionally. Launch now records an explicit hidden-by-default launch visibility policy.
- `SpeechInputCoordinator.beginScreenshotFromHotkey(...)` no longer calls `hideMainWindow()` before entering screenshot mode. Screenshot entry keeps the TypeWhale main-window state unchanged.
- `ScreenshotOverlayView` now limits toolbar interaction during translation pending state to cancel only. Copy, save, OCR, annotation, undo, and done are disabled while translation is in flight.
- Screenshot translation callbacks are guarded by an overlay-local generation token and are invalidated on close, cancel, replace/recapture, and pending recapture.

#### Version A Remaining Review Items

- First-install/default-open policy is not yet product-specified. Current implemented policy is hidden-by-default on normal launch.

#### Version B Resolved In First Pass

- Added `ScreenshotSessionState` with explicit `idle`, `selecting`, `selected`, `windowRecapturePending`, `translating`, `completed`, `cancelled`, and `failed` phases.
- Added `ScreenshotToolbarCommand` availability rules and wired toolbar hit-testing, drawing, pointer handling, and keyboard shortcuts through the same command gate.
- Added `ScreenshotSessionStateCheck` so pending-state command availability is covered without instantiating AppKit overlay windows.
- Build 449 corrected a Build 448 regression: if the overlay already has a usable selection, `idle` or `selecting` must not disable ordinary screenshot toolbar commands. Translation and window-recapture pending still allow cancel only.
- Build 450 corrected screenshot translation layout: line-level translation blocks align to each OCR source line's starting x position, with right-edge fallback only when needed.
- Build 451 added `ScreenshotCommandDispatcher`, a pure command reducer that maps screenshot command context to command availability and effects. `ScreenshotOverlayView` now renders and executes effects, while command policy lives in the testable model.
- Build 452 added `ScreenshotOperationToken` / `ScreenshotOperationTokens`, replacing ad hoc generation counters for window recapture, OCR, screenshot translation, and transient status reset.
- Build 454 added `ScreenshotTranslationLayoutCheck` so Build 450 source-line x alignment and right-edge fallback are covered by a formal lightweight test instead of a temporary shell snippet.
- Build 454 added `docs/SCREENSHOT_OVERLAY_QA.md` as the real installed-app verification checklist for the remaining Version B gate.
- B5 real installed-app overlay QA passed manually on 2026-06-30 using `docs/SCREENSHOT_OVERLAY_QA.md` shortest critical path. Covered ordinary region screenshot, toolbar availability, translation pending cancel-only behavior, stale callback safety by Esc/right-click cancel, copy/save/OCR/translate/annotation/undo, and main-window visibility preservation.

#### Version B Remaining Review Items

- None for the current Version B gate. Future screenshot interaction changes must still include real installed-app overlay QA because Build 448 proved code-level state tests alone are insufficient.

#### Refined Version B Plan

Version B should finish screenshot architecture before Version C starts. The goal is not to add a broad framework; the goal is to make screenshot behavior explainable, testable, and hard to regress.

1. `B2 ScreenshotCommandDispatcher`
   - Status: first pass complete in Build 451.
   - `ScreenshotCommandContext` carries current session state, real usable selection, operation generation, and annotation mode.
   - `ScreenshotCommandDispatcher` returns command availability and `ScreenshotCommandEffect` values such as copy, save, OCR, translate, select tool, undo, done, cancel, or ignore.
   - The dispatcher does not render AppKit views, crop images, call OCR, call DeepSeek, write files, or touch the pasteboard.
   - `ScreenshotOverlayView` keeps rendering, event forwarding, and side-effect execution.

2. `B3 Screenshot Operation Tokens`
   - Status: first pass complete in Build 452.
   - Consolidated translation, OCR, and window recapture invalidation into one explicit operation token model.
   - Cancel, close, replace/recapture, and superseding actions invalidate outstanding callbacks.
   - Old callbacks may finish, but they must not mutate markups, status, pasteboard, saved files, or overlay state.
   - The same token model also guards transient status reset so a newer screenshot operation is not overwritten by an older success timeout.

3. `B4 Screenshot Layout Policy`
   - Status: first pass complete in Build 454.
   - Keep screenshot translation layout policy in `ScreenshotTranslationLayout`.
   - Preserve Build 450 behavior: translation blocks align to source-line starting x; only right-edge overflow may shift left.
   - Do not move line-level translation placement into `ScreenshotOverlayView` drawing code.
   - `ScreenshotTranslationLayoutCheck` is the current lightweight regression for this policy.

4. `B5 Real Overlay Verification Gate`
   - Status: passed manually on 2026-06-30 against installed `1.6.6 (Build 454)`.
   - Verified installed app behavior for ordinary region selection, toolbar buttons, translation pending cancel-only state, stale callback safety, copy/save/OCR/translation/annotation/undo, Esc/right-click cancel, and main-window visibility preservation.
   - Window-selection and recapture behavior remain covered by the QA checklist for future screenshot passes; no blocker remains for entering Version C.
   - Use `docs/SCREENSHOT_OVERLAY_QA.md` as the checklist for this gate.

Exit criteria for Version B:

- Met for the current architecture pass. `ScreenshotCoordinator` / `ScreenshotOverlayView` still execute AppKit side effects, but command policy, pending-state availability, operation invalidation, and layout policy now live behind explicit state/command/layout models.
- Version C may begin next, preserving all screenshot invariants above.

#### Version C Blockers

- `SpeechInputCoordinator` remains the main concentration point for hotkeys, recording, VAD, realtime preview, final ASR, smart rewrite/translation, paste, screenshot entry, and memory safety. Action: split through speech workflow state/use cases after Version A/B stabilize user-visible state.
- Final ASR, smart processing, paste, target tracking, and ASR memory safety are interleaved in one coordinator. Action: define use cases for final recognition, smart processing, paste submission, and idle memory safety before moving logic.

#### Version C Resolved In First Pass

- Build 455 introduced `SpeechWorkflowState`, a pure task-identity and stale-callback gate for the voice workflow.
- `SpeechWorkflowState` now owns the latest submitted task id, completed final task de-duplication, realtime callback acceptance, UI update eligibility, and processed-result submission eligibility.
- `SpeechInputCoordinator` still orchestrates recording, VAD, realtime preview, final ASR, smart processing, paste, target tracking, and memory safety, but old task callbacks now pass through one workflow gate before mutating UI, history, backlog, paste queues, or realtime preview state.
- `SpeechWorkflowStateCheck` covers new-recording invalidation of older tasks, final submission de-duplication, processed-result stale gating, realtime callback acceptance, and the completed-final task retention limit.
- Build 456 introduced `FinalRecognitionUseCase`, which owns the final ASR adapter call, raw ASR response parsing, recognition text cleanup, model-error handling, and empty-result classification.
- `SpeechInputCoordinator` still owns final VAD gating, UI progress, smart rewrite/translation, paste submission, target app lookup, and memory safety. The final recognition boundary now returns only `recognized`, `empty`, or `failed`.
- `FinalRecognitionUseCaseCheck` covers successful final recognition parsing, empty-result classification, model error propagation, and the fake-ASR callback path.
- Build 457 tightened microphone input release: `AudioRecorder` now tracks tap installation, logs explicit input-session release reasons, performs delayed idle release after stop/cancel, and lets background health checks clear any idle residual input session.

#### Version C Next Review Items

- Verify Build 456 installed-app voice main path before extracting the next boundary.
- Extract smart processing next, using the stable `FinalRecognitionOutcome` contract as input.
- Extract paste submission only after smart processing has a stable task/result contract.
- Keep ASR/VAD memory safety in the coordinator until recording/finalizing/pasting state transitions are fully represented in the workflow model.

#### Preview Pipeline Blocker

- `AudioRecorder` advances chunk state and clears `realtimeBuffers` before the final chunk snapshot has been successfully written. If `writeRealtimeSnapshot` fails, the coordinator never receives that final chunk, while the recorder has already discarded the buffers and advanced `realtimeChunkIndex`. Action: make final chunk commit two-phase or otherwise recoverable so the "final chunk snapshots should not be dropped" invariant is true in failure paths.

### Next Section Handoff

The next coding section should start from this document, not from chat history.

Read order:

1. `docs/ARCHITECTURE.md`: stable invariants, review action items, and the staged Version A-D plan.
2. `docs/开发日志.md`: latest Build 454 entry for screenshot layout check and overlay QA gate, Build 453 for active documentation consistency, Build 452 for screenshot operation tokens, Build 451 for screenshot command dispatcher, Build 450 for screenshot translation layout, Build 449 for the screenshot toolbar regression fix, then Build 448 for the original Version B state model work.
3. `native/Sources/Presentation/Screenshot/ScreenshotSessionState.swift`: session state, toolbar command availability, command context, dispatcher, pure command effects, and operation token model.
4. `native/Sources/Presentation/Screenshot/ScreenshotCoordinator.swift`: current screenshot overlay rendering, event forwarding, command effect execution, and token-gated async callbacks.
5. `native/Tests/ScreenshotTranslationLayoutCheck.swift`: current lightweight layout regression for Build 450 translation placement.
6. `docs/SCREENSHOT_OVERLAY_QA.md`: real installed-app checklist required before declaring Version B done.
7. `native/Sources/Application/SpeechWorkflowState.swift`: current pure task identity and stale-callback gate for Version C.
8. `native/Tests/SpeechWorkflowStateCheck.swift`: current lightweight regression for Version C task gating.
9. `native/Sources/Application/SpeechInputCoordinator.swift`: current speech workflow orchestration and still-large concentration point.
10. `native/TypeSpeakerApp.swift`: current hidden-by-default launch policy and explicit main-window entry points.

Recommended next action:

- Continue Version C only after Build 456 installed-app voice path verification. Preserve Build 455 `SpeechWorkflowState` task gate, Build 456 final recognition use-case boundary, Build 449 command availability, Build 450 translation layout, Build 451 command dispatcher boundaries, Build 452 operation-token invalidation, Build 454 formal layout regression, and the 2026-06-30 B5 installed-app overlay QA result.
- Do not start with a broad `SpeechInputCoordinator` rewrite. Next split smart processing behind a small use-case boundary, then paste submission and idle memory safety in small verified steps.
- Preserve the Build 450 behavior: screenshot entry does not own TypeWhale main-window visibility, launch is hidden by default unless an explicit user action opens the main interface, normal screenshot toolbars stay usable after selection, translation/window-recapture pending allow cancel only, and translation blocks align to their OCR source-line starting x.

Current verification baseline:

- Full Swift typecheck passed after Build 456 changes.
- `ScreenshotSessionStateCheck` passed, including dispatcher availability/effect checks and operation-token invalidation checks.
- `ScreenshotTranslationLayoutCheck` passed, preserving Build 450 source-line x alignment and right-edge fallback.
- `SpeechWorkflowStateCheck` passed, preserving Version C task identity and stale-callback gating.
- `FinalRecognitionUseCaseCheck` passed, preserving final recognition response parsing and empty-result classification.
- `git diff --check` passed.
- `./native/build_and_log.sh` installed and opened `/Applications/TypeWhale.app` as `1.6.6 (Build 456)`.
- Manual B5 installed-app overlay QA shortest critical path passed per user report on 2026-06-30.

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
- Code changes must follow the repository build rule in `AGENTS.md`: run `./native/build_and_log.sh`, overwrite `/Applications/TypeWhale.app`, open the installed app, and report any verification gap.

### Version B: Screenshot Session State Machine And Toolbar Commands

Purpose: reduce screenshot coordinator/view state coupling without changing the user-visible workflow.

Scope:

- Introduce `ScreenshotSessionState` for idle, selecting, selected, window-recapture-pending, translating, completed, cancelled, and failed.
- Convert toolbar actions to command-style dispatch with per-state availability.
- Keep annotation rendering in presentation; move action policy out of mouse handlers.
- Make window recapture and translation cancellation generation-based and testable.

Verification:

- Lightweight checks for allowed actions per screenshot state.
- `ScreenshotTranslationLayoutCheck` for screenshot translation placement.
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
- Add a source-of-truth consistency audit for active docs and code comments. Priority terms: memory thresholds, build/install rules, version baselines, cost/token limits, screenshot pending-state semantics, and ASR/VAD warm-resource policy.
- Historical logs and version history may retain old values as historical facts; active docs (`AGENTS.md`, `docs/ARCHITECTURE.md`, PRD, release docs, current code comments) must not present superseded values as current behavior.

Verification:

- Provider route tests.
- Privacy checklist for observability events.
- Consistency audit checklist: `rg` for stale threshold/version/build-rule terms; confirm active docs point to code-level source of truth; record intentional historical references separately.
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
- Code changes must follow `AGENTS.md`: run `./native/build_and_log.sh`, overwrite `/Applications/TypeWhale.app`, open the installed app, and report verification gaps. Pure docs-only changes do not require a build unless requested.

## Documentation Rules

- Current architecture belongs here.
- Chronological implementation details belong in `docs/开发日志.md`.
- Current numeric thresholds and operational policies must point to their code-level source of truth when one exists; do not duplicate stale literals such as memory limits across active docs.
- UI/visual rules belong in `DESIGN.md`.
- Screenshot translation product specifics belong in `docs/SCREENSHOT_TRANSLATION_SPEC.md`.
- Screenshot overlay installed-app verification belongs in `docs/SCREENSHOT_OVERLAY_QA.md`.
- Model setup belongs in `docs/MODEL_SETUP.md`.
- Security/privacy policy belongs in `SECURITY.md` and relevant architecture privacy notes here.
- Old architecture files are migration stubs and must not become current sources again.
