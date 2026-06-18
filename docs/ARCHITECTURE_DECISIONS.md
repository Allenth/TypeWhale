# TypeWhale Architecture Decisions

This document records architecture decisions made during the refactor. New decisions should be appended in reverse chronological order.

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
