# Pause Auto-Finish Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make pause auto-finish session-safe, independently configurable, observable, and resistant to natural pauses and late starts.

**Architecture:** Move timing decisions into a pure `RecordingAutoFinishPolicy`. Feed it task-scoped Silero VAD probe results; only a current-task `no_speech` result may trigger a decision. Keep AppKit/audio side effects in `SpeechInputCoordinator`.

**Tech Stack:** Swift 5, AppKit, AVFoundation, shell source-boundary checks, local release scripts.

## Global Constraints

- Long-hold recording never auto-finishes.
- Initial silence cancellation requires a post-8-second `no_speech` probe and no meaningful preview evidence.
- VAD failure disables auto-finish for the current recording without making the next recording cold.
- Realtime preview and pause auto-finish remain independently configurable.
- All edits preserve unrelated dirty-worktree changes.
- Code changes require local build, overwrite-install to `/Applications/TypeWhale Pro.app`, launch, signature verification, and installed-app checks.

---

### Task 1: Pure auto-finish policy

**Files:**
- Create: `native/Sources/Domain/RecordingAutoFinishPolicy.swift`
- Create: `native/Tests/RecordingAutoFinishPolicyCheck.swift`

**Interfaces:**
- Produces: `RecordingAutoFinishPolicy`, `RecordingAutoFinishDecision`, `reset(startedAt:)`, and `evaluateProbe(...)`.

- [ ] **Step 1: Write the failing policy check**

Create a standalone Swift check that asserts disabled and hold recording never finish, short pauses continue, a qualifying pause finishes once, 3/7.9-second initial silence continues, 8-second initial silence cancels, meaningful preview prevents cancellation, and `reset` starts a clean session.

- [ ] **Step 2: Run RED**

Run:

```bash
swiftc native/Sources/Domain/RecordingAutoFinishPolicy.swift native/Tests/RecordingAutoFinishPolicyCheck.swift -o /tmp/typewhale-auto-finish-check
```

Expected: fail because the production policy file/types do not exist.

- [ ] **Step 3: Implement the minimal pure policy**

Use these public-internal interfaces:

```swift
enum RecordingAutoFinishDecision: Equatable {
    case continueRecording
    case finishAfterPause(silenceDuration: TimeInterval)
    case cancelInitialSilence(elapsed: TimeInterval)
}

struct RecordingAutoFinishPolicy {
    let pauseSeconds: TimeInterval
    let initialSilenceSeconds: TimeInterval
    mutating func reset(startedAt: Date)
    mutating func evaluateProbe(
        hasSpeech: Bool,
        capturedAt: Date,
        autoFinishEnabled: Bool,
        isHoldActivation: Bool,
        hasMeaningfulPreview: Bool
    ) -> RecordingAutoFinishDecision
}
```

The policy records speech even while auto-finish is disabled/hold so a mid-recording setting change cannot reinterpret prior speech as an empty start. Only decision emission is gated.

- [ ] **Step 4: Run GREEN**

Compile and run the standalone check; expect `RecordingAutoFinishPolicyCheck passed`.

### Task 2: Task-scoped VAD integration and diagnostics

**Files:**
- Modify: `native/Sources/Infrastructure/Audio/AudioRecorder.swift`
- Modify: `native/Sources/Application/SpeechInputCoordinator.swift`
- Modify: `native/Tests/SpeechInputCoordinatorBoundaryCheck.sh`

**Interfaces:**
- Consumes: policy from Task 1.
- Produces: `AudioRecorder.onVoiceProbe: ((UUID, [Float], Int) -> Void)?` and task-guarded coordinator decisions.

- [ ] **Step 1: Extend the source-boundary check first**

Require the recorder callback to emit `taskID`, the coordinator callback to guard `activeSession?.id == taskID`, stale callbacks to log `vad_probe_ignored reason=stale_task`, and auto decisions to log `reason=pause`/`reason=initial_silence`.

- [ ] **Step 2: Run RED**

Run `bash native/Tests/SpeechInputCoordinatorBoundaryCheck.sh`; expect failure on the first new requirement.

- [ ] **Step 3: Integrate the policy**

- Change `onVoiceProbe` to include the recorder task ID.
- Reset policy after recorder start succeeds.
- Pass task ID through `receiveVoiceProbe` and native VAD completion.
- Before mutating any VAD state, reject callbacks whose task ID is no longer active.
- Evaluate decisions only from successful probe callbacks; remove per-buffer pause evaluation.
- On `.finishAfterPause`, log reason/timing/preview evidence and call `finishRecording()`.
- On `.cancelInitialSilence`, cancel the recorder, clear workflow/session/target state, show “无输入已停止”, and do not submit final recognition.
- On VAD failure, log the concrete error and keep manual/hard-limit paths.

- [ ] **Step 4: Run GREEN and adjacent checks**

Run the boundary check, policy check, and `FinalSpeechGateCheck` with `RecognitionTextFilter.swift`; expect all pass.

### Task 3: Independent settings

**Files:**
- Modify: `native/Sources/Presentation/Main/MainViewController+Actions.swift`
- Create: `native/Tests/PauseAutoFinishSettingsBoundaryCheck.sh`

**Interfaces:**
- Produces: independent persistence of `realtimePreviewEnabled` and `autoFinishAfterPauseEnabled`.

- [ ] **Step 1: Write a failing source-boundary check**

Extract `saveSettings()` and fail if it assigns `realtime.state = .on` when auto-finish is enabled or assigns `autoFinish.state = .off` when realtime preview is disabled.

- [ ] **Step 2: Run RED**

Run `bash native/Tests/PauseAutoFinishSettingsBoundaryCheck.sh`; expect failure against the historical coupling.

- [ ] **Step 3: Remove only the obsolete coupling block**

Preserve all unrelated theme-debug changes already present in the file.

- [ ] **Step 4: Run GREEN**

Run the new boundary check and existing coordinator boundary check; expect both pass.

### Task 4: Product and architecture records

**Files:**
- Modify: `README.md`
- Modify: `docs/VAD_AND_WAVEFORM_DESIGN.md`
- Modify: `docs/ARCHITECTURE.md`
- Modify: `docs/开发日志.md`
- Modify: `native/Sources/Presentation/VersionHistory/VersionHistoryViewController.swift`

**Interfaces:**
- Documents the exact shipped behavior and next build/version entry.

- [ ] **Step 1: Update active product documentation**

Document independent preview configuration, 8-second empty-start protection, task-scoped callbacks, no-speech-only decisions, and diagnostic reasons. Clearly mark the old energy-VAD tuning table as historical so it cannot be mistaken for active configuration.

- [ ] **Step 2: Add the required version-history and development-log entry**

Read current version/build and build-state count immediately before editing. Add the exact next build entry expected by `release_local_build.sh`, without rewriting concurrent entries.

- [ ] **Step 3: Run documentation consistency checks**

Use `rg` to confirm active docs no longer say auto-finish requires realtime preview or that initial silence is 3 seconds.

### Task 5: Verification, independent review, and installed app

**Files:**
- Test: all files above plus repository-native checks.
- Generated by build: version/build references and `docs/构建日志.md`.

**Interfaces:**
- Produces verified source, signed installed app, and a focused release commit if the build is a full-version build.

- [ ] **Step 1: Run the complete focused verification set**

Run policy, coordinator, settings, final speech gate, `git diff --check`, and the project’s native build/check entry points applicable to this change.

- [ ] **Step 2: Run independent interaction/code review**

Have a reviewer inspect timing semantics, stale callback isolation, long-hold behavior, failure fallback, cancellation feedback, and preservation of unrelated dirty changes. Resolve Critical/Important findings and re-run covering tests.

- [ ] **Step 3: Check build concurrency and build state**

Run `git branch --show-current`, `git status --short`, build-process checks, and source mtimes. Reconcile any concurrent version bump before invoking the build.

- [ ] **Step 4: Build, overwrite-install, launch, and verify**

Run `./native/build_and_log.sh`. Confirm installed version/build, `codesign --verify --deep --strict`, running process, and fresh diagnostics from `/Applications/TypeWhale Pro.app`.

- [ ] **Step 5: Review commit scope**

If the build is a full-version build, stage only this feature’s code, tests, docs, version hunks, and generated build record. Do not stage unrelated UI/theme/OpenClaw work. Commit the release only after `git status --short` and staged diff review.

### Task 6: Restore natural-pause tolerance from real product feedback

**Status:** SOURCE COMPLETE / REAL APP ACCEPTANCE PENDING

**Goal:** 用户思考中的约 2 秒自然停顿不能提前结束录音，同时继续保留停顿自动完成能力。

**Scope:** 只调整 `SpeechInputCoordinator.Timing.autoFinishPauseSeconds`；保留 task ID 隔离、两次无人声确认、重开口撤销、长按录音豁免和 VAD 失败降级。

**Decision:** 2026-07-21 代码与日志复核确认，2026-07-10 的 `60312541` 曾把内部基线从 1.5 秒缩短到 1.0 秒；当前安装版因此稳定在约 1.62 秒触发，容易截断自然停顿。本任务将内部基线调整为 2.0 秒，预计用户体感约 2.5～3 秒。

- [x] RED：边界检查先要求权威常量为 2.0 秒，并确认在旧实现上失败。
- [x] GREEN：只修改权威常量，状态机和其他录音链路不变。
- [x] 自动验证：协调器边界、纯策略、设置独立性与 `git diff --check` 通过。
- [ ] 真实安装版验收：说一句后停顿约 2 秒再继续，录音不得结束；持续停顿接近 3 秒时应自动完成。
