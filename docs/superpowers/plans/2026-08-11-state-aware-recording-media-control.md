# State-Aware Recording Media Control Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prevent recording activation from starting already-paused media by pausing and resuming only a stable, positively identified system now-playing process.

**Architecture:** Add a tiny Objective-C bridge that dynamically loads two private `MediaRemote` symbols and returns a fail-closed playback snapshot. Wrap it behind an injectable Swift protocol, then change `SystemMediaPlaybackController` into a generation-guarded ownership state machine that emits media events only for confirmed states and the same process identity.

**Tech Stack:** Swift 5.10/6.2 compiler, Objective-C blocks, AppKit/ApplicationServices, `dlopen`/`dlsym`, private macOS `MediaRemote.framework`, shell boundary checks, direct DMG/Beta distribution.

## Global Constraints

- Minimum supported macOS remains 14.0 on arm64.
- Missing framework, symbols, callback, stable PID, or known state must fail closed to `unknown` and emit no media event.
- Never read or log player names, song names, video titles, URLs, artwork, or now-playing metadata.
- Starting a recording must never start media that was already paused.
- Resume only a pause successfully emitted by TypeWhale and still owned by the same nonzero process ID.
- Preserve consecutive-recording coalescing and synthetic-event isolation from OpenClaw/hotkey capture.
- Do not modify the system-volume ducking behavior.
- Do not touch protected unrelated dirt in Smart Rewrite, `.artifacts/`, `.superpowers/`, CapsuleConceptGallery, or Capsule Concepts.
- Record the completed behavior as a small milestone in `docs/开发日志.md` and in-app version history.
- Use the main workspace and established branch; do not create a worktree unless a new overlap or active concurrent writer makes the main workspace unsafe.

---

## File structure

- Create `native/SystemMediaRemoteBridge.h`: C-compatible playback snapshot enum and one asynchronous bridge function visible to Swift.
- Create `native/SystemMediaRemoteBridge.m`: dynamically load `MediaRemote`, assemble PID/state/PID snapshots, enforce timeout and one-shot completion.
- Create `native/Sources/Infrastructure/Audio/SystemMediaPlaybackStateProvider.swift`: domain snapshot types, provider protocol, and production wrapper around the bridge.
- Modify `native/TypeSpeakerNativeASR.h`: include the media bridge in the existing Swift bridging-header boundary.
- Modify `native/build_native_app.sh`: compile/link/clean the Objective-C bridge object.
- Create `native/Tests/SystemMediaPlaybackStateProviderCheck.swift`: verify raw-value mapping and fail-closed identity rules without loading real media state.
- Create `native/Tests/SystemMediaRemoteBridgeBoundaryCheck.sh`: enforce dynamic loading, stable PID reads, timeout, privacy, and build integration.
- Modify `native/Sources/Infrastructure/Audio/SystemMediaPlaybackController.swift`: add state-aware pause ownership and resume decisions.
- Modify `native/Tests/SystemMediaPlaybackControllerCheck.swift`: cover paused, unknown, same-process, changed-process, user-resume, late-callback, and consecutive-recording cases.
- Modify `docs/开发日志.md`: add the small milestone and release/build evidence.
- Modify `native/Sources/Presentation/VersionHistory/VersionHistoryViewController.swift`: add the user-visible milestone entry.
- Modify automatically during build: `README.md`, `macos/README.md`, `docs/构建日志.md`, and `native/build_native_app.sh` build number.

---

### Task 1: Add the fail-closed MediaRemote snapshot boundary

**Files:**
- Create: `native/SystemMediaRemoteBridge.h`
- Create: `native/SystemMediaRemoteBridge.m`
- Create: `native/Sources/Infrastructure/Audio/SystemMediaPlaybackStateProvider.swift`
- Create: `native/Tests/SystemMediaPlaybackStateProviderCheck.swift`
- Create: `native/Tests/SystemMediaRemoteBridgeBoundaryCheck.sh`
- Modify: `native/TypeSpeakerNativeASR.h`
- Modify: `native/build_native_app.sh`

**Interfaces:**
- Produces: `SystemMediaPlaybackState`, `SystemMediaPlaybackSnapshot`, `SystemMediaPlaybackStateProviding.fetchSnapshot(completion:)`, and `MediaRemoteSystemPlaybackStateProvider`.
- Produces C bridge: `TWSystemMediaFetchPlaybackSnapshot(TWSystemMediaPlaybackSnapshotCompletion completion)` with raw state values unknown `0`, paused `1`, playing `2`.
- Consumes later: `SystemMediaPlaybackController` receives any `SystemMediaPlaybackStateProviding`.

- [x] **Step 1: Write the failing Swift provider test**

Create a test whose injected raw fetcher returns `(2, 451)`, `(1, 451)`, unknown raw values, and zero/negative PIDs. Require exact results:

```swift
let playing = provider(rawState: 2, pid: 451)
precondition(playing == .init(state: .playing, processID: 451))

let paused = provider(rawState: 1, pid: 451)
precondition(paused == .init(state: .paused, processID: 451))

precondition(provider(rawState: 9, pid: 451).state == .unknown)
precondition(provider(rawState: 2, pid: 0).state == .unknown)
precondition(provider(rawState: 1, pid: -1).state == .unknown)
```

The test helper must inject `rawFetch` and capture exactly one completion without loading `MediaRemote`.

- [x] **Step 2: Write the failing source/build boundary check**

Require all of the following exact implementation boundaries:

```bash
require_text native/SystemMediaRemoteBridge.m 'dlopen('
require_text native/SystemMediaRemoteBridge.m 'MRMediaRemoteGetNowPlayingApplicationIsPlaying'
require_text native/SystemMediaRemoteBridge.m 'MRMediaRemoteGetNowPlayingApplicationPID'
require_count native/SystemMediaRemoteBridge.m 'getPID(' 2
require_text native/SystemMediaRemoteBridge.m 'dispatch_after('
reject_text native/SystemMediaRemoteBridge.m 'MRMediaRemoteGetNowPlayingInfo'
require_text native/build_native_app.sh 'SystemMediaRemoteBridge.m'
require_text native/build_native_app.sh 'MEDIA_REMOTE_BRIDGE_OBJECT'
require_text native/TypeSpeakerNativeASR.h '#include "SystemMediaRemoteBridge.h"'
```

The script exits nonzero with a specific message for every missing boundary.

- [x] **Step 3: Run RED and record the expected failures**

Run:

```bash
xcrun swiftc -parse-as-library \
  native/Tests/SystemMediaPlaybackStateProviderCheck.swift \
  -o /tmp/typewhale-media-state-provider-check
bash native/Tests/SystemMediaRemoteBridgeBoundaryCheck.sh
```

Expected: Swift compilation fails because provider types do not exist, and the shell check fails because bridge files/integration do not exist.

- [x] **Step 4: Implement the Objective-C bridge header and implementation**

The header exposes only state and PID:

```objc
typedef NS_ENUM(int32_t, TWSystemMediaPlaybackState) {
    TWSystemMediaPlaybackStateUnknown = 0,
    TWSystemMediaPlaybackStatePaused = 1,
    TWSystemMediaPlaybackStatePlaying = 2,
};

typedef void (^TWSystemMediaPlaybackSnapshotCompletion)(
    TWSystemMediaPlaybackState state,
    pid_t processID
);

void TWSystemMediaFetchPlaybackSnapshot(
    TWSystemMediaPlaybackSnapshotCompletion completion
);
```

The implementation must:

1. `dlopen` `/System/Library/PrivateFrameworks/MediaRemote.framework/Versions/A/MediaRemote` once.
2. `dlsym` only `MRMediaRemoteGetNowPlayingApplicationPID` and `MRMediaRemoteGetNowPlayingApplicationIsPlaying`.
3. Execute PID -> playing -> PID on one serial queue.
4. Return known state only when the two PIDs match and are greater than zero.
5. Schedule a 250 ms timeout on the same queue.
6. Use a one-shot `finished` guard so timeout and late callbacks cannot complete twice.
7. Dispatch the public completion to the main queue.

The implementation must not call `MRMediaRemoteGetNowPlayingInfo` or log metadata.

- [x] **Step 5: Implement the Swift provider and build integration**

Define:

```swift
enum SystemMediaPlaybackState: Equatable {
    case playing
    case paused
    case unknown
}

struct SystemMediaPlaybackSnapshot: Equatable {
    let state: SystemMediaPlaybackState
    let processID: pid_t?

    static let unknown = SystemMediaPlaybackSnapshot(state: .unknown, processID: nil)
}

protocol SystemMediaPlaybackStateProviding {
    func fetchSnapshot(completion: @escaping (SystemMediaPlaybackSnapshot) -> Void)
}
```

`MediaRemoteSystemPlaybackStateProvider` accepts an injected raw fetch closure for tests. It maps only raw `1`/`2` with PID greater than zero to known snapshots; everything else maps to `.unknown` with no PID.

Include the bridge header from `TypeSpeakerNativeASR.h`. In `build_native_app.sh`, compile `SystemMediaRemoteBridge.m` using Objective-C ARC and blocks, link its object into the main Swift executable, and delete it with other temporary objects.

- [x] **Step 6: Run GREEN for provider and boundary tests**

Run:

```bash
xcrun clang -O2 -fobjc-arc -fblocks \
  -target arm64-apple-macosx14.0 \
  -c native/SystemMediaRemoteBridge.m \
  -o /tmp/SystemMediaRemoteBridge.o
xcrun swiftc -parse-as-library \
  -target arm64-apple-macosx14.0 \
  -import-objc-header native/TypeSpeakerNativeASR.h \
  native/Sources/Infrastructure/Audio/SystemMediaPlaybackStateProvider.swift \
  native/Tests/SystemMediaPlaybackStateProviderCheck.swift \
  /tmp/SystemMediaRemoteBridge.o \
  -framework Foundation \
  -o /tmp/typewhale-media-state-provider-check
/tmp/typewhale-media-state-provider-check
bash native/Tests/SystemMediaRemoteBridgeBoundaryCheck.sh
```

Expected: `SystemMediaPlaybackStateProviderCheck passed` and `SystemMediaRemoteBridgeBoundaryCheck passed`.

- [x] **Step 7: Review Task 1 and reserve it for the build commit**

Run `git diff --check` and confirm no protected path is staged. Keep Task 1 in the owned working diff until Task 3 completes the required full build/install verification, then include it in the one commit corresponding to that unique build. This repository rule overrides the generic frequent-commit cadence.

```bash
git diff --check -- native/SystemMediaRemoteBridge.h native/SystemMediaRemoteBridge.m \
  native/Sources/Infrastructure/Audio/SystemMediaPlaybackStateProvider.swift \
  native/Tests/SystemMediaPlaybackStateProviderCheck.swift \
  native/Tests/SystemMediaRemoteBridgeBoundaryCheck.sh \
  native/TypeSpeakerNativeASR.h native/build_native_app.sh
```

---

### Task 2: Make media pause/resume state-aware

**Files:**
- Modify: `native/Sources/Infrastructure/Audio/SystemMediaPlaybackController.swift`
- Modify: `native/Tests/SystemMediaPlaybackControllerCheck.swift`

**Interfaces:**
- Consumes: `SystemMediaPlaybackStateProviding.fetchSnapshot(completion:)`.
- Preserves: `pauseIfNeeded(enabled:)`, `resume()`, `SyntheticMediaKeyEvent.postPlayPause()`, and the TypeWhale event marker.
- Produces: generation-guarded pause ownership stored as one nonzero `ownedProcessID`.

- [x] **Step 1: Replace blind-toggle expectations with failing state-machine tests**

Add a manual provider that queues completion closures and resolves them with exact snapshots. Cover these observable sequences:

```swift
// Paused before start: never emit.
controller.pauseIfNeeded(enabled: true)
provider.resolveNext(.init(state: .paused, processID: 101))
controller.resume()
precondition(emissionCount == 0)

// Playing then same-process paused: pause once, resume once.
controller.pauseIfNeeded(enabled: true)
provider.resolveNext(.init(state: .playing, processID: 202))
controller.resume()
scheduler.runNext()
provider.resolveNext(.init(state: .paused, processID: 202))
precondition(emissionCount == 2)
```

Also require: unknown start no-op, changed PID at resume no-op, missing PID no-op, user-resumed `playing` no-op at finish, late start callback ignored after cleanup, older callback ignored after replacement, failed pause emission does not create ownership, duplicate cleanup schedules once, and consecutive recording emits no intermediate resume.

- [x] **Step 2: Run RED against the existing blind controller**

Run:

```bash
xcrun swiftc -framework AppKit -framework ApplicationServices \
  native/Sources/Core/AppBrand.swift \
  native/Sources/Infrastructure/Diagnostics/LaunchDiagnostics.swift \
  native/Sources/Infrastructure/Audio/SystemMediaPlaybackStateProvider.swift \
  native/Sources/Infrastructure/Audio/SystemMediaPlaybackController.swift \
  native/Tests/SystemMediaPlaybackControllerCheck.swift \
  /tmp/SystemMediaRemoteBridge.o \
  -import-objc-header native/TypeSpeakerNativeASR.h \
  -o /tmp/typewhale-system-media-controller-check
/tmp/typewhale-system-media-controller-check
```

Expected: failure because the existing controller emits before any playback snapshot and has no process ownership.

- [x] **Step 3: Implement generation-guarded start decisions**

Inject `SystemMediaPlaybackStateProviding`, store `recordingActive`, `ownedProcessID`, `resumeWorkItem`, and `generation`.

At enabled start:

```swift
recordingActive = true
cancelPendingResumeAndAdvanceGeneration()
guard ownedProcessID == nil else { return }
let requestGeneration = generation
stateProvider.fetchSnapshot { [weak self] snapshot in
    guard let self,
          self.generation == requestGeneration,
          self.recordingActive,
          self.ownedProcessID == nil,
          snapshot.state == .playing,
          let processID = snapshot.processID,
          processID > 0 else { return }
    guard self.emitPlayPause() else { return }
    self.ownedProcessID = processID
}
```

Disabled starts remain no-ops and do not strand/cancel ownership from an earlier enabled recording.

- [x] **Step 4: Implement state-aware delayed resume**

`resume()` always marks the current recording inactive and advances generation to invalidate an unresolved start query. When ownership exists, schedule one delayed callback. At that callback query a fresh snapshot and emit only for `.paused` with the same PID:

```swift
let ownedPID = ownedProcessID
stateProvider.fetchSnapshot { [weak self] snapshot in
    guard let self,
          self.generation == requestGeneration,
          !self.recordingActive,
          self.ownedProcessID == ownedPID else { return }
    self.ownedProcessID = nil
    guard snapshot.state == .paused,
          snapshot.processID == ownedPID else { return }
    _ = self.emitPlayPause()
}
```

`playing`, `unknown`, missing PID, or changed PID clears ownership without sending an event. A new recording invalidates delayed/query callbacks and retains existing ownership for the final cleanup.

- [x] **Step 5: Run GREEN and shortcut isolation regressions**

Run the Task 2 command and:

```bash
bash native/Tests/SyntheticMediaHotkeyCaptureBoundaryCheck.sh
bash native/Tests/RecordingAudioPolicyCoordinatorBoundaryCheck.sh
bash native/Tests/RecordingAudioPolicySettingsBoundaryCheck.sh
```

Compile and run `SyntheticMediaHotkeyIsolationCheck.swift`, `OpenClawHotkeyCheck.swift`, and `HotkeyComboReleaseCheck.swift` with their existing domain/hotkey sources plus the media provider/controller bridge. Expected: every check prints `passed`.

- [x] **Step 6: Review Task 2 and reserve it for the build commit**

Run `git diff --check` for the controller and its test. Keep Task 2 in the owned working diff until Task 3 completes full build/install verification.

```bash
git diff --check -- \
  native/Sources/Infrastructure/Audio/SystemMediaPlaybackController.swift \
  native/Tests/SystemMediaPlaybackControllerCheck.swift
```

---

### Task 3: Complete regression, interaction review, milestone record, and installed build

**Files:**
- Modify: `docs/开发日志.md`
- Modify: `native/Sources/Presentation/VersionHistory/VersionHistoryViewController.swift`
- Modify: `docs/superpowers/plans/2026-08-11-state-aware-recording-media-control.md` checkboxes/evidence
- Modify automatically: `README.md`
- Modify automatically: `macos/README.md`
- Modify automatically: `docs/构建日志.md`
- Modify automatically: `native/build_native_app.sh` build number

**Interfaces:**
- Consumes: completed provider and state-aware controller.
- Produces: a uniquely numbered installed build, milestone narrative, verification evidence, and one final owned-files commit.

- [x] **Step 1: Run the complete focused suite before documentation/build**

Run Task 1 and Task 2 GREEN commands plus:

```bash
xcrun swiftc \
  native/Sources/Infrastructure/Audio/OutputAudioDucker.swift \
  native/Tests/OutputAudioDuckerCheck.swift \
  -o /tmp/typewhale-output-audio-ducker-check
/tmp/typewhale-output-audio-ducker-check
bash native/Tests/PauseAutoFinishSettingsBoundaryCheck.sh
bash native/Tests/AudioRecorderFinalizationBoundaryCheck.sh
bash native/Tests/OpenClawContinuousActivationCheck.sh
xcrun swiftc -parse-as-library \
  native/Sources/Domain/HotkeyDomain.swift \
  native/Tests/HotkeyEscapeCancellationCheck.swift \
  -o /tmp/HotkeyEscapeCancellationCheck
/tmp/HotkeyEscapeCancellationCheck
git diff --check
```

Expected: every executable/check passes and `git diff --check` is silent.

- [x] **Step 2: Perform the required interaction/design review**

Use the `design-review` skill to review the changed interaction, even though no row/layout changes are expected. Verify wording remains truthful, the default-off switch remains visible, paused-state behavior no longer contradicts its label, failure fallback is silent, consecutive-recording timing has no playback blip, and OpenClaw shortcut isolation remains intact. Any P0/P1 finding returns to a failing test before correction.

Evidence: the strict clean-tree audit could not own the repository because protected Smart Rewrite and capsule concept dirt must not be committed or stashed. The safe bounded interaction review used the installed-setting baseline plus the new state-machine/shortcut regression suite. It found one inaccurate help string in Build 887, fixed it test-first, and confirmed Build 888 exposes the truthful state-aware wording with no remaining P0/P1 finding.

- [x] **Step 3: Add the small milestone narrative before building**

Read the current build number immediately before editing. Add the next unique build entry to both `docs/开发日志.md` and `VersionHistoryViewController.swift`, using the actual current build plus one. Record:

- blind toggle replaced by confirmed playing-state detection;
- stable process identity required for owned resume;
- paused/unknown/changed-player states fail closed;
- user manual playback and physical media-key intent remain authoritative;
- private MediaRemote is dynamically loaded and is a direct-distribution Beta boundary, not a Mac App Store path;
- automated and installed-app acceptance evidence.

- [x] **Step 4: Re-run concurrency checks and build through the only supported entry point**

Run:

```bash
git branch --show-current
git status --short
pgrep -af 'build_and_log\.sh|release_local_build\.sh|build_native_app\.sh|swiftc|xcodebuild' || true
./native/build_and_log.sh
```

Expected: correct Pro ASR branch, only protected unrelated dirt plus owned task files, no external build process, and build/install/open succeeds. If the build guard reports a concurrent build-number change, update both narrative entries to the newly required build and retry.

Evidence: the branch was `codex/typewhale-pro-asr-hotwords`; no external build process was active; protected unrelated dirt remained untouched. `./native/build_and_log.sh` produced, installed, opened, and logged `2.0.58 (888)` as build #385.

- [x] **Step 5: Verify installed version, signature, process, and safe runtime probe**

Run:

```bash
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
  '/Applications/TypeWhale Pro.app/Contents/Info.plist'
/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' \
  '/Applications/TypeWhale Pro.app/Contents/Info.plist'
codesign --verify --deep --strict '/Applications/TypeWhale Pro.app'
pgrep -af '/Applications/TypeWhale Pro.app/Contents/MacOS/TypeWhalePro'
```

Run a read-only bridge probe while media is paused and verify it never sends a media key. Use the real installed app for manual acceptance of paused start, playing pause/resume, manual resume, replacement player, rapid consecutive recording, disabled switch, and OpenClaw physical media key. If physical hardware or active-media control cannot be automated safely, report that exact residual check rather than changing the user's current playback blindly.

Evidence: the installed plist reports `2.0.58` / `888`; deep strict signature verification passed; the installed executable was running. The read-only bridge probe returned `runtimeSnapshot state=unknown pid=0` without emitting a media key. The Build 888 accessibility tree confirmed the default-off switch and corrected help text. Real-player mutation and physical hardware remain explicit manual acceptance items.

- [x] **Step 6: Re-run fresh verification after build**

Repeat the complete focused suite from Step 1, `git diff --check`, installed version/signature checks, and source privacy boundary. Completion claims require this fresh post-build evidence.

Evidence: provider mapping, private-bridge boundary/privacy, state-aware controller, synthetic media/OpenClaw isolation, combo release, output audio ducking, settings/coordinator/capture/finalization/pause-auto-finish/OpenClaw-continuous boundaries, and `git diff --check` passed after Build 888. Installed version, signature, process, and accessibility help were rechecked against `/Applications/TypeWhale Pro.app`.

- [x] **Step 7: Commit only owned milestone/build files**

Run `git status --short`, `git diff --name-only`, and `git diff --cached --name-only`. Stage the exact remaining files from Tasks 1–3 and build outputs, reject any protected path, then commit:

```bash
git commit -m "fix(audio): make recording media control state-aware"
```

The final handoff must include **改了什么** and **测试方案**, the installed version/build, commit IDs, automated evidence, private-API distribution boundary, and any unautomated real-player/hardware check.

Evidence: the final explicit staging list excludes the protected Smart Rewrite file, `.artifacts/`, `.superpowers/`, capsule concept gallery, and capsule concept sources. This checked plan is included in the same build-corresponding commit `fix(audio): make recording media control state-aware`.
