# Realtime Cache Authority Cutover Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **硬规则:** 每个 Task 开工前必须先读本文；每个 Task 完成后必须更新本文进度；每次只做一个 Task。

**Goal:** 主胶囊和最终粘贴都改为订阅生产实时缓存；完整 Final ASR 只有用户打开“停止后重新识别整段录音”开关时才允许运行。

**Architecture:** `RealtimePreviewDeliveryCache` 是实时预览可交付文本的唯一缓存出口；主胶囊只展示缓存/状态投影，最终粘贴只由 `FinalDeliveryUseCase` 决定。旁路和候选只保留诊断/迁移观察身份，不再影响主胶囊或最终交付。

**Tech Stack:** Swift/AppKit、`SpeechInputCoordinator`、`FinalDeliveryUseCase`、`FinalRecognitionUseCase`、`ProductionRealtimePreviewDeliveryCache`、`RealtimePreviewDeliveryCache`、shell/Swift 回归测试。

## Global Constraints

- 默认只在主目录 `$HOME/Pictures/macOSwinOSCoding/TypeSpeaker` 开发；禁止新建 worktree，除非用户明确要求或主目录不可安全开发。
- 每次只做一个 Task；禁止一个 Task 同时修改 Final ASR 策略、主胶囊 UI、缓存分块算法。
- 开关语义必须清楚：`reRecognizeWholeRecordingAfterStop == false` 时不得调用完整 Final ASR。
- UI 层不修文本、不拼最终稿、不决定最终粘贴来源。
- 旁路/候选不做产品主链路；只允许作为诊断对照。
- 普通验证构建不递增版本号；完整版本构建只在用户明确要求或发布节奏要求时执行。
- 代码改动必须 RED → GREEN → 验证 → 更新本文 → commit。

---

## Current Facts

- 当前分支：`codex/typewhale-pro-asr-hotwords`。
- 当前只剩主目录 worktree。
- 当前设置值确认：`com.waykingah.typewhale.pro reRecognizeWholeRecordingAfterStop = 0`。
- Task 1 后确认：`reRecognizeWholeRecordingAfterStop == false` 时不再调用完整 Final ASR；已有实时文本时会交付可见实时预览文本，缓存为空才返回 `realtime-preview-cache-unavailable`。
- Task 2 后确认：生产预览状态桥和主胶囊文字协调器在 `ShadowPreviewRuntimeGate` 之前启动；关闭旁路实验预览窗不再阻断主胶囊文字订阅。
- Task 3 后确认：最终交付候选只读取 `productionRealtimePreviewDeliveryCache.deliverySnapshot()`；shadow/candidate runtime 只作为诊断输入，不再作为最终粘贴权威。

## Target Runtime Flow

```text
实时识别/实时快照
→ ProductionRealtimePreviewDeliveryCache / RealtimePreviewDeliveryCache
→ 主胶囊显示
→ FinalDeliveryUseCase
→ 粘贴
```

只有用户打开完整重识别开关时：

```text
停止录音后的完整音频
→ Final ASR
→ FinalDeliveryUseCase
→ 粘贴
```

## Task 1: Lock Final ASR Switch Boundary

**Status:** Completed

**Goal:** 开关关闭时，最终交付绝不调用完整 Final ASR；缓存不可交付时返回明确失败/空结果和日志原因，而不是偷偷兜底。

**Files:**

- Modify: `native/Sources/Application/FinalRecognitionUseCase.swift`
- Modify: `native/Sources/Application/FinalDeliveryUseCase.swift`
- Modify: `native/Tests/FinalRecognitionUseCaseCheck.swift`
- Modify: `native/Tests/FinalDeliveryUseCaseCheck.swift`
- Modify: `docs/superpowers/plans/2026-07-20-realtime-cache-authority-cutover.md`
- Modify: `docs/开发日志.md`

**Interfaces:**

- Consumes: `FinalRecognitionRequest.reRecognizeWholeRecordingAfterStop`
- Produces: when switch is off and candidate cache is invalid, `FinalRecognitionOutcome.empty(FinalRecognitionResult(engine: "realtime-preview-cache-unavailable", ...))`
- Produces: `final_delivery_selected reason` must say realtime cache unavailable and Final ASR disabled by user switch.

**Steps:**

- [x] RED: add a test in `FinalRecognitionUseCaseCheck.swift` proving switch off + empty candidate must not call the final transcriber.
- [x] RED: add a test in `FinalDeliveryUseCaseCheck.swift` proving delivery reason does not say `final ASR authoritative` when switch is off.
- [x] Run tests and verify they fail for the current bug. Evidence: `FinalRecognitionUseCaseCheck` failed at “candidate cache unavailable and Final ASR switch is off”.
- [x] GREEN: update `FinalRecognitionUseCase.recognize(...)` so `transcriber.transcribe(...)` is called only when `reRecognizeWholeRecordingAfterStop == true`.
- [x] GREEN: update `FinalDeliveryUseCase.reason(...)` wording for the disabled-Final-ASR path.
- [x] Run targeted tests:

```bash
swiftc native/Sources/Domain/Text/RecognitionTextFilter.swift native/Sources/Domain/Text/RecognitionTextNormalizer.swift native/Sources/Application/FinalRecognitionUseCase.swift native/Tests/FinalRecognitionUseCaseCheck.swift -o /tmp/FinalRecognitionUseCaseCheck && /tmp/FinalRecognitionUseCaseCheck

swiftc native/Sources/Domain/Text/RecognitionTextFilter.swift native/Sources/Domain/Text/RecognitionTextNormalizer.swift native/Sources/Domain/RealtimePreview/PreviewDisplaySnapshot.swift native/Sources/Domain/RealtimeTranscription/TranscriptionIdentity.swift native/Sources/Domain/RealtimeTranscription/TranscriptionEvent.swift native/Sources/Domain/RealtimeTranscription/TranscriptState.swift native/Sources/Domain/RealtimeTranscription/PreviewViewState.swift native/Sources/Application/RealtimeTranscription/PreviewStateProjector.swift native/Sources/Domain/RealtimeTranscription/TranscriptSnapshotAssembler.swift native/Sources/Domain/RealtimeTranscription/TranscriptReducer.swift native/Sources/Application/RealtimeTranscription/TranscriptionBroadcaster.swift native/Sources/Application/RealtimeTranscription/TranscriptionProvider.swift native/Sources/Application/RealtimeTranscription/TranscriptionSession.swift native/Sources/Application/RealtimeTranscription/RealtimePreviewDeliveryCache.swift native/Sources/Application/RealtimeTranscription/LegacyPreviewShadowAdapter.swift native/Sources/Domain/RealtimeTranscription/CandidateTranscriptQualityGate.swift native/Sources/Application/FinalRecognitionUseCase.swift native/Sources/Application/FinalDeliveryUseCase.swift native/Tests/FinalDeliveryUseCaseCheck.swift -o /tmp/FinalDeliveryUseCaseCheck && /tmp/FinalDeliveryUseCaseCheck
```

- [x] Run boundary grep test:

```bash
bash native/Tests/FinalRecognitionPreviewCacheDefaultCheck.sh
bash native/Tests/FinalDeliveryLogBoundaryCheck.sh
```

- [x] Full app compile/install verification:

```bash
./native/build_native_app.sh
./native/release_local_build.sh --install-only
```

- [x] Update this Task status and `docs/开发日志.md`.
- [x] Commit:

```bash
git add native/Sources/Application/FinalRecognitionUseCase.swift native/Sources/Application/FinalDeliveryUseCase.swift native/Tests/FinalRecognitionUseCaseCheck.swift native/Tests/FinalDeliveryUseCaseCheck.swift docs/superpowers/plans/2026-07-20-realtime-cache-authority-cutover.md docs/开发日志.md
git commit -m "fix(delivery): honor final asr switch boundary"
```

**Acceptance:**

- 开关关 + 缓存空：不调用 Final ASR。
- 开关关 + 缓存有效：粘贴缓存。
- 开关关 + 严格尾巴覆盖不完整但已有实时文本：不能返回 `nil`；必须有多少交付多少，缺失风险只进入日志/reason，不默认污染正文。
- 开关开：允许完整 Final ASR。
- 日志原因不再把关着的 Final ASR 说成 authoritative。

## Task 2: Make Main Capsule Independent From Shadow Preview Toggle

**Status:** Completed

**Goal:** 关闭旁路实验预览窗时，主胶囊仍能正常显示实时文本。

**Files:**

- Modify: `native/Sources/Application/SpeechInputCoordinator.swift`
- Modify: `native/Sources/Application/RealtimeTranscription/ProductionPreviewStateBridge.swift`
- Modify: `native/Sources/Application/RealtimeTranscription/ProductionPreviewTextCoordinator.swift`
- Test: add or modify `native/Tests/PreviewSubscribersBoundaryCheck.sh`
- Test: add or modify `native/Tests/UnifiedRealtimeSourceBoundaryCheck.sh`
- Modify: this plan and `docs/开发日志.md`

**Interfaces:**

- Consumes: production realtime preview snapshot/state.
- Produces: main capsule update independent of `ShadowPreviewRuntimeGate`.

**Steps:**

- [x] Code read: traced `beginShadowPreview(...)`, `applyRealtimePreview(...)`, `applyExperimentalPreviewState(...)`, `productionPreviewStateBridge`, and `productionPreviewTextCoordinator`.
- [x] RED: boundary tests exist for main capsule subscription independence: `PreviewSubscribersBoundaryCheck.sh` and `ProductionPreviewSourceIndependenceBoundaryCheck.sh`.
- [x] GREEN: production preview bridge/coordinator starts before `ShadowPreviewRuntimeGate.shouldStart`; `productionPreviewStateBridge.consume(productSnapshot)` runs before `publishShadowPreview(...)`.
- [x] Verify targeted boundary tests: `PreviewSubscribersBoundaryCheck.sh` and `ProductionPreviewSourceIndependenceBoundaryCheck.sh` passed.
- [x] Update this plan and commit.

**Acceptance:**

- 关闭旁路实验预览窗，主胶囊仍出字。
- 旁路开关只影响旁路诊断窗口，不影响主胶囊。

## Task 3: Promote RealtimePreviewDeliveryCache As Single Delivery Source

**Status:** Completed

**Goal:** 如果最终不是用户主动开启的 Final ASR，则最终粘贴文本只来自 `RealtimePreviewDeliveryCache`，不来自候选 UI runtime 或 shadow UI runtime。

**Files:**

- Modify: `native/Sources/Application/FinalDeliveryUseCase.swift`
- Modify: `native/Sources/Application/SpeechInputCoordinator.swift`
- Modify: `native/Sources/Application/RealtimeTranscription/RealtimePreviewDeliveryCache.swift`
- Modify: `native/Sources/Application/RealtimeTranscription/ProductionRealtimePreviewDeliveryCache.swift`
- Test: `native/Tests/RealtimePreviewDeliveryCacheWiringCheck.sh`
- Test: `native/Tests/ProductionPreviewDeliveryCacheWiringCheck.sh`
- Modify: this plan and `docs/开发日志.md`

**Steps:**

- [x] Code read: final delivery receives `shadowRuntimeSnapshot` only for diagnostics and `realtimePreviewDeliverySnapshot` from `productionRealtimePreviewDeliveryCache.deliverySnapshot()` as the only realtime delivery candidate.
- [x] RED: updated tests to require `realtimePreviewDeliveryCache` source and `realtime-preview-delivery-cache` final engine; tests failed because the source case did not exist.
- [x] GREEN: added `CandidateDeliverySnapshotSource.realtimePreviewDeliveryCache`; production/realtime caches now return that source; `FinalRecognitionUseCase` passes through the selected cache engine.
- [x] Verify logs: `final_delivery_selected` can emit `source=realtime-preview-delivery-cache`; `final_asr_result` maps it to `source=realtime_preview_delivery_cache`.
- [x] Update this plan and commit.

**Acceptance:**

- 日志能明确说明最终来自 realtime delivery cache。
- 旁路/候选 runtime 不再是最终粘贴权威。

## Task 4: Fix 10s/18s Pause Boundary Stalls

**Status:** Completed

**Goal:** 解决“卡在如果”：10 秒软切、VAD 停顿误判、短 chunk 识别失败时，主胶囊不冻结死，最终缓存不丢后续内容。

**Files:**

- Modify: `native/Sources/Infrastructure/Audio/AudioRecorder.swift`
- Modify: `native/Sources/Application/SpeechInputCoordinator.swift`
- Modify: `native/Sources/Application/RealtimeTranscription/ProductionRealtimePreviewDeliveryCache.swift`
- Test: `native/Tests/ProductionRealtimePreviewDeliveryCacheCheck.swift`
- New test if needed: `native/Tests/RealtimePauseBoundaryStallCheck.swift`
- Modify: this plan and `docs/开发日志.md`

**Steps:**

- [x] Code read: traced `realtimeVoiceActive`, `isChunkFinal`, `pendingFinalSnapshots`, `pendingRealtimeSnapshot`, `realtimeBusy`, and `session.committedPreviewText`.
- [x] RED: added `RealtimeStopDrainBoundaryCheck.sh`, proving stop-time realtime drain must happen before delivery cache completion and before pending realtime snapshots are discarded.
- [x] GREEN: added state-driven `drainRealtimePreviewForFinalDelivery(...)`; stop flow now waits for realtime in-flight/pending queues to empty or logs bounded timeout, then completes delivery cache.
- [x] Diagnostic log added: `realtime_stop_drain_completed` / `realtime_stop_drain_timeout`.
- [x] Verify targeted tests: `RealtimeStopDrainBoundaryCheck.sh`, `ChunkCommitStateCheck`, `ProductionRealtimePreviewDeliveryCacheCheck`, `FinalDeliveryUseCaseCheck`, `ProductionPreviewDeliveryCacheWiringCheck.sh`, `CandidateFinalDeliveryBoundaryCheck.sh`, `FinalRecognitionPreviewCacheDefaultCheck.sh`, and `git diff --check` passed.
- [x] Update this plan and commit.

**Acceptance:**

- 10 秒后停顿再继续说，主胶囊继续更新。
- 停止时不会把“如果”这类半句当完整最终稿。

## Task 5: Main Capsule Uses New Cache Without UI Rewrite

**Status:** Completed

**Goal:** 主胶囊先只换数据源，不改视觉、不改动画，让显示和交付同源。

**Files:**

- Modify: `native/Sources/Presentation/Capsule/RecordingCapsuleView.swift`
- Modify: `native/Sources/Presentation/Capsule/RecordingPanel.swift`
- Modify: `native/Sources/Application/SpeechInputCoordinator.swift`
- Test: `native/Tests/MainCapsulePreviewTextMigrationBoundaryCheck.sh`
- Test: `native/Tests/MainCapsuleRenderStateCheck.swift`
- Modify: this plan and `docs/开发日志.md`

**Steps:**

- [x] RED: existing boundary checks cover the intended boundary: `MainCapsulePreviewTextMigrationBoundaryCheck.sh`, `PreviewSubscribersBoundaryCheck.sh`, and `ProductionPreviewSourceIndependenceBoundaryCheck.sh`.
- [x] GREEN: verified existing wiring: `productSnapshot` feeds both `productionRealtimePreviewDeliveryCache.consume(...)` and `productionPreviewStateBridge.consume(...)`; `ProductionPreviewTextCoordinator` projects `PreviewViewState` back to `PreviewDisplaySnapshot` and calls `RecordingPanel.updateDraft(_ snapshot:)`.
- [x] Verify old capsule states still compile: no `RecordingCapsuleView` / `RecordingPanel` drawing code changed in this task; `MainCapsulePreviewTextMigrationBoundaryCheck.sh`, `ProductionPreviewStateBridgeCheck`, and `PreviewDisplaySnapshotProjectorCheck` passed.
- [x] Update this plan and commit.

**Acceptance:**

- 主胶囊显示和最终粘贴同源。
- UI 动画仍由 UI 展示层控制，数据层不驱动动画细节。

## Task 6: Retire Experimental Product Coupling

**Status:** Completed

**Goal:** 主链路稳定后，旁路/候选只保留诊断身份，默认关闭，不再出现在产品主流程。

**Files:**

- Modify: `native/Sources/Application/SpeechInputCoordinator.swift`
- Modify: `native/Sources/Presentation/CandidatePreview/*` if needed
- Modify: `native/Sources/Presentation/Notch/NotchPreviewPresenter.swift` if needed
- Test: `native/Tests/ShadowPreviewIsolationCheck.sh`
- Test: `native/Tests/ThreeCapsuleWiringCheck.sh`
- Modify: this plan and `docs/开发日志.md`

**Steps:**

- [x] Code read: located user-visible toggles and diagnostic windows for `shadowPreviewEnabled`, online shadow provider selection, `CandidatePreviewCoordinator`, and `ShadowPreviewCoordinator`.
- [x] RED: existing isolation tests lock this boundary: `ShadowPreviewIsolationCheck.sh`, `ThreeCapsuleWiringCheck.sh`, `ProductionPreviewSourceIndependenceBoundaryCheck.sh`, `CandidateFinalDeliveryBoundaryCheck.sh`, and `ProductionPreviewDeliveryCacheWiringCheck.sh`.
- [x] GREEN: verified current implementation already isolates diagnostics: shadow/candidate windows are behind diagnostic settings; final delivery candidate comes from production realtime cache, not candidate UI runtime.
- [x] Verify main dictation path boundary tests passed.
- [x] Update this plan and commit.

**Acceptance:**

- 产品主流程只有主胶囊。
- 旁路/候选不会影响主胶囊和最终粘贴。

## Task 7: Remove Product Realtime WAV Disk Writes

**Status:** Completed

**Goal:** 产品实时预览的小片段识别不再每 0.5 秒写 `.realtime-*.wav` 到硬盘；主胶囊/最终缓存继续使用同一条生产实时缓存。完整停止录音文件、历史记录、Final ASR、实验校准 `.reconcile` / `.tail-reconcile` 诊断文件不在本任务里改。

**Files:**

- Modify: `native/TypeSpeakerNativeASR.h`
- Modify: `native/TypeSpeakerNativeASR.c`
- Modify: `native/Sources/Infrastructure/ASR/SenseVoiceASR.swift`
- Modify: `native/Sources/Infrastructure/Audio/AudioRecorder.swift`
- Modify: `native/Sources/Application/SpeechInputState.swift`
- Modify: `native/Sources/Application/SpeechInputCoordinator.swift`
- Test: add `native/Tests/RealtimePreviewMemoryAudioBoundaryCheck.sh`
- Modify: this plan and `docs/开发日志.md`

**Steps:**

- [x] RED: add a boundary test proving product realtime snapshots are samples/PCM, not required `.realtime-*.wav` files.
- [x] RED: verify the new boundary test fails on current code.
- [x] GREEN: add native samples transcribe API and Swift wrapper.
- [x] GREEN: change `AudioRecorder.onRealtimeSnapshot` / `RealtimeSnapshotRequest` to carry samples + sample rate for product realtime preview.
- [x] GREEN: route `SpeechInputCoordinator.transcribeRealtime(...)` through the samples API.
- [x] Keep experimental corrected preview on file URLs for now; document it as diagnostic exception.
- [x] Run targeted boundary/Swift tests and native build/install.
- [x] Update this Task status, `docs/开发日志.md`, and commit.

**Acceptance:**

- 正常主胶囊实时预览不再生成 `.realtime-*.wav`。
- 停止后的完整录音文件仍正常生成。
- Final ASR 开关语义不变：关着就不自动完整重识别。
- 实验校准链路仍可用，但它的写盘属于单独后续任务，不混进产品主链路。

## Task 8: Gate Realtime ASR During Silence And Pause Tail

**Status:** Completed

**Goal:** 静音、停止说话后的无声尾巴、停顿后的低噪声片段，不再送进 realtime ASR 产出“我想。”、“I.”这类短幻觉；不新增 VAD 推理，只复用录音过程中已有的人声探测状态。

**Files:**

- Modify: `native/Sources/Application/SpeechInputCoordinator.swift`
- Modify: `native/Sources/Domain/Text/RecognitionTextFilter.swift`
- Modify: `native/Tests/RecognitionTextNormalizerCheck.swift`
- Test: add `native/Tests/RealtimeSilenceGateBoundaryCheck.sh`
- Modify: this plan and `docs/开发日志.md`

**Steps:**

- [x] RED: add a boundary test proving `transcribeRealtime(...)` must check silence gate before calling `realtimeASR.transcribe(...)`.
- [x] RED: add filter assertions for “我想。” and “I.” as realtime-preview silence hallucinations.
- [x] Verify both RED checks fail on current code.
- [x] GREEN: track latest voice-probe result and capture time in `SpeechInputCoordinator`.
- [x] GREEN: before realtime ASR, skip clearly silent snapshots using recent VAD state + short voice grace.
- [x] GREEN: for silent final chunk snapshots, freeze existing current text but do not run ASR.
- [x] GREEN: add “我想” and “i” to realtime-preview short hallucination filters.
- [x] Run targeted tests and native build/install.
- [x] Update this Task status, `docs/开发日志.md`, and commit.

**Acceptance:**

- 静音开始录音不会显示“我想。”、“I.”。
- 停止说话后的尾巴不会追加短幻觉。
- 刚开口不会因为 VAD 滞后吞掉开头字。
- 不新增 VAD 模型调用；性能不变或更省。
- 不改 Final ASR 开关、最终粘贴策略和胶囊 UI。

## Task 9: Narrow Silence Gate To Final Chunk Only

**Status:** Completed

**Goal:** 修复 Task 8 回归：VAD 误判无声时，普通 realtime snapshot 不再被 silence gate 拦截，避免主胶囊无字但旁路1有内容。保留 final chunk 无声收尾保护和短幻觉过滤。

**Files:**

- Modify: `native/Sources/Application/SpeechInputCoordinator.swift`
- Modify: `native/Tests/RealtimeSilenceGateBoundaryCheck.sh`
- Modify: this plan and `docs/开发日志.md`

**Steps:**

- [x] RED: update boundary test to require silence gate only applies to `request.isChunkFinal`.
- [x] GREEN: add `guard request.isChunkFinal else { return false }` to `shouldSkipRealtimeASRForSilence(...)`.
- [x] Run targeted tests and native build/install.
- [x] Update this Task status, `docs/开发日志.md`, and commit.

**Acceptance:**

- 普通实时预览恢复出字。
- 旁路1有内容时，主胶囊不会因为 VAD false 全程空白。
- 静音 final chunk 仍不送 ASR。
- 不改 Final ASR、最终粘贴、UI。

## Manual Acceptance Matrix

### 2026-07-21 follow-up: 6-second first chunk and conditional stopTail

- Source implementation is complete under `2026-07-21-six-second-first-chunk-conditional-stop-tail.md`.
- The first soft boundary is now 6 seconds; later soft boundaries remain 10 seconds and hard boundaries remain 18 seconds.
- Final ASR policy is frozen per recording session instead of being reread from UI during finalization.
- Final ASR off: ordinary realtime work drains, one stopTail reconciliation runs with a three-second overall deadline, then the production cache is completed and delivered.
- Final ASR on: stopTail is explicitly skipped; complete-recording Final ASR remains authoritative.
- Timeout, snapshot failure, and cancellation preserve the current cache and never silently enable Final ASR.
- Product status: compiled and installed in `2.0.58 (800)`; 20-second, 2-minute and 5-minute real-recording acceptance remains pending.

After Task 1:

- Final ASR 开关关：短句录音，日志不出现 `source=final_asr`。
- Final ASR 开关开：短句录音，日志允许 `source=final_asr`。

After Task 2:

- 旁路关闭：主胶囊仍正常出字。

After Task 4:

- 说“你先判断这几项在实际执行过程中是不是必需的。如果……”并继续说，主胶囊不能卡死在“如果”。

After Task 5:

- 主胶囊显示内容和最终粘贴内容来自同一生产缓存。

After Task 7:

- 正常录音时，产品实时预览走内存 samples；日志/代码边界不再依赖 `.realtime-*.wav`。
- 开启实验校准时仍可能出现 `.reconcile` / `.tail-reconcile`，这是诊断例外。

After Task 8:

- 静音/停顿后无声尾巴不会让主胶囊新增“我想。”、“I.”这类短幻觉。
- 真实说话开始时，预览仍能正常出字。

After Task 9:

- 普通 realtime snapshot 不会因为 VAD 误判被整段拦截；旁路1有内容时主胶囊也应恢复出字。
- 静音 final chunk 仍只做收尾冻结，不把无声尾巴送 ASR。

## Deferred Follow-up: Context Continuity Across Chunks

**Status:** The 1.2-second pause-final experiment shipped in 2.0.47 (789), caused premature chunking and missing text, and was reverted. Build 800 uses the documented 6/10/18 boundary plus conditional stopTail; real-recording acceptance remains pending.

**Observed evidence:**

- `现在我想确认` 被识别/拼接成 `现在我想觉得`。
- `补出奇怪的短句` 被识别/拼接成 `不出奇怪的恐惧`。
- `英文字母 I` 被识别/拼接成 `英文字母下我`。
- `旁路如果有内容` 出现 `旁边如果旁边有内容`，带有明显的边界重复。

**Current judgment:** 这些问题不能先简单归因于模型或用热词替换掩盖。优先检查音频分块是否保留连续上下文、stable/volatile 交界是否正确替换、重叠窗口是否正确去重，以及旧尾巴是否被错误保留。

**Do not touch before this follow-up starts:**

- 不在 UI / 胶囊层修字或拼文本。
- 不先加入针对样例的硬编码替换。
- 不改变 Final ASR 开关语义。

**Required first step when resumed:** 记录同一真实录音的每次音频时间范围、每块原始 ASR 输出、stable/volatile 状态和最终合并结果，再依据证据确定修改点。

**2026-07-20 historical failed experiment:** 曾把普通生产路径改为自然停顿连续1.2秒后 pause-final；真实录音证明它会在10秒前反复推进块序号并造成缺字、少字，随后从 Git 恢复旧10/18秒逻辑并删除遗留状态。不得把1.2秒方案视为当前实现或后续基础。

## Progress Log

- 2026-07-20: Plan created. Task 1 ready to execute.
- 2026-07-20: Task 1 completed. Final ASR now honors the switch boundary: when the switch is off and realtime delivery cache is unavailable, delivery returns `realtime-preview-cache-unavailable` without calling the final transcriber.
- 2026-07-20: Task 1补丁完成。用户截图确认主窗口显示“没有收到有效音频”，但实时文本和最近转录都有内容；日志确认失败样本已有 `production_preview_delivery chars>0`，只是 `ProductionRealtimePreviewDeliveryCache.deliverySnapshot()` 因尾巴覆盖闸门返回 nil。修正规则：Final ASR 关闭时，有实时文本就交付实时文本；生产缓存有文本就返回，不因 tail gap 返回 nil。
- 2026-07-20: Task 2归档完成。代码确认主胶囊生产预览订阅已独立于旁路实验开关；`PreviewSubscribersBoundaryCheck.sh` 与 `ProductionPreviewSourceIndependenceBoundaryCheck.sh` 通过。
- 2026-07-20: Task 3完成。生产实时缓存新增明确来源 `realtime-preview-delivery-cache`；最终交付日志不再把生产缓存混写成旧候选缓存或 final ASR。
- 2026-07-20: Task 4完成。停止录音后先按状态排空 realtime in-flight/pending 队列，再 complete 生产交付缓存和丢弃 pending；避免最后一帧实时结果还在路上时被直接取消，导致缓存/粘贴丢尾巴。
- 2026-07-20: Task 5归档完成。代码复核确认主胶囊文字显示和最终交付来自同一个生产 `productSnapshot` 源；本任务未改 UI 绘制和动画。
- 2026-07-20: Task 6归档完成。旁路/候选仍可作为诊断窗口存在，但测试确认它们不再影响主胶囊显示和最终粘贴来源。
- 2026-07-20: Task 7启动。目标是移除产品实时预览 `.realtime-*.wav` 高频写盘；完整录音和实验校准文件暂不动。
- 2026-07-20: Task 7完成。产品 realtime snapshot 改为内存 samples + sampleRate；`NativeSenseVoiceBridge` / `SenseVoiceRouter` 增加 samples 识别入口；`SpeechInputCoordinator.transcribeRealtime(...)` 不再依赖 `.realtime-*.wav`。完整停止录音文件和实验校准文件保持原路径。
- 2026-07-20: Task 8启动。目标是复用现有 VAD 状态给 realtime ASR 加静音门控，避免静音/停顿尾巴短幻觉进入主胶囊和生产缓存。
- 2026-07-20: Task 8完成。`SpeechInputCoordinator` 记录最近一次 VAD 结果与采样时间，`transcribeRealtime(...)` 在明显无声且无近期人声保护时跳过 realtime ASR；final chunk 静音快照只冻结已有文本，不新增幻觉。实时预览过滤补充 “我想” / “I” 短幻觉。
- 2026-07-20: Task 9启动。用户反馈主胶囊识别不到但旁路1有内容；日志确认普通 realtime snapshot 被 `realtime_snapshot_skipped_silence` 连续拦截。修复方向：收窄 silence gate，只拦 final chunk 无声收尾，不拦普通实时识别。
- 2026-07-20: Task 9完成。`shouldSkipRealtimeASRForSilence(...)` 只对 `request.isChunkFinal` 生效；普通 realtime snapshot 恢复进入 ASR，避免 VAD 误判导致主胶囊空白。
- 2026-07-20: The 1.2-second pause-final experiment in 2.0.47 (789) failed installed-app acceptance because it caused premature chunks and missing text; it was reverted and must remain historical only.
- 2026-07-21: Follow-up implementation compiled and installed in `2.0.58 (800)`: first soft boundary changed from the failed 3-second experiment to 6 seconds; Final ASR policy is recording-scoped; Final ASR-off stop performs one bounded stopTail before production-cache completion, with a three-second one-shot timeout and current-cache degradation. Real-recording acceptance remains pending.
