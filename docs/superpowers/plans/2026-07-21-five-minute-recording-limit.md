# Five-Minute Recording Limit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将普通语音输入的单次硬上限从120秒调整为300秒，并继续使用现有自动结束和缓存交付流程。

**Architecture:** 只修改 `SpeechInputCoordinator.Timing.maxRecordingSeconds` 这一权威常量；胶囊倒计时、每秒安全检查、自动结束提示和 `LongFormTranscriptionSession` 的当前会话上限继续读取同一常量。同步把过时的两分钟边界测试改成五分钟边界测试，不新增第二套计时逻辑。

**Tech Stack:** Swift、现有 shell 边界测试。

## Global Constraints

- 299秒仍录音，达到300秒触发现有 `finishRecording(reason: "max_duration")`。
- 不改 Final ASR、10–18秒分块、重叠矫正、缓存、VAD、UI布局和无文字超时策略。
- 不新建 worktree；保护现有未跟踪概念设计目录。

---

### Task 1: Raise the Authoritative Limit to 300 Seconds

**Files:**

- Delete: `native/Tests/TwoMinuteFinalRecognitionBoundaryCheck.sh`
- Create: `native/Tests/FiveMinuteRecordingLimitBoundaryCheck.sh`
- Modify: `native/Sources/Application/SpeechInputCoordinator.swift`
- Modify: `docs/ARCHITECTURE.md`
- Modify: `docs/开发日志.md`
- Modify: `native/Sources/Presentation/VersionHistory/VersionHistoryViewController.swift`

**Interfaces:**

- Consumes: `Timing.maxRecordingSeconds`。
- Produces: 300秒胶囊倒计时和 `recording_auto_finish reason=max_duration seconds=300`。

- [x] **Step 1: Write RED**

  用 `FiveMinuteRecordingLimitBoundaryCheck.sh` 断言权威常量为300、旧120秒常量不存在、格式化结果为“5 分钟”、自动结束仍调用现有收尾方法；同步校正重叠矫正入口的当前事实。

- [x] **Step 2: Run RED**

  Run: `bash native/Tests/FiveMinuteRecordingLimitBoundaryCheck.sh`

  Expected: FAIL，因为生产常量仍是120。

- [x] **Step 3: Implement**

  将 `maxRecordingSeconds` 改为300，并更新相邻注释。不得修改其他超时常量或收尾方法。

- [x] **Step 4: Run GREEN and regressions**

  Run the new boundary check、`Stage9AManualGateBoundaryCheck.sh`、实时缓存/停止排空检查和 `git diff --check`；全部必须通过。

- [x] **Step 5: Build, install, document, and commit**

  更新架构和版本记录，完整构建、覆盖安装、签名验证后提交。

## Progress

- 2026-07-21：代码走读确认普通录音上限只有一个生产权威常量，胶囊倒计时与自动结束均读取该值；无需新增计时器。
- 2026-07-21：RED 因生产常量仍为120秒失败；改为300秒后，五分钟边界、Stage 9A、停止排空、生产缓存接线与重叠矫正设置回归均通过。
- 2026-07-21：完整构建 `2.0.53 (Build 795)` 成功，已覆盖安装并打开 `/Applications/TypeWhale Pro.app`；Info.plist 版本和 codesign deep/strict 校验通过。
