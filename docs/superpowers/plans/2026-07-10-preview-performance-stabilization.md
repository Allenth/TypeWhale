# Preview Performance Stabilization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep experimental SenseVoice preview responsive after the first 20 seconds by measuring each lane and replacing correction-first scheduling with a deterministic deadline/fairness policy.

**Architecture:** Extend the pure `PreviewRequestScheduler` with monotonic enqueue timestamps and a small policy value. The pipeline measures queue, recognition, and end-to-end latency around the existing single `NativeSenseVoiceBridge`; no second model, coordinator migration, final-text change, or correction-window change is included.

**Tech Stack:** Swift 6, Foundation `ProcessInfo.systemUptime`, existing SenseVoice native bridge, standalone Swift checks, shell boundary checks, `native/build_and_log.sh`.

## Global Constraints

- Work only on `codex/typewhale-pro-asr-hotwords` after concurrency checks.
- Keep both experimental settings and their rollback behavior.
- Keep the 22.5-second correction window, immutable confirmed prefix, incremental final source, smart processing, and paste behavior unchanged.
- Keep one primary recognition engine; do not add a second model instance.
- Fast work is latest-only; stop-tail retains finalization priority.
- Every production behavior starts with a failing test and observed RED result.
- English architecture terms in user-facing docs receive adjacent Chinese meanings.
- Build only after confirming the installed app is idle; update version history and development records first.

---

### Task 1: Monotonic request metadata and scheduler policy

**Files:**
- Modify: `native/Sources/Application/RealtimePreview/PreviewRequestScheduler.swift`
- Modify: `native/Tests/PreviewRequestSchedulerCheck.swift`

**Interfaces:**
- Produces: `PreviewSchedulingPolicy(fastDeadlineSeconds:maxConsecutiveFastRequests:)`.
- Extends: `PreviewPipelineRequest.enqueuedUptime: TimeInterval`.
- Extends: `PreviewRequestScheduler.complete(requestID:completedAt:)`.
- Exposes: `hasPendingFastRequest`, `pendingCorrectionCount`, and discarded requests for file cleanup.

- [x] **Step 1: Write the failing scheduling checks**

Add deterministic requests with explicit enqueue times and verify four behaviors:

```swift
let policy = PreviewSchedulingPolicy(
    fastDeadlineSeconds: 0.7,
    maxConsecutiveFastRequests: 4
)
var scheduler = PreviewRequestScheduler(sessionID: sessionID, epoch: 1, policy: policy)

// A fast request waiting 0.8s outranks correction.
let activeFastAtDeadline = request(lane: .fast, enqueuedUptime: 10.0)
let overdueFast = request(lane: .fast, enqueuedUptime: 10.2)
let queuedCorrection = request(lane: .correction, enqueuedUptime: 10.3)
_ = scheduler.enqueueFast(activeFastAtDeadline)
_ = scheduler.enqueueFast(overdueFast)
_ = scheduler.enqueueCorrection(queuedCorrection)
precondition(
    scheduler.complete(requestID: activeFastAtDeadline.requestID, completedAt: 11.0) == overdueFast
)

// A correction cannot run twice ahead of a waiting fast request.
scheduler.reset(epoch: 2)
let activeCorrection = request(lane: .correction, enqueuedUptime: 20.0)
let nextCorrection = request(lane: .correction, enqueuedUptime: 20.1)
let waitingFast = request(lane: .fast, enqueuedUptime: 20.2)
_ = scheduler.enqueueCorrection(activeCorrection)
_ = scheduler.enqueueCorrection(nextCorrection)
_ = scheduler.enqueueFast(waitingFast)
precondition(
    scheduler.complete(requestID: activeCorrection.requestID, completedAt: 20.3) == waitingFast
)

// Four completed fast requests force one correction admission.
scheduler.reset(epoch: 3)
let fairnessCorrection = request(lane: .correction, enqueuedUptime: 30.1)
var activeFast = request(lane: .fast, enqueuedUptime: 30.0)
_ = scheduler.enqueueFast(activeFast)
_ = scheduler.enqueueCorrection(fairnessCorrection)
for index in 1...4 {
    let nextFast = request(lane: .fast, enqueuedUptime: 30.0 + Double(index) * 0.1)
    _ = scheduler.enqueueFast(nextFast)
    let selected = scheduler.complete(
        requestID: activeFast.requestID,
        completedAt: 30.0 + Double(index) * 0.1
    )
    if index < 4 {
        precondition(selected == nextFast)
        activeFast = nextFast
    } else {
        precondition(selected == fairnessCorrection)
    }
}

// Existing stop-tail assertion remains and must still select stop-tail first.
```

Update the request factory to require `enqueuedUptime`; do not use wall-clock `Date` in these checks.

- [x] **Step 2: Run RED**

Run:

```bash
xcrun swiftc native/Sources/Domain/RealtimePreview/*.swift native/Sources/Application/RealtimePreview/PreviewRequestScheduler.swift native/Tests/PreviewRequestSchedulerCheck.swift -o /tmp/PreviewRequestSchedulerCheck
```

Expected: compilation fails because `PreviewSchedulingPolicy`, `enqueuedUptime`, and `completedAt` do not exist.

- [x] **Step 3: Implement the minimal pure policy**

Add:

```swift
struct PreviewSchedulingPolicy: Equatable, Sendable {
    let fastDeadlineSeconds: TimeInterval
    let maxConsecutiveFastRequests: Int

    static let testStage = PreviewSchedulingPolicy(
        fastDeadlineSeconds: 0.7,
        maxConsecutiveFastRequests: 4
    )
}
```

Track the completed lane and consecutive-fast count. When pending corrections reach two, use `backlogMaxConsecutiveFastRequests = 1` instead of the normal four-fast quota. Selection order after an active request completes must be:

1. pending stop-tail;
2. overdue pending fast (`completedAt - enqueuedUptime >= 0.7`);
3. pending fast immediately after a correction, preventing consecutive corrections ahead of live display;
4. oldest correction after the backlog-pressure fast quota or four consecutive fast requests, preventing correction starvation;
5. pending fast;
6. oldest correction.

All reset/cancel/drain methods must reset counters without changing existing session/epoch validation.

- [x] **Step 4: Run GREEN**

Run:

```bash
xcrun swiftc native/Sources/Domain/RealtimePreview/*.swift native/Sources/Application/RealtimePreview/PreviewRequestScheduler.swift native/Tests/PreviewRequestSchedulerCheck.swift -o /tmp/PreviewRequestSchedulerCheck && /tmp/PreviewRequestSchedulerCheck
```

Expected: `PreviewRequestSchedulerCheck passed`.

- [x] **Step 5: Commit Task 1**

```bash
git add native/Sources/Application/RealtimePreview/PreviewRequestScheduler.swift native/Tests/PreviewRequestSchedulerCheck.swift
git commit -m "fix(preview): prioritize overdue realtime requests"
```

### Task 2: Per-lane queue and recognition telemetry

**Files:**
- Modify: `native/Sources/Application/RealtimePreview/ExperimentalRealtimePreviewPipeline.swift`
- Modify: `native/Sources/Application/SpeechInputCoordinator.swift`
- Modify: `native/Sources/Application/SpeechInputState.swift`
- Modify: `native/Sources/Infrastructure/Audio/AudioRecorder.swift`
- Modify: `native/Sources/Infrastructure/Diagnostics/LaunchDiagnostics.swift`
- Create: `native/Tests/PreviewPipelinePerformanceBoundaryCheck.sh`

**Interfaces:**
- Consumes: `PreviewPipelineRequest.enqueuedUptime`, scheduler pending-state accessors, and `complete(requestID:completedAt:)` from Task 1.
- Produces diagnostics: `preview_request_start`, `preview_request_done`, `preview_fast_budget_miss`, `preview_correction_backlog_warning`.

- [x] **Step 1: Write the failing source-boundary check**

Create a shell check that requires all request constructors to use monotonic uptime and requires start/done diagnostics to contain lane, chunk, queue wait, recognition time, end-to-end time, audio duration, pending-fast state, and correction backlog.

```bash
required=(
  'enqueuedUptime: ProcessInfo.processInfo.systemUptime'
  'preview_request_start lane='
  'queue_ms='
  'preview_request_done lane='
  'recognition_ms='
  'total_ms='
  'audio_ms='
  'pending_fast='
  'correction_backlog='
  'preview_fast_budget_miss'
  'preview_correction_backlog_warning'
)
```

The check must also reject `Date()` or `Date().timeIntervalSince` inside performance duration calculation in `ExperimentalRealtimePreviewPipeline`.

- [x] **Step 2: Run RED**

Run:

```bash
bash native/Tests/PreviewPipelinePerformanceBoundaryCheck.sh
```

Expected: FAIL because the pipeline does not emit per-lane performance diagnostics.

- [x] **Step 3: Instrument the existing execution boundary**

For fast, correction, and stop-tail construction, set:

```swift
enqueuedUptime: ProcessInfo.processInfo.systemUptime
```

At `execute(_:)`, capture `startedUptime`, calculate nonnegative queue milliseconds, and log scheduler state before calling `transcribeDetailed`. In the callback, capture `completedUptime`, calculate recognition and total milliseconds, log success/failure, and emit `preview_fast_budget_miss` when a fast request's queue wait exceeds 700ms. Emit `preview_correction_backlog_warning` when the FIFO correction backlog exceeds two; do not discard a real boundary in this function-first pass. Pass `completedUptime` into scheduler completion.

Do not log transcript contents or audio paths. Keep temporary-file cleanup in `defer` for every callback outcome.

- [x] **Step 4: Run GREEN and scheduler regression**

Run:

```bash
bash native/Tests/PreviewPipelinePerformanceBoundaryCheck.sh
xcrun swiftc native/Sources/Domain/RealtimePreview/*.swift native/Sources/Application/RealtimePreview/PreviewRequestScheduler.swift native/Tests/PreviewRequestSchedulerCheck.swift -o /tmp/PreviewRequestSchedulerCheck && /tmp/PreviewRequestSchedulerCheck
```

Expected: both checks pass.

- [x] **Step 5: Commit Task 2**

```bash
git add native/Sources/Application/RealtimePreview/ExperimentalRealtimePreviewPipeline.swift native/Sources/Application/SpeechInputCoordinator.swift native/Sources/Application/SpeechInputState.swift native/Sources/Infrastructure/Audio/AudioRecorder.swift native/Sources/Infrastructure/Diagnostics/LaunchDiagnostics.swift native/Tests/PreviewPipelinePerformanceBoundaryCheck.sh
git commit -m "feat(preview): record per-lane latency"
```

### Task 3: Full regression, release record, and installed test build

**Files:**
- Modify: `docs/PREVIEW_ARCHITECTURE_COMMUNICATION_LOG.md`
- Modify: `docs/ARCHITECTURE.md`
- Modify: `docs/开发日志.md`
- Modify: `native/Sources/Presentation/VersionHistory/VersionHistoryViewController.swift`
- Build-generated: `README.md`, `macos/README.md`, `docs/构建日志.md`, `native/build_native_app.sh`

**Interfaces:**
- Consumes: deadline scheduler and diagnostics from Tasks 1–2.
- Produces: signed installed TypeWhale Pro test build and a traceable manual validation procedure.

- [x] **Step 1: Run focused and existing regression checks**

```bash
bash native/Tests/PreviewPipelinePerformanceBoundaryCheck.sh
xcrun swiftc native/Sources/Domain/RealtimePreview/*.swift native/Sources/Application/RealtimePreview/PreviewRequestScheduler.swift native/Tests/PreviewRequestSchedulerCheck.swift -o /tmp/PreviewRequestSchedulerCheck && /tmp/PreviewRequestSchedulerCheck
xcrun swiftc native/Sources/Domain/RealtimePreview/*.swift native/Tests/PreviewTranscriptReducerCheck.swift -o /tmp/PreviewTranscriptReducerCheck && /tmp/PreviewTranscriptReducerCheck
xcrun swiftc native/Sources/Domain/RealtimePreview/*.swift native/Tests/PreviewStopTailOverflowCheck.swift -o /tmp/PreviewStopTailOverflowCheck && /tmp/PreviewStopTailOverflowCheck
xcrun swiftc native/Sources/Presentation/Capsule/CapsuleTextBuffer.swift native/Tests/CapsuleTextBufferCheck.swift -o /tmp/CapsuleTextBufferCheck && /tmp/CapsuleTextBufferCheck
bash native/Tests/LongFormDiskSafetyMainThreadBoundaryCheck.sh
bash native/Tests/LongFormCoordinatorBoundaryCheck.sh
bash native/Tests/SpeechInputCoordinatorBoundaryCheck.sh
git diff --check
```

Expected: every check exits 0; named checks print `passed`.

- [x] **Step 2: Update product and architecture records before building**

Document the selected single-engine deadline policy, 700ms test budget, monotonic diagnostics, unchanged final-text boundary, rollback behavior, and the fact that dual executors remain deferred pending evidence. Add the next build entry to in-app version history before invoking the release script.

- [x] **Step 3: Perform concurrency preflight and build**

```bash
git branch --show-current
git status --short
ps ax -o pid=,etime=,command= | awk '/build_and_log|release_local_build|build_native_app|swiftc|xcodebuild/ && $0 !~ /awk/ {print}'
./native/build_and_log.sh
```

Expected: branch is `codex/typewhale-pro-asr-hotwords`; no unrelated writer/build is active; build succeeds, installs `/Applications/TypeWhale Pro.app`, opens it, and passes signing verification.

- [x] **Step 4: Verify the installed build**

```bash
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' '/Applications/TypeWhale Pro.app/Contents/Info.plist'
/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' '/Applications/TypeWhale Pro.app/Contents/Info.plist'
codesign --verify --deep --strict --verbose=2 '/Applications/TypeWhale Pro.app'
```

Expected: version/build match the release records and codesign reports valid designated requirements.

- [ ] **Step 5: Manual installed-app acceptance**

Record continuously for at least 90 seconds, speaking through 20, 30, 60, and 90-second boundaries. Expected:

- capsule continues advancing rather than freezing during correction;
- final incremental text, smart processing, and paste complete normally;
- logs contain `preview_request_start/done` for both fast and correction;
- any fast queue wait above 700ms emits `preview_fast_budget_miss` with the competing lane visible in adjacent records.

If the 90-second check passes, continue 10-minute and one-hour sessions as test-stage soak tests; do not claim one-hour stability before those recordings complete.

- [ ] **Step 6: Final review and commit**

Review the complete diff, rerun `git diff --check`, stage only files owned by this pass, and commit:

```bash
git commit -m "perf(preview): stabilize long-form realtime scheduling"
```
