# Short-Utterance Pause Finalization Implementation Plan

> **Status: Reverted from production.** 真实安装版证明 1.2 秒 pause-final 会把 8–9 秒语音切成 3–4 个块，造成上下文断裂、缺字和少字。生产代码已从 Git 恢复到本计划实施前的 10–18 秒分块版本；本文保留为失败方案记录，不得继续作为实施依据。

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 普通实时识别在连续停顿 1.2 秒后只做一次收口识别并锁定当前语句，避免短句被新增静音反复重识别后改坏。

**Architecture:** 新增纯状态 `RealtimePauseFinalizationState`，只根据 VAD、帧位置和采样率决定继续预览、停顿等待或收口。`AudioRecorder` 使用该状态控制快照；`SpeechInputCoordinator` 识别收口快照并在失败时保留已有尾巴。生产缓存、主胶囊和最终粘贴继续消费同一份 `PreviewDisplaySnapshot`。

**Tech Stack:** Swift、AVFoundation、Silero VAD 已有状态、shell/Swift 边界测试。

## Global Constraints

- 开工前重读本文；每次只执行一个 Task；Task 完成后更新本文并提交。
- 不改 UI、候选/旁路定位、Final ASR 开关、最终交付仲裁。
- 不做错词硬编码替换。
- VAD 不可用时保留现有 18 秒硬边界兜底。
- 收口失败不能清空已有实时文字。
- 不新建 worktree；保护现有两个未跟踪概念设计目录。

---

## Hotfix: VAD False-Negative Must Not Stall Realtime ASR

**Status:** Reverted together with the 1.2-second production path

- 真实日志证据：录音已收到 `27,813–85,328` 帧、峰值为 `0.003564–0.006939`，但 Silero 连续返回 `no_speech`；每次录音只有首个 0.3 秒空快照，随后没有新快照。
- 根因：`RealtimePauseFinalizationState` 在“尚未确认人声 + VAD=false”时返回 `holdDuringPause`，把 VAD 漏判错误升级为永久停止实时 ASR。
- 修复边界：尚未确认人声时继续产生普通快照；ASR 产出有效文字后，通过 `observeRealtimeRecognizedSpeech()` 补充“本块确实有人声”的证据，之后仍按 1.2 秒停顿收口。
- 保持不变：18 秒硬边界、Final ASR 开关、生产缓存、最终粘贴、UI 和旁路/候选定位。
- RED/GREEN：状态测试先稳定失败于 `VAD must not stall realtime ASR before speech has been confirmed`；接线测试先失败于 ASR 证据未回传。实现后状态、接线、静音门控、内存快照和低电平波形边界测试通过。
- 完整构建安装：`2.0.48 (Build 790)` 已覆盖安装到 `/Applications/TypeWhale Pro.app`；Info.plist、运行进程、启动日志和 codesign deep/strict 校验通过。真实麦克风讲话响应由用户验收。

---

## Recovery: Restore Proven 10–18-Second Production Chunking

**Status:** Completed

- 真实日志：8–9 秒录音在约 3.4、5.4、7.5 秒连续出现 `final=true`，块序号从 0 推进到 3；旧生产方案在 10 秒前不会产生真正块边界。
- 根因：1.2 秒自然停顿被实现为 pause-final，直接提交块并推进块序号，导致短录音频繁失去上下文。
- 恢复方式：从 `38fe71cf^` 直接恢复 `AudioRecorder`、`SpeechInputCoordinator`、`SpeechInputState`、相关 Domain 接口和测试，不重新手写旧逻辑。
- 恢复结果：10 秒后遇停顿才真正收口；持续讲话到 18 秒强制收口。Final ASR、生产缓存、最终粘贴、UI 和旁路/候选定位不变。
- 完整构建安装：`2.0.49 (Build 791)` 已覆盖安装并打开；版本、进程、启动日志与 codesign deep/strict 校验通过。真实录音缺字/少字由用户验收。
- 安装版实测日志：恢复后的首条 4.9 秒录音从 0.3 秒快照到停止始终为 `chunk=0, final=false`，没有再次出现 10 秒前推进块序号；最终从生产实时缓存正常交付 18 个字符。内容准确性继续由用户验收。
- 遗留清理：删除未被生产链路调用、但仍会被编译进 App 的 `RealtimePauseFinalizationState.swift` 和对应测试 `RealtimePauseFinalizationStateCheck.swift`。历史计划与版本记录保留，防止未来重复引入该失败方案。
- 清理构建：`2.0.50 (Build 792)` 已完整编译、覆盖安装并打开；签名校验通过。生产源码和测试中搜索相关状态类型、`finalizePause` 与 `pauseSeconds: 1.2` 均为零结果。

---

## Task 1: Add Pure 1.2-Second Pause Finalization State

**Status:** Completed

**Files:**

- Create: `native/Sources/Domain/RealtimeTranscription/RealtimePauseFinalizationState.swift`
- Create: `native/Tests/RealtimePauseFinalizationStateCheck.swift`
- Modify: `docs/superpowers/plans/2026-07-20-short-utterance-pause-finalization.md`

**Interfaces:**

- Produces: `RealtimePauseDecision` with `.emitIntermediate`, `.holdDuringPause`, `.finalizePause`.
- Produces: `RealtimePauseFinalizationState.evaluate(voiceActive:currentFrame:sampleRate:)`.
- Produces: `RealtimePauseFinalizationState.resetForNextChunk()`.

- [x] **Step 1: Write the failing state test**

```swift
import Foundation

@main
struct RealtimePauseFinalizationStateCheck {
    static func main() {
        var state = RealtimePauseFinalizationState(pauseSeconds: 1.2)
        precondition(state.evaluate(voiceActive: true, currentFrame: 16_000, sampleRate: 16_000) == .emitIntermediate)
        precondition(state.evaluate(voiceActive: false, currentFrame: 20_000, sampleRate: 16_000) == .holdDuringPause)
        precondition(state.evaluate(voiceActive: false, currentFrame: 39_199, sampleRate: 16_000) == .holdDuringPause)
        precondition(state.evaluate(voiceActive: false, currentFrame: 39_200, sampleRate: 16_000) == .finalizePause)

        state.resetForNextChunk()
        precondition(state.evaluate(voiceActive: false, currentFrame: 48_000, sampleRate: 16_000) == .holdDuringPause)
        precondition(state.evaluate(voiceActive: true, currentFrame: 56_000, sampleRate: 16_000) == .emitIntermediate)
        precondition(state.evaluate(voiceActive: false, currentFrame: 60_000, sampleRate: 16_000) == .holdDuringPause)
        precondition(state.evaluate(voiceActive: true, currentFrame: 70_000, sampleRate: 16_000) == .emitIntermediate)
        print("RealtimePauseFinalizationStateCheck passed")
    }
}
```

- [x] **Step 2: Run RED**

```bash
swiftc native/Sources/Domain/RealtimeTranscription/RealtimePauseFinalizationState.swift native/Tests/RealtimePauseFinalizationStateCheck.swift -o /tmp/RealtimePauseFinalizationStateCheck
```

Expected: FAIL because the source/type does not exist.

- [x] **Step 3: Implement the pure state**

```swift
import Foundation

enum RealtimePauseDecision: Equatable {
    case emitIntermediate
    case holdDuringPause
    case finalizePause
}

struct RealtimePauseFinalizationState {
    let pauseSeconds: TimeInterval
    private(set) var hasObservedSpeech = false
    private(set) var silenceStartFrame: Int64?

    mutating func evaluate(voiceActive: Bool, currentFrame: Int64, sampleRate: Int) -> RealtimePauseDecision {
        guard sampleRate > 0 else { return .emitIntermediate }
        if voiceActive {
            hasObservedSpeech = true
            silenceStartFrame = nil
            return .emitIntermediate
        }
        guard hasObservedSpeech else { return .holdDuringPause }
        guard let silenceStartFrame else {
            self.silenceStartFrame = currentFrame
            return .holdDuringPause
        }
        let silentFrames = max(0, currentFrame - silenceStartFrame)
        return Double(silentFrames) / Double(sampleRate) >= pauseSeconds
            ? .finalizePause
            : .holdDuringPause
    }

    mutating func resetForNextChunk() {
        hasObservedSpeech = false
        silenceStartFrame = nil
    }
}
```

- [x] **Step 4: Run GREEN and diff check**

```bash
swiftc native/Sources/Domain/RealtimeTranscription/RealtimePauseFinalizationState.swift native/Tests/RealtimePauseFinalizationStateCheck.swift -o /tmp/RealtimePauseFinalizationStateCheck
/tmp/RealtimePauseFinalizationStateCheck
git diff --check
```

Expected: `RealtimePauseFinalizationStateCheck passed`.

- [x] **Step 5: Update this Task to Completed and commit**

```bash
git add native/Sources/Domain/RealtimeTranscription/RealtimePauseFinalizationState.swift native/Tests/RealtimePauseFinalizationStateCheck.swift docs/superpowers/plans/2026-07-20-short-utterance-pause-finalization.md
git commit -m "feat(realtime): model pause finalization state"
```

**Evidence:** RED failed because `RealtimePauseFinalizationState.swift` did not exist. GREEN printed `RealtimePauseFinalizationStateCheck passed`; `git diff --check` passed.

## Task 2: Wire Pause Finalization Into Product Realtime Snapshots

**Status:** Completed; installed-app microphone acceptance pending

**Files:**

- Modify: `native/Sources/Infrastructure/Audio/AudioRecorder.swift`
- Modify: `native/Sources/Domain/RealtimeTranscription/RealtimePauseFinalizationState.swift`
- Modify: `native/Sources/Application/SpeechInputState.swift`
- Modify: `native/Sources/Application/SpeechInputCoordinator.swift`
- Create: `native/Tests/RealtimePauseFinalizationWiringCheck.sh`
- Modify: `native/Tests/RealtimeSilenceGateBoundaryCheck.sh`
- Modify: `native/Tests/RealtimePreviewMemoryAudioBoundaryCheck.sh`
- Modify: `native/Tests/PreviewFinalChunkWriteFailureCheck.swift`
- Modify: `docs/superpowers/plans/2026-07-20-short-utterance-pause-finalization.md`
- Modify: `docs/superpowers/plans/2026-07-20-realtime-cache-authority-cutover.md`
- Modify: `docs/开发日志.md`
- Modify: `native/Sources/Presentation/VersionHistory/VersionHistoryViewController.swift`

**Interfaces:**

- Consumes: `RealtimePauseFinalizationState.evaluate(...)`.
- Produces: `RealtimeSnapshotKind` with `.intermediate`, `.pauseFinal`, `.hardLimitFinal` and `isChunkFinal`.
- Changes: `AudioRecorder.onRealtimeSnapshot` and `RealtimeSnapshotRequest` carry `kind` instead of an unqualified Boolean.

- [x] **Step 1: Write RED wiring checks**

`RealtimePauseFinalizationWiringCheck.sh` must assert:

```bash
grep -Fq 'RealtimePauseFinalizationState(pauseSeconds: 1.2)' "$AUDIO"
grep -Fq 'case .holdDuringPause:' "$AUDIO"
grep -Fq 'case .finalizePause:' "$AUDIO"
grep -Fq '.pauseFinal' "$AUDIO"
grep -Fq 'request.kind == .pauseFinal' "$COORDINATOR"
grep -Fq 'session.committedPreviewText += session.latestPreviewText' "$COORDINATOR"
```

It must also reject the old soft-boundary expression:

```bash
if grep -Fq 'softReached && !realtimeVoiceActive' "$AUDIO"; then
    echo "10-second soft boundary must not own pause finalization" >&2
    exit 1
fi
```

- [x] **Step 2: Run RED**

```bash
bash native/Tests/RealtimePauseFinalizationWiringCheck.sh
```

Expected: FAIL because pause finalization is not wired.

- [x] **Step 3: Add semantic snapshot kind**

In `RealtimePauseFinalizationState.swift` add the shared Domain snapshot kind:

```swift
enum RealtimeSnapshotKind: Sendable {
    case intermediate
    case pauseFinal
    case hardLimitFinal

    var isChunkFinal: Bool {
        switch self {
        case .intermediate: false
        case .pauseFinal, .hardLimitFinal: true
        }
    }
}
```

Change `RealtimeSnapshotRequest.isChunkFinal` into `kind` plus computed `isChunkFinal` so existing queue/freeze logic remains readable.

- [x] **Step 4: Wire the state in AudioRecorder**

Initialize/reset:

```swift
private var realtimePauseFinalizationState = RealtimePauseFinalizationState(pauseSeconds: 1.2)
```

At each snapshot opportunity evaluate the policy. Use `.holdDuringPause` to emit nothing, `.finalizePause` to call `prepareFinalChunkCommit(..., kind: .pauseFinal)`, active speech to emit `.intermediate`, and the 18-second hard limit to finalize with `.hardLimitFinal`. Remove the old `softReached && !realtimeVoiceActive` ownership. After a successful chunk commit call `resetForNextChunk()`.

- [x] **Step 5: Allow exactly one pause-final recognition**

Update `shouldSkipRealtimeASRForSilence` so `.pauseFinal` is not skipped:

```swift
if request.kind == .pauseFinal { return false }
guard request.isChunkFinal else { return false }
```

Keep `applyRealtimePreview` behavior: a meaningful pause-final result replaces `latestPreviewText` and is then committed; an empty, failed or filtered result leaves `latestPreviewText` unchanged and commits that existing text.

- [x] **Step 6: Run focused GREEN tests**

```bash
swiftc native/Sources/Domain/RealtimeTranscription/RealtimePauseFinalizationState.swift native/Tests/RealtimePauseFinalizationStateCheck.swift -o /tmp/RealtimePauseFinalizationStateCheck && /tmp/RealtimePauseFinalizationStateCheck
bash native/Tests/RealtimePauseFinalizationWiringCheck.sh
bash native/Tests/RealtimeSilenceGateBoundaryCheck.sh
bash native/Tests/RealtimeStopDrainBoundaryCheck.sh
bash native/Tests/RealtimePreviewMemoryAudioBoundaryCheck.sh
bash native/Tests/ProductionPreviewDeliveryCacheWiringCheck.sh
bash native/Tests/FinalRecognitionPreviewCacheDefaultCheck.sh
git diff --check
```

Expected: all pass.

- [x] **Step 7: Update plan and release narrative**

Record the exact implementation, tests, remaining 18-second overlap-calibration risk, and manual test phrases. Update the app version-history entry required by the build guard without claiming manual acceptance.

- [x] **Step 8: Build, install and verify**

Before building re-run branch/status/process/mtime safety checks, then:

```bash
./native/build_and_log.sh
```

Expected: build succeeds, `/Applications/TypeWhale Pro.app` is replaced and opened, signature verification succeeds, build log is appended.

- [x] **Step 9: Commit only task-owned files**

```bash
git status --short
git add native/Sources/Domain/RealtimeTranscription/RealtimePauseFinalizationState.swift native/Sources/Infrastructure/Audio/AudioRecorder.swift native/Sources/Application/SpeechInputState.swift native/Sources/Application/SpeechInputCoordinator.swift native/Tests/RealtimePauseFinalizationWiringCheck.sh native/Tests/RealtimeSilenceGateBoundaryCheck.sh native/Tests/RealtimePreviewMemoryAudioBoundaryCheck.sh native/Tests/PreviewFinalChunkWriteFailureCheck.swift docs/superpowers/plans/2026-07-20-short-utterance-pause-finalization.md docs/superpowers/plans/2026-07-20-realtime-cache-authority-cutover.md docs/开发日志.md native/Sources/Presentation/VersionHistory/VersionHistoryViewController.swift native/build_native_app.sh README.md macos/README.md docs/构建日志.md
git commit -m "fix(realtime): finalize short utterances after pause"
```

**Evidence:** `RealtimePauseFinalizationWiringCheck` first failed because `AudioRecorder` had no 1.2-second pause state. GREEN passed for the pause state, recorder wiring, pause-final silence gate, stop drain, in-memory snapshot, production cache, Final ASR switch boundary and final-chunk failure safety. `./native/build_and_log.sh --full-version` built, installed and opened `2.0.47 (789)`; deep/strict signature validation passed. Real microphone phrases below remain for product-owner acceptance.

## Manual Acceptance Text

After install, test these separately:

1. `验收短句。` 说完停 3 秒；锁定后不能反复变化。
2. `用户体验。` 说完停 1.2–2 秒，再说 `不要丢字。`；第二句开头必须保留。
3. `今天我们讨论功能优化。` 说快一点，停 3 秒；停顿后最多只允许一次收口变化。
4. 连续不停顿说 15 秒；预览仍持续更新，不能因短句策略卡住。
5. 静音录音 3 秒；不能产生 `我想`、`I`、`嗯`。

## Completion Reminder

本计划完成并通过手测后，提醒产品负责人继续处理已登记的“分块上下文割裂 / 18 秒硬边界前后重叠校准”问题。
