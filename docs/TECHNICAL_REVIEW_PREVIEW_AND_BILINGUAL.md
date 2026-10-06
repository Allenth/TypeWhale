# 预览框与中英文输入技术审查报告

**审查日期**：2026-07-10
**分支**：`codex/typewhale-pro-asr-hotwords`
**审查性质**：只读代码审查、历史日志复核、纯领域回归检查；本轮没有修改运行代码、没有构建、没有安装。

## 一、审查结论

当前预览框不是由单一 bug（缺陷）导致，而是由三条资源链同时超出设计边界：

1. 音频快照和离线识别重复处理，形成持续的 I/O（输入输出）与 CPU（处理器）放大。
2. 快速预览和边界校正共用一个串行 ASR（语音识别）执行槽；校正队列没有有界背压（backpressure，反压）或合并规则，无法从代码上保证长录音延迟稳定。
3. 文字状态虽然存在，但 UI（用户界面）仍在主线程重复测量、布局和绘制，且草稿更新会重复触发窗口布局。

因此，之前对调度公平、磁盘探测、动画欠账和后缀宽度的修复只能降低局部症状，不能解决一小时场景的端到端容量问题。

中英文同时输入则是另一类问题：当前产品代码只有 `RecognitionLanguageMode.chinese`，ASR 配置固定为中文模式，当前内置模型能力也被代码明确标记为不支持热词/中英混合；后处理无法恢复已经在声学识别阶段丢失的英文实体。

## 二、主链路与当前分层

### 当前主链路

```text
快捷键
-> SpeechInputCoordinator（语音输入协调器）
-> AudioRecorder（录音与快照）
-> SenseVoice / sherpa-onnx（离线 ASR）
-> PreviewRequestScheduler（预览调度）
-> PreviewTranscriptReducer（预览文字归约）
-> RecordingPanel / RecordingCapsuleView（胶囊渲染）
-> 停止时增量组装或完整录音 final ASR（最终识别）
-> 智能整理/翻译
-> PasteCoordinator（粘贴协调器）
```

### 分层判断

- Domain（领域层）已有 `PreviewTranscriptReducer`，可以保存确认片段、可变尾部和显示版本。
- Application（应用层）仍由 2,849 行的 `SpeechInputCoordinator` 集中管理录音、VAD、实时预览、最终 ASR、整理、翻译、粘贴和内存安全。
- Infrastructure（基础设施层）的 `AudioRecorder` 同时负责写完整录音、写预览快照、计算频段、驱动 VAD 窗口和派发 UI 回调。
- Presentation（展示层）的 `RecordingCapsuleView` 同时管理文字动画、字体测量、可见后缀计算、CoreText（文本排版）绘制和波形绘制。
- 当前没有独立的 Presentation Snapshot（展示快照）或完整 Render Cache（渲染缓存）；`CapsuleVisibleTextCache` 只缓存可见后缀测量。

## 三、预览框具体问题

### P0：快照与识别存在持续放大，长录音无法按稳定成本运行

**证据**：

- `native/Sources/Infrastructure/Audio/AudioRecorder.swift:270-305` 在每个约 `0.5s` 节拍中，把当前块从块起点到当前时刻的全部 `realtimeBuffers` 交给快照写入；每个块在 `10–18s` 后才清空。
- `native/Sources/Infrastructure/Audio/AudioRecorder.swift:595-626` 将整个当前块再次写成一个 WAV；`snapshotWriteInFlight` 只能跳过写入中的中间快照，不能改变每个成功快照包含完整当前块的事实。
- `native/Sources/Application/RealtimePreview/ExperimentalRealtimePreviewPipeline.swift:40-80` 对这些快照逐个提交 fast（快速）识别；`native/Sources/Application/RealtimePreview/ExperimentalRealtimePreviewPipeline.swift:143-205` 每个请求都调用一次 `transcribeDetailed`。

一个约 `18s` 的块，如果每 `0.5s` 都成功写出并识别，写盘和读取/解码的音频量约为输入音频的十几倍；边界校正还会额外写入最多 `22.5s` 的窗口。这不是 1.2 的“整段越来越长”平方增长，但仍然是长录音中持续存在的高倍重复工作。

**影响**：

- 录音越长，累计 CPU、磁盘 I/O 和模型解码时间越高；即使内存被窗口限制，也不能保证实时性。
- 当写盘或模型处理速度下降时，`snapshotWriteInFlight` 会跳过中间快照，用户看到的预览节奏就会变慢或不均匀。

**结论**：只优化 UI 绘制不能解决这个问题；必须重做音频传输/识别输入路径，避免把同一段当前块反复落盘并重新读取。

### P0：校正队列无界，单执行槽没有稳定容量保证

**证据**：

- `native/Sources/Application/RealtimePreview/PreviewRequestScheduler.swift:57` 使用无上限数组 `pendingCorrections`。
- `native/Sources/Application/RealtimePreview/PreviewRequestScheduler.swift:90-98` 每个 correction（校正）请求直接追加，没有最大长度、合并、丢弃策略或暂停生产者。
- `native/Sources/Application/RealtimePreview/PreviewRequestScheduler.swift:126-143` 只改变执行顺序；`correctionBacklogThreshold` 只是选择优先级和日志阈值，不是容量上限。
- `native/Sources/Application/RealtimePreview/ExperimentalRealtimePreviewPipeline.swift:138-140` backlog（积压）超过阈值只记录诊断，不改变生产速率。
- `native/Sources/Application/SpeechInputCoordinator.swift:74-80` 的 `asr` 和 `realtimeASR` 共享同一个 `nativeASR`。
- `native/Sources/Infrastructure/ASR/SenseVoiceASR.swift:34-41` 该桥只有一条串行队列；C 桥 `native/TypeSpeakerNativeASR.c:228-238` 的 SenseVoice 识别器配置为 CPU、3 个模型线程。

**容量推导**：边界校正大约每 `10–18s` 产生一次，单次校正需要读取并解码最多 `22.5s`；如果某段时间模型处理耗时超过边界产生间隔，积压必然增长。当前代码没有任何机制能让积压有界，同时又保留所有 correction FIFO（先进先出）请求。

**影响**：

- 快速预览只能保留最新 pending fast（待处理快速请求），但正在执行的旧 fast 无法取消。
- correction 不能被合并，长录音可能进入“校正越来越落后、停止时必须长时间排空”的状态。
- 两个“路由器”并不代表两个执行器；实时识别和最终识别仍竞争同一个串行桥。

**结论**：这是当前方案无法保证一小时体验的核心原因之一。调度公平只能改变谁先执行，不能改变总工作量和单执行槽的吞吐量。

### P0：已有文字后，主线程仍反复做完整胶囊绘制与布局

**证据**：

- `native/Sources/Presentation/Capsule/RecordingCapsuleView.swift:127-137` 的 `update` 无论来源是文字、状态还是波形，最后都会设置 `needsDisplay = true`。
- `native/Sources/Infrastructure/Audio/AudioRecorder.swift:321-327` 每个音频处理缓冲都会向主线程派发 bands（波形频段）；约 `1024` 帧时约每秒数十次。
- `native/Sources/Presentation/Capsule/RecordingCapsuleView.swift:80-125` 的 `preferredSize`、`measuredPreviewWidth` 和 `predictedLayoutDraft` 会同步调用 `NSString.size(withAttributes:)`。
- `native/Sources/Presentation/Capsule/RecordingCapsuleView.swift:140-201` 每次 `draw(_:)` 都重新计算可见文字，并创建 `NSMutableAttributedString` 后调用 CoreText 绘制。
- `native/Sources/Presentation/Capsule/RecordingPanel.swift:353-356` 每次 `updateDraft` 都调用 `resizeAndPosition()`；`376-424` 即使最终窗口尺寸没有变化，也会重新设置多个子视图 frame。

Build 652 的 `CapsuleVisibleTextCache` 只缓存部分后缀测量，不能缓存完整布局、带样式文本或栅格结果；此前 `sample` 已观察到主线程反复停在 `RecordingCapsuleView.draw`、`preferredSize` 和 CoreText，同时 ASR 推理达到约 `194%` CPU。

**结论**：用户关于“缓存内容本身不应卡，卡的是绘制”的理解对 UI 部分成立；但当前代码尚未实现“页面只显示已准备好的文字结果”。

### P1：音频处理队列优先级过高且承担过多工作

**证据**：

- `native/Sources/Infrastructure/Audio/AudioRecorder.swift:129-130` 使用 `.userInteractive` 的 processing queue（处理队列）和 `.userInitiated` 的 snapshot queue（快照队列）。
- `native/Sources/Infrastructure/Audio/AudioRecorder.swift:261-327` 同一处理队列同时执行文件写入、频段计算、预览缓冲管理、VAD 窗口维护和多个主线程回调。
- `native/Sources/Infrastructure/Audio/AudioRecorder.swift:751-790` 每个音频缓冲都对多个频率执行三角函数计算；这不是主要识别工作，却和录音、快照调度共享高优先级资源。

**影响**：模型推理、音频处理和 UI 竞争 CPU 时，单纯把某个回调移出主线程不能恢复整体余量。

### P1：生产代码没有真正使用“中心校正窗口规划器”

**证据**：

- `native/Sources/Domain/RealtimePreview/BoundaryCenteredPreviewPlanner.swift:50-64` 定义了 `22.5s` 窗口，并要求 `availableAudioEnd >= desiredEnd`。
- 全仓库搜索显示该规划器只在 `native/Tests/PreviewTranscriptReducerCheck.swift` 中使用；生产 `AudioRecorder` 没有调用它。
- `native/Sources/Infrastructure/Audio/AudioRecorder.swift:642-670` 只等待边界后 `9.5s`，然后从当前滚动上下文中取“最多 `22.5s`”；早期边界得到的窗口可能短于 `22.5s`，也不保证边界处在规划器定义的安全中心区域。

**影响**：测试中的窗口语义与生产中的音频快照语义不一致。校准对齐测试通过，并不能证明真实录音每个边界都按同样窗口生成。

### P1：最终块写盘失败时，生产者已先丢弃原始缓冲

**证据**：

- `native/Sources/Infrastructure/Audio/AudioRecorder.swift:285-301` 在调用最终快照写盘前，先更新 `realtimeChunkStartFrame`、递增 `realtimeChunkIndex` 并清空 `realtimeBuffers`。
- `native/Sources/Infrastructure/Audio/AudioRecorder.swift:610-620` 写盘失败时只删除目标文件，没有把失败块重新排队或恢复。
- `docs/ARCHITECTURE.md:357-359` 已明确记录这一项仍是 Preview Pipeline Blocker（预览管线阻断项）。

**影响**：最终块可能永远没有校正输入，长录音最终文本产生缺口；这不是 UI 卡顿，而是数据正确性失败。

### P1：预览存在两套并行状态权威，增加语义漂移

**证据**：

- 旧路径使用 `SpeechSession.committedPreviewText` / `latestPreviewText`（`native/Sources/Application/SpeechInputState.swift:18-23`）。
- 实验路径使用 `PreviewTranscriptReducer.state`，但 `native/Sources/Application/SpeechInputCoordinator.swift:1598-1604` 又把 reducer 的 `displayText` 填回旧 session 的 `latestPreviewText`，并将 `committedPreviewText` 清空。
- `finishRecording` 在 `native/Sources/Application/SpeechInputCoordinator.swift:1300-1303` 仍先读取旧 session 字段；实验长录音随后又走另一套 `PreviewTranscriptState` 组装。

**影响**：同一会话同时保留旧预览状态和实验预览状态，增加停止、失败、回退和跨会话回调的理解成本；这也是过去多次“看似修好一个状态又出现另一个状态”的结构性原因。

### P2：代码中存在未接入的生命周期接口，说明设计未闭合

- `LongFormTranscriptionSession.shouldFinish(elapsed:)`（`native/Sources/Application/RealtimePreview/LongFormTranscriptionSession.swift:19-21`）没有生产调用点，真正上限由协调器自己的 `enforceMaxRecordingDuration()` 决定。
- `ExperimentalRealtimePreviewPipeline.reset()`（`native/Sources/Application/RealtimePreview/ExperimentalRealtimePreviewPipeline.swift:83-85`）没有生产调用点；其 `epoch` 还是不可变属性，重置语义也未形成完整会话生命周期。

这些不是当前卡顿的主因，但表明实验接口、协调器生命周期和实际执行路径尚未收敛。

## 四、中英文同时输入具体问题

### P0：产品配置层没有“中英混合”语言模式

**证据**：

- `native/Sources/Domain/ASRDomain.swift:4-38` 的 `RecognitionLanguageMode` 只有 `.chinese`；`load()` 永远返回 `.chinese`。
- `native/Sources/Application/SpeechInputCoordinator.swift:1131-1136` 创建会话时硬编码 `ASRConfiguration(languageMode: .chinese, ...)`。
- `native/Sources/Infrastructure/ASR/SenseVoiceASR.swift:139-142` 和 `168-185` 只把这个配置转成 SenseVoice 的 language 参数。

当前 C 桥虽然传入 `auto`，但产品层没有 mixed（混合）模式、语言路由或逐段语言信息；这不能等同于已实现中英混合输入。

### P0：当前内置 ASR 能力被代码明确标记为不支持中英混合/热词

**证据**：

- `native/Sources/Infrastructure/ASR/ASRProviderCapabilities.swift:46-68` 将 SenseVoice 和 Qwen3-ASR 的 `supportsHotwords`、`supportsCodeSwitching` 都标为 `false`，并标记为 `verifiedUnsupported`。
- `native/Sources/Infrastructure/ASR/SenseVoiceASR.swift:278-294` 创建识别器时给两个模型传入的 `hotwords` 都是空字符串。
- `native/Sources/Core/SmartInput/DeveloperLexiconStore.swift` 的词库只被 SmartInput（智能输入）整理链路使用；没有被接入当前 ASR C 桥。

**影响**：英文模型名、API 名、代码名如果在第一遍声学识别中被识别成中文或丢失，后续 `RecognitionTextNormalizer` 只能清理格式，不能凭空恢复原始英文。

### P1：模型能力表与实际主链路没有形成路由执行

`ASRProviderCapabilities` 已经定义了 `supportsHotwords`、`supportsCodeSwitching`、`supportsStreaming` 等能力，但当前 `SpeechInputCoordinator` 仍直接按用户选择创建 SenseVoice/Qwen3 路径；能力表没有成为强制的 provider（模型提供者）准入或 fallback（备用）策略。

项目文档中规划的：

```text
中文 ASR 主路
-> 英文/热词 ASR 侧路
-> KWS / CTC Word Spotter（关键词声学检测）
-> Segment Merger（片段合并器）
```

目前仍是策略文档，不是 `native/Sources` 中的生产链路。

## 五、为什么之前的多轮方案无法解决

### 1. 修复层级不对

历史改动依次处理了磁盘探测、调度公平、动画欠账、后缀测量，但最主要的重复音频工作、单执行槽容量和无界校正队列没有同时被解决。每个补丁都能改善一个局部指标，却没有改变端到端资源方程。

### 2. “快”和“准”被放在同一个不可取消执行器里

fast 要求快速反馈，correction 要求更长上下文；两者共用同一个离线模型和串行队列，且 active request（正在执行请求）不可取消。只调优先级无法同时满足两种互相冲突的服务时间。

### 3. 测试主要验证规则，不验证真实容量

现有纯领域检查通过了窗口、重叠、调度顺序和缓存规则，但没有自动验证：

- 每小时实际写入/读取了多少音频；
- correction backlog 是否长期有界；
- active ASR 在积压时能否取消；
- 主线程每秒实际绘制次数和 CoreText 时间；
- 20 秒、60 秒、5 分钟、1 小时的端到端延迟曲线。

因此“规则测试通过”不能推出“长录音稳定”。

### 4. 预览文字动画掩盖了状态与识别问题

`CapsuleTextBuffer` 的按位刷新和尾部动画可以让短时结果看起来连续，但它不是识别权威；当校正结果改变前缀或发生跨块接缝变化时，展示层仍需要重新组织文字。动画层不能替代稳定的展示快照和渲染缓存。

### 5. 中英文问题不是整理模型能单独解决的

当前主 ASR 能力不足且热词为空，SmartInput 只能处理已经得到的文本。把更多规则堆到整理层无法恢复音频阶段丢失的英文实体。

## 六、技术总监结论与优先级

### 预览框

**结论**：当前预览框路线在长录音场景下不是“还差一个 UI 小修复”，而是数据路径、执行容量和渲染路径同时未闭合。继续只改胶囊绘制，不能解决根因。

**必须先解决的顺序**：

1. 先建立长录音容量基线：快照写入放大倍数、ASR 服务时间、校正到达率、队列积压、主线程绘制时间。
2. 决定 fast/correction 是采用可证明有界的单执行器策略，还是采用隔离执行器/不同模型；不能继续无限追加 correction。
3. 将音频输入改为一次顺序写入 + 有界内存窗口，避免每个快照把当前块完整重新落盘。
4. 将展示快照和渲染缓存从 `RecordingCapsuleView` 中分离；波形、边框和文字不能共享同一失效路径。
5. 修复最终块写盘失败的数据丢失路径，再谈长录音最终文本可靠性。

### 中英文同时输入

**结论**：当前代码不是“中英文同时输入效果不好”，而是尚未实现完整的中英混合识别架构。当前内置 SenseVoice/Qwen3 路径被明确标记为不支持热词/混合，且产品层没有混合语言模式。

**必须先解决的顺序**：

1. 先建立真实中英混合评测集和当前 baseline（基线），不接主粘贴链路。
2. 通过 provider 能力接口接入支持中英混合/热词的 sidecar（旁路进程）候选。
3. 实现语言/热词路由和带时间范围的片段合并器。
4. 离线评测通过后，才允许以实验开关接入 final ASR；实时预览最后接入。

## 七、当前建议

本审查不建议立即继续改 Build 652 的胶囊绘制补丁，也不建议直接并行启动两个完整模型。下一步应先冻结当前安装版作为证据基线，完成一次不改行为的容量测量；然后依据测量结果决定是“有界单引擎”还是“隔离执行器/模型”。中英文输入则应作为独立主线，不与预览框性能实验混改。
