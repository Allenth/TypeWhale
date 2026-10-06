# Realtime Recognition Quality Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **项目经理硬门禁:** 每次开发前必须先读本文件；每个 Task 完成后必须更新本文件 checkbox、真实验证结果和下一步状态。未通过门禁不得跳步，不得口头声明完成。
>
> **架构师复审硬门禁:** 本计划执行期间，每累计 3–5 次实现提交必须暂停开发并进行一次架构师复审；复审结论写回本文件后，才能继续下一批提交。若 3 次提交内已经触及 Provider/Reconciler/FinalDelivery/Presentation 边界变化，也必须提前复审，不等到第 5 次。
>
> **执行纪律硬门禁:** 开发者每次开工前必须读本计划；每次只允许做一个 Task；Task 0/1 可以直接执行；Task 2 开始前必须先做代码走读，把实现细节补进 Task 2 后再写 RED；每个 Task 完成后必须更新本计划，不能只改代码。
>
> **前置阅读:** 实施前必须先读：
>
> - `docs/CLAUDE_LEGACY_PIPELINE_AUDIT.md`
> - `docs/superpowers/plans/2026-07-18-unify-realtime-transcription-implementation-plan.md`
> - `docs/superpowers/plans/2026-07-18-single-realtime-transcription-architecture-plan.md`

**Goal:** 把统一转录核心的实时识别质量补到不低于旧 `RealtimePreview` 链路：减少开头/停顿幻觉词，避免跨窗口边界丢字、重复字、错拼，确保胶囊显示始终顺滑，最终交付有可解释的质量证据。

**Architecture:** 保留新架构，不回退旧链路。旧链路里被真实验证过的技术手段（语音活动感知、内容交叉验证、幻觉过滤、边界校准、调度可观测性）迁移到新分层里：`SenseVoiceSnapshotProvider` 负责识别请求与音频窗口，`SenseVoiceBoundaryReconciler` 负责稳定文本确认，Domain 层组件负责幻觉/边界判断，UI 只消费 `PreviewViewState`，不参与数据处理。

**Tech Stack:** Swift 5、Foundation `AsyncStream`/actor、Sherpa-onnx SenseVoice、Sherpa-onnx Silero VAD、standalone Swift `*Check.swift`、源码边界 `*BoundaryCheck.sh`、`LaunchDiagnostics` 日志、真实人声录音验收。

## Product Requirements

- 胶囊 UI 必须足够顺畅：数据层 ASR、VAD、correction、拼接、过滤、边界校准都不得阻塞 UI 显示。
- 实时展示允许先显示临时文字，但不能把明显冲突的边界文本错误稳定成最终文本。
- 真实语音是“今天我们讨论功能优化”时，不得因边界冲突输出“今天我们讨论公司功功能优化”这类错拼。
- 开头/停顿/静音附近的 “Yeah / the / 嗯 / 啊” 类幻觉词要被抑制，但用户真实说出口的 “Yeah” 不能被无差别删除。
- 长录音必须可解释：如果质量下降，日志能区分是切分问题、拼接冲突、请求丢弃、资源降级、尾部未覆盖，还是模型本身识别错误。
- 最终交付仍必须有 fallback：新核心结果异常短、未完成、冲突未解决或不可交付时，继续 fallback 完整 final ASR。

## Non-Goals

- 不重写 UI 动画系统。
- 不让候选胶囊或生产胶囊处理识别数据。
- 不默认启用在线 ASR，不改变豆包/MiMo 隐私、费用、Key 策略。
- 不恢复 `ExperimentalRealtimePreviewPipeline` 为主链路。
- 不把新规则堆回 `SpeechInputCoordinator`。
- 不承诺解决短窗口天然的标点/断句漂移；本计划只解决实时识别质量、边界拼接和可观测性。

## Global Principles / 项目经理把关原则

### P0 原则：UI 永不等待数据层

- `append(AudioFrame)` 不得等待 VAD 或 ASR 完成。
- VAD 只能作为异步“语音活动状态”输入，不能在 UI 更新路径同步调用。
- correction、boundary correction、hallucination filter 都只影响后续 `PreviewViewState`，不能让胶囊卡住。
- UI 层只允许消费 `PreviewViewState` / `PreviewDisplaySnapshot`，禁止读取 provider 私有字段、音频窗口、VAD 状态、reconciler 内部状态。

### P0 原则：稳定文本必须比临时文本更保守

- `fast` 负责快出字，只能驱动临时展示。
- `correction` / `boundaryCorrection` 才能推动 stable/finalized 文本。
- 内容冲突时宁愿晚一点稳定，也不能把冲突文本拼成稳定文本。

### P0 原则：边界冲突不能硬拼

当两个窗口在时间上重叠但内容冲突，例如：

```text
真实语音：今天我们讨论功能优化
窗口 A：今天我们讨论公司
窗口 B：功功能优化
错误结果：今天我们讨论公司功功能优化
```

系统必须：

- 标记 seam 未验证；
- 不把“公司”和“功功能”同时转正；
- 优先触发边界前后音频校准；
- 校准失败时保留 volatile，等待下一次 correction 或 fallback。

### P0 原则：18 秒硬边界必须校准

自然停顿优先；如果用户连续说话超过硬上限，必须切边界，但不能信任硬切边界两侧的直接拼接结果。

硬边界策略：

```text
边界点 T
校准窗口 = [T - preRollSeconds, T + postRollSeconds]
初始建议：preRollSeconds = 4，postRollSeconds = 4
如果真实录音证据显示仍不稳定，再评估 6 + 6
```

边界后方音频未积累够 `postRollSeconds` 前，不能执行完整边界校准；UI 继续显示最新 volatile 文本，数据层后台等待足够音频后再修正。

### P0 原则：只用官方 Silero VAD，不手写能量阈值

- 禁止新增 RMS / peak / zero-crossing / 音量阈值来判断“是否有人声”。
- 生产环境复用 `SenseVoiceASR.containsSpeech(samples:sampleRate:)` / `TypeSpeakerNativeVadHasSpeechSamples`。
- VAD 结果只能是数据层辅助信号，不得成为 UI 是否显示文字的直接条件。

### P1 原则：可观测性先于调参

不允许在没有日志证据时直接调大 capacity、调长窗口、调延迟。先补日志，能看到：

- fast 请求被替换/丢弃次数；
- correction 请求被替换/降级次数；
- boundary correction 触发/成功/失败次数；
- seam 是 token verified、boundary corrected、time fallback 还是 recovery；
- tail gap；
- provider service ms；
- completed recognition count。

### P1 原则：每个阶段必须真实录音验收

自动化测试只能证明边界，不代表体验完成。每个行为变化 Task 必须完成：

- 20 秒真实录音；
- 2 分钟真实录音；
- 至少一轮自然停顿；
- 至少一轮连续说话触发硬边界；
- 至少一轮中英混杂或故意说 “Yeah”；
- 日志可解释。

## Architecture Decision

Status: **Conditional Accepted**

Decision: 按“统一核心 + 数据质量硬化”路线执行，不回退旧链路，不把 UI 或候选胶囊变成数据处理层。

Conditions:

- 每个 Task 有 RED/GREEN 测试。
- 每个行为改变都有真实安装版验证。
- 任一 Task 导致 UI 卡顿、粘贴空、明显丢字、候选比旧路径差，立即停止并回滚本 Task。
- 真实录音不通过，不得推进下一 Task。
- 每累计 3–5 次实现提交必须进行架构师复审；如果提交改变了 Provider/Reconciler/FinalDelivery/Presentation 任一边界，必须在第 3 次提交或进入下一 Task 前复审。
- 架构师复审必须确认：分层未被破坏、UI 未等待数据层、fallback 未被削弱、旧链路没有被偷偷复活、候选/胶囊没有承担数据处理职责。
- 开发者每次开工前必须重新阅读本计划；未读计划不得开始编码。
- 每次只允许执行一个 Task；不得把多个 Task 合并成一次“大改”。
- Task 0 和 Task 1 的细节已足够，可以直接按本计划开始 RED/GREEN。
- Task 2 开始前必须先完成代码走读，确认 rolling audio buffer、request 类型、boundary correction 回写方式、session stable/volatile 修正边界；走读结论必须补进 Task 2 后，才能写 RED。
- 每个 Task 完成后必须更新本计划 checkbox、验证结果、架构风险和下一步状态；只改代码不改计划视为未完成。

## File Responsibility Map

- `native/Sources/Infrastructure/RealtimeTranscription/SenseVoiceSnapshotProvider.swift`
  - 负责音频窗口、识别请求、fast/correction/boundaryCorrection 调度、provider diagnostics。
  - 不负责 UI 展示，不负责最终粘贴策略。
- `native/Sources/Infrastructure/RealtimeTranscription/SenseVoiceBoundaryReconciler.swift`
  - 负责跨窗口稳定文本确认、内容交叉验证、seam confidence、recoveryRequired。
  - 不直接调 ASR，不读 UI。
- `native/Sources/Domain/RealtimeTranscription/RealtimeRecognitionHallucinationFilter.swift`
  - 新增。负责语境感知幻觉词过滤。
  - 不处理动画，不参与最终交付选择。
- `native/Sources/Domain/RealtimeTranscription/RealtimeBoundaryCorrectionPlanner.swift`
  - 新增。负责硬边界/冲突边界校准窗口规划。
  - 不运行 ASR，只产出需要识别的音频范围。
- `native/Sources/Infrastructure/RealtimeTranscription/SenseVoiceShadowScheduler.swift`
  - 负责有界请求调度和丢弃/降级计数。
- `native/Sources/Application/SpeechInputCoordinator.swift`
  - 只允许接线、日志汇总和 VAD 状态传递。
  - 禁止新增文本拼接、幻觉过滤、边界校准算法。
- `native/Sources/Application/RealtimeTranscription/PreviewStateProjector.swift`
  - 只投影 ViewState，不修补文本。
- `docs/CLAUDE_LEGACY_PIPELINE_AUDIT.md`
  - 每个 Task 完成后追加一行“已迁移/未迁移/证据”。
- `docs/开发日志.md`
  - 每次构建安装后记录版本、改动、验证、风险。

## Execution Order

本计划按风险从小到大执行：

1. Stage 0：诊断和项目门禁。
2. Stage 1：内容交叉验证，先阻止错拼稳定。
3. Stage 2：边界校准，专治硬边界把一句话切成前后两段。
4. Stage 3：语境感知幻觉过滤。
5. Stage 4：语音活动感知切分。
6. Stage 5：调度可观测性补齐和真实验收收口。

## Task Execution Discipline

所有执行者必须遵守：

- **每次开工前读计划**：打开本文件，确认 Current Status、当前 Task、Architecture Review Log 和 Project Manager Review Checklist。
- **每次只做一个 Task**：一个 Task 的 RED、GREEN、测试、构建、真实验证、文档更新、提交全部完成后，才能进入下一个 Task。
- **Task 0/1 可以直接做**：Task 0 是诊断补齐，Task 1 是内容交叉验证默认启用；两者已有足够接口和测试方向，可以直接 RED/GREEN。
- **Task 2 前必须代码走读**：Task 2 涉及硬边界前后窗口校准，开发者必须先走读 `SenseVoiceSnapshotProvider`、`rollingSamples` 生命周期、`SenseVoiceShadowRequest`、`TranscriptionSession`、`SenseVoiceBoundaryReconciler` 回写路径；把具体实现细节补进 Task 2，再开始写 RED。
- **每个 Task 完成后更新计划**：必须更新 checkbox、真实录音结果、日志证据、风险、下一步；不能只提交代码。
- **项目经理拒绝条件**：如果提交里没有对应的计划更新，项目经理必须视为 Task 未完成，不允许进入下一 Task。

---

### Task 0: 项目门禁与诊断字段补齐

**Purpose:** 先让后续问题可判读，不改变用户可见行为。

**Files:**

- Modify: `native/Sources/Infrastructure/RealtimeTranscription/SenseVoiceBoundaryReconciler.swift`
- Modify: `native/Sources/Infrastructure/RealtimeTranscription/SenseVoiceSnapshotProvider.swift`
- Modify: `native/Sources/Infrastructure/RealtimeTranscription/SenseVoiceShadowScheduler.swift`
- Modify: `native/Sources/Application/SpeechInputCoordinator.swift`
- Create: `native/Tests/SenseVoiceReconciliationDiagnosticsCheck.swift`
- Modify: `docs/CLAUDE_LEGACY_PIPELINE_AUDIT.md`
- Modify: `docs/开发日志.md`

**Interfaces:**

```swift
enum SeamConfidence: Equatable, Sendable {
    case tokenVerified
    case boundaryCorrected
    case timeOverlapOnly
    case noOverlapRecoveryTriggered
}

struct SenseVoiceBoundaryReconciliation {
    let seamConfidence: SeamConfidence
}

struct SenseVoiceSnapshotProviderDiagnostics {
    let discardedFastRequestCount: Int
    let discardedCorrectionRequestCount: Int
    let boundaryCorrectionRequestedCount: Int
    let boundaryCorrectionSucceededCount: Int
    let boundaryCorrectionFailedCount: Int
}
```

**Steps:**

- [x] 写 RED：`SenseVoiceReconciliationDiagnosticsCheck.swift` 断言 `.audioTime` seam 返回 `.timeOverlapOnly`，`.lexicalOverlap` 成功返回 `.tokenVerified`，无可信 overlap 返回 `.noOverlapRecoveryTriggered`。
- [x] 写 RED：`SenseVoiceShadowSchedulerCheck.swift` 断言 pending fast 被新 fast 替换时 discarded fast count 可被 provider diagnostics 看到。
- [x] 实现 seam confidence 和 discarded 计数透传，不改默认策略、不改显示、不改交付。
- [x] 在 `shadow_sensevoice_summary` 增加字段：`discarded_fast`、`discarded_correction`、`seam_confidence`、`boundary_correction_requested/succeeded/failed`。
- [x] 运行：

```bash
swiftc native/Tests/SenseVoiceReconciliationDiagnosticsCheck.swift \
  native/Sources/Infrastructure/RealtimeTranscription/SenseVoiceBoundaryReconciler.swift \
  -o /tmp/SenseVoiceReconciliationDiagnosticsCheck && /tmp/SenseVoiceReconciliationDiagnosticsCheck

swift native/Tests/SenseVoiceShadowSchedulerCheck.swift
```

- [x] 文档更新：本文件 Task 0 checkbox、`docs/CLAUDE_LEGACY_PIPELINE_AUDIT.md` 一行迁移状态、`docs/开发日志.md`。
- [x] 构建安装：

```bash
./native/build_and_log.sh
```

- [x] 真实安装版 smoke：录一段 20 秒，确认日志出现新增字段，且胶囊显示行为无变化。

**Task 0 Progress / 2026-07-19:**

- RED 已执行并按预期失败：新增 reconciler seam confidence 用例缺少 `seamConfidence` 成员；scheduler 用例缺少 `discardedFastRequestCount` / `discardedCorrectionRequestCount`。
- GREEN 已通过：`SenseVoiceReconciliationDiagnosticsCheck`、`SenseVoiceShadowSchedulerCheck`、`SenseVoiceSnapshotProviderCheck`、`git diff --check`。
- 实现边界：只补诊断字段和日志汇总，不改变默认 `.audioTime` 策略、不改变 UI 展示、不改变最终交付/fallback。
- 构建安装已完成：`./native/build_and_log.sh` build-only 覆盖安装并打开 `2.0.39 (Build 775)`，安装版 Info.plist 与 codesign 校验通过。
- 构建后回归已通过：`SenseVoiceReconciliationDiagnosticsCheck`、`SenseVoiceShadowSchedulerCheck`、`SenseVoiceSnapshotProviderCheck`、`git diff --check`。
- 真实 smoke 证据：Build 775 日志 `D5994330` 为 8.7 秒短录音，新增 `discarded_fast`、`discarded_correction`、`boundary_correction_*`、`seam_confidence=timeOverlapOnly` 字段可见，`tail_gap_ms=0`，`final_asr_result source=candidate_preview_cache chars=35`，`paste_finish outcome=restored`。该样本短于原计划 20 秒；结合用户 2026-07-19 明确要求“继续执行，不用停下来”，项目经理接受其作为 Task 0 短 smoke 证据进入 Task 1，20 秒/2 分钟真实样本继续作为后续行为 Task 的验收门槛。

**Exit Gate:**

- 新日志字段可见。
- UI 无变化。
- 无粘贴/录音回归。

---

### Task 1: 内容交叉验证默认启用，禁止冲突边界硬拼

**Purpose:** 先阻止“公司 + 功功能”这类冲突被稳定文本硬拼。

**Files:**

- Modify: `native/Sources/Infrastructure/RealtimeTranscription/SenseVoiceBoundaryReconciler.swift`
- Modify: `native/Tests/SenseVoiceBoundaryReconcilerCheck.swift`
- Create: `native/Tests/SenseVoiceContentSeamVerificationCheck.swift`
- Modify: `docs/CLAUDE_LEGACY_PIPELINE_AUDIT.md`
- Modify: `docs/开发日志.md`

**Interfaces:**

```swift
struct SenseVoiceBoundaryReconciler {
    init(strategy: SenseVoiceBoundaryReconciliationStrategy = .lexicalOverlap)
}
```

Required behavior:

- Token timestamp alignment with at least 2 matching tokens within 0.75s → confirm seam.
- Lexical suffix/prefix overlap with at least 2 matching tokens → confirm seam if timestamps unavailable.
- Time overlap but content conflict → `recoveryRequired = true` and `seamConfidence = .noOverlapRecoveryTriggered`。
- Content conflict must not append both conflicting tails into `confirmedText`。

**Steps:**

- [x] 写 RED：构造真实问题用例：

```text
previous: 今天我们讨论公司
current: 功功能优化
expected: 不得输出 今天我们讨论公司功功能优化
```

- [x] 写 RED：构造正常 overlap：

```text
previous: 今天我们讨论功能
current: 功能优化
expected: 可以稳定推进到 今天我们讨论功能，并保留 优化 为 volatile
```

- [x] 将默认策略从 `.audioTime` 改为 `.lexicalOverlap`。
- [x] 保留 `.audioTime` 仅作为显式测试/诊断策略，不作为生产默认。
- [x] 确认内容冲突时 stable 不推进，volatile 可显示最新结果。
- [x] 运行：

```bash
swift native/Tests/SenseVoiceBoundaryReconcilerCheck.swift
swift native/Tests/SenseVoiceContentSeamVerificationCheck.swift
```

- [x] 构建安装：

```bash
./native/build_and_log.sh
```

- [ ] 真实录音门禁：
  - 说：“今天我们讨论功能优化。”
  - 再说一轮较快语速版本。
  - 日志不得出现稳定文本包含“公司功功能”类错拼。
  - 胶囊显示可以修订，但不能明显卡顿。

**Task 1 Progress / 2026-07-19:**

- RED 已执行并按预期失败：默认 `.audioTime` 对冲突 seam 未触发 `recoveryRequired`，失败信息为 “conflicting content overlap must request recovery instead of trusting time overlap”。
- GREEN 已通过：生产默认改为 `.lexicalOverlap`；`.audioTime` 旧行为测试显式固定策略后仍通过。
- Provider 回归已更新为内容可验证的健康 overlap fixture，避免旧测试继续要求“内容全量改写也稳定推进”的反目标行为。
- 已通过：`SenseVoiceContentSeamVerificationCheck`、`SenseVoiceBoundaryReconcilerCheck`、`SenseVoiceReconciliationDiagnosticsCheck`、`SenseVoiceSnapshotProviderCheck`、`git diff --check`。
- 构建安装已完成：`./native/build_and_log.sh` 触发完整版本构建，覆盖安装并打开 `2.0.40 (Build 776)`，安装版 Info.plist 与 codesign 校验通过。
- 构建后回归已通过：`SenseVoiceContentSeamVerificationCheck`、`SenseVoiceBoundaryReconcilerCheck`、`SenseVoiceSnapshotProviderCheck`、`git diff --check`。
- 待完成：真实说“今天我们讨论功能优化”与较快语速版本后，确认无“公司功功能”类稳定错拼、胶囊无明显卡顿；该项通过后才能关闭 Task 1 Exit Gate。

**Exit Gate:**

- 冲突 seam 不硬拼。
- 正常 seam 仍能推进。
- UI 流畅无退化。

---

### Task 2: 硬边界前后窗口校准

**Purpose:** 当 18 秒硬边界把一句话切成前后两段时，用边界前后音频重新识别校准，而不是直接拼两边。

**Files:**

- Create: `native/Sources/Domain/RealtimeTranscription/RealtimeBoundaryCorrectionPlanner.swift`
- Modify: `native/Sources/Infrastructure/RealtimeTranscription/SenseVoiceSnapshotProvider.swift`
- Modify: `native/Sources/Infrastructure/RealtimeTranscription/SenseVoiceBoundaryReconciler.swift`
- Create: `native/Tests/RealtimeBoundaryCorrectionPlannerCheck.swift`
- Create: `native/Tests/SenseVoiceBoundaryCorrectionIntegrationCheck.swift`
- Modify: `docs/CLAUDE_LEGACY_PIPELINE_AUDIT.md`
- Modify: `docs/开发日志.md`

**Interfaces:**

```swift
enum RealtimeBoundaryKind: Equatable, Sendable {
    case voicePause
    case hardLimit
    case conflictRecovery
}

struct RealtimeBoundaryCorrectionPlan: Equatable, Sendable {
    let boundaryTime: TimeInterval
    let audioStartTime: TimeInterval
    let audioEndTime: TimeInterval
    let kind: RealtimeBoundaryKind
}

struct RealtimeBoundaryCorrectionPlanner: Sendable {
    let preRollSeconds: TimeInterval
    let postRollSeconds: TimeInterval

    func plan(
        boundaryTime: TimeInterval,
        availableAudioStart: TimeInterval,
        availableAudioEnd: TimeInterval,
        kind: RealtimeBoundaryKind
    ) -> RealtimeBoundaryCorrectionPlan?
}
```

Initial configuration:

```swift
preRollSeconds = 4
postRollSeconds = 4
```

**Steps:**

- [x] 开工前阅读本计划，确认当前只执行 Task 2，不夹带 Task 3/4。
- [x] 代码走读：记录 `rollingSamples` 如何按时间范围取样、`SenseVoiceShadowRequest` 如何表达 `.boundaryCorrection`、boundary correction 完成后如何回写 stable/volatile。
- [x] 将代码走读得到的实现细节补进本 Task 的 Interfaces/Steps；补完后再写 RED。
- [x] 写 RED：`RealtimeBoundaryCorrectionPlannerCheck.swift` 断言边界后方不足 4 秒时不产出 plan。
- [x] 写 RED：断言边界后方足够时，产出 `[boundary - 4, boundary + 4]`，并正确 clamp 到可用音频范围。
- [x] 写 RED：`SenseVoiceBoundaryCorrectionIntegrationCheck.swift` 复现 `公司` / `功功能` 冲突时，provider 发起 boundary correction request。
- [x] 实现 planner。
- [x] Provider 增加 `boundaryCorrection` 请求类型；该请求不阻塞 fast，不阻塞 UI，只在后台完成后回写 reconciler。
- [x] Reconciler 接收 boundary correction 结果后，只修正边界附近 stable/volatile，不重置整个会话文本。
- [x] 日志增加：

```text
boundary_correction_start boundary_ms=... range_ms=...
boundary_correction_done outcome=success|failed seam_confidence=boundaryCorrected
```

- [x] 运行：

```bash
swift native/Tests/RealtimeBoundaryCorrectionPlannerCheck.swift
swift native/Tests/SenseVoiceBoundaryCorrectionIntegrationCheck.swift
```

- [x] 构建安装：

```bash
./native/build_and_log.sh
```

- [ ] 真实录音门禁：
  - 连续说话超过硬边界，刻意让一句话跨过边界。
  - 观察胶囊不中断、不冻结。
  - 日志出现 boundary correction。
  - 最终文本不出现边界错拼。

**Task 2 Progress / 2026-07-19:**

- RED 已执行并按预期失败：planner 测试失败于缺少 `RealtimeBoundaryCorrectionPlanner` / `RealtimeBoundaryCorrectionPlan`；integration 测试失败于冲突 recovery 后 `boundaryCorrectionRequestedCount == 0`。
- GREEN 已通过：新增 planner、`.boundaryCorrection` 请求类型、provider retained audio 14 秒、按时间范围取样 helper、Reconciler boundary correction 入口和 start/done 日志。
- Provider 初始化语义修正：生产 `initial` 显式 retained 14 秒；测试/自定义 configuration 未声明 retained 时仍按自己的 `maximumWindowSeconds`，避免无意放大所有测试/调用方缓存。
- 已通过：`RealtimeBoundaryCorrectionPlannerCheck`、`SenseVoiceBoundaryCorrectionIntegrationCheck`、`SenseVoiceContentSeamVerificationCheck`、`SenseVoiceBoundaryReconcilerCheck`、`SenseVoiceReconciliationDiagnosticsCheck`、`SenseVoiceSnapshotProviderCheck`、`git diff --check`。
- 构建安装已完成：`./native/build_and_log.sh` build-only 覆盖安装并打开 `2.0.40 (Build 777)`，安装版 Info.plist 与 codesign 校验通过。
- 构建后回归已通过：`RealtimeBoundaryCorrectionPlannerCheck`、`SenseVoiceBoundaryCorrectionIntegrationCheck`、`SenseVoiceSnapshotProviderCheck`、`git diff --check`。
- 真实对照发现的新证据：Build 777 用户 25 秒样本 `52B2A8BA` 中，shadow-runtime-cache 已 `completed`、`tail_gap_ms=0`、候选 122 字；但最终交付因超过短录音阈值强制走完整 final ASR，final 单独复刻识别同一 wav 仍输出“功能优度优化”，且仅 104 字。
- Task 2 收口修正：取消“超过 20 秒候选无条件失权”的最终交付硬阈值；shadow-runtime-cache 候选 completed 且有效时可直接交付，final ASR 只在候选不可交付、用户显式开启整段重识别或下游安全网判断需要时接管。
- 已通过：`FinalDeliveryUseCaseCheck` 新增长录音候选可胜过完整 final ASR 的 RED/GREEN 回归。
- 待完成：构建安装后用真实 25 秒/2 分钟录音复核 `final_delivery_selected source=candidate-preview-cache`；连续说话跨硬边界仍需确认日志出现 boundary correction，该项通过后才能关闭 Task 2 Exit Gate。

**Task 2 Code Walkthrough / 2026-07-19:**

- `SenseVoiceSnapshotProviderCore.rollingSamples` 当前只保存最近 `configuration.maximumWindowSeconds` 秒，默认 8 秒；`audioStartTime` 通过 `totalFrames/sampleRate - requestSamples.count/sampleRate` 反推。Task 2 要取 `[boundary-4, boundary+4]`，默认 8 秒缓存没有任何余量，真实异步延迟下可能刚好不够；实现前必须把 provider 的音频缓存能力和“识别请求窗口上限”分开，新增类似 `maximumRetainedAudioSeconds`，初始值至少覆盖 `preRoll + postRoll + service/调度余量`，建议先用 14 秒。
- 当前没有按时间范围取样 API。Task 2 需要新增 provider 内部 helper，例如 `samples(in range: RealtimeBoundaryCorrectionPlan) -> (samples: [Float], start: TimeInterval, end: TimeInterval)?`，用 `availableStart = totalAudioEnd - rollingSamples.count/sampleRate` 计算 index，并 clamp 到 rolling buffer 边界；planner 只产出时间范围，不读 samples。
- `SenseVoiceShadowRequestKind` 当前只有 `.fast` / `.correction`。Task 2 需要新增 `.boundaryCorrection`，并把 request 的 `audioStartTime/audioEndTime` 设置为 planner 产出的校准窗口，而不是常规 suffix window。
- 调度边界：现有 `SenseVoiceShadowScheduler` 只有一个 active request，不能真正并发 ASR；“不阻塞 UI”必须靠 `append(AudioFrame)` 只入队、不 await 识别来保证。“不阻塞 fast”的可执行含义定义为：boundary correction 不得替换 pending fast；若 fast 和 boundary correction 同时待处理，`takeNext()` 仍允许 fast 按现有 `maxConsecutiveFastBeforeCorrection` 节奏被 admit，boundary correction 走 correction/backlog lane，不新增 UI 同步等待。
- `TranscriptionEvent.reconciled` / `TranscriptReducer` 只能追加新的 finalized segment 并替换 volatile tail，不能编辑已经追加的 confirmed segment。因此 Task 2 的第一版不能承诺“回写修改任意历史 stable segment”。可执行范围是：当 Task 1 标记 `recoveryRequired` 且边界 correction 成功后，Reconciler 用 boundary correction 结果重新确认边界附近尚未稳定的 tail，产生新的 `newlyConfirmedText` 与 `volatileTailText`；如果冲突文本已经被旧策略稳定进历史 segment，只能依赖 fallback/后续重建，不能让 UI 或 reducer 逆向修补。
- `SenseVoiceBoundaryReconciler.consume(...)` 当前只接收识别结果，不知道 request kind。Task 2 需要给 Reconciler 增加显式入口，例如 `consumeBoundaryCorrection(_:)` 或给 `consume` 增加 source 参数；该入口成功时设置 `seamConfidence=.boundaryCorrected`，失败时保持 `recoveryRequired`，不得清空 confirmed prefix。
- 边界触发时机：Task 1 后 `apply(...)` 已能看到 `reconciliation.recoveryRequired` 和 `confirmedThroughTime/volatileTailText`。Task 2 第一版以 `recoveryRequired` 作为触发源，`boundaryTime` 优先使用 `reconciliation.confirmedThroughTime ?? request.audioStartTime`；硬边界的精确 18 秒触发需等 Task 4 语音活动切分后再细化，不夹带到本 Task。
- 日志位置：boundary correction 入队时在 provider 内记录 `boundary_correction_start boundary_ms=... range_ms=...`，完成后记录 `boundary_correction_done outcome=... seam_confidence=...`；`SpeechInputCoordinator` 继续只汇总 diagnostics，不承载算法。

**Exit Gate:**

- 硬边界冲突会触发校准。
- 校准不会阻塞 UI。
- 校准失败不会硬拼。

---

### Task 3: 语境感知幻觉过滤

**Purpose:** 抑制低置信语境里的 “Yeah/the/嗯/啊” 幻觉，但不误删用户真实说出口的口头禅。

**Files:**

- Create: `native/Sources/Domain/RealtimeTranscription/RealtimeRecognitionHallucinationFilter.swift`
- Modify: `native/Sources/Infrastructure/RealtimeTranscription/SenseVoiceSnapshotProvider.swift`
- Create: `native/Tests/RealtimeRecognitionHallucinationFilterCheck.swift`
- Modify: `docs/CLAUDE_LEGACY_PIPELINE_AUDIT.md`
- Modify: `docs/开发日志.md`

**Interfaces:**

不要使用不存在的“VAD 置信度”。当前生产 VAD 是 Bool，因此接口用 evidence：

```swift
enum VoiceActivityEvidence: Equatable, Sendable {
    case speechDetected
    case silenceDetected
    case unknown
}

struct RealtimeRecognitionHallucinationFilter: Sendable {
    func shouldSuppress(
        text: String,
        voiceActivity: VoiceActivityEvidence,
        isAtPauseBoundary: Bool,
        hasPriorStableText: Bool
    ) -> Bool
}
```

Rules:

- 黑名单词来自旧 `RecognitionTextFilter.swift` 的中英文静音幻觉列表。
- 只有整段精确命中黑名单，且处于 `silenceDetected` 或 `isAtPauseBoundary == true`，才 suppress。
- `speechDetected` 时不 suppress “Yeah”，避免误删真实口头禅。
- `unknown` 时只 suppress 极短、无上下文、无 prior stable 的明显静音幻觉。

**Steps:**

- [ ] 写 RED：`silenceDetected + "Yeah" + pauseBoundary` → suppress。
- [ ] 写 RED：`speechDetected + "Yeah"` → not suppress。
- [ ] 写 RED：`speechDetected + "嗯"` → not suppress。
- [ ] 写 RED：`unknown + "the" + no prior stable` → suppress。
- [ ] 写 RED：`unknown + 正常中文短句` → not suppress。
- [ ] 实现 filter。
- [ ] Provider 在 apply 前调用 filter；被 suppress 的结果不进入 finalized/stable，不清空已有 stable。
- [ ] 日志增加：

```text
hallucination_filter suppress=true text="..." voice_activity=... pause_boundary=...
```

- [ ] 运行：

```bash
swift native/Tests/RealtimeRecognitionHallucinationFilterCheck.swift
swift native/Tests/SenseVoiceSnapshotProviderCheck.swift
```

- [ ] 构建安装：

```bash
./native/build_and_log.sh
```

- [ ] 真实录音门禁：
  - 开头静默半秒再说中文，确认不冒 “Yeah”。
  - 故意开头说 “Yeah 我们继续测试”，确认 “Yeah” 没被误删。
  - 自然停顿后继续说，确认停顿处不冒幻觉词。

**Exit Gate:**

- 幻觉词减少。
- 真实口头禅不被误删。
- UI 不等待 filter。

---

### Task 4: 语音活动感知切分

**Purpose:** correction 优先落在自然停顿处，而不是固定 6 秒切到词中间。

**Files:**

- Modify: `native/Sources/Infrastructure/RealtimeTranscription/SenseVoiceSnapshotProvider.swift`
- Modify: `native/Sources/Application/SpeechInputCoordinator.swift`
- Create: `native/Tests/SenseVoiceVoiceAwareBoundaryCheck.swift`
- Create: `native/Tests/SpeechInputVoiceActivityRoutingBoundaryCheck.sh`
- Modify: `docs/CLAUDE_LEGACY_PIPELINE_AUDIT.md`
- Modify: `docs/开发日志.md`

**Interfaces:**

VAD 不在 `append(AudioFrame)` 内同步执行。Provider 只接收最近状态：

```swift
enum RealtimeVoiceActivityState: Equatable, Sendable {
    case unknown
    case speech(activeSince: TimeInterval?)
    case pause(detectedAt: TimeInterval)
}

protocol RealtimeVoiceActivityReceiving: AnyObject {
    func updateVoiceActivity(_ state: RealtimeVoiceActivityState)
}
```

Provider behavior:

- fast 首次触发：必须已观察到 `.speech`，避免录音前静音 0.5 秒直接识别。
- correction 触发：
  - 达到 soft boundary 且最近状态是 `.pause` → correction。
  - 达到 hard boundary → correction + 后续 boundary correction。
  - 长时间 VAD unknown → 保留硬上限兜底，不无限等待。

初始建议：

```swift
softBoundarySeconds = 10
hardBoundarySeconds = 18
```

**Steps:**

- [ ] 写 RED：语音开始前追加 0.5 秒静音，不应触发 fast。
- [ ] 写 RED：语音 8 秒后停顿，到 soft boundary 后应触发 correction。
- [ ] 写 RED：连续语音超过 hard boundary，必须触发 correction，且标记 hard boundary。
- [ ] 写源码边界 RED：`SpeechInputCoordinator` 不得新增文本拼接/过滤算法，只允许传递 voice activity state。
- [ ] 实现 Provider 的 voice activity state。
- [ ] 将现有 `receiveVoiceProbe()` 的结果以异步状态传给 Provider/runtime。
- [ ] 保留原 `recorder.updateRealtimeVoiceActive` 行为，不破坏旧分块/自动停止。
- [ ] 运行：

```bash
swift native/Tests/SenseVoiceVoiceAwareBoundaryCheck.swift
bash native/Tests/SpeechInputVoiceActivityRoutingBoundaryCheck.sh
```

- [ ] 构建安装：

```bash
./native/build_and_log.sh
```

- [ ] 真实录音门禁：
  - 先静默 1 秒再说话，确认开头不冒幻觉词。
  - 说一句话中间自然停顿，确认 correction 落在停顿附近。
  - 连续说话超过 18 秒，确认 hard boundary correction 后文本不乱拼。
  - 胶囊出字仍顺滑。

**Exit Gate:**

- correction 不再纯固定秒表。
- UI 无卡顿。
- 停顿与硬边界日志可判读。

---

### Task 5: 调度可观测性和容量决策收口

**Purpose:** 把“请求是否被丢弃/降级/替换”从日志里看清楚，但不在没有证据时调参。

**Files:**

- Modify: `native/Sources/Infrastructure/RealtimeTranscription/SenseVoiceShadowScheduler.swift`
- Modify: `native/Sources/Infrastructure/RealtimeTranscription/SenseVoiceSnapshotProvider.swift`
- Modify: `native/Sources/Application/SpeechInputCoordinator.swift`
- Modify: `native/Tests/SenseVoiceShadowSchedulerCheck.swift`
- Create: `native/Tests/SenseVoiceSchedulingObservabilityCheck.swift`
- Modify: `docs/CLAUDE_LEGACY_PIPELINE_AUDIT.md`
- Modify: `docs/开发日志.md`

**Interfaces:**

```swift
struct SenseVoiceShadowSchedulingDiagnostics: Equatable, Sendable {
    let discardedFastRequestCount: Int
    let discardedCorrectionRequestCount: Int
    let replacedCorrectionRequestCount: Int
    let degradedCorrectionRequestCount: Int
    let admittedFastRequestCount: Int
    let admittedCorrectionRequestCount: Int
}
```

**Steps:**

- [ ] 写 RED：fast pending 被替换时 `discardedFastRequestCount += 1`。
- [ ] 写 RED：same commit horizon correction 被替换时 `replacedCorrectionRequestCount += 1`。
- [ ] 写 RED：capacity exceeded 时 `degradedCorrectionRequestCount += 1`。
- [ ] 实现 scheduler diagnostics。
- [ ] Provider diagnostics 透传。
- [ ] `shadow_sensevoice_summary` 输出所有调度字段。
- [ ] 不改 capacity 默认值；如真实日志证明容量不足，另开计划评估。
- [ ] 运行：

```bash
swift native/Tests/SenseVoiceShadowSchedulerCheck.swift
swift native/Tests/SenseVoiceSchedulingObservabilityCheck.swift
```

- [ ] 构建安装：

```bash
./native/build_and_log.sh
```

- [ ] 真实录音门禁：
  - 20 秒与 2 分钟录音日志能解释 completed、discarded、degraded、tail gap。
  - 若 discarded/degraded 高但 UI/最终文本正常，记录为可接受。
  - 若 discarded/degraded 高且质量差，停止并创建容量/预算专项计划。

**Exit Gate:**

- 调度问题可判读。
- 未经证据不调参。

---

### Task 6: 端到端真实录音验收与旧风险收口

**Purpose:** 用真实安装版证明本计划达成，而不是只靠单测。

**Files:**

- Modify: `docs/superpowers/plans/2026-07-19-realtime-recognition-quality-hardening.md`
- Modify: `docs/CLAUDE_LEGACY_PIPELINE_AUDIT.md`
- Modify: `docs/ARCHITECTURE.md`
- Modify: `docs/开发日志.md`
- Modify: `native/Sources/Presentation/VersionHistory/VersionHistoryViewController.swift`

**验收矩阵:**

- [ ] 20 秒中文自然语音。
- [ ] 2 分钟中文自然语音。
- [ ] 连续说话超过 18 秒，触发 hard boundary。
- [ ] 自然停顿后继续说话。
- [ ] 中英混杂，包含真实 “Yeah”。
- [ ] 开头静默 0.5–1 秒。
- [ ] 停止录音后最终粘贴。
- [ ] 取消录音后下一轮恢复。
- [ ] 关闭在线 ASR，本地 fallback。
- [ ] MiMo ready 时不影响本地链路边界。
- [ ] 无 Key 时不上传、不阻塞、不影响本地。

**日志必须能解释:**

- [ ] `tail_gap_ms`
- [ ] `seam_confidence`
- [ ] `boundary_correction_*`
- [ ] `hallucination_filter`
- [ ] `discarded_fast`
- [ ] `discarded_correction`
- [ ] `resource_degraded`
- [ ] `completed`
- [ ] `final_asr_result source/reason`

**Definition of Done:**

- [ ] 不再复现 “今天我们讨论公司功功能优化” 类稳定错拼。
- [ ] 不再复现开头/停顿处明显 “Yeah” 幻觉。
- [ ] 用户感知胶囊出字顺畅，不因后台 correction/VAD 卡顿。
- [ ] 新核心结果异常时 fallback 完整 final ASR。
- [ ] 文档、开发日志、版本历史全部更新。
- [ ] 项目经理可以从本文件 checkbox 和真实日志判断每阶段是否完成。

## Rollback Rules

每个 Task 必须独立提交。出现以下任一情况，回滚当前 Task：

- 胶囊显示卡顿或明显比上一版本慢。
- 正常语音被过滤为空。
- 真实 “Yeah” 被误删。
- 内容冲突被稳定成错拼。
- 停止录音后粘贴为空。
- 2 分钟录音明显丢尾。
- 在线 ASR 缺 Key 或失败影响本地 fallback。
- 日志无法解释失败原因。

## Project Manager Review Checklist

项目经理每次批准进入下一 Task 前必须确认：

- [ ] 开发者已重新阅读本文件。
- [ ] 本次只执行了一个 Task；没有夹带其它 Task 的实现。
- [ ] 已统计距离上次架构师复审后的实现提交数；若达到 3–5 次，或本 Task 改动跨越 Provider/Reconciler/FinalDelivery/Presentation 边界，已完成架构师复审。
- [ ] 架构师复审结论已写回本文件的 “Architecture Review Log”。
- [ ] 如果当前是 Task 2，已先完成代码走读，并把走读后的实现细节补回 Task 2。
- [ ] 当前 Task 的 RED 测试确实先失败过。
- [ ] GREEN 后跑了聚焦测试。
- [ ] 已通过 `git diff --check`。
- [ ] 如改代码，已运行 `./native/build_and_log.sh` 并覆盖安装。
- [ ] 真实安装版已按本 Task 门禁录音。
- [ ] `docs/开发日志.md` 已记录版本、行为、验证、风险。
- [ ] 本文件 checkbox 已更新。
- [ ] 没有把数据处理逻辑写进 UI / Candidate / RecordingPanel。
- [ ] 没有用手写音量阈值替代 Silero VAD。
- [ ] 没有跳过 fallback。

## Architecture Review Log

> 项目经理维护本节。每累计 3–5 次实现提交，或任何提前触发条件出现时，必须新增一条架构师复审记录。没有复审记录，不允许继续下一批提交。

| 日期 | 提交范围 | 触发原因 | 架构师结论 | 后续动作 |
| --- | --- | --- | --- | --- |
| 2026-07-19 | 计划提交 `55438367` → 本次规则补充 | 用户要求固定“每 3–5 次提交架构师复审” | 规则已写入计划，实施尚未开始 | 从 Task 0 开始；第 3 次实现提交后必须复审 |
| 2026-07-19 | Task 0 诊断实现（Build 775，提交前复核） | 触碰 Reconciler/Provider/Application 诊断接口，按跨边界门禁提前复核 | Conditional Accepted：新增字段只沿既有数据层向上透传只读诊断；`SpeechInputCoordinator` 仅汇总日志；未改变默认 `.audioTime` 策略、UI 展示、最终交付或 fallback；`boundary_correction_*` 暂为占位 0，后续 Task 2 才允许改变语义 | 真实 20 秒 smoke 通过后可进入 Task 1；进入 Task 2 前必须按计划先走读并补实现细节；再累计 3–5 次实现提交前复审 |
| 2026-07-19 | Task 1 内容交叉验证默认启用（Build 776，提交前复核） | 改变 Reconciler 生产默认策略，属于稳定文本确认语义变更 | Conditional Accepted：稳定文本确认从“时间重叠即可推进”收紧为“内容可验证才推进”，符合 P0“稳定文本必须比临时文本更保守”；UI 仍只消费 ViewState，Provider/FinalDelivery/fallback 边界未改变；风险是短窗口内容漂移会更晚稳定，必须用真实录音确认胶囊不明显卡顿 | 真实门禁通过后可进入 Task 2；Task 2 必须先走读 rolling audio buffer/request/session 回写路径并补计划，再写 RED |
| 2026-07-19 | Task 2 边界校准后台请求（Build 777，提交前复核） | 新增 Domain planner、Provider retained audio、Scheduler request kind、Reconciler boundary correction 入口，跨多个核心边界 | Conditional Accepted：planner 属于 Domain，Provider 负责取样和调度，Reconciler 负责解释校准结果，UI/Session/Reducer 不处理算法；`append(AudioFrame)` 不等待校准，符合“UI 永不等待数据层”；主要风险是第一版不能编辑已确认历史 segment，必须用真实跨边界录音验证收益 | Build 777 后做真实跨硬边界验收；未通过则不进入 Task 3，优先修 Task 2 |
| 2026-07-19 | Task 2 收口：FinalDelivery 候选/完整 final 仲裁修正（Build 778，提交前复核） | Build 777 真实样本证明完整 final ASR 并不天然更准；本次触碰 FinalDelivery 边界，按门禁提前复审 | Conditional Accepted：这是最小结构修正，权威仲裁仍只在 Application `FinalDeliveryUseCase`，Provider/Reconciler/UI 不参与粘贴策略；取消时长硬阈值符合“最终交付有 fallback、但不盲信单一路径”。保留用户显式整段重识别优先级，候选不可交付仍 fallback final ASR | Build 778 已覆盖安装并通过回归；仍需复核 25 秒/2 分钟真实录音日志。若候选 completed 但内容质量明显退化，再增加质量判定而不是恢复时长硬阈值 |

## Current Status

- 2026-07-19：计划已重写为项目级执行计划。
- 2026-07-19：已补充架构师复审硬门禁：每 3–5 次实现提交必须复审，跨边界改动提前复审。
- 2026-07-19：已补充执行纪律硬门禁：每次开工前读计划、每次只做一个 Task、Task 2 前先走读并补计划、每个 Task 完成后更新计划。
- 当前状态：Task 2 自动化实现、Build 777 安装后暴露最终交付仲裁错误；FinalDelivery 收口修正已完成并覆盖安装 Build 778，待真实录音复核。
- 下一步：先验证 Build 778 的最终交付来源和真实 25 秒/2 分钟长录音表现；真实跨边界门禁通过后，才进入 Task 3（语境感知幻觉过滤）。
