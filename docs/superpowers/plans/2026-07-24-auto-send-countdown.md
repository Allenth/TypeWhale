# 自动发送倒计时与取消 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 普通听写成功粘贴后，为已配置的回车或 `Command + 回车` 提供 1.5 秒可见倒计时，并允许点击“取消”或按 `Esc` 只取消发送、不撤销文字。

**Architecture:** `PasteCoordinator` 在粘贴事件成功发出后把冻结的目标与动作提交给独立 `AutoSendCountdownCoordinator`，立即继续原粘贴恢复和队列。Coordinator 是倒计时状态唯一所有者；Presenter 只显示，现有 `HotkeyMonitor` 只在存在倒计时时吞掉一次完整的 Esc down/up；到期后 Coordinator 重新核对目标 PID，再调用原 `PostPasteKeyEmitter`。

**Tech Stack:** Swift、AppKit、ApplicationServices/CGEvent、Foundation Timer、现有 `PasteCoordinator` / `SpeechInputCoordinator` / `HotkeyMonitor` / `PostPasteKeyEmitter`、Swift 可执行检查、shell 边界检查、`design-review`、`native/build_and_log.sh`。

## Global Constraints

- 设计规格：`docs/superpowers/specs/2026-07-24-auto-send-countdown-design.md`；每个 Task 开工前必须重读规格和本文。
- 只在主目录 `$HOME/Pictures/macOSwinOSCoding/TypeSpeaker` 与分支 `codex/typewhale-pro-asr-hotwords` 开发，不新建 worktree。
- 每次只做一个 Task；每个 Task 严格执行 RED → GREEN → 回归 → 更新本文 → commit。
- 固定倒计时 `1.5` 秒；本次不增加用户设置。
- 取消只影响追加按键，不撤销、不修改已经粘贴的文字。
- 浮层不得抢焦点；UI 不持有计时和发送决策。
- 自动发送总开关关闭、动作 `.none`、翻译、闪念、OpenClaw、手动复制、粘贴失败时不得创建倒计时。
- 新录音、目标应用切换、旧任务被替换、应用退出时不得补发旧按键。
- 不修改 ASR、VAD、实时缓存、Final ASR、整理提示词、主胶囊、旁路胶囊及翻译结果生成。
- 不读取、修改、stage 或提交受保护目录：`.superpowers/`、`native/Helpers/CapsuleConceptGallery/`、`native/Sources/Presentation/Capsule/Concepts/`。
- 代码完成后执行日常构建，递增 build 号、覆盖安装、打开、验签并提交。
- UI 完成后使用 `design-review` 复核真实安装版的焦点、可读性、点击取消、Esc、闪烁和消失节奏。

---

## File Structure

### 新建

- `native/Sources/Domain/AutoSendCountdownDomain.swift`
  定义倒计时请求、展示快照、取消/跳过原因、状态决策及 scheduler/presenter 边界；不依赖 AppKit。
- `native/Sources/Application/AutoSendCountdownCoordinator.swift`
  唯一持有 pending token、截止时间和 Timer；负责替换、取消、目标复核、发送和日志。
- `native/Sources/Presentation/AutoSend/AutoSendCountdownPresenter.swift`
  只管理不抢焦点的浮层、倒计时文本和取消按钮。
- `native/Tests/AutoSendCountdownDomainCheck.swift`
- `native/Tests/AutoSendCountdownCoordinatorCheck.swift`
- `native/Tests/AutoSendCountdownPresenterBoundaryCheck.sh`
- `native/Tests/AutoSendCountdownIntegrationBoundaryCheck.sh`
- `native/Tests/HotkeyEscapeCancellationCheck.swift`

### 修改

- `native/Sources/Domain/HotkeyDomain.swift`
  增加 Esc down/up 成对吞键的纯状态门。
- `native/Sources/Infrastructure/Hotkey/HotkeyMonitor.swift`
  复用现有全局事件 tap，在倒计时确实取消时吞掉 Esc down/up；无倒计时时不改变 Esc。
- `native/Sources/Infrastructure/Paste/PasteCoordinator.swift`
  把立即发送改为提交倒计时；粘贴恢复和下一请求不等待 1.5 秒。
- `native/Sources/Application/SpeechInputCoordinator.swift`
  组合 Coordinator/Presenter/Emitter；普通粘贴传 task ID；新录音和 stop 时取消 pending。
- `native/Sources/Presentation/VersionHistory/VersionHistoryViewController.swift`
- `docs/ARCHITECTURE.md`
- `docs/产品需求文档.md`
- `docs/开发日志.md`
- `docs/构建日志.md`
- 本计划

---

### Task 0: 锁定现有自动发送与粘贴队列基线

**Status:** Completed

**Files:**

- Modify: `docs/superpowers/plans/2026-07-24-auto-send-countdown.md`
- Test: `native/Tests/PostPasteKeyEmitterCheck.swift`
- Test: `native/Tests/PastePostActionSequencingCheck.swift`
- Test: `native/Tests/AutoSendIntegrationBoundaryCheck.sh`

**Interfaces:**

- Consumes: `PostPasteActionGate.evaluate(_:)`、`PasteCoordinator.enqueue(...)`
- Produces: 当前即时发送行为与层级边界的可复核基线

- [x] **Step 1: 重读规格、计划并执行并发检查**

Run:

```bash
sed -n '1,260p' docs/superpowers/specs/2026-07-24-auto-send-countdown-design.md
sed -n '1,999p' docs/superpowers/plans/2026-07-24-auto-send-countdown.md
git branch --show-current
git status --short
pgrep -af 'build_and_log|release_local_build|build_native_app|swiftc|xcodebuild' || true
```

Expected: 分支正确；只有三个受保护目录与本文是已知现场；没有其他构建进程。

- [x] **Step 2: 运行现有行为测试**

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

bash native/Tests/AutoSendIntegrationBoundaryCheck.sh
```

Expected: 三项全部 PASS。

- [x] **Step 3: 记录代码走读事实**

在本 Task 下追加：

```text
Baseline:
- Command+V 发出后 0.08 秒直接发送追加按键。
- 剪贴板 0.3 秒后恢复并释放 PasteCoordinator 队列。
- SpeechInputCoordinator 在入队前冻结 task、目标应用和动作。
- HotkeyMonitor 已有唯一全局 CGEvent tap，可复用而不新增第二个 tap。
```

- [x] **Step 4: 提交基线记录**

```bash
git add docs/superpowers/plans/2026-07-24-auto-send-countdown.md
git commit -m "docs: lock auto-send countdown baseline"
```

**Baseline evidence:**

- `Command + V` 发出后 0.08 秒直接发送追加按键。
- 剪贴板 0.3 秒后恢复并释放 `PasteCoordinator` 队列。
- `SpeechInputCoordinator` 在入队前冻结 task、目标应用和动作。
- `HotkeyMonitor` 已有唯一全局 `CGEvent` tap，可复用而不新增第二个 tap。
- `PostPasteKeyEmitterCheck`、`PastePostActionSequencingCheck` 与
  `AutoSendIntegrationBoundaryCheck` 全部通过。

---

### Task 1: 倒计时领域状态与 Esc 成对门禁

**Status:** Completed

**Files:**

- Create: `native/Sources/Domain/AutoSendCountdownDomain.swift`
- Modify: `native/Sources/Domain/HotkeyDomain.swift`
- Create: `native/Tests/AutoSendCountdownDomainCheck.swift`
- Create: `native/Tests/HotkeyEscapeCancellationCheck.swift`
- Modify: `docs/superpowers/plans/2026-07-24-auto-send-countdown.md`

**Interfaces:**

- Consumes: `PostPasteAction`
- Produces:
  - `AutoSendCountdownRequest`
  - `AutoSendCountdownSnapshot`
  - `AutoSendCountdownTerminalReason`
  - `AutoSendCountdownDecision.evaluate(...)`
  - `PostPasteActionScheduling`
  - `PostPasteActionSchedulingGate.shouldSchedule(_:)`
  - `EscapeCancellationGate.handle(keyCode:isDown:cancel:) -> Bool`

- [x] **Step 1: 写倒计时领域 RED**

Create `native/Tests/AutoSendCountdownDomainCheck.swift`:

```swift
import Foundation

@main
enum AutoSendCountdownDomainCheck {
    static func main() {
        let token = UUID()
        let request = AutoSendCountdownRequest(
            token: token,
            taskID: UUID(),
            action: .returnKey,
            targetPID: 42,
            targetBundleIdentifier: "com.example.chat",
            startedAt: 100,
            deadline: 101.5
        )
        guard case .continueCounting(let remaining) =
            AutoSendCountdownDecision.evaluate(
                request: request,
                now: 100.6,
                frontmostPID: 42
            ) else {
            preconditionFailure("countdown must still be active")
        }
        precondition(abs(remaining - 0.9) < 0.001)
        precondition(
            AutoSendCountdownDecision.evaluate(
                request: request,
                now: 101.5,
                frontmostPID: 42
            ) == .emit
        )
        precondition(
            AutoSendCountdownDecision.evaluate(
                request: request,
                now: 101.5,
                frontmostPID: 99
            ) == .skip(.focusChanged)
        )
        precondition(PostPasteActionSchedulingGate.shouldSchedule(.returnKey))
        precondition(PostPasteActionSchedulingGate.shouldSchedule(.commandReturn))
        precondition(!PostPasteActionSchedulingGate.shouldSchedule(.none))
        print("AutoSendCountdownDomainCheck passed")
    }
}
```

- [x] **Step 2: 写 Esc 门禁 RED**

Create `native/Tests/HotkeyEscapeCancellationCheck.swift`:

```swift
import Foundation

@main
enum HotkeyEscapeCancellationCheck {
    static func main() {
        var gate = EscapeCancellationGate()
        var cancelCalls = 0
        precondition(gate.handle(keyCode: 53, isDown: true) {
            cancelCalls += 1
            return true
        })
        precondition(gate.handle(keyCode: 53, isDown: false) {
            cancelCalls += 1
            return false
        })
        precondition(cancelCalls == 1)
        precondition(!gate.handle(keyCode: 53, isDown: true) { false })
        precondition(!gate.handle(keyCode: 12, isDown: true) { true })
        print("HotkeyEscapeCancellationCheck passed")
    }
}
```

- [x] **Step 3: 运行 RED**

Run:

```bash
xcrun swiftc -parse-as-library \
  native/Sources/Domain/AutoSendDomain.swift \
  native/Sources/Domain/AutoSendCountdownDomain.swift \
  native/Tests/AutoSendCountdownDomainCheck.swift \
  -o /tmp/AutoSendCountdownDomainCheck

xcrun swiftc -parse-as-library \
  native/Sources/Domain/HotkeyDomain.swift \
  native/Tests/HotkeyEscapeCancellationCheck.swift \
  -o /tmp/HotkeyEscapeCancellationCheck
```

Expected: FAIL，缺少倒计时类型和 `EscapeCancellationGate`。

- [x] **Step 4: 实现最小领域类型**

Create `native/Sources/Domain/AutoSendCountdownDomain.swift`:

```swift
import Foundation

struct AutoSendCountdownRequest: Equatable {
    let token: UUID
    let taskID: UUID
    let action: PostPasteAction
    let targetPID: pid_t
    let targetBundleIdentifier: String?
    let startedAt: TimeInterval
    let deadline: TimeInterval
}

struct AutoSendCountdownSnapshot: Equatable {
    let token: UUID
    let action: PostPasteAction
    let remainingSeconds: TimeInterval
}

protocol PostPasteActionScheduling: AnyObject {
    func schedule(
        action: PostPasteAction,
        taskID: UUID,
        targetPID: pid_t,
        targetBundleIdentifier: String?
    )
}

enum PostPasteActionSchedulingGate {
    static func shouldSchedule(_ action: PostPasteAction) -> Bool {
        action != .none
    }
}

enum AutoSendCountdownSkipReason: String, Equatable {
    case focusChanged
    case eventEmissionFailed
}

enum AutoSendCountdownCancelReason: String, Equatable {
    case cancelButton
    case escapeKey
    case newRecording
    case replaced
    case appStopping
}

enum AutoSendCountdownTerminalReason: Equatable {
    case emitted
    case cancelled(AutoSendCountdownCancelReason)
    case skipped(AutoSendCountdownSkipReason)
}

enum AutoSendCountdownDecision: Equatable {
    case continueCounting(remainingSeconds: TimeInterval)
    case emit
    case skip(AutoSendCountdownSkipReason)

    static func evaluate(
        request: AutoSendCountdownRequest,
        now: TimeInterval,
        frontmostPID: pid_t?
    ) -> Self {
        let remaining = max(0, request.deadline - now)
        if remaining > 0 {
            return .continueCounting(remainingSeconds: remaining)
        }
        guard frontmostPID == request.targetPID else {
            return .skip(.focusChanged)
        }
        return .emit
    }
}
```

Append to `native/Sources/Domain/HotkeyDomain.swift`:

```swift
struct EscapeCancellationGate {
    private var consumedKeyDown = false

    mutating func handle(
        keyCode: Int,
        isDown: Bool,
        cancel: () -> Bool
    ) -> Bool {
        guard keyCode == 53 else { return false }
        if isDown {
            let cancelled = cancel()
            consumedKeyDown = cancelled
            return cancelled
        }
        guard consumedKeyDown else { return false }
        consumedKeyDown = false
        return true
    }
}
```

- [x] **Step 5: 运行 GREEN 与领域回归**

Run:

```bash
xcrun swiftc -parse-as-library \
  native/Sources/Domain/AutoSendDomain.swift \
  native/Sources/Domain/AutoSendCountdownDomain.swift \
  native/Tests/AutoSendCountdownDomainCheck.swift \
  -o /tmp/AutoSendCountdownDomainCheck &&
  /tmp/AutoSendCountdownDomainCheck

xcrun swiftc -parse-as-library \
  native/Sources/Domain/HotkeyDomain.swift \
  native/Tests/HotkeyEscapeCancellationCheck.swift \
  -o /tmp/HotkeyEscapeCancellationCheck &&
  /tmp/HotkeyEscapeCancellationCheck
```

Expected: 两项 PASS。

- [x] **Step 6: 更新计划并提交**

```bash
git add \
  native/Sources/Domain/AutoSendCountdownDomain.swift \
  native/Sources/Domain/HotkeyDomain.swift \
  native/Tests/AutoSendCountdownDomainCheck.swift \
  native/Tests/HotkeyEscapeCancellationCheck.swift \
  docs/superpowers/plans/2026-07-24-auto-send-countdown.md
git commit -m "feat: define cancellable auto-send countdown state"
```

---

### Task 2: 独立倒计时协调器

**Status:** Completed

**Files:**

- Create: `native/Sources/Application/AutoSendCountdownCoordinator.swift`
- Create: `native/Tests/AutoSendCountdownCoordinatorCheck.swift`
- Modify: `docs/superpowers/plans/2026-07-24-auto-send-countdown.md`

**Interfaces:**

- Consumes: `AutoSendCountdownRequest`、`AutoSendCountdownDecision`
- Produces:
  - `AutoSendCountdownPresenting`
  - `AutoSendCountdownTimerScheduling`
  - `AutoSendCountdownCoordinator.schedule(...)`
  - `AutoSendCountdownCoordinator.cancel(reason:) -> Bool`
  - `AutoSendCountdownCoordinator.isCountingDown`

- [x] **Step 1: 写 Coordinator RED**

Create `native/Tests/AutoSendCountdownCoordinatorCheck.swift`，使用可手动触发的
`FakeTimerScheduler`、记录 snapshots 的 `FakePresenter` 和注入的 `now/frontmostPID/emit`；
必须断言：

```swift
precondition(presenter.shown.last?.remainingSeconds == 1.5)
now = 101.5
scheduler.fire()
precondition(emitted == [.returnKey])
precondition(!coordinator.isCountingDown)

coordinator.schedule(action: .returnKey, taskID: task, targetPID: 42, targetBundleIdentifier: nil)
precondition(coordinator.cancel(reason: .escapeKey))
precondition(emitted.count == 1)

coordinator.schedule(action: .returnKey, taskID: UUID(), targetPID: 42, targetBundleIdentifier: nil)
coordinator.schedule(action: .commandReturn, taskID: UUID(), targetPID: 42, targetBundleIdentifier: nil)
precondition(terminals.contains(.cancelled(.replaced)))

frontmostPID = 99
now += 1.5
scheduler.fire()
precondition(terminals.last == .skipped(.focusChanged))
```

- [x] **Step 2: 运行 RED**

Run:

```bash
xcrun swiftc -parse-as-library \
  native/Sources/Domain/AutoSendDomain.swift \
  native/Sources/Domain/AutoSendCountdownDomain.swift \
  native/Sources/Application/AutoSendCountdownCoordinator.swift \
  native/Tests/AutoSendCountdownCoordinatorCheck.swift \
  -o /tmp/AutoSendCountdownCoordinatorCheck
```

Expected: FAIL，Coordinator 与协议不存在。

- [x] **Step 3: 实现协议与 Coordinator**

`native/Sources/Application/AutoSendCountdownCoordinator.swift` 必须包含：

```swift
import Foundation

@MainActor
protocol AutoSendCountdownPresenting: AnyObject {
    func show(
        snapshot: AutoSendCountdownSnapshot,
        onCancel: @escaping () -> Void
    )
    func update(snapshot: AutoSendCountdownSnapshot)
    func dismiss()
}

protocol AutoSendCountdownTimerToken: AnyObject {
    func invalidate()
}

@MainActor
protocol AutoSendCountdownTimerScheduling {
    func scheduleRepeating(
        interval: TimeInterval,
        handler: @escaping () -> Void
    ) -> any AutoSendCountdownTimerToken
}

@MainActor
final class AutoSendCountdownCoordinator: PostPasteActionScheduling {
    static let duration: TimeInterval = 1.5
    static let tickInterval: TimeInterval = 0.05

    private let presenter: any AutoSendCountdownPresenting
    private let timerScheduler: any AutoSendCountdownTimerScheduling
    private let now: () -> TimeInterval
    private let frontmostPID: () -> pid_t?
    private let emit: (PostPasteAction) -> Bool
    private let diagnostics: (String) -> Void
    private var pending: AutoSendCountdownRequest?
    private var timer: (any AutoSendCountdownTimerToken)?

    var onTerminal: ((AutoSendCountdownTerminalReason) -> Void)?
    var isCountingDown: Bool { pending != nil }

    // schedule(action:taskID:targetPID:targetBundleIdentifier:) conforms to
    // PostPasteActionScheduling, replaces an old token with .replaced, shows 1.5 immediately,
    // starts one repeating timer, and captures token in every callback.
    // cancel(reason:) returns false when idle and never calls emit.
    // tick(token:) ignores stale tokens; on deadline it checks frontmost PID,
    // emits once, reports emitted/eventEmissionFailed/focusChanged, then cleans up.
}

@MainActor
final class MainRunLoopCountdownTimerScheduler:
    AutoSendCountdownTimerScheduling
{
    func scheduleRepeating(
        interval: TimeInterval,
        handler: @escaping () -> Void
    ) -> any AutoSendCountdownTimerToken {
        FoundationCountdownTimerToken(interval: interval, handler: handler)
    }
}
```

`FoundationCountdownTimerToken` 使用 scheduled `Timer`，`invalidate()` 后清空回调；
Coordinator 所有 terminal 路径统一调用一个 `finish(token:reason:)`，避免重复发送。

- [x] **Step 4: 运行 GREEN 与重复/旧 token 回归**

Run:

```bash
xcrun swiftc -parse-as-library \
  native/Sources/Domain/AutoSendDomain.swift \
  native/Sources/Domain/AutoSendCountdownDomain.swift \
  native/Sources/Application/AutoSendCountdownCoordinator.swift \
  native/Tests/AutoSendCountdownCoordinatorCheck.swift \
  -o /tmp/AutoSendCountdownCoordinatorCheck &&
  /tmp/AutoSendCountdownCoordinatorCheck
```

Expected: PASS；emit 数量严格等于期望，没有旧 token 补发。

- [x] **Step 5: 更新计划并提交**

```bash
git add \
  native/Sources/Application/AutoSendCountdownCoordinator.swift \
  native/Tests/AutoSendCountdownCoordinatorCheck.swift \
  docs/superpowers/plans/2026-07-24-auto-send-countdown.md
git commit -m "feat: coordinate cancellable auto-send countdown"
```

---

### Task 3: 不抢焦点的倒计时浮层

**Status:** Completed

**Files:**

- Create: `native/Sources/Presentation/AutoSend/AutoSendCountdownPresenter.swift`
- Create: `native/Tests/AutoSendCountdownPresenterBoundaryCheck.sh`
- Modify: `docs/superpowers/plans/2026-07-24-auto-send-countdown.md`

**Interfaces:**

- Consumes: `AutoSendCountdownPresenting`、`AutoSendCountdownSnapshot`
- Produces: `AutoSendCountdownPresenter`

- [x] **Step 1: 写 Presenter 边界 RED**

Create `native/Tests/AutoSendCountdownPresenterBoundaryCheck.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
file=native/Sources/Presentation/AutoSend/AutoSendCountdownPresenter.swift
rg -q 'nonactivatingPanel' "$file"
rg -q 'ignoresMouseEvents = false' "$file"
rg -q 'override var canBecomeKey: Bool \\{ false \\}' "$file"
rg -q '1\\.5 秒后发送' "$file"
rg -q '取消' "$file"
if rg -n 'PostPasteKeyEmitter|AutoSendSettingsStore|UserDefaults|Timer\\(' "$file"; then
  echo "Presenter must only render snapshots and forward cancel intent" >&2
  exit 1
fi
echo "AutoSendCountdownPresenterBoundaryCheck passed"
```

- [x] **Step 2: 运行 RED**

Run:

```bash
bash native/Tests/AutoSendCountdownPresenterBoundaryCheck.sh
```

Expected: FAIL，文件不存在。

- [x] **Step 3: 实现浮层**

创建 `AutoSendCountdownPresenter`：

```swift
@MainActor
final class AutoSendCountdownPresenter: AutoSendCountdownPresenting {
    private let panel = AutoSendCountdownPanel(
        contentRect: NSRect(x: 0, y: 0, width: 240, height: 44),
        styleMask: [.borderless, .nonactivatingPanel],
        backing: .buffered,
        defer: false
    )
    private let countdownLabel = NSTextField(labelWithString: "1.5 秒后发送")
    private let cancelButton = NSButton(title: "取消", target: nil, action: nil)
    private var onCancel: (() -> Void)?

    func show(
        snapshot: AutoSendCountdownSnapshot,
        onCancel: @escaping () -> Void
    ) {
        self.onCancel = onCancel
        update(snapshot: snapshot)
        positionOnActiveScreen()
        panel.orderFrontRegardless()
    }

    func update(snapshot: AutoSendCountdownSnapshot) {
        let value = ceil(snapshot.remainingSeconds * 10) / 10
        countdownLabel.stringValue =
            String(format: "%.1f 秒后发送", max(0, value))
    }

    func dismiss() {
        onCancel = nil
        panel.orderOut(nil)
    }
}

private final class AutoSendCountdownPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
```

要求：

- `panel.level = .statusBar`；
- `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]`；
- `hidesOnDeactivate = false`、`ignoresMouseEvents = false`；
- 采用系统字体、`hudWindow` 材质、单色信息层级；
- 浮层位于当前可见屏幕底部中央上方 28pt，限制在 `visibleFrame`；
- 按钮点击只调用 `onCancel`，不直接隐藏、不读设置、不发按键。

- [x] **Step 4: 运行 GREEN 与语法检查**

Run:

```bash
chmod +x native/Tests/AutoSendCountdownPresenterBoundaryCheck.sh
bash native/Tests/AutoSendCountdownPresenterBoundaryCheck.sh
xcrun swiftc -parse \
  native/Sources/Presentation/AutoSend/AutoSendCountdownPresenter.swift
```

Expected: PASS。

- [x] **Step 5: 更新计划并提交**

```bash
git add \
  native/Sources/Presentation/AutoSend/AutoSendCountdownPresenter.swift \
  native/Tests/AutoSendCountdownPresenterBoundaryCheck.sh \
  docs/superpowers/plans/2026-07-24-auto-send-countdown.md
git commit -m "feat: present nonactivating auto-send countdown"
```

#### Architecture Review A（Task 1–3 后）

**Status:** Accepted

**Depth:** Rapid

**Decision:** 保持“Domain 状态 + Application 唯一倒计时所有者 + Presentation
纯展示”边界；生产接入复用现有 `HotkeyMonitor` 的唯一 `CGEvent` tap，不新增第二套
全局键盘监听。

**Confirmed facts:**

- `AutoSendCountdownCoordinator` 唯一持有 pending token、deadline 和 Timer。
- 旧 token、替换、取消、焦点变化和事件失败已由可控时钟测试覆盖。
- `AutoSendCountdownPresenter` 不引用设置、粘贴、Emitter 或 Timer。
- Presenter 使用 `.nonactivatingPanel`，声明不能成为 key/main window。

**Execution contract:**

- Task 4 可以修改粘贴调度和快捷键接线。
- 禁止在 `PasteCoordinator` 内等待 1.5 秒或持有 UI。
- 禁止新增第二个 `CGEvent` tap；Esc 仅在取消回调返回 true 时吞掉 down/up。
- 新录音必须取消旧 pending；倒计时失败只降级为“不发送”，不得影响已粘贴文字。
- 若生产编译发现 actor 隔离、焦点或事件 tap 冲突，立即重新打开本决策。

---

### Task 4: 接入粘贴队列、新录音取消与全局 Esc

**Status:** Completed

**Files:**

- Modify: `native/Sources/Infrastructure/Paste/PasteCoordinator.swift`
- Modify: `native/Sources/Infrastructure/Hotkey/HotkeyMonitor.swift`
- Modify: `native/Sources/Application/SpeechInputCoordinator.swift`
- Create: `native/Tests/AutoSendCountdownIntegrationBoundaryCheck.sh`
- Modify: `native/Tests/PastePostActionSequencingCheck.swift`
- Modify: `docs/superpowers/plans/2026-07-24-auto-send-countdown.md`

**Interfaces:**

- Consumes: `AutoSendCountdownCoordinator.schedule(...)`、`.cancel(reason:)`
- Produces: 普通粘贴成功后的生产倒计时与两个取消入口

- [x] **Step 1: 写生产接入 RED**

Create `native/Tests/AutoSendCountdownIntegrationBoundaryCheck.sh`，要求：

```bash
require_pattern 'postPasteActionScheduler\\.schedule' "$paste"
require_pattern 'taskID:' "$paste"
require_pattern 'autoSendCountdownCoordinator\\.cancel\\(reason: \\.newRecording\\)' "$speech"
require_pattern 'hotkey\\.onEscape' "$speech"
require_pattern 'escapeCancellationGate\\.handle' "$hotkey"
reject_pattern 'postPasteActionDelay' "$paste"
reject_pattern 'asyncAfter.*1\\.5' "$paste"
reject_pattern 'AutoSendCountdownPresenter' "$paste"
```

并检查 `Presentation` 不引用 `PostPasteKeyEmitter`，Presenter 不引用
`PasteCoordinator`，`PasteCoordinator` 不引用 `UserDefaults`。

- [x] **Step 2: 更新时序测试 RED**

把 `PastePostActionSequencingCheck` 从“立即 emit/skip”改为断言：

```swift
precondition(PostPasteActionSchedulingGate.shouldSchedule(.returnKey))
precondition(PostPasteActionSchedulingGate.shouldSchedule(.commandReturn))
precondition(!PostPasteActionSchedulingGate.shouldSchedule(.none))
```

- [x] **Step 3: 运行 RED**

Run:

```bash
bash native/Tests/AutoSendCountdownIntegrationBoundaryCheck.sh
xcrun swiftc -parse-as-library \
  native/Sources/Domain/AutoSendDomain.swift \
  native/Sources/Domain/AutoSendCountdownDomain.swift \
  native/Sources/Infrastructure/Paste/PostPasteKeyEmitter.swift \
  native/Tests/PastePostActionSequencingCheck.swift \
  -o /tmp/PastePostActionSequencingCheck
```

Expected: FAIL，生产代码仍是 0.08 秒立即发送。

- [x] **Step 4: 修改 PasteCoordinator**

将 `Request` 增加 `taskID: UUID`；`enqueue` 要求调用者传入 task ID。
构造函数改为注入：

```swift
private let postPasteActionScheduler: any PostPasteActionScheduling

init(postPasteActionScheduler: any PostPasteActionScheduling) {
    self.postPasteActionScheduler = postPasteActionScheduler
}
```

`Command + V` 发出后调用：

```swift
private func schedulePostPasteActionIfNeeded(for request: Request) {
    guard let targetApp = request.targetApp,
          PostPasteActionSchedulingGate.shouldSchedule(
              request.postPasteAction
          ) else {
        return
    }
    postPasteActionScheduler.schedule(
        action: request.postPasteAction,
        taskID: request.taskID,
        targetPID: targetApp.processIdentifier,
        targetBundleIdentifier: targetApp.bundleIdentifier
    )
}
```

删除 `postPasteActionDelay`、`emitPostPasteActionIfAllowed` 和 PasteCoordinator
对 `PostPasteKeyEmitter` 的所有权。0.3 秒剪贴板恢复与 `finish` 保持原样。

- [x] **Step 5: 修改 HotkeyMonitor**

增加：

```swift
var onEscape: (() -> Bool)?
private var escapeCancellationGate = EscapeCancellationGate()
```

在 `handleKey(event:isDown:)` 最前面：

```swift
let eventKeyCode = Int(
    event.getIntegerValueField(.keyboardEventKeycode)
)
if escapeCancellationGate.handle(
    keyCode: eventKeyCode,
    isDown: isDown,
    cancel: { [weak self] in self?.onEscape?() ?? false }
) {
    return true
}
```

要求完整吞掉被使用的 Esc down/up；`onEscape` 返回 false 时事件继续交给目标应用。

- [x] **Step 6: 在 SpeechInputCoordinator 组合依赖**

把属性改为 lazy：

```swift
private lazy var autoSendCountdownCoordinator =
    AutoSendCountdownCoordinator(
        presenter: AutoSendCountdownPresenter(),
        timerScheduler: MainRunLoopCountdownTimerScheduler(),
        now: { ProcessInfo.processInfo.systemUptime },
        frontmostPID: {
            NSWorkspace.shared.frontmostApplication?.processIdentifier
        },
        emit: { SystemPostPasteKeyEmitter().emit($0) },
        diagnostics: { LaunchDiagnostics.mark($0) }
    )
private lazy var pasteCoordinator = PasteCoordinator(
    postPasteActionScheduler: autoSendCountdownCoordinator
)
```

在 `start()` 设置：

```swift
hotkey.onEscape = { [weak self] in
    self?.autoSendCountdownCoordinator.cancel(reason: .escapeKey) ?? false
}
```

在实际开始新录音前调用：

```swift
autoSendCountdownCoordinator.cancel(reason: .newRecording)
```

在 `stop()` 调用：

```swift
autoSendCountdownCoordinator.cancel(reason: .appStopping)
```

粘贴入队时传：

```swift
taskID: result.task.id
```

浮层取消回调由 Coordinator 调用 `.cancelButton`，不经过 MainViewController。

- [x] **Step 7: 运行 GREEN 与原自动发送回归**

Run:

```bash
/tmp/AutoSendCountdownDomainCheck
/tmp/HotkeyEscapeCancellationCheck
/tmp/AutoSendCountdownCoordinatorCheck
bash native/Tests/AutoSendCountdownPresenterBoundaryCheck.sh
bash native/Tests/AutoSendCountdownIntegrationBoundaryCheck.sh
bash native/Tests/AutoSendIntegrationBoundaryCheck.sh
xcrun swiftc -parse-as-library \
  native/Sources/Domain/AutoSendDomain.swift \
  native/Sources/Domain/AutoSendCountdownDomain.swift \
  native/Sources/Infrastructure/Paste/PostPasteKeyEmitter.swift \
  native/Tests/PastePostActionSequencingCheck.swift \
  -o /tmp/PastePostActionSequencingCheck &&
  /tmp/PastePostActionSequencingCheck
```

Expected: 全部 PASS。

- [x] **Step 8: 更新计划并提交**

```bash
git add \
  native/Sources/Infrastructure/Paste/PasteCoordinator.swift \
  native/Sources/Infrastructure/Hotkey/HotkeyMonitor.swift \
  native/Sources/Application/SpeechInputCoordinator.swift \
  native/Tests/AutoSendCountdownIntegrationBoundaryCheck.sh \
  native/Tests/PastePostActionSequencingCheck.swift \
  docs/superpowers/plans/2026-07-24-auto-send-countdown.md
git commit -m "feat: delay and cancel post-paste send actions"
```

---

### Task 5: 架构复审、全量验证、构建安装与记录

**Status:** Completed（真实硬件 Fn 实录待产品验收）

**Files:**

- Modify: `docs/ARCHITECTURE.md`
- Modify: `docs/产品需求文档.md`
- Modify: `docs/开发日志.md`
- Modify: `native/Sources/Presentation/VersionHistory/VersionHistoryViewController.swift`
- Modify: `docs/构建日志.md`
- Modify: `docs/superpowers/plans/2026-07-24-auto-send-countdown.md`

**Interfaces:**

- Consumes: Task 1–4 全部产物
- Produces: 安装版、设计复核、测试证据和可回滚提交

- [x] **Step 1: 架构 Gate**

逐项确认并写入本文：

```text
- PasteCoordinator 未等待 1.5 秒，0.3 秒后照常释放队列。
- Coordinator 是 pending/token/timer 唯一所有者。
- Presenter 不读设置、不管理 Timer、不发按键。
- HotkeyMonitor 只在 cancel 返回 true 时吞 Esc。
- SpeechInputCoordinator 只组合依赖和通知新录音取消。
- ASR、缓存、胶囊、翻译与整理代码无改动。
```

任一不满足，先修正后才能继续。

证据（2026-07-24）：

```text
- PasteCoordinator 在 Cmd+V 后立即调度动作，仍于0.3秒恢复剪贴板并释放队列，没有等待1.5秒。
- AutoSendCountdownCoordinator 独占 pending、token 和 Timer；旧 token 不能复活。
- AutoSendCountdownPresenter 只渲染 snapshot 和转发取消点击。
- HotkeyMonitor 复用现有 event tap，只有 cancel 返回 true 时才吞 Esc down/up。
- SpeechInputCoordinator 只负责依赖组合、Esc接线，并在新录音/退出时通知取消。
- b0e59ba..43a74ed 的代码范围不包含ASR、缓存、胶囊、翻译或整理实现。
```

- [x] **Step 2: 运行所有新增和原自动发送测试**

Run:

```bash
/tmp/AutoSendCountdownDomainCheck
/tmp/HotkeyEscapeCancellationCheck
/tmp/AutoSendCountdownCoordinatorCheck
/tmp/PostPasteKeyEmitterCheck
/tmp/PastePostActionSequencingCheck
/tmp/AutoSendSettingsStoreCheck
/tmp/AutoSendPolicyCheck
/tmp/PasteboardReadinessGateCheck
bash native/Tests/AutoSendCountdownPresenterBoundaryCheck.sh
bash native/Tests/AutoSendCountdownIntegrationBoundaryCheck.sh
bash native/Tests/AutoSendIntegrationBoundaryCheck.sh
bash native/Tests/CapsulePreviewIndependenceBoundaryCheck.sh
bash native/Tests/MainWindowLayoutBoundaryCheck.sh
bash native/Tests/HotkeyWakeSuppressionBoundaryCheck.sh
git diff --check
```

Expected: 全部 PASS。

结果（2026-07-24）：上述 8 个 Swift 行为测试与 5 个边界检查全部 PASS；
`git diff --check` 通过。

- [x] **Step 3: 更新产品、架构、日志与版本历史**

必须记录：

```text
文字先粘贴；倒计时只控制追加按键。
固定 1.5 秒；点击取消和 Esc 均可取消。
切换应用、新录音、旧 token 和程序停止均不补发。
浮层是无焦点 Presentation；倒计时在 Application 层。
总开关仍是整体回滚入口。
```

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

Expected: 无并发写入或构建。

结果（2026-07-24）：分支为 `codex/typewhale-pro-asr-hotwords`，无构建进程；
工作区只有本任务文档和三个受保护的历史未跟踪目录，无重叠写入。

- [x] **Step 5: 日常构建、覆盖安装和验签**

Run:

```bash
./native/build_and_log.sh
```

Expected: build 号递增；短版本不变；安装、打开、签名和构建日志全部成功。

结果（2026-07-24）：日常构建成功生成并安装 `2.0.58 (Build 813)`；
`codesign --verify --deep --strict` 通过，安装版进程正常运行。

- [x] **Step 6: `design-review` 真实安装版复核**

必须检查：

1. 浮层在当前屏幕边界内，不遮挡主要输入区域；
2. 文案从 `1.5` 平滑递减且不跳宽；
3. 点击“取消”不抢前台应用焦点；
4. Esc 取消后目标应用不收到残缺的 key-up；
5. 自然结束、点击取消、Esc、焦点切换后浮层均只消失一次；
6. 连续任务不会出现两个浮层或旧倒计时复活；
7. 胶囊开关关闭时倒计时浮层仍可见。

结果（2026-07-24）：

```text
- 使用 Build 813 同一 AutoSendCountdownPresenter 启动真实 AppKit 浮层并截图复核。
- 244 × 46 深色 HUD、等宽倒计时、分隔线和绿色“取消”均清晰，无截断。
- 点击“取消”一次即退出，未发现重复消失或闲置窗口。
- 设计评分 A-，AI Slop 评分 A；无视觉修复项。
- 证据：~/.gstack/projects/Allenth-TypeWhale/designs/design-audit-20260724/
- 硬件 Fn 无法由桌面自动化触发；真实听写后的1.5→0.0动画、Esc、目标焦点和
  胶囊开关关闭场景保留为产品负责人一次人工实录验收，不虚报自动通过。
```

- [x] **Step 7: 自动化真实路径与人工验收清单**

```text
1. 总开关关闭：只粘贴，无浮层。
2. 回车开启：出现 1.5 秒倒计时，到期发送一次。
3. 点击取消：文字保留，不发送。
4. Esc 取消：文字保留，不发送。
5. Command + 回车：到期发送组合键。
6. 倒计时内切换应用：不发送。
7. 倒计时内开始新录音：旧发送取消。
8. 翻译、闪念、OpenClaw：无浮层。
9. 连续十次：无双发、漏粘贴、错应用或队列卡住。
```

自动化结果：领域、协调器、粘贴顺序、设置策略、Esc 配对、Presenter 与集成边界
覆盖上述状态；安装版和真实 Presenter 可运行。物理 Fn 实录按本清单由产品负责人
验证，不阻塞开发完成状态。

- [x] **Step 8: 更新计划状态并提交最终 build**

```bash
git status --short
git diff --check
git add \
  README.md \
  macos/README.md \
  native/build_native_app.sh \
  native/Sources/Presentation/VersionHistory/VersionHistoryViewController.swift \
  docs/ARCHITECTURE.md \
  docs/产品需求文档.md \
  docs/开发日志.md \
  docs/构建日志.md \
  docs/superpowers/plans/2026-07-24-auto-send-countdown.md
git diff --cached --stat
git commit -m "release: ship cancellable auto-send countdown"
```

Expected: 提交不包含三个受保护目录。

---

## Completion Definition

- Task 0–5 全部标记 Completed，并记录测试与提交证据。
- 普通听写文字先粘贴，倒计时固定 1.5 秒。
- 点击取消和 Esc 只取消追加按键，文字保持。
- 到期只发送一次；焦点变化、新录音、替换和退出不发送。
- PasteCoordinator 队列不等待倒计时。
- 总开关关闭及翻译、闪念、OpenClaw、未配置应用不创建倒计时。
- 浮层不抢焦点，胶囊关闭时仍可用。
- 新增、自动发送、粘贴、快捷键、主窗口和胶囊边界测试全部通过。
- 真实安装版已完成设计复核、覆盖安装和验签。
- 代码、版本历史、产品/架构/开发/构建文档与本文已提交。
