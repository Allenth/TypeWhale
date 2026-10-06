# 旧实时预览链路 vs 新统一转录核心 —— 技术审计笔记

> 作者：Claude（本 worktree 协作会话）
> 日期：2026-07-18
> 目的：2026-07-18 把生产胶囊/最终交付切到统一转录核心（`ProductionPreviewTextCoordinator` /
> `SenseVoiceSnapshotProvider` / `FinalDeliveryUseCase`）后，真实测试暴露了新链路在准确率上
> 明显不如旧链路（`ExperimentalRealtimePreviewPipeline` / `PreviewTranscriptReducer` /
> `BoundaryCenteredPreviewPlanner`）。本文档系统性对比两条链路的具体实现，列出旧链路
> 几十上百个版本迭代下来积累的针对性优化，标注新链路目前**已有**、**缺失**、**部分覆盖**
> 的能力，供后续把新架构做到不低于旧链路水平时对照迁移，而不是凭空重新发明。
>
> 阅读前提：本文只谈"数据生产端"（怎么切音频、怎么识别、怎么拼接、怎么过滤），不谈
> "数据消费端"（候选 vs legacy 的选择逻辑、时长门槛），后者见
> `docs/superpowers/plans/2026-07-18-unify-realtime-transcription-implementation-plan.md`
> 和当天对话记录里的 `FinalDeliveryUseCase` 讨论。

## 一句话结论

**旧链路"听懂了你在哪停顿，才切一刀、才判断是不是幻觉"；新链路"不管你说没说完，到点就切、什么都往外吐"。** 差距不是模型本身，是切分时机的输入信号、拼接时的校验严格度、以及有没有幻觉词过滤这三件事上，新链路都比旧链路更粗糙。

**但这不代表旧链路的架构值得保留。** 旧链路这些"针对性优化"，全部堆在 `SpeechInputCoordinator`（3479 行）、`ExperimentalRealtimePreviewPipeline`、`PreviewTranscriptReducer` 这类高度集中、职责混杂的上帝代码里——每加一条规则就往同一个大文件里塞一段，State/Reducer/Provider/UI 边界模糊，改一处容易牵一发动全身，这正是当初决定推倒重来、迁移到统一转录核心（Provider/Reducer/Projector 分层清晰）的根本原因。

所以本文档不是在建议"新架构不如旧架构、应该回退"，结论应该是两句话分开看：

1. **旧链路解决问题的具体技术手段是对的**（VAD 感知切分、幻觉黑名单、时间戳互相校验），这些是几十上百个版本试错换来的成果，应该原样搬过去，不用重新踩坑。
2. **旧链路承载这些手段的架构是不对的**（上帝对象、逻辑分散、边界不清），新架构的分层设计本身没有问题，问题是新架构在"重新实现数据生产端"时，只把骨架搭好了，还没把旧架构里那些具体的数据质量手段迁移过来。

**目标是把"1"搬进"2"里，而不是连"2"一起放弃。**

---

## 对照表：核心能力逐项对比

| 能力 | 旧链路（`RealtimePreview`/`ExperimentalRealtimePreviewPipeline`） | 新链路（`SenseVoiceSnapshotProvider`/`SenseVoiceBoundaryReconciler`） | 现状 |
|---|---|---|---|
| 切分时机的输入信号 | `BoundaryCenteredPreviewPlanner.proposeBoundary` 接收真实 `voiceActive: Bool`，只在检测到停顿（`!voiceActive`）时提议切边界；18 秒硬上限兜底 | `SenseVoiceSnapshotProviderCore.append` 纯按固定时间计数：`firstFastSeconds=0.5`、`fastIntervalSeconds=2`、`correctionIntervalSeconds=6`，全程无任何语音活动输入 | ❌ **缺失** |
| 幻觉/静音短语过滤 | `RecognitionTextFilter.swift` 维护中英文静音幻觉黑名单（`realtimePreviewSilencePhrases`/`realtimePreviewSilenceLatinPhrases`，**明确包含 "yeah"**），`isMeaningfulRealtimePreviewText` 在写入胶囊前逐条过滤 | 无任何等价过滤；`SenseVoiceSnapshotProvider`/`ProductionPreviewTextProjection` 对识别文本不做语义过滤，模型吐什么就显示/交付什么 | ❌ **缺失**（直接对应"Yeah"幻觉词问题） |
| 跨窗口拼接的校验严格度 | `PreviewTranscriptReducer.timestampAlignment` 要求两次独立识别在**同一批 token 上、绝对时间误差 ≤0.75s** 才承认为同一片段；否则标记 `recoveryRequested=true` 强制重新展示，不静默拼接 | Build 776 起 `SenseVoiceBoundaryReconciler` 默认启用 `.lexicalOverlap`，优先 token 时间戳对齐，缺时间戳时要求至少 2 个 suffix/prefix token overlap；`.audioTime` 仅保留为显式诊断策略 | ✅ **已迁移第一层**（内容冲突不再硬拼；硬边界前后音频校准仍待 Task 2） |
| fast/correction 是否分层确认 | `PreviewTranscriptReducer.apply`：`.fast` 只更新 `provisionalFastTextByChunk`（临时展示，从不写入 `confirmedSegments`）；只有 `.correction` 经过时间戳比对后才能"确认"进稳定文本 | `SenseVoiceSnapshotProviderCore.apply` 对 fast/correction 结果**统一**丢给 `reconciler.consume(...)`，没有"fast 结果永不确认、只能展示"的分层保护 | ❌ **缺失** |
| 超时预算 | `previewTimeoutSeconds`：correction 用 `max(6, min(12, 音频时长*2+2))`，随音频时长动态伸缩 | `maximumServiceMilliseconds: 300`，固定死值，不随窗口大小或设备负载调整 | ⚠️ **更粗糙**（固定预算，负载高时更容易触发 `resource_degraded`） |
| 运行时可观测性 | `preview_fast_budget_miss`、`preview_correction_backlog_warning` 逐事件预警日志 | 只有整轮汇总的 `shadow_sensevoice_summary`（`resource_degraded`/`admission_skipped` 计数），没有逐事件粒度 | ⚠️ **更粗糙** |
| 停止收尾的"最后一口"处理 | `finishWhenCorrectionsDrained` + `tailFinalizationRequest`（`stopTail` lane），有专门更长的超时（`max(6, min(14, ...))`） | `enqueueFinalTailSnapshotIfNeeded`（已有，2026-07-16 加入），机制类似但没有独立 lane/超时策略 | ✅ **已覆盖**（后续加的，机制对等） |

---

## 逐项详细说明

### 1. 切分时机：语音停顿感知 vs 固定秒表（最核心差异）

**旧链路**（`native/Sources/Domain/RealtimePreview/BoundaryCenteredPreviewPlanner.swift:33-48`）：

```swift
func proposeBoundary(..., voiceActive: Bool) -> PreviewBoundary? {
    let chunkDuration = capturedAt - chunkStartedAt
    if chunkDuration >= hardBoundarySeconds { return ...(.hardLimit) }
    if chunkDuration >= softBoundarySeconds, !voiceActive {
        return ...(.voicePause)   // 只有真的停顿了才切
    }
    return nil
}
```

**新链路**（`native/Sources/Infrastructure/RealtimeTranscription/SenseVoiceSnapshotProvider.swift` 内 `append`）：

```swift
if totalFrames >= nextFastFrame { enqueue(kind: .fast) }             // 固定每 2 秒
if totalFrames >= nextCorrectionFrame { enqueue(kind: .correction) } // 固定每 6 秒
```

**后果**：新链路的切分点跟说话人真实的停顿完全无关，词组可能被从中间切断（真实案例：同一句"公司功能"两次录音分别被切成"公司能"和"功功能"，错误方式不同，符合"切分点落在词中间、拼接靠猜"的特征）。第一刀在 0.5 秒触发，音频几乎没有上下文，容易把起音噪声识别成幻觉词。

**修复方向**：让 `SenseVoiceSnapshotProvider` 的 fast/correction 触发时机接入真实语音活动信号（项目里已有 `BoundedVoiceProbeBacklog`、`AudioRecorder`/`containsSpeech` 可复用），而不是纯计时器；correction 窗口边界优先选停顿处，久不停顿再用硬上限兜底——直接复用 `BoundaryCenteredPreviewPlanner` 的既有策略，不用重新设计。

### 2. 幻觉短语过滤：黑名单 vs 无过滤

**旧链路**（`native/Sources/Domain/Text/RecognitionTextFilter.swift:13-25`）维护了一份跑了很多个版本才积累出来的黑名单：

```swift
private let realtimePreviewSilencePhrases: Set<String> = [
    "我", "嗯", "啊", "呃", "额", "哦", "唔", "呣", "诶", "哎", "呐", "嗯嗯", "啊啊",
    "谢谢", "谢谢大家", "谢谢观看", "谢谢观赏", "请", "请观看", "字幕", "中文字幕", "字幕志愿者",
]
private let realtimePreviewSilenceLatinPhrases: Set<String> = [
    "yeah", "yeahthe", "the", "you", "thankyou", ..., "okay", "ok", "uh", "um", ...
]
```

这份名单不是一次写完的，开发日志能查到至少三次迭代：
- `1.5.5 预览解耦 + 黑名单`：新增中英文静音幻觉黑名单（`docs/开发日志.md:9934`）
- `新增 isMeaningfulRealtimePreviewText`：专门用于胶囊实时预览过滤（`docs/开发日志.md:11778`）
- `强化静音幻觉拦截`：对 `我.`、`The.` 等单字/短词结果要求更高人声活动置信度（`docs/开发日志.md:14946`）
- 更早还有 `1.7.1 (Build 477) 过滤最终识别里的 The. 静音幻觉`（`docs/开发日志.md:6913`），说明这类幻觉词连"完整识别"路径都遇到过，是模型的普遍毛病，不是实时预览独有。

**新链路**：`SenseVoiceSnapshotProvider`/`ProductionPreviewTextProjection` 对识别出的文本没有任何语义过滤，模型吐什么就是什么。真实案例里独立出现两次的"Yeah"开头，`yeah` 恰好就在旧黑名单里——**旧链路本来就有解药，新链路没接上**。

**修复方向**：把 `isMeaningfulRealtimePreviewText`（或它的核心黑名单+启发式规则）应用到候选/统一核心的展示与交付路径上，不需要重新调研哪些短语是幻觉——名单已经是几个版本试错出来的成果。

### 3. 拼接严格度：时间戳互相校验 vs 单纯取时间中点

**旧链路**（`PreviewTranscriptReducer.timestampAlignment`）：两次独立识别必须在**同一批 token 上**、绝对时间误差 ≤0.75 秒，才认定为可信的缝合点；找不到就标记 `recoveryRequested = true`，强制刷新展示而不是悄悄拼错。

**新链路当前状态**（Build 776 之后）：`SenseVoiceBoundaryReconciler` 默认 `.lexicalOverlap` 策略，不再只看时间重叠。它会优先用 token 时间戳做内容+时间双重对齐；没有可信时间戳时，至少要求 2 个 suffix/prefix token overlap 才推进稳定文本。`.audioTime` 仍保留为显式测试/诊断策略，用来证明旧问题和对比行为。

**迁移状态**：Task 1 已把生产默认切到 `.lexicalOverlap`，并用 “今天我们讨论公司” + “功功能优化” 回归锁住冲突 seam 不得硬拼。下一层还没迁移的是 Task 2：当冲突发生在 18 秒硬边界附近时，要用边界前后音频重识别做校准，而不是仅停留在 recovery。

### 4. fast 结果是否允许"直接确认"

**旧链路**：`.fast` 事件只更新 `provisionalFastTextByChunk`（临时展示用），**永远不会**直接写入 `confirmedSegments`；只有 `.correction` 经过时间戳比对成功后才允许把文字"转正"为确认文本。这是刻意的两层设计：fast 负责手感、correction 负责准确。

**新链路**：`SenseVoiceSnapshotProviderCore.apply` 里 fast 和 correction 的结果都统一交给同一个 `reconciler.consume(...)`，没有"fast 结果不能单独确认"这道保护——如果 fast 窗口（仅 3 秒音频、300ms 时间预算）本身识别有误，理论上可能被直接推进稳定文本，没有等 correction 窗口二次校验。

**修复方向**：给新链路补一层类似的"fast 只展示、correction 才确认"的分级，或者至少让 `confirmedThroughTime` 的推进只信任 correction/final-tail 来源的识别结果。

---

## 不在本次范围内、但审计中留意到的相邻问题

- **超时预算固定不随窗口/负载调整**（`maximumServiceMilliseconds: 300`）：旧链路的超时是 `音频时长 * 2 + 常数` 这种动态公式，新链路是死数字，设备负载高或窗口变大时更容易误判"资源降级"。
- **逐事件可观测性粒度不够**：旧链路对每次识别请求单独打 `preview_request_start`/`preview_request_done`/`preview_fast_budget_miss` 等日志；新链路只有整轮汇总的 `shadow_sensevoice_summary`，出问题后不容易定位是哪一次具体识别拖了后腿。

以上两点不是本次准确率问题的直接成因，但会让后续排查类似问题更费劲，值得在后续版本里一并补上。

---

## 给后续接手者的建议顺序

**前提共识（重申）**：下面每一条都是"把旧链路验证过的技术手段，用新架构的分层方式重新实现"——即逻辑迁移，不是文件搬运。不要把 `BoundaryCenteredPreviewPlanner`/`PreviewTranscriptReducer`/`ExperimentalRealtimePreviewPipeline` 这几个文件原样拉回新链路里用，也不要把新加的规则堆回 `SpeechInputCoordinator`；新逻辑应该落在 `SenseVoiceSnapshotProvider`/`SenseVoiceBoundaryReconciler`/`ProductionPreviewTextProjection` 这些新架构已经分好层的组件内部，保持 Provider 只产出中立事件、Reducer 独占文本状态、UI 只消费 ViewState 的既有边界。

如果要把新链路的数据生产端补到不低于旧链路水平，建议按这个顺序（从"改动小、收益大"到"改动大"排序）：

1. **接入幻觉黑名单过滤**（最小改动）：把 `isMeaningfulRealtimePreviewText` 或其核心规则应用到候选/统一核心输出上。直接解决"Yeah"问题。
2. **拼接策略换成 `.lexicalOverlap` 或时间戳+文本双重校验**：Task 1 已完成生产默认切换；后续只在真实录音发现稳定过慢或误判时继续校准阈值。
3. **切分时机接入真实语音活动信号**：改动量最大，但收益也最大——直接解决"词组被切在句子中间"的问题。复用 `BoundedVoiceProbeBacklog`/`containsSpeech`，参考 `BoundaryCenteredPreviewPlanner` 的既有策略。
4.（可选，非本次问题直接成因）超时预算动态化 + 逐事件诊断粒度补齐。

每一步都应该按 TDD 先写失败测试复现具体案例（比如"Yeah 幻觉词过滤"、"词组横跨窗口边界不丢字"），再实现，再拿真实录音验证，不要一次性搬完再测。

## 迁移状态记录

- 2026-07-19 / Task 0：已先补齐新链路可观测性，不改变行为。`SenseVoiceBoundaryReconciler` 可报告 seam confidence，`SenseVoiceShadowScheduler` 可报告 fast/correction 丢弃计数，`shadow_sensevoice_summary` 可输出这些诊断字段。边界校准、幻觉过滤、VAD 感知切分仍未迁移，后续必须继续按主计划逐项做 RED/GREEN。
- 2026-07-19 / Task 1：已把新链路生产默认从纯时间重叠 `.audioTime` 改为内容交叉验证 `.lexicalOverlap`。冲突 seam 不再被直接稳定硬拼，正常 suffix/prefix overlap 仍可推进 stable；`.audioTime` 保留为显式诊断策略。边界前后音频重识别校准仍未迁移，属于 Task 2。
- 2026-07-19 / Task 2：已新增边界校准 planner 和 `.boundaryCorrection` 后台请求。Provider 在内容冲突 recovery 后、边界后方音频足够时截取边界前后窗口重新识别，成功时记录 `seamConfidence=boundaryCorrected`。第一版仍不等同旧链路完整 VAD 感知切分；它只处理冲突后的后台校准，Task 4 才迁移语音活动感知切分。
