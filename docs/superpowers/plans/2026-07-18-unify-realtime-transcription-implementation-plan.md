# Unify Realtime Transcription Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **架构决策前置**：实施前必须先读 `2026-07-18-single-realtime-transcription-architecture-plan.md`（Conditional Accepted 决策）与 `2026-07-11-realtime-transcription-shadow-capsule.md` 的 Execution Progress。本文件是把该决策落成可执行任务的实施计划，不重复论证决策本身。

**Goal:** 把实时转录从「新核心作为旧快照下游 + 3479 行上帝对象编排」的迁移半程，收敛为「统一转录核心作为唯一文本真相、生产胶囊消费统一 ViewState、最终交付独立成 use case」，全程旧路径可回滚，不做 big bang。

**Architecture:** 三阶段单向推进。Phase 1 把本地场景的数据流正过来——让真 PCM `SenseVoiceSnapshotProvider` 成为 `TranscriptReducer` 的真源头，而非由 `LegacyPreviewShadowAdapter` 反推。Phase 2 给成熟的生产胶囊换「进料口」——新增订阅 `AsyncStream<PreviewViewState>` 的 `ProductionPreviewTextCoordinator`，复用 `CapsuleTextBuffer.setSnapshot` 已有的稳定/可变契约，视觉零改动。Phase 3 把最终文本选择从 `SpeechInputCoordinator` 拆成 `FinalDeliveryUseCase`。每阶段以真实录音证据 + 逐字 parity 关门，旧路径留到门禁通过。

**Tech Stack:** Swift 5、Foundation `AsyncStream`/actor、`@MainActor` 隔离、standalone Swift `*Check.swift` 断言与 `*BoundaryCheck.sh` 源码门禁、`native/build_and_log.sh` 唯一构建入口、真实人声录音（人在回路）+ `LaunchDiagnostics` 日志门禁。

## Global Constraints

- **红灯先行**：每个 Task 先加失败测试并观察其失败，再实现；无红灯不写实现。
- **Parity 门**：任何「数据层替换 + 翻默认」步骤，必须先在旧路径与新路径并存态下，于真实录音上证明逐字相等，才允许删旧路径或翻默认。
- **真实证据，非墙钟**：完整性判定只接受 20 秒 / 2 分钟 / 10 分钟真实人声录音的 `tail_gap_ms` 与逐字比对；`等 N ms` 只能防卡死，不能代表可交付。
- **人在回路门禁**：真实录音验证由用户执行；实施者不得以合成 PCM 或单测代替真实录音证据宣称通过。
- **每次一个 Stage**：改 → typecheck → 聚焦测试 → `native/build_and_log.sh` → 覆盖安装 → 真实录音 → 日志门禁，全绿后才开下一个 Task。
- **旧路径不先删**：kill switch / 回滚入口保留到对应门禁通过；每次删除前留一个明确 commit 作为回滚点。
- **Review 触发器即刹车**：命中架构决策文档「Review Triggers」任一条（completed 但 tail gap 超限、UI 显示多于粘贴且非显式 fallback、UI 出现文本修补、provider 私有字段进入 Presentation、在线失败阻塞录音/粘贴）时停止并重审，不得继续局部补丁。
- **不改在线默认策略**：不得默认把音频发往在线 Provider；成本/隐私/保留策略属产品/安全决策，本计划只提供边界。

---

### Task 0: Stage A 契约冻结与文档收口

**Files:**
- Modify: `docs/superpowers/plans/2026-07-11-realtime-transcription-shadow-capsule.md`（已加 2026-07-18 前向指针，待提交）
- Reference: `docs/superpowers/plans/2026-07-18-single-realtime-transcription-architecture-plan.md`（Conditional Accepted，待提交）
- Create: `native/Tests/UnifiedRealtimeSourceBoundaryCheck.sh`

**Interfaces:**
- 源码边界门禁断言：UI 层不出现最终文本裁剪/拼接；`LegacyPreviewShadowAdapter` 不作为本地 fallback 最终默认源。

- [ ] 提交工作树里两份未提交的 7-18 架构文档，作为 Stage A 冻结基线（不改运行时行为）。
- [ ] 新增 `UnifiedRealtimeSourceBoundaryCheck.sh`：grep 断言 Presentation 层不含 transcript 修补逻辑、legacy adapter 不在生产 final 默认分支。
- [ ] 运行边界门禁并观察通过；本 Task 不构建、不覆盖安装。

### Task 1: Phase 1 — 让新核心成为真源头（Stage B）

**Files:**
- Modify: `native/Sources/Infrastructure/RealtimeTranscription/SenseVoiceShadowScheduler.swift`
- Modify: `native/Sources/Infrastructure/RealtimeTranscription/SenseVoiceSnapshotProvider.swift`
- Modify: `native/Sources/Application/RealtimeTranscription/PreviewStateProjector.swift`（若需透传覆盖字段）
- Modify: `native/Sources/Application/SpeechInputCoordinator.swift`（`startShadowPreview` 本地分支选路）
- Create: `native/Tests/SenseVoiceCoverageDiagnosticsCheck.swift`

**Interfaces:**
- Provider/session 级诊断输出 `audio_duration_ms`、`last_recognized_audio_end_ms`、`tail_gap_ms`、`completed_recognitions`、`admission_skipped`。
- 本地场景 runtime 走真 PCM `SenseVoiceSnapshotProvider`；`LegacyPreviewShadowAdapter` 仅保留给在线/缺 Key 兜底分支。

- [ ] 加失败测试：给定已知时长的合成 PCM，断言诊断记录 `tail_gap_ms` 与 `last_recognized_audio_end_ms`（当前无此字段，应失败）。
- [ ] 实现覆盖诊断字段并接入 `SenseVoiceShadowScheduler` / session 汇总日志。
- [ ] 本地分支选路切到真 PCM Provider；保留 `--debug-shadow-*` 与在线分支不变。
- [ ] typecheck + 聚焦测试转绿；`native/build_and_log.sh` 覆盖安装。
- [ ] **人在回路门禁**：真实 20 秒录音 `tail_gap_ms <= 500` 或有等价证据；2 分钟录音无明显末尾丢字、无无限增长队列。失败则回滚选路、保留旧 final ASR fallback。

### Task 2: Phase 2 — 生产胶囊改吃统一 ViewState（Stage D 数据层，视觉零改动）

**Files:**
- Create: `native/Sources/Application/RealtimeTranscription/ProductionPreviewTextCoordinator.swift`
- Modify: `native/Sources/Presentation/Capsule/RecordingPanel.swift`（声明 `ProductionPreviewTextSink` 一致性，`updateDraft(_:)` 已存在）
- Modify: `native/Sources/Application/SpeechInputCoordinator.swift`（挂载 coordinator，behind flag 并存）
- Create: `native/Tests/ProductionPreviewTextCoordinatorCheck.swift`
- Create: `native/Tests/ProductionPreviewParityBoundaryCheck.sh`

**Interfaces:**
- `ProductionPreviewTextCoordinator.begin(states:)` 订阅 `AsyncStream<PreviewViewState>`，映射为 `PreviewDisplaySnapshot` 喂 `ProductionPreviewTextSink`。
- 只接管文字草稿；波形/上下文/录音状态/隐藏仍由 `SpeechInputCoordinator` 命令式驱动，本类不碰。

- [ ] 加失败测试：会话身份锁定（晚到旧 session 丢弃）、序列单调（旧 sequence 丢弃）、终态/失败不喂字、`PreviewViewState → PreviewDisplaySnapshot` 逐字映射。
- [ ] 实现 coordinator（无需动画 timer——`CapsuleTextBuffer` 自带打字机）与窄 sink 协议。
- [ ] behind flag 挂载，与现有两处 `popup.updateDraft(snapshot)` 并存；`native/build_and_log.sh` 覆盖安装。
- [ ] **人在回路 Parity 门**：真实 20 秒 + 2 分钟录音，新旧两路显示逐字一致（日志比对）。不一致则停在并存态、不翻默认。
- [ ] Parity 通过后翻默认、删两处直喂调用、退掉 `PreviewTranscriptReducer` 预览喂入支线；`ProductionPreviewParityBoundaryCheck.sh` 断言直喂路径已移除。

### Task 3: Phase 3 — 拆最终交付出上帝对象（Stage C）

**Files:**
- Create: `native/Sources/Application/FinalDeliveryUseCase.swift`
- Modify: `native/Sources/Application/SpeechInputCoordinator.swift`（委托 use case）
- Reference: `native/Sources/Application/FinalRecognitionUseCase.swift`、`native/Sources/Application/ProviderAwareFinalASR.swift`（保留兜底）
- Create: `native/Tests/FinalDeliveryUseCaseCheck.swift`

**Interfaces:**
- `FinalDeliveryUseCase` 输入：recording task、transcript 快照、preview 快照、用户「停止后重识别」开关、provider 诊断；输出：`final text + source + reason`。
- 受保护不变量：UI 不参与选择；Provider 不知道粘贴策略；完整 final ASR fallback 保留。

- [ ] 加失败测试覆盖 5 分支：transcript completed 且完整→用 transcript；completed 但异常短→final ASR；running/failed/empty→final ASR；用户开启重识别→final ASR；online 缺 Key→本地或 final fallback。
- [ ] 实现 use case，把选择逻辑从 `SpeechInputCoordinator` 迁出；协调器改为委托。
- [ ] typecheck + 全量 final-routing 回归转绿；`native/build_and_log.sh` 覆盖安装。
- [ ] **人在回路门禁**：真实录音下 final paste `source`/`reason` 可解释、fallback 行为正常；异常短候选不粘贴。

### Task 4: Stage F 收敛与旧世界退休（门禁全绿后）

**Files:**
- Delete/Freeze: `native/Sources/Domain/RealtimePreview/PreviewTranscriptReducer.swift` 预览默认路径、`LegacyPreviewShadowAdapter` 本地默认分支
- Modify: `docs/ARCHITECTURE.md`（更新为新主链路）
- Modify: `docs/开发日志.md`、`docs/superpowers/plans/2026-07-18-single-realtime-transcription-architecture-plan.md`（用真实日志更新 Stage 状态）
- Modify: 应用内版本历史（`VersionHistoryViewController`）

**Interfaces:**
- 退休入口条件：Task 1–3 门禁全部通过，且连续若干真实录音无尾字丢失、无粘贴空、无 UI 退化，旧链路无最近救场记录。

- [ ] 确认 Task 1–3 的真实录音门禁均已由用户签核通过。
- [ ] 删除旧胶囊生产默认路径与 legacy adapter 默认分支；删除前打一个 release tag / commit 作回滚点。
- [ ] **人在回路终验**（单胶囊真实安装版）：20 秒 / 2 分钟 / 10 分钟 / 取消恢复 / 连续录音 / 在线 off / online 缺 Key / MiMo ready / 豆包 ready 或缺 Key，逐项 PASS。
- [ ] 更新 `ARCHITECTURE.md`、开发日志与架构决策文档 Stage 状态；提交实现与发布输出，保持工作树干净。

## Execution Discipline（如何确保按计划实施）

按序推进，任一门禁不过即停在当前 Task 的并存/回滚态，不跳步、不 big bang：

1. **红灯先行** → 2. **实现转绿** → 3. **构建覆盖安装** → 4. **真实录音 + 日志门禁（人在回路）** → 5. **Parity/证据签核后才翻默认或删旧** → 6. **命中 Review Trigger 则重审而非补丁**。

每个 Task 完成时，用真实日志更新本文件对应 checkbox 与架构决策文档的 Stage 状态；未获真实录音签核的 Task 不得标记为 verified。

## Definition of Done（全计划）

- 单一 `PreviewViewState` → 单一正式胶囊；技术影子/候选并行投影收敛。
- 最终粘贴只从统一转录核心取；完整 final ASR 仅作 fallback 或用户显式开关。
- `PreviewTranscriptReducer` 预览默认路径与 `LegacyPreviewShadowAdapter` 本地默认分支删除。
- `SpeechInputCoordinator` 不再自己挑最终文本；final 选择归 `FinalDeliveryUseCase`。
- `ARCHITECTURE.md` 反映新主链路；Stage 9A / B–F 以真实录音证据关闭。
