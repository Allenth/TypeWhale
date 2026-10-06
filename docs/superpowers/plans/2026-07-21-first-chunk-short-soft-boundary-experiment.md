# First-Chunk Short Soft Boundary Experiment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 用首块3秒软收口快速稳定录音开头的短词；首块收口后，所有后续块恢复10秒软收口。

**Real acceptance status:** FAILED / 未转正。安装版代码已接入，但真实测试中首块约10.3秒才切换，3秒附近没有满足VAD停顿条件；重叠矫正状态同时持续 `confirmed_chars=0`，所以文字没有由灰变白。不得把“已编译”表述为实验有效。

**2026-07-21 follow-up:** 真实34秒录音随后证明3秒规则在遇到停顿时会实际切开首块，并可能削弱开头上下文；该实验参数已退出，后续实验改由 `2026-07-21-six-second-first-chunk-conditional-stop-tail.md` 管理，首块软边界调整为6秒。本文仅保留历史证据。

**Architecture:** 新建纯值策略 `RealtimeChunkBoundaryPolicy`，集中表达首块/后续块/18秒硬边界规则；`AudioRecorder` 只提供当前块序号、块时长和VAD状态。首块3秒软收口必须先观察到真实人声，防止开头静音提前消耗首块；首块无论软收口还是18秒硬收口，`realtimeChunkIndex` 前进后都会自然切换到10秒策略。

**Tech Stack:** Swift、AVFoundation、Silero VAD、独立 Swift 边界测试和现有 shell 回归。

## Global Constraints

- 首块：观察到人声后，块时长达到3秒且当前停顿时软收口；连续讲话到18秒硬收口。
- 后续块：块时长达到10秒且当前停顿时软收口；连续讲话到18秒硬收口。
- 每次收口后 `realtimeChunkStartFrame` 重置，下一块从0重新计时。
- 开头纯静音不能在3秒触发首块软收口。
- 不改UI、缓存、Final ASR、重叠矫正、VAD模型和5分钟整场录音上限。
- 实验不理想时整体回退本实验提交，不拆改其他功能。
- 不新建 worktree；保护现有未跟踪概念设计目录。

---

### Task 1: Introduce and Wire the Boundary Policy

**Files:**

- Create: `native/Sources/Domain/RealtimeTranscription/RealtimeChunkBoundaryPolicy.swift`
- Create: `native/Tests/RealtimeChunkBoundaryPolicyCheck.swift`
- Create: `native/Tests/RealtimeChunkBoundaryPolicyWiringCheck.sh`
- Modify: `native/Sources/Infrastructure/Audio/AudioRecorder.swift`
- Modify: `docs/ARCHITECTURE.md`
- Modify: `docs/开发日志.md`
- Modify: `native/Sources/Presentation/VersionHistory/VersionHistoryViewController.swift`

**Interfaces:**

- Produces: `RealtimeChunkBoundaryPolicy.shouldFinalize(chunkIndex:chunkDuration:voiceActive:hasObservedVoice:) -> Bool`。
- Consumes: `AudioRecorder.realtimeChunkIndex`、当前块PCM时长、`realtimeVoiceActive` 和本轮已观察人声状态。

- [x] **Step 1: Write RED policy and wiring checks**

  纯策略测试覆盖：首块2.9秒不收口、首块3秒纯静音不收口、首块3秒有人声后停顿收口、首块3秒仍讲话不收口、首块18秒硬收口、第二块9.9秒不收口、第二块10秒停顿收口、第二块18秒硬收口。接线测试要求录音器调用策略、录音开始重置人声观察状态、VAD `true` 时记录观察证据。

- [x] **Step 2: Run RED**

  Compile/run the pure test and wiring script. Expected: FAIL because policy and wiring do not exist.

- [x] **Step 3: Implement minimal policy and wiring**

  策略固定 `firstChunkSoftSeconds = 3`、`laterChunkSoftSeconds = 10`、`hardSeconds = 18`。录音器保留每0.5秒快照节奏，只替换分块布尔判断；提交状态机和缓存回调不改。

- [x] **Step 4: Run GREEN and regressions**

  运行策略、接线、内存快照、静音门控、停止排空、生产缓存和重叠矫正回归；执行 `git diff --check`。

- [x] **Step 5: Build, install, document, and commit**

  完整构建、覆盖安装、签名校验；更新本计划实际证据并提交为一个可整体回退的实验提交。

## Progress

- 2026-07-21：完成代码走读。当前10秒软边界直接写在 `AudioRecorder`；块提交后已有状态机会更新 `realtimeChunkStartFrame` 和 `realtimeChunkIndex`，所以新策略无需另建计时器。
- 2026-07-21：RED 因策略类型和接线均不存在而失败；GREEN 后首块/后续块/静音保护纯策略测试、接线检查、内存快照、静音门控、停止排空、生产缓存和重叠矫正回归通过。
- 2026-07-21：完整构建并覆盖安装 TypeWhale Pro 2.0.54（Build 796）；安装版签名有效并已自动打开。实验代码、测试和文档作为单一提交固化，便于按整体回退。
- 2026-07-21：真实验收未通过。测试日志中首块直到约10.3秒才进入下一块，说明3秒规则受VAD停顿条件限制而未触发；同轮 `confirmed_chars` 始终为0，现有 correction 没有确认任何稳定前缀，故主胶囊文字保持灰色。这两个现象需要作为后续单点任务重新设计，当前实验不得转正。
