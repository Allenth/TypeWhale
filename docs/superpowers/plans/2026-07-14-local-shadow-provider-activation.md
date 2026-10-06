# Local SenseVoice Shadow Provider Activation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在线 ASR 关闭或缺少凭证时，让旁路1与候选胶囊消费真实有界 `SenseVoiceSnapshotProvider` 的统一状态，而不是继续复制旧生产预览。

**Architecture:** 保留在线 Provider 优先级和旧生产权威；把已经通过 Stage 6 容量门禁的 SenseVoice Provider 提升为旁路的正常本地 fallback。`SpeechInputCoordinator` 只负责会话级 Provider 组装，PCM 继续通过容量 8 的单向 fan-out，候选 Presentation 仍只消费 `PreviewViewState`。`LegacyPreviewShadowAdapter` 只保留为本地配置不可用时的 fail-open 安全网，不再是正常本地路线。

**Tech Stack:** Swift 6.2、Swift Concurrency、现有 Realtime Transcription Core、SenseVoice Snapshot Provider、源码边界检查、`native/build_and_log.sh`。

## Global Constraints

- 每次开发前重读主计划 Global Constraints、Stage 9A、本文和当前 `git status --short`。
- 原胶囊、旧 preview、final ASR、VAD、整理、翻译、历史、OpenClaw、粘贴和录音 120 秒策略不得修改。
- 在线 `.ready` 仍优先使用所选豆包/MiMo；`--debug-shadow-sensevoice` 与 `--debug-shadow-fake-stream` 的显式调试优先级保持。
- 在线 `.disabled` 或 `.unavailable(.missingCredential)` 才进入本地 SenseVoice；只有活动会话配置缺失时才回退 Legacy Adapter。
- 本地 Provider 必须复用 Stage 6 已验收的 admission、fast/correction 容量、300ms 服务熔断和容量 8 PCM fan-out，不新增第二套调度器。
- Candidate、Shadow Presenter、Reducer 和 Projector 不得识别本地/在线 Provider 类型；候选 View 不得处理 snapshot、WAV、SSE 或文本去重。
- 如果安装版候选仍从头重播，下一步只能检查 `SenseVoiceBoundaryReconciler -> TranscriptionEvent -> PreviewViewState` 事件证据；不得在 Candidate View 增加厂商或快照特判。
- 代码改动严格 RED → GREEN；完成后更新主计划、本文、架构、QA、开发日志和版本历史，并通过唯一入口构建、安装、签名与运行验证。
- Stage 9B、Task 14 和长录音生产承诺保持未批准。

## Execution Progress

| Task | Status | Commit | Evidence | Next action |
| --- | --- | --- | --- | --- |
| 0 / Correct route plan | COMPLETE | `d4b2a74` | 主计划与独立计划在生产代码前提交 | Task 1 |
| 1 / Source route and installed build | COMPLETE | `c4c314a` | RED/GREEN、架构复核、聚焦回归、Build 716 构建/安装/签名/运行通过 | Task 2 动态验收 |
| 2 / Installed dynamic acceptance | FAILED — REPAIR OPEN | — | Build 716 会话 `A6DEE89D` 证明本地路由与资源容量正常，但新核心正文按 `13→9→3→4→8→3→4→1` 反复缩短；截图时原胶囊 33 字、两个旁路仅“我要。” | 先完成 Task 2A，再重新执行完整动态矩阵 |
| 2A / Local transcript accumulation repair | FAILED IN REAL UI | `a201956` | Build 717恢复了物理窗口重叠，但真实状态仍按`25→13→9→4→27→32→27→25→26`改写；约18s仍因token弱重叠触发hide/show | 由Task 2B替代，不再继续调cadence |
| 2B / Atomic time-based snapshot assembly | BUILD 720 DESIGN-REVIEWED — REAL UI OPEN | — | 完整版本2.0.21 (720)已构建安装签名；三帧AppKit独立review无P0/P1/P2，本地/MiMo/隔离/最终WAV回归通过 | 执行20s/2m真实录音；确认无缩短/hide-show且原胶囊/final/paste正常 |
| P0 / Build 718 final recording regression | INSTALLED — REAL PASTE CHECK OPEN | — | 4次实录实时缓冲有8–20字，但落盘WAV均为0.25s全静音，`final_asr_empty`阻断粘贴 | Build 718已释放写句柄后再读WAV并覆盖安装；等下一次真实录音确认时长、非静音、`final_asr_result`和粘贴 |

---

## Task 0: Persist The Corrected Route Decision

**Files:**
- Create: `docs/superpowers/plans/2026-07-14-local-shadow-provider-activation.md`
- Modify: `docs/superpowers/plans/2026-07-11-realtime-transcription-shadow-capsule.md`

**Interfaces:**
- Consumes: Stage 6 SenseVoice capacity evidence and 2026-07-14 architecture truth audit.
- Produces: exact local route, rollback boundary and Task 1 implementation gate.

- [x] **Step 1: Record product scope and observable acceptance**

Observable acceptance is exact:

```text
online=off                 -> provider=sensevoice_snapshot source=local_fallback
online=missing credential  -> provider=sensevoice_snapshot source=missing_credential_fallback
online=ready               -> selected online provider
local configuration absent -> provider=legacy_adapter reason=missing_local_configuration
```

The installed app must additionally prove: PCM subscription exists only for a consuming Provider; closing/cancelling ends its Task and queues; original preview/final/paste remain authoritative.

- [x] **Step 2: Commit the route plan before production code**

Run:

```bash
git diff --check
git add docs/superpowers/plans/2026-07-14-local-shadow-provider-activation.md \
  docs/superpowers/plans/2026-07-11-realtime-transcription-shadow-capsule.md
git commit -m "docs(plan): activate local sensevoice shadow route"
```

Expected: documentation-only commit; installed app remains Build 715.

---

## Task 1: Route Normal Local Shadow Sessions Through SenseVoice

**Files:**
- Modify: `native/Sources/Application/SpeechInputCoordinator.swift`
- Create: `native/Tests/LocalSenseVoiceShadowRoutingCheck.sh`
- Modify: `native/Tests/OnlineASRShadowIsolationCheck.sh`
- Modify: `native/Tests/SenseVoiceSnapshotNativeRecognizerSourceCheck.sh`

**Interfaces:**
- Consumes: `activeSession.configuration`, `shadowASR`, `SenseVoiceSnapshotProvider`, `ClosureSenseVoiceShadowResourceAdmission`, `ShadowTranscriptionRuntime(sessionID:provider:)`.
- Produces: a private `makeLocalSenseVoiceShadowRuntime(sessionID:taskID:source:)` assembly boundary; it returns a PCM-consuming runtime when local configuration exists and a Legacy runtime only when configuration is absent.

- [x] **Step 1: RED — require local fallback to use the real Provider**

`LocalSenseVoiceShadowRoutingCheck.sh` must extract `beginShadowPreview` and the new assembly helper, then require:

```text
case .disabled                          -> makeLocalSenseVoiceShadowRuntime(sessionID:taskID:source: "local_fallback")
case .unavailable(.missingCredential)   -> makeLocalSenseVoiceShadowRuntime(sessionID:taskID:source: "missing_credential_fallback")
helper                                  -> SenseVoiceSnapshotProvider + existing admission + provider runtime
helper missing configuration            -> LegacyPreviewShadowAdapter safety fallback
```

It must reject `runtime = ShadowTranscriptionRuntime(sessionID: sessionID)` directly inside `.disabled` or `.unavailable` branches. Update the online isolation order to `debug SenseVoice -> debug fake -> online ready -> local SenseVoice -> Legacy safety fallback`.

- [x] **Step 2: Run RED and record the precise failure**

Run:

```bash
bash native/Tests/LocalSenseVoiceShadowRoutingCheck.sh
bash native/Tests/OnlineASRShadowIsolationCheck.sh
```

Expected: fail because `.disabled` and missing-credential branches still instantiate Legacy directly and the local assembly helper does not exist.

Actual: `LocalSenseVoiceShadowRoutingCheck` failed with `normal local shadow route is missing the SenseVoice assembly helper`; the pre-existing online isolation check still passed.

- [x] **Step 3: GREEN — centralize local Provider assembly**

Implement a private coordinator helper with this behavior:

```swift
private func makeLocalSenseVoiceShadowRuntime(
    sessionID: TranscriptionSessionID,
    taskID: UUID,
    source: String
) -> ShadowTranscriptionRuntime {
    guard let configuration = activeSession?.configuration else {
        LaunchDiagnostics.mark(
            "shadow_preview_mode task_id=\(taskID.uuidString.prefix(8)) provider=legacy_adapter reason=missing_local_configuration"
        )
        return ShadowTranscriptionRuntime(sessionID: sessionID)
    }
    let provider = SenseVoiceSnapshotProvider(
        recognizer: SenseVoiceSnapshotNativeRecognizer(
            bridge: shadowASR,
            configuration: configuration
        ),
        admission: ClosureSenseVoiceShadowResourceAdmission { [weak self] in
            await self?.canAdmitSenseVoiceShadowRecognition() ?? false
        }
    )
    senseVoiceShadowProvider = provider
    LaunchDiagnostics.mark(
        "shadow_preview_mode task_id=\(taskID.uuidString.prefix(8)) provider=sensevoice_snapshot source=\(source)"
    )
    return ShadowTranscriptionRuntime(sessionID: sessionID, provider: provider)
}
```

Use it for forced SenseVoice, `.disabled` and missing-credential fallback. Do not change `.ready`, fake streaming, Candidate, old preview or final paths.

- [x] **Step 4: Run focused and adjacent regressions**

Run the new route check plus Online/Shadow isolation, SenseVoice source/provider/scheduler/reconciler, FanOut, Candidate provider matrix/lifecycle/render boundary and three-capsule wiring checks. Run `git diff --check`.

Expected: all checks pass; Candidate production source remains Provider-neutral; no credential or transcript text enters diagnostics.

Actual: route/Online/Shadow/SenseVoice/FanOut/Candidate/lifecycle/wiring/credential checks passed. The first standalone Reconciler compile omitted `TranscriptionEvent.swift`; rerun with the real dependency passed and was recorded as a harness correction, not a product failure.

- [x] **Step 5: Independent architecture and code review**

Review exact requirements: route precedence, single Provider authority, fail-open Legacy safety fallback, no production-side effect, bounded PCM subscription cleanup and no Candidate data processing. Any finding must receive RED coverage before correction.

Review result: `Conditional`. The smallest effective evolution is to route `.disabled`/missing-key sessions through the already bounded Provider while retaining Legacy only for missing local configuration. Static and focused evidence confirms one runtime Provider and no Candidate/production boundary crossing; Build 716 installed CPU/RSS and old-capsule responsiveness remain the decision-sensitive runtime gate.

- [x] **Step 6: Update evidence, build and install**

Update the main plan, this plan, `docs/ARCHITECTURE.md`, `docs/SHADOW_PREVIEW_QA.md`, `docs/开发日志.md` and `VersionHistoryViewController.swift`; run `./native/build_and_log.sh`. Verify installed version/build, deep/strict signature and the running executable path.

Actual: Build 716 completed through the unique entry point; `/Applications/TypeWhale Pro.app` reports `2.0.19 (716)`, passes deep/strict signature verification and is the running executable. Post-build route/isolation/render/wiring checks passed.

- [x] **Step 7: Commit the built implementation checkpoint**

The `design-review` workflow requires a clean worktree, so commit the reviewed, built and rollback-safe implementation before dynamic visual review. This commit does not close Stage 9A or claim local runtime acceptance.

Run:

```bash
git status --short
git add README.md macos/README.md native/build_native_app.sh \
  native/Sources/Application/SpeechInputCoordinator.swift \
  native/Sources/Presentation/VersionHistory/VersionHistoryViewController.swift \
  native/Tests/LocalSenseVoiceShadowRoutingCheck.sh \
  native/Tests/OnlineASRShadowIsolationCheck.sh \
  docs/ARCHITECTURE.md docs/SHADOW_PREVIEW_QA.md docs/开发日志.md docs/构建日志.md \
  docs/superpowers/plans/2026-07-11-realtime-transcription-shadow-capsule.md \
  docs/superpowers/plans/2026-07-14-local-shadow-provider-activation.md
git diff --cached --check
git commit -m "feat(asr): activate local sensevoice shadow provider"
```

Expected: clean worktree; Task 2 remains `NOT STARTED`.

Actual: committed as `c4c314a`; Task 2 and Stage 9A dynamic acceptance remain open.

**Task 1 Exit Gate:** source routing is real, bounded and installed; Legacy is only a missing-configuration fail-open fallback; Candidate remains a pure presentation consumer. This gate does not prove dynamic old-capsule performance or candidate motion.

---

## Task 2: Run Installed Dynamic Acceptance

**Files:**
- Read runtime: `/Applications/TypeWhale Pro.app`
- Read diagnostics: current TypeWhale launch/runtime log
- Modify after evidence: `docs/SHADOW_PREVIEW_QA.md`
- Modify after evidence: `docs/superpowers/plans/2026-07-14-local-shadow-provider-activation.md`
- Modify after evidence: `docs/superpowers/plans/2026-07-11-realtime-transcription-shadow-capsule.md`

**Interfaces:**
- Consumes: clean committed Build 716 installed app and real microphone sessions.
- Produces: owner-visible route, performance, lifecycle and candidate-experience evidence; no production code unless a failing observation opens a new RED/GREEN repair task.

- [ ] **Step 1: Verify the normal local route in a real session**

With online ASR set to off and shadow preview enabled, record at least 20 seconds. Require:

```text
shadow_preview_mode ... provider=sensevoice_snapshot source=local_fallback
shadow_sensevoice_summary ... max_fast_pending<=1 max_correction_pending<=2 max_concurrent=1
```

Any `provider=legacy_adapter` without `reason=missing_local_configuration` is failure.

- [ ] **Step 2: Run the installed experience matrix**

Run local 20 seconds, local 2 minutes, cancel, two consecutive sessions and experiment-off cleanup. Observe original capsule responsiveness, technical truth, candidate no-from-head motion, final result and paste. Then run the approved MiMo 20-second comparison without changing MiMo transport semantics.

- [ ] **Step 3: Perform differential design review**

Compare candidate rhythm against the technical capsule and the prior failure video. Cover first text, append motion, non-prefix revision, flicker, jump, context retention, cancellation and hide. No static visual/layout change is expected; any dynamic finding must be backed by video/log/session evidence.

- [ ] **Step 4: Record acceptance or open a focused repair task**

If every matrix item passes, update both plans and QA with exact session evidence and close the local-route portion of Stage 9A. If any item fails, keep Stage 9A open and create a RED at the owning layer: Provider/Reconciler/Core for data truth, PresentationModel/Motion for visual time, never Candidate View string handling.

**Task 2 Exit Gate:** real Build 716 evidence proves local Provider routing, bounded resources, no old-path regression and acceptable candidate experience. MiMo and the remaining full Stage 9A matrix still gate Stage 9B.

---

## Task 2A: Repair Local Transcript Accumulation Before Resuming Acceptance

**Failure evidence:** Build 716 real session `A6DEE89D` (2026-07-15 22:53:55–22:54:28 CST) accepted all 330 PCM frames, completed 20 recognitions, kept `max_fast_pending=1`, `max_correction_pending=1`, `max_concurrent=1` and reported no resource/capacity degradation. Despite healthy execution, the production preview reached 33 characters while Shadow/Candidate repeatedly collapsed to the latest 1–8 characters. The screenshot hotkey at recording second 25 captured both new capsules showing “我要。” immediately after `sequence=16 chars=3`.

**Root cause:** `.initial` schedules correction every 10 seconds while retaining/requesting at most 8 seconds of correction audio. Adjacent correction snapshots therefore contain an approximately 2-second audio gap and cannot satisfy the reconciler's overlap contract. No stable transcript is accumulated. Meanwhile each 3-second fast result replaces the shared `sensevoice-tail` partial. A correction recovery emits `.failed(isRecoverable: true)`, and the provider-neutral Candidate projection correctly clears failed state, creating a hide/show flash. This is a Provider/Reconciler defect; Candidate Presentation must remain unchanged.

**Files:**
- Modify: `native/Tests/SenseVoiceSnapshotProviderCheck.swift`
- Modify: `native/Sources/Infrastructure/RealtimeTranscription/SenseVoiceSnapshotProvider.swift`
- Modify only if the RED proves necessary: `native/Sources/Infrastructure/RealtimeTranscription/SenseVoiceBoundaryReconciler.swift`
- Do not modify: `native/Sources/Presentation/CandidatePreview/*`

**Interfaces:**
- Consumes: bounded continuous PCM, overlapping correction snapshots and fast tail snapshots.
- Produces: monotonically append-only confirmed transcript plus a bounded revisable tail; recoverable boundary diagnostics must not erase an otherwise healthy visible transcript.

- [x] **Step 1: RED — reproduce the 30-second collapse through the real Provider/Session**

  Add a deterministic recognizer whose output is derived from each request's audio range. Require multiple correction cycles, at least one non-prefix fast revision, and assert:
  - correction audio ranges have positive overlap and no uncovered timeline gap;
  - confirmed text advances after the second correction and never shrinks;
  - projected display retains earlier confirmed content while the volatile tail changes;
  - no recoverable boundary diagnostic clears the visible candidate state during the healthy overlap scenario.

  Actual RED: the new Provider/Session test failed with `adjacent correction snapshots must overlap; got gap between 2...9 and 12...19`. This is the expected product defect, not a harness or compile failure.

- [x] **Step 2: GREEN — restore the Provider overlap invariant**

  Make correction cadence/window/rolling capacity internally consistent so every adjacent correction snapshot overlaps by an explicit bounded amount. Keep fast input bounded, one active recognition, latest-only fast scheduling and correction capacity unchanged. Do not concatenate strings in Candidate or expose correction semantics above the Provider.

  Actual GREEN: `.initial.correctionIntervalSeconds` changed from 10s to 6s while the correction/rolling window remains 8s. The same 30s real Provider/Session test now observes overlapping correction snapshots and passes without changing scheduler capacity or Candidate code.

- [x] **Step 3: GREEN — preserve confirmed truth across fast updates**

  Ensure fast partials revise only the volatile tail while confirmed segments remain authoritative in `TranscriptState`. Boundary recovery remains diagnostic, but an expected recoverable seam miss must not turn an otherwise running transcript into an empty Candidate frame.

  Actual GREEN: the accumulated confirmed prefix remains append-only across subsequent fast partials, and the healthy overlapping fixture publishes no failure state. Existing Reducer/Projector/Candidate boundaries required no production change.

- [x] **Step 4: Run focused and adjacent regressions**

  Run Provider, Reconciler, Reducer, Projector, Candidate projection/motion/render boundary, fan-out, local routing, online isolation and three-capsule wiring checks. Confirm queues and PCM retention remain bounded.

  Actual: all listed focused and adjacent checks passed. Two initial ad-hoc compile commands omitted existing harness dependencies; corrected commands passed and no product code was changed for those harness errors.

- [ ] **Step 5: Update evidence, build, install and visually review**

  Update main plan, QA, architecture, development log and version history; run the unique build entry, verify installed version/signature/process, then perform `design-review` against a fresh local 20-second recording. The 2-minute matrix remains required before Task 2 closes.

  Build evidence: automatic build count 42 produced full version `2.0.20 (717)` through `./native/build_and_log.sh`; installation, launch, deep/strict signature and post-build Provider/local-route/online-isolation/Candidate-boundary/three-capsule checks passed. Real 20-second visual evidence is still required before checking this step.

**Task 2A Exit Gate:** deterministic tests and a real installed local recording prove that Shadow/Candidate retain accumulated context, only the volatile tail revises, no from-head replay/hide flash occurs, and original preview/final/paste remain unchanged.

---

## P0 Interruption: Restore Final Recording and Paste Before Candidate Work

**Build 718 failure evidence:** four real sessions lasted 1.98–3.96 seconds and produced live preview text, but every saved final WAV is exactly 0.25 seconds of `-91 dB` silence. Logs terminate at `final_asr_empty`; paste is never invoked. The regression was introduced when `AVAudioFile` became a retained `currentFile`: `stop()` now reopens the pending URL before releasing that writer, so the reader sees zero source frames and `writeFinalRecording` outputs only its 0.25-second tail padding.

- [x] RED: add a finalization-order contract proving the retained writer is closed before the pending WAV is reopened.
- [x] GREEN: close `currentFile` after the processing group drains and before `writeFinalRecording`; preserve converter/session state until pending realtime recovery completes.
- [x] Regression: finalization order, hot switch, configuration recovery, input binding and manual capture boundaries pass; Build 718 compiled, installed, launched and passed deep/strict signing.
- [ ] Installed acceptance: record a fresh phrase in the installed build; require saved WAV duration to match the session (plus bounded tail), non-silent audio, `final_asr_result chars>0`, and a successful paste into the tracked target.
- [ ] Update this plan with exact build/session evidence, then resume Task 2B without changing Candidate presentation responsibilities.

---

## Task 2B: Replace Patch Fixes With Atomic Time-Based Snapshot Assembly

**Build 717 failure evidence:** real local sessions route correctly and remain resource-bounded, but the unified target still changes `25→13→9→4→27→32→27→25→26`. Candidate can lag a 32-character target at 4 visible characters because it withholds up to 24 characters at 50ms each. At approximately 18 seconds, a real overlapping correction still emits recovery failure because token text differs across snapshots; Candidate clears and shows again. Build 717 therefore fails the user-visible gate and Task 2A is not accepted.

**Product invariants:**
- A local recognition completion publishes exactly one atomic transcript state.
- Stable text advances by audio time and never depends on exact repeated words across snapshots.
- Fast and correction results share one Provider-local assembler; fast may not replace the whole transcript tail independently.
- A missing textual seam is a Provider diagnostic, not a UI-clearing failure. With a forward audio range, the assembler preserves prior context and advances safely.
- Candidate reveals the complete latest `PreviewViewState` immediately. Motion may not withhold transcript characters or create target/display debt; future decoration must not affect content timing.
- Candidate/View remain Provider-neutral. No SenseVoice, MiMo, snapshot, WAV or reconciliation branch enters Presentation.

**Files:**
- Modify: `native/Sources/Domain/RealtimeTranscription/TranscriptionEvent.swift`
- Modify: `native/Sources/Domain/RealtimeTranscription/TranscriptReducer.swift`
- Modify: `native/Sources/Infrastructure/RealtimeTranscription/SenseVoiceBoundaryReconciler.swift`
- Modify: `native/Sources/Infrastructure/RealtimeTranscription/SenseVoiceSnapshotProvider.swift`
- Modify: `native/Sources/Presentation/CandidatePreview/CandidateTextMotion.swift`
- Modify focused tests for Reducer, Reconciler, Provider, Candidate Motion/Model/Matrix/Lifecycle.
- Do not modify Candidate View text reconciliation, old preview, final, paste, MiMo transport or recording policy.

- [x] **Step 1: RED — encode the three real failures**

  Require an atomic transcript event to append confirmed segments and replace the volatile tail in one Reducer state. Feed overlapping snapshots whose text differs inside the overlap; require stable progress by audio time without failure. Feed the Build 717 target pattern to Candidate; require every accepted state to be fully visible immediately with no Timer debt.

- [x] **Step 2: GREEN — add one provider-neutral atomic transcript event**

  Add a semantic event that carries newly finalized segments and the current volatile tail together. Reducer applies it once and broadcasts one state. Existing partial/finalized contracts remain for streaming providers.

- [x] **Step 3: GREEN — reconcile every local snapshot by audio time**

  Send both fast and correction outputs through one chronological reconciler. Use validated token timestamps when available and proportional token positions otherwise. Advance a monotonic confirmed audio frontier at the midpoint of overlapping audio; exact token equality is optional evidence, never the commit gate. A true forward gap commits the previous remaining tail before starting the next range and records recovery internally without `.failed`.

- [x] **Step 4: GREEN — remove content-withholding animation**

  Candidate Motion immediately sets visible count to target count for every accepted state. Coordinator/View contracts stay unchanged and Provider-neutral; no Timer is needed for text visibility.

- [ ] **Step 5: Full regression, build, install and real acceptance**

  Run Domain/Core/Provider/Scheduler/Reconciler/Candidate/FanOut/online/MiMo/three-capsule regressions. Update architecture, QA, plans, development log and version history. Build/install through the unique entry, verify signature/process, then use fresh 20-second and 2-minute real local sessions to require: no full-target shrink, no hide/show, target equals displayed on every render, original preview/final/paste normal, and bounded CPU/RSS/queues.

  Actual (automated/build portion): Domain/Core/30-second local Provider/Candidate Motion/Model/Matrix/Lifecycle, online completion, full MiMo snapshot matrix, shadow/online isolation, route/wiring/render boundaries and final-WAV lifecycle pass. Build 719 was compiled, installed and launched through the unique entry; deep/strict signing and post-install gates pass. Independent visual review and real 20-second/2-minute microphone acceptance remain open, so Step 5 and Stage 9A are not complete.

  Build 720 refinement: a new RED proved confirmed segment audio ranges overlapped; Provider now advances a monotonic confirmed-audio cursor and the 30-second test requires non-overlapping valid ranges. The automatic third-build cadence produced full version `2.0.21 (720)`; compile/install/launch/signing and fresh local Provider, MiMo, route/isolation/render/final-WAV gates pass. Real visual/final/paste acceptance remains open.

  Design review: current `CandidatePreviewView` rendered waiting, atomic short revision and long latest-state frames at Retina scale. Short content is complete in one frame; long content retains the existing head-truncation rule and latest suffix; no blank/intermediate/old-text frame or style/layout regression was found (P0/P1/P2: none). Dynamic microphone rhythm remains an installed acceptance gate.

**Task 2B Exit Gate:** real installed logs and owner-visible behavior both prove atomic data truth and zero intentional UI text lag. Synthetic fixtures alone cannot close this task.
