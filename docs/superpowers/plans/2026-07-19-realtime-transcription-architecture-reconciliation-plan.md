# Realtime Transcription Architecture Reconciliation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task. Do not use broad batch edits. Do not implement more than one task per development turn.
>
> **先读目标锁:** 主胶囊、候选胶囊、旁路胶囊、实时预览、最终粘贴相关开发，必须先读 `docs/superpowers/plans/2026-07-20-main-capsule-goal-lock.md`。该文档锁定：目标是重构主胶囊，不是扶正候选胶囊；旁路/候选只是迁移期观察工具。
>
> **暂停开发后的重整计划:** 本文件取代“边开发边补计划”的执行方式。后续任何实时预览、候选交付、final ASR、旧链路迁移相关开发，必须先读本文件，再读历史计划。
>
> **硬规则:** 每次只改一个点。一个 Task 必须包含 RED、GREEN、聚焦回归、安装验证、真实录音证据、计划更新，全部完成后才能进入下一个 Task。2026-07-19 起，普通 `./native/build_and_log.sh` 只做 install-only 覆盖安装、不编译、不 bump；只有完整版本更新才重新编译。

**Goal:** 重新搭建一套分层清晰的实时转录架构容器，并把旧实时预览链路中已经验证有效的质量机制逐项移植进去，让预览和最终粘贴同时具备“快、稳、可解释、可回退”。

**Architecture:** 新链路不是为了用一套未经验证的新识别策略替代旧方案；它是新的承载容器。Provider 负责音频和识别请求，Reconciler/Reducer 负责文本状态，Projector/UI 只负责展示，FinalDeliveryUseCase 负责最终来源仲裁。旧链路是经验来源和验收基线：它的成熟机制（VAD 切分、fast/correction 分级、stopTail、幻觉过滤、时间戳校验、动态超时、详细日志）必须逐项迁移到新架构对应层，迁移完成并通过真实录音验收后，旧壳才允许退休。

**Tech Stack:** Swift 5, Foundation `AsyncStream`/actor, Sherpa-onnx SenseVoice, Silero VAD, standalone Swift `*Check.swift`, source boundary `*BoundaryCheck.sh`, `LaunchDiagnostics`, `./native/build_and_log.sh` install-only by default, `./native/build_and_log.sh --full-version` for compiling new app builds, real installed-app recording validation.

## Current Workspace Status / 施工前现场

- Current branch/worktree: `codex/realtime-transcription-shadow` in `.worktrees/realtime-transcription-shadow`.
- Build 778 changes are currently uncommitted. They modified `FinalDeliveryUseCase`, version docs, build metadata, and related tests.
- Development is paused by product owner decision. Do not add runtime behavior changes until this plan is accepted.
- Before the next coding task, the implementer must decide with the product owner whether to keep, revert, or amend Build 778 changes. No silent commit.

## Problem Statement

Recent real recordings show the new candidate path can be `completed=true` and `tail_gap_ms=0`, yet still produce bad final text:

- “代码设计计排查查一下下...” while full final ASR on the same wav was clean.
- “案用户体验验不要了吗？？？” while full final ASR was “怎么可能有这样的方案呢？用户体验不要了吗？”
- “了用户体验不要了吗？？” while full final ASR was “怎么可能用这样的方案呢？用户体验不要了吗？”

The failure is not a single UI bug. It is a missing quality contract between:

```text
ASR snapshot output
→ boundary reconciliation
→ TranscriptState confirmed + volatile
→ CandidateDeliverySnapshot
→ FinalDeliveryUseCase
→ paste
```

The plan must therefore fix the contracts one by one, not patch symptoms.

## Product Invariants

- The capsule must stay smooth. Data quality work must not block UI rendering.
- The UI must not process transcript data. UI consumes `PreviewViewState` / `PreviewDisplaySnapshot` only.
- `completed=true` means the provider reached a terminal state. It does not by itself mean the text is good enough to paste.
- Final ASR is a fallback and comparison source, not unconditional authority.
- Candidate transcript is the intended primary source only when it passes explicit quality gates.
- Old path capabilities are a proven experience baseline. New path must not retire old capability until parity evidence exists.
- Old path and new path are not competing recognition products. The old path provides proven mechanisms; the new path provides cleaner ownership boundaries for those mechanisms.
- New-path `completed`, `tail_gap_ms=0`, or “can display text” does not prove old capability migration is complete.
- Every fallback must log a reason that a non-developer can understand.

## Architecture Comparison

### Old realtime preview architecture

Main files:

- `native/Sources/Application/RealtimePreview/ExperimentalRealtimePreviewPipeline.swift`
- `native/Sources/Domain/RealtimePreview/PreviewTranscriptReducer.swift`
- `native/Sources/Domain/RealtimePreview/BoundaryCenteredPreviewPlanner.swift`
- `native/Sources/Application/RealtimePreview/PreviewRequestScheduler.swift`
- `native/Sources/Domain/Text/RecognitionTextFilter.swift`
- older orchestration in `SpeechInputCoordinator`

Data flow:

```text
Recorder / realtime snapshots
→ BoundaryCenteredPreviewPlanner
→ PreviewRequestScheduler
→ ExperimentalRealtimePreviewPipeline
→ PreviewTranscriptReducer
→ PreviewDisplaySnapshot
→ capsule
```

Strengths:

- Mature user-experience heuristics from many builds.
- `fast` lane only feeds provisional text; `correction` and `stopTail` carry more authority.
- `stopTail` has a distinct lane and higher priority during stop finalization.
- VAD-aware boundary planner waits for voice pause before soft boundaries and uses hard limit only as a fallback.
- Boundary correction windows are centered around the boundary and can be wider than the new 8-second suffix window.
- Timeout budget is dynamic: correction/stopTail budget scales with audio duration.
- `RecognitionTextFilter` suppresses known silence hallucinations and punctuation noise.
- Detailed per-request logs exist: start, done, budget miss, backlog warning, timeout, recovery.

Weaknesses:

- Too much orchestration is concentrated around `SpeechInputCoordinator` and main-actor flow.
- State, scheduling, text reduction, UI update, and final handling are harder to reason about as separate contracts.
- Old architecture is not ideal for multi-provider online/local unification.
- Because it evolved through patches, it is hard to safely add MiMo/Doubao/local provider parity without increasing coupling.
- Some logic is experience-proven but not isolated enough as reusable domain rules.

### Old Path Capability Migration Backlog / 旧链路能力拆分任务池

This backlog records the old-path mechanisms that must be preserved as product capabilities while moving them into the new unified architecture. These are not implementation tasks yet; after the new-path walkthrough, each item must be mapped to the correct new-layer owner and either merged into an existing Task or promoted into its own Task.

#### O1: VAD-aware soft boundary planning / 语音活动感知切分

**Old evidence:**

- `BoundaryCenteredPreviewPlanner.proposeBoundary(...)` proposes a soft boundary only when `chunkDuration >= 10s` and `voiceActive == false`.
- `AudioRecorder.processCapturedBuffer(...)` marks hard/soft chunk finalization based on `hardReached || (softReached && !realtimeVoiceActive)`.

**Product capability:**

- Do not cut a phrase only because a timer fired.
- Prefer natural pause boundaries; use hard limit only as a fallback.

**Target new-layer owner:**

- Provider/data layer, likely `SenseVoiceSnapshotProvider` plus a new `RealtimeBoundaryPlanner`.
- UI must not receive or interpret VAD state.

**Acceptance evidence:**

- RED test: active speech at 11 seconds does not propose soft boundary.
- RED test: inactive speech after 10 seconds proposes `voicePause`.
- RED test: active speech at 18 seconds proposes `hardLimit`.
- Real recording: natural pause then continue does not duplicate or lose seam text.

#### O2: Fast/correction authority separation / fast 只展示，correction 才转正

**Old evidence:**

- `PreviewTranscriptReducer.apply(.fast)` only updates `provisionalFastTextByChunk` and `mutableTailText`.
- `PreviewTranscriptReducer.apply(.correction)` is the path that appends `confirmedSegments`.

**Product capability:**

- Fast results keep the capsule responsive.
- Stable/final text must be more conservative than fast display text.

**Target new-layer owner:**

- `SenseVoiceBoundaryReconciler` must receive request authority/source.
- `SenseVoiceSnapshotProvider` must label requests as provisional fast, correction, final tail, or boundary correction.

**Acceptance evidence:**

- RED test: two fast snapshots cannot create confirmed/finalized segments.
- RED test: correction may confirm only after seam verification.
- Real recording: capsule still出字快, but paste does not trust text that only appeared in fast lane.

#### O3: Conservative seam verification / 边界拼接不能硬拼

**Old evidence:**

- `PreviewTranscriptReducer.timestampAlignment(...)` requires matching tokens and absolute timestamp distance within `0.75s`.
- Without timestamps, suffix/prefix overlap must be at least 2 tokens.
- One repeated token is explicitly not enough; tests reject weak overlap.

**Product capability:**

- When two windows disagree, do not silently concatenate both sides.
- Example failure to prevent: `今天我们讨论公司` + `功功能可以优化` → `今天我们讨论公司功功能可以优化`.

**Target new-layer owner:**

- `SenseVoiceBoundaryReconciler`.
- Possibly a dedicated seam-quality report that is visible in diagnostics but not UI.

**Acceptance evidence:**

- RED test: one-character overlap does not confirm seam.
- RED test: conflicting seam sets recovery/uncertain state instead of confirming both sides.
- Real recording: “今天我们讨论功能优化” does not produce “公司功功能”.

#### O4: StopTail lane / 停止录音专用收尾

**Old evidence:**

- `PreviewRequestScheduler.beginStopFinalization(...)` stores `pendingStopTail`.
- `PreviewRequestScheduler.complete(...)` gives `pendingStopTail` priority over queued corrections.
- `ExperimentalRealtimePreviewPipeline.finishWhenCorrectionsDrained(...)` creates a `.stopTail` request.
- `PreviewTranscriptReducer.preferredTail(...)` treats `.stopTail` specially and uses its correction text directly.

**Product capability:**

- Stop recording must trigger a final tail pass that specifically protects the last spoken words.
- It must not be treated as a normal periodic correction.

**Target new-layer owner:**

- `SenseVoiceShadowScheduler` for priority.
- `SenseVoiceSnapshotProvider` for final-tail request creation.
- `SenseVoiceBoundaryReconciler` for final-tail authority.

**Acceptance evidence:**

- RED test: finish enqueues one finalTail request if audio exists.
- RED test: finalTail outranks queued correction after the active request completes.
- RED test: finalTail does not duplicate overlap with confirmed tail.
- Real recording: 20-second and 2-minute recordings preserve the final phrase.

#### O5: Realtime hallucination/noise filter / 实时幻觉过滤

**Old evidence:**

- `RecognitionTextFilter.isMeaningfulRealtimePreviewText(...)` filters known silence hallucinations.
- The old blacklist includes Chinese filler/noise and Latin hallucinations such as `yeah`, `the`, `ok`, `uh`, `um`.
- It also rejects repeated identical preview, very short fragments, suspicious punctuation, and short Latin noise mixed with CJK.

**Product capability:**

- Do not display or deliver obvious model hallucinations generated from silence, breath, or noise.
- Do not delete a real spoken “Yeah, 我们继续...” style utterance.

**Target new-layer owner:**

- Domain/data layer, not UI.
- Likely `RealtimeRecognitionHallucinationFilter` consumed by `SenseVoiceSnapshotProvider` before events are emitted.

**Acceptance evidence:**

- RED test: `"Yeah"` at start is suppressed.
- RED test: `"Yeah我们继续"` is not suppressed.
- RED test: suppressed output does not clear existing confirmed/volatile text.
- Real recording: start silence does not produce visible or pasted hallucination.

#### O6: Dynamic service budget and scheduling fairness / 动态预算与调度公平

**Old evidence:**

- `ExperimentalRealtimePreviewPipeline.previewTimeoutSeconds(...)` uses `2.5s` for fast, `max(6,min(12,duration*2+2))` for correction, and `max(6,min(14,duration*2+3))` for stopTail.
- `PreviewRequestScheduler` replaces pending fast snapshots with newer ones, keeps correction backlog, limits consecutive fast completions, and lets stopTail outrank queued correction.

**Product capability:**

- UI remains fast without starving correction.
- Longer correction/final-tail windows are not failed by a fixed tiny budget.

**Target new-layer owner:**

- `SenseVoiceShadowScheduler` and provider diagnostics.
- No UI changes.

**Acceptance evidence:**

- RED test: pending fast coalesces to latest.
- RED test: correction runs after configured fast streak/backlog pressure.
- RED test: finalTail has larger allowed service budget than normal fast.
- Logs show service budget decisions at request level.

#### O7: Per-request observability / 逐请求可观测性

**Old evidence:**

- Old pipeline logs `preview_request_start`, `preview_request_done`, `preview_request_timeout`, `preview_fast_budget_miss`, `preview_correction_backlog_warning`, and recovery events.

**Product capability:**

- When real recording fails, logs must show which request caused it: fast, correction, boundary correction, finalTail, timeout, skipped, degraded, or conflict.

**Target new-layer owner:**

- `SenseVoiceSnapshotProvider` and `SenseVoiceShadowScheduler`.
- Final selection logs belong in `FinalDeliveryUseCase`.

**Acceptance evidence:**

- RED/source-boundary test: every request has request_id, kind, queue_ms, audio_ms, recognition_ms/total_ms, and outcome.
- Real recording: a 2-minute session can be diagnosed from logs without guessing.

#### O8: Bounded display projection / 有界显示窗口

**Old evidence:**

- `PreviewTranscriptReducer.publishIfChanged(...)` keeps the visible capsule bounded by prioritizing volatile tail and backfilling recent confirmed text.

**Product capability:**

- Long recordings must not make the capsule render the whole transcript.
- UI display size and final delivery text are separate concepts.

**Target new-layer owner:**

- `PreviewStateProjector` / presentation projection layer.
- Not Provider, not FinalDelivery.

**Acceptance evidence:**

- RED test: display remains within visible limit while delivery snapshot remains complete.
- Real recording: 2-minute preview remains visually stable and final paste remains complete.

### New unified transcription architecture

Main files:

- `native/Sources/Infrastructure/RealtimeTranscription/SenseVoiceSnapshotProvider.swift`
- `native/Sources/Infrastructure/RealtimeTranscription/SenseVoiceBoundaryReconciler.swift`
- `native/Sources/Infrastructure/RealtimeTranscription/SenseVoiceShadowScheduler.swift`
- `native/Sources/Application/RealtimeTranscription/TranscriptionSession.swift`
- `native/Sources/Domain/RealtimeTranscription/TranscriptReducer.swift`
- `native/Sources/Application/RealtimeTranscription/PreviewStateProjector.swift`
- `native/Sources/Application/RealtimeTranscription/ProductionPreviewTextCoordinator.swift`
- `native/Sources/Application/FinalDeliveryUseCase.swift`
- `native/Sources/Application/FinalRecognitionUseCase.swift`

Data flow:

```text
AudioFrame
→ TranscriptionProvider
→ TranscriptionEvent
→ TranscriptionSession / TranscriptReducer
→ PreviewViewState
→ ProductionPreviewTextCoordinator
→ capsule

CandidateDeliverySnapshot / final ASR / preview fallback
→ FinalDeliveryUseCase
→ paste
```

Strengths:

- Clearer layer ownership: Provider, Reconciler, Reducer, Projector, UI, FinalDelivery.
- `AsyncStream<TranscriptionEvent>` makes provider output a reusable contract.
- `TranscriptState` is a single source for confirmed and volatile text.
- `FinalDeliveryUseCase` moves final text choice out of `SpeechInputCoordinator`.
- Provider diagnostics now include tail gap, discarded requests, boundary correction counters, seam confidence, service time.
- Better long-term foundation for local SenseVoice, MiMo, Doubao, and future providers.

Weaknesses observed so far:

- `completed=true` is treated too much like “quality approved”.
- `FinalDeliveryUseCase` currently has a direct candidate shortcut that can bypass `FinalRecognitionUseCase.shouldUseCandidatePreviewCache`.
- Candidate quality gates are not explicit: no abnormal-short gate, no repeated-character gate, no orphan-prefix gate, no punctuation-storm gate.
- `SenseVoiceBoundaryReconciler` does not receive enough lane/source authority. Fast snapshots can participate in the same reconciliation path as correction snapshots.
- New path has only partial old-path migration: content overlap exists, but VAD-aware boundary planning, stopTail semantics, hallucination filtering, dynamic budgets, and per-request observability are incomplete.
- Current boundary correction cannot edit already-confirmed historical segments; this must be reflected in stage expectations.
- Real logs expose cases where final ASR is cleaner than candidate and cases where candidate is better than final. Therefore the final decision must be evidence-based, not source-biased.

### New Path Container Audit / 新链路容器审计

This section records what the new path already provides as architecture container, and which old-path capabilities have not yet been migrated. The purpose is to prevent the team from mistaking “new container exists” for “old product behavior has been preserved.”

#### Confirmed container strengths

- `TranscriptionProvider` defines a common event-producing boundary: `start`, `append(AudioFrame)`, `finish`, `cancel`, and `events()`.
- `TranscriptionSession` owns provider lifecycle, provider epoch, event consumption, cancellation, completion, and state broadcasting.
- `TranscriptReducer` is simple and mostly policy-free: it applies ordered events into `confirmedSegments`, `volatileText`, lifecycle, failure, and connection state.
- `PreviewStateProjector` keeps display projection bounded by `visibleCharacterLimit`; this is the right layer for capsule-visible text trimming.
- `SenseVoiceSnapshotProvider` already consumes PCM directly and can expose diagnostics including tail gap, service time, discarded requests, boundary correction counters, and seam confidence.
- `SenseVoiceShadowScheduler` is a pure scheduler, separate from UI and model execution.
- `FinalDeliveryUseCase` exists as a separate Application-layer final source selector, which is the correct owner for paste-source arbitration.

#### Confirmed migration gaps

- Snapshot trigger timing is still fixed-clock based: `firstFastSeconds=0.5`, `fastIntervalSeconds=2`, `correctionIntervalSeconds=6`. It does not yet use VAD/voice-active boundaries like the old path.
- Local final-tail exists as a stop-time enqueue, but it is represented as `.correction`, not a distinct `.finalTail` authority. Therefore old stopTail semantics are only partially present.
- `SenseVoiceBoundaryReconciler.consume(...)` receives recognition content but not lane authority. It cannot distinguish “fast may display only” from “correction/finalTail may confirm”.
- `SenseVoiceBoundaryReconciler.consumeBoundaryCorrection(...)` sets `previous` and volatile tail, but does not rewrite already-confirmed historical segments. Boundary correction is therefore recovery evidence, not full historical repair.
- New provider path does not yet apply the old realtime hallucination filter before emitting transcript events.
- `maximumServiceMilliseconds` is a fixed provider-level number. It is diagnostic only; slow-but-successful recognition still publishes text, but there is no old-style dynamic per-lane timeout/budget contract.
- Per-request logs are not yet equivalent to old `preview_request_start/done/timeout/budget/backlog` logs.
- `CandidateDeliverySnapshot(state:)` currently assembles delivery text as `state.confirmedText + state.volatileText` without a dedicated overlap/de-duplication assembler.
- Build 778 `FinalDeliveryUseCase` trusts shadow-runtime completed candidates directly, bypassing candidate-vs-preview quality checks. This is incompatible with the corrected principle that `completed` is terminal lifecycle, not quality approval.

#### New path reading conclusion

The new path should continue as the architectural container. The next plan revision must not ask developers to “replace old with new.” It must ask them to migrate each old-path capability into one new owner:

| Old capability | New owner |
| --- | --- |
| VAD-aware boundaries | Provider/data planner |
| fast display vs correction confirmation | Provider request authority + Reconciler |
| conservative seam verification | Reconciler |
| stopTail | Scheduler + Provider + Reconciler authority |
| hallucination filter | Domain/data filter before event emission |
| dynamic budget/fairness | Scheduler/provider diagnostics |
| request-level logs | Provider/Scheduler |
| bounded display | Projector/UI projection |
| final source arbitration | FinalDeliveryUseCase |

## Decision

Status: **Corrected after product-owner review**

Decision: Continue using the new unified architecture only as a migration container, but do **not** treat the new candidate/shadow-runtime path as final-delivery authority. Product-owner review corrected the execution target: the candidate path has repeatedly failed to produce reasonable final text, so the immediate product path is to restore the old proven path as the final delivery source while keeping the candidate path for display, diagnostics, and isolated comparison only.

Rejected:

- Reverting wholesale to the old realtime preview architecture.
- Trusting candidate merely because `completed=true`.
- Trusting final ASR merely because it has full audio context.
- Letting UI or capsule code repair text.
- Combining Provider/Reconciler/FinalDelivery changes in a single task.
- Testing as if “a quality-passing candidate may still be a desired final winner.” That was the wrong target after real usage showed the candidate path itself is not reliable enough.

Required pattern:

```text
Old mechanism
→ identify responsibility
→ port into new layer
→ add RED test
→ implement minimal GREEN
→ install build
→ real recording gate
→ update this plan
```

## Global Execution Rules

- One task = one responsibility boundary.
- No task may modify more than one major boundary unless its task title explicitly says it is a wiring task.
- Any task touching `FinalDeliveryUseCase` must not modify Provider/Reconciler in the same turn.
- Any task touching Provider/Reconciler must not modify UI/presentation in the same turn.
- Any task touching UI must not modify text production or final delivery.
- `SpeechInputCoordinator` may only wire dependencies and log. It must not receive new transcript algorithms.
- All behavior changes require RED first. The failing assertion must represent a real or product-relevant failure.
- Real installed-app validation is not optional for behavior tasks.
- If a real recording fails a gate, stop. Do not proceed to the next task.

## Current Known Issues To Track

1. Candidate completed but abnormal short:
   - AEB0EA96 and DB1212B7 produced 13/11 candidate chars while full final ASR produced 21 clean chars.
2. Candidate contains short repeated characters:
   - “设计计”, “排查查”, “一下下”, “体验验”.
3. Candidate can start with orphan prefix:
   - “案用户...”, “了用户...” appear to be tail fragments, not sentence starts.
4. Candidate direct shortcut bypasses downstream candidate-vs-preview quality gate.
5. Fast/correction authority separation is weaker in new path than old path.
6. Old hallucination filter is not fully applied to new provider/reconciler path.
7. New scheduler lacks old per-request observability and dynamic timeout/budget semantics.
8. Boundary correction is implemented only for recovery-triggered conflict, not full VAD/hard-boundary parity.

## Old Capability → Execution Task Map / 旧能力到执行任务映射

| Old capability | Capability ID | Execution task |
| --- | --- | --- |
| VAD-aware boundaries | O1 | Task 8 + Task 9 |
| fast display vs correction confirmation | O2 | Task 5 |
| conservative seam verification | O3 | Task 5 |
| stopTail | O4 | Task 6 |
| hallucination/noise filter | O5 | Task 7 |
| dynamic budget/fairness | O6 | Task 10 |
| request-level logs | O7 | Task 3 |
| bounded display projection | O8 | Already in `PreviewStateProjector`; locked by Task 11 parity |
| final source arbitration | new-path responsibility | Task 1 + Task 4 |

## Revised Execution Order / 重排后的执行顺序

The execution order is intentionally not “prove the candidate path can win.” It is:

```text
1. Restore old proven path as final-delivery authority.
2. Ensure candidate/shadow-runtime output cannot become final paste authority.
3. Keep candidate/shadow-runtime only as display/diagnostic/migration evidence.
4. Move old proven mechanisms into the new container one by one.
5. Verify parity before any future authority transfer.
```

### Product-Owner Correction / 2026-07-19

The previous Task 1 acceptance target was wrong. It asked the user to test whether “quality-passing candidate can still win.” The user rejected that premise: the candidate path has already proven it cannot reliably output reasonable final content. Therefore the necessary test is not “can candidate win”; the necessary test is:

```text
candidate path never wins final paste
old proven path / full final fallback owns final paste
candidate path remains observable but non-authoritative
```

Build 779's `CandidateTranscriptQualityGate` remains useful only as a safety net and diagnostic classification layer. It must not be used as proof that the candidate path is product-ready.

### Task 1A: Restore Old Path As Final Delivery Authority / 旧路径恢复为最终交付权威

**Purpose:** Correct the final-delivery source order. The final paste must come from the old proven path or final ASR fallback, not from the new candidate/shadow-runtime path.

**Files:**

- Modify: `native/Sources/Application/FinalDeliveryUseCase.swift`
- Modify: `native/Sources/Application/RealtimeTranscription/LegacyPreviewShadowAdapter.swift` only if a cleaner old-path snapshot is needed.
- Modify: `native/Tests/FinalDeliveryUseCaseCheck.swift`
- Create: `native/Tests/FinalDeliveryOldPathAuthorityCheck.swift` if the existing test file becomes too broad.
- Modify docs/version history after GREEN and build.

**New contract:**

```text
legacyCandidateSnapshot completed + meaningful
→ may be used as candidate-preview-cache final source

shadowRuntimeSnapshot completed + meaningful
→ diagnostic/display only; must not directly win final paste

shadowRuntimeSnapshot present but legacy missing
→ do not paste shadow directly; call full final ASR, with realtime preview fallback if final is empty/implausibly short
```

**RED tests:**

- [ ] completed shadow-runtime candidate with clean text must still call final ASR when legacy is missing.
- [ ] completed legacy candidate may win when meaningful.
- [ ] completed shadow-runtime candidate must not suppress a meaningful legacy candidate.
- [ ] final log reason must include `shadow_authority=disabled` or equivalent.

**Expected RED against Build 779:**

- Current `FinalDeliveryUseCase` still lets a quality-accepted `.shadowRuntimeCache` candidate return `source="candidate-preview-cache"` without calling final ASR.

**GREEN implementation boundary:**

- Change only final source arbitration.
- Do not edit Provider/Reconciler.
- Do not edit UI/capsule.
- Do not delete candidate runtime.
- Keep `CandidateTranscriptQualityGate` only for diagnostics/safety classification.

**Real validation:**

- The user does not need to test whether candidate is good.
- The user only needs to verify that final paste no longer comes from `shadow-runtime-cache` candidate authority.
- Logs must show final source and the disabled candidate authority reason.

### Task 0: Freeze Current Baseline And Decide Build 778 Fate

**Purpose:** Prevent hidden drift before more work. This task changes no runtime behavior.

**Files:**

- Modify: `docs/superpowers/plans/2026-07-19-realtime-transcription-architecture-reconciliation-plan.md`
- Optional commit/stash action only after product-owner confirmation.

**Allowed:**

- Record current git status.
- Record whether Build 778 is kept, reverted, or amended.

**Forbidden:**

- No Swift source changes.
- No build number bump.
- No behavior fix.

**Steps:**

- [ ] Run `git status --short`.
- [ ] Decide explicitly: keep Build 778 changes, revert them, or amend them under a later Task.
- [ ] Write the decision into this file under “Baseline Decision Log”.
- [ ] If keeping Build 778, add a note that it is not considered fully accepted until Task 1 quality gate passes.

**Exit Gate:**

- Baseline decision is written.
- No hidden worktree ambiguity remains.

### Task 1: Candidate Delivery Quality Gate / 候选交付质量门

**Purpose:** Fix the immediate class of failures where candidate is `completed=true` but clearly unfit for paste.

**Files:**

- Create: `native/Sources/Domain/RealtimeTranscription/CandidateTranscriptQualityGate.swift`
- Modify: `native/Sources/Application/FinalDeliveryUseCase.swift`
- Modify: `native/Tests/FinalDeliveryUseCaseCheck.swift`
- Create: `native/Tests/CandidateTranscriptQualityGateCheck.swift`
- Modify docs and version history only after GREEN.

**Consumes:**

- `CandidateDeliverySnapshot.text`
- `CandidateDeliverySnapshot.lifecycle`
- `realtimePreviewFallbackText`
- final ASR result via existing `FinalRecognitionUseCase`

**Produces:**

```swift
struct CandidateTranscriptQualityReport: Equatable, Sendable {
    enum Decision: Equatable, Sendable {
        case accept
        case reject(Reason)
    }

    enum Reason: String, Equatable, Sendable {
        case notCompleted
        case empty
        case abnormalShortAgainstPreview
        case repeatedShortUnit
        case orphanLeadingFragment
        case punctuationStorm
    }

    let decision: Decision
    let normalizedCandidateText: String
}
```

**Quality rules for first implementation:**

- Reject if lifecycle is not `.completed`.
- Reject if text is not meaningful after `cleanRecognitionText`.
- Reject if candidate is less than 70% of preview length and preview has at least 12 meaningful CJK characters.
- Reject obvious repeated single CJK character pairs inside words, e.g. “体验验”, “排查查”, “下下”, unless the whole word is a legitimate repetition phrase from an allowlist.
- Reject orphan leading fragment when candidate begins with one CJK character followed by a longer phrase and final/preview context suggests it is a suffix fragment. Initial heuristic: leading text count is 1 and the second through fifth characters form a meaningful phrase, e.g. “案用户...”, “了用户...”.
- Reject punctuation storm: punctuation count > max(2, semantic character count / 2).

**RED tests:**

- [ ] Candidate `"案用户体验验不要了吗？？？"` with preview `"怎么可能有这样的方案呢？用户体验不要了吗？"` must reject with `.repeatedShortUnit` or `.orphanLeadingFragment`.
- [ ] Candidate `"了用户体验不要了吗？？"` with preview `"怎么可能用这样的方案呢？用户体验不要了吗？"` must reject with `.orphanLeadingFragment` or `.abnormalShortAgainstPreview`.
- [ ] Candidate `"今天我们讨论功能优化"` with preview `"今天我们讨论功能优化"` must accept.
- [ ] Candidate `"今天我们讨论功能优化这样的一个情况..."` longer than preview must accept even when final ASR is shorter.
- [ ] In `FinalDeliveryUseCaseCheck`, rejected completed candidate must call final ASR once and return final text when final is meaningful.

**GREEN implementation boundary:**

- `CandidateTranscriptQualityGate` is pure domain logic.
- `FinalDeliveryUseCase` may call the gate.
- Do not change `SenseVoiceSnapshotProvider`.
- Do not change `SenseVoiceBoundaryReconciler`.
- Do not change UI.

**Logs:**

Add `quality=accepted|rejected` and `quality_reason=...` to `final_delivery_selected`.

**Real validation:**

- Record “用户体验不要了吗” twice.
- Expected: if candidate is short/repeated/orphan-leading, final ASR is used and paste is clean.
- Record “今天我们讨论功能优化...” 25 seconds.
- Expected: candidate may still win if it passes quality gate and final is shorter/worse.

**Exit Gate:**

- No repeated-character paste for known samples.
- No orphan-leading paste for known samples.
- Candidate still wins when it is complete and cleaner than final.

**Implementation Detail Lock:**

The first implementation must be a pure gate. It must not call ASR, inspect audio, read UI state, or mutate `TranscriptState`.

Create `native/Sources/Domain/RealtimeTranscription/CandidateTranscriptQualityGate.swift` with this shape:

```swift
struct CandidateTranscriptQualityGate: Sendable {
    func evaluate(
        candidate: CandidateDeliverySnapshot?,
        realtimePreviewFallbackText: String,
        languageMode: RecognitionLanguageMode
    ) -> CandidateTranscriptQualityReport
}
```

`CandidateTranscriptQualityReport.normalizedCandidateText` must be the cleaned candidate text that would be delivered if accepted. `FinalDeliveryUseCase` must depend on the report decision, not call `candidateSnapshot.isDeliverable(...)` as the final approval.

Add RED tests to `native/Tests/CandidateTranscriptQualityGateCheck.swift`:

```swift
precondition(
    gate.evaluate(
        candidate: CandidateDeliverySnapshot(
            text: "案用户体验验不要了吗？？？",
            source: .shadowRuntimeCache,
            lifecycle: .completed
        ),
        realtimePreviewFallbackText: "怎么可能有这样的方案呢？用户体验不要了吗？",
        languageMode: .chinese
    ).decision != .accept
)

precondition(
    gate.evaluate(
        candidate: CandidateDeliverySnapshot(
            text: "今天我们讨论功能优化",
            source: .shadowRuntimeCache,
            lifecycle: .completed
        ),
        realtimePreviewFallbackText: "今天我们讨论功能优化",
        languageMode: .chinese
    ).decision == .accept
)
```

Add RED tests to `native/Tests/FinalDeliveryUseCaseCheck.swift`:

```swift
// A completed shadow-runtime candidate with repeated short units must not bypass final ASR.
let badCandidate = CandidateDeliverySnapshot(
    text: "代码设计计排查查一下下到底哪里导致现在的问题。",
    source: .shadowRuntimeCache,
    lifecycle: .completed
)
let fake = FakeFinalASR(response: .success([
    "text": "代码设计排查一下到底哪里导致现在的问题。",
    "duration_sec": 0.5,
    "engine": "fake-final"
]))
let outcome = deliver(
    useCase: FinalDeliveryUseCase(recognitionUseCase: FinalRecognitionUseCase(transcriber: fake)),
    shadow: badCandidate,
    legacy: nil,
    preview: "代码设计排查一下到底哪里导致现在的问题。",
    reRecognize: false,
    configuration: configuration
)
precondition(outcome.text == "代码设计排查一下到底哪里导致现在的问题。")
precondition(fake.transcribeCallCount == 1)
```

Expected first RED: the current Build 778 shortcut returns candidate directly and the fake final ASR is not called.

Task completion must update this plan with:

- exact rejected reason observed for each known sample;
- whether any accepted candidate still bypasses final ASR;
- build number and real recording evidence if code changed.

### Task 2: Candidate Snapshot Assembly / confirmed + volatile 拼接边界

**Purpose:** Ensure final candidate text is assembled from stable and volatile parts without overlap or tail fragment duplication.

**Files:**

- Create: `native/Sources/Domain/RealtimeTranscription/TranscriptSnapshotAssembler.swift`
- Modify: `native/Sources/Application/RealtimeTranscription/LegacyPreviewShadowAdapter.swift`
- Create: `native/Tests/TranscriptSnapshotAssemblerCheck.swift`

**Consumes:**

- `TranscriptState.confirmedText`
- `TranscriptState.volatileText`

**Produces:**

```swift
struct TranscriptSnapshotAssembler {
    static func deliveryText(confirmed: String, volatile: String) -> String
}
```

**Rules:**

- If confirmed suffix overlaps volatile prefix, keep one copy.
- If volatile begins with the last 1–4 characters of confirmed and then continues, trim the overlap.
- If volatile is entirely contained in confirmed suffix, return confirmed.
- Do not remove legitimate repeated words when they are separated by punctuation or whitespace.

**RED tests:**

- [ ] confirmed `"用户体验"` + volatile `"体验不要了吗"` => `"用户体验不要了吗"`.
- [ ] confirmed `"代码设计"` + volatile `"计排查一下"` => `"代码设计排查一下"` only if context marks `"计"` as overlap.
- [ ] confirmed `"今天我们讨论"` + volatile `"功能优化"` => unchanged append.
- [ ] confirmed `"好好"` + volatile `"学习"` => `"好好学习"`; do not collapse legitimate repeated prefix.

**GREEN boundary:**

- Only replace `CandidateDeliverySnapshot(state:)` assembly.
- Do not change Reconciler logic.
- Do not change FinalDelivery selection.

**Real validation:**

- Repeat known phrases where previous paste produced “设计计 / 查查 / 下下”.
- Expected: assembled candidate does not create new overlap duplicates.

**Implementation Detail Lock:**

This task only fixes assembly of `confirmed + volatile`. It must not decide whether the assembled candidate is good enough to paste; that remains Task 1/4.

Create `native/Sources/Domain/RealtimeTranscription/TranscriptSnapshotAssembler.swift` with this shape:

```swift
enum TranscriptSnapshotAssembler {
    static func deliveryText(
        confirmed: String,
        volatile: String
    ) -> String
}
```

Then change only `CandidateDeliverySnapshot.init(state:source:)` from:

```swift
text: state.confirmedText + state.volatileText
```

to:

```swift
text: TranscriptSnapshotAssembler.deliveryText(
    confirmed: state.confirmedText,
    volatile: state.volatileText
)
```

The assembler must use suffix/prefix overlap, not global fuzzy rewriting. Allowed behavior:

```swift
deliveryText(confirmed: "用户体验", volatile: "体验不要了吗") == "用户体验不要了吗"
deliveryText(confirmed: "今天我们讨论", volatile: "功能优化") == "今天我们讨论功能优化"
deliveryText(confirmed: "好好", volatile: "学习") == "好好学习"
deliveryText(confirmed: "已经稳定", volatile: "已经稳定") == "已经稳定"
```

Forbidden behavior:

```swift
deliveryText(confirmed: "好好", volatile: "好学习") == "好学习"      // wrong: deletes legitimate repeated text
deliveryText(confirmed: "用户体验", volatile: "不要了吗") == "用户不要了吗" // wrong: deletes non-overlap text
```

Add tests to `native/Tests/TranscriptSnapshotAssemblerCheck.swift` and add a `CandidateDeliverySnapshotCheck.swift` assertion that `CandidateDeliverySnapshot(state:)` uses the assembler.

Expected RED: new test fails because `TranscriptSnapshotAssembler` does not exist and current state snapshot concatenates directly.

Task completion must update this plan with:

- exact overlap rules implemented;
- any examples deliberately not fixed because they belong in Reconciler rather than assembler;
- build number and real recording evidence if code changed.

### Task 3: Per-Request Observability Parity / 逐请求可观测性

**Purpose:** Make later provider/reconciler changes diagnosable before tuning behavior. This task should not alter transcript text.

**Files:**

- Modify: `native/Sources/Infrastructure/RealtimeTranscription/SenseVoiceSnapshotProvider.swift`
- Modify: `native/Sources/Infrastructure/RealtimeTranscription/SenseVoiceShadowScheduler.swift`
- Modify: `native/Sources/Application/FinalDeliveryUseCase.swift`
- Create: `native/Tests/SenseVoiceRequestDiagnosticsCheck.swift`

**Consumes:**

- `SenseVoiceShadowRequest.id`
- `SenseVoiceShadowRequest.kind`
- `SenseVoiceShadowScheduler.pendingFastCount`
- `SenseVoiceShadowScheduler.pendingCorrectionCount`
- `FinalDeliveryOutcome.source`
- `FinalDeliveryOutcome.reason`

**Produces:**

- Request-level logs with stable names:
  - `shadow_request_start`
  - `shadow_request_done`
  - `shadow_request_skipped`
  - `shadow_fast_budget_miss`
  - `shadow_correction_backlog_warning`
  - `shadow_request_timeout` only if a timeout mechanism exists in the same task; otherwise explicitly log `timeout_supported=false` in the plan update.
  - `final_delivery_selected quality=... quality_reason=...`

**Steps:**

- [ ] **Step 1: Write RED diagnostics check**

Add `native/Tests/SenseVoiceRequestDiagnosticsCheck.swift` that scans the source files and fails unless the required log event names are present in the correct layer. The initial test should fail on at least missing `shadow_request_start` / `shadow_request_done`.

- [ ] **Step 2: Run RED**

Run the focused check command used by existing standalone Swift tests. Expected: FAIL because new log event names are absent or incomplete.

- [ ] **Step 3: Add request-level logs only**

Add logs at request admission/start/completion/skip/degrade points. Do not change scheduler selection, provider request timing, reconciler output, final source selection, or UI.

- [ ] **Step 4: Run GREEN**

Run the new diagnostics check plus existing `SenseVoiceShadowSchedulerCheck.swift`, `SenseVoiceSnapshotProviderCheck.swift`, and `FinalDeliveryUseCaseCheck.swift`. Expected: PASS.

- [ ] **Step 5: Build/install and plan update**

If Swift source changed, run `./native/build_and_log.sh`, validate installed app opens, then update this plan with build number, commands, and any logs observed.

**Forbidden:**

- Do not tune scheduler capacity.
- Do not change recognized text.
- Do not change UI.
- Do not use logs to justify skipping real recording gates later.

**Implementation Detail Lock:**

This task must be behavior-preserving. The only accepted runtime difference is more logs.

Add `native/Tests/SenseVoiceRequestDiagnosticsCheck.swift` as a source-boundary check. It can be a Swift executable that reads source files and asserts required strings are present in the correct files. Required checks:

```swift
let provider = try String(contentsOfFile: "native/Sources/Infrastructure/RealtimeTranscription/SenseVoiceSnapshotProvider.swift")
let finalDelivery = try String(contentsOfFile: "native/Sources/Application/FinalDeliveryUseCase.swift")

precondition(provider.contains("shadow_request_start"))
precondition(provider.contains("shadow_request_done"))
precondition(provider.contains("shadow_request_skipped"))
precondition(provider.contains("request_id="))
precondition(provider.contains("kind="))
precondition(provider.contains("audio_ms="))
precondition(provider.contains("recognition_ms="))
precondition(finalDelivery.contains("final_delivery_selected"))
precondition(finalDelivery.contains("quality="))
precondition(finalDelivery.contains("quality_reason="))
```

Where to log:

- At the beginning of `SenseVoiceSnapshotProviderCore.launch(_:)`: `shadow_request_start`.
- In `recognitionCompleted(...)`: `shadow_request_done`, including success/failure, request kind, service ms, audio ms, pending counts after completion.
- In `recognitionSkipped(...)`: `shadow_request_skipped`.
- When `serviceMilliseconds > serviceBudget`: `shadow_fast_budget_miss` for fast or a provider-budget warning for correction/finalTail.
- In `FinalDeliveryUseCase.deliver(...)`: exactly one `final_delivery_selected` after the outcome is known.

Every log must include:

```text
session_id=<8-char-prefix> request_id=<8-char-prefix> kind=<fast|correction|boundaryCorrection|finalTail> audio_ms=<n>
```

If a value is unavailable, log `unknown` explicitly. Do not omit the key.

Expected RED: source-boundary check fails because the new log names are absent.

Task completion must update this plan with:

- sample log lines from one short real recording;
- confirmation that recognized text did not change versus before the task;
- build number if code changed.

### Task 4: FinalDelivery Source Arbitration Contract / 最终来源仲裁契约

**Purpose:** Make FinalDelivery choose between candidate, final ASR, and preview fallback by explicit quality reports, not source bias.

**Files:**

- Modify: `native/Sources/Application/FinalDeliveryUseCase.swift`
- Modify: `native/Sources/Application/FinalRecognitionUseCase.swift` only if needed for return metadata.
- Modify: `native/Tests/FinalDeliveryUseCaseCheck.swift`

**Inputs:**

- Candidate text + `CandidateTranscriptQualityReport`
- Final ASR result text
- Preview fallback text
- User switch `reRecognizeWholeRecordingAfterStop`

**Decision table:**

| Candidate | Final ASR | User full re-recognition | Result |
| --- | --- | --- | --- |
| accepted | not run | false | candidate |
| rejected | meaningful | false | final ASR |
| rejected | empty/failed | false | preview fallback if meaningful, else candidate only if safer than empty |
| accepted | meaningful but user switch on | true | final ASR |
| accepted but final is requested for audit only | meaningful | false | no audit-only final in this task |

**Forbidden:**

- Do not run final ASR for every accepted candidate in this task. That would add latency and cost.
- Do not reintroduce a fixed “20 seconds means final” rule.
- Do not put source selection back into `SpeechInputCoordinator`.

**RED tests:**

- [ ] rejected candidate with clean final returns final.
- [ ] accepted candidate does not call final.
- [ ] user switch calls final even if candidate accepted.
- [ ] final empty after rejected candidate returns preview fallback if meaningful.
- [ ] logs expose `source` and `reason`.

**Real validation:**

- Known bad candidate samples should paste final ASR.
- Known bad final-ASR sample “功能优度优化” should allow candidate if candidate passes quality gate.

**Implementation Detail Lock:**

This task is the place where Build 778's direct shortcut must be removed or amended. The final delivery rule after Task 4 must be:

```text
candidate quality accepted + user did not request full re-recognition
→ deliver candidate without final ASR

candidate quality rejected + final ASR meaningful
→ deliver final ASR

candidate quality rejected + final ASR empty/failed + preview fallback meaningful
→ deliver preview fallback

candidate quality rejected + final ASR empty/failed + preview fallback empty + candidate has meaningful text
→ deliver candidate only as last non-empty safety net, with reason marking degraded_candidate_last_resort
```

`FinalDeliveryUseCase` must not directly trust:

```swift
candidateSnapshot?.source == .shadowRuntimeCache && candidateSnapshot?.lifecycle == .completed
```

That is source bias. It may use source as metadata, but the decision must come from `CandidateTranscriptQualityReport`.

Add or update `FinalDeliveryOutcome` only if needed to expose quality metadata. Preferred shape:

```swift
struct FinalDeliveryOutcome {
    let text: String
    let source: String
    let reason: String
    let recognitionSeconds: Double
    let candidateQuality: CandidateTranscriptQualityReport?
}
```

If adding this field creates too broad a change, keep `FinalDeliveryOutcome` unchanged and ensure `reason` includes `quality_reason=<reason>`.

Required RED tests in `FinalDeliveryUseCaseCheck.swift`:

```swift
// Accepted candidate does not call final ASR.
precondition(outcome.source == "candidate-preview-cache")
precondition(fake.transcribeCallCount == 0)

// Rejected candidate calls final ASR and returns final when meaningful.
precondition(outcome.source == "fake-final")
precondition(fake.transcribeCallCount == 1)

// User switch always calls final ASR.
precondition(reRecognizeOutcome.source == "fake-force-final")
precondition(fake.transcribeCallCount == 1)

// Rejected candidate + empty final + meaningful preview returns preview fallback.
precondition(outcome.source.contains("realtime-preview-fallback"))
```

This task must also update comments in `FinalDeliveryUseCaseCheck.swift`; current comments that say “shadow-runtime-cache completed candidate should directly权威” are no longer true under the corrected architecture principle.

Expected RED: current code passes some old shortcut tests but fails the new rejected-candidate tests because it does not call final ASR.

Task completion must update this plan with:

- final decision table actually implemented;
- old tests removed or rewritten because they encoded the Build 778 shortcut;
- real recording result for “用户体验不要了吗” and one longer phrase where candidate should still win.

### Architecture Review Checkpoint A / 架构复审 A

**Trigger:** After Tasks 1–4 are complete, stop coding and perform architecture review before touching Provider/Reconciler.

**Review question:**

- Did we protect current paste behavior without moving transcript repair into UI?
- Did `FinalDeliveryUseCase` become a clear source arbiter rather than a source-biased shortcut?
- Are logs sufficient to diagnose the next Provider/Reconciler tasks?

**Required output:**

- Append review result to this plan.
- If review fails, do not start Task 5.

### Task 5: Fast/Correction Authority Separation / fast 只展示，correction 才转正

**Purpose:** Port the old core rule: fast is for responsiveness, correction/stopTail/boundaryCorrection is for stable text.

**Files:**

- Modify: `native/Sources/Infrastructure/RealtimeTranscription/SenseVoiceShadowScheduler.swift`
- Modify: `native/Sources/Infrastructure/RealtimeTranscription/SenseVoiceSnapshotProvider.swift`
- Modify: `native/Sources/Infrastructure/RealtimeTranscription/SenseVoiceBoundaryReconciler.swift`
- Create: `native/Tests/SenseVoiceLaneAuthorityCheck.swift`

**New contract:**

```swift
enum SenseVoiceSnapshotAuthority: Equatable, Sendable {
    case provisionalFast
    case correction
    case finalTail
    case boundaryCorrection
}
```

**Rules:**

- `.provisionalFast` may update volatile text.
- `.provisionalFast` must not append `newlyConfirmedText`.
- `.correction`, `.finalTail`, `.boundaryCorrection` may advance confirmed text if seam verification passes.
- Reconciler must receive authority/source, not infer from timing.

**RED tests:**

- [ ] two fast snapshots with overlapping text must not create confirmed segments.
- [ ] fast followed by correction can confirm only correction-verified text.
- [ ] finalTail may produce terminal volatile/confirmed result suitable for delivery.

**Forbidden:**

- Do not change FinalDelivery in this task.
- Do not change UI.
- Do not change VAD boundary planning.

**Real validation:**

- Capsule still shows fast text quickly.
- Final paste no longer uses text that only ever appeared in fast lane as confirmed.

**Implementation Detail Lock:**

This task changes text authority, not scheduling cadence. Do not add VAD planning, final-tail priority, hallucination filtering, or final-delivery changes here.

Add the authority contract next to the current request kind definitions in `native/Sources/Infrastructure/RealtimeTranscription/SenseVoiceShadowScheduler.swift` or move it to a new small domain file only if needed by tests:

```swift
enum SenseVoiceSnapshotAuthority: Equatable, Sendable {
    case provisionalFast
    case correction
    case finalTail
    case boundaryCorrection
}

extension SenseVoiceShadowRequestKind {
    var authority: SenseVoiceSnapshotAuthority {
        switch self {
        case .fast:
            return .provisionalFast
        case .correction:
            return .correction
        case .boundaryCorrection:
            return .boundaryCorrection
        }
    }
}
```

Then change `SenseVoiceBoundaryReconciler.consume(...)` to receive authority explicitly:

```swift
mutating func consume(
    _ current: SenseVoiceSnapshotRecognition,
    authority: SenseVoiceSnapshotAuthority
) -> SenseVoiceBoundaryReconciliation
```

Required behavior:

```swift
// provisional fast:
// - updates volatileTailText
// - updates previous fast/provisional observation if needed
// - returns newlyConfirmedText == ""
// - must not advance confirmedThroughTime

// correction:
// - may confirm text using existing lexical/timestamp seam verification

// boundaryCorrection:
// - may update volatile/recovery confidence
// - must not silently rewrite already-confirmed text in this task

// finalTail:
// - define authority now, but full scheduler priority is Task 6
```

Add `native/Tests/SenseVoiceLaneAuthorityCheck.swift` with RED assertions:

```swift
var reconciler = SenseVoiceBoundaryReconciler()
let fast1 = reconciler.consume(
    recognition(text: "今天我们讨论", tokens: ["今","天","我","们","讨","论"], timestamps: nil, start: 0, end: 3),
    authority: .provisionalFast
)
precondition(fast1.newlyConfirmedText.isEmpty)
precondition(fast1.volatileTailText == "今天我们讨论")

let fast2 = reconciler.consume(
    recognition(text: "今天我们讨论功能", tokens: ["今","天","我","们","讨","论","功","能"], timestamps: nil, start: 0, end: 4),
    authority: .provisionalFast
)
precondition(fast2.newlyConfirmedText.isEmpty, "fast must never confirm")

let correction = reconciler.consume(
    recognition(text: "今天我们讨论功能优化", tokens: ["今","天","我","们","讨","论","功","能","优","化"], timestamps: nil, start: 0, end: 6),
    authority: .correction
)
precondition(correction.volatileTailText.contains("功能") || !correction.newlyConfirmedText.isEmpty)
```

Update call sites in `SenseVoiceSnapshotProvider.apply(...)`:

```swift
reconciliation = reconciler.consume(
    recognition,
    authority: request.kind.authority
)
```

If `consumeBoundaryCorrection(...)` remains as a separate method for now, it must delegate to the authority-aware path or be clearly marked as the `.boundaryCorrection` authority path.

Expected RED:

- The new test cannot compile because `SenseVoiceSnapshotAuthority` and `consume(_:authority:)` do not exist.
- If the test is adapted to current API, it should fail because fast can influence confirmed text through the same `consume(...)` path.

Task completion must update this plan with:

- exact authority API implemented;
- evidence that fast no longer creates confirmed segments;
- real recording result showing fast display still appears promptly.

### Task 6: StopTail Lane Parity / 停止收尾专用通道

**Purpose:** Restore old stop-tail semantics in the new scheduler so the last utterance is finalized by a dedicated authority path.

**Files:**

- Modify: `native/Sources/Infrastructure/RealtimeTranscription/SenseVoiceShadowScheduler.swift`
- Modify: `native/Sources/Infrastructure/RealtimeTranscription/SenseVoiceSnapshotProvider.swift`
- Modify: `native/Sources/Infrastructure/RealtimeTranscription/SenseVoiceBoundaryReconciler.swift`
- Modify: `native/Tests/SenseVoiceSnapshotProviderCheck.swift`
- Create: `native/Tests/SenseVoiceStopTailLaneCheck.swift`

**Rules:**

- Add a distinct request kind/authority for final tail; do not encode it as ordinary `.correction`.
- `finish()` enqueues one finalTail request if audio exists and provider can run it.
- finalTail outranks queued correction after the currently active request completes.
- finalTail must not cancel an active recognition unless there is an explicit, tested cancellation policy.
- finalTail budget is allowed to be higher than normal correction.

**RED tests:**

- [ ] finish with idle scheduler enqueues finalTail.
- [ ] finish with pending corrections causes finalTail to run before older correction.
- [ ] finalTail success updates `lastRecognizedAudioEndTime` to stop point.
- [ ] finalTail does not produce duplicate text if it overlaps confirmed tail.
- [ ] finalTail authority is visible in request-level logs.

**Real validation:**

- 20-second and 2-minute recordings end without tail loss.
- Logs show finalTail requested/done, or a clear reason why not.

**Forbidden:**

- Do not alter candidate quality gate.
- Do not alter UI.
- Do not add VAD boundary planning in this task.

**Implementation Detail Lock:**

Task 6 builds on Task 5. Do not start it until `SenseVoiceSnapshotAuthority.finalTail` exists and Task 5 is green.

Change `SenseVoiceShadowRequestKind` to include a distinct final-tail kind:

```swift
enum SenseVoiceShadowRequestKind: Equatable, Sendable {
    case fast
    case correction
    case boundaryCorrection
    case finalTail
}
```

Update authority mapping:

```swift
case .finalTail:
    return .finalTail
```

Change `SenseVoiceSnapshotProviderCore.enqueueFinalTailSnapshotIfNeeded()` from creating:

```swift
kind: .correction
```

to:

```swift
kind: .finalTail
```

Scheduler rule:

- `enqueueFinalTail(_:)` may discard pending fast and older pending corrections, but it must preserve the currently active request.
- When the active request completes, finalTail must be the next admitted request.
- finalTail must be represented in diagnostics and logs as `kind=finalTail`, not `kind=correction`.

Add `native/Tests/SenseVoiceStopTailLaneCheck.swift` with RED assertions:

```swift
var scheduler = SenseVoiceShadowScheduler(policy: .initial)
let active = request("active-correction", kind: .correction, horizon: 1)
let oldCorrection = request("old-correction", kind: .correction, horizon: 2)
let fast = request("fast", kind: .fast, horizon: 2)
let tail = request("final-tail", kind: .finalTail, horizon: 99)

_ = scheduler.enqueue(active)
precondition(scheduler.admitNextIfIdle()?.id == "active-correction")
_ = scheduler.enqueue(oldCorrection)
_ = scheduler.enqueue(fast)
_ = scheduler.enqueueFinalTail(tail)

let next = scheduler.complete(activeRequestID: "active-correction")
precondition(next?.kind == .finalTail)
precondition(next?.id == "final-tail")
```

Add or update provider test in `native/Tests/SenseVoiceSnapshotProviderCheck.swift`:

```swift
// finish must publish completed only after finalTail recognition covers the stop point.
precondition(state.lifecycle == .completed)
precondition(diagnostics.tailGapMilliseconds == 0)
precondition(recordedRequestKinds.contains(.finalTail))
```

If existing test recognizers cannot record request kind, add a small recognizer/probe in the test only; do not leak testing hooks into UI.

Expected RED:

- `.finalTail` does not exist.
- Existing finish path emits a `.correction` request, so logs/tests cannot prove stopTail authority.

Task completion must update this plan with:

- sample `shadow_request_start kind=finalTail` and `shadow_request_done kind=finalTail` log lines;
- 20-second and 2-minute real recording evidence for no tail loss;
- any remaining tail-loss case classified as Reconciler, Provider, or ASR model issue.

### Task 7: Migrate Old Hallucination Filter Into New Data Layer

**Status:** Automated implementation complete; installed-app voice acceptance pending.

**Purpose:** Port old `RecognitionTextFilter` behavior into the new provider/reconciler path without moving logic into UI.

**Files:**

- Create: `native/Sources/Domain/RealtimeTranscription/RealtimeRecognitionHallucinationFilter.swift`
- Modify: `native/Sources/Application/RealtimePreview/ExperimentalRealtimePreviewPipeline.swift`
- Modify: `native/Sources/Infrastructure/RealtimeTranscription/SenseVoiceSnapshotProvider.swift`
- Create: `native/Tests/RealtimeRecognitionHallucinationFilterCheck.swift`
- Create: `native/Tests/RealtimeRecognitionHallucinationFilterWiringCheck.sh`

**Rules:**

- Exact silence hallucinations like `"Yeah"`, `"The."`, `"嗯"`, `"啊"` are suppressible only when they are the whole recognition result or near silence/start.
- Real spoken “Yeah, 我们继续...” must not be suppressed.
- Suppressed result must not clear existing confirmed text.
- Suppressed result must not become final delivery candidate.
- 当前生产主胶囊在“重叠矫正”开启时由 `ExperimentalRealtimePreviewPipeline` 驱动，因此过滤器必须同时接入该管线和 `SenseVoiceSnapshotProvider`；只改后者不能修复生产预览。
- UI 走读确认 `ProductionPreviewTextCoordinator`、`CandidateContentProjection`、`CapsuleTextBuffer` 只做会话/序列投影、稳定与可变文本合成以及动画截取，不负责识别文本修正。

**RED tests:**

- [x] `"Yeah"` at start with no prior meaningful text is suppressed.
- [x] `"Yeah我们继续"` is not suppressed.
- [x] `"嗯"` alone after silence is suppressed.
- [x] existing confirmed text remains unchanged after suppressed output.
- [x] 第二块单独识别成 `"我。"` 时不追加到已有长句，也不能进入最终实时缓存。

**Forbidden:**

- Do not edit capsule UI.
- Do not edit FinalDelivery.

**2026-07-21 code-walk amendment:** 真实日志证明 2.0.54 的异常录音走 `experimental_preview_update`，最终来源为 `realtime-preview-delivery-cache`；旧 `isMeaningfulRealtimePreviewText(...)` 只存在于普通 `transcribeRealtime(...)` 路径。Task 7 必须在 reducer/provider 之前统一过滤独立短幻觉，UI 保持纯展示。

**Implementation Detail Lock:**

This task ports the old filter into the new data layer. It must not reuse the old function by calling it from UI, and it must not filter final full-ASR output.

Create `native/Sources/Domain/RealtimeTranscription/RealtimeRecognitionHallucinationFilter.swift`:

```swift
struct RealtimeRecognitionHallucinationFilter: Sendable {
    struct Context: Equatable, Sendable {
        let hasPriorConfirmedText: Bool
        let hasPriorVolatileText: Bool
        let authority: SenseVoiceSnapshotAuthority
    }

    enum Decision: Equatable, Sendable {
        case keep(String)
        case suppress(reason: Reason)
    }

    enum Reason: String, Equatable, Sendable {
        case silencePhrase
        case latinSilencePhrase
        case tooShortWithoutContext
        case punctuationNoise
        case repeatedSameAsPrevious
    }

    func evaluate(
        text: String,
        previousPreviewText: String,
        languageMode: RecognitionLanguageMode,
        context: Context
    ) -> Decision
}
```

Add read-only state exposure to `SenseVoiceBoundaryReconciler` so the provider can build filter context without peeking into private fields:

```swift
var currentConfirmedText: String { confirmedTokens.joined() }
var currentVolatileTailText: String { volatileTailText }
var currentDisplayText: String { currentConfirmedText + currentVolatileTailText }
```

Initial behavior must reuse the old blacklist semantics:

```swift
// suppress:
"Yeah"
"The."
"嗯"
"啊"
"谢谢观看"

// keep:
"Yeah我们继续"
"OK我们继续"
"嗯我们继续讲"
"今天我们讨论功能优化"
```

Wire point in `SenseVoiceSnapshotProviderCore.apply(...)`:

```swift
let priorConfirmedText = reconciler.currentConfirmedText
let priorVolatileText = reconciler.currentVolatileTailText
let filterDecision = hallucinationFilter.evaluate(
    text: output.text,
    previousPreviewText: reconciler.currentDisplayText,
    languageMode: configuration.languageMode,
    context: .init(
        hasPriorConfirmedText: !priorConfirmedText.isEmpty,
        hasPriorVolatileText: !priorVolatileText.isEmpty,
        authority: request.kind.authority
    )
)
```

If `SenseVoiceSnapshotProviderConfiguration` does not currently carry `languageMode`, add the smallest necessary field or pass `.chinese` only if that is already the active local configuration path. Record the decision in this plan; do not guess silently.

Suppression behavior:

- If a fast result is suppressed, do not emit a transcript-clearing event.
- If a correction result is suppressed and prior text exists, do not clear existing confirmed/volatile text.
- Log `shadow_result_suppressed reason=<reason> kind=<kind>`.
- Suppressed output must not be included in `CandidateDeliverySnapshot`.

Add `native/Tests/RealtimeRecognitionHallucinationFilterCheck.swift` with RED assertions:

```swift
let filter = RealtimeRecognitionHallucinationFilter()
precondition(filter.evaluate(
    text: "Yeah",
    previousPreviewText: "",
    languageMode: .chinese,
    context: .init(hasPriorConfirmedText: false, hasPriorVolatileText: false, authority: .provisionalFast)
) == .suppress(reason: .latinSilencePhrase))

precondition(filter.evaluate(
    text: "Yeah我们继续",
    previousPreviewText: "",
    languageMode: .chinese,
    context: .init(hasPriorConfirmedText: false, hasPriorVolatileText: false, authority: .provisionalFast)
) == .keep("Yeah我们继续"))

precondition(filter.evaluate(
    text: "嗯",
    previousPreviewText: "今天我们讨论",
    languageMode: .chinese,
    context: .init(hasPriorConfirmedText: true, hasPriorVolatileText: false, authority: .correction)
) == .suppress(reason: .silencePhrase))
```

Add provider-level RED test in `native/Tests/SenseVoiceSnapshotProviderCheck.swift` or a new focused check:

```swift
// A suppressed "Yeah" result must not clear previously visible text.
precondition(finalState.confirmedText + finalState.volatileText == "今天我们讨论")
```

Expected RED:

- Filter type does not exist.
- Provider currently emits model text directly, so `"Yeah"` can become visible/candidate text.

Task completion must update this plan with:

- exact phrases migrated from old blacklist;
- false-positive cases tested and kept;
- one real recording with start silence showing no `"Yeah"`/`"The"` visible or pasted.

**2026-07-21 implementation evidence:** RED 因过滤器类型和两条数据入口接线不存在而失败。GREEN 新增纯领域过滤器，并在 `ExperimentalRealtimePreviewPipeline` 的 reducer 前、`SenseVoiceSnapshotProvider` 的 reconciler 前接入；suppression 直接返回，因此既不清空旧状态，也不会向 `ProductionRealtimePreviewDeliveryCache` 发布坏片段。迁移旧黑名单中的中文/英文整段短语，自动检查覆盖 `我。`、`我想。`、`Yeah`、`I.` 抑制，以及 `我想修改这个功能。`、`Yeah，我们继续测试。`、`最后由我。` 保留。过滤不依赖语言模式，因为只对去空白/标点后的整段精确短语判断，不对正常句子做改写。真实安装版录音仍需老板验收。

**2026-07-21 build evidence:** TypeWhale Pro 2.0.55（Build 797）完成完整编译、覆盖安装、启动和 deep/strict 签名校验；构建后过滤器、两条入口接线、静音门控、重叠矫正协调、生产缓存和首块策略回归通过。真实语音验收仍保持 pending，不以自动测试代替。

**2026-07-21 real-test failure and amendment:** 安装版静音测试产生新短词 `我放。`。日志显示整轮 8.929 秒峰值仅 0.001215，`vad_final=no_speech`；已知词过滤连续命中，但 2.314 秒时唯一一次未列入词表的 3 字结果进入生产缓存，最终以 `realtime-preview-delivery-cache` 粘贴。结论：固定黑名单不足。Task 7 增加通用短结果稳定门：去标点后不超过2字的未知结果先暂存，连续两个快照一致才发布；任一不同结果会重置暂存。正常长句立即通过，已知静音词始终抑制。新增 RED 覆盖 `我放。` 不落缓存和 `好的。` 连续稳定后放行。

**2026-07-21 short-result gate build evidence:** TypeWhale Pro 2.0.56（Build 798）完成完整编译、覆盖安装、启动和签名校验。老板后续指出首块3秒未触发、文字未转白；日志证实这两项属于边界/correction 确认闭环，不能计入本次短幻觉修复的完成范围。

**2026-07-21 short-result gate rejected:** 真实测试“静音录制5秒后。结束”中，第二块在停止前只产出一次两字尾词，短结果稳定门将其暂存后没有第二次释放机会，最终粘贴丢失“结束”。该门已回退，并新增 `结束。` 首次结果必须通过的回归。未知静音词后续只能通过VAD/音频证据处理，不允许再按字符数等待或删除。

**2026-07-21 rollback build evidence:** TypeWhale Pro 2.0.57（Build 799）完成完整编译、覆盖安装、启动和签名校验；短结果稳定门已从两条识别入口撤销，已知静音短语精确过滤继续保留。

### Task 8: VAD-Aware Boundary Planner, Pure Domain / 纯领域边界规划器

**Purpose:** Port old soft/hard boundary strategy into the new provider without hand-written audio thresholds.

**Files:**

- Create: `native/Sources/Domain/RealtimeTranscription/RealtimeBoundaryPlanner.swift`
- Create: `native/Tests/RealtimeBoundaryPlannerCheck.swift`
- Modify: `native/Sources/Domain/RealtimeTranscription/RealtimeBoundaryCorrectionPlanner.swift` only if the existing `RealtimeBoundaryKind` needs documentation comments; do not change its behavior in this task.

**Consumes:**

- Existing `RealtimeBoundaryKind.voicePause`
- Existing `RealtimeBoundaryKind.hardLimit`
- Existing `RealtimeBoundaryCorrectionPlanner.plan(...)`
- A data-layer VAD decision expressed as `voiceActive: Bool?`

**Produces:**

```swift
struct RealtimeBoundaryPlan: Equatable, Sendable {
    let boundaryTime: TimeInterval
    let kind: RealtimeBoundaryKind
}

struct RealtimeBoundaryPlanner: Sendable {
    let softBoundarySeconds: TimeInterval
    let hardBoundarySeconds: TimeInterval

    func proposeBoundary(
        chunkStartedAt: TimeInterval,
        capturedAt: TimeInterval,
        voiceActive: Bool?
    ) -> RealtimeBoundaryPlan?
}
```

**Rules:**

- Use Silero VAD state, not RMS/peak thresholds.
- Soft boundary: after `softBoundarySeconds`, if VAD says inactive, propose `.voicePause`.
- Hard boundary: after `hardBoundarySeconds`, propose `.hardLimit` even if VAD still says active.
- If `voiceActive == nil`, do not propose `.voicePause`; return `.hardLimit` only after the hard limit.
- Boundary correction window should be centered around the boundary, with enough pre/post context.
- This task is pure domain logic. It must not know about `AudioRecorder`, `SpeechInputCoordinator`, `SenseVoiceSnapshotProvider`, UI, or ASR models.

**RED tests:**

- [ ] 9 seconds active voice produces no boundary.
- [ ] 11 seconds with inactive voice produces voicePause boundary.
- [ ] 18 seconds active voice produces hardLimit boundary.
- [ ] boundary correction waits until post-roll audio is available.
- [ ] unknown VAD at 11 seconds produces no voicePause boundary.

**Forbidden:**

- Do not wire into `SenseVoiceSnapshotProvider` yet.
- Do not alter FinalDelivery.
- Do not alter UI.
- Do not introduce volume thresholds.

**Implementation Detail Lock:**

Create `native/Sources/Domain/RealtimeTranscription/RealtimeBoundaryPlanner.swift`:

```swift
import Foundation

struct RealtimeBoundaryPlan: Equatable, Sendable {
    let boundaryTime: TimeInterval
    let kind: RealtimeBoundaryKind
}

struct RealtimeBoundaryPlanner: Sendable {
    let softBoundarySeconds: TimeInterval
    let hardBoundarySeconds: TimeInterval

    init(
        softBoundarySeconds: TimeInterval = 10,
        hardBoundarySeconds: TimeInterval = 18
    ) {
        self.softBoundarySeconds = softBoundarySeconds
        self.hardBoundarySeconds = hardBoundarySeconds
    }

    func proposeBoundary(
        chunkStartedAt: TimeInterval,
        capturedAt: TimeInterval,
        voiceActive: Bool?
    ) -> RealtimeBoundaryPlan? {
        let duration = capturedAt - chunkStartedAt
        if duration >= hardBoundarySeconds {
            return RealtimeBoundaryPlan(boundaryTime: capturedAt, kind: .hardLimit)
        }
        if duration >= softBoundarySeconds, voiceActive == false {
            return RealtimeBoundaryPlan(boundaryTime: capturedAt, kind: .voicePause)
        }
        return nil
    }
}
```

Add `native/Tests/RealtimeBoundaryPlannerCheck.swift`:

```swift
import Foundation

let planner = RealtimeBoundaryPlanner(
    softBoundarySeconds: 10,
    hardBoundarySeconds: 18
)

precondition(planner.proposeBoundary(
    chunkStartedAt: 0,
    capturedAt: 9,
    voiceActive: true
) == nil)

precondition(planner.proposeBoundary(
    chunkStartedAt: 0,
    capturedAt: 11,
    voiceActive: true
) == nil)

precondition(planner.proposeBoundary(
    chunkStartedAt: 0,
    capturedAt: 11,
    voiceActive: false
) == RealtimeBoundaryPlan(boundaryTime: 11, kind: .voicePause))

precondition(planner.proposeBoundary(
    chunkStartedAt: 0,
    capturedAt: 11,
    voiceActive: nil
) == nil)

precondition(planner.proposeBoundary(
    chunkStartedAt: 0,
    capturedAt: 18,
    voiceActive: true
) == RealtimeBoundaryPlan(boundaryTime: 18, kind: .hardLimit))

let correction = RealtimeBoundaryCorrectionPlanner(
    preRollSeconds: 4,
    postRollSeconds: 4
)
precondition(correction.plan(
    boundaryTime: 11,
    availableAudioStart: 0,
    availableAudioEnd: 13,
    kind: .voicePause
) == nil)
precondition(correction.plan(
    boundaryTime: 11,
    availableAudioStart: 0,
    availableAudioEnd: 15,
    kind: .voicePause
) == RealtimeBoundaryCorrectionPlan(
    boundaryTime: 11,
    audioStartTime: 7,
    audioEndTime: 15,
    kind: .voicePause
))

print("RealtimeBoundaryPlannerCheck passed")
```

Expected RED:

- The new test cannot compile because `RealtimeBoundaryPlanner` and `RealtimeBoundaryPlan` do not exist.

Task completion must update this plan with:

- exact soft/hard boundary constants implemented;
- proof that no UI file was touched;
- focused test command and result.

### Task 9: Wire VAD-Aware Boundary Planning Into SenseVoice Provider / 接入 VAD 边界规划

**Purpose:** Use the pure boundary planner from Task 8 inside the new provider path, while keeping UI independent from VAD state.

**Files:**

- Modify: `native/Sources/Application/RealtimeTranscription/TranscriptionProvider.swift`
- Modify: `native/Sources/Infrastructure/Audio/AudioRecorder.swift`
- Modify: `native/Sources/Infrastructure/RealtimeTranscription/SenseVoiceSnapshotProvider.swift`
- Create: `native/Tests/SenseVoiceVADBoundaryIntegrationCheck.swift`
- Modify existing tests that construct `AudioFrame` only if the initializer signature requires it.

**Current code fact to preserve:**

- `AudioRecorder` already gets Silero VAD decisions through `SpeechInputCoordinator.receiveVoiceProbe(...)`.
- The decision is currently written back to `AudioRecorder.updateRealtimeVoiceActive(_:)`.
- `AudioFrame` currently carries samples, sample rate, channel count, and start frame, but no VAD metadata.
- Therefore the cleanest bridge is to attach optional data-layer voice activity metadata to `AudioFrame`, not to let UI or capsule code pass VAD state.

**Consumes:**

- `RealtimeBoundaryPlanner.proposeBoundary(...)`
- Optional `AudioFrame.voiceActivity`
- Existing `SenseVoiceSnapshotProviderCore.append(_:)`
- Existing `RealtimeBoundaryCorrectionPlanner.plan(...)`

**Produces:**

```swift
struct AudioFrameVoiceActivity: Equatable, Sendable {
    let voiceActive: Bool
}

struct AudioFrame: Sendable {
    let samples: [Float]
    let sampleRate: Int
    let channelCount: Int
    let startFrame: Int64
    let voiceActivity: AudioFrameVoiceActivity?
}
```

**Rules:**

- Use official Silero VAD signal already exposed by the app; do not add RMS/peak/volume thresholds.
- VAD influences provider request planning only.
- UI display must continue consuming `PreviewViewState`.
- If VAD signal is unavailable for a session, provider falls back to current fixed correction interval and logs `vad_boundary_available=false`.
- Fixed fast snapshots must remain unchanged; VAD planning applies to correction/boundary work, not to the first fast preview.
- A voicePause boundary must enqueue a boundary correction only after enough post-roll audio is available.
- A hardLimit boundary may enqueue immediately at the hard limit when enough retained audio exists.

**RED tests:**

- [ ] Provider with active VAD at 11 seconds does not create voicePause correction boundary.
- [ ] Provider with inactive VAD after 10 seconds creates voicePause correction boundary.
- [ ] Provider with active VAD at 18 seconds creates hardLimit boundary.
- [ ] Boundary correction waits until post-roll audio is available.
- [ ] Provider logs `vad_boundary_available=false` when frames have no VAD metadata.

**Real validation:**

- Natural pause then continue: no seam duplication/loss.
- Continuous >18 seconds: hard boundary occurs and is corrected conservatively.

**Forbidden:**

- Do not alter FinalDelivery.
- Do not alter UI.
- Do not introduce volume thresholds.

**Implementation Detail Lock:**

First change `native/Sources/Application/RealtimeTranscription/TranscriptionProvider.swift` with a backwards-compatible initializer so existing tests can keep constructing `AudioFrame(...)` without adding a new argument:

```swift
struct AudioFrameVoiceActivity: Equatable, Sendable {
    let voiceActive: Bool
}

struct AudioFrame: Sendable {
    let samples: [Float]
    let sampleRate: Int
    let channelCount: Int
    let startFrame: Int64
    let voiceActivity: AudioFrameVoiceActivity?

    init(
        samples: [Float],
        sampleRate: Int,
        channelCount: Int,
        startFrame: Int64,
        voiceActivity: AudioFrameVoiceActivity? = nil
    ) {
        self.samples = samples
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.startFrame = startFrame
        self.voiceActivity = voiceActivity
    }
}
```

Then change `AudioRecorder.makeAudioFrame(...)` to attach the recorder's current VAD state:

```swift
return AudioFrame(
    samples: mono,
    sampleRate: Int(buffer.format.sampleRate),
    channelCount: 1,
    startFrame: startFrame,
    voiceActivity: AudioFrameVoiceActivity(voiceActive: realtimeVoiceActive)
)
```

This is intentionally an optional hint. If Silero VAD is disabled, failed, or has not produced a recent decision, a later implementation may pass `nil`; this task must not fabricate voice activity from waveform volume.

Inside `SenseVoiceSnapshotProviderCore`, add planner state:

```swift
private let boundaryPlanner = RealtimeBoundaryPlanner(
    softBoundarySeconds: 10,
    hardBoundarySeconds: 18
)
private var boundaryChunkStartedAt: TimeInterval = 0
private var pendingBoundaryPlan: RealtimeBoundaryPlan?
private var latestVoiceActive: Bool?
```

In `append(_:)`, after `totalFrames` is updated and before `launchNextIfNeeded()`, update:

```swift
latestVoiceActive = frame.voiceActivity?.voiceActive
let capturedAt = Double(totalFrames) / Double(max(1, sampleRate))
if let plan = boundaryPlanner.proposeBoundary(
    chunkStartedAt: boundaryChunkStartedAt,
    capturedAt: capturedAt,
    voiceActive: latestVoiceActive
) {
    pendingBoundaryPlan = plan
    if plan.kind == .hardLimit || frame.voiceActivity?.voiceActive == false {
        enqueueBoundaryCorrectionIfPossible(
            boundaryTime: plan.boundaryTime,
            kind: plan.kind
        )
        boundaryChunkStartedAt = plan.boundaryTime
        pendingBoundaryPlan = nil
    }
}
```

The actual implementation may keep the correction request name as `.boundaryCorrection`, because Task 5/6 already made authority explicit. Do not create a new UI state.

Add `native/Tests/SenseVoiceVADBoundaryIntegrationCheck.swift` as a source-boundary plus behavior check. The source-boundary part must assert:

```swift
let provider = try String(contentsOfFile: "native/Sources/Infrastructure/RealtimeTranscription/SenseVoiceSnapshotProvider.swift")
let audioFrame = try String(contentsOfFile: "native/Sources/Application/RealtimeTranscription/TranscriptionProvider.swift")
let recorder = try String(contentsOfFile: "native/Sources/Infrastructure/Audio/AudioRecorder.swift")

precondition(audioFrame.contains("AudioFrameVoiceActivity"))
precondition(audioFrame.contains("voiceActivity: AudioFrameVoiceActivity? = nil"))
precondition(recorder.contains("voiceActivity: AudioFrameVoiceActivity(voiceActive: realtimeVoiceActive)"))
precondition(provider.contains("RealtimeBoundaryPlanner"))
precondition(provider.contains("vad_boundary_available=false"))
precondition(!provider.contains("onBands"))
precondition(!provider.contains("updateInputLevel"))
```

The behavior part must feed synthetic frames into `SenseVoiceSnapshotProvider`:

```swift
func samples(seconds: Double, sampleRate: Int = 16_000) -> [Float] {
    Array(repeating: 0.01, count: Int(seconds * Double(sampleRate)))
}

try await provider.append(AudioFrame(
    samples: samples(seconds: 11),
    sampleRate: 16_000,
    channelCount: 1,
    startFrame: 0,
    voiceActivity: AudioFrameVoiceActivity(voiceActive: true)
))
var diagnostics = await provider.diagnostics()
precondition(diagnostics.boundaryCorrectionRequestedCount == 0)

try await provider.append(AudioFrame(
    samples: samples(seconds: 1),
    sampleRate: 16_000,
    channelCount: 1,
    startFrame: 176_000,
    voiceActivity: AudioFrameVoiceActivity(voiceActive: false)
))
diagnostics = await provider.diagnostics()
precondition(diagnostics.boundaryCorrectionRequestedCount >= 1)
```

Expected RED:

- `AudioFrameVoiceActivity` does not exist.
- `AudioRecorder.makeAudioFrame(...)` does not attach VAD metadata.
- `SenseVoiceSnapshotProviderCore` currently uses fixed `correctionIntervalSeconds`, not `RealtimeBoundaryPlanner`.

Task completion must update this plan with:

- whether `voiceActivity` is always populated or can be `nil`;
- sample log lines for `vad_boundary_available=true|false`;
- real recording evidence for natural pause and continuous hard-limit cases.

### Task 10: Dynamic Budget And Scheduling Fairness / 动态预算与调度公平

**Purpose:** Bring old timing/fairness rules into the new scheduler after logs exist and authority lanes are explicit.

**Files:**

- Modify: `native/Sources/Infrastructure/RealtimeTranscription/SenseVoiceShadowScheduler.swift`
- Modify: `native/Sources/Infrastructure/RealtimeTranscription/SenseVoiceSnapshotProvider.swift`
- Create: `native/Tests/SenseVoiceDynamicBudgetCheck.swift`

**Rules:**

- Fast remains latency-oriented.
- Correction budget scales with audio window duration.
- FinalTail budget scales with audio window duration and may be higher than correction.
- Pending fast remains latest-only.
- Correction must not be permanently starved by fast.
- Do not tune capacity without a failing test or real log evidence.
- This task defines and logs request budgets. It must not kill an in-flight native recognizer unless a focused cancellation test proves the recognizer actually stops safely.

**RED tests:**

- [ ] fast budget remains short relative to correction.
- [ ] correction budget follows `max(6,min(12,duration*2+2))` or a documented new equivalent.
- [ ] finalTail budget follows `max(6,min(14,duration*2+3))` or a documented new equivalent.
- [ ] pending fast coalesces to latest.
- [ ] correction runs after configured fast streak/backlog pressure.
- [ ] over-budget request logs kind, budget, service time, and outcome.

**Real validation:**

- 2-minute recording logs show no unbounded backlog.
- UI still appears responsive while correction gets chances to run.

**Forbidden:**

- Do not alter `FinalDeliveryUseCase`.
- Do not alter UI.
- Do not change the VAD planner.
- Do not increase recognition concurrency.
- Do not add sleep-based waiting to make tests pass.

**Implementation Detail Lock:**

Add a focused budget policy near `SenseVoiceShadowSchedulingPolicy`:

```swift
struct SenseVoiceShadowServiceBudgetPolicy: Equatable, Sendable {
    let fastSeconds: TimeInterval

    init(fastSeconds: TimeInterval = 2.5) {
        self.fastSeconds = fastSeconds
    }

    func budgetSeconds(
        kind: SenseVoiceShadowRequestKind,
        audioDuration: TimeInterval
    ) -> TimeInterval {
        switch kind {
        case .fast:
            return fastSeconds
        case .correction, .boundaryCorrection:
            return max(6, min(12, audioDuration * 2 + 2))
        case .finalTail:
            return max(6, min(14, audioDuration * 2 + 3))
        }
    }

    func budgetMilliseconds(
        kind: SenseVoiceShadowRequestKind,
        audioDuration: TimeInterval
    ) -> Int {
        Int((budgetSeconds(kind: kind, audioDuration: audioDuration) * 1_000).rounded())
    }
}
```

Attach it to provider configuration:

```swift
struct SenseVoiceSnapshotProviderConfiguration: Equatable, Sendable {
    let serviceBudgetPolicy: SenseVoiceShadowServiceBudgetPolicy
}
```

Keep existing `maximumServiceMilliseconds` temporarily as a compatibility field only if removing it would broaden the task. If both exist during this task, provider logs must use the new per-request policy and this plan must record that `maximumServiceMilliseconds` is deprecated.

In `recognitionCompleted(...)`, replace fixed-budget comparison:

```swift
let serviceBudget = max(1, configuration.maximumServiceMilliseconds)
```

with:

```swift
let audioDuration = max(0, request.audioEndTime - request.audioStartTime)
let serviceBudget = configuration.serviceBudgetPolicy.budgetMilliseconds(
    kind: request.kind,
    audioDuration: audioDuration
)
```

Log over-budget without changing text:

```text
shadow_request_budget_miss kind=<kind> budget_ms=<budget> service_ms=<service> audio_ms=<audio> outcome=published
```

Scheduler fairness must remain explicit:

```swift
// pending fast: latest-only
// correction/finalTail: queued through pendingCorrections, with finalTail inserted ahead by Task 6
// maxConsecutiveFastBeforeCorrection: prevents fast from starving correction
```

Add `native/Tests/SenseVoiceDynamicBudgetCheck.swift`:

```swift
import Foundation

func request(
    _ id: String,
    kind: SenseVoiceShadowRequestKind,
    horizon: Int,
    samples: [Float] = [0.01, -0.01],
    sampleRate: Int = 16_000
) -> SenseVoiceShadowRequest {
    SenseVoiceShadowRequest(
        id: id,
        kind: kind,
        commitHorizon: horizon,
        samples: samples,
        sampleRate: sampleRate,
        capturedAtUptime: 0,
        audioStartTime: 0,
        audioEndTime: Double(samples.count) / Double(sampleRate)
    )
}

let budget = SenseVoiceShadowServiceBudgetPolicy(fastSeconds: 2.5)

precondition(budget.budgetSeconds(kind: .fast, audioDuration: 3) == 2.5)
precondition(budget.budgetSeconds(kind: .correction, audioDuration: 2) == 6)
precondition(budget.budgetSeconds(kind: .correction, audioDuration: 4) == 10)
precondition(budget.budgetSeconds(kind: .correction, audioDuration: 8) == 12)
precondition(budget.budgetSeconds(kind: .finalTail, audioDuration: 2) == 7)
precondition(budget.budgetSeconds(kind: .finalTail, audioDuration: 8) == 14)

var scheduler = SenseVoiceShadowScheduler(policy: .initial)
let fast1 = request("fast-1", kind: .fast, horizon: 1)
let fast2 = request("fast-2", kind: .fast, horizon: 2)
let correction = request("correction", kind: .correction, horizon: 2)

_ = scheduler.enqueue(fast1)
_ = scheduler.enqueue(fast2)
precondition(scheduler.discardedFastRequestCount == 1)
precondition(scheduler.admitNextIfIdle()?.id == "fast-2")
_ = scheduler.enqueue(correction)
let next = scheduler.complete(activeRequestID: "fast-2")
precondition(next?.kind == .correction)

let provider = try String(contentsOfFile: "native/Sources/Infrastructure/RealtimeTranscription/SenseVoiceSnapshotProvider.swift")
precondition(provider.contains("shadow_request_budget_miss"))
precondition(provider.contains("budget_ms="))
precondition(provider.contains("service_ms="))

print("SenseVoiceDynamicBudgetCheck passed")
```

Expected RED:

- `SenseVoiceShadowServiceBudgetPolicy` does not exist.
- `.finalTail` budget cannot compile until Task 6 exists.
- Provider still compares against fixed `maximumServiceMilliseconds`.

Task completion must update this plan with:

- exact service budget formula in use;
- whether `maximumServiceMilliseconds` remains as deprecated compatibility;
- one 2-minute real recording log summary showing pending fast/correction maxima and budget misses.

### Task 11: Old/New Parity Harness Before Retirement / 旧新能力对照门禁

**Purpose:** Compare old proven path and new path on real recordings before retiring old behavior.

**Files:**

- Create: `native/Tests/RealtimeOldNewParityLogCheck.py`
- Modify: `docs/superpowers/plans/2026-07-19-realtime-transcription-architecture-reconciliation-plan.md`
- Modify: `docs/开发日志.md` only after real installed-app validation is captured.

**Consumes:**

- `LaunchDiagnostics.logFileURL` output opened from app Test Logs.
- Task 3 log events: `shadow_request_start`, `shadow_request_done`, `shadow_request_skipped`, `final_delivery_selected`.
- Task 6 log events: `kind=finalTail`.
- Task 10 budget fields: `pending_fast`, `pending_correction`, `budget_ms`, `service_ms`.
- Old-path logs when legacy preview is still enabled.

**Produces:**

```text
RealtimeOldNewParityReport(
  sample_id=<name>,
  preview_chars=<n>,
  candidate_chars=<n>,
  pasted_chars=<n>,
  source=<candidate|final|preview_fallback|degraded>,
  tail_gap_ms=<n>,
  duplicate_marker=<none|repeated_short_unit|orphan_prefix|punctuation_storm>,
  classification=<pass|model_error|segmentation_error|seam_error|final_arbitration_error|ui_projection_error|insufficient_logs>
)
```

**Rules:**

- Collect old path display/final output when available.
- Collect new path display/final output.
- Compare text length, duplicate markers, tail gap, source, fallback reason.
- This harness is diagnostic only; it must not change production behavior.
- The harness must classify failures instead of returning a vague “bad transcript”.
- The harness must fail if logs do not contain enough fields to explain why paste chose a source.

**Real validation matrix:**

- 20-second Chinese natural speech.
- 2-minute Chinese natural speech.
- “用户体验不要了吗？”
- “今天我们讨论功能优化...”
- natural pause then continue.
- continuous >18 seconds.
- start with silence 0.5–1 second.
- mixed Chinese/English with real “Yeah”.

**Implementation Detail Lock:**

Create `native/Tests/RealtimeOldNewParityLogCheck.py` with this command contract:

```bash
python3 native/Tests/RealtimeOldNewParityLogCheck.py /absolute/path/to/LaunchDiagnostics.log
```

The script must parse log lines into records with this minimum shape:

```python
from dataclasses import dataclass
import re
import sys

@dataclass
class ParityRecord:
    sample_id: str
    preview_chars: int
    candidate_chars: int
    pasted_chars: int
    source: str
    tail_gap_ms: int
    duplicate_marker: str
    classification: str

def repeated_marker(text: str) -> str:
    for marker in ["设计计", "排查查", "一下下", "体验验"]:
        if marker in text:
            return "repeated_short_unit"
    if re.search(r"^[案了呢吗啊嗯][\\u4e00-\\u9fff]{3,}", text):
        return "orphan_prefix"
    if len(re.findall(r"[？?！!。.,，]", text)) > max(2, len(re.sub(r"\\W", "", text)) // 2):
        return "punctuation_storm"
    return "none"

def require_fields(line: str, fields: list[str]) -> None:
    missing = [field for field in fields if f"{field}=" not in line]
    if missing:
        raise SystemExit(f"missing fields {missing} in line: {line}")
```

Required assertions:

```python
log = open(sys.argv[1], encoding="utf-8").read().splitlines()
final_lines = [line for line in log if "final_delivery_selected" in line]
if not final_lines:
    raise SystemExit("missing final_delivery_selected")
for line in final_lines:
    require_fields(line, ["source", "reason", "quality", "quality_reason"])

request_done = [line for line in log if "shadow_request_done" in line]
if not request_done:
    raise SystemExit("missing shadow_request_done")
for line in request_done:
    require_fields(line, ["request_id", "kind", "audio_ms", "recognition_ms"])

if any("tail_gap_ms=" in line for line in log):
    tail_values = [
        int(match.group(1))
        for line in log
        for match in [re.search(r"tail_gap_ms=(\\d+)", line)]
        if match
    ]
    if tail_values and max(tail_values) > 1_500:
        raise SystemExit(f"tail gap too high: {max(tail_values)}ms")
```

The script may print a report even when it fails; failure must be non-zero so the developer cannot ignore it.

Expected RED:

- Script does not exist.
- Current logs may not contain the required fields until Tasks 3/6/10 are complete.

**Exit gate:**

- Each matrix item has source/reason logs.
- For any mismatch, the plan records whether it is model error, segmentation error, seam error, final arbitration error, or UI projection issue.
- No old-path retirement work may start before this task passes.
- `docs/开发日志.md` records the validation matrix result with the build number.

### Architecture Review Checkpoint B / 架构复审 B

**Trigger:** After Tasks 5–11 are complete, stop coding and perform architecture review before online provider alignment or retirement.

**Review question:**

- Have old mechanisms O1–O8 been migrated into explicit new owners?
- Is UI still presentation-only?
- Does final delivery use quality evidence rather than source bias?
- Are failures diagnosable from logs?

**Required output:**

- Append review result to this plan.
- If review fails, add corrective tasks before Task 12.

### Task 12: Online Provider Contract Alignment

**Purpose:** Ensure MiMo/Doubao/local providers all satisfy the same event and quality contracts.

**Files:**

- Modify: `native/Sources/Infrastructure/RealtimeTranscription/MiMoSnapshotProvider.swift`
- Modify: `native/Sources/Infrastructure/RealtimeTranscription/OnlineTranscriptionProvider.swift`
- Modify: `native/Sources/Infrastructure/RealtimeTranscription/DoubaoStreamingTransport.swift`
- Modify: `native/Sources/Application/RealtimeTranscription/OnlineASRProviderFactory.swift`
- Modify: `native/Tests/MiMoSnapshotProviderCheck.swift`
- Modify: `native/Tests/OnlineTranscriptionProviderCheck.swift`
- Modify: `native/Tests/DoubaoStreamingTransportCheck.swift`
- Modify: `native/Tests/CandidateProviderMatrixCheck.swift`
- Modify: `native/Tests/OnlineASRProviderFactoryCheck.swift`
- Create: `native/Tests/OnlineProviderContractBoundaryCheck.sh`

**Rules:**

- Online provider may produce streaming text, but UI still consumes `PreviewViewState`.
- Online failure must fallback local without blocking recording/paste.
- Candidate quality gate applies regardless of provider.
- Provider-specific behavior must not enter UI.
- Online providers must emit the same lifecycle meaning: `completed` is terminal, not quality approval.
- Provider-specific partial/final semantics must be translated before they reach `TranscriptReducer`.

**Entry condition:**

- Tasks 1–11 must be green first.

**Code walkthrough result to lock before RED:**

- `OnlineASRProviderFactory.make(selection:)` currently returns `.disabled` for `.off`, `.unavailable(.missingCredential(...))` for missing key, and `.ready(provider)` only when a key exists.
- `OnlineTranscriptionProvider` maps `OnlineProviderMessage.partial` to `.partial`, `finalized` to `.finalized`, and `completed` to `.completed`; this is the vendor-neutral layer.
- `MiMoSnapshotProvider` is snapshot-based, not true full-duplex streaming; it currently owns rolling samples, pending snapshot, `SenseVoiceBoundaryReconciler`, and `MiMoRequestPartialProjection`.
- `DoubaoStreamingTransport` is transport-only: it connects WebSocket, sends audio frames, receives provider messages, and should not know capsule/UI/final-delivery policy.
- `CandidateProviderMatrixCheck.swift` already tests presentation model behavior across local snapshot, local streaming, and online normalized partials.

**Shared contract:**

```text
Provider output may be partial/finalized/completed.
completed = terminal lifecycle only.
completed != quality-approved paste text.
Quality approval belongs to CandidateTranscriptQualityGate + FinalDeliveryUseCase.
UI only sees projected PreviewViewState / CandidatePresentationModel render state.
Missing online key or online runtime failure must degrade to local provider/offline path.
```

**Implementation Detail Lock:**

Add `native/Tests/OnlineProviderContractBoundaryCheck.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
UI_DIR="$ROOT/native/Sources/Presentation"
ONLINE_FILES=(
  "$ROOT/native/Sources/Infrastructure/RealtimeTranscription/MiMoSnapshotProvider.swift"
  "$ROOT/native/Sources/Infrastructure/RealtimeTranscription/OnlineTranscriptionProvider.swift"
  "$ROOT/native/Sources/Infrastructure/RealtimeTranscription/DoubaoStreamingTransport.swift"
)
FINAL="$ROOT/native/Sources/Application/FinalDeliveryUseCase.swift"

if rg -n 'MiMoSnapshotProvider|DoubaoStreamingTransport|OnlineTranscriptionProvider|OnlineProviderMessage' "$UI_DIR"; then
  echo "online provider details leaked into UI"
  exit 1
fi

if rg -n 'CandidateTranscriptQualityGate|FinalDeliveryUseCase|PasteCoordinator|candidate quality|quality_reason' "${ONLINE_FILES[@]}"; then
  echo "online provider is making final-delivery quality decisions"
  exit 1
fi

grep -q 'CandidateTranscriptQualityGate' "$FINAL"
grep -q 'completed' "$ROOT/native/Sources/Application/RealtimeTranscription/TranscriptionProvider.swift"

echo "OnlineProviderContractBoundaryCheck passed"
```

Update `native/Tests/OnlineASRProviderFactoryCheck.swift` with assertions:

```swift
precondition(factory.make(selection: .off).isDisabled)
precondition(factory.make(selection: .mimoV25).missingCredential == .mimoAPIKey)
precondition(factory.make(selection: .doubao).missingCredential == .doubaoAPIKey)
```

If helper computed properties such as `isDisabled` or `missingCredential` do not exist, define them inside the test file extension only; do not add public production API just for tests.

Update `native/Tests/CandidateProviderMatrixCheck.swift` so the same candidate presentation model accepts:

```swift
["本地", "本地模型", "本地模型输出"]
["米", "米某", "米某在线输出"]
["豆", "豆包", "豆包在线输出"]
```

and rejects stale lower sequence updates for all three.

Expected RED:

- Boundary check may fail if online provider names leaked into UI.
- Existing provider tests may not assert missing-key fallback and lifecycle/quality separation.

Task completion must update this plan with:

- exact provider matrix result for local, MiMo, and Doubao;
- whether MiMo remains snapshot-based or gained a real streaming transport;
- proof that online failure falls back local without blocking recording or paste.

### Task 13: Retirement Gate

**Purpose:** Retire old default behavior only after new path demonstrably matches or beats old behavior.

**Entry conditions:**

- Tasks 1–12 complete.
- No recent old-path rescue needed.
- Real recording matrix passes.
- Architecture review confirms boundaries.

**Required evidence:**

- No repeated-character paste in known phrases.
- No orphan-leading paste.
- No tail loss in 20-second and 2-minute recordings.
- UI remains smooth.
- Online off/local fallback works.
- MiMo/Doubao failure does not affect local.
- `FinalDeliveryUseCase` logs source/reason/quality for every paste.

**Files:**

- Modify: `docs/superpowers/plans/2026-07-19-realtime-transcription-architecture-reconciliation-plan.md`
- Modify: `docs/ARCHITECTURE.md`
- Modify: `docs/开发日志.md`
- Modify runtime wiring files only after all entry conditions pass and the retirement diff is explicitly listed in this task.

**Retirement decision table:**

| Evidence | Decision |
| --- | --- |
| Tasks 1–12 green, parity matrix green, review B accepted | Allow a small retirement PR/task |
| Any tail-loss case remains unclassified | Keep old path available |
| UI smoothness regresses versus old capsule | Keep old UI behavior or port its projection/animation before retirement |
| Online provider failure affects local paste | Keep old local fallback and block retirement |
| Logs cannot explain source choice | Block retirement |

**Implementation Detail Lock:**

This task is a gate, not a deletion task. The first implementation must only write a retirement report:

```markdown
## Retirement Report - Build <build>

- Tasks complete: 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12
- Architecture Review B: accepted / rejected
- 20-second recording: pass / fail, pasted text, source, tail_gap_ms
- 2-minute recording: pass / fail, pasted text, source, tail_gap_ms
- Known duplicate phrases: pass / fail
- Online off/local fallback: pass / fail
- MiMo failure fallback: pass / fail
- Doubao failure fallback: pass / fail
- Decision: retire old default / keep old path / add corrective task
```

Only if the decision is `retire old default`, create the next implementation task with exact files. The likely runtime files to inspect before writing that deletion/migration task are:

- `native/Sources/Application/SpeechInputCoordinator.swift`
- `native/Sources/Application/RealtimePreview/ExperimentalRealtimePreviewPipeline.swift`
- `native/Sources/Application/RealtimePreview/PreviewRequestScheduler.swift`
- `native/Sources/Domain/RealtimePreview/PreviewTranscriptReducer.swift`
- `native/Sources/Application/RealtimeTranscription/LegacyPreviewShadowAdapter.swift`

No developer may delete old preview code inside Task 13 itself.

## Baseline Decision Log

- 2026-07-19: Plan created after development pause. Build 778 remains uncommitted at the time of writing. No runtime code was changed by this planning task.
- 2026-07-19 Task 0 decision: `git status --short` still shows Build 778 edits in `FinalDeliveryUseCase`, `FinalDeliveryUseCaseCheck`, version/build docs, and `native/build_native_app.sh`. Decision is to keep the Build 778 worktree as the current baseline, not commit it and not revert it. Its direct completed-candidate authority is not considered fully accepted; Task 1 must amend it by adding an explicit candidate quality gate, and Task 4 must later complete final source arbitration.

## Task Progress Log

### 2026-07-20 Task B8: Production Delivery Cache Tail Coverage Gate

- Status: implemented, full-version built, installed, and automated checks passed.
- Product trigger:
  - User observed that after pausing and then continuing to speak, preview/final paste could stop producing new content and lose tail words.
  - Log evidence showed a 27.995s recording whose last realtime preview update covered about 27.478s, while final delivery still selected `candidate-preview-cache` with `recognition_ms=0`.
- Boundary:
  - This is not full Task 6 StopTail lane parity.
  - This task only prevents a production realtime preview cache that has not covered the recording tail from becoming final paste authority.
  - No UI, Provider, Reconciler, model, or capsule rendering change.
- Implemented files:
  - `native/Sources/Application/RealtimeTranscription/ProductionRealtimePreviewDeliveryCache.swift`
  - `native/Sources/Application/SpeechInputState.swift`
  - `native/Sources/Application/SpeechInputCoordinator.swift`
  - `native/Tests/ProductionRealtimePreviewDeliveryCacheCheck.swift`
  - `native/Tests/ProductionPreviewDeliveryCacheWiringCheck.sh`
  - `native/Tests/CandidateFinalDeliveryBoundaryCheck.sh`
- RED evidence:
  - `ProductionRealtimePreviewDeliveryCacheCheck` first failed because the cache had no `audioCoverageSeconds` input and no `complete(recordingDurationSeconds:)` tail-coverage contract.
- GREEN contract:
  - Realtime snapshot requests carry `audioCoverageSeconds`.
  - Production delivery cache records the latest preview coverage time.
  - Stop calls `complete(recordingDurationSeconds:)`.
  - If the completed cache is missing coverage information, or if the recording tail gap is greater than the tolerance, `deliverySnapshot()` returns `nil`; `FinalDeliveryUseCase` then falls back to full Final ASR / existing safety path.
- Verification so far:
  - Full version build/install completed as `2.0.46 (Build 788)`; installed app Info.plist verified and codesign passed.
  - `ProductionRealtimePreviewDeliveryCacheCheck passed`
  - `ProductionPreviewDeliveryCacheWiringCheck passed`
  - `FinalDeliveryNamingBoundaryCheck passed`
  - `FinalDeliveryLogBoundaryCheck passed`
  - `CandidateFinalDeliveryBoundaryCheck passed`
  - `git diff --check` passed.
- Remaining:
  - Real installed-app recording: pause, continue speaking, then stop; expected log should not use `candidate-preview-cache` if the last realtime cache did not cover the tail.

### 2026-07-19 Task 1: Candidate Delivery Quality Gate

- Status: automated implementation, installed build, and first real microphone validation complete.
- Implemented files:
  - `native/Sources/Domain/RealtimeTranscription/CandidateTranscriptQualityGate.swift`
  - `native/Sources/Application/FinalDeliveryUseCase.swift`
  - `native/Tests/CandidateTranscriptQualityGateCheck.swift`
  - `native/Tests/FinalDeliveryUseCaseCheck.swift`
- RED evidence:
  - `CandidateTranscriptQualityGateCheck` first failed because `CandidateTranscriptQualityGate` did not exist.
  - `FinalDeliveryUseCaseCheck` first failed because a bad completed shadow-runtime candidate (`代码设计计排查查一下下...`) bypassed final ASR.
- GREEN evidence:
  - `CandidateTranscriptQualityGateCheck passed`
  - `FinalDeliveryUseCaseCheck passed`
  - `git diff --check` passed.
- Rejected reason evidence:
  - `案用户体验验不要了吗？？？` rejects as `repeatedShortUnit`.
  - `了用户体验不要了吗？？` rejects as `orphanLeadingFragment`.
  - `代码设计计排查查一下下到底哪里导致现在的问题。` rejects through the same short repeated-unit family and no longer bypasses final ASR.
- Preserved Build 778 behavior:
  - A complete, meaningful shadow-runtime candidate can still beat full final ASR even when it is shorter than a potentially noisy legacy/preview cache.
  - The abnormal-short gate only applies when the candidate is clearly a short fragment of the preview, avoiding a pure length-ratio veto.
- Build/install:
  - `./native/build_and_log.sh` triggered full version build because local build count reached #84.
  - Installed app verified as `2.0.41 (779)`.
  - codesign verification passed.
- Real validation still required before Task 2:
  - Record “用户体验不要了吗” twice and confirm no orphan-leading/repeated-character paste.
  - Record a longer “今天我们讨论功能优化...” phrase and confirm quality-passing candidate can still win when final ASR is shorter/worse.

### 2026-07-19 Task 1A: Restore Old Path As Final Delivery Authority

- Status: implemented, installed, and automated checks passed.
- Product correction:
  - User confirmed the new candidate path output is not usable and has enabled Final ASR for normal use.
  - The acceptance target changed from “candidate may still win if quality-passing” to “shadow-runtime candidate must never be final paste authority.”
- Implemented files:
  - `native/Sources/Application/FinalDeliveryUseCase.swift`
  - `native/Tests/FinalDeliveryUseCaseCheck.swift`
  - `docs/开发日志.md`
  - `native/Sources/Presentation/VersionHistory/VersionHistoryViewController.swift`
- RED evidence:
  - `FinalDeliveryUseCaseCheck` first failed because Build 779 still let a clean completed `.shadowRuntimeCache` candidate return `source="candidate-preview-cache"` without calling final ASR.
- GREEN evidence:
  - `FinalDeliveryUseCaseCheck passed`
  - `CandidateTranscriptQualityGateCheck passed`
  - `git diff --check` passed.
- New final-delivery contract:
  - `shadowRuntimeSnapshot` is display/diagnostic/migration evidence only.
  - Final candidate cache text may come from `legacyCandidateSnapshot` only.
  - If legacy candidate is missing or not accepted, full final ASR runs; realtime preview remains the safety fallback inside `FinalRecognitionUseCase`.
  - Final reason includes `shadow_authority=disabled`.
- Build/install:
  - `./native/build_and_log.sh` completed build-only install.
  - Installed app verified as `2.0.41 (780)`.
  - codesign verification passed.
- Real validation target:
  - User no longer needs to prove candidate quality.
  - Verify logs show `final_delivery_selected ... shadow_authority=disabled`.
  - Verify normal use no longer pastes text produced solely by the new shadow-runtime candidate path.

### 2026-07-19 Task 2: Candidate Snapshot Assembly / confirmed + volatile 拼接边界

- Status: automated implementation, installed build, and first real microphone validation complete.
- Product boundary:
  - This task only fixes final assembly of `TranscriptState.confirmedText + TranscriptState.volatileText`.
  - It does not decide whether the assembled candidate is good enough to paste.
  - It does not change `SenseVoiceBoundaryReconciler`, `FinalDeliveryUseCase`, Provider scheduling, or UI rendering.
- Implemented files:
  - `native/Sources/Domain/RealtimeTranscription/TranscriptSnapshotAssembler.swift`
  - `native/Sources/Application/RealtimeTranscription/LegacyPreviewShadowAdapter.swift`
  - `native/Tests/TranscriptSnapshotAssemblerCheck.swift`
  - `native/Tests/CandidateDeliverySnapshotCheck.swift`
- RED evidence:
  - `TranscriptSnapshotAssemblerCheck` first failed because `TranscriptSnapshotAssembler` did not exist.
  - `CandidateDeliverySnapshotCheck` first failed because the old state snapshot assembled text through direct concatenation, producing `"用户体验体验不要了吗"`.
- GREEN evidence:
  - `TranscriptSnapshotAssemblerCheck passed`
  - `CandidateDeliverySnapshotCheck passed`
  - `LegacyPreviewShadowAdapterCheck passed`
  - `CandidateDeliverySourceSelectionCheck passed`
  - `FinalDeliveryUseCaseCheck passed`
  - `CandidateTranscriptQualityGateCheck passed`
  - `git diff --check` passed.
- Exact overlap rules implemented:
  - Use longest adjacent suffix/prefix overlap only.
  - If confirmed suffix equals volatile prefix, keep one copy and append the non-overlapping volatile tail.
  - If volatile is entirely the same as the confirmed suffix, return confirmed.
  - If there is no adjacent overlap, append unchanged.
  - Punctuation-only overlap is not trimmed; at least one letter/digit/CJK scalar must be present in the overlap.
- Covered examples:
  - `"用户体验"` + `"体验不要了吗"` => `"用户体验不要了吗"`.
  - `"代码设计"` + `"计排查一下"` => `"代码设计排查一下"`.
  - `"今天我们讨论"` + `"功能优化"` => `"今天我们讨论功能优化"`.
  - `"已经稳定"` + `"已经稳定"` => `"已经稳定"`.
  - `"好好"` + `"学习"` => `"好好学习"`.
  - `"用户体验"` + `"不要了吗"` => `"用户体验不要了吗"`.
- Deliberately not fixed in Task 2:
  - Non-adjacent semantic conflicts such as `"今天我们讨论公司"` + `"功功能可以优化"` still belong to Reconciler seam verification and boundary correction tasks.
  - Repeated characters produced inside a single ASR snapshot, not at the confirmed/volatile seam, still belong to candidate quality gates or future reconciler/provider quality work.
  - Final paste authority remains the old proven path / full final ASR arbitration from Task 1A; shadow-runtime candidate is still display/diagnostic/migration evidence only.
- Build/install:
  - `./native/build_and_log.sh` completed build-only install.
  - Installed app verified as `2.0.42 (784)`.
  - codesign deep/strict verification passed.
- Post-build focused regression:
  - `TranscriptSnapshotAssemblerCheck passed`
  - `CandidateDeliverySnapshotCheck passed`
  - `LegacyPreviewShadowAdapterCheck passed`
  - `CandidateDeliverySourceSelectionCheck passed`
  - `FinalDeliveryUseCaseCheck passed`
  - `git diff --check` passed.
- Real validation target:
  - Installed app record “用户体验不要了吗” and “代码设计排查一下”.
  - Expected candidate/shadow snapshot assembly must not introduce `"体验体验"` or `"设计计"` at the confirmed/volatile seam.
  - If repeated characters still appear inside one provider snapshot, log and route to Reconciler/provider tasks instead of expanding this assembler.
- Real validation evidence:
  - Product owner reported installed Build 784 output: `"用户体验不要流用。代码设机排查一下。"`
  - Interpretation: Task 2 fixed the class of assembler-created adjacent seam duplication; the result did not show `"体验体验"` or `"设计计"`.
  - Remaining defect is recognition/content quality: `"了吗"` became `"流用"` and `"设计"` became `"设机"`. This is not an assembler problem and must be handled by later Provider/Reconciler/final-arbitration tasks with request-level evidence.

### 2026-07-19 Task 2B: Extract Legacy Realtime Preview Delivery Cache / 旧链路可交付缓存封装

- Status: implemented, installed, and automated checks passed; real microphone validation pending.
- Product correction:
  - The 10–18s old realtime preview path is a distinct, proven cache source and must not be hidden behind generic shadow/candidate naming.
  - If final delivery does not use full final ASR, the text must come from the explicitly named legacy realtime preview delivery cache, not from new shadow-runtime.
- Purpose:
  - Extract the old `committedPreviewText + latestPreviewText` / `PreviewDisplaySnapshot(stableWindowText + volatileTailText)` delivery text into a dedicated file and a single getter method.
  - Make final candidate selection and diagnostics point at this cache, so future work can reason about source authority without ambiguity.
- Scope:
  - Create a small wrapper for legacy realtime preview delivery cache.
  - Replace direct construction of legacy delivery snapshots in `ShadowTranscriptionRuntime`.
  - Correct final-candidate selection helper so shadow-runtime is not returned as a final-delivery candidate.
  - Do not change ASR model behavior, realtime preview UI, new `SenseVoiceSnapshotProvider`, or full final ASR settings.
- Implemented files:
  - `native/Sources/Application/RealtimeTranscription/LegacyRealtimePreviewDeliveryCache.swift`
  - `native/Sources/Application/RealtimeTranscription/LegacyPreviewShadowAdapter.swift`
  - `native/Tests/LegacyRealtimePreviewDeliveryCacheCheck.swift`
  - `native/Tests/CandidateDeliverySourceSelectionCheck.swift`
  - `native/Tests/CandidateFinalDeliveryBoundaryCheck.sh`
- RED evidence:
  - `LegacyRealtimePreviewDeliveryCacheCheck` first failed because `LegacyRealtimePreviewDeliveryCache` did not exist.
  - `CandidateDeliverySourceSelectionCheck` first failed because `CandidateDeliverySnapshot.selectForFinalDelivery(...)` still returned `.shadowRuntimeCache`.
- GREEN evidence:
  - `LegacyRealtimePreviewDeliveryCacheCheck passed`
  - `CandidateDeliverySourceSelectionCheck passed`
  - `CandidateDeliverySnapshotCheck passed`
  - `LegacyPreviewShadowAdapterCheck passed`
  - `FinalDeliveryUseCaseCheck passed`
  - `CandidateFinalDeliveryBoundaryCheck.sh passed`
  - `UnifiedRealtimeSourceBoundaryCheck.sh passed`
  - `FinalRecognitionPreviewCacheDefaultCheck.sh passed`
  - `ShadowPreviewIsolationCheck.sh passed`
  - `git diff --check` passed.
- Build/install:
  - `./native/build_and_log.sh` triggered full version build because local build count reached #90.
  - Installed app verified as `2.0.43 (785)`.
  - codesign deep/strict verification passed.
- Real validation target:
  - With full Final ASR disabled, record a short phrase and verify `final_delivery_selected source=candidate-preview-cache`.
  - Expected: the selected candidate comes from `LegacyRealtimePreviewDeliveryCache.deliverySnapshot()` / `.legacyCandidateAdapter`, never `.shadowRuntimeCache`.
  - With full Final ASR enabled, verify final source remains final ASR.

## Review Triggers

Stop development and re-review architecture if any happens:

- Candidate is `completed=true` but final paste is shorter than preview by a product-visible amount.
- Final paste contains repeated-character artifacts: `设计计`, `排查查`, `一下下`, `体验验`, or similar.
- Final paste starts with a likely orphan fragment: one CJK character followed by a sentence fragment.
- Any task changes both FinalDelivery and Provider/Reconciler.
- UI code receives transcript repair logic.
- Real recording gate is skipped.
- Logs cannot explain why candidate or final ASR won.

## Project Manager Gate Before Each Task

- [ ] Developer read this plan.
- [ ] Current task name is stated in chat before coding.
- [ ] Only files listed in the task are modified.
- [ ] RED failed for the intended reason.
- [ ] GREEN passed.
- [ ] `git diff --check` passed.
- [ ] Build/install completed if code changed.
- [ ] Real installed-app validation completed if behavior changed.
- [ ] Plan updated with exact evidence.
- [ ] If the task passed and no review trigger fired, continue to the next task without asking the product owner for routine approval.
- [ ] Stop only at Architecture Review checkpoints, failed gates, unclear ownership, concurrent-work risk, or scope expansion beyond this plan.
