# TypeWhale Xiaomi Remote 2 Pro Integration Implementation Plan

> **For Codex:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task. This run executes inline because the user asked for fully autonomous development and no delegation was requested.

**Goal:** Add a production-grade native Remote tab to TypeWhale Pro and route Xiaomi Remote 2 Pro ATVV speech directly into the existing TypeWhale recording, realtime ASR, final recognition, and text-delivery pipeline.

**Architecture:** A pure protocol/domain layer parses ATVV capabilities/control events and decodes IMA ADPCM. A CoreBluetooth controller owns discovery and GATT lifecycle; a non-exclusive IOKit monitor observes known RC003 HID usages. `RemoteInputCoordinator` reduces those events to one privacy-safe snapshot and calls explicit remote-source methods on `SpeechInputCoordinator`. `AudioRecorder` gains an external PCM source that passes through the same canonical processing function as the microphone path. `MainViewController` renders the snapshot inside the existing inspector scroll page.

**Tech stack:** Swift 6, AppKit, CoreBluetooth, IOKit HID, AVFAudio, existing TypeWhale build/test scripts.

**Constraints:** No SayAll/GPL code or assets, no virtual audio driver, no WebView, no separate process, no persistent device identifier, no raw audio/packet logging, and no claim of real-device success without physical pairing evidence.

---

## Task 1: Lock the protocol and state contracts with failing tests

**Files:**

- Create: `native/Tests/RemoteATVVProtocolCheck.swift`
- Create: `native/Tests/RemoteADPCMDecoderCheck.swift`
- Create: `native/Tests/RemoteConnectionPolicyCheck.swift`
- Create: `native/Tests/RemoteButtonMappingCheck.swift`
- Create: `native/Tests/run_remote_domain_checks.sh`
- Create: `native/Sources/Domain/Remote/RemoteInputModels.swift`
- Create: `native/Sources/Domain/Remote/RemoteButtonMapping.swift`
- Create: `native/Sources/Infrastructure/Remote/RemoteADPCMDecoder.swift`
- Create: `native/Sources/Infrastructure/Remote/RemoteATVVProtocol.swift`

**Step 1 — RED:** Write executable Swift checks for:

- v0.4 and v1.0 capability parsing, including Xiaomi's observed swapped codec/interaction layout;
- GET_CAPS, MIC_OPEN, MIC_CLOSE, START_SEARCH, AUDIO_START/STOP, AUDIO_SYNC, unknown and truncated messages;
- high-nibble-first IMA ADPCM golden vectors, clamping, reset, 134-byte v0.4 and 120-byte v1.0 frames;
- state transitions for disabled, unavailable, scanning, connecting, negotiating, ready, listening, processing, retry, busy, protocol failure;
- fixed voice action and safe editable defaults for center/back/home/menu.

Run `zsh native/Tests/run_remote_domain_checks.sh`. Confirm compilation fails because production types do not exist.

**Step 2 — GREEN:** Implement the smallest platform-free domain/protocol code that passes every check. Reject malformed capabilities and frames. Never infer support from a device name alone.

**Step 3 — Verify:** Re-run the script twice and run `git diff --check` on the new files.

## Task 2: Add external PCM to the existing recorder without splitting the pipeline

**Files:**

- Modify: `native/Sources/Infrastructure/Audio/AudioRecorder.swift`
- Create: `native/Tests/AudioRecorderExternalPCMCheck.swift`
- Create: `native/Tests/AudioRecorderExternalPCMBoundaryCheck.sh`

**Step 1 — RED:** Add a focused executable check that starts an `AudioRecorder` external session at 16 kHz, appends deterministic PCM, stops it, and verifies a non-empty canonical mono WAV. Add boundary assertions that microphone capture still calls the shared canonical processing function and external input never installs a microphone tap or starts route monitoring.

Run both checks and confirm they fail before production edits.

**Step 2 — GREEN:** Refactor recorder initialization into one private session initializer. Keep `start(...)` semantics unchanged. Add:

```swift
func startExternal(
    taskID: UUID,
    sampleRate: Int,
    realtimeEnabled: Bool,
    sourceName: String,
    experimentalPreviewEnabled: Bool
) throws

func appendExternalPCM16(_ samples: [Int16], taskID: UUID)
```

Convert external PCM with `CanonicalAudioConverter`, then call the same `processCanonicalBuffer` used by microphone capture. Preserve fan-out, realtime snapshots, VAD probes, levels, waveform, WAV finalization, and stop/cancel behavior. Use source-appropriate empty-input errors.

**Step 3 — Verify:** Run the external tests plus existing `AudioRecorderFanOutSourceCheck.sh`, `AudioRecorderFinalizationBoundaryCheck.sh`, and `ManualAudioInputCaptureBoundaryCheck.sh`.

## Task 3: Build the BLE/HID infrastructure

**Files:**

- Create: `native/Sources/Infrastructure/Remote/RemoteBluetoothController.swift`
- Create: `native/Sources/Infrastructure/Remote/RemoteHIDMonitor.swift`
- Create: `native/Tests/RemoteBluetoothBoundaryCheck.sh`
- Create: `native/Tests/RemoteHIDEventReducerCheck.swift`

**Step 1 — RED:** Assert the controller filters on the ATVV service, retrieves already connected ATVV peripherals, subscribes to control and RX before GET_CAPS, retries capabilities at most three times, reads Battery/Model characteristics, handles disconnect, and never logs UUID/address/raw data. Assert HID reduction emits one down/up pair, ignores repeats/unknown usages, and clears a held button on device removal.

**Step 2 — GREEN:** Implement `CBCentralManagerDelegate`/`CBPeripheralDelegate` on the main queue with bounded capability negotiation and reconnect backoff. Implement a non-exclusive `IOHIDManager` monitor for vendor `0x2717`, product `0x32B8`, and the documented RC003 keyboard usage map. Observation must not remap, seize, or suppress macOS events.

**Step 3 — Verify:** Compile pure reducer tests, run boundary checks, and build the whole app once before UI wiring.

## Task 4: Connect remote sessions to SpeechInputCoordinator

**Files:**

- Create: `native/Sources/Application/RemoteInputCoordinator.swift`
- Modify: `native/Sources/Application/SpeechInputState.swift`
- Modify: `native/Sources/Application/SpeechInputCoordinator.swift`
- Create: `native/Tests/RemoteSpeechSessionPolicyCheck.swift`
- Create: `native/Tests/RemoteSpeechCoordinatorBoundaryCheck.sh`

**Step 1 — RED:** Cover source ownership and idempotency: a remote start is accepted only while idle; remote stop cannot finish a keyboard-owned session; duplicate START/STOP is harmless; disconnect cancels or safely finishes only the remote-owned session; samples from a stale task are dropped.

**Step 2 — GREEN:** Add `SpeechCaptureSource` to `SpeechSession`. Extend private `startRecording` with a default microphone source. Skip microphone permission and input-device resolution only for the remote source, then call `AudioRecorder.startExternal`. Expose narrow `beginRemoteSpeech(sampleRate:)`, `appendRemotePCM16`, and `endRemoteSpeech` methods. Wire a single `RemoteInputCoordinator` during coordinator start/stop and wake/sleep lifecycle.

**Step 3 — Verify:** Run new checks and existing workflow/hotkey/recording boundary checks. Confirm microphone hotkey behavior is unchanged.

## Task 5: Implement the complete native Remote tab

**Files:**

- Modify: `native/Sources/Presentation/Main/MainViewController.swift`
- Modify: `native/Sources/Presentation/Main/MainViewController+PanelLayout.swift`
- Create: `native/Sources/Presentation/Main/MainViewController+Remote.swift`
- Create: `native/Tests/RemoteTabBoundaryCheck.sh`
- Reference: `docs/design/xiaomi-remote-tab/spec.json`
- Reference: `docs/design/xiaomi-remote-tab/clean.svg`

**Step 1 — RED:** Assert a seventh `remote` tab exists, the page is built from existing inspector groups, every approved region and user-facing state string exists, controls have accessibility labels, and no WebView/iframe/external brand asset is referenced.

**Step 2 — GREEN:** Build one scroll page with:

- lead status / enable switch / context action;
- device truth and Home + Menu pairing guidance;
- five-stage voice path and live packet/level/session indicators;
- voice, center, back, home, menu mappings with safe defaults and reset;
- Bluetooth/Input Monitoring status, System Settings action, privacy copy;
- embedded three-step usage and recovery copy.

Use `UITheme`, `UILayout`, `inspectorGroup`, system symbols, vertical reflow, and existing scroll behavior. Drive all dynamic text from `RemoteInputSnapshot`.

**Step 3 — Verify:** Run the boundary check and app build. Inspect dark/light token paths, keyboard focus, and VoiceOver labels.

## Task 6: Build metadata, privacy, licensing, and documentation

**Files:**

- Modify: `native/build_native_app.sh`
- Modify: `THIRD_PARTY_NOTICES.md`
- Modify: `docs/ARCHITECTURE.md`
- Modify: `docs/开发日志.md`
- Modify: `native/Sources/Presentation/VersionHistory/VersionHistoryViewController.swift`
- Create: `native/Tests/TypeWhaleRemoteFeatureCheck.sh`

**Step 1 — RED:** Make the aggregate feature check require `CoreBluetooth`, `IOKit`, `NSBluetoothAlwaysUsageDescription`, protocol/domain tests, external PCM boundary, UI boundary, no forbidden GPL/Logo source paths, and a version-history/developer-log entry.

**Step 2 — GREEN:** Link frameworks, add a specific Bluetooth usage description, document architecture/privacy/recovery/third-party protocol references, and add the next build history entry. Keep product UI copy free of engineering/legal process text.

**Step 3 — Verify:** Run the aggregate script, `git diff --check`, and scan changed files for `HD838A`, `SayAll`, `MiRemoteV`, `BlackHole`, raw UUID logging, and copied brand assets. Only documentation may name excluded upstream during the license audit.

## Task 7: Install, runtime-QA, and handoff

**Files:**

- Modify automatically: `native/build_native_app.sh` build number
- Modify automatically: `docs/构建日志.md`
- Modify: `docs/design/xiaomi-remote-tab/verification.md`

**Step 1 — Concurrency check:** Confirm the TypeSpeaker tracked tree contains only this task's changes and no build/install process is active.

**Step 2 — Build/install:** Run `./native/build_and_log.sh`. It must compile, bump build 897 to 898 or later, replace `/Applications/TypeWhale Pro.app`, open it, and append the build log.

**Step 3 — Runtime QA:** Open the Remote tab. Capture top and bottom scroll evidence plus accessibility tree. Verify selected tab, no-device state, enable/scan controls, all cards, no clipping, and no launch crash. Do not grant macOS privacy permissions automatically.

**Step 4 — Regression:** Run `TypeWhaleRemoteFeatureCheck.sh`, all task-adjacent recorder/workflow checks, `git diff --check`, bundle version/usage-description checks, `codesign --verify --deep --strict`, process presence, and launch diagnostics for build 898+.

**Step 5 — Review:** Use `design-review` on the installed UI. Fix all P0/P1/P2 visual or interaction findings and repeat evidence. Apply `superpowers:verification-before-completion` before any success claim.

**Step 6 — Commit:** Stage only explicit task paths and commit one coherent TypeSpeaker change. Leave pre-existing untracked artifacts untouched.

**Step 7 — Handoff truthfully:** Report code/build/UI status separately from hardware status. If the remote was not physically paired, leave G6 `No-Go` and give the owner the one required action: hold Home + Menu, then click scan. Never state that hold-to-talk and transcription passed without observed real audio.
