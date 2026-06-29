# TypeWhale Architecture Decisions

This document records architecture decisions made during the refactor. New decisions should be appended in reverse chronological order.

## ADR-010: Remove Short-Segment Preview State From The Active Code Path

Date: 2026-06-25

Status: Accepted

Decision:

- The active realtime preview path must not keep dormant short-segment state or reset-window helpers.
- Remove `committedPreviewText`, `realtimeGeneration`, `segmentStartedAt`, `pendingSegmentCommit`, `evaluateRealtimeSegmentCommit`, `commitRealtimeSegment`, `resetRealtimeWindow`, and unused realtime-buffer trimming helpers from active source.
- `SpeechSession.latestPreviewText` means the latest cumulative realtime ASR result for the current recording.
- VAD energy tracking may still drive auto-finish and safety timeouts, but it must not split realtime preview text or reset the realtime audio window.

Reasoning:

- Dormant segmentation code is not harmless: it preserves the wrong mental model and makes future agents likely to reconnect the failed short-segment path.
- The restored 1.2 capsule experience depends on a clean contract: cumulative audio snapshot in, visual catch-up cache out.
- If segmentation is needed for a future streaming ASR design, it should be introduced as a new architecture with its own reducer and review, not by reusing old disabled fields.

Consequences:

- Searches for segment commit/reset-window symbols should return no active source hits.
- Future preview changes should start from ADR-009 and this ADR, not from the 1.3/1.4 short-segment experiment.
- Historical development-log entries may still mention the removed symbols as past work; that history should not be copied back into active implementation.

## ADR-009: Restore 1.2 Capsule Preview Mechanics

Date: 2026-06-25

Status: Accepted

Supersedes: ADR-008's non-prefix replacement strategy

Decision:

- The recording capsule realtime preview should restore the proven 1.2 behavior from `v1.2.42-build199`.
- Realtime preview uses cumulative snapshots from the start of the current recording, not short-pause segmentation or a sliding window that resets on silence.
- `SpeechInputCoordinator.transcribeRealtime` should display the cleaned cumulative preview text directly in the controller and capsule.
- `CapsuleTextBuffer` should keep the 1.2 `refreshedDisplayPreservingLength` strategy, then animate newly appended tail characters with the existing draft timer.
- The first visible preview should start its local fade at index 0, matching 1.2.
- `RecordingCapsuleView` should keep the 1.2 draft timer and fade timer rhythm, alpha floor, and 7-bar waveform behavior unless a future change is explicitly tested against the old app.

Reasoning:

- The user has directly reported that the current capsule is worse than the 1.2 experience.
- The 1.2 implementation already solved the important product job: the user can see what they are saying with enough certainty while speaking.
- The later "non-prefix clean replacement" direction was a reaction to the 1.3 segmented/sliding-window architecture; it should not be treated as a universal capsule display rule.
- Under cumulative snapshots, preserving the current displayed length and refreshing characters is part of the old smoothness, not the root problem.
- The root regression came from changing both the ASR preview architecture and the display layer away from the 1.2 behavior.

Consequences:

- Future capsule work must compare against `v1.2.42-build199` before changing animation or preview-buffer policy.
- If true streaming ASR is introduced later, it needs a new stability reducer and a separate design review; do not reuse the failed short-segment preview path.
- `CapsuleTextBufferCheck` should lock 1.2 behavior, including initial fade at 0 and non-prefix refresh preserving the displayed length.
- Manual QA must include a real recording with natural pauses and silence, because unit tests cannot verify perceived smoothness.

## ADR-008: Capsule Realtime Preview Is A Confidence Anchor With Local Motion Continuity

Date: 2026-06-25

Status: Accepted

Note: Superseded in part by ADR-009. The confidence-anchor principle remains accepted, but the clean non-prefix replacement strategy did not match the 1.2 experience and should not guide current capsule work.

Decision:

- The recording capsule realtime preview exists to help the user clearly see what they are saying while speaking.
- Capsule text animation must preserve certainty and motion continuity: no whole-text flashing, no hard jump as the default transition, and no old/new text mixed by index.
- Append-only ASR updates use a typewriter progression with a short local fade on newly added characters.
- Non-prefix ASR corrections replace the old text cleanly, but must keep a readable new-text head and animate the tail into place.
- Non-prefix corrections must not collapse to one visible character unless the whole target text is that short.
- UI, interaction, animation, layout, and feedback-state changes require design-review skill or independent subagent review before being treated as complete.

Reasoning:

- The user has already experienced better capsule behavior in earlier versions, so regression is a product failure, not just an implementation detail.
- Removing animation avoids one bug but destroys the user's sense of continuity.
- Whole-text fade avoids hard jumps but makes the entire capsule look like it is flashing.
- Showing only one character during a correction makes the recognition feel lost and unstable.
- The correct boundary is local motion: clean semantic replacement, readable head, animated tail, and only newly appearing characters fading in.

Consequences:

- `CapsuleTextBuffer` owns text-stability policy and should remain regression-testable without AppKit.
- `RecordingCapsuleView` owns visual rendering and may use local fade only for the newly appearing tail.
- Future ASR preview strategy changes must preserve the capsule's confidence-anchor role before optimizing for implementation simplicity.
- Manual QA should include long pauses, natural silence, non-prefix ASR corrections, and append-only growth.

## ADR-007: Automatic Smart Rewrite Rules Match Target And Content Separately

Date: 2026-06-25

Status: Accepted

Decision:

- Smart rewrite automatic mode may choose a rewrite mode from both target context and the current final ASR text.
- Each automatic rule declares whether it matches target context, content text, or both.
- Target context means target App name, Bundle ID, and window title.
- Content text means the final local ASR text after trimming and before remote rewrite.
- Manual rewrite preferences still override automatic rules.
- Secure text entry still forces raw mode before any automatic rule is evaluated.

Reasoning:

- App-only routing is too coarse: the same target window can receive a chat reply, a development task, or a meeting summary.
- Content-only routing is too risky: a development window should still default to development-oriented formatting unless a more specific content rule intentionally wins.
- Keeping target and content matching explicit lets users tune automatic behavior without hiding policy in code.

Consequences:

- Default automatic rules may include content-intent rules such as summary/meeting-note phrasing.
- Rule order matters; more specific content-intent rules should appear before broad target rules.
- Stored rule migration must preserve older target-only rules as `matchTarget = true` and `matchContent = false`.
- Progress UI can only estimate from target context before final ASR is available; final routing may become more specific after recognition.

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
- If the process memory footprint reaches the dynamic warning threshold while the app is idle, release ASR/VAD resources and immediately warm-load them again.
- The warning threshold is `min(20GB, max(2GB, total physical memory * 25%))`, so low-memory Macs do not wait until 20GB before self-protection while still avoiding the old 1GB churn.
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

## ADR-011: Capsule Preview Is A Presentation Pipeline With Bounded Realtime Work

Date: 2026-06-26

Status: Accepted

Decision:

- Treat the recording capsule as a presentation pipeline driven by realtime preview events, not as the owner of recording, final ASR, rewrite, translation, or paste workflows.
- `SpeechInputCoordinator` may route realtime preview text into the capsule, but a stuck realtime VAD/ASR snapshot must not permanently block later capsule updates.
- Each realtime preview snapshot must have a short timeout. If the timeout fires, discard that snapshot and continue with the newest pending snapshot.
- Stale realtime callbacks must be ignored after a newer snapshot or timeout has taken ownership.
- Realtime preview should prefer quick user-visible feedback over an extra realtime VAD pass; final ASR still keeps VAD, while preview relies on text filtering to suppress common silence hallucinations.
- Cumulative preview context may be preserved for ASR quality, but snapshot production must avoid the long-recording trap of rewriting all in-memory buffers as the only path. Prefer a validated copy of the current recording file, then a chunked file rewrite, with buffer rewrite only as fallback.
- `RecordingPanel`, `RecordingCapsuleView`, and `CapsuleTextBuffer` stay focused on window presentation, drawing, animation, and local text-buffer progression.

Reasoning:

- The capsule is the user's confidence signal while speaking; it can fail visually even when final ASR and smart rewrite still succeed.
- Realtime preview uses asynchronous local model callbacks. Without a timeout, one lost or very slow callback can leave `realtimeBusy` stuck and prevent later preview text from reaching the capsule.
- Running VAD and ASR sequentially for each preview snapshot can make the first visible text arrive too late, especially because preview snapshots are cumulative. The capsule's product job is confidence feedback, so responsiveness wins here.
- Bounding realtime preview work keeps the visual layer resilient without changing final recognition correctness.
- The user confirmed the cumulative-context path has better quality and fewer nonsense states, so the fix for long-recording freezes should optimize snapshot production rather than returning to short windows or silence segmentation.

Consequences:

- Logs should include realtime preview update and timeout events so future "capsule stopped typing" reports can be separated into ASR-output, realtime-timeout, and UI-animation causes.
- Future capsule changes should not couple main-window status, screenshot flow, rewrite flow, or paste flow into capsule rendering state.

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
