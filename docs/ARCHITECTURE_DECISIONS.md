# TypeWhale Architecture Decisions

This document records architecture decisions made during the refactor. New decisions should be appended in reverse chronological order.

## ADR-006: Prefer Strategy, Coordinator/Use Case, And Command For Extension Points

Date: 2026-06-25

Status: Accepted

Decision:

- Use Strategy for replaceable product capabilities: ASR providers, smart rewrite modes, translation direction, paste behavior, screenshot OCR/translation providers, and future model choices.
- Use Coordinator / Use Case objects for user workflows: speech input, screenshot capture, app lifecycle, permission checks, and paste submission.
- Use Command for discrete user actions that need consistent dispatch or undo semantics: screenshot annotations, toolbar actions, global hotkey actions, and recent-transcription copy/save operations.

Reasoning:

- TypeWhale is becoming a commercial desktop product rather than a small MVP; the cost of adding each new feature directly into a view controller or one coordinator is rising.
- Strategy keeps future model/provider choices isolated without changing stable flows.
- Coordinators already match the product shape, but their responsibilities need sharper boundaries so `SpeechInputCoordinator` and `ScreenshotCoordinator` do not keep absorbing unrelated policy.
- Command is a natural fit for annotation tools, shortcut actions, and undo/redo because those actions are small, repeatable, and user-visible.

Consequences:

- New ASR/OCR/rewrite/translation choices should first be expressed behind a protocol or small strategy object when the behavior is expected to vary.
- View controllers should stay focused on presentation and event forwarding; workflow sequencing belongs in coordinators/use cases.
- New screenshot annotation tools should be designed as commands so undo/delete/save/copy behavior stays predictable.
- Do not introduce a generic abstraction before behavior is stable; extract from verified product behavior, not speculation.

## ADR-005: Release ASR/VAD Resources On Idle, Not After Every Input

Date: 2026-06-25

Status: Accepted

Decision:

- Keep ASR and VAD resources warm while the user is actively typing or speaking.
- Do not unload the native recognizer after every transcription.
- Do not use an idle timer that unloads models after N seconds of inactivity.
- If the process memory footprint reaches the warning threshold while the app is idle, release ASR/VAD resources and immediately warm-load them again.
- The release path must flush the expanded native memory arena without making the next recording pay the cold-load cost.

Reasoning:

- Keeping the recognizer warm gives better continuous-input latency.
- Unloading after every sentence would reduce memory but make the product feel slower and less commercial-ready.
- Letting the recognizer and VAD cache stay resident forever can leave Activity Monitor memory high after long typing sessions.
- A high-memory-only safety net preserves the fast path for active sessions while still providing a way to flush expanded ONNX Runtime arenas.

Consequences:

- `SpeechInputCoordinator` owns the high-memory safety check because it knows whether recording, recognition, rewrite, paste, and realtime preview are active.
- `NativeSenseVoiceBridge` owns actual release of recognizer and native VAD cache.
- Future ASR/OCR/model providers should expose explicit cache-release and warm-load APIs rather than relying on process exit.
- Manual QA should check two paths: continuous dictation should not reload on every sentence, and memory should drop only when idle and above the warning threshold.

## ADR-004: Screenshot Overlay Must Not Activate The Main App Window

Date: 2026-06-25

Status: Accepted

Decision:

- Starting screenshot mode must not call `NSApp.activate(...)` or otherwise bring the TypeWhale main panel to the front.
- Screenshot overlays may order themselves front and become key enough to receive keyboard input, but they must preserve the existing z-order of ordinary app windows.
- If the TypeWhale main panel is hidden, screenshot mode keeps it hidden.
- If the TypeWhale main panel is visible behind another app, screenshot mode keeps it behind.
- If the user explicitly chooses a hovered window in screenshot mode, TypeWhale may raise that selected target window, wait briefly, recapture the screen, and preselect the target window bounds.

Reasoning:

- Screenshot is an observation tool. Triggering it should not mutate the desktop by surfacing TypeWhale's own main panel.
- Window-level selection is an explicit user action. Raising the selected target window there is intentional because the user asked to capture that window, and recapturing avoids saving stale occluded pixels.
- The rule prevents conflicts between "main panel visibility" and "screenshot content" while keeping window capture convenient.

Consequences:

- `ScreenshotCoordinator.begin()` should keep using overlay ordering/key-window behavior instead of app activation.
- Future screenshot features must preserve this distinction: entering screenshot mode is non-activating; choosing a target window may activate/raise that target.
- Tests and manual QA should include a TypeWhale main panel that is hidden, visible behind another app, and visible in front.

## ADR-001: Use Current English Experiment Branch As Architecture Sandbox

Date: 2026-06-13

Status: Accepted

Decision:

- Use the current English experiment line as the refactor sandbox.
- Create `refactor/architecture-preview-pipeline` from it.
- Do not rewrite old release tags.
- Do not directly perform large refactors on stable product lines.

Reasoning:

- The current branch already contains the bilingual and preview experiments that need architectural validation.
- Stable versions should remain useful rollback points.
- A sandbox branch lets us prove the design before migrating it to `main`, `lite`, `pro`, or future product lines.

Consequences:

- The sandbox branch may temporarily diverge from stable releases.
- Migration must be documented and phase-based.
- Stable branches should absorb the refactor as a new version, not as rewritten history.

## ADR-002: Use MVVM + Coordinator, Keep Preview Strategy Testable

Date: 2026-06-13

Status: Accepted, revised after Phase 5 preview experiment

Decision:

- Use MVVM + Coordinator as the main app architecture.
- Use small Clean Architecture-style domain modules where business rules are complex.
- Keep preview strategy outside AppDelegate and infrastructure.
- Do not promote preview strategy into a domain component until the reducer and typing-buffer behavior is proven by tests.

Reasoning:

- AppKit works naturally with ViewControllers and ViewModels.
- Coordinators are a good fit for speech input flow orchestration.
- Preview behavior should be testable without UI or ASR, but the first `PreviewComposer` attempt proved that premature abstraction can make the product feel worse.

Consequences:

- `AppDelegate` should shrink to lifecycle and dependency wiring.
- `RecordingCapsuleView` should stay mostly visual and must not affect final paste.
- Future preview reducer / typing buffer work should be independently testable before it replaces the active capsule path.

## ADR-003: Final Transcription Is Independent From Realtime Preview

Date: 2026-06-13

Status: Accepted

Decision:

- Realtime preview is a temporary listening aid.
- Final transcript must come from full audio transcription.
- Paste and recent history use final transcript, not preview text.

Reasoning:

- Current preview input is rolling snapshot ASR, not true streaming committed text.
- Rolling snapshots can be incomplete, duplicated, or contradictory.
- Full audio transcription has better context and is more reliable.

Consequences:

- Preview and final result may differ.
- UI copy and architecture must not imply preview is final.
- Preview pipeline should optimize perceived responsiveness and readability, not final correctness.
