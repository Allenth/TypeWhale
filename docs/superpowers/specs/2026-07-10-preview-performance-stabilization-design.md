# Preview Performance Stabilization Design

**Date:** 2026-07-10
**Status:** Approved for test-stage implementation
**Scope:** Experimental SenseVoice corrected preview and long-form incremental output

## Goal

Keep the preview behavior observed during the first approximately 20 seconds—responsive incremental display and useful recognition quality—stable during recordings lasting minutes or hours. This pass prioritizes a usable experiment. It does not migrate the preview into the future SDK or broadly refactor `SpeechInputCoordinator`.

## Product Boundaries

- The experiment switches and rollback path remain available.
- Recording, authoritative incremental final text, smart processing, and paste behavior remain unchanged.
- Confirmed transcript prefixes remain immutable; only the mutable tail may be corrected.
- Raw audio and incremental evidence remain recoverable.
- The main thread performs no synchronous model, filesystem-capacity, or persistence work.
- A single session has one primary recognition engine. A second full model instance is not introduced in this pass.

## Approaches Considered

1. **UI-only smoothing:** keep the scheduler unchanged and hide latency in the capsule. Rejected because it masks model and queue delay.
2. **Measured single-engine scheduling (selected):** instrument each lane, enforce bounded/latest-only fast work, give fast requests a latency deadline, and admit correction work with explicit fairness and backlog limits.
3. **Dual model executors:** dedicate one model to fast preview and another to correction. Deferred because Build 648 already reached high CPU usage and a second full model may worsen resource contention before single-engine scheduling is measured.

## Design

### Per-request observability

Each `PreviewPipelineRequest` records enqueue time. The pipeline logs lane（通道）, chunk, queue wait, recognition duration, end-to-end duration, audio duration, pending-fast state, and correction backlog at start and completion. Logs must make the 0–20 second and later phases directly comparable.

### Deadline-aware scheduler

- Fast work remains latest-only: a newer pending fast snapshot replaces an older pending snapshot.
- Stop-tail finalization retains highest priority after recording stops.
- During recording, an overdue fast request is selected before correction work.
- Correction remains FIFO（先进先出） and real boundaries are not discarded in this function-first pass. A backlog above two emits an explicit warning and becomes evidence that the single-engine design is insufficient.
- Fairness prevents permanent correction starvation, but never permits an unbounded sequence of corrections ahead of a waiting fast request. When correction backlog reaches two, the fast quota tightens to 1:1 until pressure falls.
- Scheduling decisions are pure and covered by deterministic time-based tests.

Initial test-stage budgets:

- Fast queue wait target: P95（第 95 百分位） ≤ 700ms.
- No more than one pending fast request.
- Correction backlog target: ≤ 2; larger backlogs emit `preview_correction_backlog_warning` without silently dropping authoritative boundaries.
- Capsule animation debt remains ≤ 8 characters.

### Stable context and final authority

The fast lane continues to own immediate display. Correction never overwrites immutable confirmed text and confirms only through a real `PreviewBoundary`. This performance pass does not shorten the 22.5-second correction window or change final transcript authority without recorded evidence that the window itself is the bottleneck.

### Degradation and rollback

- Fast failure: keep the latest visible state and continue with newer fast work.
- Correction failure: mark recovery/degraded state, preserve audio and confirmed text, and continue recording. Backlog warnings preserve FIFO boundaries for this test-stage pass.
- Performance budget miss: log the miss with lane and queue state; do not silently freeze the capsule.
- The experiment can be disabled to return to the stable non-experimental path.

## Verification

1. TDD（测试驱动开发） checks for enqueue timestamps, overdue-fast priority, correction fairness, bounded coalescing, stale session rejection, and temporary-file cleanup.
2. Existing reducer, stop-tail, persistence, coordinator-boundary, and capsule-buffer checks remain green.
3. Full Swift typecheck, build, install, launch, and signing verification.
4. Real installed-app recordings at approximately 1, 10, and 60 minutes. Compare first 20 seconds with later periods using logged queue wait and inference duration.

## Deferred Migration Work

- Extracting the speech-to-text SDK and preview UI module.
- Splitting coordinator ownership into final production services.
- Dual local model executors or a separate lightweight streaming model.
- Cross-platform public API finalization.
