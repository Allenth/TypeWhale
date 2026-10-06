# Overlap Correction Toggle Restoration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在设置页恢复正式的“重叠矫正”开关，并让下一次录音真实读取和执行该设置。

**Architecture:** 复用现有 `ExperimentalPreviewSettingsStore`、`correctedPreviewExperiment` 与 `ExperimentalRealtimePreviewPipeline`，不新建第二套配置或识别路径。设置页只恢复一个产品入口；历史“长录音增量输出”入口继续隐藏。控制器从开关状态返回本轮录音的 `ExperimentalPreviewSettings`，不再强制返回关闭。

**Tech Stack:** Swift、AppKit、UserDefaults、现有 shell/Swift 边界测试。

## Global Constraints

- 开工前读取本计划；本轮只执行一个 Task，完成后更新本计划并提交。
- 显示名称固定为“重叠矫正”，放在“录音与预览”产品设置区，紧跟“胶囊实时预览”。
- “重叠矫正”标题与右侧开关之间使用低对比度虚线引导；只影响这一行，不改变其他设置行。
- 开启重叠矫正时自动开启胶囊实时预览；关闭时恢复普通实时预览路径。
- 不恢复“长录音增量输出”入口，不改重叠矫正算法、10–18 秒分块、VAD、缓存、Final ASR、旁路和候选胶囊。
- 保护现有未跟踪概念设计目录，不新建 worktree。

---

### Task 1: Restore the Product Toggle and Runtime Wiring

**Files:**

- Modify: `native/Tests/ExperimentalPreviewSettingsBoundaryCheck.sh`
- Modify: `native/Sources/Presentation/Main/MainViewController+PanelLayout.swift`
- Modify: `native/Sources/Presentation/Main/MainViewController+Configuration.swift`
- Modify: `native/Sources/Presentation/Main/MainViewController+Actions.swift`
- Modify: `docs/ARCHITECTURE.md`
- Modify: `docs/开发日志.md`
- Modify: `native/Sources/Presentation/VersionHistory/VersionHistoryViewController.swift`

**Interfaces:**

- Consumes: `correctedPreviewExperiment: BrandSwitch`、`ExperimentalPreviewSettingsStore`。
- Produces: `experimentalPreviewSettings.correctedPreviewEnabled`，供 `SpeechInputCoordinator.startRecording` 选择普通路径或 `ExperimentalRealtimePreviewPipeline`。

- [x] **Step 1: Write RED boundary checks**

  修改测试，要求 `MainViewController+PanelLayout.swift` 包含 `optionRow("重叠矫正", correctedPreviewExperiment)`，继续拒绝长录音入口；要求 `experimentalPreviewSettings` 从 `correctedPreviewExperiment.state == .on` 读取，拒绝 `correctedPreviewEnabled: false` 的强制关闭实现。

- [x] **Step 2: Run RED**

  Run: `bash native/Tests/ExperimentalPreviewSettingsBoundaryCheck.sh`

  Expected: FAIL，因为当前布局没有“重叠矫正”，运行时 getter 仍强制关闭。

- [x] **Step 3: Implement the minimal restoration**

  在产品设置区将 `optionRow("重叠矫正", correctedPreviewExperiment)` 放在实时预览下一行；无障碍名称和提示语同步改为正式名称。`experimentalPreviewSettings` 返回经过依赖归一化的真实开关状态，且 `longFormIncrementalOutputEnabled` 固定为 `false`。

- [x] **Step 4: Run GREEN and regressions**

  Run:

  ```bash
  bash native/Tests/ExperimentalPreviewSettingsBoundaryCheck.sh
  xcrun swiftc native/Sources/Infrastructure/Settings/ExperimentalPreviewSettings.swift native/Tests/ExperimentalPreviewSettingsCheck.swift -o /tmp/ExperimentalPreviewSettingsCheck
  /tmp/ExperimentalPreviewSettingsCheck
  git diff --check
  ```

  Expected: both checks print `passed`; diff check exits 0.

- [x] **Step 5: Review UI and runtime boundaries**

  确认开关只出现一次、位于产品设置而非诊断工具；确认长录音入口仍不存在；确认下一轮录音能读取开关，关闭时仍走普通快照路径。执行设计质量复核，覆盖标签、层级、禁用状态和持久化反馈。

- [x] **Step 6: Build, install, document, and commit**

  按仓库规则更新版本记录，执行 `./native/build_and_log.sh --full-version`，覆盖安装并打开真实 App；更新本计划的实际证据后提交本 Task。

## Progress

- 2026-07-21：完成代码走读。根因不是控件缺失：控件、存储和 Action 仍存在，但布局测试主动禁止显示，`experimentalPreviewSettings` 也强制返回关闭，因此需要同时恢复 UI 入口与运行时读取。
- 2026-07-21：RED 因布局缺少“重叠矫正”失败；GREEN 后边界测试与设置持久化测试通过。布局仅恢复一个产品开关，运行时 getter 改为读取真实开关状态，长录音入口继续隐藏。
- 2026-07-21：安装版视觉复核发现标题与开关横向距离较大。用户要求只在该行中间增加虚线引导，保持现有左右对齐和其他设置行不变；已补入本 Task 的 UI 验收范围。
- 2026-07-21：新增可选 `dottedLeaderView`，仅“重叠矫正”行传入 `showsLeader: true`；对应 RED/GREEN 边界测试通过。安装版 `2.0.52 (Build 794)` 已完整构建、覆盖安装并打开，签名有效。真实界面确认虚线只填充标题与开关之间的空白，开关可打开且录音运行时读取为开启；用户正在继续真实录音验收。
