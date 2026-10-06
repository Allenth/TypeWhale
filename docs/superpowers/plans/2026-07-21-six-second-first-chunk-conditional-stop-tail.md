# Six-Second First Chunk And Conditional Stop-Tail Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把首块软边界从3秒调整为6秒，并在“停止后重新识别整段录音”关闭时完成一次有界的 stopTail 校准后再交付实时缓存。

**Architecture:** `RealtimeChunkBoundaryPolicy` 继续唯一拥有 6/10/18 秒分块规则。`SpeechSession` 在录音开始时冻结 Final ASR 策略，`SpeechInputCoordinator` 只负责停止顺序；`ExperimentalRealtimePreviewPipeline` 负责 stopTail 调度、超时和 Reducer 合并；`ProductionRealtimePreviewDeliveryCache` 只能在 stopTail 正常完成或有界降级后标记完成。UI 只订阅快照，不处理文本。

**Tech Stack:** Swift 5、AppKit、AVFoundation、SenseVoice、Silero VAD、独立 Swift 检查、shell 边界测试。

## Global Constraints

- 首块：观察到人声后，达到6秒且当前处于停顿时软收口。
- 后续块：达到10秒且当前处于停顿时软收口。
- 所有块持续讲话到18秒时硬收口。
- Final ASR 开启时禁止创建或执行 stopTail 请求。
- Final ASR 关闭时，生产缓存必须在 stopTail 完成或3秒超时降级后才能 `complete`。
- stopTail 失败、超时或快照创建失败时保留已有实时缓存，不返回空，不自动启用 Final ASR。
- 录音开始时冻结 Final ASR 策略；录音途中修改设置只影响下一次录音。
- stopTail 等待期间重复快捷键不能二次停止同一会话。
- 不改 UI 绘制、动画、在线 Provider、旁路诊断、Final ASR 本身及5分钟上限。
- 不新建 worktree；保护 `native/Helpers/CapsuleConceptGallery/` 与 `native/Sources/Presentation/Capsule/Concepts/`。

---

### Task 1: Change First Soft Boundary From 3 Seconds To 6 Seconds

**Status:** Compiled in 2.0.58 (800) / real-recording acceptance pending

**Files:**
- Modify: `native/Sources/Domain/RealtimeTranscription/RealtimeChunkBoundaryPolicy.swift`
- Modify: `native/Tests/RealtimeChunkBoundaryPolicyCheck.swift`
- Modify: `docs/superpowers/plans/2026-07-21-first-chunk-short-soft-boundary-experiment.md`
- Modify: this plan

**Interfaces:**
- Produces: `RealtimeChunkBoundaryPolicy(firstChunkSoftSeconds: 6, laterChunkSoftSeconds: 10, hardSeconds: 18)`。
- Consumes: `AudioRecorder.realtimeChunkIndex`、块时长、VAD状态和已观察人声状态；接线不变。

- [x] **Step 1: Write RED**

把纯策略测试改为：首块5.9秒不收口、6秒纯静音不收口、6秒有人声后停顿收口、6秒仍讲话不收口、18秒硬收口；后续块仍为9.9/10/18秒边界。

- [x] **Step 2: Verify RED**

Run:

```bash
swiftc native/Sources/Domain/RealtimeTranscription/RealtimeChunkBoundaryPolicy.swift native/Tests/RealtimeChunkBoundaryPolicyCheck.swift -o /tmp/typewhale-chunk-boundary-check && /tmp/typewhale-chunk-boundary-check
```

Expected: FAIL because production still defaults to3 seconds.

- [x] **Step 3: Implement GREEN**

只把 `firstChunkSoftSeconds` 默认值从 `3` 改为 `6`；不修改 `AudioRecorder` 接线和其他边界。

- [x] **Step 4: Verify GREEN**

Run the pure check, `RealtimeChunkBoundaryPolicyWiringCheck.sh`, `RealtimePreviewMemoryAudioBoundaryCheck.sh`, `RealtimeSilenceGateBoundaryCheck.sh`, and `git diff --check`.

- [x] **Step 5: Update plan and commit**

记录 RED/GREEN 证据和“6秒仍是实验参数”；提交只包含本 Task 文件。

### Task 2: Freeze Final-ASR Policy Per Recording Session

**Status:** Compiled in 2.0.58 (800) / real-recording acceptance pending

**Files:**
- Modify: `native/Sources/Application/SpeechInputState.swift`
- Modify: `native/Sources/Domain/ASRDomain.swift`
- Modify: `native/Sources/Application/SpeechInputCoordinator.swift`
- Create: `native/Tests/RecordingFinalizationPolicyBoundaryCheck.sh`
- Modify: `native/Tests/FinalRecognitionPreviewCacheDefaultCheck.sh`
- Modify: this plan

**Interfaces:**
- Produces: `SpeechSession.reRecognizeWholeRecordingAfterStop: Bool` and `RecordingTask.reRecognizeWholeRecordingAfterStop: Bool`。
- Consumes: `MainViewController.reRecognizeWholeRecordingAfterStopEnabled` exactly once when `SpeechSession` is created.

- [x] **Step 1: Write RED**

边界测试必须断言：会话创建时保存开关；`RecordingTask` 继承会话值；`startFinalRecognition` 使用 `task.reRecognizeWholeRecordingAfterStop`，不得再次读取 controller。

- [x] **Step 2: Verify RED**

Run `bash native/Tests/RecordingFinalizationPolicyBoundaryCheck.sh`.

Expected: FAIL because the session/task do not own the policy yet.

- [x] **Step 3: Implement GREEN**

新增两个同名只读字段。创建 `SpeechSession` 时从 controller 捕获；创建 `RecordingTask` 时从 session 复制；最终交付请求只读取 task 字段。

- [x] **Step 4: Verify GREEN**

Run the new boundary test, `FinalRecognitionPreviewCacheDefaultCheck.sh`, `FinalDeliveryUseCaseCheck`, and `git diff --check`.

- [x] **Step 5: Update plan and commit**

记录“设置只影响下一次录音”的所有权规则并提交本 Task。

### Task 3: Gate And Sequence Stop-Tail Before Cache Completion

**Status:** Compiled in 2.0.58 (800) / real-recording acceptance pending

**Files:**
- Modify: `native/Sources/Application/SpeechInputCoordinator.swift`
- Modify: `native/Sources/Application/RealtimePreview/ExperimentalRealtimePreviewPipeline.swift`
- Modify: `native/Sources/Application/RealtimePreview/PreviewRequestScheduler.swift` only if pending-request cleanup needs explicit API
- Create: `native/Tests/ConditionalStopTailBoundaryCheck.sh`
- Modify: `native/Tests/LongFormCoordinatorBoundaryCheck.sh`
- Modify: `native/Tests/PreviewRequestSchedulerCheck.swift`
- Modify: this plan

**Interfaces:**
- Produces: coordinator helper `finalizeRealtimePreviewTailIfNeeded(...) async`.
- Consumes: `RecordingTask/SpeechSession.reRecognizeWholeRecordingAfterStop`, `AudioRecorder.makeExperimentalTailSnapshot(...)`, and `ExperimentalRealtimePreviewPipeline.finishWhenCorrectionsDrained(...)`.

- [x] **Step 1: Write RED ordering and gating checks**

要求源码顺序满足：普通 realtime drain → 条件 stopTail → 读取最终预览文本 → cache complete → clear session。检查 Final ASR 开启分支记录 `realtime_stop_tail_skipped reason=full_final_asr_enabled`，关闭分支才允许调用 `makeExperimentalTailSnapshot` 和 `finishWhenCorrectionsDrained`。

- [x] **Step 2: Write RED timeout check**

要求 pipeline 有3秒整段 stop-finalization deadline；超时记录 `preview_stop_tail_timeout`、标记 recovery、用当前 reducer state 完成一次回调，后到回调不得再次交付。

- [x] **Step 3: Verify RED**

Run `ConditionalStopTailBoundaryCheck.sh`, `LongFormCoordinatorBoundaryCheck.sh`, and focused scheduler/reducer checks.

Expected: FAIL because coordinator currently completes cache before stopTail and the old long-form guard explicitly forbids coordinator stopTail wiring.

- [x] **Step 4: Implement minimal orchestration**

在 recorder 已停止且文件有效后：

```swift
if session.reRecognizeWholeRecordingAfterStop {
    logSkip()
} else if let pipeline = experimentalPreviewPipeline {
    let tail = try recorder.makeExperimentalTailSnapshot(from: url, taskID: taskID)
    await pipeline.finishWhenCorrectionsDrained(tailSnapshot: tail)
}
prepareShadowPreviewForFinalDelivery(recordingDuration: duration)
```

实际实现使用 callback-to-async helper；活动 session 保留到 stopTail 完成，确保 `applyExperimentalPreviewState` 能更新生产缓存。快照失败直接降级到现有缓存。

- [x] **Step 5: Add one-shot deadline and duplicate-stop guard**

pipeline 的 deadline 与完成回调都在 MainActor 上通过同一 one-shot 状态收口。Coordinator 记录当前正在停止的 task ID；同一 task 的重复停止只记日志并返回。

- [x] **Step 6: Update obsolete long-form boundary guard**

删除“Coordinator 永远不得出现 stopTail”的过时断言，替换为“stopTail 只能位于 Final ASR 关闭的专用 helper；不得恢复旧长录音直接交付分支”。

- [x] **Step 7: Verify GREEN**

Run:

```bash
bash native/Tests/ConditionalStopTailBoundaryCheck.sh
bash native/Tests/LongFormCoordinatorBoundaryCheck.sh
bash native/Tests/RealtimeStopDrainBoundaryCheck.sh
```

Compile/run `PreviewRequestSchedulerCheck`, `PreviewTranscriptReducerCheck`, `PreviewStopTailOverflowCheck`, `ProductionRealtimePreviewDeliveryCacheCheck`, `FinalDeliveryUseCaseCheck`, and `git diff --check`.

- [x] **Step 8: Update plan and commit**

记录正常、跳过、快照失败和超时四条路径的日志字段；提交本 Task。

### Task 4: Product Documentation, Regression And Installed-App Gate

**Status:** Full-version build complete / real-recording acceptance pending

**Files:**
- Modify: `docs/ARCHITECTURE.md`
- Modify: `docs/开发日志.md`
- Modify: `docs/superpowers/plans/2026-07-20-realtime-cache-authority-cutover.md`
- Modify: this plan
- Generated by install-only: `docs/构建日志.md`

**Interfaces:**
- Documents: 6/10/18 boundary, per-session Final ASR ownership, conditional stopTail sequence, timeout degradation and runtime evidence.

- [x] **Step 1: Update product and architecture records**

记录本次真实问题：34秒录音最终168字仅60字已确认，首块约3秒切分，停止时0次 stopTail；说明“编译接入”不等于“生产收尾生效”。

- [x] **Step 2: Run focused regression suite**

执行本计划全部测试、`FinalSpeechGateCheck`、生产缓存接线检查和 `git diff --check`。

- [x] **Step 3: Install-only verification**

并发检查通过后运行 `./native/build_and_log.sh`。确认其明确输出“未编译”，验签安装包并检查启动日志。不得把旧二进制描述为已包含本轮源码。

- [x] **Step 4: Commit documentation/build record**

仅提交本计划、架构/开发日志和本轮生成的构建记录；不提交两个概念目录。

- [ ] **Step 5: Real full-version acceptance gate**

完整版本构建后必须验证：

1. Final ASR关闭：首块在6秒前不切；停止日志出现 `lane=stopTail`，cache complete 在其后；20秒和2分钟录音末尾不丢。
2. Final ASR开启：日志出现 skip reason，整轮没有 `lane=stopTail`，最终来源为完整 Final ASR。
3. stopTail 故障注入：3秒内降级，已有内容仍可交付。
4. OpenClaw：Final ASR关闭时不会卡在 stopTail，超时后仍能发送或明确失败。

### Task 5: Repair Fast/Correction Audio-Range Ownership

**Status:** Compiled in 2.0.58 (801) / real-recording acceptance pending

**Files:**
- Modify: `native/Sources/Infrastructure/Audio/AudioRecorder.swift`
- Modify: `native/Sources/Application/SpeechInputState.swift`
- Modify: `native/Sources/Application/SpeechInputCoordinator.swift`
- Modify: `native/Sources/Application/RealtimePreview/ExperimentalRealtimePreviewPipeline.swift`
- Modify: `native/Sources/Domain/RealtimePreview/PreviewTranscriptReducer.swift`
- Modify: `native/Tests/PreviewTranscriptReducerCheck.swift`
- Modify: `native/Tests/RealtimePreviewMemoryAudioBoundaryCheck.sh`
- Modify: this plan and `docs/开发日志.md`

**Interfaces:**
- `AudioRecorder.onRealtimeSnapshot` 增加当前 fast 快照的绝对 `PreviewAudioRange`。
- `RealtimeSnapshotRequest.audioRange` 从录音帧位置产生，pipeline 原样传给 `PreviewRecognitionResult`，禁止再次伪造为 `0...audioDuration`。
- Reducer 保存带范围的 fast 结果；correction 只能接管自己实际覆盖的时间区间。窗口开始前尚未确认的 fast 内容先转为稳定内容，未完全被确认时间覆盖的 fast 结果不得整块删除。

- [x] **Step 1: Write RED ownership tests**

增加三个失败用例：首个 correction 从第7秒开始时保留0～7秒开头；后续 correction 只覆盖块的一部分时保留未覆盖前文；措辞变化时不得把 fast 与 correction 重复拼接。同步更新 callback 接线边界，要求 AudioRecorder 使用帧位置产出绝对范围、pipeline 使用 `request.audioRange`。

- [x] **Step 2: Verify RED**

运行 `PreviewTranscriptReducerCheck` 和 `RealtimePreviewMemoryAudioBoundaryCheck.sh`。必须分别失败于“开头被整块删除”和“fast audioRange 契约不存在”，不能因编译错误或测试写错而失败。

- [x] **Step 3: Implement absolute range propagation**

普通快照范围为 `realtimeChunkStartFrame/sampleRate ... + audioDuration`；最终块使用 commit ticket 的 `startFrame/endFrame`。Coordinator、request 和 pipeline 只透传，不推测、不读取 UI。

- [x] **Step 4: Implement range-based ownership transfer**

Reducer 在确认 correction 前，把 `confirmedThroughTime ... correction.audioRange.start` 之间仍由 fast 持有的单位按时间顺序转为稳定内容；随后确认 correction 到真实 boundary。只清理 `audioRange.end <= confirmedThroughTime` 的 fast 结果。时间戳缺失时使用现有 token/字符顺序做有界比例定位，并标记恢复，不能静默整块删除。

- [x] **Step 5: Verify GREEN and regressions**

运行 Reducer、内存音频、分块、stopTail、生产缓存、最终交付和 `git diff --check`。额外确认 Final ASR、UI、6/10/18秒常量和 stopTail 顺序没有 diff。

- [x] **Step 6: Update records and commit**

记录 RED/GREEN 证据、残余风险和固定WAV复测入口；提交仅包含本Task文件，不包含两个概念目录。完整版本构建前不得宣称真实录音已修复。

### Task 6: Keep Capsule Text Visible While Data Exists

**Status:** Compiled in 2.0.58 (801) / real-recording acceptance pending

独立排查 UI 状态选择：数据层已有非空 preview 时，胶囊不得退回仅“录音中”折线。Task 6 只能修改状态投影或展示层，禁止读取、改写、过滤或清空交付缓存；必须在 Task 5 完成并提交后再开始。

**复审事实：** Build 800 的任务 `99B7BDF8` 在 14:33:47 发生 `shadow_audio_overflow`，紧接着执行 `endShadowPreview(cancelled: true)`；该方法错误地同时取消 `ProductionPreviewStateBridge` 与 `ProductionPreviewTextCoordinator`。此后同一任务的实验数据仍从 4 字持续增长到 160 字，但没有任何 `production_preview_delivery`，因此主胶囊只剩“录音中”折线。问题不在识别结果、缓存正文或胶囊绘制。

**补充体验事实：** 正常任务中 `experimental_preview_update` 与 `production_preview_delivery` 同秒发生，证明主胶囊的数据订阅没有额外排队；可感知延迟来自主胶囊逐字定时器每字 `75ms`，而候选胶囊每字 `50ms`。两者消费同一快照时，主胶囊会更晚追上目标文字。

**实现边界：**

- 主胶囊订阅必须在每次录音开始时独立启动，不受“旁路预览（诊断）”开关、旁路启动失败、音频溢出或 Provider 失败影响。
- `endShadowPreview` 只能结束旁路/候选 runtime、音频订阅和两个诊断胶囊；不得触碰生产状态桥、生产文字协调器或生产交付缓存。
- 正常停止时仍按原顺序封存生产缓存并完成主胶囊订阅；取消整次录音时才取消主胶囊订阅。
- 主胶囊逐字间隔只从 `75ms` 收紧到与候选一致的 `50ms`；保留逐字推进、8字欠账上限和淡入，不删除动画。
- 不修改 `CapsuleTextBuffer`、Reducer、识别策略、Final ASR、最终粘贴或文字内容。

**验收：**

- 新增结构门禁先在旧代码上失败：旁路 teardown 不得包含生产订阅对象；生产订阅必须独立于旁路 gate 启动。
- 旁路开启后即使发生 overflow/启动失败，主胶囊仍继续收到后续非空文字；旁路关闭时主胶囊同样持续显示文字。
- 主胶囊最多8字动画欠账由约600ms降到约400ms，且仍逐字显示、无整段跳变。
- 停止与取消路径不遗留订阅；既有生产缓存、最终交付、旁路隔离和源码类型检查全部通过。
- 真实安装版需在下一次明确完整版本构建后，用“旁路关闭”和“旁路开启并触发异常”两条录音路径验收；install-only 不作为源码生效证据。

## Progress

- 2026-07-21：架构审计确认当前首块3秒实验仍在生产路径；34秒真实录音在约3秒、10秒、10秒处分块，停止时未运行 stopTail，最终168字中仅60字稳定确认。
- 2026-07-21：产品负责人选择继续实验，将首块调整到5～6秒；架构决策采用6秒，以增加短句上下文，同时保留相对10秒边界的提前校准机会。
- 2026-07-21：产品负责人明确 stopTail 仅在“停止后重新识别整段录音”关闭时生效；开启时完整 Final ASR 保持唯一收尾权威。
- 2026-07-21：Task 1 完成 RED→GREEN。纯策略测试在旧3秒默认值上以退出码133失败；改为6秒后，纯策略、接线、内存快照、静音门控和 diff 检查通过。真实安装版验收仍需完整版本构建。
- 2026-07-21：Task 2 完成 RED→GREEN。Final ASR 开关在 `SpeechSession` 创建时冻结，`RecordingTask` 继承该值，最终识别不再读取可变 UI 状态；新增边界检查、默认开关检查和最终交付用例通过。
- 2026-07-21：Task 3 完成 RED→GREEN。停止顺序改为普通实时排空→条件 stopTail→读取缓存→封存缓存→清理会话；Final ASR 开启时记录 `realtime_stop_tail_skipped reason=full_final_asr_enabled`，关闭时记录 started/completed，快照失败记录 snapshot_failed 并保留当前缓存，3秒总超时记录 `preview_stop_tail_timeout`、标记 recovery 并一次性返回当前状态。重复停止被任务 ID 门控；超时/取消会清理活动及排队临时音频，外部取消会记录 `recording_finish_aborted` 且不继续交付。聚焦回归全部通过。
- 2026-07-21：Task 4 源码阶段完成。架构文档、主缓存计划和开发日志已同步；计划内聚焦回归全部通过。`./native/build_and_log.sh` 完成 Build 799 的覆盖安装、启动和签名验证，并明确输出“未编译”；因此该动作只验证安装流程，不代表本轮源码已进入安装版。完整版本真实录音验收仍保持未勾选。
- 2026-07-21：完整版本构建完成：`2.0.58 (800)` 已重新编译、覆盖安装并启动，仓库包与安装包版本一致，deep/strict 签名有效；安装版二进制可检出 stopTail started/completed/skipped/timeout 与重复停止保护标识。构建后关键回归通过。真实20秒、2分钟和5分钟录音门禁仍保持未勾选。
- 2026-07-21：Build 800 首轮真实验收通过。Final ASR关闭，录音24.513秒；首块在约7.3秒停顿后进入 chunk 1，未在6秒前切开，后续块约10秒推进。停止时普通队列0ms排空，stopTail覆盖22.5秒音频并在248ms成功完成，最终78字全部来自 `realtime-preview-delivery-cache`，`recognition_ms=0`，末尾完整粘贴。2分钟和5分钟门禁仍待执行。
- 2026-07-21：Build 800 闪念/OpenClaw真实回归通过。闪念5.595秒录音的 stopTail耗时79ms，20字从实时缓存交付并写入闪念文件；OpenClaw 2.785秒录音的 stopTail耗时71ms，8字从实时缓存交付，随后发送成功、收到3字回复并完成语音播放。发送前一次健康探测超时未阻断实际请求。
- 2026-07-21：Build 800 Final ASR开启门禁通过。录音11.934秒，日志明确出现 `realtime_stop_tail_skipped reason=full_final_asr_enabled`，整轮没有执行 stopTail；完整 SenseVoice Final ASR耗时133ms并交付43字，最终来源为 `source=final_asr engine=sensevoice-small/sherpa-native`，粘贴成功。
- 2026-07-21：Build 800 的125.857秒长录音门禁失败。实时请求虽持续推进至 chunk 8、队列等待始终为0ms，stopTail也成功完成并粘贴641字，但使用同一安装版 SenseVoice、`auto`语言模式对保存的完整WAV独立识别得到724字。两版末尾同为“另外两款设备的。”，证明本次没有丢最后尾巴；实时结果丢失了开头及多处中间连续语句，净少83字。录音文件完整，问题边界收窄到实时分块合成/稳定缓存交付，2分钟门禁保持未勾选。
- 2026-07-21：使用同一段音频扬声器回放再次复现。新录音129.425秒，完整WAV独立识别751字，实时缓存交付638字，净少113字，末尾仍一致。代码与时间线确认首个22.5秒 correction 窗口约从录音第7秒开始，但 `confirmFastChunks(through:)` 会删除覆盖0～18秒的整个 fast chunk；Reducer只确认 correction 窗口内的部分文本，导致窗口开始前的开头必丢。架构审查拒绝“仅在Reducer补回字符串”的窄修：fast快照目前没有准确的全局音频范围，无法安全局部替换，容易引入重复和错序。正式修复必须先让fast结果携带绝对 `audioRange`，Reducer按时间覆盖范围转移文字所有权；correction未覆盖的fast前后文必须保留，只有被明确覆盖的范围才能移除。不改模型、UI、6/10/18秒分块、Final ASR或stopTail策略。
- 2026-07-21：同轮录音还复现“胶囊只显示录音中折线、没有文字”。截图剩余4:44，对应录音约第16秒；同期日志显示实验预览已连续发布，`visible_chars`约85且继续增长，因此不是识别无结果，而是UI状态选择/投影暂时隐藏了已有文字。该问题作为独立后续Task处理，不与音频范围和Reducer修复混改；UI修复不得读取、改写或清空交付缓存。
- 2026-07-21：Task 5 完成源码 RED→GREEN。Reducer 用例在旧实现上稳定失败于首个 correction 从第7秒开始后0～7秒开头消失；接线门禁失败于 fast 缺少绝对 `audioRange`。实现后 AudioRecorder 从帧位置产生绝对范围并逐层透传；Reducer 先保留 correction 窗口前仍由 fast 独占的文字，只清理已被确认时间或当前 correction 完整覆盖的 fast 结果。旧尾巴防重复测试曾在首轮GREEN拦截不完整清理，收紧条件后通过；无时间戳时使用有界估算并保留 recovery 标记。Reducer、调度器、stopTail、内存音频、分块、生产缓存、最终交付、源码类型检查和diff检查通过。未执行完整版本构建，真实固定WAV复测仍待安装新版。
- 2026-07-21：Task 6 完成源码 RED→GREEN。Build 800 日志确认旁路音频溢出后 `endShadowPreview` 同时取消主胶囊订阅，导致数据层继续从4字增长到160字而主胶囊始终只有折线。现将生产订阅的开始、正常完成和整次取消从旁路生命周期中拆开；关闭旁路、旁路溢出或Provider失败均不再影响主胶囊。主胶囊逐字间隔从75ms调整为50ms，保留8字欠账上限和淡入，理论最大动画延迟由约600ms降到约400ms。生命周期、生产来源独立、三胶囊隔离、主胶囊边界、缓存、停止排空、最终交付接线、快照缓冲及全量源码类型检查通过。未执行完整版本构建，真实安装版折线与速度验收待新版。
- 2026-07-21：构建规则按产品负责人最新确认恢复为“日常 build 编译当前源码并递增 build 号，短版本号不变；完整版本才递增短版本号”。Task 5/6 将进入 `2.0.58 (Build 801)`，避免继续用 Build 800 覆盖不同二进制。
