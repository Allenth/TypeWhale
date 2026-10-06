# Minimal Black Candidate UI Recovery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 Git 中已验证的候选胶囊 UI/展示机制恢复并转正为“简洁黑色”主主题，同时删除错误的旧主胶囊黑色换肤实现，不恢复任何候选 runtime、旁路耦合或重复数据链路。

**Architecture:** `PreviewTheme.minimalBlack` 改为创建独立的 `MinimalBlackPreviewPresenter`，它和默认胶囊、刘海主题一样只实现 `PreviewPresenting`，并通过既有 `ProductionPreviewTextCoordinator` 消费唯一生产 `PreviewDisplaySnapshot`。候选历史代码只作为视觉与展示机制参考，从提交 `9f4d82d` 定向恢复、当场重命名；不恢复 `CandidatePreviewCoordinator`、`ThreeCapsuleLayout`、`ShadowTranscriptionRuntime` 订阅或候选窗口定位逻辑。

**Tech Stack:** Swift 5.10、AppKit、QuartzCore、现有 `PreviewPresenting` / `ProductionPreviewTextSink`、shell 边界测试、`swiftc` 轻量行为测试。

## Global Constraints

- 每次开始 Task 前重新读取本文；每次只执行一个 Task，完成后立即回写状态、证据并独立提交。
- 默认只在主目录 `$HOME/Pictures/macOSwinOSCoding/TypeSpeaker` 和分支 `codex/typewhale-pro-asr-hotwords` 工作；不新建 worktree。
- 两个现存未跟踪目录 `native/Helpers/CapsuleConceptGallery/`、`native/Sources/Presentation/Capsule/Concepts/` 属于受保护现场；禁止修改、删除、stage 或提交。
- 只允许从 `9f4d82d` 读取候选 UI 历史；禁止执行整目录 `git checkout`，禁止恢复 Candidate runtime、Coordinator、三胶囊布局和旧专用订阅。
- 默认胶囊、刘海主题、闪念、OpenClaw、旁路诊断、识别、Reducer、生产缓存、Final ASR、最终粘贴均为 do-not-touch。
- `MinimalBlackPreviewPresenter` 只能消费 `PreviewDisplaySnapshot` 和协调器已有命令；禁止引用 Provider、Reconciler、Shadow runtime、Final delivery 或 Paste。
- 不允许长期保留两套简洁黑色实现：新 Presenter 接通并通过测试后，下一个 Task 必须删除 `MainCapsuleVisualStyle` 换肤代码。
- 每次删除前先用 `rg` 证明引用范围；删除后必须编译或运行边界测试。禁止模糊批量删除。
- 代码改动全部完成后只执行一次日常 build；保持短版本 `2.0.58`，build 从 `804` 增加到 `805`，覆盖安装 `/Applications/TypeWhale Pro.app`。

## Architecture Decision

**Status:** Accepted

**Confirmed facts:**

- `c71c90a` 删除了候选 Presentation；其父提交 `9f4d82d` 仍保留候选 View、Presenter 和展示状态代码。
- 当前 Build 804 的 `.minimalBlack` 路由是 `RecordingPanel(visualStyle: .minimalBlack)`，即旧主胶囊换肤。
- `ProductionPreviewTextCoordinator.replaceSink(_:)` 已支持在录音会话之间将唯一生产订阅切换到不同 `PreviewPresenting`。
- 候选 runtime 已在 `9f4d82d` 删除；旁路仍由独立 `ShadowPreviewCoordinator` / `ShadowTranscriptionRuntime` 负责。

**Rejected candidates:**

- 整体回退到 `446bdc1`：会恢复候选 runtime、重复窗口和旧订阅，违反单生产链路约束。
- 继续扩展 `MainCapsuleVisualStyle`：只能得到旧主胶囊换肤，不能恢复候选 UI/展示边界，已被用户明确否决。

**Selected boundary:**

```text
Production PreviewViewState
  -> ProductionPreviewTextCoordinator
  -> PreviewDisplaySnapshot
  -> one selected PreviewPresenting
       classic      -> RecordingPanel
       notch        -> NotchPreviewPresenter
       minimalBlack -> MinimalBlackPreviewPresenter

Optional diagnostics only:
ShadowTranscriptionRuntime -> ShadowPreviewPresenter
```

**Rollback:** 每个 Task 单独提交。Task 1 失败可回退新增 Presenter 与单条路由；Task 2 失败可回退换肤清理提交，恢复 Build 804 的经典胶囊实现。任何回退都不改变识别、缓存或粘贴数据。

---

### Task 1: 定向恢复候选展示为独立 MinimalBlack 主主题

**Status:** Completed

**Files:**

- Create: `native/Sources/Presentation/MinimalBlackPreview/MinimalBlackRenderState.swift`
- Create: `native/Sources/Presentation/MinimalBlackPreview/MinimalBlackTextMotion.swift`
- Create: `native/Sources/Presentation/MinimalBlackPreview/MinimalBlackPreviewView.swift`
- Create: `native/Sources/Presentation/MinimalBlackPreview/MinimalBlackPreviewPresenter.swift`
- Create: `native/Tests/MinimalBlackPresentationCheck.swift`
- Create: `native/Tests/MinimalBlackThemeRoutingBoundaryCheck.sh`
- Modify: `native/Sources/Application/SpeechInputCoordinator.swift`
- Modify: `native/Tests/PreviewThemeRoutingBoundaryCheck.sh`
- Modify: `docs/superpowers/plans/2026-07-23-minimal-black-candidate-ui-recovery.md`

**Interfaces:**

- Consumes: `PreviewPresenting`, `PreviewDisplaySnapshot`, `MainCapsulePanelShell.targetFrame(panelSize:screenVisibleFrame:)`.
- Produces: `final class MinimalBlackPreviewPresenter: PreviewPresenting`.
- Historical source: 只参考 `git show 9f4d82d:native/Sources/Presentation/CandidatePreview/...`；所有生产类型必须使用 `MinimalBlack` 命名。

- [x] **Step 1: 写 Presenter 行为和路由 RED**

`MinimalBlackPresentationCheck.swift` 必须验证：

```swift
var motion = MinimalBlackTextMotion()
precondition(motion.apply(contentCharacterCount: 40) == .updated(needsTimer: true))
precondition(motion.targetCharacterCount - motion.visibleCharacterCount == 12)
while motion.advance() != .finished {}
precondition(motion.visibleCharacterCount == 40)

var state = MinimalBlackRenderState.empty
state.apply(stableWindowText: "已确认", volatileTailText: "尾巴")
precondition(state.displayText == "已确认尾巴")
precondition(state.stableCharacterCount == 3)
```

`MinimalBlackThemeRoutingBoundaryCheck.sh` 必须先要求：

```bash
test -f native/Sources/Presentation/MinimalBlackPreview/MinimalBlackPreviewPresenter.swift
grep -Fq 'final class MinimalBlackPreviewPresenter: PreviewPresenting' \
  native/Sources/Presentation/MinimalBlackPreview/MinimalBlackPreviewPresenter.swift
grep -Fq 'popup = MinimalBlackPreviewPresenter()' \
  native/Sources/Application/SpeechInputCoordinator.swift
! rg -n 'CandidatePreview|ShadowTranscriptionRuntime|FinalDeliveryUseCase|PasteCoordinator|TranscriptionProvider' \
  native/Sources/Presentation/MinimalBlackPreview
```

- [x] **Step 2: 运行 RED**

Run: `bash native/Tests/MinimalBlackThemeRoutingBoundaryCheck.sh`
Expected: 新 Presenter 尚不存在，FAIL。

Evidence: 路由测试以 exit 1 失败，Swift 行为测试因两个新生产文件不存在而失败，符合预期。

- [x] **Step 3: 创建独立展示状态与 View**

从历史 Candidate 定向迁移黑色表面、绿色细边、稳定白字/可变灰字、单行头部截断和 12 字动画欠账机制。`MinimalBlackRenderState` 必须提供：

```swift
struct MinimalBlackRenderState: Equatable, Sendable {
    static let empty = MinimalBlackRenderState(
        stableWindowText: "",
        volatileTailText: "",
        visibleCharacterCount: 0
    )
    private(set) var stableWindowText: String
    private(set) var volatileTailText: String
    var visibleCharacterCount: Int
    var displayText: String { stableWindowText + volatileTailText }
    var stableCharacterCount: Int { stableWindowText.count }

    mutating func apply(stableWindowText: String, volatileTailText: String) {
        self.stableWindowText = stableWindowText
        self.volatileTailText = volatileTailText
    }
}
```

`MinimalBlackPreviewView` 必须是全新 View，不复用 `RecordingCapsuleView`；尺寸 `252 x 40`，移除“候选”徽标后文字从 `x=14` 开始。无文字时显示录音状态和轻量波形；有文字时稳定区白色、可变尾巴低透明灰色。

- [x] **Step 4: 创建独立 Presenter 并接入生产路由**

```swift
final class MinimalBlackPreviewPresenter: PreviewPresenting {
    static let panelSize = NSSize(width: 252, height: 40)
    var onCycleMode: (() -> Void)?
    var presentationFrame: CGRect? { panel.frame }

    func updateDraft(_ snapshot: PreviewDisplaySnapshot) {
        applyContent(
            stableWindowText: snapshot.stableWindowText,
            volatileTailText: snapshot.volatileTailText
        )
    }
}
```

- 面板作为唯一主胶囊显示在 `MainCapsulePanelShell` 的底部中心锚点。
- 不使用历史 `ThreeCapsuleLayout`，不相邻定位，不订阅状态流。
- `show`、`hideAnimated`、`updateDraft`、`updateBands`、`updateInputLevel` 完整实现；其余主胶囊命令保持无副作用兼容。
- `.minimalBlack` 路由改为 `MinimalBlackPreviewPresenter()`；`.classic` 和 `.notch` 不变。

- [x] **Step 5: 运行 GREEN**

```bash
xcrun swiftc \
  native/Sources/Presentation/MinimalBlackPreview/MinimalBlackRenderState.swift \
  native/Sources/Presentation/MinimalBlackPreview/MinimalBlackTextMotion.swift \
  native/Tests/MinimalBlackPresentationCheck.swift \
  -o /tmp/minimal-black-presentation-check
/tmp/minimal-black-presentation-check
bash native/Tests/MinimalBlackThemeRoutingBoundaryCheck.sh
bash native/Tests/PreviewThemeRoutingBoundaryCheck.sh
bash native/Tests/ProductionPreviewSourceIndependenceBoundaryCheck.sh
git diff --check
```

Expected: 全部 PASS。

Evidence: 展示状态、12字动画欠账、主题路由和生产订阅隔离测试通过；全量 Swift `-typecheck -warnings-as-errors` 通过。

- [x] **Step 6: 更新证据并提交**

```bash
git add native/Sources/Presentation/MinimalBlackPreview \
  native/Sources/Application/SpeechInputCoordinator.swift \
  native/Tests/MinimalBlackPresentationCheck.swift \
  native/Tests/MinimalBlackThemeRoutingBoundaryCheck.sh \
  native/Tests/PreviewThemeRoutingBoundaryCheck.sh \
  docs/superpowers/plans/2026-07-23-minimal-black-candidate-ui-recovery.md
git diff --cached --check
git commit -m "feat: restore candidate UI as minimal black theme"
```

---

### Task 2: 删除错误黑色换肤且恢复经典胶囊单一实现

**Status:** Completed

**Files:**

- Delete: `native/Sources/Presentation/Capsule/MainCapsuleVisualStyle.swift`
- Delete: `native/Tests/MainCapsuleVisualStyleCheck.swift`
- Create: `native/Tests/MinimalBlackSkinRetirementBoundaryCheck.sh`
- Modify: `native/Sources/Presentation/Capsule/RecordingPanel.swift`
- Modify: `native/Sources/Presentation/Capsule/RecordingCapsuleView.swift`
- Modify: `native/Sources/Application/SpeechInputCoordinator.swift`
- Modify: `docs/superpowers/plans/2026-07-23-minimal-black-candidate-ui-recovery.md`

**Interfaces:**

- `RecordingPanel` 恢复为经典主题唯一实现：`init()`，不接受视觉样式参数。
- `RecordingCapsuleView` 恢复直接使用 `UITheme` 颜色和固定 `volatileTailAlpha = 0.72`。
- `.minimalBlack` 已由 Task 1 的独立 Presenter 接管。

- [x] **Step 1: 写垃圾代码退休 RED**

```bash
test ! -f native/Sources/Presentation/Capsule/MainCapsuleVisualStyle.swift
test ! -f native/Tests/MainCapsuleVisualStyleCheck.swift
! rg -n 'MainCapsuleVisualStyle|visualStyle' \
  native/Sources/Presentation/Capsule/RecordingPanel.swift \
  native/Sources/Presentation/Capsule/RecordingCapsuleView.swift
! rg -n 'RecordingPanel\\(visualStyle:' native/Sources native/Tests
grep -Fq 'popup = RecordingPanel()' native/Sources/Application/SpeechInputCoordinator.swift
grep -Fq 'popup = MinimalBlackPreviewPresenter()' native/Sources/Application/SpeechInputCoordinator.swift
```

- [x] **Step 2: 运行 RED**

Run: `bash native/Tests/MinimalBlackSkinRetirementBoundaryCheck.sh`
Expected: `MainCapsuleVisualStyle.swift` 仍存在，FAIL。

Evidence: 退休边界测试以 exit 1 失败，确认测试能捕获仍存在的换肤文件。

- [x] **Step 3: 用提交差异逐项恢复经典实现**

以 `git show 21865314^..21865314` 作为删除清单，只撤销 `visualStyle` 相关行。不得整体覆盖 `RecordingPanel.swift` 或 `RecordingCapsuleView.swift`，避免删除 218 之后加入的主胶囊功能。

- [x] **Step 4: 运行 GREEN 与经典胶囊回归**

```bash
bash native/Tests/MinimalBlackSkinRetirementBoundaryCheck.sh
bash native/Tests/MinimalBlackThemeRoutingBoundaryCheck.sh
bash native/Tests/MainCapsulePreviewTextMigrationBoundaryCheck.sh
bash native/Tests/MainCapsuleContextMigrationBoundaryCheck.sh
bash native/Tests/MainCapsuleStatusMigrationBoundaryCheck.sh
bash native/Tests/MainCapsuleWaveformMigrationBoundaryCheck.sh
bash native/Tests/MainCapsuleIdeaPillMigrationBoundaryCheck.sh
bash native/Tests/MainCapsuleOpenClawMigrationBoundaryCheck.sh
git diff --check
```

Evidence: 换肤退休、独立 MinimalBlack 路由及六项经典胶囊功能回归通过；全量 Swift `-typecheck -warnings-as-errors` 通过。

- [x] **Step 5: 更新证据并提交**

```bash
git add -A -- \
  native/Sources/Presentation/Capsule/MainCapsuleVisualStyle.swift \
  native/Tests/MainCapsuleVisualStyleCheck.swift
git add native/Sources/Presentation/Capsule/RecordingPanel.swift \
  native/Sources/Presentation/Capsule/RecordingCapsuleView.swift \
  native/Sources/Application/SpeechInputCoordinator.swift \
  native/Tests/MinimalBlackSkinRetirementBoundaryCheck.sh \
  docs/superpowers/plans/2026-07-23-minimal-black-candidate-ui-recovery.md
git diff --cached --check
git commit -m "refactor: remove minimal black skin implementation"
```

---

### Task 3: 收紧唯一数据源、无垃圾代码和旁路隔离门禁

**Status:** Completed

**Files:**

- Create: `native/Tests/MinimalBlackProductionBoundaryCheck.sh`
- Modify: `native/Tests/CandidatePreviewRetirementBoundaryCheck.sh`
- Modify: `native/Tests/PreviewSubscribersBoundaryCheck.sh`
- Modify: `docs/ARCHITECTURE.md`
- Modify: `docs/开发日志.md`
- Modify: `docs/superpowers/plans/2026-07-23-minimal-black-theme-candidate-retirement.md`
- Modify: `docs/superpowers/plans/2026-07-23-minimal-black-candidate-ui-recovery.md`

**Interfaces:**

- 产品主题只存在 `RecordingPanel`、`NotchPreviewPresenter`、`MinimalBlackPreviewPresenter`。
- 诊断窗口只存在 `ShadowPreviewPresenter`。
- Candidate 命名 Presentation/runtime 必须继续为零。

- [x] **Step 1: 写结构边界 RED**

```bash
grep -Fq 'final class MinimalBlackPreviewPresenter: PreviewPresenting' "$PRESENTER"
grep -Fq 'func updateDraft(_ snapshot: PreviewDisplaySnapshot)' "$PRESENTER"
! rg -n 'AsyncStream|PreviewViewState|Shadow|Provider|Reconciler|FinalDelivery|Paste' "$MINIMAL_DIR"
! rg -n 'CandidatePreview(View|Presenter|Coordinator)|ThreeCapsuleLayout' native/Sources
```

- [x] **Step 2: 运行边界测试**

```bash
bash native/Tests/MinimalBlackProductionBoundaryCheck.sh
bash native/Tests/CandidatePreviewRetirementBoundaryCheck.sh
bash native/Tests/PreviewSubscribersBoundaryCheck.sh
bash native/Tests/ShadowPreviewRuntimeGateBoundaryCheck.sh
bash native/Tests/OnlineASRShadowIsolationCheck.sh
bash native/Tests/RealtimePreviewDeliveryCacheWiringCheck.sh
bash native/Tests/UnifiedRealtimeSourceBoundaryCheck.sh
```

Evidence: MinimalBlack 生产边界、候选退休、生产/旁路订阅隔离、旁路 gate、在线隔离、交付缓存和统一数据源七项测试通过。

- [x] **Step 3: 更新架构和历史计划**

必须记录：Build 804 的黑色换肤被独立 Presenter 取代；只恢复历史 Candidate 的 UI/展示机制，没有恢复 runtime；三个主主题共享唯一生产接口；旁路仍是唯一诊断窗口；换肤文件已删除。

- [x] **Step 4: 更新证据并提交**

```bash
git add native/Tests/MinimalBlackProductionBoundaryCheck.sh \
  native/Tests/CandidatePreviewRetirementBoundaryCheck.sh \
  native/Tests/PreviewSubscribersBoundaryCheck.sh \
  docs/ARCHITECTURE.md docs/开发日志.md \
  docs/superpowers/plans/2026-07-23-minimal-black-theme-candidate-retirement.md \
  docs/superpowers/plans/2026-07-23-minimal-black-candidate-ui-recovery.md
git diff --cached --check
git commit -m "test: enforce minimal black production boundary"
```

---

### Task 4: 完整测试、Build 805 和真实安装版验收

**Status:** Completed

**Files:**

- Modify: `native/Sources/Presentation/VersionHistory/VersionHistoryViewController.swift`
- Modify: `docs/开发日志.md`
- Modify: `docs/构建日志.md`（构建脚本）
- Modify: `README.md`（构建脚本）
- Modify: `macos/README.md`（构建脚本）
- Modify: `native/build_native_app.sh`（构建脚本）
- Modify: `docs/superpowers/plans/2026-07-23-minimal-black-candidate-ui-recovery.md`

**Interfaces:**

- 日常构建目标：`2.0.58 (Build 805)`。
- 真实安装版默认选中简洁黑色进行视觉检查，之后由用户用物理 Fn 做录音验收。

- [x] **Step 1: 运行完整相关测试**

```bash
bash native/Tests/MinimalBlackThemeRoutingBoundaryCheck.sh
bash native/Tests/MinimalBlackSkinRetirementBoundaryCheck.sh
bash native/Tests/MinimalBlackProductionBoundaryCheck.sh
bash native/Tests/PreviewThemeRoutingBoundaryCheck.sh
bash native/Tests/CandidatePreviewRetirementBoundaryCheck.sh
bash native/Tests/PreviewSubscribersBoundaryCheck.sh
bash native/Tests/ShadowPreviewRuntimeGateBoundaryCheck.sh
bash native/Tests/OnlineASRShadowIsolationCheck.sh
bash native/Tests/ProductionPreviewSourceIndependenceBoundaryCheck.sh
bash native/Tests/MainCapsulePreviewTextMigrationBoundaryCheck.sh
bash native/Tests/UnifiedRealtimeSourceBoundaryCheck.sh
bash native/Tests/RealtimeRecognitionQualityBoundaryCheck.sh
bash native/Tests/TranscriptionProviderBoundaryCheck.sh
git diff --check
```

Evidence: 13 组相关边界测试全部通过；全量 Swift 源码使用 `-warnings-as-errors` 类型检查通过；`git diff --check` 通过。

- [x] **Step 2: 更新 Build 805 版本叙事**

版本历史必须说明：恢复候选独立 UI 为简洁黑色主题、仍使用生产缓存、删除 Build 804 换肤实现、未恢复候选 runtime。

Evidence: `VersionHistoryViewController` 已新增 Build 805 条目，开发日志已记录纠偏边界和验证状态。

- [x] **Step 3: 并发复核后执行唯一一次日常构建**

```bash
git branch --show-current
git status --short
pgrep -af 'build_and_log\\.sh|release_local_build\\.sh|build_native_app\\.sh|swiftc|xcodebuild' || true
./native/build_and_log.sh
```

Expected: `2.0.58 (805)` 编译、覆盖安装、打开、验签和日志写入成功。

Evidence: 并发检查无活动构建进程；`./native/build_and_log.sh` 唯一一次执行成功，安装版为 `2.0.58 (805)`，启动和 codesign 校验通过，构建日志累计 `#308`。

- [x] **Step 4: 使用 `design-review` 检查安装版**

检查简洁黑色与默认胶囊在尺寸、表面、边框和文本展示上明显不同；无候选标签；三主题选中态正确；旁路关闭无额外窗口。自动化无法发送硬件 Fn 时，明确记录波形、逐字动画、旁路双窗和粘贴为用户实录项，不伪报。

Evidence: 安装版三个主题可切换；简洁黑色选中态明确，缩略图为独立窄黑面板、绿色细边和左侧状态点，与默认胶囊明显不同；没有“候选”标签，旁路关闭。复核记录位于 `~/.gstack/projects/Allenth-TypeWhale/designs/design-audit-20260723-build805/`。硬件 Fn 路径未伪报通过。

- [x] **Step 5: 更新计划为 Completed 并提交构建记录**

```bash
git add README.md macos/README.md native/build_native_app.sh \
  native/Sources/Presentation/VersionHistory/VersionHistoryViewController.swift \
  docs/开发日志.md docs/构建日志.md \
  docs/superpowers/plans/2026-07-23-minimal-black-candidate-ui-recovery.md
git diff --cached --check
git commit -m "feat: ship recovered minimal black capsule theme"
```

Evidence: Task 4 状态、测试、构建和视觉证据已回写；最终提交在完成新鲜验证后固化。

---

## Completion Gate

- `.minimalBlack` 创建 `MinimalBlackPreviewPresenter`，不再创建带样式的 `RecordingPanel`。
- 简洁黑色 View 不复用 `RecordingCapsuleView`，不存在“候选”标签。
- `MainCapsuleVisualStyle.swift`、其测试和所有 `visualStyle` 分支已删除。
- Candidate Presentation/runtime、三胶囊布局和重复订阅继续不存在。
- 旁路诊断、本地/MiMo/豆包 Provider 测试能力保留。
- 默认、刘海、闪念、OpenClaw、生产缓存和最终粘贴边界测试通过。
- Build 805 编译、覆盖安装、启动和验签通过。
- `design-review` 完成；无法自动完成的物理 Fn 实录项被明确记录。
- 所有 Task 状态、RED/GREEN 证据和提交均回写本文。

---

### Task 5: 解耦胶囊可见性、主窗口实时文本和重叠矫正

**Status:** Completed

**Root cause:** 当前 `realtimePreviewEnabled` 同时控制桌面胶囊、`AudioRecorder` 实时快照和 `ExperimentalPreviewSettings.normalized`。关闭胶囊后，录音器不再产出实时数据，重叠矫正也被强制归一化为关闭，导致主窗口实时文本同步消失。

**Scope:**

- “胶囊实时预览”只控制桌面胶囊是否显示。
- 主窗口实时文本和生产实时缓存始终继续接收实时快照。
- “重叠矫正”只受自身开关和 SenseVoice 能力约束，不受胶囊可见性影响。
- 不改识别算法、分块时长、缓存合并、Final ASR 或最终粘贴。

- [x] **Step 1: 写两个联动问题的 RED**
- [x] **Step 2: 最小化拆分可见性和实时数据接线**
- [x] **Step 3: 完整回归、更新架构与开发日志**
- [x] **Step 4: 日常 Build 806、覆盖安装并提交**

Evidence: 新边界测试先因缺少独立可见性/数据变量退出 1，设置测试先因旧归一化 API 编译失败；修复后两项转绿。相关七组边界回归和全源码 `-warnings-as-errors` 类型检查通过。

Build evidence: `2.0.58 (Build 806)` 已编译、覆盖安装、打开并通过 codesign 校验，构建日志累计 `#309`。

**Acceptance:**

- Build 806 对本条理解错误：关闭开关时隐藏了整个胶囊。真实产品定义见 Task 6。
- 关闭胶囊不会改变“重叠矫正”的保存值、可用状态或下一轮运行状态。
- 重新打开胶囊后无需恢复其他设置，下一轮录音正常显示。

---

### Task 6: 恢复“胶囊实时预览”的原始产品语义

**Status:** Completed

**Confirmed contract:** `README.md` 明确规定：开启后录音胶囊显示实时预览文字；关闭后仍进行最终识别和粘贴。历史代码始终执行 `popup.show()`，因此该开关控制的是胶囊文字，不是整个胶囊可见性。

**Architecture review:** `Accepted`。文字展示门属于 `ProductionPreviewTextCoordinator` 的投递职责；胶囊生命周期、声波、主窗口、完整缓存和矫正均不应依赖该门。拒绝在 Presenter 内处理数据，也拒绝重新关闭实时识别。

**Scope:**

- 保留 Task 5 已完成的数据层与重叠矫正解耦。
- 录音开始时始终显示胶囊及其状态、声波。
- 在 `ProductionPreviewTextCoordinator` 展示投递边界控制是否向胶囊发送文字快照。
- 主窗口实时文本、生产缓存、识别、Final ASR 和粘贴不变。

- [x] **Step 1: 写“胶囊始终显示、文字可关闭”的 RED**
- [x] **Step 2: 增加展示投递门并删除 Build 806 的隐藏分支**
- [x] **Step 3: 回归、文档纠偏、Build 807 与提交**

Evidence: Swift 行为测试先因 `begin(states:deliversText:)` 不存在而编译失败；边界测试先因录音开始仍调用 `popup.hideAnimated()` 而退出 1。实现后五项展示/订阅/生命周期边界测试和全源码严格类型检查通过。

Build evidence: `2.0.58 (Build 807)` 已编译、覆盖安装、打开并通过 codesign 校验，构建日志累计 `#310`。

**Acceptance:**

- 开关开启：胶囊显示状态、声波和实时文字。
- 开关关闭：胶囊仍显示状态与声波，但不出现实时文字。
- 两种状态下主窗口实时文本、完整缓存、重叠矫正和最终粘贴一致工作。

---

### Task 7: 补齐 Fn 与胶囊显示诊断链路

**Status:** Completed

**Problem:** 安装版偶发需要按两次 Fn。现有日志只记录成功的 `recording_start`，无法区分第一次按键未进入监听器、未进入业务处理器，还是录音已启动但胶囊未真正显示。

**Scope:**

- 只增加诊断日志，不改变 Fn 触发语义、录音状态机、主题、动效、识别、缓存或粘贴。
- 记录 HotkeyMonitor 的 Fn down/up 事件。
- 记录 SpeechInputCoordinator 的 down/up 处理入口。
- 记录胶囊 show 请求，以及 classic、notch、minimalBlack 三种正式主题 show 后的可见性、透明度和 frame。
- 不记录语音正文、按键内容或用户输入。

- [x] **Step 1: 写完整诊断链路 RED**
- [x] **Step 2: 最小化补充事件与显示结果日志**
- [x] **Step 3: 回归、更新日志、Build 808 与提交**

Evidence: `HotkeyCapsuleVisibilityDiagnosticsBoundaryCheck` 先因八个诊断点全部不存在而退出 1；最小实现后转绿。胶囊展示门、主胶囊声波和 MinimalBlack 生产边界回归通过。

Build evidence: `2.0.58 (Build 808)` 已编译、覆盖安装、打开并通过 codesign 校验，构建日志累计 `#311`。

**Acceptance:**

- 下一次复现时，单份日志可明确判断断点位于监听器、业务处理器、录音启动还是胶囊显示。
- 正常录音、停止、预览文字、声波和粘贴行为完全不变。

---

### Task 8: 修复唤醒后第一次 Fn 被吞

**Status:** Completed

**Root cause:** Build 808 日志证明第一次 Fn 的 down/up 均进入监听器和业务处理器，但没有进入录音启动。向上追踪发现 `cancelRecordingForSystemSleep` 在空闲睡眠时仍无条件设置 `suppressNextHotkeyUp = true`，导致唤醒后的第一次正常 Fn 松开被消费。第二次 Fn 才能启动。

**Scope:**

- 只修睡眠取消路径的抑制标记。
- 睡眠时 Fn 正在按住：继续忽略唤醒后的对应松开，避免误启动。
- 空闲睡眠：不留下抑制标记，唤醒后第一次 Fn 正常启动。
- 不改快捷键语义、胶囊、录音、识别、缓存或粘贴。

- [x] **Step 1: 写空闲睡眠不得吞键的 RED**
- [x] **Step 2: 将无条件抑制改为按真实按键状态抑制**
- [x] **Step 3: 回归、开发日志、Build 809 与提交**

Evidence: Build 808 实际日志显示第一次 Fn 的监听器和业务入口均正常，但没有 `recording_start`；第二次才启动。`HotkeyWakeSuppressionBoundaryCheck` 先因无条件抑制失败，并额外锁定必须先读取真实按键状态、再清零状态。修复后空闲恢复、诊断链和展示门回归通过。

Build evidence: `2.0.58 (Build 809)` 已编译、覆盖安装、打开并通过 codesign 校验，构建日志累计 `#312`。

**Acceptance:**

- 睡眠唤醒后第一次 Fn 即可启动录音。
- 睡眠发生时若 Fn 正被按住，唤醒后的孤立松开不会误启动录音。
