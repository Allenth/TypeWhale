# Three-Capsule Candidate Preview Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在不改变原胶囊和现有技术旁路的前提下，新增独立候选产品胶囊，对新核心已经真实返回的文字进行有界连续展示，为后续正式预览切换提供可对照的产品证据。

**Architecture:** 原胶囊继续走旧生产预览；现有 `ShadowPreview` 作为旁路1直接显示 `PreviewViewState`；`CandidatePreview` 作为旁路2独立订阅同一 `ShadowTranscriptionRuntime`。候选完整内容由`CandidateContentProjection`拥有，动画进度由只消费字符数的`CandidateTextMotion`拥有，二者在Model组合；两个旁路窗口、订阅和定时器完全独立，共用纯布局算法但不互相转发状态。

**Tech Stack:** Swift 6.2、AppKit、Swift Concurrency、AsyncStream、现有 Realtime Transcription Core、手工 Swift checks、`native/build_and_log.sh`。

## Global Constraints

- 每次开始下一 Task 前必须重新读取本计划、主计划 Global Constraints、当前 Task 和 `git status --short`。
- 每次写入、构建、安装、stage 或 commit 前执行分支、dirty、构建进程和相关 mtime 并发保护；发现重叠立即降级只读。
- 原胶囊、旧预览、完整录音 final ASR、VAD、整理、翻译、历史、OpenClaw 和粘贴不得修改。
- 旁路1保留真实技术节奏，不添加逐字动画、不消费旁路2显示状态。
- 旁路2只显示最新 `PreviewViewState` 已经包含的文字；不得生成 Provider 未返回的字，不得描述为服务端逐字识别或持续 PCM。
- 旁路2最多保留 24 个 Character 做动画，推进间隔固定为 50ms；积压更多时立即追赶到只剩 24 字。
- 非前缀修订必须干净切换，不允许把旧文本和新文本按位置混合。
- 两个旁路必须拥有独立 `AsyncStream` 订阅、Presenter、Panel、View、Timer/Task 和清理路径；一个 UI 不能向另一个转发状态。
- 关闭实验、失败、取消、完成或跨 session 时，两个旁路的订阅、Timer、Task 和窗口必须停止并清空。
- 每个代码 Task 必须先 RED、再 GREEN，完成后更新本计划 Execution Progress、版本历史和开发日志，运行 `./native/build_and_log.sh` 覆盖安装 `/Applications/TypeWhale Pro.app` 并验证签名。
- UI Task 必须执行 `design-review` 和真实安装版三胶囊复核；不能只靠源码推断。
- Task 13A 完成不授权 Stage 9B 生产切换，也不授权删除旧胶囊或旁路1。

## Execution Progress

| Task | Status | Commit | Verification | Next action |
| --- | --- | --- | --- | --- |
| 0 / Stage 8 + three-capsule decision | COMPLETE | `8fb24a1` | 主计划 Stage 8 已关闭；三胶囊规格、范围和门禁一致 | Task 0 Gate 达成；已重读计划并进入 Task 1 |
| 1 / Candidate stream buffer | COMPLETE | 本任务提交 | RED准确失败于类型缺失；GREEN与Shadow隔离通过；完整版本2.0.16 (705)构建、安装、打开、签名通过 | Task 1 Gate达成；重读计划后进入Task 2三胶囊布局与候选UI |
| 2 / Three-capsule layout + candidate UI | COMPLETE | `6f96adb` | 布局RED/GREEN、AppKit类型检查、Build706安装签名通过；真实组件截图design-review为A-且无P0/P1/P2 | Task 2 Gate达成；重读计划后进入Task 3独立候选生命周期 |
| 3 / Independent candidate lifecycle | COMPLETE | 本任务提交 | RED/GREEN、候选与技术旁路生命周期通过；Build707安装、打开、签名通过 | Task 3 Gate达成；重读计划后进入Task 4双状态流接线 |
| 4 / Coordinator wiring + diagnostics | AWAITING INSTALLED QA | 本任务提交 | RED/GREEN、隔离/生命周期/Broadcaster通过；完整版本2.0.17(708)安装签名且启动日志正常 | 用户执行20秒三胶囊smoke后关闭Task 4 |
| 4B / Three-provider candidate matrix | AWAITING INSTALLED QA | — | 矩阵RED/GREEN、Fake/MiMo Provider及隔离通过；无厂商UI分支 | Build710分别执行本地与MiMo安装版smoke |
| 5 / Installed acceptance + Stage 9A close | IN PROGRESS | — | 2026-07-12 核心候选缓存/三数据源矩阵/布局/接线/隔离回归通过；安装版2.0.17(710)签名通过 | 补齐生命周期、核心状态机聚焦回归，并执行本地+MiMo安装版人工矩阵；用户验收后才讨论 Stage 9B |

## File Map

### New candidate presentation

- `native/Sources/Presentation/CandidatePreview/CandidateStreamTextBuffer.swift`: 无 AppKit 的真实文本目标、追赶、推进和修订状态机。
- `native/Sources/Presentation/CandidatePreview/CandidatePreviewView.swift`: 绘制候选胶囊并拥有单一 50ms Timer。
- `native/Sources/Presentation/CandidatePreview/CandidatePreviewPresenter.swift`: 独立 `NSPanel` 生命周期。
- `native/Sources/Presentation/CandidatePreview/CandidatePreviewCoordinator.swift`: 独立状态订阅、session gate 和诊断。
- `native/Sources/Presentation/ShadowPreview/ThreeCapsuleLayout.swift`: 同时计算旁路1与旁路2安全位置。

### Modified integration

- `native/Sources/Presentation/ShadowPreview/ShadowPreviewPresenter.swift`: 仅改用三胶囊布局中的技术胶囊 frame；文字展示不变。
- `native/Sources/Application/SpeechInputCoordinator.swift`: 创建候选 Coordinator，从 runtime 获取第二个独立 state stream，开始/结束两套旁路并记录分离诊断。
- `native/build_native_app.sh`: 把新生产 Swift 文件加入构建输入（若脚本使用显式文件列表）。

### New/modified checks

- `native/Tests/CandidateStreamTextBufferCheck.swift`
- `native/Tests/ThreeCapsuleLayoutCheck.swift`
- `native/Tests/CandidatePreviewLifecycleCheck.swift`
- `native/Tests/ShadowPreviewIsolationCheck.sh`
- `native/Tests/OnlineASRShadowIsolationCheck.sh`

---

### Task 0: Record Stage 8 Closure And Three-Capsule Decision

**Files:**
- Modify: `docs/superpowers/plans/2026-07-11-realtime-transcription-shadow-capsule.md`
- Modify: `docs/superpowers/specs/2026-07-12-shadow-capsule-streamed-presentation-design.md`
- Modify: `docs/开发日志.md`
- Create: `docs/superpowers/plans/2026-07-12-three-capsule-candidate-preview.md`

**Interfaces:**
- Consumes: MiMo Build 703/704 evidence and product decision.
- Produces: Stage 8 complete status and Stage 9A exact execution source of truth.

- [x] **Step 1: Mark main-plan Task 12 Steps 2–3 and Stage 8 Exit Gate complete**

- [x] **Step 2: Replace the single-shadow animation design with three independent roles**

- [x] **Step 3: Record current state and unapproved Stage 9B/Task 14 boundaries**

- [x] **Step 4: Commit Task 0 documentation**

```bash
git add docs/superpowers/plans/2026-07-11-realtime-transcription-shadow-capsule.md \
  docs/superpowers/specs/2026-07-12-shadow-capsule-streamed-presentation-design.md \
  docs/superpowers/plans/2026-07-12-three-capsule-candidate-preview.md \
  docs/开发日志.md
git commit -m "docs: plan three-capsule preview migration"
```

Expected: documentation-only commit; no build or installed app change.

---

### Task 1: Build The Pure Candidate Stream Buffer

**Files:**
- Create: `native/Sources/Presentation/CandidatePreview/CandidateStreamTextBuffer.swift`
- Create: `native/Tests/CandidateStreamTextBufferCheck.swift`
- Modify after GREEN: version history files required by `build_and_log.sh`, `docs/开发日志.md`, this plan.

**Interfaces:**
- Consumes: `PreviewViewState.displayText`, `sessionID`, `sequence`, `failure`, `lifecycle`.
- Produces:

```swift
struct CandidateStreamTextBuffer {
    static let maximumAnimatedTail = 24
    private(set) var displayedText: String
    private(set) var targetText: String
    mutating func apply(_ state: PreviewViewState) -> CandidateStreamTextUpdate
    mutating func advance() -> CandidateStreamTextAdvance
    mutating func reset()
}

enum CandidateStreamTextUpdate: Equatable {
    case unchanged
    case updated(needsTimer: Bool)
    case cleared
}

enum CandidateStreamTextAdvance: Equatable {
    case advanced
    case finished
}
```

- [x] **Step 1: Write the failing pure-buffer check**

The check must construct real `PreviewViewState` values and assert:

```swift
var buffer = CandidateStreamTextBuffer()
precondition(buffer.apply(state(sequence: 1, text: "今天")) == .updated(needsTimer: true))
precondition(buffer.displayedText.isEmpty)
precondition(buffer.advance() == .advanced)
precondition(buffer.displayedText == "今")

let forty = String(repeating: "流", count: 40)
_ = buffer.apply(state(sequence: 2, text: forty))
precondition(buffer.targetText == forty)
precondition(buffer.targetText.count - buffer.displayedText.count <= 24)

let before = buffer.displayedText
precondition(buffer.apply(state(sequence: 2, text: forty)) == .unchanged)
precondition(buffer.displayedText == before)

_ = buffer.apply(state(sequence: 3, text: "完全修订"))
precondition("完全修订".hasPrefix(buffer.displayedText))
precondition(!buffer.displayedText.contains("流"))

precondition(buffer.apply(failedState(sequence: 4)) == .cleared)
precondition(buffer.displayedText.isEmpty && buffer.targetText.isEmpty)
```

- [x] **Step 2: Run RED**

```bash
swiftc -parse-as-library -o /tmp/typewhale-candidate-stream-buffer-check \
  native/Sources/Domain/RealtimeTranscription/TranscriptionIdentity.swift \
  native/Sources/Domain/RealtimeTranscription/TranscriptionEvent.swift \
  native/Sources/Domain/RealtimeTranscription/TranscriptState.swift \
  native/Sources/Domain/RealtimeTranscription/PreviewViewState.swift \
  native/Tests/CandidateStreamTextBufferCheck.swift
```

Expected: FAIL because `CandidateStreamTextBuffer` and result enums do not exist.

- [x] **Step 3: Implement the minimal buffer**

Implementation rules:

```swift
mutating func apply(_ state: PreviewViewState) -> CandidateStreamTextUpdate {
    guard state.failure == nil, state.lifecycle == .running else {
        reset()
        return .cleared
    }
    let incoming = state.displayText
    guard incoming != targetText else { return .unchanged }
    if incoming.hasPrefix(targetText), incoming.hasPrefix(displayedText) {
        targetText = incoming
        catchUpIfNeeded()
        return .updated(needsTimer: displayedText != targetText)
    }
    targetText = incoming
    displayedText = String(incoming.prefix(max(0, incoming.count - Self.maximumAnimatedTail)))
    return .updated(needsTimer: displayedText != targetText)
}

mutating func advance() -> CandidateStreamTextAdvance {
    guard displayedText != targetText else { return .finished }
    displayedText = String(targetText.prefix(displayedText.count + 1))
    return displayedText == targetText ? .finished : .advanced
}
```

`catchUpIfNeeded()` must set `displayedText` to `targetText.prefix(targetText.count - 24)` only when the backlog exceeds 24; it must never add characters absent from `targetText`.

- [x] **Step 4: Run GREEN and adjacent domain checks**

```bash
swiftc -parse-as-library -o /tmp/typewhale-candidate-stream-buffer-check \
  native/Sources/Domain/RealtimeTranscription/TranscriptionIdentity.swift \
  native/Sources/Domain/RealtimeTranscription/TranscriptionEvent.swift \
  native/Sources/Domain/RealtimeTranscription/TranscriptState.swift \
  native/Sources/Domain/RealtimeTranscription/PreviewViewState.swift \
  native/Sources/Presentation/CandidatePreview/CandidateStreamTextBuffer.swift \
  native/Tests/CandidateStreamTextBufferCheck.swift
/tmp/typewhale-candidate-stream-buffer-check
bash native/Tests/ShadowPreviewIsolationCheck.sh
```

Expected: `CandidateStreamTextBufferCheck passed` and `ShadowPreviewIsolationCheck passed`.

- [x] **Step 5: Update plan/version narrative, build and install**

Run concurrency protection, update version history/development log, then:

```bash
./native/build_and_log.sh
codesign --verify --deep --strict --verbose=2 '/Applications/TypeWhale Pro.app'
```

Expected: build/install/open/signature pass; UI behavior is unchanged because the buffer is not wired.

- [x] **Step 6: Commit Task 1 and mark its Execution Progress row complete**

```bash
git add native/Sources/Presentation/CandidatePreview/CandidateStreamTextBuffer.swift \
  native/Tests/CandidateStreamTextBufferCheck.swift \
  docs/superpowers/plans/2026-07-12-three-capsule-candidate-preview.md \
  docs/开发日志.md native/Sources/Presentation/VersionHistory/VersionHistoryViewController.swift README.md native/README.md docs/构建日志.md
git commit -m "feat: add bounded candidate stream buffer"
```

---

### Task 2: Add Safe Three-Capsule Layout And Candidate Panel

**Files:**
- Create: `native/Sources/Presentation/ShadowPreview/ThreeCapsuleLayout.swift`
- Create: `native/Sources/Presentation/CandidatePreview/CandidatePreviewView.swift`
- Create: `native/Sources/Presentation/CandidatePreview/CandidatePreviewPresenter.swift`
- Create: `native/Tests/ThreeCapsuleLayoutCheck.swift`
- Modify: `native/Sources/Presentation/ShadowPreview/ShadowPreviewPresenter.swift`
- Modify: `native/build_native_app.sh` if it explicitly enumerates sources.

**Interfaces:**
- Produces:

```swift
enum AuxiliaryCapsuleRole { case technical, candidate }

struct ThreeCapsuleFrames: Equatable {
    let technical: CGRect
    let candidate: CGRect
}

struct ThreeCapsuleLayout {
    static func frames(
        productionFrame: CGRect,
        technicalSize: CGSize,
        candidateSize: CGSize,
        visibleFrame: CGRect,
        gap: CGFloat = 8,
        edgeInset: CGFloat = 12
    ) -> ThreeCapsuleFrames
}

@MainActor protocol CandidatePreviewPresenting: AnyObject {
    func apply(_ state: PreviewViewState)
    func show(adjacentTo productionFrame: CGRect)
    func hideImmediately()
}
```

- [x] **Step 1: Write layout RED for below, above and constrained screens**

`ThreeCapsuleLayoutCheck` must assert all three frames are mutually non-intersecting and inside `visibleFrame` for:

```swift
let normal = CGRect(x: 0, y: 0, width: 1512, height: 940)
let production = CGRect(x: 656, y: 800, width: 200, height: 42)
let frames = ThreeCapsuleLayout.frames(
    productionFrame: production,
    technicalSize: CGSize(width: 252, height: 40),
    candidateSize: CGSize(width: 252, height: 40),
    visibleFrame: normal
)
precondition(!frames.technical.intersects(production))
precondition(!frames.candidate.intersects(production))
precondition(!frames.technical.intersects(frames.candidate))
```

Also cover a bottom-edge production frame and a narrow 800×600 visible frame. If two vertical auxiliaries do not fit on one side, place one below and one above; if neither arrangement fits, clamp a horizontal row inside safe insets without overlap.

- [x] **Step 2: Run RED**

```bash
swiftc -parse-as-library -o /tmp/typewhale-three-capsule-layout-check \
  native/Tests/ThreeCapsuleLayoutCheck.swift
```

Expected: FAIL because `ThreeCapsuleLayout` does not exist.

- [x] **Step 3: Implement shared layout and minimal candidate panel**

Both Presenters must call the same layout function with panel sizes 252×40 and select their own frame. `CandidatePreviewView` must:

- draw badge text `候选`;
- retain the latest `PreviewViewState` for stable/volatile styling;
- feed the state to `CandidateStreamTextBuffer`;
- own at most one scheduled 50ms Timer;
- invalidate the Timer in `resetPresentation()` and `deinit`;
- draw `buffer.displayedText`, never `state.displayText` directly.

- [x] **Step 4: Run GREEN, typecheck UI and layout regressions**

```bash
swiftc -parse-as-library -o /tmp/typewhale-three-capsule-layout-check \
  native/Sources/Presentation/ShadowPreview/ThreeCapsuleLayout.swift \
  native/Tests/ThreeCapsuleLayoutCheck.swift
/tmp/typewhale-three-capsule-layout-check

swiftc -typecheck \
  native/Sources/Domain/RealtimeTranscription/TranscriptionIdentity.swift \
  native/Sources/Domain/RealtimeTranscription/TranscriptState.swift \
  native/Sources/Domain/RealtimeTranscription/PreviewViewState.swift \
  native/Sources/Presentation/CandidatePreview/CandidateStreamTextBuffer.swift \
  native/Sources/Presentation/CandidatePreview/CandidatePreviewView.swift \
  native/Sources/Presentation/CandidatePreview/CandidatePreviewPresenter.swift \
  native/Sources/Presentation/ShadowPreview/ThreeCapsuleLayout.swift

swiftc -o /tmp/typewhale-shadow-layout-check \
  native/Sources/Presentation/ShadowPreview/ShadowPreviewLayout.swift \
  native/Tests/ShadowPreviewLayoutCheck.swift
/tmp/typewhale-shadow-layout-check
```

Expected: both layout checks pass; AppKit typecheck is clean.

- [x] **Step 5: Build/install, checkpoint the functional UI, then run design-review on a three-panel fixture**

Create a temporary fixture outside the repository that shows production, technical and candidate panels in waiting, incremental, 40-character catch-up and revision states. Run `design-review` for spacing, distinction, hierarchy, flicker, jump, truncation and safe-area behavior. Apply only issues within Task 2 scope.

`design-review` requires a clean tree. After GREEN and build verification, first commit the independently working Task 2 implementation, then start the review. Any visual finding must use its own atomic `style(design): FINDING-NNN — ...` commit and before/after evidence; do not fold review fixes into the functional commit.

```bash
./native/build_and_log.sh
codesign --verify --deep --strict --verbose=2 '/Applications/TypeWhale Pro.app'
```

- [x] **Step 6: Commit Task 2 and update Execution Progress**

```bash
git add native/Sources/Presentation/ShadowPreview/ThreeCapsuleLayout.swift \
  native/Sources/Presentation/ShadowPreview/ShadowPreviewPresenter.swift \
  native/Sources/Presentation/CandidatePreview/CandidatePreviewView.swift \
  native/Sources/Presentation/CandidatePreview/CandidatePreviewPresenter.swift \
  native/Tests/ThreeCapsuleLayoutCheck.swift native/build_native_app.sh \
  docs/superpowers/plans/2026-07-12-three-capsule-candidate-preview.md \
  docs/开发日志.md native/Sources/Presentation/VersionHistory/VersionHistoryViewController.swift README.md macos/README.md docs/构建日志.md
git commit -m "feat: add candidate preview panel layout"
```

---

### Task 3: Add An Independent Candidate Coordinator And Lifecycle

**Files:**
- Create: `native/Sources/Presentation/CandidatePreview/CandidatePreviewCoordinator.swift`
- Create: `native/Tests/CandidatePreviewLifecycleCheck.swift`
- Modify: `native/build_native_app.sh` if required.

**Interfaces:**
- Produces:

```swift
@MainActor final class CandidatePreviewCoordinator {
    var onRenderDiagnostics: ((PreviewViewState, Int) -> Void)?
    init(presenter: any CandidatePreviewPresenting)
    convenience init()
    func begin(
        states: AsyncStream<PreviewViewState>,
        productionFrame: @escaping @MainActor () -> CGRect?
    )
    func end()
}
```

- [x] **Step 1: Write lifecycle RED**

Using a fake Candidate Presenter, assert:

- first session state is applied and shown;
- another session is ignored;
- `end()` hides once and rejects late state;
- `.shadowPreviewSettingDidChange(false)` ends the candidate independently;
- beginning a second stream cancels the first stream;
- candidate fake and existing shadow fake receive states from two separate streams without forwarding.

- [x] **Step 2: Run RED**

```bash
swiftc -parse-as-library -o /tmp/typewhale-candidate-lifecycle-check \
  native/Sources/Domain/RealtimeTranscription/TranscriptionIdentity.swift \
  native/Sources/Domain/RealtimeTranscription/TranscriptState.swift \
  native/Sources/Domain/RealtimeTranscription/PreviewViewState.swift \
  native/Sources/Infrastructure/Settings/ShadowPreviewSettings.swift \
  native/Tests/CandidatePreviewLifecycleCheck.swift
```

Expected: FAIL because `CandidatePreviewCoordinator` and presenting protocol do not exist.

- [x] **Step 3: Implement by preserving the existing coordinator boundary**

The new Coordinator may follow the existing session gate pattern but must own its own `subscriptionTask`, `expectedSessionID` and setting observer. `end()` must call `presenter.hideImmediately()`, and Candidate Presenter hide must call `candidateView.resetPresentation()` before `panel.orderOut(nil)`.

- [x] **Step 4: Run GREEN and both lifecycle checks**

Compile and execute `CandidatePreviewLifecycleCheck` with the new Coordinator, then execute the existing `ShadowPreviewLifecycleCheck` unchanged. Expected: both print matching `passed` lines.

- [x] **Step 5: Build/install, verify signature, update plan and commit**

```bash
./native/build_and_log.sh
codesign --verify --deep --strict --verbose=2 '/Applications/TypeWhale Pro.app'
git commit -m "feat: isolate candidate preview lifecycle"
```

Stage only Task 3 code, tests, required version/log files and this plan.

---

### Task 4: Wire Two Independent New-Core State Streams

**Files:**
- Modify: `native/Sources/Application/SpeechInputCoordinator.swift`
- Modify: `native/Tests/ShadowPreviewIsolationCheck.sh`
- Modify: `native/Tests/OnlineASRShadowIsolationCheck.sh`
- Create: `native/Tests/ThreeCapsuleWiringCheck.sh`

**Interfaces:**
- Consumes: `ShadowTranscriptionRuntime.states()` twice, `ShadowPreviewCoordinator`, `CandidatePreviewCoordinator`.
- Produces: a running original capsule plus two isolated auxiliary panels when the existing experiment setting is enabled.

- [x] **Step 1: Write wiring/isolation RED**

The source check must require:

```text
private let candidatePreviewCoordinator = CandidatePreviewCoordinator()
let technicalStates = await runtime.states()
let candidateStates = await runtime.states()
shadowPreviewCoordinator.begin(states: technicalStates
candidatePreviewCoordinator.begin(states: candidateStates
candidatePreviewCoordinator.end()
```

It must also fail if CandidatePreview sources reference `finishRecording`, `PasteCoordinator`, `SpeechSession`, `committedPreviewText`, `latestPreviewText`, `MiMoSnapshotProvider`, `MiMoSSEParser`, WAV/Base64 or online credentials.

- [x] **Step 2: Run RED**

```bash
bash native/Tests/ThreeCapsuleWiringCheck.sh
```

Expected: FAIL because Candidate Coordinator is not wired and only one state stream is requested.

- [x] **Step 3: Add narrow coordinator wiring**

At successful shadow runtime start:

```swift
let technicalStates = await runtime.states()
let candidateStates = await runtime.states()
shadowPreviewCoordinator.begin(states: technicalStates) { [weak self] in
    self?.popup.presentationFrame
}
candidatePreviewCoordinator.begin(states: candidateStates) { [weak self] in
    self?.popup.presentationFrame
}
```

`endShadowPreview(cancelled:)` must end both coordinators before cancelling/completing runtime. Add candidate diagnostics named `candidate_preview_render` with session, sequence, visible character count and draw milliseconds; do not log transcript text.

- [x] **Step 4: Run GREEN and full isolation/lifecycle regressions**

```bash
bash native/Tests/ThreeCapsuleWiringCheck.sh
bash native/Tests/ShadowPreviewIsolationCheck.sh
bash native/Tests/OnlineASRShadowIsolationCheck.sh
```

Compile/run both lifecycle checks and `TranscriptionBroadcasterCheck`; verify two state subscribers are independent and remain bounded newest without an intermediate UI relay.

- [ ] **Step 5: Build, install and perform installed smoke QA**

```bash
./native/build_and_log.sh
codesign --verify --deep --strict --verbose=2 '/Applications/TypeWhale Pro.app'
```

Manual smoke:

1. 关闭旁路：录音时只出现原胶囊。
2. 开启旁路并选择MiMo：下一轮录音出现原胶囊、旁路1、旁路2。
3. 旁路1保持批次跳动；旁路2只对已到达文字连续推进。
4. 取消后两个旁路立即消失，下一轮无旧字。
5. final和粘贴与原链路一致。

- [x] **Step 6: Update plan and commit Task 4**

```bash
git commit -m "feat: wire independent candidate preview stream"
```

Stage only Task 4 code/tests, required version/log files and this plan.

#### Build 708 Installed Feedback Amendment

- 用户确认候选UI效果正常，但发现每个MiMo快照会把同一目标按 `a → ab → abc` 从头刷新。
- Build 708日志证明新快照开始时ViewState字符数出现 `7 → 1 → 7`、`16 → 1 → 16`；这是新请求SSE partial回放旧目标前缀，不是UI Timer重复。
- Task 4在关闭前增加候选缓存门禁：若incoming是当前target的严格短前缀，则保持当前显示和target不变；追平后仍不刷新，超过旧target后只动画真实新增尾部。非前缀修订继续干净替换。
- 旁路1和MiMo Provider保持原样，以继续保存真实技术证据；修复必须先扩展 `CandidateStreamTextBufferCheck` RED/GREEN，再重新构建安装。

---

### Task 4B: Prove Candidate Behavior Across Three Provider Classes

本任务由Build 708用户验收反馈补入，必须在Task 5前完成。候选胶囊的产品优化不能只对MiMo有效。

**Files:**
- Create: `native/Tests/CandidateProviderMatrixCheck.swift`
- Modify only if RED exposes a generic defect: `native/Sources/Presentation/CandidatePreview/CandidateStreamTextBuffer.swift`
- Modify: this plan and `docs/开发日志.md`

**Provider classes:**

1. 本地非流式快照/修订：Legacy Adapter或SenseVoice Snapshot产生整段ViewState，可能追加，也可能非前缀修订。
2. 本地流式：Fake Streaming Provider代表连续partial/finalized语义；后续真实本地流式模型必须复用同一事件契约。
3. 在线MiMo：每个完整音频快照的SSE会从短前缀重新累计，候选缓存必须抑制已展示前缀回放，只展示追平后的新增尾部。

- [x] **Step 1: Write one RED matrix against the public candidate buffer**

The check must feed real `PreviewViewState` sequences and assert:

```swift
// Local snapshot: append stays continuous; a real non-prefix correction replaces cleanly.
["今天讨论", "今天讨论模型", "今天改为验证模型"]

// Local streaming: each real partial remains eligible for progressive display.
["今", "今天", "今天讨论", "今天讨论在线模型"]

// MiMo snapshot SSE: replay prefixes do not restart display; only the extension animates.
["在线模型", "在", "在线", "在线模型", "在线模型支持流式输出"]
```

For every sequence, `displayedText` must never contain characters absent from the latest accepted target, backlog must stay `≤24`, and after draining it must equal the final accepted ViewState.

- [x] **Step 2: Run RED and identify whether the failure is generic or fixture-only**

```bash
swiftc -parse-as-library -o /tmp/typewhale-candidate-provider-matrix \
  native/Sources/Domain/RealtimeTranscription/TranscriptionIdentity.swift \
  native/Sources/Domain/RealtimeTranscription/TranscriptionEvent.swift \
  native/Sources/Domain/RealtimeTranscription/TranscriptState.swift \
  native/Sources/Domain/RealtimeTranscription/PreviewViewState.swift \
  native/Sources/Presentation/CandidatePreview/CandidateStreamTextBuffer.swift \
  native/Tests/CandidateProviderMatrixCheck.swift
/tmp/typewhale-candidate-provider-matrix
```

Expected: the first run must demonstrate at least one missing matrix invariant or the test is not a valid RED. Do not weaken an already-correct behavior merely to force failure; add the missing observable invariant first.

- [x] **Step 3: Fix only the generic buffer contract**

No `MiMo`, `SenseVoice`, `FakeStreamingProvider`, WAV, SSE or vendor name may enter CandidatePreview production sources. Provider-specific interpretation stays in fixtures; production code only compares accepted target strings and lifecycle state.

- [x] **Step 4: Run GREEN and provider-adjacent regressions**

Run the matrix, `CandidateStreamTextBufferCheck`, `FakeStreamingProviderCheck`, `MiMoSnapshotProviderCheck`, Shadow/Online isolation and both lifecycle checks. Expected: all pass without CandidatePreview importing provider types.

- [ ] **Step 5: Build/install and record the three-source readiness result**

Update version history, development log and this plan before `./native/build_and_log.sh`. Installed smoke must include one local Legacy/SenseVoice session and one MiMo session. Fake streaming remains a deterministic fixture unless explicitly launched with the existing debug argument.

- [x] **Step 6: Commit Task 4B**

```bash
git commit -m "test: prove candidate preview provider matrix"
```

**Task 4B Gate:** all three Provider classes produce correct candidate behavior through the same `PreviewViewState → CandidateStreamTextBuffer` contract; no provider-specific presentation branch exists.

---

### Task 5: Complete Installed Acceptance And Close Stage 9A

**Files:**
- Modify: `docs/SHADOW_PREVIEW_QA.md`
- Modify: `docs/ONLINE_STREAMING_PROVIDER_READINESS.md`
- Modify: `docs/ARCHITECTURE.md`
- Modify: `docs/开发日志.md`
- Modify: `docs/superpowers/plans/2026-07-11-realtime-transcription-shadow-capsule.md`
- Modify: this plan.

**Interfaces:**
- Consumes: installed three-capsule build and user observations.
- Produces: Stage 9A acceptance evidence; does not authorize Stage 9B.

- [ ] **Step 1: Re-read both plans and run the complete focused suite**

Run Candidate buffer/layout/lifecycle/wiring, existing Shadow layout/lifecycle/isolation, MiMo protocol/provider, Reducer, Projector, Session, Broadcaster, fan-out and final-chunk checks. Record exact pass/fail output and installed version.

2026-07-12 partial evidence: `CandidateStreamTextBufferCheck`、`CandidateProviderMatrixCheck`、`ThreeCapsuleLayoutCheck`、`ThreeCapsuleWiringCheck`、`ShadowPreviewIsolationCheck`、`OnlineASRShadowIsolationCheck` 全部通过；`/Applications/TypeWhale Pro.app` 2.0.17 (710) 通过 deep/strict codesign。其余生命周期与核心状态机检查仍须完成，因此本 Step 保持未勾选。

2026-07-13 installation provenance review: `/Applications/TypeWhale Pro.app` 曾被主工作区旧构建 2.0.9 (683) 覆盖，故该时段的人工观察不属于 Stage 9A 验收证据。确认两个工作区均无并发构建后，直接从本 worktree 已签名产物恢复 2.0.17 (710)，未重新编译、未 bump 版本；deep/strict codesign 与启动进程通过。Build 710 历史日志包含 21 个 MiMo session、21 个正常 online summary、188 个 candidate render state event，未检出 MiMo terminal failure。注意当前 `candidate_preview_render chars` 仍记录输入 `PreviewViewState` 长度而非 buffer 实际可见长度，因此只能证明链路活跃，不能替代候选视觉节奏验收。

2026-07-13 Build 712 owner复测仍为FAIL：最长公共前缀只有1字时，从1字动画到11字仍等于从句首重播。Task 6的append-only在Build 713阻止重播，但owner再次确认旁路1/2体验一致、动画消失。Task 7因此拆分完整内容与动效进度：修订立即更新已可见区，未显示尾部继续推进。纯状态、三Provider、lifecycle和AppKit四帧已通过；`2.0.19 (714)`已完整构建、覆盖安装、启动并通过deep/strict签名，等待owner复看。Stage 9A仍未关闭。

- [ ] **Step 2: Execute installed manual matrix**

Record:

| Case | 原胶囊 | 旁路1技术节奏 | 旁路2候选节奏 | final/paste | Result |
| --- | --- | --- | --- | --- | --- |
| 20s continuous | unchanged | actual batches visible | bounded continuous tail | unchanged | PASS/FAIL |
| 2m mixed pauses | unchanged | revisions retained | no long animation lag | unchanged | PASS/FAIL |
| cancel | remains authoritative | hides | timer stops/hides | no stale paste | PASS/FAIL |
| consecutive sessions | clean | no stale state | no stale timer/text | normal | PASS/FAIL |
| experiment off | only original | absent | absent | normal | PASS/FAIL |

- [ ] **Step 3: Run final design-review**

Review installed dark/light screenshots or recording for hierarchy, role distinction, spacing, safe area, cadence, flicker, jumps, truncation and context retention. Fix any P0/P1/P2 issue with a new RED before accepting; record any unverified device-specific risk.

- [ ] **Step 4: Record architecture and readiness truth**

`ARCHITECTURE.md` must distinguish production original, technical shadow and candidate shadow. Readiness must state MiMo input is still snapshot-based and candidate animation is client presentation of returned content.

- [ ] **Step 5: Close Stage 9A only after owner acceptance**

Mark Stage 9A/Task 13A complete only when the user confirms the installed matrix. Leave Stage 9B and Task 14 explicitly unapproved.

- [ ] **Step 6: Final build/signature verification and commit**

If Task 5 includes code fixes, rebuild/install first. If documentation-only after an already verified installed build, record that no additional build was required.

```bash
git commit -m "docs: close three-capsule candidate validation"
```

**Stage 9A Exit Gate:** original production behavior is unchanged; technical shadow remains truthful; candidate shadow demonstrates bounded product presentation with no stale lifecycle or long-lag backlog; user explicitly accepts the installed result. This gate does not authorize Stage 9B.
