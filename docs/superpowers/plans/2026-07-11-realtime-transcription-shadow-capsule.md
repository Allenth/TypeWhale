# Realtime Transcription Shadow Capsule Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **2026-07-18 architecture update:** This document remains the migration history and Stage 9A evidence ledger. For the forward plan to keep only one realtime transcription architecture, read `2026-07-18-single-realtime-transcription-architecture-plan.md` first. The forward decision is Conditional Accepted: candidate/unified realtime core is the target production architecture, but legacy preview retirement is forbidden until the new plan's stage gates pass.

**Goal:** 在不改变 TypeWhale 当前录音、旧胶囊、最终识别和粘贴行为的前提下，旁路建立可同时支持非流式、本地流式和在线流式 Provider 的统一转录核心，并用第二个影子胶囊实时展示和比较新链路结果。

**Architecture:** 采用 Strangler Migration（旁路迁移）。旧 `SpeechInputCoordinator`、旧预览胶囊和完整录音 final ASR 在迁移期间始终保持生产权威；新 `RealtimeTranscriptionSession` 以独立会话、统一事件、唯一 Transcript 状态和结构化 ViewState 运行，第二个影子胶囊只能观察，不能结束录音、触发 VAD、提交 final、整理、翻译、粘贴或历史记录。SenseVoice 快照识别、本地流式和在线流式分别作为 Provider 内部策略，上层不得暴露 fast/correction/WAV/WebSocket 等实现细节。

**Tech Stack:** Swift 6.2、AppKit、Swift Concurrency actor、AsyncStream、现有 sherpa-onnx/SenseVoice bridge、现有 TypeWhale 手工 Swift 检查脚本与 `native/build_and_log.sh`。

## Global Constraints

- 旧胶囊、旧实时预览、完整录音 final ASR、Smart Rewrite、翻译、粘贴、历史和 OpenClaw 主路径在阶段 0–7 中保持唯一生产权威。
- 影子链路不得调用 `finishRecording`、修改 `activeSession`、修改 `SpeechSession.committedPreviewText/latestPreviewText`、提交 `RecordingTask`、写 PasteCoordinator 或改变 VAD/自动结束决策。
- 影子链路默认关闭；仅在独立“旁路预览（实验）”开关开启时创建，关闭后不得保留音频订阅、Timer、Task、文件或窗口。
- 影子链路失败必须 fail-open：旧链路继续工作；影子胶囊显示可诊断的降级状态或隐藏，不得阻塞录音和 final。
- 单个转录会话任一时刻只有一个 active Provider 可以产生权威新链路事件；Provider 切换通过 `providerEpoch` 隔离旧回调。
- Core 不依赖 AppKit、`RecordingPanel`、`RecordingCapsuleView`、主窗口或 `SpeechInputCoordinator`。
- `TranscriptEvent`、`TranscriptSegment`、`TranscriptState`、配置、错误和 ViewState 必须是不可变 `Sendable` 值。
- 单 Session 事件使用单调递增 `sequence`；不同 Session 不承诺全局顺序。
- `states()` 是可合并最新状态，多订阅者各有独立 bounded newest buffer；`events()` 是语义事件流，不得由 UI 消费速度阻塞 Session actor。
- SenseVoice 的 fast/correction、音频快照和边界校正只允许存在于 `SenseVoiceSnapshotProvider` 内部，不得成为公共 SDK 事件。
- 在线流式 Provider 使用连续 PCM 和长连接语义，不得被强制写 WAV；真实服务接入必须经过独立隐私、鉴权、成本和失败恢复评审。
- ASR/VAD 模型保持热加载；不得恢复空闲定时卸载。高内存释放仍只允许空闲且超过动态阈值时 flush 后立即 warmUp。
- 每个代码任务先写失败测试，再实现，再跑聚焦测试；代码变更完成后必须执行 `./native/build_and_log.sh`、覆盖安装 `/Applications/TypeWhale.app` 并验证真实安装版。
- UI/动效任务完成后必须使用 `design-review` skill，并检查双胶囊位置、节奏、闪烁、跳变、上下文保持及关闭恢复。
- 每次写入、构建、安装、stage 或 commit 前重新执行分支、dirty 状态、构建进程和相关文件 mtime 检查；发现并发立即降级只读。
- 每完成一个 Stage，只允许在该 Stage Exit Gate 全部通过后进入下一 Stage；不得用“后面再补”跨越门禁。
- 每个 Task 开始前必须重新读取本文档的 Global Constraints、当前 Stage 和当前 Task；不得依赖聊天记忆直接继续开发。
- 每个 Task 完成后必须立即更新本文档：勾选已完成步骤，并在 Execution Progress 中记录提交、测试证据、未验证风险和下一 Task；计划进度未更新前不得开始下一 Task。
- 实施中若证据要求改变接口、顺序或范围，必须先修改本文档并说明理由，再执行偏离项；不得事后补写计划来合理化已经完成的代码。

---

## Product Contract And Acceptance

### In Scope

- 新建统一 Realtime Transcription Core 的事件、状态、Session、Provider 和多订阅边界。
- 新建独立影子胶囊，与旧胶囊并排显示；旧胶囊保持原位置和原行为。
- 首阶段通过 Legacy Event Adapter 把现有预览状态投影到新核心，先验证状态/展示边界，不增加第二次 ASR 推理。
- 后续把现有 SenseVoice 快照/校正算法迁入独立 Provider，在受控实验开关下运行真正的新旁路识别。
- 建立对照诊断：首字延迟、修订次数、稳定边界、失败、积压、资源耗时和旧/新文本差异。
- 用 Fake Streaming Provider 证明本地/在线流式事件可以接入而无需修改胶囊和通用 Reducer。

### Out Of Scope Until A Separate Approved Stage

- 影子结果参与最终粘贴、Smart Rewrite、翻译、历史或 OpenClaw 请求。
- 默认启用在线模型、发送用户音频到网络、保存 API Key 或产生网络费用。
- 删除旧胶囊、旧预览状态字段或旧 SenseVoice 生产链路。
- 用影子结果替代完整录音 final ASR。
- 同时运行多个 active Provider 竞争同一 Transcript 权威。
- 借本计划全面重写 `SpeechInputCoordinator`、`AudioRecorder` 或整个 App 架构。

### Observable Acceptance

1. 关闭“旁路预览（实验）”后，只出现旧胶囊，录音、停止、final、整理和粘贴与当前安装版一致。
2. 开启后，旧胶囊位置和行为不变；新胶囊稳定出现在其旁边，带明确“旁路”视觉标识，不会遮挡菜单栏、刘海或旧胶囊。
3. 新胶囊可以显示 stable（已确认）和 volatile（可修订）文本；修订只发生在 volatile 区，稳定区不得倒退或改写。
4. 影子链路超时、Provider 失败、窗口关闭或取消时，旧胶囊、录音和最终粘贴不受影响。
5. 连续开始两轮录音时，上一轮任何晚到事件都不能更新新一轮影子胶囊。
6. Fake Streaming Provider 能连续发出 partial/finalized/completed；无需修改 Presenter 或 TranscriptReducer。
7. SenseVoice Shadow Provider 的 correction 队列有明确容量和合并/降级规则；测试能证明不会无界增长。
8. 20 秒、2 分钟和 10 分钟测试均记录旧/新首字延迟、最大积压、修订次数和 CPU/内存观测；在没有容量证据前不得启用一小时/多小时产品承诺。

## Execution Progress

| Stage / Task | Status | Commit | Verification | Residual risk / Next action |
| --- | --- | --- | --- | --- |
| Stage 0 / Task 0 | COMPLETE | `a50c209` | 五项预览基线通过；安装版 `2.0.6 (673)` 签名有效；用户确认 20 秒与 2 分钟真实录音全部正常 | 进入 Stage 1 / Task 1；旧胶囊与 final 主路径作为不可退化基线 |
| Stage 1 / Task 1 | COMPLETE | `3856bcc` | RED 因新 Domain 类型缺失失败；GREEN `TranscriptReducerCheck passed`；旧 `PreviewDisplaySnapshotCheck passed`；安装版 `2.0.6 (674)` 构建、签名、运行通过 | 新 Domain 尚未接生产链路；下一步开始 Task 2 有界 ViewState |
| Stage 1 / Task 2 | COMPLETE | `3b475b9` | RED 因 Projector/ViewState 缺失失败；GREEN `PreviewStateProjectorCheck passed`；Task 1 回归通过；安装版 `2.0.6 (675)` 构建、签名、运行通过 | 新 ViewState 尚未接 UI；Stage 1 Exit Gate 达成，下一步 Stage 2 / Task 3 |
| Stage 2 / Task 3 | COMPLETE | `6246356` | 有效 RED 因 Provider/Session 类型缺失失败；GREEN `TranscriptionSessionCheck passed`；Reducer/Projector 回归通过；完整版本 `2.0.7 (676)` 构建、签名、运行通过 | Session 内临时 stream 将在 Task 4 抽成明确溢出语义的 Broadcaster；下一步 Task 4 |
| Stage 2 / Task 4 | COMPLETE | `a3f4d4c` | RED 因 Broadcaster 缺失失败；GREEN `TranscriptionBroadcasterCheck passed`；Session/Projector 回归通过；安装版 `2.0.7 (677)` 构建、签名、运行通过 | Stage 2 Exit Gate 达成；下一步 Stage 3 / Task 5 影子胶囊 UI，必须执行 design-review |
| Stage 3 / Task 5 | COMPLETE | `b63e4d9`, `fb08428`, `9d0884f` | Layout/Presenter 编译通过；真实 AppKit Retina 截图；F001/F002 原子修正复核；完整版本 `2.0.8 (679)` 构建、签名、运行通过 | 静态 UI 通过；真实双胶囊相对位置、revision 闪烁和出现/隐藏节奏留给 Task 6 安装版复核 |
| Stage 3 / Task 6 | COMPLETE | `7f143bc`, `dc0fa37` | RED/GREEN 完成；Isolation/Lifecycle/Session 回归通过；安装版 `2.0.8 (680)` 构建签名通过；老板确认设置项、默认关闭、提示文案、开关持久化与旧录音/粘贴全部正常 | Stage 3 Exit Gate 达成；进入 Stage 4 / Task 7，以既有预览结果驱动双胶囊且不增加 ASR 推理 |
| Stage 4 / Task 7 | COMPLETE | `28e674c`, `6b1db53` | Adapter/Isolation/Session/Lifecycle 检查通过；安装版 `2.0.8 (681)` 构建签名通过；日志记录 16.3s/44.0s/96.8s 会话，首字 3909/1849/1339ms；老板确认双胶囊、修订、清理与旧 final 全部正常 | Stage 4 Exit Gate 达成；录音中途才重新开启旁路不会热加入当前会话，老板接受为 start-only 实验生命周期；进入 Task 8 流式兼容证明 |
| Stage 5 / Task 8 | COMPLETE | `63e8ba9` | Fake Provider/注入边界/Isolation/Session 检查通过；完整版本 `2.0.9 (682)` 构建签名通过；老板确认旧胶囊真实识别与旁路固定流式脚本互不干扰 | Fake 参数首次被普通启动覆盖，证据确认后重新以参数启动验收通过；现已恢复无参数正常启动，Stage 5 Gate 达成，进入 Task 9 |
| Stage 6 / Task 9 | COMPLETE | `6d6c132`, `b300348`, `f8abd3b` | Build 690 构建安装签名通过；46.3s、120.1s、94.5s 真实录音用户均确认流畅；fast/correction≤1、service≤96ms；10 分钟 6000 帧合成检查缓冲≤8s 且终态资源归零；design-review 无新增问题 | Stage 6 Exit Gate 达成；RSS 峰值 2.68GB 保留为 Native 工作集观察项，不外推一小时承诺；下一步 Task 11 两阶段 final chunk 安全 |
| Stage 6 prerequisite / Task 10 | COMPLETE | `a3180d1` | FanOut/Recorder source/Isolation 检查通过；首次 Build 683 编译发现 weak-self 错误并修正；安装版 `2.0.9 (684)` 构建签名通过；老板确认正常录音、取消恢复、连续录音和输入路由全部正常 | Task 10 Gate 达成；按顺序修正返回 Task 9 Step 3，开始真实 SenseVoice Shadow Provider 接入 |
| Stage 7 / Task 11 | COMPLETE | `f3f921e` | RED 复现提前推进/释放；状态机、失败注入集成门禁、FanOut/Isolation 回归通过；Build 692 构建安装签名有效；用户确认录音、停顿、final/粘贴、取消恢复、下一轮无残留 | Stage 7 Exit Gate 达成；日志多轮 16–35s final 正常且 `final_chunk_*_failed=0`；下一步 Stage 8 / Task 12 在线 Provider readiness 决策 |
| Stage 8 / Task 12 + 12A | COMPLETE — SHADOW-ONLY DECISION RESTORED | `ccbbc95`, `386feb9` | MiMo 真实鉴权/计费证据保持；通用连续 PCM Provider 的 ordered `finalized -> completed`、单次 disconnect、late/cancel 终态回归通过；安装版 `2.0.19 (715)` 构建、签名、运行通过 | 仍只批准旁路；MiMo 仍是“完整快照输入 + 流式文本响应”，不授权生产切换或长录音声明 |
| Stage 9A / Task 13A | BUILD 749 INSTALLED — CANDIDATE MOTION TUNED, REAL GATES STILL MISSING | `12ac12e`、`f1874f6`、`ce7b903`、`9cb81c4`、`e1a56e2`、`be9a8b3`、`f398982`、`d4b2a74`、`c4c314a`、`5512704`、`a201956`、`3c287a`、`e771265`、`12d0def`、`2e46030` + Build 745 test-gate sync + `f35c414` Build 746 P0 fix + `9fcf23b` Build 747 startup guard + Build 748 diagnostic gate + installed log gate + Build 749 candidate motion tuning | Build 742/743 的 final 空/异常短问题已由 Build 744 的 empty/shortfall fallback 收口；Build 744 安装版真实 120.126s 本地 fallback 录音复核通过：候选到 `target_chars=790 displayed_chars=790`，final ASR `chars=761 engine=sensevoice-small/sherpa-native`，`paste_finish outcome=restored`，用户确认“可以了”。Build 745 不改产品逻辑，补齐自动化 Stage 9A 边界证据。随后用户反馈 Build 745“基本不能用了”；日志确认异常从 `voice_processing=true` 开始，连续 `audio_route_configuration_recovered target=default:108`，无 `realtime_preview_update`，旁路 `accepted_frames=0`，最终 `recording_finish_empty`。根因定位为 Apple Voice Processing 引发 AVAudioEngine configuration change 循环，恢复逻辑又按 voice processing 重建 engine，导致整轮录音 0 帧。Build 746 源码修复：`AudioRecorder` 在 configuration recovery 中本轮自动降级 voice processing，使用普通麦克风采集继续录音，并记录 `voice_processing_auto_disabled reason=configuration_change`；聚焦门禁通过：AudioRecorderConfigurationRecoveryBoundary、AudioRecorderHotSwitchBoundary、AudioRecorderFanOutSource、AudioRecorderFinalization、`git diff --check`；唯一入口完成 `2.0.29 (746)` 完整版本构建、覆盖安装、打开和签名校验。Build 746 真实日志进一步确认恢复中降级仍会造成 `recorder_start_ms=784/839` 与首段约 1.7s 延迟，用户反馈启动慢并丢开头字；Build 747 源码新增启动前稳定性守卫：系统默认输入下若用户开启语音增强，本次录音直接跳过 Apple Voice Processing，记录 `voice_processing_skipped reason=stability_guard target=system_default`，避免先踩不稳定路径再恢复；老板真实复核确认“现在可以了”。Build 748 不改变产品行为，新增 `recording_cancel_requested` 与 `shadow_preview_teardown` 诊断，让关闭/取消真实门槛可从安装版日志审计；追加 `Stage9AInstalledLogGateCheck.py` 作为只读安装版日志门禁，并在 `docs/SHADOW_PREVIEW_QA.md` 固化 Case A 单胶囊与 Case B 取消恢复的操作/日志 PASS 口径。Build 749 只优化候选旁路 Presentation 层：`CandidateTextMotion` 动画欠账从 24 字收紧到 12 字，保留逐字展示但减少长文本尾部追赶时间；不改变 ASR、Provider、旧胶囊、final ASR 或粘贴权威。 | Build 747 日志证据：系统默认输入均出现 `voice_processing_skipped reason=stability_guard target=system_default`，`recorder_start_ms=163/190`，首个 realtime tick 在 `elapsed_ms=444/447`，无连续 `audio_route_configuration_recovered`；旁路 `accepted_frames=28/78`，final ASR `chars=12/37`，`paste_finish outcome=restored`。Build 748 聚焦回归通过：Stage9AManualGateBoundary、ShadowPreviewIsolation、ThreeCapsuleWiring、CandidatePreviewRenderBoundary、AudioRecorderConfigurationRecovery、AudioRecorderFinalization、`git diff --check`。唯一入口完成 `2.0.29 (748)` build-only 覆盖安装、打开和签名校验；安装版 Info.plist 为 `2.0.29/748`，日志 `2.0.29-748.log` 显示 app 启动、hotkey listening 与 warmup 正常。Build 749 聚焦验证通过：CandidateTextMotion、CandidateContentProjection、CandidatePresentationModel、CandidatePreviewLifecycle、CandidatePreviewRenderBoundary、`git diff --check`；唯一入口完成 `2.0.30 (749)` 完整版本构建、覆盖安装、打开和 deep/strict 签名校验，安装版 Info.plist 为 `2.0.30/749`。构建后复跑 CandidateTextMotion 与 CandidatePreviewRenderBoundary 通过。`Stage9AInstalledLogGateCheck.py` 仍输出 `MISSING single_capsule` 与 `MISSING cancel_recovery`。Stage 9A 仍需补齐关闭候选/旁路后的单胶囊路径与取消恢复真实验收；真实操作后必须跑 `native/Tests/Stage9AInstalledLogGateCheck.py --require-complete` 通过，才允许进入 Stage 9B 或宣称 Stage 9A 完成；不得宣称长录音已根治 |
| Stage 9A / Rollback to Build 749 behavior | BUILD 755 INSTALLED — CODE BEHAVIOR BACK TO 749 | Build 755 rollback to 749 behavior | 用户要求“代码退回到 749”。本轮采用非破坏性 revert，撤销 Build 750–754 的后续行为提交，不使用 `git reset --hard`。回滚后主胶囊不再由候选产品流接管，`原：` 对照方案和默认预览缓存 final 也被撤销；保留 Build 749 的候选旁路出字节奏优化和当时的 ASR/Provider/旧胶囊/final/paste 边界。 | 版本号不随代码行为回退，避免重复 Build 750；唯一入口完成 `2.0.32 (755)` build-only 覆盖安装、打开和 deep/strict 签名校验，安装后 Info.plist 为 `2.0.32/755`。复跑 CandidatePreviewRenderBoundary、ShadowPreviewIsolation、ThreeCapsuleWiring、Stage9AManualGateBoundary、LocalSenseVoiceShadowRouting、OnlineASRShadowIsolation、CandidateTextMotion、CandidateContentProjection、CandidatePresentationModel、FinalRecognitionUseCase 与 `git diff --check` 通过。下一步由用户真实观察 749 行为是否回到预期；Stage 9A 仍未关闭，不能宣称长录音完成 |
| Stage 9A / Upgrade to Build 750 behavior | BUILD 756 INSTALLED — PREVIEW CACHE DEFAULT ONLY | Build 756 upgrade to 750 behavior | 用户要求“再升级到 750”。本轮只恢复 Build 750 的最终文本权威切换：新增“停止后重新识别整段录音”开关，默认关闭；默认最终文本改为停止时完整实时预览缓存，开关开启或预览缓存无效时才跑完整录音 final ASR。明确不恢复 Build 751/753 的主胶囊候选流接管、`原：` 对照方案或 Build 754 当前 build 日志门禁收紧。 | 唯一入口完成 `2.0.33 (756)` 完整版本构建、覆盖安装、打开和 deep/strict 签名校验，安装后 Info.plist 为 `2.0.33/756`。复跑 FinalRecognitionUseCase、FinalRecognitionPreviewCacheDefault、CandidatePreviewRenderBoundary、ShadowPreviewIsolation、ThreeCapsuleWiring、Stage9AManualGateBoundary 与 `git diff --check` 通过。Stage 9A 仍未关闭，不能宣称长录音完成 |
| Stage 9A / Candidate delivery cache for final paste | BUILD 757 INSTALLED — CANDIDATE CACHE FINAL DEFAULT | 本轮待提交 | 用户确认最终粘贴策略：停止录音时先让候选 runtime 完成收尾，从候选状态取 finalized/stable 文本并追加 volatile 尾巴；候选缓存有效且不短于默认预览缓存时作为最终文本；候选没启动、失败、为空、短得异常时直接 fallback 到完整 final ASR，不再使用默认预览缓存作为最终兜底。 | 已新增 `CandidateDeliverySnapshot` 与 `ShadowTranscriptionRuntime.completeForDelivery()`，`SpeechInputCoordinator` 在 final 前完成候选 runtime 并把候选交付文本传入 `FinalRecognitionUseCase`；`FinalRecognitionUseCase` 只在候选缓存通过有效性判断时返回 `candidate-preview-cache`，否则调用完整 final ASR。RED/GREEN 与构建后回归已通过 FinalRecognitionUseCase、CandidateDeliverySnapshot、FinalRecognitionPreviewCacheDefault、CandidatePreviewRenderBoundary、ShadowPreviewIsolation、ThreeCapsuleWiring、TranscriptionSession、TranscriptionBroadcaster、OnlineASRShadowIsolation、LocalSenseVoiceShadowRouting 与 `git diff --check`；唯一入口完成 `2.0.33 (757)` build-only 覆盖安装、打开和 codesign deep/strict 校验，安装后 Info.plist 为 `2.0.33/757`。仍需用户真实录音确认日志出现 `candidate_delivery_cache` 与 `final_asr_result source=candidate_preview_cache/final_asr`；Stage 9A 仍未关闭，不能宣称长录音完成 |
| Stage 9A / Candidate stop flush before delivery | BUILD 758 INSTALLED — SUPERSEDED BY TERMINAL-GATED DELIVERY | 本轮待提交 | 用户批准先解决最后丢字且不用完整 final：停止录音时候选 runtime 先做短 flush，让 provider.finish 之后异步到达的尾部 partial/completed 进入状态，再取候选交付缓存。用户随后指出固定等待不严谨，因此该实现被下一行 completed 终态驱动策略接续收紧。 | `ShadowTranscriptionRuntime.completeForDelivery()` 增加有界等待；新增 `CandidateDeliverySnapshotCheck` 延迟尾巴 provider，证明 `finish()` 返回后 50ms 才吐出的最后文本会被交付缓存捕获。唯一入口完成 `2.0.33 (758)` build-only 覆盖安装、打开和 codesign deep/strict 校验；安装后 Info.plist 为 `2.0.33/758`。该构建只作为第一层 flush 证据，不作为最终严谨方案 |
| Stage 9A / Terminal-gated candidate delivery | BUILD 759 INSTALLED — COMPLETED-GATED DELIVERY | 本轮待提交 | 用户要求一步做到位并指出固定 800ms 不严谨。本轮把候选交付条件改为 completed 终态驱动：保护上限只防卡死，不能作为取文本依据；候选必须 lifecycle `.completed` 且文本有效才允许交付，否则 fallback 完整 final ASR。 | `CandidateDeliverySnapshot.isDeliverable` 要求 completed + meaningful；`SpeechInputCoordinator` 只有 `deliverable=true` 才传入候选文本，日志记录 `usable/deliverable/lifecycle`。`completeForDelivery` 默认安全上限调为约 2s，但语义是等待 completed 的保护上限。已通过 CandidateDeliverySnapshot hanging provider、FinalRecognitionUseCase、FinalRecognitionPreviewCacheDefault、CandidatePreviewRenderBoundary、ShadowPreviewIsolation、ThreeCapsuleWiring、OnlineASRShadowIsolation、LocalSenseVoiceShadowRouting 与 `git diff --check`；唯一入口完成 `2.0.34 (759)` 完整版本构建、覆盖安装、打开和 codesign deep/strict 校验，安装后 Info.plist 为 `2.0.34/759`。仍需真实录音验证最后尾字与日志；Stage 9A 仍未关闭，不能宣称长录音完成 |
| Stage 9A / Candidate final delivery source correction | BUILD 760 INSTALLED — REAL RUNTIME FIRST | 本轮待提交 | Build 759 真实日志确认本地 fallback 仍丢末尾。根因是最终交付优先取 legacy `candidatePreviewRuntime`，而不是吃音频帧的真实 `shadowPreviewRuntime`；同时收尾前 cancel 音频帧投递可能掐掉最后几帧。本轮目标是不将就：候选 UI runtime 继续只做展示，最终交付源必须来自真实旁路 runtime；真实 runtime 不 completed/无效时 fallback 完整 final ASR，不拿 UI 缓存兜底。 | 已新增 `CandidateDeliverySourceSelectionCheck` 锁定真实 runtime 优先于 legacy adapter，新增 `CandidateFinalDeliveryBoundaryCheck.sh` 防止收尾前 cancel 音频投递；`candidate_delivery_cache` 增加 `source`。唯一入口完成 `2.0.34 (760)` build-only 覆盖安装、打开和 codesign deep/strict 校验，安装版 Info.plist 确认为 `2.0.34/760`，进程已运行。构建前后通过 CandidateDeliverySourceSelection、CandidateDeliverySnapshot、CandidateFinalDeliveryBoundary、FinalRecognitionUseCase、FinalRecognitionPreviewCacheDefault、CandidatePreviewRenderBoundary、ShadowPreviewIsolation、ThreeCapsuleWiring、OnlineASRShadowIsolation、LocalSenseVoiceShadowRouting 与 `git diff --check`。安装后 8.692s 真实本地 fallback 样本 `1E90F15C` 显示 `had_audio_subscription=true`、`candidate_delivery_cache source=shadow-runtime-cache deliverable=true lifecycle=completed`，证明最终交付源已扶正；但该样本候选 18 字、完整 final ASR 35 字，因此安全策略正确 fallback 到 `source=final_asr`。下一步需要继续验证/优化真实 SenseVoice shadow runtime 覆盖率，直到候选本身足够完整；Stage 9A 仍未关闭，不能宣称长录音完成 |
| Stage 9A / SenseVoice finish tail snapshot | BUILD 761 INSTALLED — STOP-TIME TAIL COVERAGE | 本轮待提交 | Build 760 真实日志进一步证明真实 `shadow-runtime-cache` 来源已扶正，但 SenseVoice shadow runtime 在停止点前最后一次识别可能早于录音结束，导致 completed 只代表旧队列 drained，不代表尾部音频被识别。本轮目标是在 provider 空闲的停止瞬间强制补一次 final tail snapshot，让 completed 更接近“覆盖到停止点”。 | RED `finishEnqueuesTailSnapshotBeforeCompleting` 复现停止前未触发周期识别导致 final state 为空；GREEN 在 `SenseVoiceSnapshotProvider.finish()` 中仅当 `recognitionTask == nil && scheduler.isIdle` 时插入 final tail correction snapshot，避免与慢识别重叠造成重复文本。唯一入口完成 `2.0.34 (761)` build-only 覆盖安装、打开和 codesign deep/strict 校验，安装版 Info.plist 确认为 `2.0.34/761`，进程已运行。构建前通过 SenseVoiceSnapshotProvider、CandidateDeliverySourceSelection、CandidateDeliverySnapshot、CandidateFinalDeliveryBoundary、FinalRecognitionUseCase、FinalRecognitionPreviewCacheDefault、CandidatePreviewRenderBoundary、ShadowPreviewIsolation、ThreeCapsuleWiring、OnlineASRShadowIsolation、LocalSenseVoiceShadowRouting 与 `git diff --check`；构建后复跑 SenseVoiceSnapshotProvider、CandidateDeliverySourceSelection、CandidateFinalDeliveryBoundary 与 `git diff --check` 通过。下一步需要真实录音比较候选/最终字数和 `candidate_delivery_cache source=shadow-runtime-cache`；Stage 9A 仍未关闭，不能宣称长录音完成 |
| Stage 9A / Stop-time SenseVoice tail admission | BUILD 762 INSTALLED — FINAL TAIL ADMITTED | 本轮待提交 | Build 761 真实日志显示 final tail snapshot 仍未改善候选长度，并出现 `admission_skipped=2`。根因是准入条件要求 `recorder.isRecording`，但 final tail snapshot 在 `recorder.stop()` 之后运行，被停止后的录音状态挡掉。本轮目标是只放行停止后的 SenseVoice 收尾识别，录音中节流保持不变。 | GREEN 修改 `canAdmitSenseVoiceShadowRecognition()`：当 recorder 已停止时直接允许 shadow final tail；录音中仍检查 `realtimeBusy`、pending snapshots 和最近 production preview 完成时间。`CandidateFinalDeliveryBoundaryCheck.sh` 新增 stop-time admission 边界；回归通过 SenseVoiceSnapshotProvider、CandidateDeliverySourceSelection、CandidateFinalDeliveryBoundary、FinalRecognitionPreviewCacheDefault、CandidatePreviewRenderBoundary、ShadowPreviewIsolation、ThreeCapsuleWiring、OnlineASRShadowIsolation、LocalSenseVoiceShadowRouting 与 `git diff --check`。唯一入口完成完整版本构建 `2.0.35 (762)`、覆盖安装、打开和 codesign deep/strict 校验；安装版 Info.plist 确认为 `2.0.35/762`，构建后复跑 SenseVoiceSnapshotProvider、CandidateDeliverySourceSelection、CandidateFinalDeliveryBoundary 与 `git diff --check` 通过。下一步真实录音验证候选是否追到停止点；Stage 9A 仍未关闭，不能宣称长录音完成 |

### 2026-07-11 Evidence-Driven Execution Order Amendment

- 证据：Task 9 的 Provider 公共输入是连续 `AudioFrame`，而当前 `AudioRecorder` 只向旧链路公开 WAV 快照；计划原顺序要求 Task 9 先实机接入、Task 10 后提供 PCM fan-out，形成依赖倒置。
- 被拒绝方案：让新旧链路共享或复制临时 WAV。该方案会引入删除/所有权竞态、额外磁盘 I/O，并使影子链路可能干扰旧预览，不符合 fail-open 与“在线 Provider 不强制 WAV”约束。
- 修正顺序：完成 Task 9 Step 1–2 的纯调度与边界算法后，提前执行原 Task 10 的单向有界 PCM fan-out；Task 10 Gate 通过后返回 Task 9 Step 3–5，最后再执行 Task 11。
- 范围不变：Task 编号、文件、验收和旧链路权威均保持；只调整依赖顺序。Task 10 不因此获得修改 Provider、胶囊、final 或粘贴的权限。

### 2026-07-14 Evidence Truth Reset

- 候选胶囊不降级为无效实验。`CandidateContentProjection` / `CandidateTextMotion` / `CandidatePresentationModel` 是目标架构的正式 Presentation 层，应保留并继续验证。
- 展示层完成不等于整套转录架构完成。关闭在线 Provider 或缺 Key 时，当前 runtime 通过 `LegacyPreviewShadowAdapter` 消费旧生产 `PreviewDisplaySnapshot`；因此候选内容与原预览同源是当前实现事实，不得描述为独立本地识别链。
- 本计划 Global Constraints 明确保留完整录音 final ASR，当前产品又有 120 秒录音硬上限。因此 Stages 0–9A 只能证明旁路迁移、Provider 兼容、有界资源和候选展示，不得用来宣称“长录音已解决”。
- 2026-07-14 只读审计重跑了 Reducer、Projector、Session、Broadcaster、SenseVoice Provider、final-chunk 源码门禁、Candidate Model/Matrix 和 Shadow/Online/Wiring 边界检查，均通过；这些证据不替代 Build 714 真实动态验收。
- 10 分钟现有证据是 6000×100ms 等量合成 PCM + stub/fixture，只证明 Provider 缓冲、队列与终态清理有界；不证明真实墙钟 10 分钟、真实模型/网络、CPU/RSS 或 UI 稳定。

### 2026-07-17 Candidate Display Root-Cause Amendment

- 真实 Build 739 验收失败：用户反馈 2 分钟明显丢字，且候选胶囊“压根没有正常展示内容”。日志显示 120 秒录音文件完整保存；旧实时预览在同一会话中增长到约 464 字，但 `candidate_preview_render` 从 sequence 11 起长期停在 `target_chars=160`。
- 根因 1：候选胶囊与技术旁路胶囊共用 `ShadowTranscriptionRuntime.states()`，该方法无条件执行 `PreviewStateProjector.project(state)`，默认只暴露 160 字尾部窗口。该 160 字窗口适合小技术胶囊，不适合候选胶囊的“未来效果/长文本候选”目标。
- 根因 2：`CandidateTextMotion` 当前把 `visibleCharacterCount` 直接设置为 `targetCharacterCount`，并让 `advance()` 永远结束，导致候选“按字展示”的 Presentation 目标在实现上被关闭。
- 修正方向：保持 Core 与 UI 分层，不让候选视图处理 Provider 或数据修补；在 `ShadowTranscriptionRuntime` 暴露候选专用长文本投影参数，技术旁路继续使用 160 字窗口，候选使用更大的候选窗口；恢复 `CandidateTextMotion` 的字符级推进，但修订/缩短时不从头重播。
- Stage 9A 不关闭；本修正完成并安装后，必须重新执行候选开启/关闭、本地 fallback、20 秒和 2 分钟真实录音验收。2 分钟 final ASR 104 字的问题作为独立 final 长音频路径风险继续记录，不能用候选修复替代 final 修复。

## Source-Of-Truth And File Map

### Existing Sources To Preserve

- `docs/ARCHITECTURE.md`: 当前 TypeWhale 架构与生产不变量的上位来源。
- `docs/PREVIEW_ARCHITECTURE_COMMUNICATION_LOG.md`: 预览历史决定、三 Provider、SDK、多线程和迁移原则的证据来源。
- `native/Sources/Application/SpeechInputCoordinator.swift`: 旧主路径协调器；迁移期间只增加窄适配器调用，不继续塞入新状态机。
- `native/Sources/Application/RealtimePreview/ExperimentalRealtimePreviewPipeline.swift`: 现有 SenseVoice 实验实现；迁移证据源，不作为新公共接口。
- `native/Sources/Domain/RealtimePreview/PreviewDisplaySnapshot.swift`: 已验证的 stable/volatile 展示思想；新 ViewState 应吸收而不是复制两套语义。
- `native/Sources/Presentation/Capsule/RecordingPanel.swift`: 旧胶囊生产 Presenter，迁移期间保持行为不变。

### New Core Files

- `native/Sources/Domain/RealtimeTranscription/TranscriptionIdentity.swift`: Session、Provider epoch、sequence 和 Segment 身份。
- `native/Sources/Domain/RealtimeTranscription/TranscriptionEvent.swift`: 公共语义事件；不包含 fast/correction/WAV/WebSocket。
- `native/Sources/Domain/RealtimeTranscription/TranscriptState.swift`: 唯一权威转录状态值。
- `native/Sources/Domain/RealtimeTranscription/TranscriptReducer.swift`: 纯状态归约、stale gate、幂等和稳定区规则。
- `native/Sources/Domain/RealtimeTranscription/PreviewViewState.swift`: UI 可消费的有界快照，携带身份与 revision。
- `native/Sources/Application/RealtimeTranscription/TranscriptionProvider.swift`: Provider 能力、输入和事件协议。
- `native/Sources/Application/RealtimeTranscription/TranscriptionSession.swift`: 独立 actor，顺序处理 start/append/finish/cancel/switchProvider。
- `native/Sources/Application/RealtimeTranscription/TranscriptionBroadcaster.swift`: 每订阅者独立 AsyncStream 与 bounded buffer。
- `native/Sources/Application/RealtimeTranscription/PreviewStateProjector.swift`: `TranscriptState -> PreviewViewState` 唯一映射。
- `native/Sources/Application/RealtimeTranscription/LegacyPreviewShadowAdapter.swift`: 将旧预览结果转为统一事件；阶段 1–4 使用。
- `native/Sources/Infrastructure/RealtimeTranscription/SenseVoiceSnapshotProvider.swift`: 迁移后的非流式 Provider。
- `native/Sources/Infrastructure/RealtimeTranscription/FakeStreamingProvider.swift`: 确认流式兼容性的确定性测试 Provider。
- `native/Sources/Infrastructure/RealtimeTranscription/OnlineStreamingProviderPort.swift`: 在线 Provider 连接/音频端口契约；本计划不接真实服务。

### New Presentation Files

- `native/Sources/Presentation/ShadowPreview/ShadowPreviewPresenter.swift`: 影子胶囊 Presenter，不复用旧窗口实例。
- `native/Sources/Presentation/ShadowPreview/ShadowPreviewView.swift`: 只绘制影子 ViewState，不决定 Transcript 真相。
- `native/Sources/Presentation/ShadowPreview/ShadowPreviewLayout.swift`: 根据旧胶囊 frame 和屏幕安全区计算旁路位置。
- `native/Sources/Presentation/ShadowPreview/ShadowPreviewCoordinator.swift`: 订阅 states、切主线程更新、生命周期清理。
- `native/Sources/Infrastructure/Settings/ShadowPreviewSettings.swift`: 独立默认关闭实验设置。

### New Tests

- `native/Tests/TranscriptReducerCheck.swift`
- `native/Tests/TranscriptionSessionCheck.swift`
- `native/Tests/TranscriptionBroadcasterCheck.swift`
- `native/Tests/PreviewStateProjectorCheck.swift`
- `native/Tests/ShadowPreviewIsolationCheck.sh`
- `native/Tests/ShadowPreviewLayoutCheck.swift`
- `native/Tests/FakeStreamingProviderCheck.swift`
- `native/Tests/SenseVoiceShadowSchedulerCheck.swift`
- `native/Tests/ShadowPreviewLifecycleCheck.swift`

---

## Stage 0 — Baseline Freeze And Safety Harness

### Task 0: Record The Existing Production Baseline

**Files:**
- Modify: `docs/开发日志.md`
- Create: `docs/SHADOW_PREVIEW_QA.md`
- Test: existing preview checks under `native/Tests/`

**Interfaces:**
- Consumes: current installed TypeWhale behavior and diagnostics.
- Produces: a reproducible old-capsule baseline and manual QA gate used by every later stage.

- [ ] **Step 1: Re-run concurrency protection**

Run:

```bash
git branch --show-current
git status --short
pgrep -af 'build_and_log\.sh|release_local_build\.sh|build_native_app\.sh|swiftc|xcodebuild' || true
```

Expected: branch is `codex/typewhale-pro-asr-hotwords`; no unexplained dirty overlap; no active build.

- [ ] **Step 2: Capture old-capsule behavior before changing code**

Record in `docs/SHADOW_PREVIEW_QA.md` exact observations for 20-second and 2-minute dictation:

```markdown
| Case | First visible text | Natural pause | Stop transition | Final paste | Result |
| --- | --- | --- | --- | --- | --- |
| 20s continuous | timestamp | no reset | detecting/recognizing | exact pasted text | PASS/FAIL |
| 2m mixed pauses | timestamp | prior text retained | no stale tail | exact pasted text | PASS/FAIL |
```

- [ ] **Step 3: Run existing focused checks**

Run:

```bash
swiftc -o /tmp/typewhale-preview-display-check \
  native/Sources/Domain/RealtimePreview/BoundaryCenteredPreviewPlanner.swift \
  native/Sources/Domain/RealtimePreview/PreviewDisplaySnapshot.swift \
  native/Sources/Domain/RealtimePreview/PreviewRecognitionResult.swift \
  native/Sources/Domain/RealtimePreview/PreviewTranscriptReducer.swift \
  native/Sources/Application/RealtimePreview/LongFormTranscriptionSession.swift \
  native/Tests/PreviewDisplaySnapshotCheck.swift
/tmp/typewhale-preview-display-check

swiftc -o /tmp/typewhale-preview-scheduler-check \
  native/Sources/Domain/RealtimePreview/BoundaryCenteredPreviewPlanner.swift \
  native/Sources/Domain/RealtimePreview/PreviewDisplaySnapshot.swift \
  native/Sources/Domain/RealtimePreview/PreviewRecognitionResult.swift \
  native/Sources/Application/RealtimePreview/PreviewRequestScheduler.swift \
  native/Tests/PreviewRequestSchedulerCheck.swift
/tmp/typewhale-preview-scheduler-check

swiftc -o /tmp/typewhale-preview-reducer-check \
  native/Sources/Domain/RealtimePreview/BoundaryCenteredPreviewPlanner.swift \
  native/Sources/Domain/RealtimePreview/PreviewDisplaySnapshot.swift \
  native/Sources/Domain/RealtimePreview/PreviewRecognitionResult.swift \
  native/Sources/Domain/RealtimePreview/PreviewTranscriptReducer.swift \
  native/Tests/PreviewTranscriptReducerCheck.swift
/tmp/typewhale-preview-reducer-check

swiftc -o /tmp/typewhale-capsule-snapshot-check \
  native/Sources/Presentation/Capsule/CapsuleTextBuffer.swift \
  native/Tests/CapsuleSnapshotBufferCheck.swift
/tmp/typewhale-capsule-snapshot-check

swiftc -o /tmp/typewhale-capsule-text-check \
  native/Sources/Presentation/Capsule/CapsuleTextBuffer.swift \
  native/Tests/CapsuleTextBufferCheck.swift
/tmp/typewhale-capsule-text-check
```

Expected: all commands exit 0; the first four binaries print their matching `<CheckName> passed` line, while `CapsuleTextBufferCheck` succeeds silently.

- [ ] **Step 4: Record immutable Stage 0 invariants**

Add to `docs/SHADOW_PREVIEW_QA.md`:

```markdown
## Production Protection

- Old capsule is the production display authority.
- Full-recording final ASR remains the default paste source.
- Shadow failures never change recording, VAD, finalization, paste, history, or OpenClaw.
- Disabling the experiment restores a single-capsule process with no shadow tasks or windows.
```

- [ ] **Step 5: Commit Stage 0**

```bash
git add docs/SHADOW_PREVIEW_QA.md docs/开发日志.md
git commit -m "docs: freeze shadow preview migration baseline"
```

**Stage 0 Exit Gate:** installed-app old-capsule baseline is recorded; focused existing preview checks pass; no production code changed.

---

## Stage 1 — Unified Domain Contract

### Task 1: Define Identity, Events, State And Pure Reducer

**Files:**
- Create: `native/Sources/Domain/RealtimeTranscription/TranscriptionIdentity.swift`
- Create: `native/Sources/Domain/RealtimeTranscription/TranscriptionEvent.swift`
- Create: `native/Sources/Domain/RealtimeTranscription/TranscriptState.swift`
- Create: `native/Sources/Domain/RealtimeTranscription/TranscriptReducer.swift`
- Test: `native/Tests/TranscriptReducerCheck.swift`

**Interfaces:**
- Consumes: immutable Provider events carrying `sessionID`, `providerEpoch`, `sequence` and segment identity.
- Produces: `TranscriptState` as the single new-chain authority and `TranscriptReducer.apply(_:) -> TranscriptState?`.

- [x] **Step 1: Write the failing reducer check**

The check must prove: partial replacement, finalized immutability, duplicate sequence idempotency, stale session/epoch rejection, cancel terminality and completed terminality.

```swift
let id = TranscriptionSessionID(rawValue: UUID())
var reducer = TranscriptReducer(sessionID: id, providerEpoch: 1)
precondition(reducer.apply(.partial(meta(id, 1, 1), segmentID: "s0", revision: 1, text: "今天"))?.volatileText == "今天")
precondition(reducer.apply(.partial(meta(id, 1, 2), segmentID: "s0", revision: 2, text: "今天讨论"))?.volatileText == "今天讨论")
precondition(reducer.apply(.finalized(meta(id, 1, 3), segment: segment("s0", "今天讨论")))?.confirmedText == "今天讨论")
precondition(reducer.apply(.partial(meta(id, 1, 4), segmentID: "s0", revision: 3, text: "被改写")) == nil)
precondition(reducer.apply(.partial(meta(id, 0, 5), segmentID: "s1", revision: 1, text: "旧回调")) == nil)
```

- [x] **Step 2: Compile the test and verify failure**

Run:

```bash
swiftc -parse-as-library -o /tmp/typewhale-transcript-reducer-check \
  native/Tests/TranscriptReducerCheck.swift
```

Expected: FAIL because the new domain types do not exist.

- [x] **Step 3: Implement the public domain signatures**

Use these exact public shapes inside the app target:

```swift
struct TranscriptionSessionID: Hashable, Sendable { let rawValue: UUID }
struct TranscriptionEventMetadata: Equatable, Sendable {
    let sessionID: TranscriptionSessionID
    let providerEpoch: Int
    let sequence: UInt64
    let emittedAtUptime: TimeInterval
}
enum TranscriptionEvent: Equatable, Sendable {
    case partial(TranscriptionEventMetadata, segmentID: String, revision: Int, text: String)
    case finalized(TranscriptionEventMetadata, segment: TranscriptSegment)
    case failed(TranscriptionEventMetadata, TranscriptionFailure)
    case connectionChanged(TranscriptionEventMetadata, ProviderConnectionState)
    case completed(TranscriptionEventMetadata)
    case cancelled(TranscriptionEventMetadata)
}
struct TranscriptState: Equatable, Sendable {
    let sessionID: TranscriptionSessionID
    let providerEpoch: Int
    let lastSequence: UInt64
    let confirmedSegments: [TranscriptSegment]
    let volatileSegmentID: String?
    let volatileRevision: Int
    let volatileText: String
    let lifecycle: TranscriptionLifecycle
    let failure: TranscriptionFailure?
    var confirmedText: String { confirmedSegments.map(\.text).joined() }
}
```

- [x] **Step 4: Implement strict reducer invariants**

Implementation must reject mismatched session/epoch, `sequence <= lastSequence`, partial revisions not newer than the current partial, edits to finalized segment IDs, and mutations after terminal lifecycle. It must never trim or visually animate text.

- [x] **Step 5: Run the reducer check**

Run:

```bash
swiftc -parse-as-library -o /tmp/typewhale-transcript-reducer-check \
  native/Sources/Domain/RealtimeTranscription/*.swift \
  native/Tests/TranscriptReducerCheck.swift
/tmp/typewhale-transcript-reducer-check
```

Expected: `TranscriptReducerCheck passed`.

- [x] **Step 6: Commit Task 1**

```bash
git add native/Sources/Domain/RealtimeTranscription native/Tests/TranscriptReducerCheck.swift
git commit -m "feat: add unified realtime transcript domain"
```

### Task 2: Project Transcript State Into A Bounded Preview ViewState

**Files:**
- Create: `native/Sources/Domain/RealtimeTranscription/PreviewViewState.swift`
- Create: `native/Sources/Application/RealtimeTranscription/PreviewStateProjector.swift`
- Test: `native/Tests/PreviewStateProjectorCheck.swift`

**Interfaces:**
- Consumes: `TranscriptState`.
- Produces: `PreviewStateProjector.project(_:, visibleCharacterLimit:) -> PreviewViewState`.

- [x] **Step 1: Write failing tests for identity, monotonic stable boundary and bounded window**

Require the projected type to include:

```swift
struct PreviewViewState: Equatable, Sendable {
    let sessionID: TranscriptionSessionID
    let providerEpoch: Int
    let sequence: UInt64
    let stableCharacterCount: Int
    let stableWindowText: String
    let volatileTailText: String
    let lifecycle: TranscriptionLifecycle
    let failure: TranscriptionFailure?
}
```

Test a 200-character confirmed transcript plus a 40-character tail with limit 160. Expected: total visible characters <= 160, tail receives capacity first, stable count remains the full confirmed character count.

- [x] **Step 2: Verify test failure**

Run:

```bash
swiftc -o /tmp/typewhale-preview-projector-check \
  native/Sources/Domain/RealtimeTranscription/*.swift \
  native/Sources/Application/RealtimeTranscription/PreviewStateProjector.swift \
  native/Tests/PreviewStateProjectorCheck.swift
```

Expected: FAIL because projector/ViewState are missing.

- [x] **Step 3: Implement projection without UI policy leakage**

The projector may select a visible suffix and expose stable/volatile boundaries. It must not apply fade, typewriter timing, font, layout, hallucination filtering or Provider-specific correction.

- [x] **Step 4: Run test and commit**

Expected: `PreviewStateProjectorCheck passed`.

```bash
git add native/Sources/Domain/RealtimeTranscription/PreviewViewState.swift \
  native/Sources/Application/RealtimeTranscription/PreviewStateProjector.swift \
  native/Tests/PreviewStateProjectorCheck.swift
git commit -m "feat: add bounded shadow preview projection"
```

**Stage 1 Exit Gate:** domain checks prove one authority, immutable finalized segments, stale rejection and bounded UI projection; no AppKit or existing production file depends on the new core.

---

## Stage 2 — Session Actor And Multi-Subscriber Delivery

### Task 3: Add Provider Port And Session Actor

**Files:**
- Create: `native/Sources/Application/RealtimeTranscription/TranscriptionProvider.swift`
- Create: `native/Sources/Application/RealtimeTranscription/TranscriptionSession.swift`
- Test: `native/Tests/TranscriptionSessionCheck.swift`

**Interfaces:**
- Consumes: `AudioFrame`, `TranscriptionProvider`, session commands.
- Produces: ordered state/events and idempotent lifecycle methods.

- [x] **Step 1: Write a fake Provider and failing session lifecycle test**

Test exact order:

```text
start -> append frame 1 -> append frame 2 -> finish -> completed
start -> cancel -> late partial ignored
start epoch 1 -> switchProvider -> epoch 1 callback ignored -> epoch 2 accepted
finish twice -> one provider finish and one completed state
```

- [x] **Step 2: Define Provider capabilities and input**

```swift
struct AudioFrame: Sendable {
    let samples: [Float]
    let sampleRate: Int
    let channelCount: Int
    let startFrame: Int64
}
struct TranscriptionProviderCapabilities: Equatable, Sendable {
    let supportsRealtimePCM: Bool
    let supportsPartialResults: Bool
    let supportsServerFinalization: Bool
    let maximumConcurrentSessions: Int
}
protocol TranscriptionProvider: Sendable {
    var id: String { get }
    var capabilities: TranscriptionProviderCapabilities { get }
    func start(sessionID: TranscriptionSessionID, providerEpoch: Int) async throws
    func append(_ frame: AudioFrame) async throws
    func finish() async throws
    func cancel() async
    func events() -> AsyncStream<TranscriptionEvent>
}
```

- [x] **Step 3: Implement `actor TranscriptionSession`**

Required methods:

```swift
func start() async throws
func append(_ frame: AudioFrame) async throws
func finish() async
func cancel() async
func switchProvider(to provider: any TranscriptionProvider) async throws
func currentState() -> TranscriptState
func states() async -> AsyncStream<TranscriptState>
func events() async -> AsyncStream<TranscriptionEvent>
```

Provider callbacks must enter the actor before reducer mutation. `switchProvider` increments epoch before starting the replacement and never clears confirmed segments.

- [x] **Step 4: Run focused test and commit**

Expected: `TranscriptionSessionCheck passed`.

```bash
git add native/Sources/Application/RealtimeTranscription/TranscriptionProvider.swift \
  native/Sources/Application/RealtimeTranscription/TranscriptionSession.swift \
  native/Tests/TranscriptionSessionCheck.swift
git commit -m "feat: isolate realtime transcription sessions"
```

### Task 4: Add A True Multi-Subscriber Broadcaster

**Files:**
- Create: `native/Sources/Application/RealtimeTranscription/TranscriptionBroadcaster.swift`
- Test: `native/Tests/TranscriptionBroadcasterCheck.swift`

**Interfaces:**
- Consumes: immutable events and states from `TranscriptionSession`.
- Produces: independent AsyncStream per subscriber with explicit buffering.

- [x] **Step 1: Write failing tests with fast and slow subscribers**

State subscribers use `.bufferingNewest(1)`. Event subscribers use a fixed capacity defined as `64`; overflow emits one `.failed(... .subscriberOverflow)` diagnostic to that subscriber and terminates it, without affecting Session or other subscribers.

- [x] **Step 2: Implement subscriber ownership**

Each subscription gets a UUID and its own continuation. `onTermination` removes only that subscriber. Finishing the broadcaster finishes every continuation exactly once.

- [x] **Step 3: Run check and commit**

Expected: `TranscriptionBroadcasterCheck passed`.

```bash
git add native/Sources/Application/RealtimeTranscription/TranscriptionBroadcaster.swift \
  native/Tests/TranscriptionBroadcasterCheck.swift
git commit -m "feat: add bounded transcription broadcasts"
```

**Stage 2 Exit Gate:** Thread Sanitizer-compatible tests show Session ordering, idempotent terminal commands, epoch-based stale rejection and independent subscribers. The old app still does not instantiate the new Session.

---

## Stage 3 — Shadow Capsule UI Without A Second ASR

### Task 5: Build A Separate Shadow Capsule Presenter

**Files:**
- Create: `native/Sources/Presentation/ShadowPreview/ShadowPreviewLayout.swift`
- Create: `native/Sources/Presentation/ShadowPreview/ShadowPreviewView.swift`
- Create: `native/Sources/Presentation/ShadowPreview/ShadowPreviewPresenter.swift`
- Test: `native/Tests/ShadowPreviewLayoutCheck.swift`
- Test fixture: `native/Tests/ShadowPreviewVisualFixture.swift`（仅独立编译截图，不进入 App 包）

**Interfaces:**
- Consumes: `PreviewViewState` and the current production capsule frame/screen.
- Produces: a non-activating, non-authoritative adjacent shadow panel.

- [x] **Step 1: Write failing pure layout tests**

Required placement policy:

```text
Preferred: shadow capsule centered directly below production capsule with 8pt vertical gap.
Fallback 1: place above when below crosses visibleFrame.
Fallback 2: clamp horizontally inside visibleFrame with 12pt edge inset.
Never: overlap production capsule or cross the screen safe visible frame.
```

Test normal display, top menu-bar proximity, bottom edge, left/right clamp and physical-notch screen visibleFrame.

- [x] **Step 2: Implement pure `ShadowPreviewLayout`**

```swift
struct ShadowPreviewLayout {
    static func frame(
        productionFrame: CGRect,
        shadowSize: CGSize,
        visibleFrame: CGRect,
        gap: CGFloat = 8,
        edgeInset: CGFloat = 12
    ) -> CGRect
}
```

- [x] **Step 3: Implement visually distinct but quiet presentation**

Requirements:

- non-activating `NSPanel`, ignores mouse events, never becomes key/main;
- small “旁路” badge and restrained secondary border;
- same readable typography and stable/volatile distinction as the new ViewState;
- no copy/save/cancel/stop controls;
- no use of `SpeechSession`, ASR, VAD or paste APIs;
- `apply(_ state:)`, `show(adjacentTo:)`, `hideImmediately()` are the only public mutations.

- [x] **Step 4: Run layout test, typecheck and design review**

Expected: `ShadowPreviewLayoutCheck passed`; typecheck passes. 独立编译运行 `ShadowPreviewVisualFixture`，截图真实 `NSPanel` 后调用 `design-review`，验证 hierarchy、spacing、distinction、flicker、transition 和 context retention；fixture 不得加入 `build_native_app.sh`。

`design-review` 要求 clean working tree：先完成本 Task 初始实现的构建安装并提交视觉基线检查点，再运行 review；review 发现的每个视觉修正单独提交，全部复核后才将 Task 5 标记 COMPLETE。

- [x] **Step 5: Commit Task 5**

```bash
git add native/Sources/Presentation/ShadowPreview native/Tests/ShadowPreviewLayoutCheck.swift
git commit -m "feat: add isolated shadow preview capsule"
```

### Task 6: Add Default-Off Setting And Lifecycle Coordinator

**Files:**
- Create: `native/Sources/Infrastructure/Settings/ShadowPreviewSettings.swift`
- Create: `native/Sources/Presentation/ShadowPreview/ShadowPreviewCoordinator.swift`
- Modify: `native/Sources/Presentation/Main/MainViewController.swift`
- Modify: `native/Sources/Presentation/Main/MainViewController+Configuration.swift`
- Modify: `native/Sources/Presentation/Main/MainViewController+PanelLayout.swift`
- Modify: `native/Sources/Presentation/Main/MainViewController+Actions.swift`
- Test: `native/Tests/ShadowPreviewIsolationCheck.sh`
- Test: `native/Tests/ShadowPreviewLifecycleCheck.swift`

**Interfaces:**
- Consumes: independent persisted boolean and a stream of `PreviewViewState`.
- Produces: a coordinator that creates/destroys only the shadow panel and subscription Task.

- [x] **Step 1: Write the isolation boundary test**

The shell check must fail if Shadow Preview source references any of:

```text
finishRecording
activeSession
PasteCoordinator
RecordingTask
onVoiceProbe
containsSpeech
SmartInput
OpenClaw
```

It must require the setting default to `false` and require subscription cancellation on hide/end/deinit.

- [x] **Step 2: Implement setting and UI copy**

Use exact product copy:

```text
旁路预览（实验）
在现有胶囊旁显示新转录架构结果；不参与最终识别和粘贴。
```

The toggle is independent of corrected-preview and long-form toggles. Turning it off immediately destroys the shadow window and subscription.

- [x] **Step 3: Implement `@MainActor ShadowPreviewCoordinator`**

Required API:

```swift
func begin(states: AsyncStream<PreviewViewState>, productionFrame: @escaping () -> CGRect?)
func end()
```

`begin` cancels any prior Task. Every received state is verified against the expected session identity. `end` cancels, clears identity and hides immediately.

- [x] **Step 4: Run tests and install build**

Run focused tests, full typecheck, then:

```bash
./native/build_and_log.sh
```

Expected: version/build records updated by the repository workflow; `/Applications/TypeWhale.app` opens successfully and signing verification passes.

- [x] **Step 5: Manual installed-app visual QA**

Verify toggle off/on, normal capsule, notch theme, screen change, repeated recordings, cancel, route failure and app quit. At this task the shadow panel may show only deterministic fixture/adapter content; old final paste must remain identical.

- [x] **Step 6: Commit Task 6**

Stage only files from this task plus required version/docs files after reviewing `git status --short`.

**Stage 3 Exit Gate:** installed app can show/hide an adjacent shadow capsule; old capsule is unchanged; disabling the experiment leaves no shadow Task/window; isolation test proves no production side effects.

---

## Stage 4 — Legacy Event Adapter And Live Side-By-Side Observation

### Task 7: Feed Existing Preview State Into The New Core Without Extra Inference

**Files:**
- Create: `native/Sources/Application/RealtimeTranscription/LegacyPreviewShadowAdapter.swift`
- Modify: `native/Sources/Application/SpeechInputCoordinator.swift`
- Test: `native/Tests/LegacyPreviewShadowAdapterCheck.swift`
- Test: `native/Tests/ShadowPreviewIsolationCheck.sh`

**Interfaces:**
- Consumes: existing `PreviewDisplaySnapshot` or existing production preview update at one narrow call site.
- Produces: unified partial/finalized events for a shadow `TranscriptionSession`; never writes back.

- [x] **Step 1: Write failing adapter tests**

Prove:

- same content with advanced stable boundary emits finalized promotion without visual reset;
- volatile replacement emits a newer partial revision;
- decreasing stable count emits failure diagnostic and no state mutation;
- session end completes once;
- events from old recording ID are rejected.

- [x] **Step 2: Implement one-way adapter**

```swift
struct LegacyPreviewShadowAdapter {
    mutating func consume(_ snapshot: PreviewDisplaySnapshot) -> [TranscriptionEvent]
    mutating func complete() -> [TranscriptionEvent]
    mutating func cancel() -> [TranscriptionEvent]
}
```

The adapter may translate legacy stable/volatile boundaries; it must not call the legacy pipeline or change the snapshot.

- [x] **Step 3: Add a narrow coordinator hook**

At recording start, create shadow objects only when setting is enabled. At existing preview publication, send a copy to the adapter after the production UI update. At every finish/cancel/failure/new recording path, terminate and release shadow objects. Do not move existing conditions or return statements.

- [x] **Step 4: Run stale/lifecycle checks and installed build**

Expected: two capsules update in real time using one recognition result; shadow failure injection leaves production capsule/final paste working.

- [x] **Step 5: Record Stage 4 measurements**

Add to `docs/SHADOW_PREVIEW_QA.md` first-text timing, text parity, revision count, stale callback result and lifecycle cleanup for 20 seconds and 2 minutes.

- [x] **Step 6: Design review and commit**

Invoke `design-review`, then commit code, tests, version history, development log and build log with scoped staging.

**Stage 4 Exit Gate:** user can compare old and new capsule presentation live with no second ASR cost; parity/lifecycle evidence is recorded; old path remains authoritative.

---

## Stage 5 — Streaming Compatibility Proof

### Task 8: Drive The Same Core With A Fake Streaming Provider

**Files:**
- Create: `native/Sources/Infrastructure/RealtimeTranscription/FakeStreamingProvider.swift`
- Create: `native/Sources/Infrastructure/RealtimeTranscription/OnlineStreamingProviderPort.swift`
- Modify: `native/Sources/Application/SpeechInputCoordinator.swift`（仅增加显式内部启动参数控制的旁路 Provider 选择；正常启动不变）
- Test: `native/Tests/FakeStreamingProviderCheck.swift`
- Test: `native/Tests/FakeStreamingShadowInjectionCheck.sh`

**Interfaces:**
- Consumes: continuous `AudioFrame` values and scripted streaming events.
- Produces: the same `TranscriptionEvent` contract used by the shadow Session and capsule.

- [x] **Step 1: Write a failing scripted-stream test**

Script:

```text
partial("今")
partial("今天")
partial("今天讨论")
finalized("今天讨论")
partial("在线模型")
connectionChanged(reconnecting)
partial from old epoch -> rejected
partial from new epoch -> accepted
completed
```

- [x] **Step 2: Implement the fake provider without AppKit dependencies**

The provider exposes deterministic latency and failure injection. It must not know about capsules or `PreviewViewState`.

- [x] **Step 3: Define, but do not implement, real online transport port**

```swift
protocol OnlineStreamingTransport: Sendable {
    func connect(configuration: OnlineProviderConfiguration) async throws
    func send(_ frame: AudioFrame) async throws
    func finishInput() async throws
    func disconnect() async
    func messages() -> AsyncStream<OnlineProviderMessage>
}
```

No vendor SDK, API key, endpoint or network permission enters production in this task.

- [x] **Step 4: Run test and show fake stream in installed shadow capsule**

Use explicit internal launch argument `--debug-shadow-fake-stream` as a deterministic injection entry. It must default to false, must not be persisted or exposed in settings, and normal installed-app launch must remain on the Legacy Adapter. Confirm the old capsule continues its real path while only the shadow capsule consumes the fake streaming Provider.

- [x] **Step 5: Commit Task 8**

**Stage 5 Exit Gate:** the same Session, Reducer, Projector and Presenter handle a streaming Provider without code changes; no real audio leaves the machine.

---

## Stage 6 — Migrate SenseVoice Into A Bounded Shadow Provider

### Task 9: Extract SenseVoice-Specific Work Behind The Provider Port

**Files:**
- Create: `native/Sources/Infrastructure/RealtimeTranscription/SenseVoiceSnapshotProvider.swift`
- Create: `native/Sources/Infrastructure/RealtimeTranscription/SenseVoiceSnapshotNativeRecognizer.swift`（Provider-local PCM→临时 WAV→Native bridge 适配；URL 不得越过 Provider 边界，回调后必须删除）
- Create: `native/Sources/Infrastructure/RealtimeTranscription/SenseVoiceShadowScheduler.swift`
- Create: `native/Sources/Infrastructure/RealtimeTranscription/SenseVoiceBoundaryReconciler.swift`
- Test: `native/Tests/SenseVoiceShadowSchedulerCheck.swift`
- Test: `native/Tests/SenseVoiceBoundaryReconcilerCheck.swift`
- Test: `native/Tests/SenseVoiceSnapshotProviderCheck.swift`
- Test: `native/Tests/SenseVoiceSnapshotNativeRecognizerSourceCheck.sh`

**Interfaces:**
- Consumes: bounded PCM/window source, `NativeSenseVoiceBridge`, provider-local configuration.
- Produces: only unified partial/finalized/failure/completed events.

- [x] **Step 1: Write a scheduler capacity test before extraction**

Required policy:

```swift
struct SenseVoiceShadowSchedulingPolicy: Sendable {
    let correctionCapacity: Int // initial value: 2
    let pendingFastCapacity: Int // exact value: 1
    let maxConsecutiveFastBeforeCorrection: Int // initial value: 1 under pressure
}
```

When correction capacity is reached, merge/replace only requests whose commit horizon has not advanced; otherwise enter `.degraded(.correctionCapacityExceeded)` and stop producing new corrections for that session. Never append unbounded FIFO work.

- [x] **Step 2: Move algorithm, not public names**

Migrate reusable timestamp alignment, boundary reconciliation and latest-only fast behavior. Do not expose `PreviewSourceLane`, `PreviewPipelineRequest`, WAV URL or correction terminology outside Provider files.

- [x] **Step 3: Keep the old pipeline untouched and run shadow provider default-off（依赖提前完成 Task 10 PCM fan-out）**

Initial shadow SenseVoice execution is a separately enabled submode under “旁路预览（实验）”. It must enforce one bounded model admission slot and publish resource diagnostics. If duplicate inference would breach the agreed CPU/latency budget, the shadow Provider degrades instead of delaying the old/final pipeline.

- [x] **Step 4: Run 20-second, 2-minute and 10-minute capacity checks**

Record:

```text
old_first_text_ms
shadow_first_text_ms
max_fast_pending
max_correction_pending
correction_degraded_count
provider_service_ms
main_thread_draw_ms
process_cpu_peak
resident_memory_peak_mb
```

- [x] **Step 5: Install, design-review and commit**

**Stage 6 Exit Gate:** queue capacity is proven by tests, real installed shadow results are visible, old/final latency does not regress beyond an explicitly accepted bound, and no unbounded files/requests survive session end.

---

## Stage 7 — Audio Delivery And Two-Phase Chunk Safety

### Task 10: Add One-Way Bounded Audio Fan-Out

**Execution order:** 根据 2026-07-11 依赖证据，本 Task 在 Task 9 Step 2 后提前执行；其 Exit Gate 通过后返回 Task 9 Step 3。该顺序修正不允许跨过任何 Task 自身门禁。

**Files:**
- Create: `native/Sources/Infrastructure/Audio/AudioFrameFanOut.swift`
- Modify: `native/Sources/Infrastructure/Audio/AudioRecorder.swift`
- Test: `native/Tests/AudioFrameFanOutCheck.swift`

**Interfaces:**
- Consumes: copied PCM frames after the real-time tap.
- Produces: independent bounded consumers; capture callback never awaits or performs ASR/disk/network work.

- [x] **Step 1: Test slow consumer isolation**

Prove one slow shadow subscriber cannot block file recording, VAD or production preview. Overflow must disable only that shadow consumer for the session and emit diagnostics.

- [x] **Step 2: Implement bounded fan-out**

The audio tap performs only bounded copy and non-blocking offer. Each consumer owns capacity and overflow policy. Same physical device is opened once.

- [x] **Step 3: Add shadow subscription without changing existing recorder callbacks**

Do not remove `onRealtimeSnapshot` or `onExperimentalPreviewSnapshot` in this stage.

- [x] **Step 4: Run audio, route-change and installed-app regression**

Verify normal mic, Bluetooth startup configuration churn, real device switch, cancel and repeated recordings.

### Task 11: Make Final Chunk Commit Recoverable

**Files:**
- Create: `native/Sources/Domain/RealtimeTranscription/ChunkCommitState.swift`
- Modify: `native/Sources/Infrastructure/Audio/AudioRecorder.swift`
- Test: `native/Tests/ChunkCommitStateCheck.swift`
- Test: `native/Tests/PreviewFinalChunkWriteFailureCheck.swift`

**Interfaces:**
- Consumes: frozen buffer ownership and snapshot write result.
- Produces: two-phase prepared/committed/failed state with retry or full-recording fallback evidence.

- [x] **Step 1: Reproduce current failure in a focused test**

Inject snapshot write failure after chunk boundary. Expected failing baseline: old code advances index and clears buffers without a recoverable final snapshot.

- [x] **Step 2: Implement two-phase ownership**

State transitions:

```text
collecting -> prepared(frozenBuffers) -> writing
writing -> committed(release buffers, advance authoritative chunk)
writing -> retryableFailure(retain buffers)
retryableFailure -> writing
retryableFailure -> recoveredFromFullRecording(range)
```

No buffer release or authoritative chunk advance before `committed` or verified fallback.

- [x] **Step 3: Run failure injection and production regressions**

Expected: no final chunk gap; write failure is observable; old final path remains available.

- [x] **Step 4: Install, document and commit Stage 7**

**Stage 7 Exit Gate:** audio fan-out is bounded and non-blocking; final chunk failure is recoverable; route/record/final/paste regressions pass in installed app.

---

## Stage 8 — Decision Gate For Real Online Provider

### Task 12: Produce The Online Provider Readiness Decision

**Files:**
- Create: `docs/ONLINE_STREAMING_PROVIDER_READINESS.md`
- Modify only after approval: `docs/ARCHITECTURE.md`

**Interfaces:**
- Consumes: approved vendor/model requirements, privacy policy, authentication, pricing, regional availability, latency and retention evidence.
- Produces: Accepted / Conditional / Experiment required / Rejected architecture status and a separate implementation plan if accepted.

- [x] **Step 1: Confirm product decisions**

Require explicit owner decisions for: provider/vendor, audio retention, account/API key model, network-off behavior, cost ceiling, supported regions, user disclosure and fallback order.

Decision evidence: Doubao ASR and Xiaomi MiMo-V2.5-ASR are selectable one-at-a-time; user-owned Keychain credentials; default off; client retention none; Mainland China first; zero spend before keys/terms; explicit online-audio disclosure; online failure ends only the shadow path. Step 1 当时把 Provider 侧条款、价格和实测行为留给 Step 2；后续 MiMo 真实验证与产品接受证据见 Step 2–3。Exact design and execution plan: `docs/superpowers/specs/2026-07-11-doubao-mimo-online-asr-design.md`, `docs/superpowers/plans/2026-07-11-doubao-mimo-online-asr.md`.

- [x] **Step 2: Run isolated transport spike outside production defaults**

Measure connection setup, first partial, finalization, reconnect continuity, provider limits and cancellation. Do not store credentials in source or enable network transmission by default.

Completion evidence: MiMo Build 703/704 已完成真实鉴权、真实请求、SSE 增量、后台计费、48kHz→16kHz 设备音频归一化、单 active/单 pending、临时 WAV 归零与旧 final/paste fail-open 验证。产品负责人接受 MiMo 作为快照输入/流式响应旁路，并决定豆包真实 Key 验证退出本阶段门禁。MiMo 不因此获得持续 PCM 流或生产预览资格。

- [x] **Step 3: Record decision status and evidence**

If accepted, write a separate exact implementation plan for the chosen provider. Do not append vendor-specific work to this generic migration plan.

Decision evidence: `docs/ONLINE_STREAMING_PROVIDER_READINESS.md`、`docs/superpowers/specs/2026-07-11-doubao-mimo-online-asr-design.md`、`docs/superpowers/plans/2026-07-11-doubao-mimo-online-asr.md`。在线扩展计划 Task 0–9 已完成，MiMo 状态为 `ACCEPTED / SNAPSHOT INPUT + STREAMED RESPONSE`。

**Stage 8 Exit Gate: COMPLETE.** MiMo 真实 Provider 已在默认关闭、用户自有 Key、旁路失败隔离和旧生产权威不变的边界内获准使用。服务端条款、重复快照计费和批次更新仍是产品限制，不得据此批准生产切换。

### Task 12A: Restore The Generic Online Provider Terminal Contract

**2026-07-14 audit amendment:** MiMo has its own complete terminal state machine, but `OnlineTranscriptionProvider` / `DoubaoStreamingTransport` can receive a server-final transcript without producing unified `.completed` or deterministically disconnecting. Stage 8 is reopened only for this provider-neutral terminal defect; real Doubao credential validation remains outside the owner-approved gate.

**Files:**
- Modify: `native/Sources/Infrastructure/RealtimeTranscription/OnlineStreamingProviderPort.swift`
- Modify: `native/Sources/Infrastructure/RealtimeTranscription/OnlineTranscriptionProvider.swift`
- Modify: `native/Sources/Infrastructure/RealtimeTranscription/DoubaoStreamingTransport.swift`
- Modify: `native/Tests/OnlineTranscriptionProviderCheck.swift`
- Modify: `native/Tests/DoubaoStreamingTransportCheck.swift`

**Interfaces:**
- Consumes: one transport-level server-final/completed signal after all final text messages.
- Produces: ordered `finalized -> completed`, one transport disconnect, a finished Provider event stream, and a `.completed` `TranscriptionSession` state.

- [x] **Step 1: RED — add terminal assertions before production changes**

The Provider check must require a successful finish to emit exactly one `.completed`, emit no `.cancelled`, ignore late messages, disconnect exactly once, finish its event stream and drive a real `TranscriptionSession` to `.completed`. The Doubao transport check must require stream-final to emit finalized text followed by one transport completed signal; sentence-final alone must not complete the stream.

- [x] **Step 2: GREEN — implement one ordered provider-neutral terminal signal**

The transport signal must remain vendor-neutral. `OnlineTranscriptionProvider` owns unified event metadata and terminal idempotency. A successful `finish()` must deterministically disconnect after the transport has observed server final. Cancel and recoverable failure semantics must not regress.

- [x] **Step 3: Run focused and adjacent regressions**

Run Online Provider, Doubao protocol/transport, Fake Streaming, Session, Reducer, Broadcaster, Online/Shadow isolation and three-capsule wiring checks. Confirm no transcript text or credential enters diagnostics.

- [x] **Step 4: Update evidence, build, install and commit**

Update this plan, `docs/SHADOW_PREVIEW_QA.md`, `docs/ARCHITECTURE.md`, `docs/开发日志.md` and version history; run `./native/build_and_log.sh`, verify installed version/process/deep-strict signature, then stage only Task 12A files and commit.

Completion evidence: Build 715 通过唯一构建入口覆盖安装并启动，deep/strict 签名有效；新鲜 focused/boundary 回归通过。代码边界检查证明本任务未修改 Candidate、MiMo、生产 final/paste 或长录音实现；真实 Stage 9A 体验矩阵仍待产品负责人签收。

**Task 12A Exit Gate: PASSED FOR FIXTURE/INSTALLED BUILD.** Successful generic online finish is terminal, ordered and leak-free under fixture integration. This restores the prior Stage 8 shadow-only decision but does not claim real Doubao network acceptance, Stage 9A acceptance, production cutover, or long-recording completion.

---

## Stage 9 — Future Cutover And Old-Path Retirement

This stage is gated by accumulated evidence. Task 13A candidate-capsule validation is product-approved; Task 13B production cutover and Task 14 retirement each still require separate user approval before implementation.

### 2026-07-12 Three-Capsule Migration Amendment

产品负责人批准在生产切换前把候选体验与真实技术观测拆开：

- 原胶囊：当前生产权威，行为和位置保持不变。
- 旁路1（技术胶囊）：沿用现有 `ShadowPreview`，真实呈现 Provider/Reducer 的实际批次、修订和失败，不增加逐字美化。
- 旁路2（候选产品胶囊）：消费同一新架构 `PreviewViewState`，允许对已真实到达的文字做有界连续展示，用于验证未来正式胶囊体验；不得生成未返回文字或影响生产链路。

三胶囊只在实验设置开启时出现。Task 13 拆为已批准的候选验证阶段 13A 和仍需单独批准的生产切换阶段 13B。

### Task 13A: Build And Validate The Candidate Product Capsule

本任务已获产品批准，但开始代码前必须完成修订规格和精确实施计划。

Required behavior:

- 保留旁路1作为原始技术证据；不得给它增加打字机动画来掩盖 MiMo 的批次节奏。
- 新增独立旁路2；首版视觉可复用原胶囊语言，但数据只来自新核心 `PreviewViewState`。
- 旁路2只动画 Provider 已返回的真实新增文字；有界追赶、修订干净替换、失败/取消/隐藏/跨 session 清理必须有 RED/GREEN 测试。
- 三个窗口不得互相遮挡或越过屏幕安全区；关闭实验后两个旁路窗口及其 Timer/Task 必须全部销毁。
- 记录原始 chunk 时间和候选展示时间，使技术真实性与产品体验可分别评估。

Exit evidence:

- 20 秒、2 分钟、快速突发、非前缀修订、取消、连续两轮与关闭恢复全部通过；
- 旁路1仍能暴露 MiMo 真实约 2 秒首快照/后续约 4 秒批次；旁路2最终文字严格等于最新新核心状态；
- 旧胶囊、final、整理、粘贴零退化；
- 完成 design-review、真实安装版验证、版本/开发日志/计划同步。

#### 2026-07-14 Local Data-Source Correction

只完成 Candidate Presentation 分层不足以关闭本任务。当前在线关闭或缺 Key 时，两个旁路虽然订阅统一 `PreviewViewState`，其本地数据仍由 `LegacyPreviewShadowAdapter` 复制旧生产快照；这不能证明新架构的本地 Provider 效果，也会把旧快照整段修订直接带入候选体验。

批准的纠正路径见 `docs/superpowers/plans/2026-07-14-local-shadow-provider-activation.md`：正常本地 fallback 必须使用已经通过 Stage 6 容量门禁的有界 `SenseVoiceSnapshotProvider`；Legacy Adapter 只保留活动配置缺失时的 fail-open 安全网。Candidate 继续只做展示，若仍出现从头重播，必须沿 Provider/Reconciler/Core 事件链定位，不得在 View 中处理数据。

### Task 13B: Decide Whether The New Core May Control Production Preview

Required evidence:

- old/new text comparison across the agreed corpus;
- installed-app 20-second, 2-minute, 10-minute and long-session capacity evidence;
- zero stale cross-session updates;
- bounded queues and audio fan-out;
- recoverable final chunk writes;
- UI design review and real-world owner acceptance;
- rollback proven by disabling one setting/build.

Task 13A 完成不自动批准本任务。只有产品负责人再次明确批准后，才可把候选产品胶囊的 ViewState/展示策略移入正式位置；final paste 仍保持完整录音 ASR。切换后旁路1至少保留一个版本作为诊断比较，旁路2是否转为正式胶囊或删除由切换计划明确规定。

### Task 14: Retire Legacy Preview State Only After Production Stability

Candidate removals after a separately approved retirement review:

- `SpeechSession.committedPreviewText`
- `SpeechSession.latestPreviewText`
- coordinator-owned realtime busy/pending/final queues superseded by the new Session
- `ExperimentalRealtimePreviewPipeline`
- legacy string-based `PreviewPresenting.updateDraft(_:)` fallback
- duplicate long-form transcript authority

Retirement proof must include repository search showing no remaining runtime consumer, migration notes in `docs/ARCHITECTURE.md`, development log evidence, complete build/install verification and rollback instructions for the last release containing the old path.

---

## Mandatory Review Checklist At Every Stage

- [ ] Re-read this plan's Global Constraints.
- [ ] Re-run branch/status/process/mtime concurrency protection.
- [ ] Confirm task scope and do-not-touch list before editing.
- [ ] Write the focused failing test first.
- [ ] Run the test and observe the expected failure reason.
- [ ] Implement only the stage-owned boundary.
- [ ] Run focused tests, adjacent regressions and `git diff --check`.
- [ ] For code changes, update `docs/开发日志.md` and application version history before build.
- [ ] Run `./native/build_and_log.sh` and verify installed `/Applications/TypeWhale.app`.
- [ ] Perform the stage's manual installed-app QA.
- [ ] For UI changes, run `design-review` and record unverified visual risks.
- [ ] Review `git status --short`; stage only task-owned files.
- [ ] Commit one independently testable task/change set.
- [ ] Mark completed checkboxes and record measured evidence in `docs/SHADOW_PREVIEW_QA.md`.
- [ ] Confirm the Stage Exit Gate before beginning the next stage.

## Rollback Contract

- Stages 1–2: remove the unreferenced new files; production behavior is unchanged.
- Stages 3–4: disable “旁路预览（实验）”; coordinator must cancel subscription and destroy the shadow window immediately.
- Stages 5–6: disable the selected shadow Provider; legacy-adapter shadow or no shadow remains available without touching production recognition.
- Stage 7: retain compatibility with existing recorder callbacks until two-phase commit and fan-out pass installed-app evidence; rollback restores the previous capture adapter without changing persisted transcripts.
- No rollback may delete user audio, transcript persistence, settings or history.
- A source revert is insufficient if a stage introduces persisted state; each such task must define backward-readable settings/data before implementation.

## Plan Completion Definition

This plan is complete only when:

1. The new core proves non-streaming and streaming Providers behind one public contract.
2. The shadow capsule provides live, isolated comparison in the installed app.
3. The old production path remains unchanged until an explicit Stage 9 cutover approval.
4. Queues, audio delivery, cancellation, stale callbacks and chunk commit failure all have bounded/tested semantics.
5. Online model support is demonstrated by the generic port and fake Provider; a real vendor is added only through a separately approved readiness decision and plan.
6. Documentation accurately distinguishes planned, experimental and production behavior.
