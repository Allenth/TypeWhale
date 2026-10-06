# 简洁黑色主题与候选胶囊退休 Implementation Plan

> **Superseded on 2026-07-23:** 本计划错误地把“候选 UI 转正为新主题”实现成 `RecordingPanel` 黑色换肤。当前纠正计划为 `2026-07-23-minimal-black-candidate-ui-recovery.md`；本文仅保留历史证据，不再作为实现依据。

> **Correction progress:** 新计划 Task 1–3 已将独立 UI 接入生产接口并删除 `MainCapsuleVisualStyle` 换肤实现；不得从本文恢复该换肤设计。

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将候选胶囊的黑色视觉风格迁移为主胶囊第三主题，删除候选独立窗口和 runtime，同时完整保留旁路诊断能力。

**Architecture:** 主胶囊继续只消费生产实时状态；简洁黑色是 `RecordingPanel` 的独立视觉样式，不创建候选数据链路。旁路继续通过 `ShadowTranscriptionRuntime → ShadowPreviewCoordinator` 展示技术结果。主题切换时必须同步替换 `ProductionPreviewTextCoordinator` 的文字接收对象，避免文字继续发往旧窗口。

**Tech Stack:** Swift、AppKit、现有 `PreviewPresenting` / `RecordingPanel` / `ProductionPreviewTextCoordinator`、shell/Swift 边界测试、`design-review`、`native/build_and_log.sh`。

## Global Constraints

- 默认只在主目录 `$HOME/Pictures/macOSwinOSCoding/TypeSpeaker` 开发，不新建 worktree。
- 每次只执行一个 Task；每个 Task 开工前重读本文，完成后更新状态和证据。
- 不修改 ASR、实时分块、Reducer、生产缓存、Final ASR、最终粘贴或在线 Provider 协议。
- 简洁黑色只改变主胶囊视觉，不订阅 `ShadowTranscriptionRuntime` 或任何候选状态流。
- 旁路胶囊、在线 Provider、Key 设置和旁路诊断日志必须保留。
- 闪念胶囊和 OpenClaw 继续强制使用经典主题。
- `CandidateDeliverySnapshot`、`CandidateTranscriptQualityGate` 等 Application/Domain 层类型不是候选 UI，禁止因为名称相同而删除。
- 不读取、修改、提交当前受保护的未跟踪目录：
  - `native/Helpers/CapsuleConceptGallery/`
  - `native/Sources/Presentation/Capsule/Concepts/`
- 每个代码 Task 使用 RED → GREEN → 回归测试 → 更新本文 → commit。
- 所有代码 Task 完成后执行一次真实日常构建：`./native/build_and_log.sh`；必须递增 build 号、覆盖安装、打开和验签。
- UI 修改完成后必须使用 `design-review` 对真实安装版复核；无法覆盖的状态必须明确记录。

---

## File Structure

### 新建

- `native/Sources/Presentation/Capsule/MainCapsuleVisualStyle.swift`
  只定义经典与简洁黑色两套颜色、材质和描边参数，不包含状态、文字或 Provider 逻辑。
- `native/Tests/MainCapsuleVisualStyleCheck.swift`
  验证简洁黑色主题没有候选标签语义，并与经典主题具有独立视觉参数。
- `native/Tests/PreviewThemeRoutingBoundaryCheck.sh`
  验证三主题路由、文字 sink 重绑定和闪念/OpenClaw 的经典主题边界。
- `native/Tests/CandidatePreviewRetirementBoundaryCheck.sh`
  验证候选 Presentation/runtime 已删除而旁路仍存在。

### 修改

- `native/Sources/Infrastructure/Settings/AppSettings.swift`
  增加 `PreviewTheme.minimalBlack`。
- `native/Sources/Application/RealtimeTranscription/ProductionPreviewTextCoordinator.swift`
  允许在录音开始前替换 `ProductionPreviewTextSink`。
- `native/Sources/Application/SpeechInputCoordinator.swift`
  路由第三主题、同步更新 sink；删除候选 Coordinator/runtime，只保留旁路。
- `native/Sources/Presentation/Capsule/RecordingPanel.swift`
  接收 `MainCapsuleVisualStyle` 并把样式交给胶囊视图及信息栏。
- `native/Sources/Presentation/Capsule/RecordingCapsuleView.swift`
  使用视觉样式绘制背景强调、默认描边、正文和可变尾巴。
- `native/Sources/Presentation/Main/MainViewController.swift`
  增加简洁黑色主题卡片引用。
- `native/Sources/Presentation/Main/MainViewController+PanelLayout.swift`
  增加第三张主题卡片和选中状态。
- `native/Sources/Presentation/Main/ThemePreviewTile.swift`
  绘制不含“候选”标签的简洁黑色缩略图。
- `native/Sources/Presentation/ShadowPreview/ShadowPreviewPresenter.swift`
  从三胶囊布局切回已有 `ShadowPreviewLayout`。
- 现有边界测试
  移除对 `Presentation/CandidatePreview` 和三胶囊结构的过时要求，改为验证单主胶囊 + 可选旁路。
- `docs/ARCHITECTURE.md`、`docs/开发日志.md`、应用内版本历史和本文
  记录候选退休、旁路保留和构建结果。

### 删除

- `native/Sources/Presentation/CandidatePreview/`
- `native/Sources/Presentation/ShadowPreview/ThreeCapsuleLayout.swift`
- 只验证候选窗口、动画和三胶囊布局的测试：
  - `CandidateContentProjectionCheck.swift`
  - `CandidatePresentationModelCheck.swift`
  - `CandidatePreviewLifecycleCheck.swift`
  - `CandidatePreviewRenderBoundaryCheck.sh`
  - `CandidateProviderMatrixCheck.swift`
  - `CandidateTextMotionCheck.swift`
  - `CandidateWindowUpdatePolicyCheck.swift`
  - `ThreeCapsuleLayoutCheck.swift`
  - `ThreeCapsuleWiringCheck.sh`
  - `Stage9AManualGateBoundaryCheck.sh`

---

### Task 1: 主题切换时重绑定生产文字接收对象

**Status:** Completed

**Files:**

- Modify: `native/Sources/Application/RealtimeTranscription/ProductionPreviewTextCoordinator.swift`
- Create: `native/Tests/ProductionPreviewSinkRebindingCheck.swift`
- Modify: `native/Tests/ProductionPreviewSourceIndependenceBoundaryCheck.sh`
- Modify: `docs/superpowers/plans/2026-07-23-minimal-black-theme-candidate-retirement.md`

**Interfaces:**

- Consumes: `ProductionPreviewTextSink`
- Produces: `func replaceSink(_ sink: any ProductionPreviewTextSink)`
- Invariant: 当前 `PreviewPresenting` 必须在 `begin(states:)` 前成为生产文字 sink。

**Baseline evidence:** 2026-07-23 开工检查发现
`ProductionPreviewSourceIndependenceBoundaryCheck.sh` 把
`publishShadowPreview(productSnapshot` 写死为单行调用；当前源码使用多行参数，
导致测试解析失败。实际源码仍保持先 consume 生产桥、再 publish 旁路的正确顺序。
本 Task 同步把测试改为定位 `publishShadowPreview(`，不改变生产行为。

- [x] **Step 1: 写 sink 切换 RED**

在 `ProductionPreviewSinkRebindingCheck.swift` 增加两个 fake sink：先构造 coordinator，再调用 `replaceSink(secondSink)`，输入一条 `PreviewViewState` 后断言只有第二个 sink 收到 `PreviewDisplaySnapshot`。

核心断言：

```swift
coordinator.replaceSink(secondSink)
coordinator.begin(states: stream)
continuation.yield(state(sequence: 1, text: "第三主题收到文字"))
await waitUntil { secondSink.snapshots.last?.displayText == "第三主题收到文字" }
precondition(firstSink.snapshots.isEmpty)
```

- [x] **Step 2: 运行 RED**

Run:

```bash
swiftc \
  native/Sources/Domain/RealtimePreview/PreviewDisplaySnapshot.swift \
  native/Sources/Domain/RealtimeTranscription/TranscriptionIdentity.swift \
  native/Sources/Domain/RealtimeTranscription/TranscriptionEvent.swift \
  native/Sources/Domain/RealtimeTranscription/TranscriptState.swift \
  native/Sources/Domain/RealtimeTranscription/PreviewViewState.swift \
  native/Sources/Application/RealtimeTranscription/PreviewDisplaySnapshotProjector.swift \
  native/Sources/Application/RealtimeTranscription/ProductionPreviewTextCoordinator.swift \
  native/Tests/ProductionPreviewSinkRebindingCheck.swift \
  -o /tmp/ProductionPreviewSinkRebindingCheck
```

Expected: `replaceSink` 不存在或主题切换未调用重绑定，测试失败。

RED evidence: 编译按预期失败，错误为
`ProductionPreviewTextCoordinator has no member replaceSink`。

- [x] **Step 3: 实现可替换 sink**

将 coordinator 的不可变 sink 改为弱引用，并增加：

```swift
private weak var sink: (any ProductionPreviewTextSink)?

func replaceSink(_ sink: any ProductionPreviewTextSink) {
    precondition(subscriptionTask == nil, "Preview sink may change only between sessions")
    self.sink = sink
}
```

投递时使用：

```swift
guard let sink = self.sink else { continue }
sink.updateDraft(snapshot)
```

- [x] **Step 4: 运行 GREEN 与现有生产桥测试**

Run:

```bash
swiftc \
  native/Sources/Domain/RealtimePreview/PreviewDisplaySnapshot.swift \
  native/Sources/Domain/RealtimeTranscription/TranscriptionIdentity.swift \
  native/Sources/Domain/RealtimeTranscription/TranscriptionEvent.swift \
  native/Sources/Domain/RealtimeTranscription/TranscriptState.swift \
  native/Sources/Domain/RealtimeTranscription/PreviewViewState.swift \
  native/Sources/Application/RealtimeTranscription/PreviewDisplaySnapshotProjector.swift \
  native/Sources/Application/RealtimeTranscription/ProductionPreviewTextCoordinator.swift \
  native/Tests/ProductionPreviewSinkRebindingCheck.swift \
  -o /tmp/ProductionPreviewSinkRebindingCheck && /tmp/ProductionPreviewSinkRebindingCheck
bash native/Tests/ProductionPreviewSourceIndependenceBoundaryCheck.sh
bash native/Tests/MainCapsulePreviewTextMigrationBoundaryCheck.sh
```

Expected: 全部 PASS。

- [x] **Step 5: 更新本文 Task 1 状态和测试证据并提交**

```bash
git add native/Sources/Application/RealtimeTranscription/ProductionPreviewTextCoordinator.swift \
  native/Tests/ProductionPreviewSinkRebindingCheck.swift \
  native/Tests/ProductionPreviewSourceIndependenceBoundaryCheck.sh \
  docs/superpowers/plans/2026-07-23-minimal-black-theme-candidate-retirement.md
git commit -m "fix: rebind production preview sink on theme change"
```

**Completion evidence:** `ProductionPreviewSinkRebindingCheck`、
`ProductionPreviewSourceIndependenceBoundaryCheck`、
`MainCapsulePreviewTextMigrationBoundaryCheck` 和 `git diff --check` 全部通过。

---

### Task 2: 增加简洁黑色主胶囊视觉样式

**Status:** Completed

**Files:**

- Create: `native/Sources/Presentation/Capsule/MainCapsuleVisualStyle.swift`
- Create: `native/Tests/MainCapsuleVisualStyleCheck.swift`
- Modify: `native/Sources/Presentation/Capsule/RecordingPanel.swift`
- Modify: `native/Sources/Presentation/Capsule/RecordingCapsuleView.swift`
- Modify: `docs/superpowers/plans/2026-07-23-minimal-black-theme-candidate-retirement.md`

**Interfaces:**

- Produces:

```swift
enum MainCapsuleVisualStyle: Equatable {
    case classic
    case minimalBlack
}
```

- `RecordingPanel.init(visualStyle: MainCapsuleVisualStyle = .classic)`
- `RecordingCapsuleView.visualStyle: MainCapsuleVisualStyle`
- Invariant: style 只提供颜色/材质/描边；现有 `MainCapsuleState`、文字缓冲、波形、状态和尺寸逻辑不变。

- [x] **Step 1: 写视觉样式 RED**

测试必须断言：

```swift
precondition(MainCapsuleVisualStyle.classic != .minimalBlack)
precondition(MainCapsuleVisualStyle.minimalBlack.backgroundKind == .solidBlack)
precondition(MainCapsuleVisualStyle.minimalBlack.defaultBorderKind == .subduedGreen)
precondition(MainCapsuleVisualStyle.classic.defaultBorderKind == .waterInkAccent)
```

- [x] **Step 2: 编译 RED**

Run:

```bash
swiftc native/Sources/Presentation/Capsule/MainCapsuleVisualStyle.swift \
  native/Tests/MainCapsuleVisualStyleCheck.swift \
  -o /tmp/MainCapsuleVisualStyleCheck
```

Expected: 新类型不存在，编译失败。

RED evidence: 编译按预期失败，错误为
`MainCapsuleVisualStyle.swift: No such file or directory`。

- [x] **Step 3: 实现样式值对象**

样式只暴露展示参数：

```swift
enum MainCapsuleBackgroundKind: Equatable {
    case visualEffect
    case solidBlack
}

enum MainCapsuleBorderKind: Equatable {
    case waterInkAccent
    case subduedGreen
}

enum MainCapsuleVisualStyle: Equatable {
    case classic
    case minimalBlack

    var backgroundKind: MainCapsuleBackgroundKind {
        switch self {
        case .classic: return .visualEffect
        case .minimalBlack: return .solidBlack
        }
    }

    var backgroundColor: NSColor {
        switch self {
        case .classic: return .clear
        case .minimalBlack: return NSColor(calibratedWhite: 0.055, alpha: 0.94)
        }
    }

    var defaultBorderKind: MainCapsuleBorderKind {
        switch self {
        case .classic: return .waterInkAccent
        case .minimalBlack: return .subduedGreen
        }
    }

    var defaultBorderColor: NSColor {
        switch self {
        case .classic: return UITheme.capsuleAccent.withAlphaComponent(0.44)
        case .minimalBlack:
            return NSColor(calibratedRed: 0.55, green: 0.69, blue: 0.42, alpha: 0.58)
        }
    }

    var primaryTextColor: NSColor {
        switch self {
        case .classic: return UITheme.capsuleText
        case .minimalBlack: return NSColor(calibratedWhite: 0.94, alpha: 0.94)
        }
    }

    var volatileTextAlpha: CGFloat {
        switch self {
        case .classic: return 0.72
        case .minimalBlack: return 0.62
        }
    }
}
```

`RecordingPanel` 根据 `backgroundKind` 配置现有 `NSVisualEffectView`，不新增窗口；`RecordingCapsuleView` 只把硬编码主题色替换成样式属性，不改变文字和波形状态机。

- [x] **Step 4: 运行视觉值对象和主胶囊状态回归**

Run:

```bash
swiftc native/Sources/Presentation/Capsule/MainCapsuleVisualStyle.swift \
  native/Tests/MainCapsuleVisualStyleCheck.swift \
  -o /tmp/MainCapsuleVisualStyleCheck && /tmp/MainCapsuleVisualStyleCheck
bash native/Tests/MainCapsuleShellBoundaryCheck.sh
bash native/Tests/MainCapsuleStatusMigrationBoundaryCheck.sh
bash native/Tests/MainCapsuleWaveformMigrationBoundaryCheck.sh
```

Expected: 全部 PASS。

- [x] **Step 5: 更新本文 Task 2 状态和证据并提交**

```bash
git add native/Sources/Presentation/Capsule/MainCapsuleVisualStyle.swift \
  native/Sources/Presentation/Capsule/RecordingPanel.swift \
  native/Sources/Presentation/Capsule/RecordingCapsuleView.swift \
  native/Tests/MainCapsuleVisualStyleCheck.swift \
  docs/superpowers/plans/2026-07-23-minimal-black-theme-candidate-retirement.md
git commit -m "feat: add minimal black main capsule style"
```

**Completion evidence:** `MainCapsuleVisualStyleCheck`、
`MainCapsuleShellBoundaryCheck`、`MainCapsuleStatusMigrationBoundaryCheck`、
`MainCapsuleWaveformMigrationBoundaryCheck` 和 `git diff --check` 全部通过。
独立样式测试使用最小 `UITheme` stub，避免把设置页和 UI helper 依赖带入值对象测试；
正式 App 仍链接真实 `UITheme`。

---

### Task 3: 接入第三主题和设置卡片

**Status:** Completed

**Files:**

- Modify: `native/Sources/Infrastructure/Settings/AppSettings.swift`
- Modify: `native/Sources/Application/SpeechInputCoordinator.swift`
- Modify: `native/Sources/Presentation/Main/MainViewController.swift`
- Modify: `native/Sources/Presentation/Main/MainViewController+PanelLayout.swift`
- Modify: `native/Sources/Presentation/Main/ThemePreviewTile.swift`
- Create: `native/Tests/PreviewThemeRoutingBoundaryCheck.sh`
- Modify: `docs/superpowers/plans/2026-07-23-minimal-black-theme-candidate-retirement.md`

**Interfaces:**

- Produces: `PreviewTheme.minimalBlack`
- Theme route:

```swift
case .classic:
    popup = RecordingPanel(visualStyle: .classic)
case .notch:
    popup = NotchPreviewPresenter()
case .minimalBlack:
    popup = RecordingPanel(visualStyle: .minimalBlack)
```

- [x] **Step 1: 扩充主题路由 RED**

`PreviewThemeRoutingBoundaryCheck.sh` 必须检查：

```bash
grep -Fq 'case minimalBlack' native/Sources/Infrastructure/Settings/AppSettings.swift
grep -Fq 'RecordingPanel(visualStyle: .minimalBlack)' native/Sources/Application/SpeechInputCoordinator.swift
grep -Fq 'productionPreviewTextCoordinator.replaceSink(popup)' native/Sources/Application/SpeechInputCoordinator.swift
grep -Fq 'ThemePreviewTile(kind: .minimalBlack, title: "简洁黑色")' native/Sources/Presentation/Main/MainViewController+PanelLayout.swift
```

并检查普通听写才使用所选主题，闪念/OpenClaw 仍选择 `.classic`。

- [x] **Step 2: 运行 RED**

```bash
bash native/Tests/PreviewThemeRoutingBoundaryCheck.sh
```

Expected: 缺少 `minimalBlack`，FAIL。

RED evidence: `PreviewThemeRoutingBoundaryCheck.sh` 在
`PreviewTheme.minimalBlack` 检查处按预期退出 1。

- [x] **Step 3: 实现枚举、路由和设置卡片**

- `PreviewTheme` 增加 `.minimalBlack`。
- `SpeechInputCoordinator.applyPreviewTheme` 用明确的 `activePreviewTheme` 判断是否需要替换。
- 替换 `popup` 后依次执行：

```swift
wirePreviewCallbacks()
productionPreviewTextCoordinator.replaceSink(popup)
activePreviewTheme = theme
```

- `ThemePreviewTile.Kind` 增加 `.minimalBlack`，缩略图只画黑色胶囊、低饱和绿色细边和正文条，不画“候选”标签。
- 设置页三张卡片等宽排列并维护清晰选中态。

- [x] **Step 4: 运行主题和设置边界**

```bash
bash native/Tests/PreviewThemeRoutingBoundaryCheck.sh
bash native/Tests/MainCapsuleRetirementSettingsBoundaryCheck.sh
bash native/Tests/MainCapsulePreviewTextMigrationBoundaryCheck.sh
```

Expected: 全部 PASS。

- [x] **Step 5: 更新本文 Task 3 状态和证据并提交**

```bash
git add native/Sources/Infrastructure/Settings/AppSettings.swift \
  native/Sources/Application/SpeechInputCoordinator.swift \
  native/Sources/Presentation/Main/MainViewController.swift \
  native/Sources/Presentation/Main/MainViewController+PanelLayout.swift \
  native/Sources/Presentation/Main/ThemePreviewTile.swift \
  native/Tests/PreviewThemeRoutingBoundaryCheck.sh \
  docs/superpowers/plans/2026-07-23-minimal-black-theme-candidate-retirement.md
git commit -m "feat: expose minimal black capsule theme"
```

**Completion evidence:** `PreviewThemeRoutingBoundaryCheck`、
`MainCapsuleRetirementSettingsBoundaryCheck`、
`MainCapsulePreviewTextMigrationBoundaryCheck`、`MainCapsuleVisualStyleCheck`
和 `git diff --check` 全部通过。闪念/OpenClaw 的经典主题强制路由保持不变。

---

### Task 4: 从运行时删除候选胶囊，保持旁路完整

**Status:** Completed

**Files:**

- Modify: `native/Sources/Application/SpeechInputCoordinator.swift`
- Modify: `native/Sources/Presentation/ShadowPreview/ShadowPreviewPresenter.swift`
- Create: `native/Tests/CandidatePreviewRetirementBoundaryCheck.sh`
- Modify: `native/Tests/PreviewSubscribersBoundaryCheck.sh`
- Modify: `native/Tests/ShadowPreviewRuntimeGateBoundaryCheck.sh`
- Modify: `native/Tests/OnlineASRShadowIsolationCheck.sh`
- Modify: `docs/superpowers/plans/2026-07-23-minimal-black-theme-candidate-retirement.md`

**Interfaces:**

- 保留：`shadowPreviewRuntime`、`ShadowPreviewCoordinator`、`beginShadowAudioFrameDelivery`、本地/MiMo/豆包 Provider。
- 删除：`candidatePreviewCoordinator`、`candidatePreviewRuntime`、`productCandidateRuntime`。
- 旁路布局：`ShadowPreviewLayout.frame(productionFrame:shadowSize:visibleFrame:)`。

- [x] **Step 1: 写候选退休 RED**

`CandidatePreviewRetirementBoundaryCheck.sh` 检查：

```bash
! rg -n 'candidatePreviewCoordinator|candidatePreviewRuntime|productCandidateRuntime' \
  native/Sources/Application/SpeechInputCoordinator.swift
grep -Fq 'private let shadowPreviewCoordinator = ShadowPreviewCoordinator()' \
  native/Sources/Application/SpeechInputCoordinator.swift
grep -Fq 'ShadowPreviewLayout.frame(' \
  native/Sources/Presentation/ShadowPreview/ShadowPreviewPresenter.swift
```

并确认 `OnlineASRProviderFactory`、`MiMoSnapshotProvider`、`DoubaoStreamingTransport` 仍存在。

- [x] **Step 2: 运行 RED**

```bash
bash native/Tests/CandidatePreviewRetirementBoundaryCheck.sh
```

Expected: 候选 Coordinator/runtime 仍存在，FAIL。

RED evidence: 测试列出 `candidatePreviewCoordinator`、`candidatePreviewRuntime`
和 `productCandidateRuntime` 的现存位置后按预期失败。

- [x] **Step 3: 只删除候选运行时**

- `beginShadowPreview` 只创建一个 `ShadowTranscriptionRuntime`。
- `publishShadowPreview` 只调用 `runtime.consume(...)`。
- 停止与取消只完成/取消 shadow runtime。
- 保留 `finishShadowPreviewForFinalDelivery` 返回的 shadow snapshot作为诊断质量报告；`FinalDeliveryUseCase` 继续只选择生产实时缓存。
- `ShadowPreviewPresenter` 使用现有 `ShadowPreviewLayout`，不再依赖候选 panel 尺寸。

- [x] **Step 4: 运行旁路与最终交付回归**

```bash
bash native/Tests/CandidatePreviewRetirementBoundaryCheck.sh
bash native/Tests/PreviewSubscribersBoundaryCheck.sh
bash native/Tests/ShadowPreviewRuntimeGateBoundaryCheck.sh
bash native/Tests/OnlineASRShadowIsolationCheck.sh
bash native/Tests/UnifiedRealtimeSourceBoundaryCheck.sh
bash native/Tests/FinalDeliveryLogBoundaryCheck.sh
```

Expected: 全部 PASS；旁路仍为诊断，生产缓存仍是最终权威。

- [x] **Step 5: 更新本文 Task 4 状态和证据并提交**

```bash
git add native/Sources/Application/SpeechInputCoordinator.swift \
  native/Sources/Presentation/ShadowPreview/ShadowPreviewPresenter.swift \
  native/Tests/CandidatePreviewRetirementBoundaryCheck.sh \
  native/Tests/PreviewSubscribersBoundaryCheck.sh \
  native/Tests/ShadowPreviewRuntimeGateBoundaryCheck.sh \
  native/Tests/OnlineASRShadowIsolationCheck.sh \
  docs/superpowers/plans/2026-07-23-minimal-black-theme-candidate-retirement.md
git commit -m "refactor: retire candidate preview runtime"
```

**Completion evidence:** `CandidatePreviewRetirementBoundaryCheck`、
`PreviewSubscribersBoundaryCheck`、`ShadowPreviewRuntimeGateBoundaryCheck`、
`OnlineASRShadowIsolationCheck`、`UnifiedRealtimeSourceBoundaryCheck`、
`FinalDeliveryLogBoundaryCheck` 和 `git diff --check` 全部通过。旁路仍保留
本地/MiMo/豆包 Provider 和 shadow snapshot 诊断；候选 runtime 已从协调器移除。

---

### Task 5: 删除候选 Presentation 文件和过时测试

**Status:** Completed

**Files:**

- Delete: `native/Sources/Presentation/CandidatePreview/`
- Delete: `native/Sources/Presentation/ShadowPreview/ThreeCapsuleLayout.swift`
- Delete: 本文 File Structure 中列出的候选/三胶囊专用测试
- Modify: `native/Tests/UnifiedRealtimeSourceBoundaryCheck.sh`
- Modify: `native/Tests/RealtimeRecognitionQualityBoundaryCheck.sh`
- Modify: `native/Tests/TranscriptionProviderBoundaryCheck.sh`
- Modify: `native/Tests/CandidatePreviewRetirementBoundaryCheck.sh`
- Modify: `docs/superpowers/plans/2026-07-23-minimal-black-theme-candidate-retirement.md`

**Interfaces:**

- Presentation 层最终只保留 `Capsule`、`Notch` 和 `ShadowPreview` 三类预览实现。
- Candidate 命名的 Application/Domain 最终交付类型继续保留。

- [x] **Step 1: 扩充退休 RED**

增加：

```bash
test ! -d native/Sources/Presentation/CandidatePreview
test ! -f native/Sources/Presentation/ShadowPreview/ThreeCapsuleLayout.swift
! rg -n 'CandidatePreview(View|Presenter|Coordinator)|ThreeCapsuleLayout' \
  native/Sources
! find native/Tests -maxdepth 1 -type f \
  \( -name 'CandidatePreview*' -o -name 'CandidateContentProjectionCheck.swift' \
     -o -name 'CandidatePresentationModelCheck.swift' -o -name 'CandidateProviderMatrixCheck.swift' \
     -o -name 'CandidateTextMotionCheck.swift' -o -name 'CandidateWindowUpdatePolicyCheck.swift' \
     -o -name 'ThreeCapsule*' -o -name 'Stage9AManualGateBoundaryCheck.sh' \) \
  | grep -q .
```

- [x] **Step 2: 运行 RED**

```bash
bash native/Tests/CandidatePreviewRetirementBoundaryCheck.sh
```

Expected: 旧文件仍存在，FAIL。

Evidence: 旧 `CandidatePreview` 目录仍存在，退休边界测试按预期失败。

- [x] **Step 3: 删除候选文件并收紧通用边界测试**

- 删除候选 Presentation 和专用测试。
- 通用边界测试的 UI 目录列表改为 `Capsule` 与 `ShadowPreview`。
- 不把 `CandidateDeliverySnapshot`、`CandidateTranscriptQualityGate`、模型候选或 ASR benchmark 误判为候选胶囊残留。

- [x] **Step 4: 运行边界测试组**

```bash
bash native/Tests/CandidatePreviewRetirementBoundaryCheck.sh
bash native/Tests/UnifiedRealtimeSourceBoundaryCheck.sh
bash native/Tests/RealtimeRecognitionQualityBoundaryCheck.sh
bash native/Tests/TranscriptionProviderBoundaryCheck.sh
bash native/Tests/RealtimePreviewDeliveryCacheWiringCheck.sh
bash native/Tests/PreviewSubscribersBoundaryCheck.sh
```

Expected: 全部 PASS。

Evidence: 六项边界测试与 `git diff --check` 全部通过。

- [x] **Step 5: 更新本文 Task 5 状态和证据并提交**

只 stage 本 Task 列出的删除和测试修改，复核后提交：

```bash
git status --short
git add -A -- \
  native/Sources/Presentation/CandidatePreview \
  native/Sources/Presentation/ShadowPreview/ThreeCapsuleLayout.swift \
  native/Tests/CandidateContentProjectionCheck.swift \
  native/Tests/CandidatePresentationModelCheck.swift \
  native/Tests/CandidatePreviewLifecycleCheck.swift \
  native/Tests/CandidatePreviewRenderBoundaryCheck.sh \
  native/Tests/CandidateProviderMatrixCheck.swift \
  native/Tests/CandidateTextMotionCheck.swift \
  native/Tests/CandidateWindowUpdatePolicyCheck.swift \
  native/Tests/ThreeCapsuleLayoutCheck.swift \
  native/Tests/ThreeCapsuleWiringCheck.sh \
  native/Tests/Stage9AManualGateBoundaryCheck.sh
git add \
  native/Tests/UnifiedRealtimeSourceBoundaryCheck.sh \
  native/Tests/RealtimeRecognitionQualityBoundaryCheck.sh \
  native/Tests/TranscriptionProviderBoundaryCheck.sh \
  native/Tests/CandidatePreviewRetirementBoundaryCheck.sh \
  docs/superpowers/plans/2026-07-23-minimal-black-theme-candidate-retirement.md
git diff --cached --check
git commit -m "refactor: remove candidate preview presentation"
```

---

### Task 6: 架构、视觉和真实安装版验收

**Status:** Completed with one physical-key acceptance item

**Files:**

- Modify: `docs/ARCHITECTURE.md`
- Modify: `docs/开发日志.md`
- Modify: `native/Sources/Presentation/VersionHistory/VersionHistoryViewController.swift`
- Modify: `docs/构建日志.md`（由构建脚本写入）
- Modify: `docs/superpowers/plans/2026-07-23-minimal-black-theme-candidate-retirement.md`

**Interfaces:**

- 发布态主题：默认胶囊 / 刘海主题 / 简洁黑色。
- 诊断态额外窗口：旁路胶囊一个。
- 产品态不存在候选窗口/runtime。

- [x] **Step 1: 更新架构与版本叙事**

明确记录：

```text
候选视觉已迁移为主胶囊主题；候选 runtime 和窗口已删除。
旁路保留为本地/MiMo/豆包 Provider 测试工具。
主胶囊和最终粘贴继续只消费生产实时缓存。
```

- [x] **Step 2: 运行完整相关测试**

```bash
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

Expected: 全部 PASS。

Evidence: 十项相关边界测试与 `git diff --check` 全部通过。

- [x] **Step 3: 并发复核后执行日常构建**

```bash
git branch --show-current
git status --short
pgrep -af 'build_and_log\\.sh|release_local_build\\.sh|build_native_app\\.sh|swiftc|xcodebuild' || true
./native/build_and_log.sh
```

Expected:

- `CFBundleVersion` 增加 1；
- `/Applications/TypeWhale Pro.app` 被覆盖安装并打开；
- 验签通过；
- 构建日志写入成功。

Evidence: `2.0.58 (Build 804)` 编译成功，已覆盖安装并打开；仓库包与安装包验签均通过，构建日志已写入。

- [x] **Step 4: 使用 `design-review` 检查真实安装版**

必须检查：

- 三张主题卡片布局和选中态；
- 简洁黑色无“候选”标签；
- 录音中、实时文字、稳定/可变尾巴、波形、停止处理状态；
- 默认主题和刘海主题无回归；
- 旁路关闭时只有主胶囊；
- 旁路打开时只增加一个旁路胶囊；
- 动效不闪烁、不跳回旧窗口、不丢上下文。

Evidence: 安装版三张主题卡片逐一切换并截图，布局、选中态和“简洁黑色”无候选标签均通过。报告位于 `~/.gstack/projects/Allenth-TypeWhale/designs/design-audit-20260723/`。桌面控制无法模拟硬件 Fn 键，实时录音动效列为明确的物理按键验收项。

- [x] **Step 5: 手动功能验收（自动可达部分完成，物理 Fn 部分待用户实录）**

1. 选择简洁黑色，录制 10–20 秒并停止，确认预览与粘贴完整。
2. 打开旁路，确认主胶囊 + 旁路共存且没有候选窗口。
3. 关闭旁路再次录音，确认主胶囊和粘贴不受影响。
4. 切回默认和刘海主题，各录制一次。
5. 验证闪念和 OpenClaw 仍使用经典主题。

Evidence: 主题选择、三卡布局、候选标签退休和安装版版本完成实机检查；源码边界测试证明旁路只保留一个且闪念/OpenClaw 强制经典主题。由于自动化不能发送 Fn，录音、粘贴、动态窗口数量和动效不伪报通过，按 Completion Gate 记录为剩余真实验收风险。

- [x] **Step 6: 更新本文为 Completed，复核提交范围并提交构建**

```bash
git status --short
git diff --check
git add docs/ARCHITECTURE.md \
  docs/开发日志.md \
  docs/构建日志.md \
  docs/superpowers/plans/2026-07-23-minimal-black-theme-candidate-retirement.md \
  README.md \
  macos/README.md \
  native/Sources/Presentation/VersionHistory/VersionHistoryViewController.swift \
  native/build_native_app.sh
git commit -m "feat: ship minimal black capsule theme"
```

不得 stage 或提交受保护的两个未跟踪概念目录。

---

## Completion Gate

只有同时满足以下条件才可声明完成：

- 三个主胶囊主题可选，简洁黑色完整消费生产状态。
- 简洁黑色不显示“候选”标签。
- 候选独立窗口、Coordinator、runtime、动画和专用测试已删除。
- 旁路诊断、本地/MiMo/豆包 Provider 测试能力仍存在。
- 主胶囊、生产缓存、最终粘贴与旁路相互隔离。
- 自动测试、日常 build、覆盖安装、启动和验签通过。
- `design-review` 与真实安装版手测完成，或未验证风险被明确记录。
- 每个 Task 的进度和证据已回写本文。

Completion evidence: Tasks 1–6 已逐项实现并提交；Build 804 编译、安装、启动、验签及安装版主题选择视觉复核通过。仅物理 Fn 实录动效与粘贴保留为已明确记录的用户验收项。
