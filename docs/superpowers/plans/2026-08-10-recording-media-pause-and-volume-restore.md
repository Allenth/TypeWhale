# Recording Media Pause and Volume Restore Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Preserve the first system-volume baseline across consecutive recordings and add an opt-in, paired system-media pause/resume control that cannot trigger TypeWhale's own media-key shortcuts.

**Architecture:** Keep CoreAudio ownership in `OutputAudioDucker`, but retain mutable per-control snapshots through delayed restoration and invalidate stale callbacks with generations. Add a focused `SystemMediaPlaybackController` that emits marked play/pause key pairs and coalesces consecutive recording sessions; wire both policies into the existing start/cleanup lifecycle. Persist and present the new setting through the existing `MainViewSettings` boundary.

**Tech Stack:** Swift, AppKit, ApplicationServices/CoreGraphics, CoreAudio, Dispatch, shell boundary checks, native TypeWhale build/install scripts.

## Global Constraints

- Work only on `codex/typewhale-pro-asr-hotwords` in `$HOME/Pictures/macOSwinOSCoding/TypeSpeaker`.
- Preserve unrelated dirty Smart Rewrite, `.artifacts`, `.superpowers`, capsule gallery, and capsule concept files.
- Do not use private `MediaRemote`, per-player AppleScript, Python, Homebrew, or new dependencies.
- Both settings default to off independently; existing 5% duck target remains unchanged.
- Physical headset play-key bindings must keep working; generated media events must bypass every TypeWhale shortcut path.
- Recording, ASR, paste, translation, screenshot, and OpenClaw semantics remain unchanged beyond shared start/cleanup policy calls.
- Every RED test must be observed failing for the intended reason before production implementation.
- Before build, add the `2.0.58 (Build 886)` narrative to `docs/开发日志.md` and `VersionHistoryViewController.swift`; if another build bumps first, recalculate and update both entries.
- Final validation must use `./native/build_and_log.sh`, install `/Applications/TypeWhale Pro.app`, verify signing, and commit only task-owned files.

---

### Task 1: Preserve the first volume baseline across consecutive recordings

**Files:**
- Modify: `native/Sources/Infrastructure/Audio/OutputAudioDucker.swift`
- Create: `native/Tests/OutputAudioDuckerCheck.swift`

**Interfaces:**
- Consumes: existing `duckIfNeeded(enabled: Bool)`, `restore()`, CoreAudio volume controls.
- Produces: the same public API plus an internal injectable initializer for fake volume access and scheduling.

- [x] **Step 1: Write the failing behavioral test**

Create a fake volume control at `0.70`, collect scheduled `DispatchWorkItem`s, and assert this sequence:

```swift
ducker.duckIfNeeded(enabled: true) // 0.70 -> 0.05
ducker.restore()                   // delayed; must retain 0.70
ducker.duckIfNeeded(enabled: true) // cancel restore; remain 0.05
ducker.restore()
scheduler.runAll()
precondition(abs(volume - 0.70) < 0.001)
```

Add two cases in the same executable: a manually changed volume becomes the next baseline, and `enabled: false` does not cancel an already scheduled restore.

- [x] **Step 2: Run RED and verify the current implementation fails on 0.05**

Run:

```bash
xcrun swiftc \
  native/Sources/Infrastructure/Audio/OutputAudioDucker.swift \
  native/Tests/OutputAudioDuckerCheck.swift \
  -o /tmp/typewhale-output-audio-ducker-check
/tmp/typewhale-output-audio-ducker-check
```

Expected: FAIL because the second `duckIfNeeded` captures `0.05` as `originalVolume`, or because the required injectable initializer does not exist before production changes.

- [x] **Step 3: Implement retained snapshot ownership**

Use a reference snapshot that tracks the last value TypeWhale wrote:

```swift
private final class VolumeSnapshot {
    let deviceID: AudioDeviceID
    let element: AudioObjectPropertyElement
    let originalVolume: Float32
    let duckedVolume: Float32
    var lastAppliedVolume: Float32
}
```

Add injected closures for control discovery, read, write, and delayed scheduling, with defaults wrapping the existing static CoreAudio methods. Move `guard enabled else { return }` before restore cancellation. On enabled starts, reconcile retained snapshots against `lastAppliedVolume`; retain the first baseline when values match and create a fresh baseline only after a user override. Keep snapshots through `restore()`, increment a generation in `cancelPendingRestore()`, guard every callback by that generation, update `lastAppliedVolume` after each ramp write, and remove a snapshot only after its final step or a detected user override/read failure.

- [x] **Step 4: Run GREEN and relevant source checks**

Run the command from Step 2. Expected: `OutputAudioDuckerCheck passed`.

Also run:

```bash
git diff --check -- native/Sources/Infrastructure/Audio/OutputAudioDucker.swift native/Tests/OutputAudioDuckerCheck.swift
```

Expected: no output.

---

### Task 2: Add coalesced paired system-media control

**Files:**
- Create: `native/Sources/Infrastructure/Audio/SystemMediaPlaybackController.swift`
- Create: `native/Tests/SystemMediaPlaybackControllerCheck.swift`

**Interfaces:**
- Produces: `SystemMediaPlaybackController.pauseIfNeeded(enabled: Bool)`, `resume()`, and `SyntheticMediaKeyEvent.isTypeWhaleGenerated(_:)`.
- Consumes later: `HotkeyMonitor` uses the synthetic marker; `SpeechInputCoordinator` uses pause/resume.

- [x] **Step 1: Write the failing controller test**

Inject an emitter counter and manual scheduler. Verify:

```swift
controller.pauseIfNeeded(enabled: true)
controller.resume()
controller.pauseIfNeeded(enabled: true) // cancels pending resume, emits nothing
controller.resume()
scheduler.runAll()
precondition(emissionCount == 2) // first pause + final resume only
```

Also verify disabled start emits zero, duplicate `resume()` schedules once, a cancelled generation cannot emit, and both generated down/up events carry the nonzero TypeWhale marker.

- [x] **Step 2: Run RED**

Run:

```bash
xcrun swiftc -framework AppKit -framework ApplicationServices \
  native/Tests/SystemMediaPlaybackControllerCheck.swift \
  -o /tmp/typewhale-system-media-controller-check
```

Expected: FAIL with missing `SystemMediaPlaybackController` and `SyntheticMediaKeyEvent`.

- [x] **Step 3: Implement the controller and event emitter**

Use one owned interval, one pending work item, and a generation:

```swift
func pauseIfNeeded(enabled: Bool) {
    guard enabled else { return }
    cancelPendingResume()
    guard !ownsPairedToggle else { return }
    if emitPlayPause() { ownsPairedToggle = true }
}

func resume() {
    guard ownsPairedToggle, resumeWorkItem == nil else { return }
    scheduleGenerationGuardedResume()
}
```

Create system-defined play-key down/up events with subtype `8`, key code `16`, key states `0x0A`/`0x0B`, and set `.eventSourceUserData` to a TypeWhale-specific `Int64` marker before posting to `.cghidEventTap`. Event-creation/posting failure logs diagnostics and never throws into recording.

- [x] **Step 4: Run GREEN**

Run:

```bash
xcrun swiftc -framework AppKit -framework ApplicationServices \
  native/Sources/Infrastructure/Audio/SystemMediaPlaybackController.swift \
  native/Tests/SystemMediaPlaybackControllerCheck.swift \
  -o /tmp/typewhale-system-media-controller-check
/tmp/typewhale-system-media-controller-check
```

Expected: `SystemMediaPlaybackControllerCheck passed` and no real playback change because tests inject the emitter.

---

### Task 3: Isolate generated media events from TypeWhale shortcuts

**Files:**
- Modify: `native/Sources/Infrastructure/Hotkey/HotkeyMonitor.swift`
- Modify: `native/Sources/Presentation/Main/MainViewController+HotkeyCapture.swift`
- Create: `native/Tests/SyntheticMediaHotkeyIsolationCheck.swift`
- Create: `native/Tests/SyntheticMediaHotkeyCaptureBoundaryCheck.sh`

**Interfaces:**
- Consumes: `SyntheticMediaKeyEvent.isTypeWhaleGenerated(_:)` from Task 2.
- Preserves: unmarked physical media-key handling and `.mediaPlay` bindings.

- [x] **Step 1: Write RED tests for OpenClaw isolation**

Configure `HotkeyMonitor` with `.mediaPlayBinding` for OpenClaw. Pass a marked media down event to `handleSystemDefined(event:)` and assert `onDown` is not called; pass an identical unmarked event and assert OpenClaw is called once. Add a shell boundary test that requires both CGEvent and NSEvent hotkey-capture paths to reject the marker before calling `captureMediaPlay`.

- [x] **Step 2: Run RED**

Run:

```bash
xcrun swiftc -framework AppKit -framework ApplicationServices \
  native/Sources/Domain/AutoSendCountdownDomain.swift \
  native/Sources/Domain/HotkeyDomain.swift \
  native/Sources/Domain/SpeechInputPurpose.swift \
  native/Sources/Infrastructure/Audio/SystemMediaPlaybackController.swift \
  native/Sources/Infrastructure/Hotkey/HotkeyMonitor.swift \
  native/Tests/SyntheticMediaHotkeyIsolationCheck.swift \
  -o /tmp/typewhale-synthetic-media-hotkey-check
/tmp/typewhale-synthetic-media-hotkey-check
bash native/Tests/SyntheticMediaHotkeyCaptureBoundaryCheck.sh
```

Expected: FAIL because `handleSystemDefined` is private and/or does not inspect the marker, and capture paths do not yet guard it.

- [x] **Step 3: Add marker guards before shortcut matching**

Make `handleSystemDefined(event:)` internal for the focused test and start it with:

```swift
guard !SyntheticMediaKeyEvent.isTypeWhaleGenerated(event) else { return false }
```

Add the equivalent early return in `capture(event:type:)` and in `capture(event: NSEvent)` by reading `event.cgEvent`. Return `false` from the global monitor so generated events continue to the system media destination without entering TypeWhale actions.

- [x] **Step 4: Run GREEN and existing hotkey regressions**

Run the Step 2 commands, then compile/run `OpenClawHotkeyCheck.swift` and `HotkeyComboReleaseCheck.swift` with the same domain/infrastructure source set. Expected: all checks print `passed`.

---

### Task 4: Persist, present, and wire the new option

**Files:**
- Modify: `native/Sources/Infrastructure/Settings/AppSettings.swift`
- Modify: `native/Sources/Presentation/Main/MainViewController.swift`
- Modify: `native/Sources/Presentation/Main/MainViewController+Actions.swift`
- Modify: `native/Sources/Presentation/Main/MainViewController+Configuration.swift`
- Modify: `native/Sources/Presentation/Main/MainViewController+PanelLayout.swift`
- Modify: `native/Sources/Application/SpeechInputCoordinator.swift`
- Create: `native/Tests/RecordingAudioPolicySettingsBoundaryCheck.sh`
- Create: `native/Tests/RecordingAudioPolicyCoordinatorBoundaryCheck.sh`

**Interfaces:**
- Produces: `MainViewSettings.pauseSystemMediaWhileRecordingEnabled` and `MainViewController.pauseSystemMediaWhileRecordingEnabled`.
- Consumes: `SystemMediaPlaybackController.pauseIfNeeded(enabled:)` and `.resume()`.

- [x] **Step 1: Write RED source-boundary checks**

Require the new property/key in load and save, the `BrandSwitch` property and initialization, the row label, accessibility label and tooltip, the controller computed property, one `SystemMediaPlaybackController` instance, exactly one start call near `duckIfNeeded`, and exactly one cleanup call near `outputAudioDucker.restore()`.

- [x] **Step 2: Run RED**

Run:

```bash
bash native/Tests/RecordingAudioPolicySettingsBoundaryCheck.sh
bash native/Tests/RecordingAudioPolicyCoordinatorBoundaryCheck.sh
```

Expected: FAIL because the new setting and lifecycle calls do not exist.

- [x] **Step 3: Add settings and UI wiring**

Add `pauseSystemMediaWhileRecordingEnabled: Bool` beside the duck setting in `MainViewSettings`, persist it under `pauseSystemMediaWhileRecording`, add `let pauseSystemMedia = BrandSwitch()`, load/save it independently, expose the computed property, and render:

```swift
optionRow("录音时暂停媒体", pauseSystemMedia)
```

Set the accessibility label to the same copy and tooltip to `录音开始和结束时切换当前系统媒体；适用于录音前正在播放的内容。`.

- [x] **Step 4: Add shared lifecycle wiring**

Instantiate one controller beside `outputAudioDucker`. At recording start call:

```swift
systemMediaPlaybackController.pauseIfNeeded(
    enabled: controller.pauseSystemMediaWhileRecordingEnabled
)
```

In `clearActiveRecording`, call `systemMediaPlaybackController.resume()` beside `outputAudioDucker.restore()`. Do not add purpose-specific OpenClaw branches.

- [x] **Step 5: Run GREEN plus settings regressions**

Run both new shell checks and `bash native/Tests/PauseAutoFinishSettingsBoundaryCheck.sh`. Expected: all print `passed`.

---

### Task 5: Document, review, and verify the production behavior

**Files:**
- Modify: `docs/开发日志.md`
- Modify: `native/Sources/Presentation/VersionHistory/VersionHistoryViewController.swift`
- Modify automatically by build: `native/build_native_app.sh`
- Modify automatically by build: `docs/构建日志.md`
- Modify: this plan's checkboxes/evidence notes if needed.

- [x] **Step 1: Run the complete focused test set**

Run Tasks 1–4 commands and:

```bash
bash native/Tests/AudioRecorderFinalizationBoundaryCheck.sh
bash native/Tests/HotkeyEscapeCancellationCheck.sh
bash native/Tests/OpenClawContinuousActivationCheck.sh
git diff --check
```

Expected: all checks pass and `git diff --check` is silent.

- [x] **Step 2: Add release narrative before building**

Add the top development-log and version-history entries for `2.0.58 (Build 886)`, covering the retained first volume baseline, coalesced media pause/resume, synthetic-event/OpenClaw isolation, and tests. If current build is no longer 885, use current build + 1 consistently instead of 886.

- [x] **Step 3: Use the `design-review` skill for the settings UI**

Review row order, copy, tooltip, accessibility, spacing, and whether the two independent switches communicate their distinct effects. Capture the installed settings page if desktop tooling permits. Any P0/P1 finding returns to a new RED test before correction.

- [x] **Step 4: Re-run concurrency safety checks**

Run:

```bash
git branch --show-current
git status --short
pgrep -af 'build_and_log\.sh|release_local_build\.sh|build_native_app\.sh|swiftc|xcodebuild' || true
```

Expected: correct branch, only protected pre-existing dirt plus this task's files, and no external build process.

- [x] **Step 5: Build, install, open, and verify signature/version**

Run:

```bash
./native/build_and_log.sh
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' '/Applications/TypeWhale Pro.app/Contents/Info.plist'
/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' '/Applications/TypeWhale Pro.app/Contents/Info.plist'
codesign --verify --deep --strict '/Applications/TypeWhale Pro.app'
```

Expected: build/install/open succeeds, version remains `2.0.58`, build is `886` unless concurrency required a higher recalculated value, and codesign exits 0.

- [x] **Step 6: Perform installed-app acceptance where automatable**

Verify the new switch appears and defaults off. Use Apple Music/browser playback to confirm pause, delayed resume, and no intermediate resume on rapid consecutive recording. Bind OpenClaw to a normal key and to the headset play key; generated media events must not activate it, while a physical headset press still does. If physical hardware cannot be automated, record that precise residual manual check in the final handoff.

- [x] **Step 7: Review scope and commit only owned files**

Run `git status --short`, `git diff --name-only`, and `git diff --cached --name-only`. Stage the exact files listed in Tasks 1–5, excluding all protected dirt, then commit:

```bash
git commit -m "fix(audio): preserve recording media state"
```

Expected: one code/build commit containing tests, production changes, version/build narrative, and build log; protected unrelated files remain uncommitted.
