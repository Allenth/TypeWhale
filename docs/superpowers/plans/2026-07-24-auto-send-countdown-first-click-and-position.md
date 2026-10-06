# 自动发送倒计时首次取消与胶囊对齐 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 首次出现的自动发送浮层可以一击取消，倒计时改为 2 秒，并在主胶囊正上方 10px 横向居中。

**Architecture:** 日志和隔离复现证明普通按钮首击正常，失效来自 1.5 秒过短且浮层离胶囊太远。位置通过 Presenter 注入的只读 `popup.presentationFrame` 计算，不让自动发送反向持有具体胶囊；纯几何放进独立 Layout，Coordinator 只把固定时长从 1.5 改为 2.0。

**Tech Stack:** Swift 6、AppKit、现有无框 `NSPanel`、现有 Swift 可执行测试和 Bash 边界检查。

## Global Constraints

- 每次只做一个 Task，开工前读本计划，完成后更新本计划。
- 不新建 worktree，只在 `$HOME/Pictures/macOSwinOSCoding/TypeSpeaker` 当前分支开发。
- 浮层位于胶囊上方 10px，横向中心对齐，不覆盖胶囊。
- 上方空间不足时放到胶囊下方 10px；所有位置限制在目标屏幕 `visibleFrame` 内。
- 胶囊 frame 不可用时保留当前屏幕底部居中 fallback。
- 不修改 `PasteCoordinator` 的 0.3 秒释放，不改 ASR、缓存、最终粘贴、翻译、闪念、OpenClaw 和胶囊自身布局。
- 日常 build 必须递增 build 号、覆盖安装、打开、验签、更新文档并提交。

---

### Task 0: 复现、锁定根因并纠正方案

**Status:** Completed

**Files:**

- Modify: `docs/superpowers/specs/2026-07-24-auto-send-countdown-first-click-and-position-design.md`
- Modify: `docs/superpowers/plans/2026-07-24-auto-send-countdown-first-click-and-position.md`

**Interfaces:**

- Consumes: Build 813 `auto_send_countdown_*` 日志、非激活 Presenter 实景、AppKit `NSButton.acceptsFirstMouse(for:)`
- Produces: 已验证根因与不新增按钮子类的实现边界

- [x] **Step 1: 核对生产日志**

结果：首次倒计时终态为 `emitted`，第二次开始才出现
`cancelled_cancelButton`。

- [x] **Step 2: 隔离复现非激活浮层首击**

结果：同一 Presenter 在非激活临时 App 中第一次点击即可触发取消。

- [x] **Step 3: 核对系统按钮 first mouse**

Run:

```bash
xcrun swift -e \
  'import AppKit; print(NSButton(title: "取消", target: nil, action: nil).acceptsFirstMouse(for: nil))'
```

结果：`true`。

- [x] **Step 4: 纠正规格和计划**

结论：根因是 1.5 秒过短且浮层固定在屏幕底部；采用 2 秒和胶囊就近定位，不新增
无意义按钮子类。

- [x] **Step 5: 提交证据**

```bash
git add \
  docs/superpowers/specs/2026-07-24-auto-send-countdown-first-click-and-position-design.md \
  docs/superpowers/plans/2026-07-24-auto-send-countdown-first-click-and-position.md
git commit -m "docs: correct first-countdown root cause"
```

---

### Task 1: 2 秒时长与胶囊相邻几何

**Status:** Completed

**Files:**

- Create: `native/Sources/Presentation/AutoSend/AutoSendCountdownLayout.swift`
- Create: `native/Tests/AutoSendCountdownLayoutCheck.swift`
- Modify: `native/Sources/Application/AutoSendCountdownCoordinator.swift`
- Modify: `native/Tests/AutoSendCountdownCoordinatorCheck.swift`
- Modify: `docs/superpowers/plans/2026-07-24-auto-send-countdown-first-click-and-position.md`

**Interfaces:**

- Consumes: `capsuleFrame: CGRect?`、`overlaySize: CGSize`、`visibleFrame: CGRect`
- Produces: `AutoSendCountdownLayout.origin(...) -> CGPoint`

- [x] **Step 1: 写时长和几何 RED**

Coordinator assertions:

```swift
precondition(presenter.shown.last?.remainingSeconds == 2)
now = 101
scheduler.fireAll()
precondition(
    abs((presenter.updated.last?.remainingSeconds ?? 0) - 1) < 0.001
)
now = 102
scheduler.fireAll()
precondition(emitted == [.returnKey])
```

Create layout test:

```swift
import Foundation

@main
enum AutoSendCountdownLayoutCheck {
    static func main() {
        let visible = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let capsule = CGRect(x: 350, y: 68, width: 300, height: 60)
        let size = CGSize(width: 244, height: 46)
        let above = AutoSendCountdownLayout.origin(
            overlaySize: size,
            capsuleFrame: capsule,
            visibleFrame: visible
        )
        precondition(above == CGPoint(x: 378, y: 138))

        let topCapsule = CGRect(x: 350, y: 750, width: 300, height: 40)
        let below = AutoSendCountdownLayout.origin(
            overlaySize: size,
            capsuleFrame: topCapsule,
            visibleFrame: visible
        )
        precondition(below == CGPoint(x: 378, y: 694))

        let fallback = AutoSendCountdownLayout.origin(
            overlaySize: size,
            capsuleFrame: nil,
            visibleFrame: visible
        )
        precondition(fallback == CGPoint(x: 378, y: 28))
        print("AutoSendCountdownLayoutCheck passed")
    }
}
```

- [x] **Step 2: 运行 RED**

Run both tests. Expected: Coordinator 仍返回 1.5；Layout 类型不存在。

- [x] **Step 3: 写最小 GREEN**

Coordinator:

```swift
static let duration: TimeInterval = 2
```

Layout:

```swift
import Foundation

enum AutoSendCountdownLayout {
    static let gap: CGFloat = 10
    static let fallbackBottomInset: CGFloat = 28

    static func origin(
        overlaySize: CGSize,
        capsuleFrame: CGRect?,
        visibleFrame: CGRect
    ) -> CGPoint {
        guard let capsuleFrame else {
            return clamp(
                CGPoint(
                    x: visibleFrame.midX - overlaySize.width / 2,
                    y: visibleFrame.minY + fallbackBottomInset
                ),
                overlaySize: overlaySize,
                visibleFrame: visibleFrame
            )
        }
        let x = capsuleFrame.midX - overlaySize.width / 2
        let aboveY = capsuleFrame.maxY + gap
        let y = aboveY + overlaySize.height <= visibleFrame.maxY
            ? aboveY
            : capsuleFrame.minY - gap - overlaySize.height
        return clamp(
            CGPoint(x: x, y: y),
            overlaySize: overlaySize,
            visibleFrame: visibleFrame
        )
    }

    private static func clamp(
        _ origin: CGPoint,
        overlaySize: CGSize,
        visibleFrame: CGRect
    ) -> CGPoint {
        CGPoint(
            x: min(
                max(origin.x, visibleFrame.minX),
                visibleFrame.maxX - overlaySize.width
            ),
            y: min(
                max(origin.y, visibleFrame.minY),
                visibleFrame.maxY - overlaySize.height
            )
        )
    }
}
```

- [x] **Step 4: 运行 GREEN 与 Coordinator 回归**

Run:

```bash
xcrun swiftc -parse-as-library \
  native/Sources/Presentation/AutoSend/AutoSendCountdownLayout.swift \
  native/Tests/AutoSendCountdownLayoutCheck.swift \
  -o /tmp/AutoSendCountdownLayoutCheck &&
  /tmp/AutoSendCountdownLayoutCheck

xcrun swiftc -parse-as-library \
  native/Sources/Domain/AutoSendDomain.swift \
  native/Sources/Domain/AutoSendCountdownDomain.swift \
  native/Sources/Application/AutoSendCountdownCoordinator.swift \
  native/Tests/AutoSendCountdownCoordinatorCheck.swift \
  -o /tmp/AutoSendCountdownCoordinatorCheck &&
  /tmp/AutoSendCountdownCoordinatorCheck
```

Expected: 两项 PASS。

- [x] **Step 5: 更新计划并提交**

结果：几何测试与 Coordinator 回归均通过；倒计时时长为 2 秒，布局计算与
UI/识别链路隔离。

```bash
git add \
  native/Sources/Presentation/AutoSend/AutoSendCountdownLayout.swift \
  native/Tests/AutoSendCountdownLayoutCheck.swift \
  native/Sources/Application/AutoSendCountdownCoordinator.swift \
  native/Tests/AutoSendCountdownCoordinatorCheck.swift \
  docs/superpowers/plans/2026-07-24-auto-send-countdown-first-click-and-position.md
git commit -m "feat: align two-second countdown above capsule"
```

---

### Task 2: Presenter 与主胶囊 frame 接线

**Status:** Completed

**Files:**

- Modify: `native/Sources/Presentation/AutoSend/AutoSendCountdownPresenter.swift`
- Modify: `native/Sources/Application/SpeechInputCoordinator.swift`
- Modify: `native/Tests/AutoSendCountdownPresenterBoundaryCheck.sh`
- Modify: `native/Tests/AutoSendCountdownIntegrationBoundaryCheck.sh`
- Modify: `docs/superpowers/plans/2026-07-24-auto-send-countdown-first-click-and-position.md`

**Interfaces:**

- Consumes: `capsuleFrame: () -> CGRect?`、`PreviewPresenting.presentationFrame`
- Produces: 每次显示时基于最新主胶囊 frame 的浮层位置

- [x] **Step 1: 写 Presenter/接线 RED**

Boundary checks must require:

```bash
rg -q 'capsuleFrame: @escaping \\(\\) -> CGRect\\?' "$presenter"
rg -q 'AutoSendCountdownLayout\\.origin' "$presenter"
rg -q 'self\\?\\.popup\\.presentationFrame' "$speech"
rg -q '2\\.0 秒后发送' "$presenter"
```

- [x] **Step 2: 运行 RED**

Expected: FAIL，Presenter 仍使用 1.5 文案和屏幕底部固定位置，且未接入胶囊 frame。

- [x] **Step 3: 写最小 GREEN**

Presenter:

```swift
private let capsuleFrame: () -> CGRect?

init(capsuleFrame: @escaping () -> CGRect? = { nil }) {
    self.capsuleFrame = capsuleFrame
    super.init()
    configurePanel()
    configureContent()
}
```

取消按钮继续使用系统 `NSButton`；默认文案改为 `2.0 秒后发送`。
定位时先用胶囊中心确定屏幕，再调用 `AutoSendCountdownLayout.origin(...)`；无胶囊
frame 时继续按鼠标所在屏幕 fallback。

Speech composition:

```swift
presenter: AutoSendCountdownPresenter(
    capsuleFrame: { [weak self] in
        self?.popup.presentationFrame
    }
),
```

- [x] **Step 4: 运行 GREEN 与边界回归**

Run:

```bash
bash native/Tests/AutoSendCountdownPresenterBoundaryCheck.sh
bash native/Tests/AutoSendCountdownIntegrationBoundaryCheck.sh
bash native/Tests/CapsulePreviewIndependenceBoundaryCheck.sh
bash native/Tests/MainWindowLayoutBoundaryCheck.sh
git diff --check
```

Expected: 全部 PASS。

- [x] **Step 5: 更新计划并提交**

结果：Presenter 只读取主胶囊最新 frame 决定展示位置；系统取消按钮、识别链路、
粘贴队列均保持原设计，四项边界检查通过。

```bash
git add \
  native/Sources/Presentation/AutoSend/AutoSendCountdownPresenter.swift \
  native/Sources/Application/SpeechInputCoordinator.swift \
  native/Tests/AutoSendCountdownPresenterBoundaryCheck.sh \
  native/Tests/AutoSendCountdownIntegrationBoundaryCheck.sh \
  docs/superpowers/plans/2026-07-24-auto-send-countdown-first-click-and-position.md
git commit -m "fix: anchor countdown to production capsule"
```

---

### Task 3: 全量验证、文档、Build 814 与安装验收

**Status:** Completed

**Files:**

- Modify: `docs/ARCHITECTURE.md`
- Modify: `docs/产品需求文档.md`
- Modify: `docs/开发日志.md`
- Modify: `docs/构建日志.md`
- Modify: `native/Sources/Presentation/VersionHistory/VersionHistoryViewController.swift`
- Modify: `README.md`
- Modify: `macos/README.md`
- Modify: `native/build_native_app.sh`
- Modify: `docs/superpowers/plans/2026-07-24-auto-send-countdown-first-click-and-position.md`

**Interfaces:**

- Consumes: Task 0–2 全部产物
- Produces: Build 814 安装版、设计复核和最终提交

- [x] **Step 1: 运行全部倒计时及关键回归**

结果：13 项倒计时、粘贴、设置、胶囊、主窗口及快捷键检查全部通过。两条历史
测试编译命令补齐 `AutoSendCountdownDomain.swift` 依赖后通过，产品代码无新增失败。

Run：

```bash
/tmp/AutoSendCountdownLayoutCheck
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

- [x] **Step 2: 更新文档与 Build 814 版本历史**

记录：2 秒、胶囊上方 10px、横向中心对齐、上方不足放下方、首次点击取消生效、
无 frame fallback，以及未改 ASR/缓存/粘贴队列。

- [x] **Step 3: 并发检查并执行日常构建**

结果：无并发构建或重叠写入；`2.0.58 (Build 814)` 已编译、覆盖安装、打开，
并通过 codesign deep/strict 校验。

```bash
git branch --show-current
git status --short
pgrep -af 'build_and_log|release_local_build|build_native_app|swiftc|xcodebuild' || true
./native/build_and_log.sh
```

Expected: `2.0.58 (Build 814)` 覆盖安装、打开、验签成功。

- [x] **Step 4: 真实安装版设计与首次点击复核**

检查：浮层以生产胶囊 frame 定位；2.0 文案不跳宽；重启后的第一次浮层一击取消；
第二次仍可取消；文字保留；自然结束与 Esc 正常。

结果：Build 814 安装版版本、进程和签名正常；同一生产 Presenter 的非激活临时
App 显示 `2.0 秒后发送` 无截断，重启后第一次点击“取消”即退出。胶囊相邻位置
由纯布局测试覆盖。Codex 未获整屏录制权限，因此“生产胶囊 + 浮层”同屏截图以及
真实 Fn 听写中的动画、Esc、目标焦点仍保留为产品负责人手动验收项。

- [x] **Step 5: 更新计划并提交**

```bash
git add \
  README.md \
  macos/README.md \
  native/build_native_app.sh \
  native/Sources/Presentation/VersionHistory/VersionHistoryViewController.swift \
  docs/ARCHITECTURE.md \
  docs/产品需求文档.md \
  docs/开发日志.md \
  docs/构建日志.md \
  docs/superpowers/plans/2026-07-24-auto-send-countdown-first-click-and-position.md
git commit -m "release: ship two-second capsule-aligned countdown"
```

---

## Completion Definition

- 第一次浮层第一次点击“取消”即生效，文字保留且不发送。
- 后续浮层点击、Esc 与自然倒计时继续正常。
- 倒计时固定 2 秒。
- 浮层在胶囊上方 10px 横向居中；屏幕边界和无 frame fallback 正常。
- 粘贴队列、ASR、缓存、最终文字和其他胶囊能力不变。
- 全部测试、Build 814、安装、验签、视觉复核、文档和提交完成。
