# 应用范围中心与粘贴后自动发送 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 建立统一、可自适应的应用范围管理页，并为普通听写提供默认关闭、按应用配置的粘贴后回车或 `Command + 回车`。

**Architecture:** 应用目录只在设置页打开时异步生成；整理范围和自动发送共用 Presentation，但分别由 `SmartRewriteAutoRuleStore` 与 `AutoSendSettingsStore` 保存。普通听写在进入粘贴队列时由 `AutoSendPolicy` 决定动作，`PasteCoordinator` 在原有粘贴 readiness gate 通过、目标焦点仍正确后执行一次追加按键，任何失败都不得阻塞识别、胶囊或下一条粘贴。

**Tech Stack:** Swift、AppKit、Foundation、ApplicationServices/CGEvent、UserDefaults、现有 `PasteCoordinator` / `SpeechInputCoordinator` / `SmartRewriteAutoRuleStore`、Swift 可执行检查、shell 边界检查、`design-review`、`native/build_and_log.sh`。

## Global Constraints

- 设计规格是 `docs/superpowers/specs/2026-07-23-application-scope-and-auto-send-design.md`；每个 Task 开工前必须重读规格和本文。
- 默认只在主目录 `$HOME/Pictures/macOSwinOSCoding/TypeSpeaker` 与分支 `codex/typewhale-pro-asr-hotwords` 开发，不新建 worktree。
- 每次只执行一个 Task；每个 Task 使用 RED → GREEN → 回归 → 更新本文 → commit。
- 不修改 ASR、VAD、实时缓存、Final ASR、重叠矫正、文本整理算法或任何胶囊的数据/绘制。
- 自动发送总开关默认关闭，只对普通听写生效；翻译、闪念、OpenClaw、手动复制、空文本、取消和粘贴失败不得发送按键。
- 整理范围与自动发送只共用应用目录和 UI 组件；配置、开关、Store 与执行决策不得共用。
- `PasteCoordinator` 不得直接读取 `UserDefaults`；Presentation 不得引用 `SpeechSession`、实时缓存、Provider 或胶囊类型。
- 应用扫描只在应用范围窗口打开时运行，不创建常驻 Timer、后台扫描或录音状态观察者。
- 旧 `SmartRewriteAutoConfiguration` 必须兼容解码；旧规则保持内容和顺序，不能静默丢失。
- 应用范围窗口初始内容尺寸 `960 × 620`，最小 `820 × 520`，最大不超过当前屏幕 `visibleFrame` 的 90%。
- 不读取、修改、stage 或提交受保护的未跟踪目录：
  - `native/Helpers/CapsuleConceptGallery/`
  - `native/Sources/Presentation/Capsule/Concepts/`
  - `.superpowers/`
- 每完成 3–5 个代码提交执行一次架构复审，并把结论写入本文；发现越界必须先纠正再继续。
- 所有代码 Task 完成后执行真实日常构建：`./native/build_and_log.sh`，递增 build 号、覆盖安装、打开、验签并提交。
- UI 完成后使用 `design-review` 复核真实安装版，覆盖窗口缩放、滚动、选中状态、模式切换和按钮可见性。

---

## File Structure

### 新建：Domain / Application / Infrastructure

- `native/Sources/Domain/AutoSendDomain.swift`
  定义 `PostPasteAction` 和自动发送配置值，不包含系统事件或 UI。
- `native/Sources/Infrastructure/Settings/AutoSendSettingsStore.swift`
  只负责自动发送配置的编码、解码、默认值和归一化。
- `native/Sources/Application/AutoSendPolicy.swift`
  根据总开关、任务用途、翻译状态、文本和目标 Bundle ID 返回动作。
- `native/Sources/Infrastructure/Paste/PostPasteKeyEmitter.swift`
  封装回车与 `Command + 回车` 的 `CGEvent` 创建和发送。
- `native/Sources/Infrastructure/Applications/RecentTargetApplicationStore.swift`
  在普通听写成功粘贴后记录有限数量的最近目标应用。
- `native/Sources/Infrastructure/Applications/ApplicationCatalog.swift`
  仅在设置页打开时异步枚举、去重、分类应用并生成展示快照。

### 新建：Presentation

- `native/Sources/Presentation/Main/Dialogs/ApplicationScopeEditorModel.swift`
  保存窗口内尚未落盘的整理范围与自动发送草稿，提供筛选和批量修改。
- `native/Sources/Presentation/Main/Dialogs/ApplicationScopeViewController.swift`
  构建 A+C 合并界面：分类栏、应用列表、右侧设置、高级规则、分段切换。
- `native/Sources/Presentation/Main/Dialogs/ApplicationScopeWindowController.swift`
  负责可调整大小的 sheet/window、屏幕范围限制、尺寸恢复、保存和取消。
- `native/Sources/Presentation/Main/Dialogs/ApplicationScopeApplicationRowView.swift`
  只绘制应用图标、名称、勾选状态和当前模式/动作。

### 修改

- `native/Sources/Core/SmartInput/SmartRewriteAutoRuleStore.swift`
  增加 Bundle ID → 默认整理模式，同时兼容旧配置并保持旧高级规则顺序。
- `native/Sources/Infrastructure/Paste/PasteCoordinator.swift`
  在原有粘贴成功时序内调用 `PostPasteKeyEmitter`，并保持队列串行。
- `native/Sources/Application/SpeechInputCoordinator.swift`
  仅普通、非翻译听写入队时调用 `AutoSendPolicy`；成功后记录最近应用。
- `native/Sources/Presentation/Main/MainViewController.swift`
  增加自动发送总开关和应用范围按钮引用。
- `native/Sources/Presentation/Main/MainViewController+Configuration.swift`
  配置新控件的辅助功能、事件和初始值。
- `native/Sources/Presentation/Main/MainViewController+PanelLayout.swift`
  在“常用”增加“粘贴与发送”Section，并把智能页入口改为“应用范围”。
- `native/Sources/Presentation/Main/MainViewController+Actions.swift`
  保存总开关并从两个入口打开同一范围窗口。
- `native/Sources/Presentation/VersionHistory/VersionHistoryViewController.swift`
- `docs/ARCHITECTURE.md`
- `docs/产品需求文档.md`
- `docs/开发日志.md`
- 本计划

### 新建测试

- `native/Tests/AutoSendSettingsStoreCheck.swift`
- `native/Tests/AutoSendPolicyCheck.swift`
- `native/Tests/PostPasteKeyEmitterCheck.swift`
- `native/Tests/PastePostActionSequencingCheck.swift`
- `native/Tests/AutoSendIntegrationBoundaryCheck.sh`
- `native/Tests/RecentTargetApplicationStoreCheck.swift`
- `native/Tests/ApplicationCatalogCheck.swift`
- `native/Tests/ApplicationCatalogRuntimeBoundaryCheck.sh`
- `native/Tests/SmartRewriteAppAssignmentCheck.swift`
- `native/Tests/ApplicationScopeTestStubs.swift`
- `native/Tests/ApplicationScopeEditorModelCheck.swift`
- `native/Tests/ApplicationScopeLayoutBoundaryCheck.sh`
- `native/Tests/ApplicationScopeSettingsEntryCheck.sh`

---

### Task 0: 锁定现有整理规则与粘贴基线

**Status:** Completed

**Files:**

- Create: `native/Tests/ApplicationScopeLegacyBaselineCheck.swift`
- Create: `native/Tests/ApplicationScopeTestStubs.swift`
- Create: `native/Tests/ApplicationScopeArchitectureBoundaryCheck.sh`
- Modify: `docs/superpowers/plans/2026-07-23-application-scope-and-auto-send.md`

**Interfaces:**

- Consumes: `SmartRewriteAutoRuleStore.mode(for:rawText:)`、`PasteCoordinator`
- Produces: 后续任务不可破坏的旧行为与分层边界

- [x] **Step 1: 重读计划并检查并发现场**

Run:

```bash
sed -n '1,340p' docs/superpowers/specs/2026-07-23-application-scope-and-auto-send-design.md
sed -n '1,260p' docs/superpowers/plans/2026-07-23-application-scope-and-auto-send.md
git branch --show-current
git status --short
pgrep -af 'build_and_log|release_local_build|build_native_app|swiftc|xcodebuild' || true
```

Expected: 分支正确；只有已知受保护目录和本计划/规格为未提交改动；无并发构建。

- [x] **Step 2: 写旧规则基线测试**

`ApplicationScopeLegacyBaselineCheck.swift` 必须保存并恢复原配置，然后验证现有匹配顺序：

```swift
import Foundation

@main
struct ApplicationScopeLegacyBaselineCheck {
    static func main() {
        let key = "smartRewriteAutoConfiguration.v1"
        let original = UserDefaults.standard.data(forKey: key)
        defer {
            if let original { UserDefaults.standard.set(original, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }

        SmartRewriteAutoRuleStore.reset()
        let summary = SmartRewriteAutoRuleStore.mode(
            for: SmartInputContext(
                targetAppName: "Xcode",
                targetBundleIdentifier: "com.apple.dt.Xcode"
            ),
            rawText: "请总结今天的修改"
        )
        precondition(summary == .exhaustiveSummary)

        let development = SmartRewriteAutoRuleStore.mode(
            for: SmartInputContext(
                targetAppName: "Xcode",
                targetBundleIdentifier: "com.apple.dt.Xcode"
            ),
            rawText: "修复构建错误"
        )
        precondition(development == .developerRequirement)
        print("ApplicationScopeLegacyBaselineCheck passed")
    }
}
```

`ApplicationScopeTestStubs.swift` 只为独立 `swiftc` 测试提供与生产字段一致的
`SmartInputContext`：

```swift
struct SmartInputContext {
    let targetAppName: String?
    let targetBundleIdentifier: String?
    let windowTitle: String?

    init(
        targetAppName: String? = nil,
        targetBundleIdentifier: String? = nil,
        windowTitle: String? = nil
    ) {
        self.targetAppName = targetAppName
        self.targetBundleIdentifier = targetBundleIdentifier
        self.windowTitle = windowTitle
    }
}
```

- [x] **Step 3: 写架构边界测试**

`ApplicationScopeArchitectureBoundaryCheck.sh` 必须包含：

```bash
#!/usr/bin/env bash
set -euo pipefail

scope_files=(
  native/Sources/Infrastructure/Applications/ApplicationCatalog.swift
  native/Sources/Presentation/Main/Dialogs/ApplicationScopeEditorModel.swift
  native/Sources/Presentation/Main/Dialogs/ApplicationScopeViewController.swift
  native/Sources/Presentation/Main/Dialogs/ApplicationScopeWindowController.swift
)

for file in "${scope_files[@]}"; do
  [[ -e "$file" ]] || continue
  if rg -n 'SpeechSession|RealtimePreview|TranscriptionProvider|RecordingPanel|CandidatePreview|ShadowPreview' "$file"; then
    echo "Application scope UI/catalog crossed realtime or capsule boundary: $file" >&2
    exit 1
  fi
done

if [[ -e native/Sources/Infrastructure/Paste/PasteCoordinator.swift ]] &&
   rg -n 'UserDefaults|AutoSendSettingsStore' native/Sources/Infrastructure/Paste/PasteCoordinator.swift; then
  echo "PasteCoordinator must not read settings" >&2
  exit 1
fi
```

- [x] **Step 4: 运行基线**

Run:

```bash
swiftc \
  native/Sources/Core/SmartInput/RewriteProfile.swift \
  native/Sources/Core/SmartInput/SmartRewriteAutoRuleStore.swift \
  native/Tests/ApplicationScopeTestStubs.swift \
  native/Tests/ApplicationScopeLegacyBaselineCheck.swift \
  -o /tmp/ApplicationScopeLegacyBaselineCheck &&
  /tmp/ApplicationScopeLegacyBaselineCheck
bash native/Tests/ApplicationScopeArchitectureBoundaryCheck.sh
xcrun swiftc \
  native/Sources/Core/AppBrand.swift \
  native/Sources/Domain/PasteDomain.swift \
  native/Sources/Infrastructure/Diagnostics/LaunchDiagnostics.swift \
  native/Sources/Infrastructure/Paste/PasteCoordinator.swift \
  native/Tests/PasteboardReadinessGateCheck.swift \
  -o /tmp/PasteboardReadinessGateCheck &&
  /tmp/PasteboardReadinessGateCheck
```

Expected: 三项检查全部 PASS。

- [x] **Step 5: 更新计划证据并提交**

```bash
git add \
  native/Tests/ApplicationScopeLegacyBaselineCheck.swift \
  native/Tests/ApplicationScopeTestStubs.swift \
  native/Tests/ApplicationScopeArchitectureBoundaryCheck.sh \
  docs/superpowers/specs/2026-07-23-application-scope-and-auto-send-design.md \
  docs/superpowers/plans/2026-07-23-application-scope-and-auto-send.md
git commit -m "test: lock application scope compatibility boundaries"
```

**Completion evidence:** 2026-07-23 已确认当前分支和并发现场；独立测试使用
`RewriteProfile.swift` 加测试专用 `SmartInputContext` stub，避免错误引用不存在的
`SmartInputDomain.swift`。`ApplicationScopeLegacyBaselineCheck`、
`ApplicationScopeArchitectureBoundaryCheck` 与
`PasteboardReadinessGateCheck` 全部 PASS。

---

### Task 1: 建立自动发送 Domain、Store 与纯策略

**Status:** Completed

**Files:**

- Create: `native/Sources/Domain/AutoSendDomain.swift`
- Create: `native/Sources/Infrastructure/Settings/AutoSendSettingsStore.swift`
- Create: `native/Sources/Application/AutoSendPolicy.swift`
- Create: `native/Tests/AutoSendSettingsStoreCheck.swift`
- Create: `native/Tests/AutoSendPolicyCheck.swift`
- Modify: `docs/superpowers/plans/2026-07-23-application-scope-and-auto-send.md`

**Interfaces:**

- Produces:

```swift
enum PostPasteAction: String, Codable, CaseIterable, Equatable {
    case none
    case returnKey
    case commandReturn
}

struct AutoSendConfiguration: Codable, Equatable {
    var isEnabled: Bool
    var actionsByBundleID: [String: PostPasteAction]
}

enum AutoSendSettingsStore {
    static func load() -> AutoSendConfiguration
    static func save(_ configuration: AutoSendConfiguration)
    static func reset()
}

struct AutoSendPolicy {
    func action(
        configuration: AutoSendConfiguration,
        purpose: SpeechInputPurpose,
        text: String,
        targetBundleIdentifier: String?,
        isTranslated: Bool
    ) -> PostPasteAction
}
```

- [x] **Step 1: 重读规格、计划并检查工作区**

使用 Task 0 Step 1 的命令；Expected 同 Task 0。

- [x] **Step 2: 写 Store 与 Policy RED**

测试必须覆盖：

```swift
precondition(AutoSendSettingsStore.defaultConfiguration == .init(
    isEnabled: false,
    actionsByBundleID: [:]
))
precondition(policy.action(
    configuration: .init(
        isEnabled: true,
        actionsByBundleID: ["com.tencent.xinWeChat": .returnKey]
    ),
    purpose: .dictation,
    text: "你好",
    targetBundleIdentifier: "com.tencent.xinWeChat",
    isTranslated: false
) == .returnKey)
precondition(policy.action(
    configuration: enabled,
    purpose: .ideaPill,
    text: "你好",
    targetBundleIdentifier: "com.tencent.xinWeChat",
    isTranslated: false
) == .none)
precondition(policy.action(
    configuration: enabled,
    purpose: .dictation,
    text: "Hello",
    targetBundleIdentifier: "com.tencent.xinWeChat",
    isTranslated: true
) == .none)
```

同时验证空文本、空 Bundle ID、总开关关闭、未配置应用和未知动作解码均返回 `.none`。

- [x] **Step 3: 运行 RED**

Run:

```bash
xcrun swiftc -parse-as-library \
  native/Tests/AutoSendSettingsStoreCheck.swift \
  -o /tmp/AutoSendSettingsStoreCheck
```

Expected: `AutoSendConfiguration` / `AutoSendSettingsStore` 不存在，编译失败。

- [x] **Step 4: 实现最小 Domain、Store 与 Policy**

Store 归一化必须使用：

```swift
static let defaultConfiguration = AutoSendConfiguration(
    isEnabled: false,
    actionsByBundleID: [:]
)

static func normalized(_ configuration: AutoSendConfiguration) -> AutoSendConfiguration {
    let actions = configuration.actionsByBundleID.reduce(into: [String: PostPasteAction]()) {
        result, pair in
        let bundleID = pair.key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !bundleID.isEmpty, pair.value != .none else { return }
        result[bundleID] = pair.value
    }
    return AutoSendConfiguration(
        isEnabled: configuration.isEnabled,
        actionsByBundleID: actions
    )
}
```

Policy 必须保持纯函数：

```swift
func action(
    configuration: AutoSendConfiguration,
    purpose: SpeechInputPurpose,
    text: String,
    targetBundleIdentifier: String?,
    isTranslated: Bool
) -> PostPasteAction {
    guard configuration.isEnabled,
          purpose == .dictation,
          !isTranslated,
          !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          let bundleID = targetBundleIdentifier,
          !bundleID.isEmpty else {
        return .none
    }
    return configuration.actionsByBundleID[bundleID] ?? .none
}
```

- [x] **Step 5: 运行 GREEN 与边界检查**

Run:

```bash
xcrun swiftc -parse-as-library \
  native/Sources/Domain/AutoSendDomain.swift \
  native/Sources/Infrastructure/Settings/AutoSendSettingsStore.swift \
  native/Tests/AutoSendSettingsStoreCheck.swift \
  -o /tmp/AutoSendSettingsStoreCheck &&
  /tmp/AutoSendSettingsStoreCheck
xcrun swiftc -parse-as-library \
  native/Sources/Domain/AutoSendDomain.swift \
  native/Sources/Domain/SpeechInputPurpose.swift \
  native/Sources/Application/AutoSendPolicy.swift \
  native/Tests/AutoSendPolicyCheck.swift \
  -o /tmp/AutoSendPolicyCheck &&
  /tmp/AutoSendPolicyCheck
bash native/Tests/ApplicationScopeArchitectureBoundaryCheck.sh
```

Expected: 全部 PASS。

- [x] **Step 6: 更新计划证据并提交**

```bash
git add \
  native/Sources/Domain/AutoSendDomain.swift \
  native/Sources/Infrastructure/Settings/AutoSendSettingsStore.swift \
  native/Sources/Application/AutoSendPolicy.swift \
  native/Tests/AutoSendSettingsStoreCheck.swift \
  native/Tests/AutoSendPolicyCheck.swift \
  docs/superpowers/plans/2026-07-23-application-scope-and-auto-send.md
git commit -m "feat: add per-app auto send policy"
```

**Completion evidence:** RED 因 `AutoSendSettingsStore` / `AutoSendConfiguration`
不存在而失败；GREEN 后 `AutoSendSettingsStoreCheck`、
`AutoSendPolicyCheck` 和 `ApplicationScopeArchitectureBoundaryCheck`
全部 PASS。Store 会保留有效旧动作并忽略未知未来动作；策略已锁定总开关、
普通听写、非翻译、非空文本和精确 Bundle ID 五个门禁。

---

### Task 2: 在粘贴队列内增加受控追加按键

**Status:** Completed

**Files:**

- Create: `native/Sources/Infrastructure/Paste/PostPasteKeyEmitter.swift`
- Create: `native/Tests/PostPasteKeyEmitterCheck.swift`
- Create: `native/Tests/PastePostActionSequencingCheck.swift`
- Modify: `native/Sources/Infrastructure/Paste/PasteCoordinator.swift`
- Modify: `docs/superpowers/plans/2026-07-23-application-scope-and-auto-send.md`

**Interfaces:**

- Consumes: `PostPasteAction`
- Produces:

```swift
protocol PostPasteKeyEmitting {
    func emit(_ action: PostPasteAction) -> Bool
}

struct SystemPostPasteKeyEmitter: PostPasteKeyEmitting {
    func emit(_ action: PostPasteAction) -> Bool
}

func enqueue(
    text: String,
    targetApp: NSRunningApplication?,
    postPasteAction: PostPasteAction = .none,
    completion: @escaping (PasteOutcome) -> Void
)
```

- [x] **Step 1: 先完成代码走读并把实际时序写回本 Task**

必须逐行确认：

```bash
sed -n '1,380p' native/Sources/Infrastructure/Paste/PasteCoordinator.swift
sed -n '1,100p' native/Sources/Domain/PasteDomain.swift
sed -n '3150,3290p' native/Sources/Application/SpeechInputCoordinator.swift
```

在本文记录：readiness gate、`Command + V` 发出点、剪贴板恢复点、`finish` 点、焦点二次确认位置。确认后才能写 RED。

**Walkthrough evidence:** 2026-07-23 已确认当前顺序为：
`performPasteboardShortcut` 写剪贴板 → `waitForPasteboardReadiness`
确认本轮文字可读 → `postPasteboardShortcut` 发出 `Command + V` →
0.3 秒后恢复或保留剪贴板 → `finish` 释放串行队列。追加按键必须在
`Command + V` 发出后的 0.08 秒执行，并在执行前再次比较冻结目标 PID 与
当前前台 PID；它早于剪贴板恢复和 `finish`，因此不会跨入下一条 request。

- [x] **Step 2: 写按键映射与时序 RED**

`PostPasteKeyEmitterCheck` 使用可注入闭包捕获虚拟键码和 flags：

```swift
var posted: [(keyCode: CGKeyCode, flags: CGEventFlags)] = []
let emitter = SystemPostPasteKeyEmitter { keyCode, flags in
    posted.append((keyCode, flags))
    return true
}
precondition(emitter.emit(.returnKey))
precondition(posted == [(36, [])])
posted.removeAll()
precondition(emitter.emit(.commandReturn))
precondition(posted == [(36, .maskCommand)])
```

`PastePostActionSequencingCheck` 必须用纯状态机验证：

```swift
precondition(PostPasteActionGate.evaluate(
    .init(
        action: .returnKey,
        pasteEventPosted: true,
        targetStillFrontmost: true
    )
) == .emit)
precondition(PostPasteActionGate.evaluate(
    .init(
        action: .returnKey,
        pasteEventPosted: false,
        targetStillFrontmost: true
    )
) == .skip)
precondition(PostPasteActionGate.evaluate(
    .init(
        action: .commandReturn,
        pasteEventPosted: true,
        targetStillFrontmost: false
    )
) == .skip)
```

- [x] **Step 3: 运行 RED**

Run:

```bash
xcrun swiftc -parse-as-library \
  native/Sources/Domain/AutoSendDomain.swift \
  native/Tests/PostPasteKeyEmitterCheck.swift \
  -o /tmp/PostPasteKeyEmitterCheck
```

Expected: emitter/gate 不存在，编译失败。

- [x] **Step 4: 实现可注入 Emitter 与纯 Gate**

实现必须使用 Return 键码 36，并分别给 keyDown/keyUp 设置 flags：

```swift
enum PostPasteActionGate {
    struct Snapshot {
        let action: PostPasteAction
        let pasteEventPosted: Bool
        let targetStillFrontmost: Bool
    }

    enum Decision: Equatable { case emit, skip }

    static func evaluate(_ snapshot: Snapshot) -> Decision {
        guard snapshot.action != .none,
              snapshot.pasteEventPosted,
              snapshot.targetStillFrontmost else {
            return .skip
        }
        return .emit
    }
}
```

`PasteCoordinator.Request` 增加 `postPasteAction`，但不得读取设置。`Command + V` 发出后，在同一 request 内短延迟执行：

```swift
private func emitPostPasteActionIfAllowed(
    for request: Request
) {
    let targetStillFrontmost =
        request.targetApp?.processIdentifier ==
        NSWorkspace.shared.frontmostApplication?.processIdentifier
    guard PostPasteActionGate.evaluate(.init(
        action: request.postPasteAction,
        pasteEventPosted: true,
        targetStillFrontmost: targetStillFrontmost
    )) == .emit else {
        return
    }
    _ = postPasteKeyEmitter.emit(request.postPasteAction)
}
```

固定使用 `PasteboardTiming.postPasteActionDelay = 0.08` 秒：它位于
`Command + V` 发出之后、现有 0.3 秒剪贴板恢复之前；不能放到 UI，也不能等待
`PasteOutcome` completion 才执行。

- [x] **Step 5: 运行 GREEN 与现有粘贴回归**

Run:

```bash
xcrun swiftc -parse-as-library \
  native/Sources/Domain/AutoSendDomain.swift \
  native/Sources/Infrastructure/Paste/PostPasteKeyEmitter.swift \
  native/Tests/PostPasteKeyEmitterCheck.swift \
  -o /tmp/PostPasteKeyEmitterCheck &&
  /tmp/PostPasteKeyEmitterCheck
xcrun swiftc -parse-as-library \
  native/Sources/Domain/AutoSendDomain.swift \
  native/Sources/Infrastructure/Paste/PostPasteKeyEmitter.swift \
  native/Tests/PastePostActionSequencingCheck.swift \
  -o /tmp/PastePostActionSequencingCheck &&
  /tmp/PastePostActionSequencingCheck
xcrun swiftc -parse-as-library \
  native/Sources/Core/AppBrand.swift \
  native/Sources/Domain/AutoSendDomain.swift \
  native/Sources/Domain/PasteDomain.swift \
  native/Sources/Infrastructure/Diagnostics/LaunchDiagnostics.swift \
  native/Sources/Infrastructure/Paste/PostPasteKeyEmitter.swift \
  native/Sources/Infrastructure/Paste/PasteCoordinator.swift \
  native/Tests/PasteboardReadinessGateCheck.swift \
  -o /tmp/PasteboardReadinessGateCheck &&
  /tmp/PasteboardReadinessGateCheck
bash native/Tests/ApplicationScopeArchitectureBoundaryCheck.sh
```

Expected: 全部 PASS；原 readiness gate 行为不变。

- [x] **Step 6: 更新计划证据并提交**

```bash
git add \
  native/Sources/Infrastructure/Paste/PasteCoordinator.swift \
  native/Sources/Infrastructure/Paste/PostPasteKeyEmitter.swift \
  native/Tests/PostPasteKeyEmitterCheck.swift \
  native/Tests/PastePostActionSequencingCheck.swift \
  docs/superpowers/plans/2026-07-23-application-scope-and-auto-send.md
git commit -m "feat: append post-paste key inside paste queue"
```

**Completion evidence:** RED 因 `SystemPostPasteKeyEmitter` 不存在而失败；
GREEN 后 `PostPasteKeyEmitterCheck`、`PastePostActionSequencingCheck`、
原 `PasteboardReadinessGateCheck` 和架构边界检查全部 PASS。追加按键固定在
`Command + V` 后 0.08 秒执行，执行前再次确认目标 PID；失败只写日志，
不会改变原粘贴 outcome 或阻塞 0.3 秒后的队列释放。

---

### Task 3: 只把普通非翻译听写接入自动发送

**Status:** Completed

**Files:**

- Create: `native/Sources/Infrastructure/Applications/RecentTargetApplicationStore.swift`
- Create: `native/Tests/RecentTargetApplicationStoreCheck.swift`
- Create: `native/Tests/AutoSendIntegrationBoundaryCheck.sh`
- Modify: `native/Sources/Application/SpeechInputState.swift`
- Modify: `native/Sources/Application/SpeechInputCoordinator.swift`
- Modify: `docs/superpowers/plans/2026-07-23-application-scope-and-auto-send.md`

**Interfaces:**

- Consumes: `AutoSendPolicy.action(...)`、`PasteCoordinator.enqueue(...postPasteAction:...)`
- Produces: 仅普通、非翻译 `PendingPasteResult` 的自动发送动作；成功粘贴后的最近应用记录

- [x] **Step 1: 重读规格、计划并走读所有 `PendingPasteResult` 来源**

Run:

```bash
rg -n 'PendingPasteResult\\(' native/Sources/Application/SpeechInputCoordinator.swift
sed -n '2620,2890p' native/Sources/Application/SpeechInputCoordinator.swift
sed -n '3040,3290p' native/Sources/Application/SpeechInputCoordinator.swift
```

把普通原文、整理、翻译、闪念、OpenClaw 的实际分流结论写回本文。

**Walkthrough evidence:** 2026-07-23 已确认只有两个 `PendingPasteResult`
构造点：`rewriteAndSubmit` 负责普通原文/整理，`rewriteTranslateAndSubmit`
负责翻译请求。闪念在 `submitPasteResult` 提前保存并返回，不进入粘贴队列；
OpenClaw 使用独立消息队列。仅用 `translationDirection == nil` 不足以排除翻译，
因为翻译失败回退时该字段同样为 nil。因此 `PendingPasteResult` 增加
`wasTranslationRequested`：翻译构造点固定为 true，普通构造点固定为 false，
后续策略只读这一事实字段。

- [x] **Step 2: 写集成边界 RED**

`AutoSendIntegrationBoundaryCheck.sh` 必须验证：

```bash
#!/usr/bin/env bash
set -euo pipefail
file=native/Sources/Application/SpeechInputCoordinator.swift
rg -q 'AutoSendPolicy' "$file"
rg -q 'postPasteAction:' "$file"
rg -q 'wasTranslationRequested: true' "$file"
rg -q 'wasTranslationRequested: false' "$file"
rg -q 'result\\.task\\.purpose' "$file"
if rg -n 'AutoSendSettingsStore|PostPasteKeyEmitter' native/Sources/Presentation; then
  echo "Presentation must not own auto-send settings or system key emission" >&2
  exit 1
fi
if rg -n 'AutoSendSettingsStore|UserDefaults' \
  native/Sources/Infrastructure/Paste/PasteCoordinator.swift; then
  echo "PasteCoordinator must not own auto-send policy/settings" >&2
  exit 1
fi
```

`RecentTargetApplicationStoreCheck` 验证 Bundle ID 去重、最近优先、最多 20 条和保存恢复。

- [x] **Step 3: 运行 RED**

Run:

```bash
bash native/Tests/AutoSendIntegrationBoundaryCheck.sh
```

Expected: `SpeechInputCoordinator` 尚未引用策略，失败。

- [x] **Step 4: 实现单点接线**

在 `drainPendingPasteResultsIfPossible` 中只决定一次：

```swift
let postPasteAction = AutoSendPolicy().action(
    configuration: AutoSendSettingsStore.load(),
    purpose: result.task.purpose,
    text: result.text,
    targetBundleIdentifier: pasteTarget.bundleIdentifier,
    isTranslated: result.wasTranslationRequested
)
pasteCoordinator.enqueue(
    text: result.text,
    targetApp: pasteTarget,
    postPasteAction: postPasteAction
) { [weak self] outcome in
    self?.handlePasteOutcome(outcome, result: result)
}
```

只有 `outcome.pasteCompletedAt != nil` 时记录最近应用：

```swift
if outcome.pasteCompletedAt != nil,
   let app = currentTargetApp(for: task) {
    RecentTargetApplicationStore.record(app, usedAt: Date())
}
```

不得修改 `submitPasteResult` 的闪念提前返回和 OpenClaw 独立发送路径。

- [x] **Step 5: 运行 GREEN 与回归**

Run:

```bash
bash native/Tests/AutoSendIntegrationBoundaryCheck.sh
xcrun swiftc -parse-as-library \
  native/Sources/Infrastructure/Applications/RecentTargetApplicationStore.swift \
  native/Tests/RecentTargetApplicationStoreCheck.swift \
  -o /tmp/RecentTargetApplicationStoreCheck &&
  /tmp/RecentTargetApplicationStoreCheck
bash native/Tests/ApplicationScopeArchitectureBoundaryCheck.sh
bash native/Tests/FinalDeliveryLogBoundaryCheck.sh
bash native/Tests/CapsulePreviewIndependenceBoundaryCheck.sh
```

Expected: 全部 PASS。

- [x] **Step 6: 更新计划证据并提交**

```bash
git add \
  native/Sources/Application/SpeechInputState.swift \
  native/Sources/Application/SpeechInputCoordinator.swift \
  native/Sources/Infrastructure/Applications/RecentTargetApplicationStore.swift \
  native/Tests/RecentTargetApplicationStoreCheck.swift \
  native/Tests/AutoSendIntegrationBoundaryCheck.sh \
  docs/superpowers/plans/2026-07-23-application-scope-and-auto-send.md
git commit -m "feat: route ordinary dictation through auto send policy"
```

**Implementation evidence:** RED 明确失败于 `SpeechInputCoordinator must resolve
AutoSendPolicy`，Recent Store RED 明确失败于类型不存在。GREEN 后集成边界、
最近应用去重/排序/20 条上限、架构边界、Final Delivery 日志边界和胶囊独立性
检查全部 PASS。翻译请求事实被写入 `PendingPasteResult`，不会因翻译失败回退
而误触发自动发送。

- [x] **Step 7: 架构复审 Gate A**

复审 Task 0–3 的 diff，必须确认：

- `PasteCoordinator` 不读设置；
- 自动发送不进入翻译、闪念或 OpenClaw；
- 没有修改 ASR、缓存或胶囊；
- 回车失败不阻塞 `finish` 和下一条队列；
- 最近应用写入发生在粘贴完成后，不在实时链路。

Run:

```bash
git diff HEAD~4..HEAD -- \
  native/Sources/Domain \
  native/Sources/Application \
  native/Sources/Infrastructure
bash native/Tests/ApplicationScopeArchitectureBoundaryCheck.sh
bash native/Tests/AutoSendIntegrationBoundaryCheck.sh
```

将结论写入本文再继续 Task 4。

**Architecture review Gate A:** 复审提交 `2713248..af63568` 后确认：

- 设置读取只在 Application 层，`PasteCoordinator` 只接收已决定动作；
- `wasTranslationRequested` 排除了翻译成功和翻译失败回退两条路径；
- 闪念在粘贴前返回，OpenClaw 使用独立发送队列；
- 追加按键失败只记录日志，0.3 秒后的原 `finish` 仍会释放队列；
- 最近应用只在 `PasteOutcome.pasteCompletedAt != nil` 后写入；
- 未修改 ASR、VAD、实时缓存或胶囊。

复审额外发现默认 `.none` 仍安排 0.08 秒空任务；已先写边界 RED，再增加
`schedulePostPasteActionIfNeeded` 的 early return。修正后集成边界、
readiness gate、胶囊独立性和 `git diff --check` 全部 PASS。

---

### Task 4: 为整理范围增加应用默认模式并兼容旧规则

**Status:** Completed

**Files:**

- Modify: `native/Sources/Core/SmartInput/SmartRewriteAutoRuleStore.swift`
- Modify: `native/Sources/Presentation/Main/Dialogs/SmartRewriteAutoRuleDialog.swift`
- Create: `native/Tests/SmartRewriteAppAssignmentCheck.swift`
- Modify: `native/Tests/ApplicationScopeArchitectureBoundaryCheck.sh`
- Modify: `native/Tests/SmartInputCheck.swift`
- Modify: `docs/superpowers/plans/2026-07-23-application-scope-and-auto-send.md`

**Interfaces:**

- Produces:

```swift
struct SmartRewriteAutoConfiguration: Codable, Equatable {
    var rules: [SmartRewriteAutoRule]
    var appModesByBundleID: [String: RewriteMode]
    var fallbackMode: RewriteMode

    init(
        rules: [SmartRewriteAutoRule],
        appModesByBundleID: [String: RewriteMode] = [:],
        fallbackMode: RewriteMode
    )
}
```

- [x] **Step 1: 重读计划并检查所有配置构造点**

Run:

```bash
rg -n 'SmartRewriteAutoConfiguration\\(' native/Sources native/Tests
sed -n '1,250p' native/Sources/Core/SmartInput/SmartRewriteAutoRuleStore.swift
```

记录旧配置解码和默认规则合并行为。

- [x] **Step 2: 写兼容与优先级 RED**

测试必须验证：

```swift
let configuration = SmartRewriteAutoConfiguration(
    rules: [
        .init(
            id: "summary",
            title: "总结",
            keywords: ["总结"],
            mode: .exhaustiveSummary,
            isEnabled: true,
            matchTarget: false,
            matchContent: true
        ),
    ],
    appModesByBundleID: ["com.apple.dt.Xcode": .developerRequirement],
    fallbackMode: .polish
)
SmartRewriteAutoRuleStore.save(configuration)

let summary = SmartRewriteAutoRuleStore.mode(
    for: .init(targetBundleIdentifier: "com.apple.dt.Xcode"),
    rawText: "总结修改"
)
precondition(summary == .exhaustiveSummary)

let appDefault = SmartRewriteAutoRuleStore.mode(
    for: .init(targetBundleIdentifier: "com.apple.dt.Xcode"),
    rawText: "修复错误"
)
precondition(appDefault == .developerRequirement)
```

另用手工 JSON 缺少 `appModesByBundleID` 字段，断言解码为空字典且旧规则顺序不变。

- [x] **Step 3: 运行 RED**

Run:

```bash
xcrun swiftc -parse-as-library \
  native/Sources/Core/SmartInput/RewriteProfile.swift \
  native/Sources/Core/SmartInput/SmartRewriteAutoRuleStore.swift \
  native/Tests/ApplicationScopeTestStubs.swift \
  native/Tests/SmartRewriteAppAssignmentCheck.swift \
  -o /tmp/SmartRewriteAppAssignmentCheck
```

Expected: 新字段或 initializer 不存在，失败。

- [x] **Step 4: 实现兼容解码与匹配**

自定义解码必须使用：

```swift
appModesByBundleID = try container.decodeIfPresent(
    [String: RewriteMode].self,
    forKey: .appModesByBundleID
) ?? [:]
```

匹配必须保持：

```swift
for rule in configuration.rules where rule.isEnabled {
    if matches(rule, targetHaystack: targetHaystack, contentHaystack: contentHaystack) {
        return rule.mode
    }
}
if let bundleID = context.targetBundleIdentifier,
   let appMode = configuration.appModesByBundleID[bundleID] {
    return appMode
}
return configuration.fallbackMode
```

保存时过滤空 Bundle ID 和不可选模式；不得改写 `rules` 顺序。

- [x] **Step 5: 运行 GREEN 与旧基线**

Run:

```bash
xcrun swiftc -parse-as-library \
  native/Sources/Core/SmartInput/RewriteProfile.swift \
  native/Sources/Core/SmartInput/SmartRewriteAutoRuleStore.swift \
  native/Tests/ApplicationScopeTestStubs.swift \
  native/Tests/SmartRewriteAppAssignmentCheck.swift \
  -o /tmp/SmartRewriteAppAssignmentCheck &&
  /tmp/SmartRewriteAppAssignmentCheck
xcrun swiftc -parse-as-library \
  native/Sources/Core/SmartInput/RewriteProfile.swift \
  native/Sources/Core/SmartInput/SmartRewriteAutoRuleStore.swift \
  native/Tests/ApplicationScopeTestStubs.swift \
  native/Tests/ApplicationScopeLegacyBaselineCheck.swift \
  -o /tmp/ApplicationScopeLegacyBaselineCheck &&
  /tmp/ApplicationScopeLegacyBaselineCheck
```

Expected: 全部 PASS。

- [x] **Step 6: 更新计划证据并提交**

```bash
git add \
  native/Sources/Core/SmartInput/SmartRewriteAutoRuleStore.swift \
  native/Sources/Presentation/Main/Dialogs/SmartRewriteAutoRuleDialog.swift \
  native/Tests/SmartRewriteAppAssignmentCheck.swift \
  native/Tests/ApplicationScopeArchitectureBoundaryCheck.sh \
  native/Tests/SmartInputCheck.swift \
  docs/superpowers/plans/2026-07-23-application-scope-and-auto-send.md
git commit -m "feat: add exact app defaults to rewrite scope"
```

**Completion evidence:** RED 因 `appModesByBundleID` 不存在而失败；GREEN 后
应用默认模式、旧 JSON 解码、旧自定义规则顺序和“高级规则优先于应用默认”
全部通过。额外 RED 锁定旧弹窗在新 UI 上线前必须原样保留 app 默认映射，
避免用户临时打开旧入口时清空新配置。`SmartRewriteAppAssignmentCheck`、
旧基线、旧弹窗 parse 和架构边界检查全部 PASS。

---

### Task 5: 建立只在设置页运行的应用目录

**Status:** Completed

**Files:**

- Create: `native/Sources/Infrastructure/Applications/ApplicationCatalog.swift`
- Create: `native/Tests/ApplicationCatalogCheck.swift`
- Create: `native/Tests/ApplicationCatalogRuntimeBoundaryCheck.sh`
- Modify: `docs/superpowers/plans/2026-07-23-application-scope-and-auto-send.md`

**Interfaces:**

- Consumes: `RecentTargetApplicationStore`
- Produces:

```swift
enum ApplicationCategory: String, CaseIterable {
    case recent, communication, productivity, development, browser, other, all
}

struct ApplicationCatalogItem: Equatable {
    let bundleIdentifier: String
    let displayName: String
    let bundleURL: URL
    let category: ApplicationCategory
    let lastUsedAt: Date?
}

protocol ApplicationCatalogLoading {
    func load() async -> [ApplicationCatalogItem]
    func cancel()
}
```

- [x] **Step 1: 重读计划并确认应用分类来源**

已在计划阶段验证：当前 Swift Foundation 不提供
`URLResourceKey.applicationCategoryTypeKey` /
`URLResourceValues.applicationCategoryType`。实现必须读取应用 Bundle 的
`Info.plist`：

```swift
let categoryIdentifier = Bundle(url: applicationURL)?
    .object(forInfoDictionaryKey: "LSApplicationCategoryType") as? String
```

系统分类缺失时才使用有限的 Bundle ID 规则补足；不得依赖不存在的 URL resource API。

- [x] **Step 2: 写去重、分类、取消 RED**

使用注入的候选 URL 和元数据 loader，断言：

```swift
precondition(items.filter {
    $0.bundleIdentifier == "com.apple.dt.Xcode"
}.count == 1)
precondition(items.first {
    $0.bundleIdentifier == "com.apple.dt.Xcode"
}?.category == .development)
precondition(items.first {
    $0.bundleIdentifier == "com.tencent.xinWeChat"
}?.category == .communication)
```

另验证无 Bundle ID、重复 Bundle ID、无法读取分类、取消后的结果。

- [x] **Step 3: 运行 RED**

Run:

```bash
xcrun swiftc -parse-as-library \
  native/Sources/Infrastructure/Applications/RecentTargetApplicationStore.swift \
  native/Tests/ApplicationCatalogCheck.swift \
  -o /tmp/ApplicationCatalogCheck
```

Expected: `ApplicationCatalog` 不存在，失败。

- [x] **Step 4: 实现目录加载**

实现约束：

```swift
let roots = [
    URL(fileURLWithPath: "/Applications", isDirectory: true),
    FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Applications", isDirectory: true),
    URL(fileURLWithPath: "/System/Applications", isDirectory: true),
]
```

- 在 utility task/queue 枚举 `.app`；
- 用 Bundle ID 去重；
- 最近应用合并后排序在前；
- 分类优先读取系统 application category，再使用有限 Bundle ID 规则补足 communication/browser；
- 不加载图标；图标由 UI 对可见行调用 `NSWorkspace.shared.icon(forFile:)`；
- `cancel()` 只取消当前窗口的加载任务；
- 不创建 Timer、通知监听或 singleton 常驻扫描。

- [x] **Step 5: 运行 GREEN 与运行时边界**

`ApplicationCatalogRuntimeBoundaryCheck.sh` 必须拒绝：

```bash
rg -n 'Timer|SpeechSession|AudioRecorder|RealtimePreview|TranscriptionProvider' \
  native/Sources/Infrastructure/Applications/ApplicationCatalog.swift
```

Run:

```bash
xcrun swiftc -parse-as-library \
  native/Sources/Infrastructure/Applications/RecentTargetApplicationStore.swift \
  native/Sources/Infrastructure/Applications/ApplicationCatalog.swift \
  native/Tests/ApplicationCatalogCheck.swift \
  -o /tmp/ApplicationCatalogCheck &&
  /tmp/ApplicationCatalogCheck
bash native/Tests/ApplicationCatalogRuntimeBoundaryCheck.sh
bash native/Tests/ApplicationScopeArchitectureBoundaryCheck.sh
```

Expected: 全部 PASS。

- [x] **Step 6: 更新计划证据并提交**

```bash
git add \
  native/Sources/Infrastructure/Applications/ApplicationCatalog.swift \
  native/Tests/ApplicationCatalogCheck.swift \
  native/Tests/ApplicationCatalogRuntimeBoundaryCheck.sh \
  docs/superpowers/plans/2026-07-23-application-scope-and-auto-send.md
git commit -m "feat: add on-demand application catalog"
```

**Completion evidence:** RED 因 `InstalledApplicationMetadata` /
`ApplicationCatalog` 不存在而失败。实现使用 MainActor 管理一次性加载任务，
实际目录枚举在 detached utility task 中完成；扫描协作响应取消，不加载图标，
不引用录音/实时/胶囊。测试覆盖 Bundle ID 去重、系统分类、浏览器 fallback、
无分类归入其他、最近使用排序、标准目录外的最近目标合并和取消传播。
`ApplicationCatalogCheck`、运行时边界和架构边界全部 PASS。

---

### Task 6: 建立自适应应用范围窗口和编辑模型

**Status:** Completed

**Files:**

- Create: `native/Sources/Presentation/Main/Dialogs/ApplicationScopeEditorModel.swift`
- Create: `native/Sources/Presentation/Main/Dialogs/ApplicationScopeWindowController.swift`
- Create: `native/Tests/ApplicationScopeEditorModelCheck.swift`
- Create: `native/Tests/ApplicationScopeLayoutBoundaryCheck.sh`
- Modify: `docs/superpowers/plans/2026-07-23-application-scope-and-auto-send.md`

**Interfaces:**

- Produces:

```swift
enum ApplicationScopeSection: Equatable {
    case rewrite
    case autoSend
}

struct ApplicationScopeDraft {
    var rewriteConfiguration: SmartRewriteAutoConfiguration
    var autoSendConfiguration: AutoSendConfiguration
}

enum ApplicationScopeWindowSizing {
    static let preferredContentSize = NSSize(width: 960, height: 620)
    static let minimumContentSize = NSSize(width: 820, height: 520)
    static func clampedContentSize(
        saved: NSSize?,
        visibleFrame: NSRect
    ) -> NSSize
}
```

- [x] **Step 1: 重读计划并检查现有 sheet 的固定尺寸限制**

Run:

```bash
sed -n '1,180p' native/Sources/Presentation/Shared/FormSheetController.swift
sed -n '1,220p' native/Sources/Presentation/Main/Dialogs/SmartRewriteAutoRuleDialog.swift
```

记录为什么新窗口不能复用固定 width/height constraint。

- [x] **Step 2: 写编辑模型与尺寸 RED**

必须验证：

```swift
let small = ApplicationScopeWindowSizing.clampedContentSize(
    saved: NSSize(width: 1400, height: 1000),
    visibleFrame: NSRect(x: 0, y: 0, width: 1280, height: 760)
)
precondition(small.width <= 1152)
precondition(small.height <= 684)

var draft = ApplicationScopeDraft(
    rewriteConfiguration: rewrite,
    autoSendConfiguration: autoSend
)
draft.setRewriteMode(.chat, for: ["com.tencent.xinWeChat"])
precondition(draft.autoSendConfiguration == autoSend)
draft.setAutoSendAction(.returnKey, for: ["com.tencent.xinWeChat"])
precondition(draft.rewriteConfiguration.appModesByBundleID["com.tencent.xinWeChat"] == .chat)
```

- [x] **Step 3: 运行 RED**

Run:

```bash
xcrun swiftc -parse-as-library \
  native/Sources/Domain/AutoSendDomain.swift \
  native/Sources/Core/SmartInput/RewriteProfile.swift \
  native/Sources/Core/SmartInput/SmartRewriteAutoRuleStore.swift \
  native/Tests/ApplicationScopeTestStubs.swift \
  native/Tests/ApplicationScopeEditorModelCheck.swift \
  -o /tmp/ApplicationScopeEditorModelCheck
```

Expected: editor/sizing 类型不存在，失败。

- [x] **Step 4: 实现草稿隔离与可调整 window**

Window 必须使用：

```swift
let window = NSWindow(
    contentRect: .zero,
    styleMask: [.titled, .resizable],
    backing: .buffered,
    defer: true
)
window.contentMinSize = ApplicationScopeWindowSizing.minimumContentSize
window.setContentSize(ApplicationScopeWindowSizing.clampedContentSize(
    saved: savedSize,
    visibleFrame: screen.visibleFrame
))
```

约束必须做到：

- 顶部标题/分段、底部按钮固定；
- 中间三栏使用 `NSSplitView` 或等价可压缩约束；
- 中间应用列表与右侧详情分别放入 `NSScrollView`；
- 关闭/取消时调用 catalog `cancel()`；
- 保存前只操作 draft，不边点边写 `UserDefaults`；
- 保存尺寸时只存宽高，恢复后重新 clamp。

- [x] **Step 5: 运行 GREEN 与布局边界**

`ApplicationScopeLayoutBoundaryCheck.sh` 必须检查：

```bash
rg -q '\\.resizable' native/Sources/Presentation/Main/Dialogs/ApplicationScopeWindowController.swift
rg -q 'contentMinSize' native/Sources/Presentation/Main/Dialogs/ApplicationScopeWindowController.swift
rg -q 'visibleFrame' native/Sources/Presentation/Main/Dialogs/ApplicationScopeWindowController.swift
rg -q 'NSScrollView' native/Sources/Presentation/Main/Dialogs/ApplicationScopeViewController.swift \
  native/Sources/Presentation/Main/Dialogs/ApplicationScopeWindowController.swift
```

Run:

```bash
xcrun swiftc -parse-as-library \
  native/Sources/Domain/AutoSendDomain.swift \
  native/Sources/Core/SmartInput/RewriteProfile.swift \
  native/Sources/Core/SmartInput/SmartRewriteAutoRuleStore.swift \
  native/Tests/ApplicationScopeTestStubs.swift \
  native/Sources/Presentation/Main/Dialogs/ApplicationScopeEditorModel.swift \
  native/Tests/ApplicationScopeEditorModelCheck.swift \
  -o /tmp/ApplicationScopeEditorModelCheck &&
  /tmp/ApplicationScopeEditorModelCheck
bash native/Tests/ApplicationScopeLayoutBoundaryCheck.sh
```

Expected: 全部 PASS。

- [x] **Step 6: 更新计划证据并提交**

```bash
git add \
  native/Sources/Presentation/Main/Dialogs/ApplicationScopeEditorModel.swift \
  native/Sources/Presentation/Main/Dialogs/ApplicationScopeWindowController.swift \
  native/Tests/ApplicationScopeEditorModelCheck.swift \
  native/Tests/ApplicationScopeLayoutBoundaryCheck.sh \
  docs/superpowers/plans/2026-07-23-application-scope-and-auto-send.md
git commit -m "feat: add adaptive application scope window"
```

**Completion evidence:** 旧 `FormSheetController` 只有 `.titled` 样式并把内容
宽高锁成常量，无法支持该编辑器。RED 因草稿、编辑模型和尺寸策略不存在而失败。
实现后，窗口会把首选/历史尺寸重新限制在当前屏幕 `visibleFrame` 的 90% 内；
小屏幕会同步收缩最小尺寸。标题区、内容容器和底部按钮使用纵向约束固定分区，
未引入固定内容宽高。编辑模型只操作内存草稿，取消恢复打开时状态，保存才调用
持久化闭包；关闭窗口会取消目录加载并只保存宽高。模型测试、窗口 typecheck、
布局边界和架构边界全部 PASS。

---

### Task 7: 实现 A+C 应用选择与整理范围编辑

**Status:** Completed

**Files:**

- Create: `native/Sources/Presentation/Main/Dialogs/ApplicationScopeApplicationRowView.swift`
- Create: `native/Sources/Presentation/Main/Dialogs/ApplicationScopeViewController.swift`
- Modify: `native/Sources/Presentation/Main/Dialogs/ApplicationScopeWindowController.swift`
- Modify: `native/Tests/ApplicationScopeLayoutBoundaryCheck.sh`
- Modify: `docs/superpowers/plans/2026-07-23-application-scope-and-auto-send.md`

**Interfaces:**

- Consumes: `ApplicationCatalogLoading`、`ApplicationScopeDraft`
- Produces: 分类、搜索、多选、仅看已配置、应用默认整理模式、通用高级规则编辑

- [x] **Step 1: 重读规格、设计稿和计划**

检查视觉稿 `.superpowers` 只作参考，不 stage。明确布局：

```text
顶部：标题 + 整理范围/自动发送
左：分类
中：搜索 + 应用列表 + 多选
右：当前应用设置 + 高级规则
底：摘要 + 取消/保存
```

- [x] **Step 2: 扩展 Presentation RED**

`ApplicationScopeEditorModelCheck` 增加：

```swift
model.query = "xcode"
precondition(model.visibleApplications.map(\.bundleIdentifier) == ["com.apple.dt.Xcode"])
model.category = .communication
precondition(model.visibleApplications.allSatisfy { $0.category == .communication })
model.showsConfiguredOnly = true
precondition(model.visibleApplications.allSatisfy(model.isConfigured))
```

边界脚本必须验证应用目录和配置 Store 只能由 editor/window controller 使用，row view 不得读取 Store：

```bash
if rg -n 'UserDefaults|SmartRewriteAutoRuleStore|AutoSendSettingsStore' \
  native/Sources/Presentation/Main/Dialogs/ApplicationScopeApplicationRowView.swift; then
  exit 1
fi
```

- [x] **Step 3: 运行 RED**

Run Task 6 的 EditorModel 编译命令。

Expected: 筛选 API 或 ViewController 不存在，失败。

- [x] **Step 4: 实现 A+C 主界面**

实现要求：

- `NSSegmentedControl` 切换两个分段；
- 左侧分类使用单选列表；
- 中间 `NSTableView` 支持多选，行高不低于 48 点；
- 可见行才从 `NSWorkspace.shared.icon(forFile:)` 取图标；
- 搜索匹配展示名称和 Bundle ID；
- 当前应用详情显示默认整理模式；
- “通用高级规则”完整映射现有 `rules`，允许启用、标题、匹配目标、匹配口述、关键词、模式和顺序编辑；
- 旧规则未修改时保存结果必须 `Equatable` 相等；
- 视图只改 draft，保存由 window controller 一次执行。

行视图更新接口固定为：

```swift
func render(
    item: ApplicationCatalogItem,
    icon: NSImage,
    isSelected: Bool,
    valueText: String
)
```

- [x] **Step 5: 运行 GREEN、parse 与边界测试**

Run:

```bash
xcrun swiftc -parse-as-library \
  native/Sources/Domain/AutoSendDomain.swift \
  native/Sources/Core/SmartInput/RewriteProfile.swift \
  native/Sources/Core/SmartInput/SmartRewriteAutoRuleStore.swift \
  native/Tests/ApplicationScopeTestStubs.swift \
  native/Sources/Infrastructure/Applications/ApplicationCatalog.swift \
  native/Sources/Presentation/Main/Dialogs/ApplicationScopeEditorModel.swift \
  native/Tests/ApplicationScopeEditorModelCheck.swift \
  -o /tmp/ApplicationScopeEditorModelCheck &&
  /tmp/ApplicationScopeEditorModelCheck
xcrun swiftc -parse \
  native/Sources/Presentation/Main/Dialogs/ApplicationScopeApplicationRowView.swift \
  native/Sources/Presentation/Main/Dialogs/ApplicationScopeViewController.swift \
  native/Sources/Presentation/Main/Dialogs/ApplicationScopeWindowController.swift
bash native/Tests/ApplicationScopeLayoutBoundaryCheck.sh
bash native/Tests/ApplicationScopeArchitectureBoundaryCheck.sh
```

Expected: 全部 PASS。

- [x] **Step 6: 更新计划证据并提交**

```bash
git add \
  native/Sources/Presentation/Main/Dialogs/ApplicationScopeApplicationRowView.swift \
  native/Sources/Presentation/Main/Dialogs/ApplicationScopeViewController.swift \
  native/Sources/Presentation/Main/Dialogs/ApplicationScopeWindowController.swift \
  native/Tests/ApplicationScopeEditorModelCheck.swift \
  native/Tests/ApplicationScopeLayoutBoundaryCheck.sh \
  docs/superpowers/plans/2026-07-23-application-scope-and-auto-send.md
git commit -m "feat: add unified application scope editor"
```

**Completion evidence:** 扩展 RED 因应用列表、查询、分类和“仅看已配置”API
不存在而失败。GREEN 后，同一个编辑模型按当前分段分别判断整理配置与自动发送
配置，搜索同时匹配名称和 Bundle ID；分类、最近使用、多选和仅看已配置均通过
测试。界面使用三栏 `NSSplitView`，应用列表和详情分别滚动；应用行高 52 点，
图标只在可见行创建时由 UI 加载并缓存。右侧支持批量设置，整理分段完整保留
高级规则的启用、标题、窗口/口述条件、关键词、模式、顺序和 fallback；自动
发送分段只展示总开关与三种动作。行视图不读取 Store/UserDefaults，所有编辑
仍只进入 draft。模型、零警告 typecheck、布局边界与架构边界全部 PASS。

---

### Task 8: 接入自动发送设置与两个页面入口

**Status:** Completed

**Files:**

- Create: `native/Tests/ApplicationScopeSettingsEntryCheck.sh`
- Modify: `native/Sources/Presentation/Main/MainViewController.swift`
- Modify: `native/Sources/Presentation/Main/MainViewController+Configuration.swift`
- Modify: `native/Sources/Presentation/Main/MainViewController+PanelLayout.swift`
- Modify: `native/Sources/Presentation/Main/MainViewController+Actions.swift`
- Modify: `native/Sources/Presentation/Main/Dialogs/ApplicationScopeViewController.swift`
- Modify: `native/Sources/Presentation/Main/Dialogs/ApplicationScopeWindowController.swift`
- Modify: `docs/superpowers/plans/2026-07-23-application-scope-and-auto-send.md`

**Interfaces:**

- Consumes: `ApplicationScopeWindowController(initialSection:)`
- Produces:
  - 常用 > 粘贴与发送 > 总开关 / 应用范围
  - 智能 > 应用范围

- [x] **Step 1: 重读计划并盘点设置控件的 load/save/action**

Run:

```bash
sed -n '120,180p' native/Sources/Presentation/Main/MainViewController.swift
sed -n '300,360p' native/Sources/Presentation/Main/MainViewController.swift
sed -n '1,90p' native/Sources/Presentation/Main/MainViewController+Actions.swift
sed -n '245,440p' native/Sources/Presentation/Main/MainViewController+PanelLayout.swift
```

把控件创建、初始值、target/action、保存和布局位置写回本文。

实际接线：控件声明位于 `MainViewController`；初始化与 target/action 位于
`MainViewController+Configuration`；常用页“粘贴与发送”与智能页“应用范围”
位于 `MainViewController+PanelLayout`；总开关保存、两个入口和统一窗口装配
位于 `MainViewController+Actions`。

- [x] **Step 2: 写入口 RED**

`ApplicationScopeSettingsEntryCheck.sh` 必须验证：

```bash
#!/usr/bin/env bash
set -euo pipefail
rg -q '粘贴与发送' native/Sources/Presentation/Main/MainViewController+PanelLayout.swift
rg -q '粘贴后自动发送' native/Sources/Presentation/Main/MainViewController+PanelLayout.swift
rg -q 'ApplicationScopeSection\\.rewrite|initialSection: \\.rewrite' \
  native/Sources/Presentation/Main/MainViewController+Actions.swift
rg -q 'ApplicationScopeSection\\.autoSend|initialSection: \\.autoSend' \
  native/Sources/Presentation/Main/MainViewController+Actions.swift
rg -q 'AutoSendSettingsStore\\.save' \
  native/Sources/Presentation/Main/MainViewController+Actions.swift
```

- [x] **Step 3: 运行 RED**

Run:

```bash
bash native/Tests/ApplicationScopeSettingsEntryCheck.sh
```

Expected: 新入口不存在，失败。

- [x] **Step 4: 实现两个入口和总开关**

新增控件：

```swift
let autoSendAfterPaste = BrandSwitch()
let autoSendApplicationScopeButton = NSButton(title: "应用范围", target: nil, action: nil)
```

初始化：

```swift
let autoSendConfiguration = AutoSendSettingsStore.load()
autoSendAfterPaste.state = autoSendConfiguration.isEnabled ? .on : .off
autoSendAfterPaste.target = self
autoSendAfterPaste.action = #selector(saveAutoSendEnabled)
autoSendApplicationScopeButton.target = self
autoSendApplicationScopeButton.action = #selector(configureAutoSendApplicationScope)
```

保存总开关必须只改自动发送配置：

```swift
@objc func saveAutoSendEnabled() {
    var configuration = AutoSendSettingsStore.load()
    configuration.isEnabled = autoSendAfterPaste.state == .on
    AutoSendSettingsStore.save(configuration)
}
```

两个入口：

```swift
@objc func configureSmartRewriteAutoRules() {
    presentApplicationScope(initialSection: .rewrite)
}

@objc func configureAutoSendApplicationScope() {
    presentApplicationScope(initialSection: .autoSend)
}
```

保存窗口时分别调用两个 Store；取消时两个都不写。

- [x] **Step 5: 运行 GREEN 与完整 UI 边界**

Run:

```bash
bash native/Tests/ApplicationScopeSettingsEntryCheck.sh
bash native/Tests/ApplicationScopeLayoutBoundaryCheck.sh
bash native/Tests/ApplicationScopeArchitectureBoundaryCheck.sh
bash native/Tests/AutoSendIntegrationBoundaryCheck.sh
xcrun swiftc -parse \
  native/Sources/Presentation/Main/MainViewController.swift \
  native/Sources/Presentation/Main/MainViewController+Configuration.swift \
  native/Sources/Presentation/Main/MainViewController+PanelLayout.swift \
  native/Sources/Presentation/Main/MainViewController+Actions.swift
```

Expected: 全部 PASS。

- [x] **Step 6: 更新计划证据并提交**

```bash
git add \
  native/Sources/Presentation/Main/MainViewController.swift \
  native/Sources/Presentation/Main/MainViewController+Configuration.swift \
  native/Sources/Presentation/Main/MainViewController+PanelLayout.swift \
  native/Sources/Presentation/Main/MainViewController+Actions.swift \
  native/Sources/Presentation/Main/Dialogs/ApplicationScopeViewController.swift \
  native/Sources/Presentation/Main/Dialogs/ApplicationScopeWindowController.swift \
  native/Tests/ApplicationScopeSettingsEntryCheck.sh \
  docs/superpowers/plans/2026-07-23-application-scope-and-auto-send.md
git commit -m "feat: expose unified application scope settings"
```

- [x] **Step 7: 架构复审 Gate B**

复审 Task 4–8，必须确认：

- 旧规则解码、顺序和 fallback 无回归；
- UI 只修改草稿，保存时才写 Store；
- 两个分段只共用应用目录/UI，不共享配置；
- 应用扫描不常驻、不进入录音；
- 固定头尾与滚动区域满足窗口适配；
- 没有触碰 ASR、实时缓存或胶囊。

Run:

```bash
git diff HEAD~5..HEAD -- native/Sources native/Tests
bash native/Tests/ApplicationScopeArchitectureBoundaryCheck.sh
bash native/Tests/ApplicationCatalogRuntimeBoundaryCheck.sh
bash native/Tests/ApplicationScopeLayoutBoundaryCheck.sh
```

将结论写入本文再继续 Task 9。

**Completion evidence:** 入口 RED 因常用页分区、自动发送入口和统一窗口装配
不存在而失败。GREEN 后，常用页新增“粘贴与发送”，总开关读取/保存独立
`AutoSendSettingsStore`；智能页原“自动范围”改为“应用范围”。两个入口只改变
初始分段，保存时分别写两份 Store，取消不写。已完成 Gate B：旧 JSON 解码、
规则顺序和 fallback 测试仍通过；目录扫描只在窗口打开时运行；固定头尾和双
滚动区边界通过；ASR、实时缓存与胶囊无改动。旧固定弹窗已无引用，能力迁移后
删除其死代码和专属 UI 测试，保留配置兼容测试。为适配批准后的设置入口，
`AutoSendIntegrationBoundaryCheck` 收窄为“只有主设置控制器可读写 Store，
任何 Presentation 代码均不得发系统按键”。入口、布局、目录运行时、自动发送
集成及架构边界全部 PASS。

---

### Task 9: 全量验证、设计复核、构建安装与记录

**Status:** Implementation Complete — Manual Acceptance Pending

**Files:**

- Modify: `docs/ARCHITECTURE.md`
- Modify: `docs/产品需求文档.md`
- Modify: `docs/开发日志.md`
- Modify: `native/Sources/Presentation/VersionHistory/VersionHistoryViewController.swift`
- Modify: `docs/构建日志.md`（由构建脚本追加）
- Modify: `docs/superpowers/plans/2026-07-23-application-scope-and-auto-send.md`

**Interfaces:**

- Produces: 可审计的最终 build、真实安装版和测试证据

- [x] **Step 1: 重读完整计划并复核本轮 diff 范围**

Run:

```bash
sed -n '1,999p' docs/superpowers/plans/2026-07-23-application-scope-and-auto-send.md
git status --short
git diff --stat
git diff --check
```

Expected: 不包含受保护目录和无关文件。

- [x] **Step 2: 运行功能、边界和回归测试**

Run:

```bash
/tmp/AutoSendSettingsStoreCheck
/tmp/AutoSendPolicyCheck
/tmp/PostPasteKeyEmitterCheck
/tmp/PastePostActionSequencingCheck
/tmp/RecentTargetApplicationStoreCheck
/tmp/ApplicationCatalogCheck
/tmp/SmartRewriteAppAssignmentCheck
/tmp/ApplicationScopeEditorModelCheck
/tmp/ApplicationScopeLegacyBaselineCheck
bash native/Tests/ApplicationScopeArchitectureBoundaryCheck.sh
bash native/Tests/ApplicationCatalogRuntimeBoundaryCheck.sh
bash native/Tests/ApplicationScopeLayoutBoundaryCheck.sh
bash native/Tests/ApplicationScopeSettingsEntryCheck.sh
bash native/Tests/AutoSendIntegrationBoundaryCheck.sh
bash native/Tests/CapsulePreviewIndependenceBoundaryCheck.sh
bash native/Tests/MainWindowLayoutBoundaryCheck.sh
bash native/Tests/HotkeyWakeSuppressionBoundaryCheck.sh
```

Expected: 全部 PASS；任何失败先修复并在对应 Task 记录，不能跳过。

- [x] **Step 3: 更新产品、架构、开发日志与版本历史**

文档必须明确：

```text
应用目录只在设置页按需加载。
整理范围与自动发送共用 UI，但 Store 和执行链路独立。
自动发送只由普通非翻译听写在成功粘贴后触发。
追加按键失败不改变文本粘贴结果，也不阻塞队列。
```

版本历史必须写明用户可见入口、默认关闭、按应用动作和自适应窗口。

- [x] **Step 4: 构建前并发检查**

Run:

```bash
git branch --show-current
git status --short
pgrep -af 'build_and_log|release_local_build|build_native_app|swiftc|xcodebuild' || true
stat -f '%Sm %N' \
  native/build_and_log.sh \
  native/release_local_build.sh \
  native/Sources/Presentation/VersionHistory/VersionHistoryViewController.swift \
  docs/开发日志.md
```

Expected: 无并发写入或构建；如有并发，立即降级只读并报告。

- [x] **Step 5: 执行日常构建、覆盖安装和验签**

Run:

```bash
./native/build_and_log.sh
```

Expected:

- build 号递增 1；
- 短版本号不变；
- `/Applications/TypeWhale Pro.app` 被覆盖并打开；
- 签名验证通过；
- `docs/构建日志.md` 追加记录。

- [x] **Step 6: 使用 `design-review` 复核真实安装版**

必须检查：

1. 内建屏和当前副屏不越界；
2. 窗口缩到最小不重叠；
3. 标题、分段、保存/取消始终可见；
4. 左侧分类、中间列表、右侧规则滚动正确；
5. 应用图标、选中状态、多选和批量设置清楚；
6. 整理/自动发送切换后数据不串；
7. 关闭总开关后 UI 仍可编辑范围，但运行时不发送。

把截图/观察结论写入本文；无法覆盖的状态明确列为风险。

初次安装版复核发现 `FINDING-001`：选择“通用高级规则”后，中间应用列表仍
占用大半窗口，右侧规则编辑被压窄并截断关键词。已新增
`ApplicationScopeAdvancedLayoutBoundaryCheck.sh`，RED 确认缺少布局切换；
修复后高级规则模式收起应用列表并扩展规则工作区。Build 811 复核发现返回
应用分类后列表宽度被压缩，因此继续补充“记住并恢复原列表宽度”的回归测试；
最终修正版使用 Build 812 复核。

Build 812 真实安装版复核结果：

- 正常尺寸三栏清楚；缩到 `820 × 520` 后标题、分段、列表、详情、保存和取消均可见且不重叠。
- 高级规则模式隐藏无关应用列表，关键词不再截断；返回“全部应用”后恢复原列表宽度。
- 整理范围与自动发送切换后，应用状态分别显示，不共用草稿数据。
- 搜索、“仅看已配置”、应用图标和分类正常；取消窗口不写入设置。
- 自动发送已恢复默认关闭，测试配置已清除为 0 个。
- 当前显示器已验证；没有可安全自动化的副屏环境，副屏边界仍由 `visibleFrame × 90%` 约束和尺寸测试覆盖。

- [ ] **Step 7: 手动真实路径验收**

按顺序验证：

```text
1. 总开关关闭：在微信普通听写，只粘贴不发送。
2. 微信设为回车并开启：普通听写粘贴后发送。
3. 一个测试应用设为 Command+回车：收到组合键。
4. 未配置应用：只粘贴。
5. 录音后立刻切换前台应用：不追加按键。
6. 开启自动翻译：只粘贴翻译结果，不追加按键。
7. 闪念和 OpenClaw：保持原行为。
8. 智能页旧高级规则：打开、保存后匹配结果不变。
9. 连续十次普通听写：无乱序、漏粘贴或卡住。
```

自动化已覆盖动作选择、粘贴 readiness、目标切换、翻译/闪念/OpenClaw
排除、失败不阻塞和队列顺序。真实应用中的回车、`Command + 回车` 与连续
十次听写需要产品负责人用实际输入目标验收，因此本 Step 保持未勾选。

- [x] **Step 8: 更新计划完成状态并提交最终 build**

提交前只 stage 本轮文件：

```bash
git status --short
git diff --check
git add \
  native/build_native_app.sh \
  native/Sources/Presentation/VersionHistory/VersionHistoryViewController.swift \
  docs/ARCHITECTURE.md \
  docs/产品需求文档.md \
  docs/开发日志.md \
  docs/构建日志.md \
  docs/superpowers/plans/2026-07-23-application-scope-and-auto-send.md
git diff --cached --stat
git commit -m "release: ship application scope and auto send"
```

Expected: 提交不包含 `.superpowers/` 和两个受保护目录。

---

## Completion Definition

只有同时满足以下条件才可以宣布完成：

- Task 0–9 全部标记 Completed，并记录实际测试/commit/build 证据；
- 自动发送默认关闭且只作用于普通非翻译听写；
- 回车、`Command + 回车`、未配置、失败和焦点切换路径均通过；
- 旧整理规则、fallback 和规则顺序保持兼容；
- 应用目录只在设置页按需运行；
- 窗口在当前内建屏和副屏内自适应；
- 实时识别、主胶囊、最终交付、快捷键、闪念和 OpenClaw 无回归；
- 真实安装版已覆盖安装并完成设计复核；
- 最终代码、版本历史、开发日志、构建日志和本文已提交。
