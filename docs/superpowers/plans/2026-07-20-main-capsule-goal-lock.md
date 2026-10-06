# Main Capsule Architecture Goal Lock Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans`（逐 Task 执行计划）to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **目标锁定:** 后续所有主胶囊、候选胶囊、旁路胶囊、实时预览、最终粘贴相关开发，必须先读本文，再读具体 Task 文档。

**Goal:** 重构主胶囊，而不是扶正候选胶囊；最终产品只保留一个主预览胶囊和一条清晰的最终交付链路。

**Architecture:** 候选胶囊只作为参考实现，参考它的内容/动画/渲染分层，不把它升级成产品主胶囊。主胶囊保留产品身份，但内部逐层拆分：状态、内容投影、动画进度、渲染、外壳。旁路/候选是迁移期观察工具，不是长期产品结构。

**Tech Stack:** Swift/AppKit（macOS 原生 UI）、`PreviewViewState`（统一预览状态）、`PreviewDisplaySnapshot`（旧胶囊快照）、`FinalDeliveryUseCase`（最终交付选择）、`RealtimePreviewDeliveryCache`（计划中的实时预览交付缓存）。

## Global Constraints

- 每次只改一个点；禁止一个 Task 同时改数据层、UI 层和最终粘贴。
- 普通 `./native/build_and_log.sh`（安装入口）只做 install-only，不编译、不 bump；只有显式 `--full-version` / `--package` 才构建。
- 代码改动完成后必须提交；文档改动完成后也应提交，避免目标锁丢失。
- UI 层不决定文本内容；UI 只展示状态，不修字、不拼最终稿。
- 最终粘贴来源只能由交付层决定，不由任何胶囊决定。

---

## 1. 固定目标

### 目标

```text
重构主胶囊
```

### 非目标

```text
不是扶正候选胶囊
不是长期保留三胶囊
不是把旁路做成产品功能
不是顺手改最终粘贴策略
不是通过 UI 修补识别结果
```

### 一句话原则

```text
候选胶囊是参考实现，不是迁移目标；最终目标是一个重新分层的主胶囊。
```

## 2. 当前现实

当前存在三套可见预览：

- `RecordingCapsuleView`（主胶囊 View）：产品主预览，承载录音、声波、翻译、龙虾、闪念、错误态等能力。
- `ShadowPreviewView`（旁路胶囊 View）：迁移期技术观察窗口。
- `CandidatePreviewView`（候选胶囊 View）：迁移期展示方式参考窗口。

当前存在几类文本/状态来源：

- `PreviewDisplaySnapshot`（旧胶囊快照）：主胶囊旧展示入口使用。
- `PreviewViewState`（统一预览状态）：旁路/候选/部分主胶囊迁移路径使用。
- `LegacyRealtimePreviewDeliveryCache`（旧实时预览交付缓存）：当前用于保护旧链路最终可交付文本。
- `FinalDeliveryUseCase`（最终交付选择）：决定最终粘贴使用候选缓存还是 Final ASR。

## 3. 未来目标结构

目标不是三胶囊并存，而是：

```text
识别/预览状态
→ MainCapsuleState（主胶囊统一状态）
→ MainCapsulePresentationModel（主胶囊展示模型）
→ MainCapsuleShell（主胶囊外壳）
→ 一个产品主胶囊
```

最终交付独立：

```text
RealtimePreviewDeliveryCache（实时预览交付缓存）
或 Final ASR（停止后整段识别）
→ FinalDeliveryUseCase（最终交付选择）
→ 粘贴
```

## 4. 分层边界

### 数据层

负责：

```text
识别、分段、stable/volatile 状态、质量判断输入
```

禁止：

```text
控制胶囊动画
决定 UI 怎么画
```

### 展示模型层

负责：

```text
把状态转成可画的 RenderState
管理 displayed count 这类显示进度
```

禁止：

```text
改识别文本
决定最终粘贴
```

### View 层

负责：

```text
画背景、文字、声波、徽标、状态
```

禁止：

```text
拼文本
修文本
持有最终交付缓存
```

### 交付层

负责：

```text
决定最终粘贴文本来源
记录选择原因
```

禁止：

```text
依赖某个胶囊当前显示了什么
```

## 5. 每次开工前必须回答

- [ ] 本 Task 改的是哪一层？
- [ ] 本 Task 是否改变用户可见行为？
- [ ] 本 Task 是否影响最终粘贴来源？
- [ ] 本 Task 是否把候选/旁路变成产品主线？
- [ ] 本 Task 失败时能否单独回滚？

只要有一项答不清楚，不能开工。

## 6. 禁止事项

- 禁止把 `CandidatePreviewView`（候选胶囊 View）直接扶正为主胶囊。
- 禁止让 `ShadowPreviewView`（旁路胶囊 View）进入产品主路径。
- 禁止让 `RecordingCapsuleView`（旧主胶囊 View）继续吸收新的业务判断。
- 禁止让 `CapsuleTextBuffer`（旧主胶囊文本缓冲）决定最终粘贴。
- 禁止让 `CandidatePresentationModel`（候选展示模型）决定最终粘贴。
- 禁止一个 Task 同时改 `FinalDeliveryUseCase`（最终交付选择）和胶囊 UI。

## 7. 推荐改造顺序

### Task 1: 主胶囊状态清单

**Files:**
- Modify: `docs/superpowers/plans/2026-07-20-main-capsule-goal-lock.md`（本文）

**Goal:** 列全主胶囊现有状态，不写代码。

- [x] 列出录音、识别中、整理中、空音频、错误、翻译、原文、OpenClaw、闪念、声波、倒计时、上下文。
- [x] 标注每个状态现在由哪个文件控制。
- [x] 标注是否必须迁移到新主胶囊。

#### Task 1 盘点结果 / 主胶囊现有状态

**状态驱动入口:**

- `native/Sources/Application/SpeechInputCoordinator.swift`（主流程协调器：决定何时显示、隐藏、更新主胶囊）
- `native/Sources/Presentation/Capsule/PreviewPresenting.swift`（主预览协议：胶囊/刘海主题共同实现）

**经典主胶囊实现:**

- `native/Sources/Presentation/Capsule/RecordingPanel.swift`（主胶囊窗口：位置、上下文条、边框、状态 badge）
- `native/Sources/Presentation/Capsule/RecordingCapsuleView.swift`（主胶囊绘制：文本、声波、内发光、OpenClaw badge）
- `native/Sources/Presentation/Capsule/CapsuleTextBuffer.swift`（旧文本显示缓冲：target/displayed/stable/volatile/逐字推进）
- `native/Sources/Presentation/Capsule/CapsuleVisibleTextCache.swift`（可见文本裁剪缓存）

**另一套主预览实现:**

- `native/Sources/Presentation/Notch/NotchPreviewPresenter.swift`（刘海主题：实现同一 `PreviewPresenting`，但能力少于经典胶囊）

| 状态 / 能力 | 现在怎么触发 | 当前主要文件 | 是否必须迁移 | 迁移备注 |
| --- | --- | --- | --- | --- |
| 录音中 | `startRecording(...)` 调 `popup.show(state: "录音中", draft: "")` | `SpeechInputCoordinator.swift`, `RecordingPanel.swift`, `RecordingCapsuleView.swift` | 必须 | 主胶囊基础状态。 |
| 实时预览文本 | `applyRealtimePreview(...)` / `applyExperimentalPreviewState(...)` 产出 `PreviewDisplaySnapshot`，再经 `productionPreviewTextCoordinator` 投递 | `SpeechInputCoordinator.swift`, `ProductionPreviewTextCoordinator.swift`, `RecordingCapsuleView.swift`, `CapsuleTextBuffer.swift` | 必须 | 不允许 View 拼最终文本；UI 只展示 stable/volatile。 |
| 结构化 stable/volatile 显示 | `RecordingCapsuleView.update(snapshot:)` 调 `CapsuleTextBuffer.setSnapshot(...)` | `RecordingCapsuleView.swift`, `CapsuleTextBuffer.swift` | 必须 | 后续应拆成主胶囊展示模型，不放 View 内。 |
| 逐字推进 | `CapsuleTextBuffer.advance()` + `draftTimer` | `RecordingCapsuleView.swift`, `CapsuleTextBuffer.swift` | 必须 | 应参考候选胶囊 motion 分层，只让 motion 管显示进度。 |
| 声波 | `recorder.onBands` 调 `popup.updateBands(...)`，View 用 `WaveformRenderer` 画 | `SpeechInputCoordinator.swift`, `RecordingPanel.swift`, `RecordingCapsuleView.swift`, `UIComponents.swift` | 必须 | 这是主胶囊录音反馈，不能丢。 |
| 输入电平 | `recorder.onInputLevelDb` 调 `popup.updateInputLevel(...)` | `SpeechInputCoordinator.swift`, `RecordingPanel.swift`, `NotchPreviewPresenter.swift` | 可迁移为内部能力 | 经典胶囊当前兼容但不显示工程读数；刘海主题用它驱动 pulse。 |
| 顶部上下文条 | 录音开始 `popup.setContext(appIcon, appName, modeName, autoTranslateEnabled)` | `SpeechInputCoordinator.swift`, `RecordingPanel.swift` | 必须 | 包括目标 App、模式、自动翻译 badge。 |
| 目标 App 变化 | `popup.updateTargetApp(...)` | `SpeechInputCoordinator.swift`, `RecordingPanel.swift`, `NotchPreviewPresenter.swift` | 必须 | 防止粘贴目标/展示目标信息错乱。 |
| 整理模式标签 | `popup.updateModeName(...)` / `popup.updateModeEmphasis(...)` | `SpeechInputCoordinator.swift`, `RecordingPanel.swift` | 必须 | 包括自动模式解析出的高亮状态。 |
| 点击切换整理模式 | `popup.onCycleMode` 回调 `cycleSmartRewriteModeFromCapsule()` | `SpeechInputCoordinator.swift`, `PreviewPresenting.swift`, `RecordingPanel.swift` | 必须 | 新 Shell 要保留点击入口。 |
| 自动翻译 badge | `popup.updateAutoTranslateEnabled(...)` | `SpeechInputCoordinator.swift`, `RecordingPanel.swift` | 必须 | 只在 dictation 且自动翻译开启时显示。 |
| 倒计时 / 最长录音提醒 | `updateCapsuleStatus()` 调 `popup.updateRecordingStatus(remainingSeconds:, memoryHigh:)` | `SpeechInputCoordinator.swift`, `RecordingPanel.swift` | 必须 | 10s/30s 以内边框变色。 |
| 内存偏高提醒 | `updateCapsuleStatus()` 同一路径传 `memoryHigh` | `SpeechInputCoordinator.swift`, `RecordingPanel.swift` | 必须 | 会覆盖边框颜色和状态 badge。 |
| Ollama 健康绿环 | `refreshOllamaHealthForCapsuleIfNeeded()` 调 `popup.updateOllamaHealth(...)` | `SpeechInputCoordinator.swift`, `RecordingPanel.swift`, `HealthBorderOverlayView.swift` | 必须 | 仅本地 Ollama provider 有意义。 |
| 录音失败 | recorder start 失败后 `popup.show(state: "录音失败")` | `SpeechInputCoordinator.swift`, `RecordingPanel.swift` | 必须 | 错误态。 |
| 保存失败 | recorder stop 失败后 `popup.show(state: "保存失败", draft: "")` | `SpeechInputCoordinator.swift`, `RecordingPanel.swift` | 必须 | 错误态。 |
| 检测中 | 停止录音后 VAD 前 `popup.show(state: "检测中")` | `SpeechInputCoordinator.swift`, `RecordingPanel.swift` | 必须 | OpenClaw 录音会隐藏胶囊。 |
| 识别中 | VAD 失败兜底或开始 final recognition 时 `popup.show(state: "识别中", draft: "")` | `SpeechInputCoordinator.swift`, `RecordingPanel.swift` | 必须 | OpenClaw 录音会隐藏胶囊。 |
| 识别失败 | final 失败时 `popup.show(state: "识别失败", draft: "")` | `SpeechInputCoordinator.swift`, `RecordingPanel.swift` | 必须 | OpenClaw 录音会隐藏胶囊。 |
| 识别完成 | final/rewrite 后更新主窗口状态，并隐藏胶囊 | `SpeechInputCoordinator.swift` | 必须保留流程 | 胶囊通常隐藏，不是持续显示状态。 |
| 翻译中 | 自动翻译路径 `popup.show(state: "翻译中", draft: "")` | `SpeechInputCoordinator.swift`, `RecordingPanel.swift` | 必须 | 属于后处理状态。 |
| 翻译完成 / 翻译未完成 | 更新主窗口状态后 `popup.hideAnimated()` | `SpeechInputCoordinator.swift` | 必须保留流程 | 胶囊最终隐藏。 |
| 整理中 | smart rewrite 路径 `popup.show(state: "整理中", draft: "")` | `SpeechInputCoordinator.swift`, `RecordingPanel.swift` | 必须 | 属于后处理状态。 |
| 原文模式 | `progress.shouldRewrite == false` 时不显示整理中，直接成功状态 | `SpeechInputCoordinator.swift`, `SpeechInputPurpose.swift`, `RecordingPanel.swift` | 必须 | 顶部模式名要保留“原文/自动解析结果”。 |
| 长录音收尾 | `longFormFinalizationTaskIDs` 非空时 `popup.show(state: "正在收尾", draft: "请稍候...")` | `SpeechInputCoordinator.swift`, `RecordingPanel.swift` | 必须 | 防止用户误以为可立即开始下一次。 |
| 自动结束 | 长时间无文本但有语音时 `popup.show(state: "自动结束", draft: "正在识别")` | `SpeechInputCoordinator.swift`, `RecordingPanel.swift` | 必须 | 属于录音安全状态。 |
| 无输入已停止 | 初始静音/无文本超时 `popup.show(state: "无输入已停止", draft: ...)` 后延迟隐藏 | `SpeechInputCoordinator.swift`, `RecordingPanel.swift` | 必须 | 空录音提示。 |
| 空录音 / 未检测到人声 | `showEmptyRecording()` 更新主窗口并隐藏胶囊 | `SpeechInputCoordinator.swift` | 必须保留流程 | 当前胶囊不显示“录音为空”，是产品选择。 |
| 闪念胶囊模式 | `SpeechInputPurpose.ideaPill` 强制 classic 主题，`popup.updateAccent(.ideaPill)` | `SpeechInputCoordinator.swift`, `SpeechInputPurpose.swift`, `RecordingPanel.swift`, `RecordingCapsuleView.swift` | 必须 | 不是候选胶囊；是主胶囊目的状态。 |
| 闪念保存成功/失败 | `saveIdeaPill(...)` 更新主窗口状态并隐藏胶囊 | `SpeechInputCoordinator.swift`, `BacklogWriter.swift` | 必须保留流程 | 主胶囊要保留入口和视觉强调，保存状态主要在主窗口/Toast。 |
| OpenClaw 模式 | `SpeechInputPurpose.openClawChat` 强制 classic 主题，`popup.updateAccent(.openClaw)` | `SpeechInputCoordinator.swift`, `SpeechInputPurpose.swift`, `RecordingPanel.swift`, `RecordingCapsuleView.swift` | 必须 | 不是旁路胶囊；是主胶囊目的状态。 |
| OpenClaw 连接状态 | `refreshOpenClawConnectionStatusForCapsuleIfNeeded()` 调 `popup.updateOpenClawConnectionStatus(...)` | `SpeechInputCoordinator.swift`, `RecordingCapsuleView.swift` | 必须 | 右上角龙虾 badge 会按 checking/connected/unavailable 变色。 |
| OpenClaw 发送中 | 识别完成后主窗口显示“发送 OpenClaw”，胶囊隐藏 | `SpeechInputCoordinator.swift`, `OpenClawReplyPresenter.swift` | 必须保留流程 | 主胶囊负责录音期视觉；回复 UI 在 `OpenClawReplyPresenter`。 |
| OpenClaw 排队/回复/失败 | 非录音时更新主窗口与回复面板 | `SpeechInputCoordinator.swift`, `OpenClawReplyPresenter.swift` | 必须保留流程 | 不应塞进主胶囊 View。 |
| 粘贴中 | `inputState = .pasting`，胶囊通常已经隐藏 | `SpeechInputCoordinator.swift`, `PasteCoordinator.swift` | 保留流程即可 | 不应成为胶囊文本缓存责任。 |
| 自动粘贴失败 | 主窗口显示“已保存到主页历史”，Toast 后隐藏胶囊 | `SpeechInputCoordinator.swift`, `PasteCoordinator.swift` | 必须保留流程 | 不属于主胶囊绘制核心。 |
| 隐藏/收起 | 多处 `popup.hideAnimated()` | `SpeechInputCoordinator.swift`, `RecordingPanel.swift`, `NotchPreviewPresenter.swift` | 必须 | 新 Shell 必须统一生命周期。 |
| 主题切换 classic/notch | `applyPreviewTheme(...)` 替换 `RecordingPanel` / `NotchPreviewPresenter` | `SpeechInputCoordinator.swift`, `PreviewPresenting.swift`, `NotchPreviewPresenter.swift` | 必须决策 | 主胶囊重构需决定刘海主题是否同步迁移或保持适配层。 |

#### Task 1 结论

主胶囊不是一个“语音文本框”。它现在承载：

```text
录音反馈
实时文本
声波
目标 App 上下文
整理模式
自动翻译标记
倒计时/内存/Ollama 健康
闪念模式
OpenClaw 模式与连接状态
错误/空录音/自动结束/收尾
隐藏生命周期
```

因此 Task 2 不能只抽“文本状态”。`MainCapsuleState` 必须先覆盖三类状态：

```text
录音期状态
后处理状态
目的/外观状态
```

并且必须把 `RecordingPanel`（主胶囊窗口）和 `RecordingCapsuleView`（主胶囊绘制）分开处理，不能继续让单个 View 同时承担文本、声波、OpenClaw badge、内发光、边框和动画。

### Task 2: 抽 `MainCapsuleState`（主胶囊统一状态）

**Files:**
- Create: `native/Sources/Presentation/Capsule/MainCapsuleState.swift`（主胶囊统一状态）
- Test: `native/Tests/MainCapsuleStateCheck.swift`（状态映射测试）

**Goal:** 只抽状态，不改 UI 显示。

- [x] 先写测试：输入录音期、后处理、目的/外观状态，输出明确 enum case。
- [x] 实现最小 `MainCapsuleState`，至少覆盖 Task 1 结论里的三类：录音期状态、后处理状态、目的/外观状态。
- [x] 不改 `RecordingCapsuleView` 绘制。
- [x] 不改 `FinalDeliveryUseCase`、Provider、Reconciler 或粘贴流程。

### Task 3: 抽 `MainCapsuleTextMotion`（主胶囊文字动画进度）

**Files:**
- Create: `native/Sources/Presentation/Capsule/MainCapsuleTextMotion.swift`（主胶囊文字显示进度）
- Test: `native/Tests/MainCapsuleTextMotionCheck.swift`（逐字推进测试）

**Goal:** 参考候选胶囊的 motion 分层，把“显示到第几个字”从文本内容里拆出来。

- [x] 先写测试：目标文本增长时只推进 visible count。
- [x] 实现 motion。
- [x] 不改变最终粘贴。

### Task 4: 抽 `MainCapsuleRenderState`（主胶囊渲染状态）

**Files:**
- Create: `native/Sources/Presentation/Capsule/MainCapsuleRenderState.swift`（主胶囊可绘制状态）
- Test: `native/Tests/MainCapsuleRenderStateCheck.swift`（渲染状态测试）

**Goal:** View 只画 render state，不再自己推导业务状态。

- [x] 先写测试：`MainCapsuleState` + text motion 输出 `MainCapsuleRenderState`。
- [x] 保持原胶囊视觉行为不变。

### Task 5A: 主胶囊 View 外壳拆分

**Files:**
- Modify: `native/Sources/Presentation/Capsule/RecordingCapsuleView.swift`（旧主胶囊 View）
- Create: `native/Sources/Presentation/Capsule/MainCapsuleShell.swift`（主胶囊外壳）

**Goal:** 先拆 View 内部胶囊本体外壳：尺寸、圆角、本体绘制区域、OpenClaw 外置徽章预留区域。

- [x] 先写边界测试：View 不直接引用最终交付类型。
- [x] 分离 shell。
- [x] 用户可见行为保持不变。

### Task 5B: 主胶囊 Panel 外壳拆分

**Files:**
- Modify: `native/Sources/Presentation/Capsule/RecordingPanel.swift`（旧主胶囊窗口）
- Create: `native/Sources/Presentation/Capsule/MainCapsulePanelShell.swift`（主胶囊窗口外壳）
- Test: `native/Tests/MainCapsulePanelShellCheck.swift`（窗口布局几何测试）

**Goal:** 补完 Panel 层外壳：窗口初始大小、屏幕内宽度限制、底部居中锚点、content/capsule/material/health overlay frame。

- [x] 先写测试：bodySize + infoBarWidth + screenFrame 输出明确 panel frame 和子视图 frame。
- [x] 把 `RecordingPanel` 的窗口几何计算迁到 `MainCapsulePanelShell`。
- [x] 不改顶部信息条内容、不改胶囊内容绘制、不改数据缓存或最终粘贴。

### Task 6: 逐状态迁移

**Goal:** 一次只迁移一个状态。

顺序：

```text
语音预览
声波
翻译/原文
OpenClaw
闪念
错误/空音频/整理中
上下文
```

每个状态单独 Task、单独测试、单独提交。

#### Task 6A: 迁移语音预览文本展示

**Files:**
- Modify: `native/Sources/Presentation/Capsule/RecordingCapsuleView.swift`（主胶囊文本绘制入口）
- Modify: `native/Sources/Presentation/Capsule/MainCapsuleTextMotion.swift`（补一个只读桥接初始化）
- Test: `native/Tests/MainCapsuleTextMotionCheck.swift`（桥接计数测试）
- Test: `native/Tests/MainCapsulePreviewTextMigrationBoundaryCheck.sh`（迁移边界测试）

**Goal:** 主胶囊语音预览文本展示开始通过 `MainCapsuleTextMotion` + `MainCapsuleRenderState` 输出可绘制文本。

- [x] 先写测试：旧 `CapsuleTextBuffer` 产出的 displayed/target/stable 计数能桥接成 render state。
- [x] `RecordingCapsuleView` 只改文本展示读取路径，不改 `CapsuleTextBuffer` 内容生成和 timer 推进。
- [x] 不改最终粘贴，不改 `FinalDeliveryUseCase`、Provider、Reconciler、候选/旁路胶囊。
- [x] 用户可见文本内容、裁剪、淡入和 stable/volatile 弱化效果保持不变。

#### Task 6B: 迁移声波展示状态

**Files:**
- Create: `native/Sources/Presentation/Capsule/MainCapsuleWaveformMotion.swift`（主胶囊声波显示状态）
- Modify: `native/Sources/Presentation/Capsule/MainCapsuleRenderState.swift`（渲染状态携带声波 bands）
- Modify: `native/Sources/Presentation/Capsule/RecordingCapsuleView.swift`（主胶囊声波绘制入口）
- Test: `native/Tests/MainCapsuleWaveformMotionCheck.swift`（声波平滑状态测试）
- Test: `native/Tests/MainCapsuleRenderStateCheck.swift`（render state 携带声波测试）
- Test: `native/Tests/MainCapsuleWaveformMigrationBoundaryCheck.sh`（声波迁移边界测试）

**Goal:** 主胶囊声波展示开始通过主胶囊 render/presentation 分层读取状态。

- [x] 先写测试：声波 motion 接收 raw bands 后输出平滑 bands，空输入回落到基线。
- [x] `MainCapsuleRenderState` 携带已平滑的 waveform bands。
- [x] `RecordingCapsuleView` 只改声波展示状态读取路径，不改 `recorder.onBands`、`WaveformRenderer` 折线算法或颜色。
- [x] 不改 ASR、录音采集、文本缓存、最终粘贴、候选/旁路胶囊。

#### Task 6C: 迁移翻译/原文状态展示映射

**Files:**
- Create: `native/Sources/Presentation/Capsule/MainCapsuleLegacyStatusProjection.swift`（旧状态字符串到主胶囊状态的展示投影）
- Modify: `native/Sources/Presentation/Capsule/MainCapsuleRenderState.swift`（允许保留旧状态显示文案）
- Modify: `native/Sources/Presentation/Capsule/RecordingCapsuleView.swift`（状态文字从 render state 读取）
- Test: `native/Tests/MainCapsuleLegacyStatusProjectionCheck.swift`（翻译/旧状态投影测试）
- Test: `native/Tests/MainCapsuleTranslationOriginalMigrationBoundaryCheck.sh`（翻译/原文迁移边界测试）

**Goal:** 主胶囊的“翻译中/原文相关展示状态”开始进入 `MainCapsuleState` / `MainCapsuleRenderState`，但旧调用方仍可传原状态字符串。

- [x] 先写测试：`翻译中` 投影为 `.translating`，显示文案仍为 `翻译中`。
- [x] 旧状态字符串显示保持兼容，不能让 `检测中/识别中/保存失败` 等旧文案退化成 `录音中`。
- [x] `RecordingCapsuleView` 状态文字改为从 `MainCapsuleRenderState.statusText` 绘制。
- [x] 不改翻译引擎、智能整理、ASR、文本缓存、最终粘贴、候选/旁路胶囊。

#### Task 6D: 迁移 OpenClaw 主胶囊目的/连接状态展示映射

**Files:**
- Create: `native/Sources/Presentation/Capsule/MainCapsuleOpenClawProjection.swift`（旧 OpenClaw accent/connection 到主胶囊 purpose 的展示投影）
- Modify: `native/Sources/Presentation/Capsule/MainCapsuleRenderState.swift`（继续携带 purpose）
- Modify: `native/Sources/Presentation/Capsule/RecordingCapsuleView.swift`（OpenClaw badge 从 render state 读取是否显示和连接状态）
- Test: `native/Tests/MainCapsuleOpenClawProjectionCheck.swift`（OpenClaw 投影测试）
- Test: `native/Tests/MainCapsuleOpenClawMigrationBoundaryCheck.sh`（OpenClaw 迁移边界测试）

**Goal:** 主胶囊 OpenClaw 的“是否显示龙虾 badge”和“连接状态颜色”进入 `MainCapsuleState` / `MainCapsuleRenderState`，但旧 Panel 调用 `updateAccent` / `updateOpenClawConnectionStatus` 保持不变。

- [x] 先写测试：`.openClaw + .connected/checking/unavailable` 投影为 `.openClaw(connection: ...)`。
- [x] 非 OpenClaw accent 投影为 `.dictation` 或 `.ideaPill`，不得误画 OpenClaw badge。
- [x] `RecordingCapsuleView` 只改 OpenClaw 展示读取路径；badge 几何、颜色、绘制算法保持不变。
- [x] 不改 OpenClaw 发送逻辑、回复面板、ASR、文本缓存、最终粘贴、候选/旁路胶囊。

#### Task 6E: 迁移闪念/目的内发光展示映射

**Files:**
- Modify: `native/Sources/Presentation/Capsule/MainCapsuleRenderState.swift`（从 purpose 输出内发光展示类型）
- Modify: `native/Sources/Presentation/Capsule/RecordingCapsuleView.swift`（内发光从 render state 读取）
- Test: `native/Tests/MainCapsulePurposeGlowCheck.swift`（目的内发光投影测试）
- Test: `native/Tests/MainCapsuleIdeaPillMigrationBoundaryCheck.sh`（闪念迁移边界测试）

**Goal:** 主胶囊闪念模式的内发光展示从 `MainCapsuleRenderState` 读取；旧 Panel 仍可继续通过 `updateAccent(.ideaPill)` 驱动。

- [x] 先写测试：`.ideaPill` 输出闪念内发光，`.dictation` 不输出内发光。
- [x] 保留 OpenClaw 内发光分支，颜色和绘制参数不变。
- [x] `RecordingCapsuleView` 只改内发光展示读取路径；不改外壳尺寸、边框、文本、声波、badge。
- [x] 不改闪念保存逻辑、ASR、文本缓存、最终粘贴、候选/旁路胶囊。

#### Task 6F: 迁移错误/空音频/整理中状态展示映射

**Files:**
- Modify: `native/Sources/Presentation/Capsule/MainCapsuleLegacyStatusProjection.swift`（补齐旧状态字符串到 phase 的展示投影）
- Modify: `native/Tests/MainCapsuleLegacyStatusProjectionCheck.swift`（错误/空音频/整理中状态测试）
- Test: `native/Tests/MainCapsuleStatusMigrationBoundaryCheck.sh`（状态迁移边界测试）

**Goal:** 主胶囊常见旧状态文案进入 `MainCapsulePhase`，但旧调用方、旧文案和最终交付链路不变。

- [x] 先写测试：`整理中` 投影为 `.rewriting`，render status 为 `.processing`。
- [x] 先写测试：`检测中/识别中/正在收尾/自动结束` 投影为对应处理中状态。
- [x] 先写测试：`录音失败/保存失败/识别失败` 投影为 `.failed(message:)`，显示文案保持原文。
- [x] 先写测试：`无输入已停止` 投影为 `.empty(reason:)`，显示文案保持原文。
- [x] 未列出的旧状态仍保留旧文案并退回 `.recording`，避免误改其他状态。
- [x] 不改 VAD、ASR、智能整理引擎、文本缓存、最终粘贴、Provider、Reconciler、候选/旁路胶囊。

#### Task 6G: 迁移顶部上下文展示映射

**Files:**
- Create: `native/Sources/Presentation/Capsule/MainCapsuleContextPresentation.swift`（主胶囊顶部上下文展示模型）
- Modify: `native/Sources/Presentation/Capsule/RecordingPanel.swift`（顶部信息条从上下文展示模型读取）
- Test: `native/Tests/MainCapsuleContextPresentationCheck.swift`（上下文展示模型测试）
- Test: `native/Tests/MainCapsuleContextMigrationBoundaryCheck.sh`（上下文迁移边界测试）

**Goal:** 目标 App 名、App 图标显示、模式名、自动翻译 badge 的显示值进入主胶囊展示模型；旧 `setContext/updateTargetApp/updateModeName/updateAutoTranslateEnabled` 调用保持不变。

- [x] 先写测试：空 App 名显示为 `未知应用`。
- [x] 先写测试：有/无 App 图标决定 `appIconHidden`。
- [x] 先写测试：模式名和自动翻译 badge 显示状态从 `MainCapsuleContext` 输出。
- [x] `RecordingPanel` 只改顶部信息条赋值来源，不改点击切模式、翻译开关逻辑、布局约束、字体、颜色、间距。
- [x] 不改 ASR、文本缓存、最终粘贴、Provider、Reconciler、候选/旁路胶囊。

### Task 7: 退休迁移工具

**Goal:** 主胶囊完成后，再处理旁路/候选。

#### Task 7A: 旁路/候选退休边界盘点

**Files:**
- Modify: `docs/superpowers/plans/2026-07-20-main-capsule-goal-lock.md`（本文）

**Goal:** 只盘点，不改代码；明确哪些东西是诊断工具，哪些不能进入产品态。

- [x] 确认 `ShadowPreviewSettings.defaultValue` 当前默认关闭。
- [x] 确认候选胶囊由 `candidatePreviewRuntime` 跟随旁路 runtime 启动，不是独立产品入口。
- [x] 确认 `MainViewController.experimentalPreviewSettings` 当前对业务返回 false/false，不让实验预览接管主线。
- [x] 确认 `FinalDeliveryUseCase` / `FinalRecognitionUseCase` 仍属于最终交付层，不由胶囊 View 决定。
- [x] 不改任何 UI、设置、Provider、ASR、文本缓存、最终粘贴。

#### Task 7B: 产品态隐藏迁移窗口入口

**Files:**
- Modify: `native/Sources/Presentation/Main/MainViewController+PanelLayout.swift`（设置页布局）
- Modify: `native/Sources/Presentation/Main/MainViewController+Configuration.swift`（文案/可访问性）
- Test: `native/Tests/MainCapsuleRetirementSettingsBoundaryCheck.sh`（设置入口退休边界）

**Goal:** 普通产品设置不再把旁路/候选当作产品功能展示；必要诊断入口保留为明确的实验/诊断能力。

- [x] 先写边界测试：不能出现“候选胶囊”作为产品设置入口。
- [x] 保留 `旁路预览` 的诊断定位并移动到诊断分区；不得改默认关闭。
- [x] 在线旁路仍只作为旁路诊断服务选择，不参与最终粘贴。
- [x] 不改 Shadow/Candidate runtime、Provider、ASR、文本缓存、最终粘贴。

#### Task 7C: 运行期退休门禁

**Files:**
- Create: `native/Sources/Application/RealtimeTranscription/ShadowPreviewRuntimeGate.swift`（旁路/候选运行期门禁）
- Modify: `native/Sources/Application/SpeechInputCoordinator.swift`（启动/发布前读取门禁）
- Test: `native/Tests/ShadowPreviewRuntimeGateCheck.swift`（门禁规则测试）
- Test: `native/Tests/ShadowPreviewRuntimeGateBoundaryCheck.sh`（运行期门禁边界测试）

**Goal:** 确认运行期只有主胶囊是产品主视图；旁路/候选只在诊断开关打开时出现。

- [x] 先做代码走读，再补实现细节。
- [x] 写 RED：`shadowPreviewEnabled == false` 时不得启动 shadow/candidate runtime。
- [x] 写 RED：`shadowPreviewEnabled == false` 时不得向 shadow/candidate runtime 发布快照。
- [x] 写 RED：关闭/取消后 shadow/candidate coordinator 必须 end。
- [x] 不改 Provider、ASR、文本缓存、最终粘贴。

#### Task 7D: 退休完成复审

**Goal:** Task 7B/7C 完成后复审：产品态只剩一个主预览胶囊。

- [x] 架构复审。
- [x] 计划更新。
- [x] 安装版验证。

## 8. 每次完成后必须写入计划

每个 Task 结束必须补三行：

```text
完成了什么
明确没有改什么
下一步只能做什么
```

### Task 1 完成记录 / 2026-07-20

完成了什么：

```text
完成主胶囊状态盘点，确认主胶囊现有能力不只是实时文本，还包括声波、上下文条、模式标签、自动翻译 badge、倒计时、内存/Ollama 状态、闪念、OpenClaw、错误、空录音、自动结束、长录音收尾和隐藏生命周期。
```

明确没有改什么：

```text
没有改运行代码，没有改 UI，没有改最终粘贴，没有改 Provider/Reconciler/FinalDelivery。
```

下一步只能做什么：

```text
先细化并执行 Task 2：抽 MainCapsuleState。Task 2 只能抽状态，不得改 RecordingCapsuleView 绘制，不得改最终交付链路。
```

### Task 2 完成记录 / 2026-07-20

完成了什么：

```text
新增 MainCapsuleState 纯状态模型和 MainCapsuleStateCheck 测试，把主胶囊状态先分成录音期状态、后处理状态、目的/外观状态、上下文状态和指标状态。
```

明确没有改什么：

```text
没有接入 RecordingCapsuleView，没有改 RecordingPanel，没有改最终粘贴，没有改 FinalDeliveryUseCase、Provider、Reconciler，也没有改变安装版可见行为。
```

下一步只能做什么：

```text
执行 Task 3：抽 MainCapsuleTextMotion。Task 3 只处理“文字显示到第几个字”的显示进度，不得改识别文本、不改最终粘贴。
```

### Task 3 完成记录 / 2026-07-20

完成了什么：

```text
新增 MainCapsuleTextMotion 纯文字动效进度模型和 MainCapsuleTextMotionCheck 测试，参考候选胶囊的轻量 motion 思路，只保存 target/visible/stable 字符数量，不保存文本内容。
```

明确没有改什么：

```text
没有接入 RecordingCapsuleView，没有改 CapsuleTextBuffer，没有改候选/旁路胶囊，没有改识别内容、Provider、Reconciler 或最终粘贴。
```

下一步只能做什么：

```text
执行 Task 4：抽 MainCapsuleRenderState。Task 4 只允许把 MainCapsuleState + MainCapsuleTextMotion 转成可绘制状态，不得改旧 UI 绘制行为。
```

### 架构复审记录 / 2026-07-20 / after Task 3

结论：

```text
Accepted。Task 1/2/3 没有把候选胶囊扶正，也没有把旁路变成产品主线；状态层和动效层都保持纯模型，尚未影响 UI、识别、Provider、Reconciler 或最终粘贴。
```

关键边界：

```text
Task 4 可以生成可绘制快照，但不能决定文本来源。由于 MainCapsuleState 不保存文本内容，Task 4 允许显式接收 contentText 作为输入参数；这只是渲染输入，不是接入候选/旁路/旧缓存数据源。
```

复审触发：

```text
进入 Task 5 之前，如果 Task 4 通过，需要再次确认 MainCapsuleRenderState 是否足够承接旧主胶囊视觉状态；真正修改 RecordingCapsuleView 前必须保留旧 UI 行为。
```

### Task 4 完成记录 / 2026-07-20

完成了什么：

```text
新增 MainCapsuleRenderState 纯可绘制快照和 MainCapsuleRenderStateCheck 测试，把 MainCapsuleState、contentText、MainCapsuleTextMotion 合成为 status/statusText/displayedText/visible counts/context/indicators。
```

明确没有改什么：

```text
没有接入 RecordingCapsuleView，没有改 RecordingPanel，没有改 CapsuleTextBuffer，没有改识别内容、Provider、Reconciler、候选/旁路胶囊或最终粘贴。
```

下一步只能做什么：

```text
进入 Task 5 前先复核旧主胶囊绘制入口，再拆 MainCapsuleShell。Task 5 才允许触碰 RecordingCapsuleView，但必须保持用户可见行为不变。
```

### Task 5A 完成记录 / 2026-07-20

完成了什么：

```text
新增 MainCapsuleShell 和 MainCapsuleShellCheck/MainCapsuleShellBoundaryCheck，把主胶囊外壳尺寸、圆角、本体区域、OpenClaw 外置徽章预留区域从 RecordingCapsuleView 中拆出来。
```

明确没有改什么：

```text
没有改 RecordingPanel 窗口生命周期，没有改 CapsuleTextBuffer，没有改文本内容绘制、声波绘制、OpenClaw badge 绘制、闪念/OpenClaw glow 绘制，没有改任何数据缓存、识别、Provider、Reconciler 或最终粘贴。
```

下一步只能做什么：

```text
补做 Task 5B：拆 RecordingPanel 窗口/布局外壳。不得进入 Task 6，直到 Panel 层外壳拆分完成。
```

设计复核：

```text
已按 UI 改动规则做源代码级设计复核：本轮只移动外壳尺寸/边界职责，视觉参数保持原值；未接入新 render state，安装版可见行为理论上保持不变。
```

### Task 5B 完成记录 / 2026-07-20

完成了什么：

```text
新增 MainCapsulePanelShell 和 MainCapsulePanelShellCheck/MainCapsulePanelShellBoundaryCheck，把 RecordingPanel 的窗口初始大小、屏幕宽度限制、底部居中锚点、content/capsule/material/health overlay frame 计算抽出来。
```

明确没有改什么：

```text
没有改顶部信息条内容，没有改 show/hide 动画时长和曲线，没有改胶囊内容绘制，没有改数据缓存、识别、Provider、Reconciler、候选/旁路胶囊或最终粘贴。
```

下一步只能做什么：

```text
进入 Task 6：逐状态迁移。每次只迁移一个状态；优先从语音预览文本开始，先让新状态/动效/render 模型承接展示，不得改最终粘贴。
```

设计复核：

```text
已做源代码级设计复核：Panel 只迁移窗口几何职责，保留 OpenClaw 右侧 overhang 对顶部信息条宽度的补偿，避免龙虾徽章状态下信息条被压缩。
```

### 架构复审记录 / 2026-07-20 / before Task 6A

结论：

```text
Accepted。Task 6A 只迁移主胶囊语音预览文本展示读取口，不接入候选胶囊，不接入旁路胶囊，不改变最终粘贴来源。
```

关键边界：

```text
旧 CapsuleTextBuffer 仍负责内容生成和逐字推进；MainCapsuleTextMotion 只接收旧 buffer 已经产出的 displayed/target/stable 计数；MainCapsuleRenderState 只输出 View 可画的 displayedText 和 visibleStableCharacterCount。
```

复审触发：

```text
Task 6A 完成后，下一步仍只能做 Task 6 的下一个单一状态迁移，不能顺手改数据缓存、最终交付、Provider/Reconciler 或候选/旁路产品定位。
```

### Task 6A 完成记录 / 2026-07-20

完成了什么：

```text
主胶囊语音预览文本绘制入口开始通过 MainCapsuleTextMotion + MainCapsuleRenderState 读取 displayedText 和 visibleStableCharacterCount；新增 motion 桥接初始化和迁移边界测试。
```

明确没有改什么：

```text
没有改 CapsuleTextBuffer 的内容生成、逐字 timer、裁剪缓存、淡入节奏；没有改最终粘贴、FinalDeliveryUseCase、Provider、Reconciler、候选胶囊或旁路胶囊。
```

下一步只能做什么：

```text
继续 Task 6 的下一个单一状态迁移：声波。声波迁移只允许把声波展示状态接入主胶囊 render/presentation 分层，不得改录音采集、ASR、文本缓存或最终粘贴。
```

设计复核：

```text
已做源代码级设计复核：本轮没有改尺寸、颜色、字体、圆角、位置、timer 间隔或动画参数；用户可见文本、裁剪、淡入和 stable/volatile 弱化逻辑保持原效果。
```

### Task 6B 完成记录 / 2026-07-20

完成了什么：

```text
新增 MainCapsuleWaveformMotion，把主胶囊声波平滑状态从 RecordingCapsuleView 私有 WaveformBands 迁到主胶囊展示状态；MainCapsuleRenderState 现在携带 waveformBands，View 只从 render state 读取 bands 并调用原 WaveformRenderer 绘制。
```

明确没有改什么：

```text
没有改 recorder.onBands、AudioRecorder、WaveformRenderer 折线算法、声波颜色、声波位置、文本缓存、ASR、Provider、Reconciler、最终粘贴、候选胶囊或旁路胶囊。
```

下一步只能做什么：

```text
继续 Task 6 的下一个单一状态迁移：翻译/原文。只允许迁移主胶囊对翻译/原文状态的展示映射，不得改智能整理、翻译引擎、ASR、文本缓存或最终粘贴。
```

设计复核：

```text
已做源代码级设计复核：本轮保留声波 rect、lineWidth、颜色、activity 计算和折线路径算法；用户可见声波理论上保持不变，只改变内部状态归属。
```

### Task 6C 完成记录 / 2026-07-20

完成了什么：

```text
新增 MainCapsuleLegacyStatusProjection，把旧主胶囊 state 字符串先投影成 MainCapsulePhase；当前先让“翻译中”进入 .translating，同时通过 statusTextOverride 保留旧状态显示文案。RecordingCapsuleView 的状态文字改为从 MainCapsuleRenderState.statusText 绘制。
```

明确没有改什么：

```text
没有改翻译引擎、智能整理、ASR、文本缓存、最终粘贴、Provider、Reconciler、候选胶囊或旁路胶囊；没有改状态文字的字体、颜色、位置、宽度。
```

下一步只能做什么：

```text
继续 Task 6 的下一个单一状态迁移：OpenClaw。只允许迁移 OpenClaw 的主胶囊目的/连接状态展示映射，不得改 OpenClaw 发送逻辑、回复面板、ASR、文本缓存或最终粘贴。
```

设计复核：

```text
已做源代码级设计复核：本轮只改变状态文字读取来源；旧状态文案仍按原字符串显示，避免“检测中/识别中/保存失败”等未迁移状态退化成“录音中”。
```

### 架构复审记录 / 2026-07-20 / after Task 6C

结论：

```text
Accepted。Task 6A/6B/6C 仍然只在主胶囊内部迁移展示读取口：文本、声波、状态文字都进入 MainCapsuleTextMotion/MainCapsuleWaveformMotion/MainCapsuleRenderState；没有把候选胶囊或旁路胶囊扶正为产品主线。
```

证据：

```text
复审范围 diff 为 2d3d014..HEAD；改动集中在 native/Sources/Presentation/Capsule、native/Tests/MainCapsule* 和计划/日志。边界测试禁止 FinalDeliveryUseCase、LegacyRealtimePreviewDeliveryCache、RealtimePreviewDeliveryCache、PasteCoordinator、Provider/Reconciler、ShadowPreview、CandidatePreview 进入主胶囊迁移代码。
```

下一步只能做什么：

```text
继续 Task 6D：迁移 OpenClaw 主胶囊目的/连接状态展示映射。只允许把现有 accent/openClawConnectionStatus 投影进 MainCapsuleState/MainCapsuleRenderState，不得改 OpenClaw 发送逻辑、回复面板、ASR、文本缓存或最终粘贴。
```

### Task 6D 完成记录 / 2026-07-20

完成了什么：

```text
新增 MainCapsuleOpenClawProjection，把旧 OpenClaw accent/connectionStatus 投影成 MainCapsulePurposeAppearance；RecordingCapsuleView 的 OpenClaw badge 是否显示和连接状态颜色改为从 MainCapsuleRenderState 读取。
```

明确没有改什么：

```text
没有改 OpenClaw 发送逻辑、回复面板、ASR、文本缓存、最终粘贴、Provider、Reconciler、候选胶囊或旁路胶囊；没有改龙虾 badge 几何、颜色值、阴影和绘制算法。
```

下一步只能做什么：

```text
继续 Task 6 的下一个单一状态迁移：闪念。只允许迁移闪念胶囊目的/外观状态展示映射，不得改闪念保存逻辑、ASR、文本缓存或最终粘贴。
```

设计复核：

```text
已做源代码级设计复核：本轮只改变 OpenClaw badge 的状态读取来源；badge 的 rect、overlap、top lift、palette 颜色和 lobster path 保持原值。
```

### Task 6E 完成记录 / 2026-07-20

完成了什么：

```text
新增 MainCapsulePurposeGlow，让 MainCapsuleRenderState 根据 purpose 输出闪念/OpenClaw 内发光类型；RecordingCapsuleView 的内发光显示条件改为从 render state 读取。
```

明确没有改什么：

```text
没有改闪念保存逻辑、OpenClaw 发送逻辑、ASR、文本缓存、最终粘贴、Provider、Reconciler、候选胶囊或旁路胶囊；没有改内发光颜色值、覆盖步数、透明度曲线、边框、文本、声波或 badge。
```

下一步只能做什么：

```text
继续 Task 6 的下一个单一状态迁移：错误/空音频/整理中。只允许迁移主胶囊错误/空音频/整理中状态展示映射，不得改识别、VAD、智能整理引擎、文本缓存或最终粘贴。
```

设计复核：

```text
已做源代码级设计复核：本轮只提前生成 renderState 并把内发光开关改为 renderState.purposeGlow；原 fill/stroke 颜色、steps、alpha 公式和路径绘制保持不变。
```

### Task 6F 完成记录 / 2026-07-20

完成了什么：

```text
扩展 MainCapsuleLegacyStatusProjection，把旧主胶囊常见状态文案映射到 MainCapsulePhase：整理中、检测中、识别中、正在收尾、自动结束、无输入已停止、录音失败、保存失败、识别失败。
```

明确没有改什么：

```text
没有改 VAD、ASR、智能整理引擎、文本缓存、最终粘贴、Provider、Reconciler、候选胶囊或旁路胶囊；没有改状态文字字体、颜色、位置、宽度，也没有改旧调用方传入的文案。
```

下一步只能做什么：

```text
先按“三到五次提交架构复审”规则做一次架构复审；复审通过后继续 Task 6 的下一个单一状态迁移：上下文。只允许迁移目标 App、模式名、自动翻译标记等上下文展示映射，不得改模式切换逻辑、翻译开关逻辑、ASR、文本缓存或最终粘贴。
```

设计复核：

```text
已做源代码级设计复核：本轮只改变状态文案到 phase 的投影；RecordingCapsuleView 仍从 MainCapsuleRenderState.statusText 绘制，旧状态文案通过 statusTextOverride 原样显示。
```

### 架构复审记录 / 2026-07-20 / after Task 6F

结论：

```text
Accepted。Task 6D/6E/6F 仍然只在主胶囊展示层和纯投影层内迁移：OpenClaw badge、闪念/OpenClaw 内发光、错误/空音频/整理中状态都进入 MainCapsuleRenderState 或 MainCapsuleLegacyStatusProjection；没有把候选胶囊或旁路胶囊扶正为产品主线。
```

证据：

```text
复审范围 diff 为 de5ba6a..HEAD；改动集中在 native/Sources/Presentation/Capsule、native/Tests/MainCapsule* 和计划/日志。边界测试持续禁止 FinalDeliveryUseCase、LegacyRealtimePreviewDeliveryCache、RealtimePreviewDeliveryCache、PasteCoordinator、Provider/Reconciler、ShadowPreview、CandidatePreview、OpenClawReplyPresenter、BacklogWriter、SmartRewriteEngine、SenseVoice/VAD 进入本轮迁移代码。
```

下一步只能做什么：

```text
继续 Task 6 的下一个单一状态迁移：上下文。只允许迁移目标 App、模式名、自动翻译标记等上下文展示映射，不得改模式切换逻辑、翻译开关逻辑、ASR、文本缓存、最终粘贴、候选/旁路胶囊。
```

### Task 6G 完成记录 / 2026-07-20

完成了什么：

```text
新增 MainCapsuleContextPresentation，把顶部信息条的目标 App 名、App 图标隐藏状态、模式名、自动翻译 badge 显示状态从 MainCapsuleContext 投影出来；RecordingPanel 的 setContext/updateTargetApp/updateModeName/updateAutoTranslateEnabled 改为读取该展示模型。
```

明确没有改什么：

```text
没有改点击切换模式逻辑、自动翻译开关逻辑、布局约束、字体、颜色、间距、ASR、文本缓存、最终粘贴、Provider、Reconciler、候选胶囊或旁路胶囊。
```

下一步只能做什么：

```text
进入 Task 7 前先盘点迁移工具退休边界。只允许判断旁路/候选诊断窗口的保留/隐藏策略，不得改最终交付、Provider、ASR 或文本缓存。
```

设计复核：

```text
已做源代码级设计复核：本轮只把 appName/modeName/autoTranslate/appIconHidden 的赋值来源换成 MainCapsuleContextPresentation；infoBar 的 stack 配置、字体颜色、spacing、constraints、modeTapped 回调保持不变。
```

### Task 7A 完成记录 / 2026-07-20

完成了什么：

```text
完成旁路/候选退休边界盘点：旁路设置当前默认关闭；候选胶囊跟随旁路 runtime 启动，不是独立产品入口；experimentalPreviewSettings 当前对业务返回 false/false；最终交付仍在 FinalDeliveryUseCase / FinalRecognitionUseCase，不由胶囊 View 决定。
```

明确没有改什么：

```text
没有改运行代码、UI、设置、Provider、ASR、文本缓存、最终粘贴、候选胶囊或旁路胶囊。
```

下一步只能做什么：

```text
继续 Task 7B：产品态隐藏迁移窗口入口。只允许调整设置页里旁路/候选相关入口的产品定位和显示边界，不得改 Shadow/Candidate runtime、Provider、ASR、文本缓存或最终粘贴。
```

### Task 7B 完成记录 / 2026-07-20

完成了什么：

```text
设置页“录音与预览”中，普通产品项只保留胶囊实时预览、停顿自动完成、停止后重新识别整段录音、录音时降低系统音量；旁路预览、在线旁路、豆包/MiMo Key 移入“诊断工具（实验）”分区，并把旁路/在线旁路文案标注为诊断。
```

明确没有改什么：

```text
没有改 Shadow/Candidate runtime、默认关闭策略、在线旁路选择保存逻辑、Provider、ASR、文本缓存、最终粘贴、候选胶囊或旁路胶囊。
```

下一步只能做什么：

```text
继续 Task 7C：运行期退休门禁。先做代码走读并写 RED，确认 shadowPreviewEnabled == false 时不会启动 shadow/candidate runtime，关闭/取消后 coordinator 会 end；不得改 Provider、ASR、文本缓存或最终粘贴。
```

设计复核：

```text
已做源代码级设计复核：本轮只调整设置页分组、行标题和 accessibility label；没有改控件实例、target/action、保存方法、布局基础组件、字体、颜色或 spacing。
```

### Task 7C 完成记录 / 2026-07-20

完成了什么：

```text
新增 ShadowPreviewRuntimeGate，把旁路/候选运行期启动和快照发布门禁收口为可测试规则；SpeechInputCoordinator 的 beginShadowPreview 和 publishShadowPreview 改为先读取该门禁。
```

明确没有改什么：

```text
没有改 Shadow/Candidate runtime 实现、Provider、ASR、文本缓存、最终粘贴、候选/旁路窗口绘制、关闭/取消 teardown 流程。
```

下一步只能做什么：

```text
继续 Task 7D：退休完成复审。只做架构复审、计划更新和安装版验证；不得顺手改 Provider、ASR、文本缓存或最终粘贴。
```

设计复核：

```text
本轮无视觉改动；运行期行为保持原语义，只把 controller.shadowPreviewEnabled 和 runtime 存在性判断从散落 guard 抽成 ShadowPreviewRuntimeGate。
```

### Task 7D 完成记录 / 2026-07-20

完成了什么：

```text
完成退休完成复审：主胶囊重构和旁路/候选退休边界均保持目标锁。普通产品设置中旁路/在线旁路已进入“诊断工具（实验）”；ShadowPreviewSettings 默认关闭；运行期由 ShadowPreviewRuntimeGate 阻止关闭时启动或发布；候选胶囊仍跟随旁路 runtime，不是独立产品入口。
```

明确没有改什么：

```text
没有改最终交付、FinalDeliveryUseCase、FinalRecognitionUseCase、Provider、ASR、文本缓存、Shadow/Candidate runtime 实现、候选/旁路窗口绘制。
```

下一步只能做什么：

```text
如果继续开发，应进入 Stage A：预览数据层统一。进入 Stage A 前必须重新读本文，并重新拆 Task；不得在主胶囊重构 Task 内继续顺手改最终交付或 Provider。
```

架构复审：

```text
Accepted。Task 6G/7A/7B/7C 没有把候选/旁路扶正为产品主线；上下文展示进入 MainCapsuleContextPresentation；迁移窗口入口进入诊断分区；运行期开关进入 ShadowPreviewRuntimeGate。产品态只剩主胶囊，诊断态仍可显式打开旁路/候选。
```

### Task A0 完成记录 / 2026-07-20

完成了什么：

```text
细化 Stage A 预览数据层统一计划，明确当前主胶囊生产文字进料仍借用 beginShadowPreview 内的 shadow/candidate runtime 状态流；下一步必须先把主胶囊生产数据源从旁路诊断开关下拆出来。
```

明确没有改什么：

```text
没有改 Swift 运行代码，没有改 UI，没有改 Provider、ASR、文本缓存、最终粘贴或旁路/候选 runtime。
```

下一步只能做什么：

```text
执行 Task A1：抽 ProductionPreviewStateBridge。A1 必须在同一 Task 内完成 RED→GREEN，不提交失败测试；目标是关闭旁路诊断时主胶囊仍能正常接收实时文字状态。
```

### Task A1 完成记录 / 2026-07-20

完成了什么：

```text
新增 ProductionPreviewStateBridge，把旧实时预览的 PreviewDisplaySnapshot 独立转换为 PreviewViewState 供主胶囊订阅；SpeechInputCoordinator 录音开始时总是启动生产主胶囊状态流，旁路/候选 runtime 仍只受 ShadowPreviewRuntimeGate 诊断开关控制。
```

明确没有改什么：

```text
没有改胶囊 View 绘制，没有改 Provider、ASR、文本识别策略、最终粘贴、FinalDeliveryUseCase、候选/旁路窗口绘制或诊断开关默认值。
```

下一步只能做什么：

```text
执行 Task A2：把 PreviewViewState → PreviewDisplaySnapshot 投影命名中性化，收敛到 PreviewDisplaySnapshotProjector；不得在 A2 改最终粘贴或 Provider。
```

### Task A2 完成记录 / 2026-07-20

完成了什么：

```text
新增 PreviewDisplaySnapshotProjector，把 PreviewViewState → PreviewDisplaySnapshot 的投影从 ProductionPreviewTextCoordinator 文件中抽出；ProductionPreviewTextCoordinator 改为使用中性的 projector。
```

明确没有改什么：

```text
没有改投影行为、用户可见文本、UI 绘制、Provider、ASR、最终粘贴、旁路/候选 runtime 或诊断开关。
```

下一步只能做什么：

```text
执行 Task A3：统一三类预览订阅边界。A3 只能整理主胶囊/旁路/候选谁订阅什么，不得改状态内容、Provider 或最终粘贴。
```

### 架构复审记录 / 2026-07-20 / after Task A2

结论：

```text
Accepted。Task A0/A1/A2 修正了生产主胶囊实时文字状态流借用旁路/候选 runtime 的结构问题；现在主胶囊通过 ProductionPreviewStateBridge 获取生产 PreviewViewState，旁路/候选仍由 ShadowPreviewRuntimeGate 控制为诊断路径。
```

证据：

```text
复审范围为 1961e7d..HEAD。改动集中在 ProductionPreviewStateBridge、PreviewDisplaySnapshotProjector、ProductionPreviewTextCoordinator、SpeechInputCoordinator glue、测试和文档。没有修改 Provider、ASR、FinalDeliveryUseCase、FinalRecognitionUseCase、PasteCoordinator 或胶囊 View 绘制。
```

风险：

```text
SpeechInputCoordinator 仍是生产/诊断订阅 glue 的集中点；A3 需要继续把三类订阅者边界写成测试，避免未来又把主胶囊进料绑回旁路/候选。
```

下一步：

```text
执行 Task A3：统一三类预览订阅边界。只允许写订阅边界和测试，不允许改 Provider、ASR、最终粘贴或 UI 文本修补。
```

### Task A3 完成记录 / 2026-07-20

完成了什么：

```text
新增 PreviewSubscribersBoundaryCheck，把主胶囊生产订阅、旁路诊断订阅、候选诊断订阅的边界写成源码门禁；同时移除了 ProductionPreviewTextCoordinator 注释中对候选协调器的参照。
```

明确没有改什么：

```text
没有改运行 glue、状态模型、Provider、ASR、最终粘贴、胶囊 View 绘制、旁路/候选 runtime 或诊断开关。
```

下一步只能做什么：

```text
执行 Task A4：Stage A 完成复审。A4 只做复审和文档记录；若复审通过，下一阶段才允许进入 Stage B 交付缓存统一。
```

### Task A4 完成记录 / 2026-07-20

完成了什么：

```text
完成 Stage A 预览数据层统一复审：主胶囊生产状态流已从旁路/候选诊断 runtime 拆出；PreviewViewState → PreviewDisplaySnapshot 投影已中性化；三类预览订阅边界已有源码门禁。
```

明确没有改什么：

```text
没有改 Swift 运行代码，没有改 UI，没有改 Provider、ASR、最终粘贴、FinalDeliveryUseCase、候选/旁路 runtime 或诊断开关。
```

下一步只能做什么：

```text
如果继续开发，应先细化 Stage B：交付缓存统一。Stage B 涉及最终粘贴来源，开工前必须重新读本文、读旧交付缓存相关代码，并拆成小 Task。
```

### Task B0 完成记录 / 2026-07-20

完成了什么：

```text
细化 Stage B 交付缓存统一计划，确认当前最终交付缓存链路是 PreviewDisplaySnapshot → LegacyRealtimePreviewDeliveryCache → CandidateDeliverySnapshot → FinalDeliveryUseCase；Stage B 的第一目标是命名和职责收敛，不是改变最终粘贴策略。
```

明确没有改什么：

```text
没有改运行代码，没有改 UI，没有改 Provider、ASR、最终粘贴选择、FinalDeliveryUseCase 行为或旁路/候选 runtime。
```

下一步只能做什么：

```text
执行 Task B1：新增中性的 RealtimePreviewDeliveryCache。B1 只新增类型和测试，不接入运行路径、不改变最终粘贴策略。
```

### Task B1 完成记录 / 2026-07-20

完成了什么：

```text
新增 RealtimePreviewDeliveryCache 和 RealtimePreviewDeliveryCacheCheck；新缓存行为与旧 LegacyRealtimePreviewDeliveryCache 一致，仍只保存 PreviewDisplaySnapshot.stableWindowText + volatileTailText，并通过 deliverySnapshot() 返回可交付快照。
```

明确没有改什么：

```text
没有接入运行路径，没有替换 ShadowTranscriptionRuntime 字段，没有改最终粘贴选择策略、FinalDeliveryUseCase、Provider、ASR、UI 或旁路/候选 runtime。
```

下一步只能做什么：

```text
执行 Task B2：把 ShadowTranscriptionRuntime 内部缓存字段切到 RealtimePreviewDeliveryCache。B2 只能替换内部缓存类型和字段名，不改 FinalDeliveryUseCase。
```

### 架构复审记录 / 2026-07-20 / after Task B1

结论：

```text
Accepted。Task B0/B1 只是把交付缓存统一目标拆细，并新增行为等价的 RealtimePreviewDeliveryCache；运行路径仍使用 LegacyRealtimePreviewDeliveryCache，最终粘贴选择策略未改变。
```

证据：

```text
复审范围为 028ab60..HEAD。改动包含 Stage B 计划、RealtimePreviewDeliveryCache、缓存测试、订阅边界测试和文档。FinalDeliveryUseCase、FinalRecognitionUseCase、PasteCoordinator、Provider、ASR、胶囊 View 均未改。
```

下一步：

```text
允许执行 Task B2：ShadowTranscriptionRuntime 内部缓存字段切到 RealtimePreviewDeliveryCache。B2 禁止修改 FinalDeliveryUseCase 入参、选择策略、Provider、ASR 或 UI。
```

### Task B2 完成记录 / 2026-07-20

完成了什么：

```text
ShadowTranscriptionRuntime 内部缓存字段从 legacyDeliveryCache / LegacyRealtimePreviewDeliveryCache 切换为 realtimePreviewDeliveryCache / RealtimePreviewDeliveryCache；新增 RealtimePreviewDeliveryCacheWiringCheck 锁定接线。
```

明确没有改什么：

```text
没有改 FinalDeliveryUseCase 入参或选择策略，没有改 CandidateDeliverySnapshot 返回类型，没有改 Provider、ASR、UI、最终粘贴或旁路/候选窗口。
```

下一步只能做什么：

```text
执行 Task B3：FinalDeliveryUseCase 入参命名去候选化。B3 只能改命名和调用点，不得改选择条件或最终文本。
```

### Task B3 完成记录 / 2026-07-20

完成了什么：

```text
FinalDeliveryUseCase.deliver 入参从 legacyCandidateSnapshot 改为 realtimePreviewDeliverySnapshot；SpeechInputCoordinator、CandidateDeliverySnapshot.selectForFinalDelivery 和相关测试同步命名。
```

明确没有改什么：

```text
没有改最终选择条件、最终文本、FinalRecognitionUseCase 的 candidatePreviewCacheText 字段、Provider、ASR、UI 或旁路/候选 runtime。
```

下一步只能做什么：

```text
执行 Task B4：最终交付日志说明真实来源。B4 只允许改日志 source/reason 文案，不得改最终选择策略。
```

### Task B4 完成记录 / 2026-07-20

完成了什么：

```text
最终交付选择实时预览缓存时，FinalDeliveryUseCase.reason 现在明确包含 realtime_preview_delivery_cache；新增 FinalDeliveryLogBoundaryCheck 锁定 final_delivery_selected 日志仍输出 source/reason。
```

明确没有改什么：

```text
没有改最终选择策略、最终文本、engine/source 值、Provider、ASR、UI、FinalRecognitionUseCase 或旁路/候选 runtime。
```

下一步只能做什么：

```text
执行 Task B5：退休 LegacyRealtimePreviewDeliveryCache 旧名。B5 只允许删除旧缓存类型/旧测试名，不得改行为。
```

### 架构复审记录 / 2026-07-20 / after Task B4

结论：

```text
Accepted。Task B2/B3/B4 仍在 Stage B 边界内：运行路径已切到 RealtimePreviewDeliveryCache，FinalDeliveryUseCase 入参命名已去候选化，日志 reason 已说明 realtime_preview_delivery_cache；最终选择策略和最终文本未改。
```

证据：

```text
复审范围为 1b16732..HEAD。改动集中在 ShadowTranscriptionRuntime 缓存字段、FinalDeliveryUseCase 入参/日志文案、SpeechInputCoordinator 调用点、边界测试和文档。未修改 Provider、ASR、PasteCoordinator、胶囊 View 或 FinalRecognitionUseCase 选择逻辑。
```

下一步：

```text
允许执行 Task B5：删除 LegacyRealtimePreviewDeliveryCache 旧名和旧测试名。B5 禁止修改 RealtimePreviewDeliveryCache 行为、FinalDeliveryUseCase 选择策略、Provider、ASR 或 UI。
```

### Task B5 完成记录 / 2026-07-20

完成了什么：

```text
删除 LegacyRealtimePreviewDeliveryCache.swift 和 LegacyRealtimePreviewDeliveryCacheCheck.swift；新增 RealtimePreviewDeliveryCacheRetirementCheck，确保运行源码中旧缓存类型已退休。
```

明确没有改什么：

```text
没有改 RealtimePreviewDeliveryCache 行为，没有改 FinalDeliveryUseCase 选择策略、最终文本、Provider、ASR、UI 或旁路/候选 runtime。
```

下一步只能做什么：

```text
执行 Task B6：Stage B 完成复审。B6 只做复审、验证和文档记录；若通过，下一阶段才允许进入 Stage C Provider 接口统一。
```

### Task B6 完成记录 / 2026-07-20

完成了什么：

```text
完成 Stage B 交付缓存统一复审：运行源码中只保留 RealtimePreviewDeliveryCache 作为实时预览交付缓存；FinalDeliveryUseCase 入参和 reason 已明确指向 realtime_preview_delivery_cache；最终粘贴仍不依赖任何胶囊 View。
```

明确没有改什么：

```text
没有改 Swift 运行代码，没有改最终选择策略、最终文本、Provider、ASR、UI、FinalRecognitionUseCase 或旁路/候选 runtime。
```

下一步只能做什么：

```text
如果继续开发，应先细化 Stage C：Provider 接口统一。Stage C 会涉及本地、MiMo、豆包事件语义，开工前必须重新读本文、读 Provider 相关代码，并拆成小 Task。
```

### Task C0 完成记录 / 2026-07-20

完成了什么：

```text
细化 Stage C Provider 接口统一计划，确认当前不是从零重写 Provider，而是先固定事件语义边界：文本产出、终止事件、诊断/连接事件分开。
```

明确没有改什么：

```text
没有改运行代码，没有改 UI，没有改 Provider 行为，没有改最终交付或粘贴策略。
```

下一步只能做什么：

```text
执行 Task C1：固定 Provider 文本事件分类合同。C1 只允许新增纯事件分类合同和测试，不得改 Provider 行为、UI 或最终粘贴。
```

### Task C1 完成记录 / 2026-07-20

完成了什么：

```text
新增 TranscriptionProviderEventContract 和 TranscriptionProviderEventContractCheck，把现有 TranscriptionEvent 明确分为 text_output、terminal、diagnostic 三类；partial/finalized/reconciled 属于文本产出，completed/failed/cancelled 属于终止相关，connectionChanged 只属于诊断。
```

明确没有改什么：

```text
没有改 SenseVoiceSnapshotProvider、MiMoSnapshotProvider、OnlineTranscriptionProvider 的输出行为；没有改主胶囊、候选/旁路胶囊、FinalDeliveryUseCase 或 PasteCoordinator。
```

下一步只能做什么：

```text
执行 Task C2：固定 Provider 输出边界测试。C2 只新增边界测试，不改业务逻辑。
```

### Task C2 完成记录 / 2026-07-20

完成了什么：

```text
新增 TranscriptionProviderBoundaryCheck，锁住 Provider 与 UI/最终交付的边界：Provider 文件不得引用胶囊 UI、FinalDeliveryUseCase、PasteCoordinator；胶囊/候选/旁路 UI 不得引用具体 Provider 实现或 Provider 事件合同。
```

明确没有改什么：

```text
没有改 Provider 输出行为，没有改主胶囊、候选/旁路胶囊、最终交付、粘贴、ASR 或在线模型接入。
```

下一步只能做什么：

```text
执行 Task C3：盘点 SenseVoice、MiMo、豆包三类 Provider 的实际事件序列差异。C3 只做代码走读和计划补充，不直接改 Provider。
```

### Task C3 完成记录 / 2026-07-20

完成了什么：

```text
完成三类 Provider 事件序列盘点：SenseVoice 在 fast/correction 完成后输出 reconciled，必要时输出 recoverable failed，收尾 drained 后 completed；MiMo 在 snapshot 过程中输出 partial，完成快照后输出 finalized + partial，收尾时 finalized/empty partial + completed，失败时 failed；豆包经 OnlineTranscriptionProvider 输出 connectionChanged、partial、finalized、completed、failed。
```

明确没有改什么：

```text
没有改 SenseVoice、MiMo、豆包 Provider 行为，没有改主胶囊、候选/旁路胶囊、最终交付、粘贴或 ASR。
```

下一步只能做什么：

```text
跳过 Task C4 的新增适配层实现，直接进入 Task C5：Stage C 完成复审。原因是现有 TranscriptionSession/TranscriptReducer 已能消费这些事件，C1 的分类合同足以统一语义边界；强行把 reconciled 拆成 finalized+partial 反而可能破坏原子更新。
```

### Task C4 跳过记录 / 2026-07-20

完成了什么：

```text
C3 结论为当前不需要新增 Provider 事件适配层；Stage C 暂以 TranscriptionProviderEventContract 作为统一语义边界。
```

明确没有改什么：

```text
没有新增 Adapter，没有改 Provider 输出事件，没有改 UI 或最终粘贴。
```

下一步只能做什么：

```text
执行 Task C5：Stage C 完成复审。
```

### Task C5 完成记录 / 2026-07-20

完成了什么：

```text
完成 Stage C 架构复审。结论 Accepted：当前三类 Provider 已被统一到 TranscriptionProviderEventContract 的 text_output / terminal / diagnostic 分类边界；UI 和最终交付不感知具体 Provider。保留 reconciled 是合理的，因为它表达本地边界校准后的 stable+volatile 原子更新，强行拆成 finalized+partial 有闪烁和顺序风险。
```

明确没有改什么：

```text
没有改 Provider 行为，没有新增 Adapter，没有改主胶囊、候选/旁路胶囊、最终交付、粘贴、ASR 或在线模型接入。
```

下一步只能做什么：

```text
如果继续开发，应进入 Stage D：识别质量层。Stage D 涉及重复字、丢尾巴、分段拼接、幻觉文本，开工前必须重新读本文、读质量层/Reducer/Provider 相关代码，并拆成小 Task；不得在 UI 层修文本。
```

### Task D0 完成记录 / 2026-07-20

完成了什么：

```text
细化 Stage D 识别质量层计划，确认当前已有 SenseVoiceBoundaryReconciler、CandidateTranscriptQualityGate、FinalRecognitionUseCase、tailGapMilliseconds 等质量治理点；Stage D 后续按重复字、分段错拼、尾部丢字、幻觉文本、final ASR 短缺逐项治理。
```

明确没有改什么：

```text
没有改运行代码，没有改 UI，没有改 Provider 行为，没有改最终交付或粘贴策略。
```

下一步只能做什么：

```text
执行 Task D1：建立识别质量问题矩阵。D1 只允许补充计划和验收样例，不改代码。
```

### Task D1 完成记录 / 2026-07-20

完成了什么：

```text
新增 Stage D 识别质量问题矩阵，把短距离重复字、分段错拼、尾部丢字、静音/噪声幻觉、final ASR 短缺、语义误识别分别归到质量层、seam/reconciler、Provider stop-tail、FinalRecognitionUseCase、FinalDeliveryUseCase 或模型/诊断评估。
```

明确没有改什么：

```text
没有改运行代码，没有改 UI，没有改 Provider 行为，没有改最终交付或粘贴策略。
```

下一步只能做什么：

```text
执行 Task D2：固定质量层边界测试。D2 只新增边界测试，防止修字逻辑进入 View/Presenter/胶囊。
```

### Task D2 完成记录 / 2026-07-20

完成了什么：

```text
新增 RealtimeRecognitionQualityBoundaryCheck，锁住胶囊/候选/旁路 UI 不得引用 CandidateTranscriptQualityGate、SenseVoiceBoundaryReconciler、FinalRecognitionUseCase、FinalDeliveryUseCase、文本清洗函数或已知质量坏例。
```

明确没有改什么：

```text
没有改识别文本，没有改 UI，没有改 Provider 行为，没有改最终交付或粘贴策略。
```

下一步只能做什么：

```text
执行 Task D3：补重复字质量测试。D3 必须先写真实坏例 RED，再在数据/质量层处理；不得在 UI 层修“体验验”“设计计”。
```

### Task D3 完成记录 / 2026-07-20

完成了什么：

```text
补充 CandidateTranscriptQualityGateCheck 的真实重复字样例：`代码设计计排查一下。` 必须被判为 repeatedShortUnit；`我们好好看看这个问题。` 必须允许通过，避免误杀真实口语重复。
```

明确没有改什么：

```text
没有改生产算法。现有 CandidateTranscriptQualityGate 已能覆盖本轮样例；没有改 UI、Provider、最终交付或粘贴策略。
```

下一步只能做什么：

```text
执行 Task D4：补分段错拼质量测试。D4 只允许先补 SenseVoiceContentSeamVerificationCheck 的真实错拼样例，再决定是否需要改 seam/reconciler。
```

### 架构复审记录 / 2026-07-20 / after Task D3

结论：

```text
Accepted。Stage D 当前仍在质量层边界内：D0/D1 只做计划和矩阵，D2 锁住 UI 不得修文本，D3 只补 CandidateTranscriptQualityGate 真实样例测试且未改生产算法。没有把“体验验/设计计”修补逻辑写入 View、Presenter 或胶囊。
```

关键边界：

```text
D4 可以继续补 seam/reconciler 测试，但只能触碰 SenseVoiceContentSeamVerificationCheck 和必要的 Reconciler 质量逻辑；不得改主胶囊、候选/旁路胶囊、FinalDeliveryUseCase 或 Provider 运行策略。
```

复审触发：

```text
D4/D5 任一项需要修改生产算法时，必须先确认失败测试确实复现真实质量问题；D5 如果涉及 stop-tail 调度或缓存，完成后需要再次架构复审。
```

### Task D4 完成记录 / 2026-07-20

完成了什么：

```text
补充 SenseVoiceContentSeamVerificationCheck 的真实错拼样例：`今天我们讨论公司能` + `功功能可以优化` 不得稳定成 `公司能功功能`；同时把该测试改成 @main，后续可稳定用 swiftc 跑。
```

明确没有改什么：

```text
没有改生产算法。现有 SenseVoiceBoundaryReconciler 已能覆盖本轮样例；没有改 UI、Provider、最终交付或粘贴策略。
```

下一步只能做什么：

```text
执行 Task D5：补停止尾部覆盖测试。D5 如果发现需要改 stop-tail 调度或缓存，必须先有失败测试，再改 Provider/调度/缓存层，不能靠 UI 固定等待。
```

### Task D5 完成记录 / 2026-07-20

完成了什么：

```text
复核并运行现有 SenseVoiceCoverageDiagnosticsCheck，确认它已经覆盖 stop-tail：finish 后必须进入 completed，必须有成功识别，audioDurationMilliseconds 必须等于输入时长，tailGapMilliseconds 必须等于总时长减最后识别覆盖点，且停止后尾部覆盖差必须 <= 500ms。
```

明确没有改什么：

```text
没有改生产算法，也没有新增 UI 等待。现有 SenseVoiceSnapshotProvider 的 finish/stop-tail 覆盖测试已通过；没有改 Provider 行为、最终交付或粘贴策略。
```

下一步只能做什么：

```text
执行 Task D6：Stage D 完成复审。D6 只做架构复审、验证和计划记录。
```

### Task D6 完成记录 / 2026-07-20

完成了什么：

```text
完成 Stage D 架构复审。结论 Accepted：重复字、分段错拼、尾部覆盖、幻觉/空结果、final ASR 短缺都已有对应质量层或交付层测试；UI 层通过 RealtimeRecognitionQualityBoundaryCheck 锁住，不参与修文本。
```

明确没有改什么：

```text
Stage D 没有把识别质量修补放进主胶囊、候选胶囊、旁路胶囊、View 或 Presenter；没有改 Provider 运行策略、最终交付选择或粘贴策略。
```

下一步只能做什么：

```text
如果继续开发，应进入 Stage E：诊断与验收层。Stage E 的目标是让每次录音都能从日志解释预览来源、最终粘贴来源、fallback 原因和质量判断。
```

### Task E0 完成记录 / 2026-07-20

完成了什么：

```text
细化 Stage E 诊断与验收层计划，确认当前已有 candidate_delivery_cache、final_delivery_selected、final_asr_result/final_asr_empty、shadow_sensevoice_summary、shadow_online_summary、paste_drain 等日志；Stage E 后续目标是把这些日志串成单次录音解释链。
```

明确没有改什么：

```text
没有改运行代码，没有改 UI，没有改 Provider 行为，没有改最终交付或粘贴策略。
```

下一步只能做什么：

```text
执行 Task E1：固定诊断日志边界测试。E1 只新增边界测试，不改业务逻辑。
```

### Task E1 完成记录 / 2026-07-20

完成了什么：

```text
新增 RealtimeRecognitionDiagnosticsBoundaryCheck，锁住单次录音解释链的关键日志：candidate_delivery_cache、final_delivery_selected(source/reason)、final_asr_result/final_asr_empty、shadow_sensevoice_summary(tail_gap_ms/seam_confidence)、shadow_online_summary、paste_drain，以及 FinalDeliveryUseCase 的 quality/realtime_preview_delivery_cache reason。
```

明确没有改什么：

```text
没有改运行代码，没有改 UI，没有改 Provider 行为，没有改最终交付或粘贴策略。
```

下一步只能做什么：

```text
执行 Task E2：建立单次录音解释链矩阵。E2 只写计划和字段矩阵，不改代码。
```

### Task E2 完成记录 / 2026-07-20

完成了什么：

```text
新增 Stage E 单次录音解释链矩阵，把录音开始、VAD/自动结束、实时预览缓存、本地旁路诊断、在线旁路诊断、最终交付选择、final ASR 结果、粘贴结果逐项映射到现有日志和必要字段。
```

明确没有改什么：

```text
没有改运行代码，没有新增散乱日志，没有改 UI、Provider、最终交付或粘贴策略。
```

下一步只能做什么：

```text
执行 Task E3：如缺字段，补最小诊断字段。E3 必须先针对矩阵中的缺口写 RED；如果判断不需要补代码，则跳过 E3。
```

### 架构复审记录 / 2026-07-20 / after Task E2

结论：

```text
Accepted。Stage E 当前没有新增散乱运行日志，先用 E1 边界测试锁住已有关键日志，再用 E2 矩阵串成单次录音解释链；方向符合“不用猜来源/原因”的目标。
```

关键边界：

```text
E3 只能补矩阵中明确缺失且会影响排查的问题字段；不得为了日志完整性改最终交付策略、Provider 运行策略或 UI 展示。
```

复审触发：

```text
如果 E3 修改 SpeechInputCoordinator 或 Provider 运行日志字段，完成后需要跑诊断边界测试；如果累计再到 3~5 次提交，继续架构复审。
```

### Task E3 跳过记录 / 2026-07-20

完成了什么：

```text
复核 E2 矩阵后确认：当前用于解释“预览来自哪里、最终粘贴来自哪里、为什么选它”的关键字段已存在并被 RealtimeRecognitionDiagnosticsBoundaryCheck 锁住。在线 summary 中 `connect_ms/first_text_ms/sent_audio_ms=-1` 属于性能体验诊断，不影响本阶段来源/原因解释，暂不补运行代码。
```

明确没有改什么：

```text
没有改运行日志格式，没有改 UI，没有改 Provider、最终交付或粘贴策略。
```

下一步只能做什么：

```text
执行 Task E4：真实验收矩阵。E4 只写用户手测路径和日志证据，不改代码。
```

### Task E4 完成记录 / 2026-07-20

完成了什么：

```text
新增 Stage E 真实验收矩阵，覆盖本地短句、本地重复字坏例、seam 错拼坏例、尾部收尾、MiMo 在线旁路、在线关闭 fallback、粘贴目标验证，并为每条路径写清胶囊行为、最终交付行为和必看日志。
```

明确没有改什么：

```text
没有改运行代码，没有改 UI，没有改 Provider 行为，没有改最终交付或粘贴策略。
```

下一步只能做什么：

```text
执行 Task E5：Stage E 完成复审。E5 只做架构复审、验证和计划记录。
```

### Task E5 完成记录 / 2026-07-20

完成了什么：

```text
完成 Stage E 架构复审。结论 Accepted：诊断边界测试已锁住关键日志，解释链矩阵和真实验收矩阵已覆盖预览来源、Provider 诊断、质量判断、最终交付、粘贴目标；当前可以做到“看日志定位问题属于 Provider、质量层、交付层还是 UI 层”。
```

明确没有改什么：

```text
没有新增运行日志字段，没有改 UI、Provider、最终交付或粘贴策略。
```

下一步只能做什么：

```text
主胶囊重构目标锁当前完成到 Stage E。后续如果继续产品化收口，应进入“退休临时诊断入口/真实安装版验收/发布前整理”阶段，开工前必须重新读本文并拆新 Stage。
```

### Task F0 完成记录 / 2026-07-20

完成了什么：

```text
新增 Stage F 产品化收口计划，明确收口阶段只做旁路/候选诊断入口复核、真实安装版验收清单、发布前风险清单和完成复审。
```

明确没有改什么：

```text
没有改运行代码，没有改 UI，没有改 Provider 行为，没有改最终交付或粘贴策略。
```

下一步只能做什么：

```text
执行 Task F1：临时诊断入口复核。F1 只运行边界测试并记录结论，不改运行代码。
```

### Task F1 完成记录 / 2026-07-20

完成了什么：

```text
完成临时诊断入口复核：MainCapsuleRetirementSettingsBoundaryCheck、ShadowPreviewRuntimeGateBoundaryCheck、RealtimeRecognitionDiagnosticsBoundaryCheck 均通过。当前默认产品态仍由主胶囊承载，旁路/候选仍被锁定为诊断能力。
```

明确没有改什么：

```text
没有改运行代码，没有改 UI，没有改 Provider 行为，没有改最终交付或粘贴策略。
```

下一步只能做什么：

```text
执行 Task F2：真实安装版验收清单。F2 只整理自动测试项、真实安装版手测项和需要用户环境/Key 的验收项，不改代码。
```

### Task F2 完成记录 / 2026-07-20

完成了什么：

```text
新增 Stage F 真实安装版验收清单，把已自动验证项、必须真实安装版手测项、需要用户环境/Key 的项目拆开，避免把自动边界测试误当成真实录音验收。
```

明确没有改什么：

```text
没有改运行代码，没有改 UI，没有改 Provider 行为，没有改最终交付或粘贴策略。
```

下一步只能做什么：

```text
执行 Task F3：发布前风险清单。F3 只记录剩余风险和未验证事项，不改代码。
```

### Task F3 完成记录 / 2026-07-20

完成了什么：

```text
新增 Stage F 发布前风险清单，记录 MiMo 在线性能字段占位、真实长录音仍需安装版手测、语义误识别不能靠规则无损修正、候选/旁路诊断入口仍存在、视觉/动效未本轮重新录屏验证等风险。
```

明确没有改什么：

```text
没有改运行代码，没有改 UI，没有改 Provider 行为，没有改最终交付或粘贴策略。
```

下一步只能做什么：

```text
执行 Task F4：Stage F 完成复审。F4 只做架构复审、关键边界测试和计划记录。
```

### Task F4 完成记录 / 2026-07-20

完成了什么：

```text
完成 Stage F 产品化收口复审。结论 Accepted：默认产品态仍只保留主胶囊；旁路/候选仍被锁定为诊断能力；自动边界测试、真实安装版验收清单和发布前风险清单均已落地。
```

明确没有改什么：

```text
没有改运行代码，没有改 UI，没有改 Provider 行为，没有改最终交付或粘贴策略。
```

下一步只能做什么：

```text
当前主胶囊重构目标锁从 Stage A 到 Stage F 已完成。下一步不应继续加功能；应按 F2 清单做真实安装版手测，或进入发布/合并准备。
```

## 9. 回滚规则

如果出现以下情况，停止继续叠补丁：

- 主胶囊显示变慢。
- 原有龙虾/闪念/翻译状态坏掉。
- 最终粘贴来源变得说不清。
- 候选/旁路又变成产品主线。
- 一个 Task 需要同时改三层以上。

处理方式：

```text
回滚当前 Task
更新本文原因
重新拆小 Task
```

## 10. 主胶囊完成后的整体架构路线

主胶囊重构只是第一段。主胶囊 OK 后，还必须继续收敛下面 5 层，否则只是 UI 变清楚，系统仍会被多缓存、多来源拖住。

### Stage A: 预览数据层统一

**目标:**

```text
统一 stable / volatile / finalized 状态
```

**要处理:**

- `PreviewViewState`（统一预览状态）
- `PreviewDisplaySnapshot`（旧胶囊快照）
- 旧 realtime preview 状态
- shadow/candidate runtime 状态

**验收:**

```text
主胶囊、候选观察窗、旁路诊断窗可以订阅同一份状态投影
但只有主胶囊是产品 UI
```

**禁止:**

```text
禁止为了统一数据层顺手改最终粘贴策略
```

#### Stage A 当前代码判断 / 2026-07-20

```text
当前生产主胶囊文字进料仍借用了 shadow/candidate runtime 的状态流：beginShadowPreview(...) 里启动 runtime 后，ProductionPreviewTextCoordinator 才开始订阅 PreviewViewState；applyRealtimePreview(...) / applyExperimentalPreviewState(...) 只 publishShadowPreview(productSnapshot)，不再直接喂 popup.updateDraft(snapshot)。

这说明主胶囊已经有展示层分层，但生产数据源还没有真正独立：旁路诊断开关不应该决定主胶囊有没有实时文字状态。
```

#### Task A0: Stage A 入口边界钉死

**Files:**
- Modify: `docs/superpowers/plans/2026-07-20-main-capsule-goal-lock.md`（本文）

**Goal:** 只写 Stage A 执行边界，不改运行行为；先把“主胶囊生产数据源不得依赖旁路诊断开关”钉死，避免后续继续绕。

**Interfaces:**
- `ProductionPreviewTextCoordinator.begin(states:)`（主胶囊文字进料口）
- `ShadowPreviewRuntimeGate.shouldStart(isEnabled:)`（旁路/候选诊断门禁）
- `SpeechInputCoordinator.beginShadowPreview(taskID:)`（当前混在一起的启动入口）

- [x] 本 Task 改的是数据入口边界测试，不改 UI。
- [x] 本 Task 不改变用户可见行为。
- [x] 本 Task 不影响最终粘贴来源。
- [x] 本 Task 不把候选/旁路变成产品主线。
- [x] 本 Task 失败时可单独回滚。
- [x] 记录当前耦合点：`ProductionPreviewTextCoordinator.begin(states:)` 目前在 `beginShadowPreview(taskID:)` 内启动。
- [x] 记录当前风险：`ShadowPreviewRuntimeGate.shouldStart(isEnabled:) == false` 时，生产主胶囊文字状态流也可能无法启动。
- [x] 明确 A1 才创建 `ProductionPreviewSourceIndependenceBoundaryCheck.sh`，并在同一 Task 内 RED→GREEN，不提交失败测试。
- [x] 不改 Swift 运行代码。
- [x] 更新本文完成记录。
- [x] 提交：`docs(capsule): detail preview data layer unification plan`

#### Task A1: 抽生产预览状态桥，不再借旁路诊断 runtime

**Files:**
- Create: `native/Sources/Application/RealtimeTranscription/ProductionPreviewStateBridge.swift`（生产主胶囊专用状态桥）
- Modify: `native/Sources/Application/SpeechInputCoordinator.swift`（把主胶囊生产进料接到独立 bridge）
- Test: `native/Tests/ProductionPreviewStateBridgeCheck.swift`（状态桥单测）
- Test: `native/Tests/ProductionPreviewSourceIndependenceBoundaryCheck.sh`（A0 边界转绿）

**Goal:** 主胶囊实时文字来自独立生产状态桥；旁路/候选仍只由诊断开关控制。

**Interfaces:**
- `ProductionPreviewStateBridge.begin(sessionID: TranscriptionSessionID) -> AsyncStream<PreviewViewState>`（开始一轮生产预览状态流）
- `ProductionPreviewStateBridge.consume(_ snapshot: PreviewDisplaySnapshot)`（接收旧链路生产快照）
- `ProductionPreviewStateBridge.complete()`（停止时发 completed）
- `ProductionPreviewStateBridge.cancel()`（取消时结束）

- [x] 本 Task 改的是数据层到主胶囊文字进料，不改胶囊 View 绘制。
- [x] 用户可见目标：关闭旁路诊断时，主胶囊仍能正常显示实时文字。
- [x] 本 Task 不影响最终粘贴来源。
- [x] 本 Task 不把候选/旁路变成产品主线。
- [x] 本 Task 失败时可单独回滚。
- [x] 写 RED：`ProductionPreviewStateBridgeCheck` 输入 `PreviewDisplaySnapshot(stableWindowText: "用户体验", volatileTailText: "不要了吗")` 后，输出 `PreviewViewState.displayText == "用户体验不要了吗"`。
- [x] 写 RED：连续 consume 时 `sequence` 必须单调递增。
- [x] 写 RED：`complete()` 后输出 lifecycle `.completed`，之后再 consume 不得继续发布新 running 文本。
- [x] 实现 `ProductionPreviewStateBridge`，内部可复用 `LegacyPreviewShadowAdapter` 的事件语义，但文件职责只能是“生产预览状态桥”，不能引用 `ShadowPreviewCoordinator` / `CandidatePreviewCoordinator`。
- [x] 修改 `SpeechInputCoordinator`：录音开始时总是启动 `productionPreviewTextCoordinator.begin(states:)` 的生产状态流；旁路/候选 runtime 仍然只在 `ShadowPreviewRuntimeGate.shouldStart` 为 true 时启动。
- [x] 修改 `applyRealtimePreview(...)` / `applyExperimentalPreviewState(...)`：先把 `productSnapshot` 送入 `ProductionPreviewStateBridge.consume(...)`，再按诊断开关决定是否 `publishShadowPreview(...)`。
- [x] 修改 stop/cancel/end：生产状态桥随录音生命周期 complete/cancel/end；旁路/候选 teardown 保持原样。
- [x] 运行 `xcrun swiftc ... ProductionPreviewStateBridgeCheck.swift ...`，预期通过。
- [x] 运行 `bash native/Tests/ProductionPreviewSourceIndependenceBoundaryCheck.sh`，预期通过。
- [x] 运行主胶囊相关边界测试，预期通过。
- [x] `./native/build_and_log.sh` 覆盖安装。
- [x] 更新本文和 `docs/开发日志.md`。
- [x] 提交：`refactor(capsule): decouple production preview state source`

#### Task A2: 中性化 PreviewViewState → PreviewDisplaySnapshot 投影命名

**Files:**
- Create: `native/Sources/Application/RealtimeTranscription/PreviewDisplaySnapshotProjector.swift`（统一投影：状态转旧胶囊快照）
- Modify: `native/Sources/Application/RealtimeTranscription/ProductionPreviewTextCoordinator.swift`（改用中性 projector）
- Modify: `native/Tests/ProductionPreviewTextProjectionCheck.swift`（迁移到新名字或增加兼容测试）
- Test: `native/Tests/PreviewDisplaySnapshotProjectorCheck.swift`（中性投影测试）

**Goal:** 把 `ProductionPreviewTextProjection` 从“生产胶囊专用名字”迁成可复用的数据投影，主胶囊/诊断窗都能明确订阅同一份状态投影。

**Interfaces:**
- `PreviewDisplaySnapshotProjector.apply(_ state: PreviewViewState) -> PreviewDisplaySnapshot?`
- `PreviewDisplaySnapshotProjector.reset()`

- [x] 本 Task 只改命名和投影所有权，不改状态内容。
- [x] 本 Task 不改变用户可见行为。
- [x] 本 Task 不影响最终粘贴来源。
- [x] 本 Task 不把候选/旁路变成产品主线。
- [x] 本 Task 失败时可单独回滚。
- [x] 写 RED：复用现有会话锁定、序列单调、终态/失败不喂字、空白不喂字测试。
- [x] 实现 `PreviewDisplaySnapshotProjector`。
- [x] 让 `ProductionPreviewTextCoordinator` 使用新 projector。
- [x] 保留或删除旧 `ProductionPreviewTextProjection` 时，必须保证测试和源码里不会同时存在两套有行为差异的投影。
- [x] 运行 projector/production projection 聚焦测试。
- [x] `./native/build_and_log.sh` 覆盖安装。
- [x] 更新本文和 `docs/开发日志.md`。
- [x] 提交：`refactor(capsule): centralize preview display projection`

#### Task A3: 统一三类预览订阅边界

**Files:**
- Modify: `native/Sources/Application/SpeechInputCoordinator.swift`（订阅分发边界）
- Test: `native/Tests/PreviewSubscribersBoundaryCheck.sh`（订阅边界）

**Goal:** 明确三类订阅者的位置：主胶囊是产品订阅者；旁路/候选是诊断订阅者；任何订阅者都不能反向决定数据内容。

**Interfaces:**
- 主胶囊：`ProductionPreviewTextCoordinator`
- 旁路诊断：`ShadowPreviewCoordinator`
- 候选诊断：`CandidatePreviewCoordinator`

- [x] 本 Task 只整理订阅边界，不改 Provider、ASR、最终粘贴。
- [x] 用户可见行为保持不变。
- [x] 本 Task 不影响最终粘贴来源。
- [x] 本 Task 不把候选/旁路变成产品主线。
- [x] 本 Task 失败时可单独回滚。
- [x] 写 RED：`PreviewSubscribersBoundaryCheck.sh` 断言 `ProductionPreviewTextCoordinator` 不引用 `ShadowPreviewRuntimeGate`。
- [x] 写 RED：断言 `ShadowPreviewCoordinator` / `CandidatePreviewCoordinator` 不被 `FinalDeliveryUseCase` 引用。
- [x] 写 RED：断言 `RecordingCapsuleView` / `CandidatePreviewView` / `ShadowPreviewView` 不引用 `FinalDeliveryUseCase` 或 `CandidateDeliverySnapshot`。
- [x] 只在必要时移动小段订阅 glue 代码，不改状态模型。
- [x] 运行边界测试。
- [x] `./native/build_and_log.sh` 覆盖安装。
- [x] 更新本文和 `docs/开发日志.md`。
- [x] 提交：`refactor(capsule): lock preview subscriber boundaries`

#### Task A4: Stage A 完成复审

**Files:**
- Modify: `docs/superpowers/plans/2026-07-20-main-capsule-goal-lock.md`（本文）
- Modify: `docs/开发日志.md`

**Goal:** 复审 Stage A 是否真的做到“同一份状态投影、一个产品主胶囊、诊断窗不参与主线”。

- [x] 架构复审：确认主胶囊生产数据源不依赖旁路/候选诊断开关。
- [x] 设计复审：确认 UI 层没有新增文本修补、拼接或最终交付判断。
- [x] 验证：关闭旁路诊断后，主胶囊仍能实时出字；打开旁路诊断后，旁路/候选只作为观察窗出现。
- [x] 更新本文完成记录。
- [x] 更新 `docs/开发日志.md`。
- [x] 提交：`docs(capsule): complete preview data layer unification review`

### Stage B: 交付缓存统一

**目标:**

```text
用 RealtimePreviewDeliveryCache 作为实时预览交付缓存
```

**要处理:**

- 当前 `LegacyRealtimePreviewDeliveryCache`（旧实时预览交付缓存）
- 计划中的 `RealtimePreviewDeliveryCache`（实时预览交付缓存）
- `FinalDeliveryUseCase`（最终交付选择）

**验收:**

```text
最终粘贴不依赖任何胶囊显示内容
日志能说明最终来自 RealtimePreviewDeliveryCache 还是 Final ASR
```

**禁止:**

```text
禁止从 CandidatePreviewView / RecordingCapsuleView 读取最终文本
```

#### Stage B 当前代码判断 / 2026-07-20

```text
当前最终交付可用缓存名仍是 LegacyRealtimePreviewDeliveryCache，实际内容来自 PreviewDisplaySnapshot.stableWindowText + volatileTailText。ShadowTranscriptionRuntime 持有 legacyDeliveryCache；停止时 completeForDelivery() 返回 CandidateDeliverySnapshot；FinalDeliveryUseCase 再把 legacyCandidateSnapshot 作为候选交付输入。

这条链路已经不从胶囊 View 读文本，但命名仍混杂：legacy/candidate/shadow/runtime/cache 容易让后续开发再次误以为最终文本来自候选胶囊或旁路胶囊。
```

#### Task B0: Stage B 入口边界钉死

**Files:**
- Modify: `docs/superpowers/plans/2026-07-20-main-capsule-goal-lock.md`（本文）

**Goal:** 只写 Stage B 执行边界，不改运行行为；明确交付缓存统一是“命名和职责收敛”，不是改变最终粘贴策略。

- [x] 本 Task 只改计划文档，不改代码。
- [x] 本 Task 不改变用户可见行为。
- [x] 本 Task 不改变最终粘贴选择策略。
- [x] 本 Task 不把候选/旁路变成产品主线。
- [x] 本 Task 失败时可单独回滚。
- [x] 记录当前链路：`PreviewDisplaySnapshot` → `LegacyRealtimePreviewDeliveryCache` → `CandidateDeliverySnapshot` → `FinalDeliveryUseCase`。
- [x] 明确 B1 才新增 `RealtimePreviewDeliveryCache`，并在同一 Task 内 RED→GREEN。
- [x] 提交：`docs(capsule): detail delivery cache unification plan`

#### Task B1: 新增中性的 RealtimePreviewDeliveryCache

**Files:**
- Create: `native/Sources/Application/RealtimeTranscription/RealtimePreviewDeliveryCache.swift`（实时预览交付缓存）
- Test: `native/Tests/RealtimePreviewDeliveryCacheCheck.swift`（交付缓存单测）

**Goal:** 先创建中性缓存类型，行为与 `LegacyRealtimePreviewDeliveryCache` 一致，不接入运行路径。

**Interfaces:**
- `RealtimePreviewDeliveryCache.consume(_ snapshot: PreviewDisplaySnapshot)`
- `RealtimePreviewDeliveryCache.complete()`
- `RealtimePreviewDeliveryCache.deliverySnapshot() -> CandidateDeliverySnapshot?`

- [x] 本 Task 只新增中性缓存，不替换调用方。
- [x] 用户可见行为不变。
- [x] 本 Task 不改变最终粘贴选择策略。
- [x] 本 Task 不把候选/旁路变成产品主线。
- [x] 本 Task 失败时可单独回滚。
- [x] 写 RED：输入 stable=`用户体验`、volatile=`不要了吗`，`deliverySnapshot()?.text == "用户体验不要了吗"`。
- [x] 写 RED：`complete()` 后 lifecycle 为 `.completed`。
- [x] 实现 `RealtimePreviewDeliveryCache`，不得引用 `RecordingCapsuleView` / `CandidatePreviewView` / `ShadowPreviewView`。
- [x] 运行 `RealtimePreviewDeliveryCacheCheck` 和现有 `LegacyRealtimePreviewDeliveryCacheCheck`。
- [x] `./native/build_and_log.sh` 覆盖安装。
- [x] 更新本文和 `docs/开发日志.md`。
- [x] 提交：`refactor(delivery): add realtime preview delivery cache`

#### Task B2: ShadowTranscriptionRuntime 切到中性缓存类型

**Files:**
- Modify: `native/Sources/Application/RealtimeTranscription/LegacyPreviewShadowAdapter.swift`（runtime 内部缓存字段）
- Test: `native/Tests/RealtimePreviewDeliveryCacheWiringCheck.sh`（缓存接线边界）
- Test: `native/Tests/LegacyPreviewShadowAdapterCheck.swift`（现有 runtime 行为回归）

**Goal:** `ShadowTranscriptionRuntime` 内部不再持有 `LegacyRealtimePreviewDeliveryCache`，改为持有 `RealtimePreviewDeliveryCache`；返回文本行为保持不变。

- [x] 本 Task 只替换 runtime 内部缓存类型，不改 FinalDeliveryUseCase。
- [x] 用户可见行为不变。
- [x] 本 Task 不改变最终粘贴选择策略。
- [x] 本 Task 不把候选/旁路变成产品主线。
- [x] 本 Task 失败时可单独回滚。
- [x] 写 RED：边界测试断言 `ShadowTranscriptionRuntime` 不再出现 `LegacyRealtimePreviewDeliveryCache` 字段。
- [x] 实现最小替换：`private var legacyDeliveryCache` 改名为中性 `realtimePreviewDeliveryCache`。
- [x] 保留 `CandidateDeliverySnapshot` 返回类型，避免同一 Task 改交付 use case。
- [x] 运行 runtime/cache 相关聚焦测试。
- [x] `./native/build_and_log.sh` 覆盖安装。
- [x] 更新本文和 `docs/开发日志.md`。
- [x] 提交：`refactor(delivery): use realtime preview delivery cache in runtime`

#### Task B3: FinalDeliveryUseCase 入参命名去候选化

**Files:**
- Modify: `native/Sources/Application/FinalDeliveryUseCase.swift`（入参命名）
- Modify: `native/Sources/Application/SpeechInputCoordinator.swift`（调用点命名）
- Test: `native/Tests/FinalDeliveryUseCaseCheck.swift`（最终交付行为回归）
- Test: `native/Tests/FinalDeliveryNamingBoundaryCheck.sh`（命名边界）

**Goal:** 把 `legacyCandidateSnapshot` 这类误导命名改为 `realtimePreviewDeliverySnapshot`；行为和选择策略保持不变。

- [x] 本 Task 只改命名，不改选择条件。
- [x] 用户可见行为不变。
- [x] 本 Task 不改变最终粘贴选择策略。
- [x] 本 Task 不把候选/旁路变成产品主线。
- [x] 本 Task 失败时可单独回滚。
- [x] 写 RED：边界测试断言 `FinalDeliveryUseCase.deliver` 不再出现 `legacyCandidateSnapshot` 参数名。
- [x] 写 RED：`FinalDeliveryUseCaseCheck` 现有分支结果完全不变。
- [x] 修改入参和局部变量命名：`legacyCandidateSnapshot` → `realtimePreviewDeliverySnapshot`。
- [x] 不改 `candidatePreviewCacheText` 字段名；它属于 `FinalRecognitionUseCase` 旧接口，是否改名留给 B4/B5。
- [x] 运行 final delivery 相关回归。
- [x] `./native/build_and_log.sh` 覆盖安装。
- [x] 更新本文和 `docs/开发日志.md`。
- [x] 提交：`refactor(delivery): rename realtime preview delivery input`

#### Task B4: 最终交付日志说明真实来源

**Files:**
- Modify: `native/Sources/Application/FinalDeliveryUseCase.swift`（reason/source 文案）
- Modify: `native/Sources/Application/SpeechInputCoordinator.swift`（diagnostic log key/value）
- Test: `native/Tests/FinalDeliveryUseCaseCheck.swift`
- Test: `native/Tests/FinalDeliveryLogBoundaryCheck.sh`

**Goal:** 日志能明确说明最终来自 `RealtimePreviewDeliveryCache` 还是 Final ASR；不再让用户或开发者误会来自候选胶囊 UI。

- [x] 本 Task 只改日志/source/reason 文案，不改选择策略。
- [x] 用户可见最终文本不变。
- [x] 本 Task 不改变最终粘贴选择策略。
- [x] 本 Task 不把候选/旁路变成产品主线。
- [x] 本 Task 失败时可单独回滚。
- [x] 写 RED：最终选择实时预览缓存时，日志 reason 必须包含 `realtime_preview_delivery_cache`。
- [x] 写 RED：边界测试断言 `final_delivery_selected` 日志仍存在 source/reason。
- [x] 调整 reason/source 文案，保留旧 engine 值时必须在 reason 里写清真实来源。
- [x] 运行 final delivery 相关回归。
- [x] `./native/build_and_log.sh` 覆盖安装。
- [x] 更新本文和 `docs/开发日志.md`。
- [x] 提交：`refactor(delivery): clarify realtime preview delivery source`

#### Task B5: 退休 LegacyRealtimePreviewDeliveryCache 旧名

**Files:**
- Delete: `native/Sources/Application/RealtimeTranscription/LegacyRealtimePreviewDeliveryCache.swift`
- Modify: `native/Tests/LegacyRealtimePreviewDeliveryCacheCheck.swift`（删除或迁移为中性测试）
- Test: `native/Tests/RealtimePreviewDeliveryCacheRetirementCheck.sh`

**Goal:** 删除旧缓存名，避免未来继续把最终交付缓存理解为 legacy/candidate/sidepath。

- [x] 本 Task 只退休旧名，不改行为。
- [x] 用户可见行为不变。
- [x] 本 Task 不改变最终粘贴选择策略。
- [x] 本 Task 不把候选/旁路变成产品主线。
- [x] 本 Task 失败时可单独回滚。
- [x] 写 RED：边界测试断言源码不再出现 `LegacyRealtimePreviewDeliveryCache`。
- [x] 删除旧文件或迁移旧测试到新文件名。
- [x] 运行缓存、runtime、final delivery 相关回归。
- [x] `./native/build_and_log.sh` 覆盖安装。
- [x] 更新本文和 `docs/开发日志.md`。
- [x] 提交：`refactor(delivery): retire legacy preview cache name`

#### Task B6: Stage B 完成复审

**Files:**
- Modify: `docs/superpowers/plans/2026-07-20-main-capsule-goal-lock.md`（本文）
- Modify: `docs/开发日志.md`

**Goal:** 复审交付缓存是否统一到 `RealtimePreviewDeliveryCache`，且最终粘贴仍不依赖任何胶囊 View。

- [x] 架构复审：确认最终交付缓存只有一个中性类型。
- [x] 验证：日志能说明最终来自 realtime preview delivery cache 还是 Final ASR。
- [x] 验证：View / Presenter 不引用交付缓存或 final delivery 类型。
- [x] 更新本文完成记录。
- [x] 更新 `docs/开发日志.md`。
- [x] 提交：`docs(delivery): complete delivery cache unification review`

#### Task B7: 补正生产交付缓存实例归属

**Files:**
- Create: `native/Sources/Application/RealtimeTranscription/ProductionRealtimePreviewDeliveryCache.swift`（生产最终交付缓存）
- Modify: `native/Sources/Application/SpeechInputCoordinator.swift`（生产缓存接入）
- Test: `native/Tests/ProductionRealtimePreviewDeliveryCacheCheck.swift`（生产缓存单测）
- Test: `native/Tests/ProductionPreviewDeliveryCacheWiringCheck.sh`（生产缓存接线边界）

**Goal:** 修正 B6 复审误判：最终交付缓存类型虽已中性化，但实例仍挂在 `ShadowTranscriptionRuntime` / `candidatePreviewRuntime`。本 Task 新增生产交付缓存实例，最终交付读取生产缓存；旁路/候选 runtime 原实现保留为诊断分支。

- [x] 本 Task 改交付缓存实例归属，不改主胶囊 UI。
- [x] 用户可见主胶囊显示不变。
- [x] 本 Task 改最终粘贴候选来源：从候选 runtime 缓存改为生产缓存。
- [x] 本 Task 不把候选/旁路变成产品主线。
- [x] 本 Task 失败时可单独回滚。
- [x] 写 RED：`SpeechInputCoordinator` 不得用 `candidateRuntime?.completeForDelivery()` 作为 `realtimePreviewDeliverySnapshot`。
- [x] 写 RED：生产缓存独立文件存在，并提供 `reset/consume/complete/deliverySnapshot`。
- [x] GREEN：录音开始 reset，实时预览 snapshot consume，停止前 complete，最终交付读取生产缓存。
- [x] 保留旁路/候选 runtime 的 begin/end/complete，不删除诊断窗口代码。
- [x] 运行生产缓存、最终交付、旁路门禁相关回归。
- [x] 更新本文和 `docs/开发日志.md`。
- [x] 提交：`refactor(delivery): detach production preview cache from shadow runtime`

### Task B7 完成记录 / 2026-07-20

完成了什么：

```text
新增 ProductionRealtimePreviewDeliveryCache 作为生产链路最终交付缓存实例；SpeechInputCoordinator 录音开始 reset，生产预览 snapshot 写入缓存，停止前 complete，FinalDeliveryUseCase 读取这份生产缓存。candidatePreviewRuntime 仍会 complete 以关闭诊断流，但不再提供 realtimePreviewDeliverySnapshot。
2026-07-20 追加完整编译安装验证：2.0.44 (Build 786) 已通过 --full-version 构建、覆盖安装、签名校验并打开，修正此前 install-only 只复制旧 App 包导致源码未进入安装版的问题。
```

明确没有改什么：

```text
没有改主胶囊 UI、没有改旁路/候选窗口绘制、没有改 Provider/ASR 识别策略、没有删除 ShadowTranscriptionRuntime 内部诊断缓存。
```

下一步只能做什么：

```text
如果继续处理交付策略，只能在 FinalDeliveryUseCase/FinalRecognitionUseCase 层做独立小 Task；不得在 UI 或旁路/候选 View 中修文本。
```

### Stage C: Provider 接口统一

**目标:**

```text
本地、MiMo、豆包输出同一种事件语义
```

**要处理:**

- `TranscriptionProvider`（统一 Provider 接口）
- `SenseVoiceSnapshotProvider`（本地旁路 Provider）
- `MiMoSnapshotProvider`（MiMo Provider）
- `OnlineTranscriptionProvider`（在线流式 Provider）

**验收:**

```text
Provider 文本输出必须能统一归类为 text_output：partial / finalized / reconciled
Provider 终止相关事件必须能统一归类为 terminal：completed / failed / cancelled
Provider 连接状态只能归类为 diagnostic：connectionChanged
Provider 不知道 UI，不决定粘贴
```

**禁止:**

```text
禁止把 MiMo / 豆包专用逻辑写进胶囊 UI
```

#### Stage C 当前代码判断 / 2026-07-20

```text
领域层已经存在 TranscriptionEvent，包含 partial / finalized / completed / failed，也包含 reconciled / connectionChanged / cancelled。
当前 Stage C 不应从零重写 Provider，而应先把“Provider 文本事件合同”和“连接/取消/诊断事件”边界说清楚。
本地 SenseVoice 当前会输出 reconciled，MiMo/豆包主要输出 partial/finalized/completed/failed/connectionChanged/cancelled。
主胶囊不直接消费 Provider；主胶囊只消费 PreviewViewState / PreviewDisplaySnapshot 投影后的展示状态。
```

#### Task C0: Stage C 入口边界钉死

**Files:**
- Modify: `docs/superpowers/plans/2026-07-20-main-capsule-goal-lock.md`（本文）

**Goal:** 只写 Stage C 执行边界，不改运行行为；明确 Stage C 第一目标是统一 Provider 事件语义，不是修 UI，也不是改变最终粘贴策略。

- [x] 走读 `TranscriptionProvider`、`TranscriptionEvent`、`TranscriptionSession`。
- [x] 走读 `SenseVoiceSnapshotProvider`、`MiMoSnapshotProvider`、`OnlineTranscriptionProvider`。
- [x] 记录当前差异：`reconciled` 属于本地 Provider 的边界修正事件，不能直接扩散成 UI 逻辑。
- [x] 不改运行代码，不改 UI，不改最终交付。

#### Task C1: 固定 Provider 文本事件分类合同

**Files:**
- Create: `native/Sources/Domain/RealtimeTranscription/TranscriptionProviderEventContract.swift`（Provider 事件分类合同）
- Test: `native/Tests/TranscriptionProviderEventContractCheck.swift`（事件分类合同测试）

**Goal:** 给现有 `TranscriptionEvent` 加一个纯分类层，明确哪些事件是文本产出，哪些是终态，哪些是诊断/连接/取消；先不改任何 Provider 行为。

- [x] 写 RED：`partial/finalized/reconciled` 必须被分类为文本事件。
- [x] 写 RED：`completed/failed/cancelled` 必须被分类为终止相关事件。
- [x] 写 RED：`connectionChanged` 不得被分类为文本事件，也不得进入最终交付文本。
- [x] GREEN：只新增纯分类扩展/工具，不修改 Provider。
- [x] 验证：新增测试通过；Provider 源码不引用胶囊 UI / FinalDelivery。
- [x] 更新本文完成记录。

#### Task C2: 固定 Provider 输出边界测试

**Files:**
- Create: `native/Tests/TranscriptionProviderBoundaryCheck.sh`（Provider 边界测试）

**Goal:** 防止后续把 MiMo / 豆包 / SenseVoice 专用逻辑写进胶囊 UI、最终交付或 Provider 之外的错误位置。

- [x] RED：Provider 文件不得引用 `RecordingCapsuleView`、`CandidatePreviewView`、`ShadowPreviewView`、`FinalDeliveryUseCase`、`PasteCoordinator`。
- [x] GREEN：按现状补边界测试；不改业务逻辑。
- [x] 验证：边界测试通过。
- [x] 更新本文完成记录。

#### Task C3: 盘点三类 Provider 事件序列差异

**Files:**
- Modify: `docs/superpowers/plans/2026-07-20-main-capsule-goal-lock.md`（本文）

**Goal:** 只做代码走读和计划补充；列出 SenseVoice / MiMo / 豆包当前实际事件序列，决定是否需要适配层。

- [x] 记录 SenseVoice：fast/correction/reconciled/completed/failure 的实际序列。
- [x] 记录 MiMo：snapshot partial/finalized/completed/failure 的实际序列。
- [x] 记录豆包：online partial/finalized/completed/failure/connection 的实际序列。
- [x] 明确下一步是否需要新增统一 Adapter；不得直接改 Provider。
- [x] 更新本文完成记录。

#### Task C4: 如需要，新增 Provider 事件适配层

**Files:**
- 待 Task C3 后补充。

**Goal:** 如果 C3 证明三类 Provider 语义不一致，再新增适配层；否则跳过。

- [x] Task C3 前不得开工。
- [x] C3 结论：当前不新增适配层；先使用 C1 的统一分类合同作为 Stage C 的收口边界。
- [x] 不改 UI，不改最终粘贴。

#### Task C5: Stage C 完成复审

**Goal:** 复审 Stage C 是否做到“Provider 事件语义清晰，UI/最终交付不感知具体 Provider”。

- [x] 架构复审。
- [x] 边界测试通过。
- [x] 更新本文完成记录。

### Stage D: 识别质量层

**目标:**

```text
把重复字、丢尾巴、分段拼接、幻觉文本放到数据/质量层处理
```

**要处理:**

- seam 重叠去重
- stop tail 收尾
- VAD 边界
- hallucination filter
- candidate quality gate

**验收:**

```text
UI 层没有识别质量修补逻辑
每次 fallback 都有原因
```

**禁止:**

```text
禁止在 View / Presenter 里修“体验验”“设计计”这类文本
```

#### Stage D 当前代码判断 / 2026-07-20

```text
当前已经存在几块质量治理代码：SenseVoiceBoundaryReconciler 处理分段边界和 seam；CandidateTranscriptQualityGate 处理最终交付前的候选质量；FinalRecognitionUseCase 处理 final ASR 空结果、明显短缺和静音幻觉 fallback；SenseVoiceSnapshotProvider 有 tailGapMilliseconds 诊断。
Stage D 不能把这些逻辑搬到 UI，也不能在胶囊里修字。正确方向是：先把已存在的质量规则归档成可验收矩阵，再补缺失规则。
```

#### Task D0: Stage D 入口边界钉死

**Files:**
- Modify: `docs/superpowers/plans/2026-07-20-main-capsule-goal-lock.md`（本文）

**Goal:** 只写 Stage D 执行边界，不改运行行为；明确质量层只处理数据和交付判断，不处理 UI 动画。

- [x] 走读 `SenseVoiceBoundaryReconciler`、`CandidateTranscriptQualityGate`、`FinalRecognitionUseCase`、`SenseVoiceSnapshotProvider` 诊断字段。
- [x] 记录当前已有质量治理能力。
- [x] 不改运行代码，不改 UI，不改最终粘贴策略。

#### Task D1: 建立识别质量问题矩阵

**Files:**
- Modify: `docs/superpowers/plans/2026-07-20-main-capsule-goal-lock.md`（本文）

**Goal:** 把真实问题拆成独立类别，每类绑定代码位置和验收样例。

- [x] 记录重复字：如“体验验”“设计计”。
- [x] 记录分段错拼：如“公司功功能”。
- [x] 记录尾部丢字：停止点后最后几百毫秒未进缓存/交付。
- [x] 记录幻觉短句：如静音/噪声识别成无意义文本。
- [x] 记录 final ASR 明显短于实时预览。
- [x] 不改代码。

#### Stage D 识别质量问题矩阵 / 2026-07-20

| 问题类别 | 真实样例 | 当前责任层 | 已有代码/测试 | 缺口 | 下一步 |
| --- | --- | --- | --- | --- | --- |
| 短距离重复字 | `用户体验验不要了吗`、`代码设计计排查一下` | 质量层 / 最终交付前质量门 | `CandidateTranscriptQualityGate.hasRepeatedShortUnit` 已有基础规则 | 需要用真实样例固定，确认不误杀“好好/看看”等真实口语重复 | Task D3 |
| 分段错拼 | `今天我们讨论公司` + `功功能可以优化` 被拼成 `公司功功能` | seam / Reconciler | `SenseVoiceBoundaryReconciler`、`SenseVoiceContentSeamVerificationCheck` 已覆盖相近样例 | 需要补更贴近真实输入的样例，并确认 no-overlap 时不硬确认前段尾巴 | Task D4 |
| 尾部丢字 | 近 2 分钟录音，预览有内容，最终粘贴少末尾 | Provider stop-tail / 实时预览交付缓存 / FinalRecognitionUseCase fallback | `tailGapMilliseconds`、`SenseVoiceCoverageDiagnosticsCheck`、`FinalRecognitionUseCaseCheck` 已有兜底 | 需要确认停止时最后音频是否进入缓存，不能靠 UI 等待或固定 sleep | Task D5 |
| 静音/噪声幻觉 | 静音识别成 `The.` 或无意义短句 | final ASR resolve / meaningful text 判断 | `FinalRecognitionUseCaseCheck` 已覆盖 `The.` 空结果 | 需要后续扩充多语言/标点/单字噪声样例 | Stage D 后续小 Task |
| final ASR 短缺 | final ASR 明显短于长实时预览 | FinalRecognitionUseCase / FinalDeliveryUseCase | `realtime-preview-shortfall-fallback` 已有测试 | 需要日志能说明 fallback 原因，并与 Stage E 诊断联动 | Stage E |
| 语义误识别 | `用户体验不要了吗` → `用户体人比我了` | ASR 模型/Provider 质量，非 UI 修补 | 当前没有可靠规则能无损修正 | 只能先进入诊断矩阵，不能在 UI 或简单规则里硬改 | Stage E/模型评估 |

#### Task D2: 固定质量层边界测试

**Files:**
- Create: `native/Tests/RealtimeRecognitionQualityBoundaryCheck.sh`（质量层边界测试）

**Goal:** 防止后续把修字逻辑写进 View / Presenter / 胶囊。

- [x] RED：Presentation 层不得引用 `CandidateTranscriptQualityGate`、`SenseVoiceBoundaryReconciler`、`FinalRecognitionUseCase`。
- [x] GREEN：新增边界测试，不改业务逻辑。
- [x] 验证：边界测试通过。
- [x] 更新本文完成记录。

#### Task D3: 补重复字质量测试

**Files:**
- Modify: `native/Tests/CandidateTranscriptQualityGateCheck.swift`（候选交付质量测试）
- 或 Create: `native/Tests/RealtimeTextQualityCheck.swift`（如需独立质量工具，先写 RED）

**Goal:** 先用真实坏例固定预期，不直接写算法。

- [x] RED：`体验验`、`设计计` 这类短距离重复不得被当成可直接交付文本。
- [x] RED：允许真实口语重复，例如“好好”“看看”，不能误杀。
- [x] GREEN：只在数据/质量层实现，不改 UI。
- [x] 更新本文完成记录。

#### Task D4: 补分段错拼质量测试

**Files:**
- Modify: `native/Tests/SenseVoiceContentSeamVerificationCheck.swift`（边界拼接验证）

**Goal:** 固定“前段尾巴 + 后段开头”不能硬拼出错词。

- [x] RED：`今天我们讨论公司` + `功功能可以优化` 不得产出 `公司功功能`。
- [x] RED：有可信 overlap 的 `功能` + `功能优化` 仍可稳定前进。
- [x] GREEN：只改 seam/reconciler 或其质量门，不改 UI。
- [x] 更新本文完成记录。

#### Task D5: 补停止尾部覆盖测试

**Files:**
- Modify: `native/Tests/SenseVoiceCoverageDiagnosticsCheck.swift`（尾部覆盖诊断）
- 或新增专门 tail coverage 测试。

**Goal:** 防止长录音/停止时最后一小段没有进入实时预览缓存。

- [x] RED：finish 后必须排空 stop-tail，`tailGapMilliseconds` 应在可接受范围内。
- [x] GREEN：只改 Provider/调度/缓存层，不改 UI。
- [x] 更新本文完成记录。

#### Task D6: Stage D 完成复审

**Goal:** 复审 Stage D 是否做到“质量问题在数据/质量/交付层处理，UI 不修文本”。

- [x] 架构复审。
- [x] 质量测试和边界测试通过。
- [x] 更新本文完成记录。

### Stage E: 诊断与验收层

**目标:**

```text
每次录音都能解释：预览来自哪里、最终粘贴来自哪里、为什么选它
```

**要处理:**

- request-level logs
- final delivery selected logs
- source / reason / quality diagnostics
- 真实录音验收矩阵

**验收:**

```text
不用猜；看日志能定位是 Provider、质量层、交付层还是 UI 层问题
```

#### Stage E 当前代码判断 / 2026-07-20

```text
当前已有关键日志：candidate_delivery_cache、final_delivery_selected、final_asr_result/final_asr_empty、shadow_sensevoice_summary、shadow_online_summary、paste_drain，以及 VAD/auto-finish 相关日志。
Stage E 不应先加更多散乱日志，而应先建立“每次录音解释链”：预览来源、实时缓存状态、Provider 诊断、质量门结果、最终交付选择、粘贴结果。
```

#### Task E0: Stage E 入口边界钉死

**Files:**
- Modify: `docs/superpowers/plans/2026-07-20-main-capsule-goal-lock.md`（本文）

**Goal:** 只写 Stage E 执行边界，不改运行行为；明确诊断目标是串起现有日志，不是让 UI 承担调试判断。

- [x] 走读 `SpeechInputCoordinator`、`FinalDeliveryUseCase`、`FinalRecognitionUseCase` 现有诊断日志。
- [x] 记录当前已有日志点。
- [x] 不改运行代码，不改 UI，不改最终交付。

#### Task E1: 固定诊断日志边界测试

**Files:**
- Create: `native/Tests/RealtimeRecognitionDiagnosticsBoundaryCheck.sh`（诊断日志边界测试）

**Goal:** 防止未来删掉关键来源/原因日志，确保不用猜数据来自哪里。

- [x] RED：必须存在 `candidate_delivery_cache`。
- [x] RED：必须存在 `final_delivery_selected task_id=... source=... reason=...`。
- [x] RED：必须存在 `final_asr_result` / `final_asr_empty`。
- [x] RED：必须存在 `shadow_sensevoice_summary`，包含 `tail_gap_ms` 和 `seam_confidence`。
- [x] RED：必须存在 `shadow_online_summary`。
- [x] GREEN：新增边界测试，不改业务逻辑。
- [x] 更新本文完成记录。

#### Task E2: 建立单次录音解释链矩阵

**Files:**
- Modify: `docs/superpowers/plans/2026-07-20-main-capsule-goal-lock.md`（本文）

**Goal:** 把一次录音从开始、预览、停止、质量判断、最终交付、粘贴结果串成可检查矩阵。

- [x] 记录每个阶段应有的日志名。
- [x] 记录每个日志必须包含的字段。
- [x] 标注缺失字段是否需要后续代码补充。
- [x] 不改代码。

#### Stage E 单次录音解释链矩阵 / 2026-07-20

| 阶段 | 现有日志 | 必要字段 | 能解释什么 | 当前缺口 |
| --- | --- | --- | --- | --- |
| 录音开始 | `recording_started` | `task_id`、`mode`、`backend`、`device` | 本轮录音是谁、用什么模式/设备开始 | 需后续确认现有字段是否足够统一 |
| VAD/自动结束 | `vad_final`、`vad_final_override`、`recording_auto_finish` | `task_id`、`reason`、`preview_chars`、`probe_ms` | 为什么停、有没有人声、是否用实时预览证据覆盖 VAD | 已有，后续 Stage E 验收中核对 |
| 实时预览缓存 | `candidate_delivery_cache` | `task_id`、`chars`、`source`、`usable`、`deliverable`、`lifecycle` | 停止时实时预览交付缓存是否可用 | 已有 |
| 本地旁路诊断 | `shadow_sensevoice_summary` | `tail_gap_ms`、`seam_confidence`、`completed`、`provider_service_ms` | 本地 Provider 是否覆盖尾部、seam 是否可信 | 已有 |
| 在线旁路诊断 | `shadow_online_summary` | `provider`、`session`、`completed_requests`、`terminal_reason` | 在线 Provider 是否参与、是否完成 | 已有，但 connect/first_text/sent_audio 目前是占位 `-1`，真实流式诊断后续可补 |
| 最终交付选择 | `final_delivery_selected` | `task_id`、`chars`、`source`、`reason` | 最终粘贴为什么选这个文本 | 已有 |
| final ASR 结果 | `final_asr_result` / `final_asr_empty` | `task_id`、`source`、`audio_duration_ms`、`recognition_ms`、`chars`、`engine` | 完整 final ASR 是否空、是否短缺、是否 fallback | 已有 |
| 粘贴结果 | `paste_drain` + paste result logs | `task_id`、`target`、`frontmost`、`fallback` | 最终文本去哪了，目标是否变化 | 已有但结果链可在验收矩阵中补齐 |

#### Task E3: 如缺字段，补最小诊断字段

**Files:**
- 待 Task E2 后补充。

**Goal:** 只补能解释问题的字段，不新增散乱日志。

- [x] Task E2 前不得开工。
- [x] E2 结论：当前“来源/原因解释链”字段已够用；在线 `connect_ms/first_text_ms/sent_audio_ms=-1` 属于性能诊断缺口，先不在本阶段补运行代码。
- [x] 不改 UI，不改最终交付策略。

#### Task E4: 真实验收矩阵

**Files:**
- Modify: `docs/superpowers/plans/2026-07-20-main-capsule-goal-lock.md`（本文）

**Goal:** 固定用户手测路径，覆盖本地、MiMo、豆包、在线关闭、本地 fallback、长录音、停顿收尾。

- [x] 写清每条手测路径。
- [x] 写清预期看到的胶囊行为、最终粘贴行为和日志证据。
- [x] 不改代码。

#### Stage E 真实验收矩阵 / 2026-07-20

| 路径 | 设置 | 口述建议 | 预期胶囊行为 | 预期最终交付 | 必看日志 |
| --- | --- | --- | --- | --- | --- |
| 本地短句 | 在线 ASR 关闭，Final ASR 按当前设置 | `今天我们讨论功能优化` | 主胶囊正常显示逐字/稳定文本，不出现旁路/候选产品入口 | 正常粘贴短句 | `recording_start`、`realtime_preview_update`、`candidate_delivery_cache`、`final_delivery_selected`、`final_asr_result` |
| 本地重复字坏例 | 在线 ASR 关闭 | `用户体验不要了吗`，观察是否出现 `体验验` | UI 不负责修字，只展示数据层结果 | 若候选缓存出现重复字，应被质量门拒绝或由 final ASR 兜底 | `candidate_delivery_cache`、`final_delivery_selected reason=quality=rejected...` |
| seam 错拼坏例 | 在线 ASR 关闭，长一点分段 | `今天我们讨论功能优化，如果可以的话继续推进` | 主胶囊不能靠 UI 拼接修补 | 不应稳定出 `公司功功能` 一类硬拼文本 | `shadow_sensevoice_summary seam_confidence=...`、质量测试作离线证据 |
| 尾部收尾 | 录 20s+，最后快速补一句 | 结尾说 `最后这一句也要保留` 后立刻停止 | 不靠 UI 等待固定 sleep | 最终粘贴应保留末尾；若 fallback，日志说明原因 | `tail_gap_ms`、`candidate_delivery_cache lifecycle=completed`、`final_delivery_selected` |
| MiMo 在线旁路 | 在线 ASR 选 MiMo，Key 已配 | 普通 10~20s 口述 | 主胶囊仍用生产预览；旁路只是诊断 | 最终交付仍由交付层决定，不由旁路 UI 决定 | `shadow_preview_mode provider=mimoV25`、`shadow_online_summary provider=mimoV25`、`final_delivery_selected` |
| 在线关闭 fallback | 在线 ASR 关闭或缺 Key | 任意短句 | 主胶囊正常；旁路不应成为产品依赖 | 本地路径正常交付 | `shadow_preview_mode ... local_fallback/missing_credential_fallback` 或无旁路启动，`final_delivery_selected` |
| 粘贴目标验证 | 任意 ASR | 录音时切换/保持目标 App | 胶囊显示目标应与粘贴目标逻辑一致 | 粘贴到正确目标；失败时保存最近转录 | `paste_drain target=... frontmost=... fallback=...`、paste result logs |

#### Task E5: Stage E 完成复审

**Goal:** 复审 Stage E 是否做到“每次录音可解释，不靠猜”。

- [x] 架构复审。
- [x] 边界测试通过。
- [x] 更新本文完成记录。

### Stage F: 产品化收口

**目标:**

```text
确认迁移期诊断能力不会变成产品主线，并完成真实安装版验收与发布前整理。
```

**要处理:**

- 旁路/候选诊断入口复核
- 真实安装版验收路径
- 发布前测试清单
- 后续未完成风险清单

**验收:**

```text
默认产品态只保留一个主胶囊；旁路/候选只作为诊断工具；验收路径和日志证据清楚。
```

**禁止:**

```text
禁止再把候选胶囊扶正
禁止把旁路诊断变成默认产品功能
禁止在收口阶段顺手改识别、交付、UI 动画或粘贴策略
```

#### Stage F 当前代码判断 / 2026-07-20

```text
Task 7 已做过旁路/候选退休边界：ShadowPreviewSettings 默认关闭；候选胶囊跟随旁路 runtime，不是独立产品入口；ShadowPreviewRuntimeGate 阻止关闭时启动或发布。Stage F 不重复改这套运行逻辑，而是做发布前复核和真实验收清单。
```

#### Task F0: Stage F 入口边界钉死

**Files:**
- Modify: `docs/superpowers/plans/2026-07-20-main-capsule-goal-lock.md`（本文）

**Goal:** 只写 Stage F 执行边界，不改运行行为；明确收口阶段只做复核、验收、清单，不顺手改主流程。

- [x] 读取 Task 7 退休记录。
- [x] 读取 Stage A-E 完成记录。
- [x] 明确 Stage F 不改 UI、Provider、最终交付、粘贴策略。
- [x] 更新本文完成记录。

#### Task F1: 临时诊断入口复核

**Files:**
- Test: `native/Tests/MainCapsuleRetirementSettingsBoundaryCheck.sh`
- Test: `native/Tests/ShadowPreviewRuntimeGateBoundaryCheck.sh`
- Test: `native/Tests/RealtimeRecognitionDiagnosticsBoundaryCheck.sh`
- Modify: `docs/superpowers/plans/2026-07-20-main-capsule-goal-lock.md`（本文）

**Goal:** 复核默认产品态是否仍只保留一个主胶囊，旁路/候选是否仍只是诊断能力。

- [x] 运行设置入口退休边界测试。
- [x] 运行运行期门禁边界测试。
- [x] 运行诊断日志边界测试。
- [x] 记录复核结论。
- [x] 不改运行代码。

#### Task F2: 真实安装版验收清单

**Files:**
- Modify: `docs/superpowers/plans/2026-07-20-main-capsule-goal-lock.md`（本文）

**Goal:** 把 Stage E 的验收矩阵改成发布前可执行清单，明确哪些已自动验证，哪些必须用户手测。

- [x] 列出自动测试项。
- [x] 列出真实安装版手测项。
- [x] 标注哪些需要用户提供 Key/录音环境。
- [x] 不改运行代码。

#### Stage F 真实安装版验收清单 / 2026-07-20

**已自动验证:**

- 主胶囊生产预览不依赖旁路/候选：`ProductionPreviewSourceIndependenceBoundaryCheck`
- 旁路/候选订阅边界：`PreviewSubscribersBoundaryCheck`
- 旁路/候选设置入口退休：`MainCapsuleRetirementSettingsBoundaryCheck`
- 旁路运行期门禁：`ShadowPreviewRuntimeGateBoundaryCheck`
- Provider 边界：`TranscriptionProviderBoundaryCheck`
- 识别质量边界：`RealtimeRecognitionQualityBoundaryCheck`
- 诊断日志边界：`RealtimeRecognitionDiagnosticsBoundaryCheck`
- 重复字质量样例：`CandidateTranscriptQualityGateCheck`
- seam 错拼样例：`SenseVoiceContentSeamVerificationCheck`
- stop-tail 覆盖诊断：`SenseVoiceCoverageDiagnosticsCheck`
- final ASR fallback/幻觉过滤：`FinalRecognitionUseCaseCheck`

**必须真实安装版手测:**

- 本地短句：主胶囊显示正常，最终粘贴正确。
- 本地 20s+ 尾部收尾：最后一句不丢。
- 本地重复字坏例：如果出现重复字，最终交付应由质量层/Final ASR 兜底，UI 不修字。
- 粘贴目标：录音期间切换/保持目标 App，确认粘贴目标和 `paste_drain` 一致。
- 旁路关闭：关闭旁路后仍只有主胶囊产品态可用。

**需要用户环境 / Key:**

- MiMo 在线旁路：需要已配置 MiMo Key，检查 `shadow_online_summary provider=mimoV25` 和最终交付日志。
- 豆包在线旁路：需要豆包 Key，检查在线 fallback / provider 日志；当前用户已决定豆包可后续再测。
- 长录音真实口述：需要真实 1–2 分钟口述，重点看末尾、重复字、seam 和最终粘贴。

#### Task F3: 发布前风险清单

**Files:**
- Modify: `docs/superpowers/plans/2026-07-20-main-capsule-goal-lock.md`（本文）

**Goal:** 明确剩余风险，避免把未验证事项当成已完成。

- [x] 记录在线 MiMo 性能诊断字段仍是占位的风险。
- [x] 记录真实长录音仍需安装版手测。
- [x] 记录语义误识别无法靠规则无损修正，需要模型/Provider 评估。
- [x] 不改运行代码。

#### Stage F 发布前风险清单 / 2026-07-20

| 风险 | 当前状态 | 影响 | 后续处理 |
| --- | --- | --- | --- |
| MiMo 在线性能字段占位 | `shadow_online_summary` 中 `connect_ms/first_text_ms/sent_audio_ms` 仍可能是 `-1` | 不影响来源/交付判断，但影响定位“为什么在线旁路卡顿” | 后续单独做在线性能诊断 Task，不在本轮收口顺手改 |
| 真实长录音未由本轮自动测试完全覆盖 | 自动测试覆盖 stop-tail 机制，但不等价于真实 1–2 分钟口述体验 | 仍需用户在安装版验证末尾、seam、重复字和最终粘贴 | 按 Stage F 真实安装版验收清单手测 |
| 语义误识别不可无损规则修正 | 如 `用户体验不要了吗` → `用户体人比我了`，当前只能归因模型/Provider | 不能靠 UI 或简单替换修，否则会误改真实内容 | 后续进入模型/Provider 评估，或引入更强上下文校准 |
| 候选/旁路仍存在诊断入口 | 默认产品态已锁住，但诊断能力仍在代码里 | 用户误开诊断时仍可能看到多胶囊 | 发布说明中标注为诊断工具；后续可做更深隐藏/开发者模式 |
| 真实安装版视觉/动效未本轮重新录屏验证 | 本轮多数为架构、测试、文档收口 | 不能声明视觉体验已完全验收 | 需要按 F2 清单做安装版手测 |

#### Task F4: Stage F 完成复审

**Goal:** 复审产品化收口是否完成，决定是否可以进入发布/合并准备。

- [x] 架构复审。
- [x] 关键边界测试通过。
- [x] 更新本文完成记录。

## 11. 旧计划中会影响本次重构的内容

下面这些内容会影响主胶囊重构，开发前必须对照，不允许无视：

### 11.1 `2026-07-19-realtime-transcription-architecture-reconciliation-plan.md`

影响点：

- 旧链路能力迁移。
- `FinalDeliveryUseCase` 最终交付权威。
- `LegacyRealtimePreviewDeliveryCache` 当前交付缓存。
- Provider/Reconciler/FinalDelivery 不能混改。

处理原则：

```text
主胶囊 Task 不得顺手改 FinalDelivery / Provider / Reconciler
```

### 11.2 `2026-07-18-unify-realtime-transcription-implementation-plan.md`

影响点：

- 统一转录状态和旧新路径合并目标。
- 新链路不是替代旧链路，而是承载旧能力。

处理原则：

```text
只取它的数据层目标，不把三胶囊变成产品目标
```

### 11.3 `2026-07-12-three-capsule-candidate-preview.md`

影响点：

- 三胶囊布局、候选窗口、旁路窗口。
- 候选动效分层参考。

处理原则：

```text
候选胶囊只作为分层参考，不作为主胶囊迁移目标
```

### 11.4 `2026-07-19-realtime-recognition-quality-hardening.md`

影响点：

- 边界校准、交叉验证、识别质量问题。

处理原则：

```text
质量问题归数据/质量层，不归主胶囊 UI 层
```

### 11.5 版本历史与构建规则

影响点：

- 普通安装不构建。
- 完整版本才编译。
- 文档/代码改动必须提交。

处理原则：

```text
每个 Task 完成后更新计划并提交；只有明确完整版本时才 full-version 构建
```

## 12. 计划是否需要继续细化

需要。

本文现在是目标锁和路线图，不是每个代码 Task 的完整执行细节。下一步应先执行 Task 1：

```text
主胶囊状态清单
```

Task 1 完成后，再把 Task 2–7 拆成更细的代码执行计划。

禁止现在直接开写 `MainCapsuleState`。必须先把旧主胶囊所有状态列全，否则会漏掉龙虾、闪念、翻译、错误态等能力。

## 13. 当前决策状态

Status: Accepted

Decision:

```text
参考候选胶囊分层方式，重构主胶囊；不把候选胶囊直接改造成主胶囊。
```

Reason:

```text
候选胶囊的价值在分层，不在它作为独立窗口的产品形态。
主胶囊承载完整产品能力，必须保留产品身份，但内部重新分层。
```
