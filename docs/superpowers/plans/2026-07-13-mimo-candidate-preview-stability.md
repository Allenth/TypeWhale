# MiMo Candidate Preview Stability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在不改变原胶囊、旁路1和统一三模型契约的前提下，让 MiMo 适配层吸收请求级前缀重放，并把候选弹窗收敛为无厂商语义、无无效重绘的纯展示组件。

**Architecture:** 新增纯 Swift `MiMoRequestPartialProjection`，由 `MiMoSnapshotProvider` 使用 snapshot ID 和已接受基线过滤请求重放，继续输出公共 `TranscriptionEvent`。新增 `CandidateRenderState` 与 `CandidatePresentationModel`，在 View 之外维护通用显示缓冲；Presenter 对 show/move/order-front 幂等，View 只绘制 render state。

**Tech Stack:** Swift 6.2、AppKit、Swift Concurrency、AsyncStream、现有 Realtime Transcription Core、手工 Swift checks、`native/build_and_log.sh`。

## Global Constraints

- 每个 Task 前重读本计划、`2026-07-13-mimo-candidate-preview-stability-design.md`、主计划约束和 `git status --short`。
- 每次写入、构建、安装、stage 或 commit 前检查两个工作区的分支/status、构建进程和相关 mtime；重叠时立即只读。
- 原胶囊、旁路1文字节奏、旧 preview、final ASR、VAD、整理、翻译、历史、OpenClaw 和粘贴不得修改。
- MiMo 特殊语义只能存在于 `Infrastructure/RealtimeTranscription/MiMo*`；Candidate 生产代码不得引用厂商、Provider、snapshot、SSE 或 WAV。
- SenseVoice 非流式、本地流式和 MiMo 继续共享 `TranscriptionEvent → TranscriptReducer → PreviewViewState`。
- 候选弹窗只接收 `CandidateRenderState`；不得比较 Provider 文本、决定 transcript 真相或写回核心状态。
- 候选动画只显示已到达文字，尾部最多 24 Character、50ms/Character；非前缀修订干净替换。
- 所有代码任务严格 RED → GREEN；完成后更新本计划和版本叙事，构建安装并执行 design-review。
- Stage 9B 与 Task 14 保持未批准。

## Execution Progress

| Task | Status | Commit | Verification | Next action |
| --- | --- | --- | --- | --- |
| 0 / Spec and plan | COMPLETE | spec `f1874f6` / plan `ce7b903` | 分层、范围、验收与回滚已批准；placeholder/diff 自检通过 | Task 0 Gate 达成 |
| 1 / MiMo request partial projection | COMPLETE | 本任务提交 | RED 准确失败于类型缺失；纯投影、Provider 二次快照重放、MiMo Provider、Online/Shadow isolation 全部通过 | 重读计划后进入 Task 2 |
| 2 / Candidate pure render boundary | COMPLETE | 本任务提交 | model/buffer/三数据源矩阵/纯View边界/lifecycle/isolation/AppKit typecheck/三胶囊接线通过 | 重读计划后进入 Task 3 |
| 3 / Idempotent panel lifecycle and diagnostics | COMPLETE | 本任务提交 | window policy/lifecycle/接线/隔离/纯View边界/AppKit typecheck通过；诊断含真实动作 | 重读计划后进入 Task 4 |
| 4 / Full regression, build and installed acceptance | READY FOR OWNER ACCEPTANCE | `536ea14` | 完整聚焦套件、Build 711当前AppKit渲染与design-review通过；2.0.18(711)完整构建/安装/启动/签名通过 | 真实MiMo 20s/2m现场观察；Stage 9B仍未授权 |
| 5 / Real provider revisions and candidate replay | READY FOR OWNER VISUAL ACCEPTANCE | `9cb81c4` | 三条RED/GREEN、聚焦回归、design-review、2.0.18(712)构建/安装/启动/签名通过；安装日志已证明本地修订不回零且Timer不move | 真实视觉复看本地与MiMo；Stage 9B仍未授权 |
| 6 / Snapshot revision animation semantics | READY FOR OWNER VISUAL ACCEPTANCE | `e1a56e2` | 真实common-prefix-1 RED/GREEN、完整聚焦回归、AppKit design-review及2.0.18(713)构建/安装/启动/签名通过 | 本地或MiMo真实口述复看；Stage 9B仍未授权 |
| 7 / Decouple candidate content and motion | READY FOR OWNER VISUAL ACCEPTANCE | `be9a8b3` | 双RED/GREEN、完整聚焦回归、AppKit design-review及2.0.19(714)完整构建/安装/启动/签名通过 | 本地或MiMo真实口述复看；Stage 9B仍未授权 |

## File Map

- Create `native/Sources/Infrastructure/RealtimeTranscription/MiMoRequestPartialProjection.swift`: 纯请求级重放/修订投影。
- Modify `native/Sources/Infrastructure/RealtimeTranscription/MiMoSnapshotProvider.swift`: 在 Provider 内使用投影，不把 snapshot 语义泄漏到公共核心。
- Create `native/Tests/MiMoRequestPartialProjectionCheck.swift`: 请求重放、扩展、修订、跨请求测试。
- Create `native/Sources/Presentation/CandidatePreview/CandidateRenderState.swift`: View 唯一输入值。
- Create `native/Sources/Presentation/CandidatePreview/CandidatePresentationModel.swift`: 通用候选显示状态机，拥有 `CandidateStreamTextBuffer`。
- Modify `native/Sources/Presentation/CandidatePreview/CandidateStreamTextBuffer.swift`: 删除 snapshot 猜测，只保留通用展示语义。
- Modify `native/Sources/Presentation/CandidatePreview/CandidatePreviewCoordinator.swift`: 订阅统一 ViewState，驱动 model 和动画 tick，向 Presenter 发送 render state。
- Modify `native/Sources/Presentation/CandidatePreview/CandidatePreviewPresenter.swift`: 幂等 show/move/hide；View 只接收 render state。
- Modify `native/Sources/Presentation/CandidatePreview/CandidatePreviewView.swift`: 删除 buffer、Timer 和 PreviewViewState，只绘制 `CandidateRenderState`。
- Modify `native/Sources/Application/SpeechInputCoordinator.swift`: 诊断记录 target/displayed 和窗口动作，不改变业务路径。
- Update `native/build_native_app.sh` 与相邻 checks 的显式文件清单。

---

### Task 0: Commit The Approved Execution Source Of Truth

**Files:**
- Existing: `docs/superpowers/specs/2026-07-13-mimo-candidate-preview-stability-design.md`
- Create: `docs/superpowers/plans/2026-07-13-mimo-candidate-preview-stability.md`
- Modify: `docs/superpowers/plans/2026-07-12-three-capsule-candidate-preview.md`

**Interfaces:**
- Consumes: approved product/layering decision.
- Produces: exact execution order and Stage 9A gates.

- [x] **Step 1: Self-review spec coverage and placeholders**

Run:

```bash
rg -n 'TBD|TODO|implement later|类似 Task|适当处理' \
  docs/superpowers/specs/2026-07-13-mimo-candidate-preview-stability-design.md \
  docs/superpowers/plans/2026-07-13-mimo-candidate-preview-stability.md
git diff --check
```

Expected: no placeholder output; diff check passes.

- [x] **Step 2: Commit plan documents only**

```bash
git add docs/superpowers/plans/2026-07-13-mimo-candidate-preview-stability.md \
  docs/superpowers/plans/2026-07-12-three-capsule-candidate-preview.md
git commit -m "docs: plan mimo candidate stability fix"
```

Expected: documentation-only commit; installed app unchanged.

---

### Task 1: Normalize MiMo Request-Level Partial Replay

**Files:**
- Create: `native/Sources/Infrastructure/RealtimeTranscription/MiMoRequestPartialProjection.swift`
- Modify: `native/Sources/Infrastructure/RealtimeTranscription/MiMoSnapshotProvider.swift`
- Create: `native/Tests/MiMoRequestPartialProjectionCheck.swift`
- Modify: `native/Tests/MiMoSnapshotProviderCheck.swift`
- Modify: `native/build_native_app.sh`

**Interfaces:**
- Consumes: `snapshotID: String`, `baselineText: String`, request-accumulated `incomingText: String`.
- Produces:

```swift
enum MiMoRequestPartialUpdate: Equatable {
    case suppressedReplay
    case emit(String)
}

struct MiMoRequestPartialProjection {
    mutating func begin(snapshotID: String, baselineText: String)
    mutating func accept(snapshotID: String, incomingText: String) -> MiMoRequestPartialUpdate
    mutating func end(snapshotID: String)
    mutating func reset()
}
```

- [x] **Step 1: Write RED projection check**

The check must assert:

```swift
projection.begin(snapshotID: "s2", baselineText: "在线模型")
precondition(projection.accept(snapshotID: "s2", incomingText: "在") == .suppressedReplay)
precondition(projection.accept(snapshotID: "s2", incomingText: "在线模型") == .suppressedReplay)
precondition(projection.accept(snapshotID: "s2", incomingText: "在线模型支持") == .emit("在线模型支持"))

projection.begin(snapshotID: "s3", baselineText: "今天讨论模型")
precondition(projection.accept(snapshotID: "s3", incomingText: "今天改") == .emit("今天改"))
```

Also assert duplicate incoming text is suppressed and `reset()` isolates a new session.

- [x] **Step 2: Run RED**

```bash
swiftc -parse-as-library -o /tmp/typewhale-mimo-partial-projection-check \
  native/Tests/MiMoRequestPartialProjectionCheck.swift
```

Expected: compile failure because `MiMoRequestPartialProjection` does not exist.

- [x] **Step 3: Implement the pure projection and wire Provider**

Rules:

```swift
// Replay: the accepted baseline starts with this request prefix.
if baselineText.hasPrefix(incomingText) { return .suppressedReplay }
// Duplicate request output must not produce another event.
if incomingText == lastEmittedText { return .suppressedReplay }
return .emit(incomingText)
```

`launch(_:)` begins projection using current `projectedText`; `observedPartial` calls `accept` and only `.emit` reaches `unconfirmedTail`/`.partial`; request completion and all terminal paths end/reset projection. No Candidate type may be imported.

- [x] **Step 4: Run GREEN and Provider regression**

Compile/run the new pure check, `MiMoASRProtocolCheck` and `MiMoSnapshotProviderCheck`. Extend Provider check so a second snapshot replay does not emit shorter volatile partials before its real extension.

Expected: all print `passed`; existing request count, pending bound, temporary-file cleanup, cancel and completion invariants stay green.

Actual: `MiMoRequestPartialProjectionCheck`、`MiMoSnapshotProviderCheck`、`OnlineASRShadowIsolationCheck`、`ShadowPreviewIsolationCheck` passed。Provider 集成 fixture 的第二次请求按 `在`、`线模型`、`支持` 发送 SSE delta，事件流不再出现短 partial `在`，仍出现真实扩展 `在线模型支持`。`native/build_native_app.sh` 使用 `find native/Sources -name '*.swift'` 自动收集源文件，无需修改清单。

- [x] **Step 5: Commit Task 1**

```bash
git add native/Sources/Infrastructure/RealtimeTranscription/MiMoRequestPartialProjection.swift \
  native/Sources/Infrastructure/RealtimeTranscription/MiMoSnapshotProvider.swift \
  native/Tests/MiMoRequestPartialProjectionCheck.swift \
  native/Tests/MiMoSnapshotProviderCheck.swift native/build_native_app.sh
git commit -m "fix: normalize mimo snapshot partial replay"
```

---

### Task 2: Make Candidate Window A Pure Render Consumer

**Files:**
- Create: `native/Sources/Presentation/CandidatePreview/CandidateRenderState.swift`
- Create: `native/Sources/Presentation/CandidatePreview/CandidatePresentationModel.swift`
- Modify: `native/Sources/Presentation/CandidatePreview/CandidateStreamTextBuffer.swift`
- Modify: `native/Sources/Presentation/CandidatePreview/CandidatePreviewView.swift`
- Modify: `native/Sources/Presentation/CandidatePreview/CandidatePreviewPresenter.swift`
- Modify: `native/Sources/Presentation/CandidatePreview/CandidatePreviewCoordinator.swift`
- Create: `native/Tests/CandidatePresentationModelCheck.swift`
- Modify: `native/Tests/CandidateProviderMatrixCheck.swift`
- Modify: `native/Tests/CandidateStreamTextBufferCheck.swift`
- Modify: `native/build_native_app.sh`

**Interfaces:**
- Consumes: provider-neutral `PreviewViewState` in model/controller only.
- Produces:

```swift
struct CandidateRenderState: Equatable, Sendable {
    let displayedText: String
    let targetText: String
    let stableCharacterCount: Int
    let status: CandidateRenderStatus
}

enum CandidatePresentationUpdate: Equatable {
    case unchanged
    case render(CandidateRenderState, needsTimer: Bool)
    case clear
}

struct CandidatePresentationModel {
    mutating func apply(_ state: PreviewViewState) -> CandidatePresentationUpdate
    mutating func advance() -> CandidatePresentationUpdate
    mutating func reset()
}
```

- [x] **Step 1: Write RED model and boundary checks**

Assert all three sequences use the same API:

```swift
localSnapshot = ["今天讨论", "今天讨论模型", "今天改为验证模型"]
localStreaming = ["今", "今天", "今天讨论", "今天讨论在线模型"]
mimoNormalized = ["在线模型", "在线模型支持", "在线模型支持流式输出"]
```

Assert duplicate state returns `.unchanged`, timer advances only already-returned text, non-prefix revision is clean, terminal clears, and no Candidate production source contains `MiMo|SenseVoice|snapshot|SSE|WAV|TranscriptionProvider`.

- [x] **Step 2: Run RED**

Expected: compile failure because render model types do not exist, plus boundary check failure because View still owns `PreviewViewState`, buffer and Timer.

- [x] **Step 3: Implement model and pure View**

Move buffer ownership and stable-count projection out of `CandidatePreviewView`. Remove snapshot replay suppression from `CandidateStreamTextBuffer`; normalized MiMo inputs are monotonic or real revisions. `CandidatePreviewView` exposes only:

```swift
func apply(_ renderState: CandidateRenderState)
func resetPresentation()
```

It stores one render state, draws it and has no Timer, `PreviewViewState`, Provider or text comparison.

- [x] **Step 4: Run GREEN and three-provider matrix**

Run model, buffer, provider matrix, Candidate lifecycle, Shadow lifecycle and isolation checks. Typecheck all Candidate AppKit sources.

Expected: all pass; source boundary scan has no output.

Actual: `CandidatePresentationModelCheck`、`CandidateStreamTextBufferCheck`、`CandidateProviderMatrixCheck`、`CandidatePreviewRenderBoundaryCheck`、`CandidatePreviewLifecycleCheck`、`ShadowPreviewIsolationCheck`、`OnlineASRShadowIsolationCheck`、`ThreeCapsuleWiringCheck` passed；Candidate/Shadow 联合 AppKit typecheck 通过。`CandidatePreviewView` 只持有 `CandidateRenderState`，buffer/Timer/ViewState 已移到 model/coordinator；Candidate 生产源码的厂商/Provider 边界扫描无输出。

- [x] **Step 5: Commit Task 2**

```bash
git add native/Sources/Presentation/CandidatePreview native/Tests/CandidatePresentationModelCheck.swift \
  native/Tests/CandidateProviderMatrixCheck.swift native/Tests/CandidateStreamTextBufferCheck.swift \
  native/build_native_app.sh
git commit -m "refactor: isolate candidate render state"
```

---

### Task 3: Make Candidate Window Updates Idempotent

**Files:**
- Modify: `native/Sources/Presentation/CandidatePreview/CandidatePreviewCoordinator.swift`
- Modify: `native/Sources/Presentation/CandidatePreview/CandidatePreviewPresenter.swift`
- Modify: `native/Sources/Application/SpeechInputCoordinator.swift`
- Create: `native/Tests/CandidateWindowUpdatePolicyCheck.swift`
- Modify: `native/Tests/CandidatePreviewLifecycleCheck.swift`

**Interfaces:**
- Consumes: `CandidatePresentationUpdate` and production frame.
- Produces:

```swift
enum CandidateWindowAction: Equatable {
    case none
    case show(frame: CGRect)
    case move(frame: CGRect)
    case hide
}

struct CandidateWindowUpdatePolicy {
    mutating func present(frame: CGRect, hasRenderableContent: Bool) -> CandidateWindowAction
    mutating func hide() -> CandidateWindowAction
}
```

- [x] **Step 1: Write RED policy/lifecycle check**

Assert first render returns `.show`, 100 identical updates return `.none`, a changed frame returns one `.move`, hide is idempotent, and a new session can show once again. Lifecycle fake Presenter must record render/show/move/hide counts.

- [x] **Step 2: Run RED**

Expected: type missing and current lifecycle records repeated `show` calls.

- [x] **Step 3: Implement idempotent coordinator/presenter path**

Coordinator owns the animation Timer and calls model `advance()`. It invokes Presenter only on `.render` or `.clear`. Presenter applies `CandidateWindowUpdatePolicy`; `orderFrontRegardless()` occurs only for `.show`, `setFrame` only for `.show/.move`, and `.none` performs no AppKit mutation.

Diagnostics must report provider-neutral values:

```text
candidate_render sequence=<n> target_chars=<n> displayed_chars=<n> action=none|show|move|hide
```

- [x] **Step 4: Run GREEN and lifecycle/isolation regressions**

Run window policy, Candidate lifecycle, ThreeCapsule wiring, Shadow isolation, Online isolation and AppKit typecheck.

Expected: identical states produce no render/window action; cancellation and consecutive sessions cleanly reset.

Actual: `CandidateWindowUpdatePolicyCheck` 证明首次 `.show`、100 次相同 frame `.none`、一次 frame 变化 `.move`、hide/new session 幂等；`CandidatePreviewLifecycleCheck`、`ThreeCapsuleWiringCheck`、`ShadowPreviewIsolationCheck`、`OnlineASRShadowIsolationCheck`、`CandidatePreviewRenderBoundaryCheck` 与 Candidate/Shadow AppKit typecheck 全部通过。诊断已改为 `target_chars/displayed_chars/action/draw_ms`，hide 也有独立动作证据。

- [x] **Step 5: Commit Task 3**

```bash
git add native/Sources/Presentation/CandidatePreview/CandidatePreviewCoordinator.swift \
  native/Sources/Presentation/CandidatePreview/CandidatePreviewPresenter.swift \
  native/Sources/Application/SpeechInputCoordinator.swift \
  native/Tests/CandidateWindowUpdatePolicyCheck.swift native/Tests/CandidatePreviewLifecycleCheck.swift
git commit -m "fix: eliminate candidate window flicker"
```

---

### Task 4: Verify, Build, Install And Close The Fix

**Files:**
- Modify: `docs/ARCHITECTURE.md`
- Modify: `docs/SHADOW_PREVIEW_QA.md`
- Modify: `docs/ONLINE_STREAMING_PROVIDER_READINESS.md`
- Modify: `docs/开发日志.md`
- Modify: `docs/构建日志.md`
- Modify: `README.md`, `macos/README.md`, version history/build files as required.
- Modify: both active Stage 9A plans.

**Interfaces:**
- Consumes: Tasks 1–3.
- Produces: signed installed build and Stage 9A acceptance evidence; no Stage 9B authorization.

- [x] **Step 1: Run the complete focused suite**

Run MiMo protocol/projection/provider, Candidate buffer/model/provider matrix/window/lifecycle, Reducer, Projector, Session, Broadcaster, audio fan-out, final-chunk, layouts, wiring and both isolation checks.

Expected: every executable prints `passed`; shell boundaries pass; no Candidate vendor dependency.

Actual: MiMo protocol/projection/provider，Candidate buffer/model/provider matrix/window/lifecycle，Reducer、Projector、Session、Broadcaster、AudioFrameFanOut、ChunkCommitState、PreviewFinalChunkWriteFailure、ThreeCapsule/Shadow layout、wiring、Candidate render boundary、Shadow/Online isolation、AudioRecorder fan-out source及两分钟final边界均通过。首次final-chunk命令误传`SpeechInputCoordinator.swift`，定位后使用真实所有者`AudioRecorder.swift`通过；不是产品失败。

- [x] **Step 2: Update plan and version narrative before build**

Record exact automated evidence, root cause, architecture boundary and installed test matrix. Keep Stage 9B/Task 14 unapproved.

- [x] **Step 3: Build/install through the only entry point**

After concurrency protection:

```bash
./native/build_and_log.sh
codesign --verify --deep --strict --verbose=2 '/Applications/TypeWhale Pro.app'
open -a '/Applications/TypeWhale Pro.app'
```

Expected: version/build rules pass; app is copied, signed and running. If the three-build counter triggers a full version, commit the release after verifying scope as required by AGENTS.md.

Actual: `./native/build_and_log.sh` 自动按累计 #36 执行完整版本构建并升级至2.0.18(711)；覆盖安装、LaunchProbe/main/lifecycle启动链、进程与deep/strict codesign全部通过。

- [ ] **Step 4: Run installed matrix and design-review**

Verify MiMo 20s and 2m mixed pauses, local SenseVoice, deterministic local streaming fixture, cancel, consecutive sessions and experiment off. Inspect dark/light installed screenshots or recording for flicker, repeated fronting, text/style jumps, hierarchy, spacing and truncation. Any P0/P1/P2 finding returns to a new RED before acceptance.

Actual（自动与组件级部分）：Build 711等待/增长/完成三态使用当前`CandidatePreviewView`真实AppKit渲染复核；既有三胶囊视觉基线未被修改；`CandidateWindowUpdatePolicyCheck`证明同frame不重复置前/移动，`CandidatePresentationModelCheck`证明相同目标不重复render，独立design-review为A-且无P0/P1/P2。报告：`~/.gstack/projects/Allenth-TypeWhale/designs/design-audit-20260713-build-711/design-audit-build-711.md`。真实MiMo 20s/2m仍保留为owner现场观察，不能由无麦克风fixture冒充。

- [x] **Step 5: Update final documentation and commit**

Record what was automatically proven and what required owner observation. Do not mark Stage 9A complete without owner acceptance, but deliver the installed fix and exact remaining observation in one handoff.

Actual：架构边界、Provider readiness、QA、开发日志、版本历史、主计划和本计划已同步；完整版本提交为`536ea14`，本次进度状态在后续文档提交中固化。Stage 9A保持`READY FOR OWNER ACCEPTANCE`，未进入Stage 9B。

```bash
git add <only files owned by this plan>
git commit -m "docs: record candidate stability verification"
```

**Exit Gate:** MiMo request replay is normalized before the common core; Candidate View is a pure render consumer; all three model classes share the same presentation API; repeated identical states cause no redraw or window mutation; installed MiMo no longer flickers; original production path remains unchanged.

---

### Task 5: Suppress Real MiMo Cross-Snapshot Rollback Replay

**Observed failure:** Build 711真实会话`13B069B4`中，候选目标在同一会话由11字增长至22字，随后下一快照回退到11字；`CandidatePresentationModel`按公共契约把非前缀缩短视为修订，清空后重新逐字展示。请求级投影只比较当前请求基线与请求内累计文本，因此未阻止完成快照回退覆盖`projectedText`。

**Scope:** MiMo快照回退只在`Infrastructure/RealtimeTranscription/MiMo*`处理；通用候选修订只在`CandidateStreamTextBuffer/Coordinator`处理视觉过渡与窗口节奏。Candidate不得判断Provider真相；原胶囊、本地Provider、Reducer、final/paste不改。

- [x] **Step 1: Write RED from the real `11→22→11` shape**

Provider集成测试必须连续完成三个快照：已接受11字、扩展到22字、下一完整快照回退到11字。断言第三快照不得向公共事件流发出短目标，也不得把Provider的`projectedText`回退；随后真实扩展到更长文本仍必须发出。

Actual：纯投影检查准确失败于严格缩短仍被`.emit`；Provider集成检查准确失败于公共partial包含11字rollback。GREEN后两项均通过，第四快照更长扩展仍发出。

- [x] **Step 2: Write generic Candidate transition RED from local logs**

本地`legacy_adapter`连续快照即使目标长度增长，也可能发生非前缀修订。断言Candidate保留新旧文字的最长公共前缀，只动画真实变化后缀；完全无公共前缀时立即替换，不允许从空串重新播放整句。动画Timer tick只更新RenderState，不得重复查询production frame或触发show/move。

Actual：Build 711日志会话`28CCBA9F`复现`target_chars 3→6、6→6、10→10`时每次`displayed_chars→0`；用户视频`$HOME/Downloads/截图/iShot_2026-07-13_16.25.08.mp4`清楚显示候选完整显示后退回“对，现在”重新播放。Buffer与Lifecycle RED分别失败于公共前缀未保留、Timer重复读取frame。

- [x] **Step 3: Implement provider and presentation fixes at their own layers**

请求内SSE仍由`MiMoRequestPartialProjection`过滤。完成结果进入reconciler前，MiMo适配层必须拒绝相对当前已投影全文的严格缩短/旧快照重放；不得在Candidate层加MiMo判断。非缩短的真实扩展继续接受；不确定的整句非前缀改写只在完成快照层处理并保留诊断，不用动画伪装。

Candidate buffer只计算通用视觉diff：扩展沿用现有前缀；修订保留最长公共前缀并动画变化后缀；无公共前缀立即显示新目标。Coordinator仅在新源状态到达时更新窗口位置，50ms动画tick只重绘文字。

Actual：MiMo请求partial与完成快照均拒绝相对已投影全文的严格缩短；Candidate保留最长公共前缀、无公共前缀即时替换；Timer tick返回`action=none`且不读取production frame。Candidate仍无Provider类型或厂商语义。

- [x] **Step 4: Run MiMo and three-provider regressions**

运行纯投影、MiMo协议、MiMo Provider、Candidate三Provider矩阵、Reducer/Projector、Candidate边界及Shadow/Online isolation。确认本地快照真实修订能力不受影响。

Actual：MiMo纯投影/协议/Provider，Candidate buffer/model/三Provider矩阵/window/lifecycle，TranscriptReducer、PreviewStateProjector、Candidate纯View边界、三胶囊接线、Shadow/Online isolation及Candidate/Shadow AppKit typecheck全部通过。首次Projector命令漏传Reducer源文件，补齐后通过，不是产品失败。

- [x] **Step 5: Update docs, build/install and verify**

更新本计划、架构、QA、开发日志和版本历史；通过唯一入口构建安装。验证安装版版本、签名、运行进程和启动链。Stage 9B保持未批准。

Actual：功能提交`9cb81c4`；design-review对照用户视频与Build 712 AppKit fixture，结论`DONE_WITH_CONCERNS`，整句重播与逐字move均已关闭，真实MiMo视觉仍待现场观察。`./native/build_and_log.sh`完成build-only `2.0.18 (712)`、覆盖安装、打开和deep/strict签名。安装版本地`legacy_adapter`日志显示sequence 2由3字更新至6字时直接`displayed_chars=6`，sequence 3目标10字时从公共前缀`displayed_chars=5`继续，全部Timer tick为`action=none`。

---

### Task 6: Animate Append Only, Never Replay Snapshot Revisions

**Observed failure:** owner复测Build 712仍判定“从头来”。真实本地会话`C96528BF`中，sequence 4已完成9字，sequence 5的新11字只保留1字并从`displayed_chars=1→11`重播；sequence 6同为11字修订再次从1字重播。最长公共前缀策略虽不回零，但仍把快照修订的大部分旧句当成新尾部动画，产品体验没有解决。

**Architecture correction:** 候选动画只服务严格追加：`incoming.hasPrefix(previousTarget)`时动画新增尾部。任何非前缀修订都是新的识别快照，必须立即替换为完整目标，不论公共前缀长度；Candidate只判断通用展示关系，不识别Provider。真流式append仍逐字，本地/MiMo修订不重播。

- [x] **Step 1: Write RED from the real 9→11 / common-prefix-1 shape**

完成旧目标后输入一个仅共享1字的新目标，断言更新为`needsTimer=false`且`displayedText==targetText==incoming`。再输入同长度非前缀修订，仍立即替换。现有最长公共前缀实现必须准确失败。

Actual：`CandidateStreamTextBufferCheck`准确失败于common-prefix-1修订仍返回Timer动画；同一测试同时覆盖下一次同长度非前缀修订。

- [x] **Step 2: Implement append-only animation**

保留首次目标动画和严格前缀追加动画。删除非前缀修订的公共前缀动画路径；修订直接设置完整displayed/target并停止Timer。View、Provider、Reducer、窗口策略不改。

Actual：非前缀分支现在原子设置`targetText/displayedText=incoming`并返回`needsTimer=false`；严格追加分支与首次目标动画保持不变。buffer/model/三Provider矩阵/lifecycle、Candidate纯View边界及Shadow/Online isolation通过。

- [x] **Step 3: Regress three data classes and install Build 713**

运行buffer/model/三Provider矩阵/lifecycle/边界/隔离与MiMo回归；更新架构、QA、开发日志、版本历史和计划；通过唯一入口构建安装并用真实日志确认任何非前缀修订首帧`displayed_chars==target_chars`。

Actual：`CandidateStreamTextBufferCheck`、`CandidatePresentationModelCheck`、`CandidateProviderMatrixCheck`、`CandidateWindowUpdatePolicyCheck`、`CandidatePreviewLifecycleCheck`、MiMo projection/protocol/provider、Candidate纯View边界、三胶囊接线及Shadow/Online isolation全部通过。当前真实AppKit组件fixture覆盖稳定、严格追加、非前缀修订和同长度修订四帧；design-review结论`DONE_WITH_CONCERNS`，组件级无句首中间帧。`./native/build_and_log.sh`完成build-only `2.0.18 (713)`、覆盖安装、打开、版本核对和deep/strict签名，累计#38；真实录音视觉仍需owner观察，Stage 9B未授权。

---

### Task 7: Decouple Candidate Content From Motion

**Owner feedback:** Build 713中旁路1与候选体验一致，动画没有了。真实安装日志会话`F4E80286`证明：sequence 1首次6字正常动画；后续`6→13、13→16、22→24、24→27、27→32`等增长多数同时带非前缀修订，因此Build 713全部首帧完整替换。只有严格前缀的`16→22、59→64、65→69`仍有Timer。候选虽不再重播，但失去未来产品体验目标。

**Root cause:** `CandidateStreamTextBuffer`同时拥有最新文字`targetText`和动画进度`displayedText`，一次`apply`分支既决定接受什么内容，也决定是否启动Timer。Build 712的公共前缀策略因此导致重播；Build 713把修订分支改为完整替换时，同一分支又返回`needsTimer=false`，导致大多数带修订的增长快照失去动画。View虽然纯净，但Presentation内部的内容状态和动效状态仍然耦合。

**Architecture decision — Accepted:** 删除组合式`CandidateStreamTextBuffer`职责，拆成两个纯状态所有者：

- `CandidateContentProjection`：消费`PreviewViewState`，只拥有session/provider epoch/sequence/lifecycle门禁和完整最新`CandidateContent`；不包含Timer、可见字符数或动画结果。
- `CandidateTextMotion`：只消费`contentCharacterCount`，拥有`visibleCharacterCount/targetCharacterCount`和24字欠账上限；不读取字符串、不识别修订、不认识Provider。
- `CandidatePresentationModel`：先原子接受完整内容，再把字符总数交给Motion，组合出`CandidateRenderState(contentText, visibleCharacterCount, stableCharacterCount)`。
- `CandidatePreviewView`：继续只绘制RenderState；Timer继续只推进Motion，不修改ContentProjection。

**Rejected alternatives:** 保持现有buffer只调整分支，会继续让内容变更开关动画；在同一buffer内按旧目标长度截取再动画，只是把公共前缀耦合换成长度耦合，不能防止下一次策略修改再次影响数据展示。

**Observable acceptance:** 对9字旧目标到11字、仅1字公共前缀的新目标，ContentProjection必须立即拥有完整11字；Motion保持9字可见进度，只推进第10至11字；RenderState首帧显示新内容前9字，不含旧字。对已完整显示的同长度或缩短修订不重启动画。严格追加和首次目标保持现有动画；任何路径不得出现1→11句首重播。

- [x] **Step 1: Write independent content and motion REDs**

新增`CandidateContentProjectionCheck`，证明完整修订被立即接受且无动画API；新增`CandidateTextMotionCheck`，证明它只按字符数保持进度、推进和有界欠账；扩展Model测试覆盖9→11/common-prefix-1。新类型缺失与旧Model整段即时替换必须分别准确失败。

Actual：ContentProjection与TextMotion两个检查分别准确失败于类型缺失；Model 9→11 fixture在Build 713整段即时替换实现上准确触发precondition。三条RED均对应目标边界，不是编译清单或fixture拼写错误。

- [x] **Step 2: Implement separated state owners**

实现两个纯类型并让Model组合；RenderState携带完整内容和独立可见字符数，以计算属性提供现有`targetText/displayedText`兼容读口。删除旧buffer及其测试，Provider矩阵迁移到Model公共契约。View、Coordinator和诊断接口不增加数据判断。

Actual：新增`CandidateContentProjection`和`CandidateTextMotion`；`CandidateRenderState`改为完整`contentText + visibleCharacterCount`，兼容计算现有target/displayed读口；Model只负责组合，Timer advance只改变Motion。旧`CandidateStreamTextBuffer`及其测试删除，三Provider矩阵迁移到Model契约。两个纯检查、Model、三Provider矩阵、lifecycle、Candidate纯View边界、三胶囊接线及Shadow/Online isolation全部通过。

- [x] **Step 3: Regress, design-review, build and install**

运行三Provider、model/buffer/lifecycle/window、MiMo和隔离回归；用真实AppKit组件验证“修订区完整 + 新尾部推进”且无句首中间帧；更新架构、QA、日志和版本历史，通过唯一入口构建安装。

Actual：ContentProjection、TextMotion、Model、三Provider矩阵、window/lifecycle、MiMo projection/protocol/provider、Candidate纯View边界、三胶囊接线及Shadow/Online isolation通过。真实AppKit组件9→11 fixture四帧分别为旧9字完整、新修订首帧9字、第10字、第11字；无旧字、空帧或句首重播。design-review结论`DONE_WITH_CONCERNS`。`./native/build_and_log.sh`按累计#39完成完整版本`2.0.19 (714)`、覆盖安装、打开、版本核对和deep/strict签名；真实口述仍需owner观察，Stage 9B未授权。
