# Primary Microphone Hot Switching Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Common settings page the single “主麦克风” control and let a running recording immediately switch to another CoreAudio input without losing the session or previously captured audio.

**Architecture:** Keep device discovery in `AudioInputDeviceProvider`, extract deterministic route-selection and switch-generation logic into focused pure Swift types, and upgrade `AudioRecorder` to convert every hardware input into one canonical PCM format before it reaches WAV, preview, waveform, or VAD. `SpeechInputCoordinator` owns product feedback and tells the active recorder to switch; the recorder owns serialized engine/tap replacement and recovery.

**Tech Stack:** Swift, AppKit, AVFAudio (`AVAudioEngine`, `AVAudioConverter`, `AVAudioFile`), CoreAudio, shell/Swift regression checks, existing native release scripts.

## Global Constraints

- A manual device disconnect permanently saves “跟随系统”; reconnecting it must not restore or auto-select it.
- A recording-time manual selection takes effect immediately in the same task, with an accepted 0.3–1 second capture gap and no loss of already captured audio.
- ASR, Silero VAD, realtime-preview authority, long-form transcript authority, smart processing, and paste semantics must not change.
- Do not add simultaneous dual-microphone capture, per-feature microphones, or continuous listening.
- Device enumeration and route observation remain lazy so idle TypeWhale does not hold the microphone stack active.
- Do not log transcript text, audio paths, or persistent raw device identifiers.
- Any code change requires concurrency re-check, build-number handling through `./native/build_and_log.sh`, installation to `/Applications/TypeWhale.app`, signature verification, app launch, and installation-path testing.
- UI work requires `design-review` and installed-app visual verification; missing second-device coverage must be reported explicitly.

---

## File Structure

- Create `native/Sources/Infrastructure/Audio/AudioInputRoutePolicy.swift`: pure route-selection, disconnect fallback, and latest-generation decisions.
- Modify `native/Sources/Infrastructure/Audio/AudioInputDevice.swift`: expose stable UID/name lookup and return typed selection resolution without scattering persistence side effects.
- Create `native/Sources/Infrastructure/Audio/CanonicalAudioConverter.swift`: canonical format and per-device buffer conversion.
- Modify `native/Sources/Infrastructure/Audio/AudioRecorder.swift`: serialized hot-switch lifecycle, one canonical writer, recovery, and route events.
- Modify `native/Sources/Application/SpeechInputCoordinator.swift`: connect active UI selection to recorder switching and present product-level status.
- Modify `native/Sources/Presentation/Main/MainViewController.swift`: add a status label and a dedicated selection callback.
- Modify `native/Sources/Presentation/Main/MainViewController+Configuration.swift`: lazy device menu and state rendering.
- Modify `native/Sources/Presentation/Main/MainViewController+Actions.swift`: save selection and emit a selection intent without conflating it with unrelated settings.
- Modify `native/Sources/Presentation/Main/MainViewController+PanelLayout.swift`: render “主麦克风” as a lead Common-page group and remove the old System-row duplicate.
- Create `native/Tests/AudioInputRoutePolicyCheck.swift`: pure selection, disconnect, generation, and recovery checks.
- Create `native/Tests/CanonicalAudioConverterCheck.swift`: 44.1/48 kHz and mono/stereo conversion checks.
- Create `native/Tests/PrimaryMicrophoneUIBoundaryCheck.sh`: single-entry/copy/callback source boundary.
- Modify `docs/ARCHITECTURE.md`, `docs/开发日志.md`, `README.md`, `README_macOS.md` (if present), `native/Sources/Presentation/VersionHistory/VersionHistoryViewController.swift`: behavior and release record.

---

### Task 1: Deterministic Input-Route Policy

**Files:**
- Create: `native/Sources/Infrastructure/Audio/AudioInputRoutePolicy.swift`
- Modify: `native/Sources/Infrastructure/Audio/AudioInputDevice.swift`
- Test: `native/Tests/AudioInputRoutePolicyCheck.swift`

**Interfaces:**
- Consumes: `[AudioInputDevice]`, selected UID, current system-default UID, and monotonically increasing selection generation.
- Produces: `AudioInputSelectionResolution`, `AudioInputSwitchIntent`, and `AudioInputSwitchGeneration.accepts(_:)` for the recorder and coordinator.

- [ ] **Step 1: Write the failing pure-policy check**

```swift
import Foundation

@main
struct AudioInputRoutePolicyCheck {
    static func main() {
        let builtIn = AudioInputDevice(id: 1, uid: "builtin", name: "MacBook Microphone", isDefault: true)
        let usb = AudioInputDevice(id: 2, uid: "usb", name: "USB Mic", isDefault: false)

        precondition(AudioInputRoutePolicy.resolve(selectedUID: "usb", devices: [builtIn, usb], defaultDeviceID: 1) == .manual(usb))
        precondition(AudioInputRoutePolicy.resolve(selectedUID: "usb", devices: [builtIn], defaultDeviceID: 1) == .downgradeToSystemDefault(builtIn))
        precondition(AudioInputRoutePolicy.resolve(selectedUID: "", devices: [builtIn], defaultDeviceID: 1) == .systemDefault(builtIn))
        precondition(AudioInputRoutePolicy.resolve(selectedUID: "", devices: [], defaultDeviceID: nil) == .unavailable)

        var generation = AudioInputSwitchGeneration()
        let first = generation.issue(targetUID: "usb")
        let latest = generation.issue(targetUID: "builtin")
        precondition(!generation.accepts(first))
        precondition(generation.accepts(latest))
    }
}
```

- [ ] **Step 2: Compile to verify the policy test fails**

Run:

```bash
swiftc native/Sources/Infrastructure/Audio/AudioInputDevice.swift native/Tests/AudioInputRoutePolicyCheck.swift -o /tmp/AudioInputRoutePolicyCheck
```

Expected: compilation fails because `AudioInputRoutePolicy` and `AudioInputSwitchGeneration` do not exist.

- [ ] **Step 3: Add typed policy and side-effect-free resolution**

Implement these exact public internal interfaces in `AudioInputRoutePolicy.swift`:

```swift
enum AudioInputSelectionResolution: Equatable {
    case systemDefault(AudioInputDevice)
    case manual(AudioInputDevice)
    case downgradeToSystemDefault(AudioInputDevice)
    case unavailable
}

struct AudioInputSwitchIntent: Equatable {
    let generation: UInt64
    let targetUID: String
}

struct AudioInputSwitchGeneration {
    private(set) var latest: UInt64 = 0
    mutating func issue(targetUID: String) -> AudioInputSwitchIntent {
        latest &+= 1
        return AudioInputSwitchIntent(generation: latest, targetUID: targetUID)
    }
    func accepts(_ intent: AudioInputSwitchIntent) -> Bool { intent.generation == latest }
}

enum AudioInputRoutePolicy {
    static func resolve(
        selectedUID: String,
        devices: [AudioInputDevice],
        defaultDeviceID: AudioDeviceID?
    ) -> AudioInputSelectionResolution
}
```

Move persistence out of `resolveSelectedManualDevice()`: a missing manual UID returns `.downgradeToSystemDefault`; the coordinator/UI caller performs the one explicit save of `systemDefaultUID` and renders the message.

- [ ] **Step 4: Run the pure-policy check**

Run:

```bash
swiftc native/Sources/Infrastructure/Audio/AudioInputDevice.swift native/Sources/Infrastructure/Audio/AudioInputRoutePolicy.swift native/Tests/AudioInputRoutePolicyCheck.swift -o /tmp/AudioInputRoutePolicyCheck && /tmp/AudioInputRoutePolicyCheck
```

Expected: exit 0 with no precondition failure.

- [ ] **Step 5: Commit the route policy**

```bash
git add native/Sources/Infrastructure/Audio/AudioInputDevice.swift native/Sources/Infrastructure/Audio/AudioInputRoutePolicy.swift native/Tests/AudioInputRoutePolicyCheck.swift
git commit -m "feat: define primary microphone route policy"
```

---

### Task 2: Canonical Audio Conversion

**Files:**
- Create: `native/Sources/Infrastructure/Audio/CanonicalAudioConverter.swift`
- Test: `native/Tests/CanonicalAudioConverterCheck.swift`

**Interfaces:**
- Consumes: an input `AVAudioPCMBuffer` in the currently bound hardware format.
- Produces: `CanonicalAudioConverter.format` and `convert(_:) -> AVAudioPCMBuffer`, used unchanged by WAV, snapshots, waveform, and VAD.

- [ ] **Step 1: Write conversion checks for representative hardware formats**

Create buffers containing deterministic non-zero samples and assert canonical output:

```swift
import AVFAudio

@main
struct CanonicalAudioConverterCheck {
    static func main() throws {
        for (rate, channels) in [(44_100.0, AVAudioChannelCount(1)), (48_000.0, AVAudioChannelCount(2))] {
            let inputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: channels, interleaved: false)!
            let input = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: AVAudioFrameCount(rate / 10))!
            input.frameLength = input.frameCapacity
            for channel in 0..<Int(channels) {
                for frame in 0..<Int(input.frameLength) { input.floatChannelData![channel][frame] = 0.25 }
            }
            let converter = try CanonicalAudioConverter(inputFormat: inputFormat)
            let output = try converter.convert(input)
            precondition(output.format == CanonicalAudioConverter.format)
            precondition(output.frameLength > 0)
            precondition(output.floatChannelData![0][0] != 0)
        }
    }
}
```

- [ ] **Step 2: Compile to verify the converter check fails**

Run:

```bash
swiftc -framework AVFAudio native/Tests/CanonicalAudioConverterCheck.swift -o /tmp/CanonicalAudioConverterCheck
```

Expected: compilation fails because `CanonicalAudioConverter` does not exist.

- [ ] **Step 3: Implement the canonical converter**

Use one fixed, non-interleaved Float32 mono format compatible with the existing ASR/VAD path:

```swift
final class CanonicalAudioConverter {
    static let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
    private let converter: AVAudioConverter

    init(inputFormat: AVAudioFormat) throws
    func convert(_ input: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer
}
```

`convert(_:)` must size output by `ceil(Double(input.frameLength) * 16_000 / input.format.sampleRate) + 32`, provide input once from the AVAudioConverter block, accept `.haveData` and `.inputRanDry`, and throw a domain-specific error for `.error` or empty output.

- [ ] **Step 4: Run converter checks**

Run:

```bash
swiftc -framework AVFAudio native/Sources/Infrastructure/Audio/CanonicalAudioConverter.swift native/Tests/CanonicalAudioConverterCheck.swift -o /tmp/CanonicalAudioConverterCheck && /tmp/CanonicalAudioConverterCheck
```

Expected: exit 0; both 44.1 kHz mono and 48 kHz stereo cases produce non-empty 16 kHz mono Float32 buffers.

- [ ] **Step 5: Commit canonical conversion**

```bash
git add native/Sources/Infrastructure/Audio/CanonicalAudioConverter.swift native/Tests/CanonicalAudioConverterCheck.swift
git commit -m "feat: normalize microphone audio format"
```

---

### Task 3: Single-Session Recorder Hot Switch

**Files:**
- Modify: `native/Sources/Infrastructure/Audio/AudioRecorder.swift`
- Create: `native/Tests/AudioRecorderHotSwitchBoundaryCheck.sh`
- Modify: `native/Tests/SpeechInputCoordinatorBoundaryCheck.sh`

**Interfaces:**
- Consumes: `switchInput(to:intent:completion:)` with resolved `AudioDeviceID?` and the latest `AudioInputSwitchIntent`.
- Produces: `AudioInputSwitchResult` and `AudioInputRouteEvent` on the main queue; preserves the existing `start`, `stop`, `cancel`, preview, VAD, and level callbacks.

- [ ] **Step 1: Add a failing structural regression check**

The shell check must require these symbols and forbid the old cancel-on-route behavior:

```bash
grep -Fq 'func switchInput(' "$AUDIO"
grep -Fq 'CanonicalAudioConverter' "$AUDIO"
grep -Fq 'case switching' "$AUDIO"
grep -Fq 'switchGeneration' "$AUDIO"
! grep -Fq 'cancelForInputRouteChange(message)' "$AUDIO"
grep -Fq 'processingGroup.wait()' "$AUDIO"
```

- [ ] **Step 2: Run the boundary check to verify it fails**

Run: `bash native/Tests/AudioRecorderHotSwitchBoundaryCheck.sh`

Expected: non-zero because `switchInput` and the canonical converter are not wired.

- [ ] **Step 3: Convert the initial recording path to canonical buffers**

Create the authority file with `CanonicalAudioConverter.format.settings`. In the hardware tap, copy the hardware buffer, enqueue it, convert it through the converter belonging to the current route generation, then pass only the converted buffer to file writing, frame counting, peak/bands, VAD windows, realtime buffers, and experimental buffers. Keep current snapshot functions unchanged except that their format argument is always the canonical format.

- [ ] **Step 4: Implement serialized switching and typed results**

Add these interfaces:

```swift
enum AudioInputSwitchResult: Equatable {
    case switched(deviceName: String)
    case restoredPrevious(deviceName: String, error: String)
    case followedSystem(deviceName: String, error: String?)
    case unavailable(error: String)
    case superseded
}

enum AudioInputRouteEvent {
    case manualDeviceDisconnected(name: String)
    case systemDefaultChanged
    case engineConfigurationChanged
}

func switchInput(
    to deviceID: AudioDeviceID?,
    deviceName: String,
    intent: AudioInputSwitchIntent,
    completion: @escaping (AudioInputSwitchResult) -> Void
)
```

Run switching work on a dedicated serial `routeControlQueue`. Stop accepting only the old route generation, wait for `processingGroup`, remove the old tap, rebuild/bind the engine and converter, install exactly one new tap, restart, and accept new buffers without calling `state.begin()`. Keep accumulated frame count, `currentTaskID`, pending URL, chunk index, VAD state, and preview buffers.

- [ ] **Step 5: Replace route cancellation with route events**

For a missing manual UID, emit `.manualDeviceDisconnected`, allowing the coordinator to save follow-system and call `switchInput`. Preserve `shouldIgnoreStartupRouteChange` for same-device Bluetooth churn. A configuration notification for the current still-present device attempts an engine restart before escalating.

- [ ] **Step 6: Run recorder and existing audio boundary checks**

Run:

```bash
bash native/Tests/AudioRecorderHotSwitchBoundaryCheck.sh
bash native/Tests/SpeechInputCoordinatorBoundaryCheck.sh
bash native/Tests/BoundaryCenteredAudioSourceCheck.sh
bash native/Tests/PreviewPipelinePerformanceBoundaryCheck.sh
```

Expected: all print their passed message and exit 0.

- [ ] **Step 7: Commit recorder hot switching**

```bash
git add native/Sources/Infrastructure/Audio/AudioRecorder.swift native/Tests/AudioRecorderHotSwitchBoundaryCheck.sh native/Tests/SpeechInputCoordinatorBoundaryCheck.sh
git commit -m "feat: hot switch recording input devices"
```

---

### Task 4: Coordinator and Common-Page Product UI

**Files:**
- Modify: `native/Sources/Application/SpeechInputCoordinator.swift`
- Modify: `native/Sources/Presentation/Main/MainViewController.swift`
- Modify: `native/Sources/Presentation/Main/MainViewController+Configuration.swift`
- Modify: `native/Sources/Presentation/Main/MainViewController+Actions.swift`
- Modify: `native/Sources/Presentation/Main/MainViewController+PanelLayout.swift`
- Create: `native/Tests/PrimaryMicrophoneUIBoundaryCheck.sh`

**Interfaces:**
- Consumes: `onPrimaryMicrophoneSelection: ((String) -> Void)?`, recorder route events and switch results.
- Produces: one Common-page “主麦克风” group, persistent selected UID, and non-activating status/capsule feedback.

- [ ] **Step 1: Write the failing UI boundary check**

Require one visible copy and the callback:

```bash
grep -Fq 'onPrimaryMicrophoneSelection' "$MAIN"
grep -Fq 'inspectorGroup("主麦克风"' "$LAYOUT"
test "$(grep -o 'optionRow("主麦克风"\|inspectorGroup("主麦克风"' "$LAYOUT" | wc -l | tr -d ' ')" = "1"
! grep -Fq 'optionRow("输入设备"' "$LAYOUT"
grep -Fq '主麦克风已切换到' "$COORDINATOR"
grep -Fq '已断开，已改为跟随系统' "$COORDINATOR"
```

- [ ] **Step 2: Run the UI check to verify it fails**

Run: `bash native/Tests/PrimaryMicrophoneUIBoundaryCheck.sh`

Expected: non-zero because the dedicated group and callback are absent.

- [ ] **Step 3: Separate microphone selection from generic settings save**

Add to `MainViewController`:

```swift
let audioInputStatus = label("按需读取可用设备", size: 11, weight: .medium)
var onPrimaryMicrophoneSelection: ((String) -> Void)?
```

Point the popup action at `selectPrimaryMicrophone(_:)`. That action saves all current settings once, updates local status to “正在切换麦克风…”, and invokes `onPrimaryMicrophoneSelection?(selectedAudioInputDeviceUID)`. Other settings continue using `saveSettings()`.

- [ ] **Step 4: Build the single Common-page group**

Add `buildPrimaryMicrophoneContent()` returning the popup/refresh row plus `audioInputStatus`, insert `inspectorGroup("主麦克风", buildPrimaryMicrophoneContent(), prominence: .lead)` before screenshot/system in `.common`, and remove the old input-device row from `buildSystemSettingsContent()`.

- [ ] **Step 5: Wire coordinator switching and disconnect fallback**

During coordinator setup:

```swift
controller.onPrimaryMicrophoneSelection = { [weak self] uid in
    self?.switchPrimaryMicrophone(to: uid)
}
```

`switchPrimaryMicrophone(to:)` resolves the latest device list. If no recording is active, it updates the status for the next start. If active, it issues a new generation and calls `recorder.switchInput`. On success it updates card/capsule to “主麦克风已切换到 …”; on restored-previous it saves the old UID and rolls the menu back; on manual disconnect it saves `systemDefaultUID`, refreshes the menu, displays “已断开，已改为跟随系统”, and switches the same session to current system default. `.unavailable` safely closes the active recording while preserving the pending audio path.

- [ ] **Step 6: Run UI and coordinator boundary checks**

Run:

```bash
bash native/Tests/PrimaryMicrophoneUIBoundaryCheck.sh
bash native/Tests/MainWindowLayoutBoundaryCheck.sh
bash native/Tests/SpeechInputCoordinatorBoundaryCheck.sh
```

Expected: all pass; the layout contains exactly one “主麦克风” entry.

- [ ] **Step 7: Commit coordinator and UI**

```bash
git add native/Sources/Application/SpeechInputCoordinator.swift native/Sources/Presentation/Main/MainViewController.swift native/Sources/Presentation/Main/MainViewController+Configuration.swift native/Sources/Presentation/Main/MainViewController+Actions.swift native/Sources/Presentation/Main/MainViewController+PanelLayout.swift native/Tests/PrimaryMicrophoneUIBoundaryCheck.sh
git commit -m "feat: expose primary microphone hot switching"
```

---

### Task 5: Regression Suite, Documentation, Design Review, and Installed Build

**Files:**
- Modify: `README.md`
- Modify if present: `README_macOS.md`
- Modify: `docs/ARCHITECTURE.md`
- Modify: `docs/开发日志.md`
- Modify: `native/Sources/Presentation/VersionHistory/VersionHistoryViewController.swift`
- Generated by build entry: version/build records and `docs/构建日志.md`

**Interfaces:**
- Consumes: completed feature and all earlier checks.
- Produces: product documentation, version history, installed signed app, and a manual test record.

- [ ] **Step 1: Re-run concurrency protection before any release writes**

Run:

```bash
git branch --show-current
git status --short
pgrep -af 'build_and_log\.sh|release_local_build\.sh|build_native_app\.sh|swiftc|xcodebuild' || true
```

Expected: `codex/typewhale-pro-asr-hotwords`, only this feature’s known changes, and no foreign build process. If overlap exists, stop and report it.

- [ ] **Step 2: Run focused and broad automated checks**

Run the two Swift checks, the three new/updated shell checks, existing recorder/preview boundaries, and the repository’s native validation command discovered in `build_and_log.sh`. Expected: every command exits 0; no test may be waived because hardware is unavailable.

- [ ] **Step 3: Update product and architecture documentation before build**

Document exactly: Common-page “主麦克风”; same-session immediate switch; 0.3–1 second accepted gap; disconnect permanently follows system; reconnect does not auto-restore; canonical 16 kHz mono pipeline; failure recovery; unchanged ASR/VAD/paste semantics. Add the pending build/version entry to `VersionHistoryViewController` as required by the release guard.

- [ ] **Step 4: Run `design-review` on source and installed UI**

Review discoverability, device-name truncation, refresh affordance, switching/success/failure timing, focus behavior, and capsule continuity. Fix any P0/P1 UI issue and repeat the relevant checks before building.

- [ ] **Step 5: Build, install, launch, and verify signature through the sole entry point**

Run:

```bash
./native/build_and_log.sh
```

Expected: build guard succeeds, build/version rules are applied, `/Applications/TypeWhale.app` is replaced and launched, signature verification passes, and `docs/构建日志.md` is appended. If the build guard reports a concurrent version bump, follow its required version rewrite and retry rather than overwriting history.

- [ ] **Step 6: Test the installed app with real hardware**

Verify built-in → second device → built-in during one recording; unplug the selected device and confirm permanent follow-system; reconnect and confirm no auto-restore; cover realtime preview on/off, pause auto-finish, hold-to-talk, and manual stop. Confirm the final WAV/transcript contains speech from both sides of the switch and the microphone indicator releases after stop.

- [ ] **Step 7: Commit the completed daily build safely**

Run `git status --short`, stage only this feature’s code/tests/docs/build records, and commit:

```bash
git commit -m "feat: add primary microphone hot switching"
```

If `build_and_log.sh` triggers a full version build, this commit is mandatory; if it produces a normal daily build, still commit the complete verified feature as one final integration record without staging unrelated files.
