# Personal Voice Recording Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a guided, local-only recording sheet that saves one validated ZipVoice reference named “我的声音” and makes it immediately selectable in the Sounds reading lab.

**Architecture:** A focused reference-pack service owns conversion, validation, hashing, staging, and atomic replacement. A dedicated AppKit sheet controller owns the recording state machine and delegates microphone capture to the existing `AudioRecorder`; the existing reading-lab controller discovers the dynamic voice and refreshes its menu without changing the four qualified presets.

**Tech Stack:** Swift, AppKit, AVFAudio/AVFoundation, CryptoKit, existing ZipVoice worker and TTS reading-lab service, shell/Swift source-boundary tests.

## Global Constraints

- Fixed prompt: `清晰自然，稳定可靠。`
- Fixed voice ID: `zipvoice-my-voice`.
- Recording countdown is 0.8 seconds; capture is 1.0–3.0 seconds and stops automatically at 3.0 seconds.
- Output is 24 kHz, mono, PCM16 WAV and is produced with native Apple APIs.
- No Python, Conda, Homebrew, or ffmpeg runtime dependency may be introduced.
- Do not trim a fixed prefix or suffix; preserve the spoken first character and tail.
- The recording and reference pack remain local and do not enter ASR history, dictation, paste, or cloud flows.
- Existing default, Serena, CosyVoice, and video-reference voices and their qualification fingerprint remain unchanged.
- This change does not add personal-voice selection to OpenClaw or Reader Demo.
- Existing protected untracked directories must not be edited, staged, or committed.

---

### Task 1: Native Reference Pack Pipeline

**Files:**
- Create: `native/Sources/Infrastructure/TTSLab/TTSLabPersonalVoiceStore.swift`
- Create: `native/Tests/TTSLabPersonalVoiceStoreCheck.swift`
- Modify: `native/build_native_app.sh`

**Interfaces:**
- Consumes: canonical 16 kHz mono WAV returned by `AudioRecorder.stop()`.
- Produces: `TTSLabPersonalVoiceStore.validateRecording(at:)`, `prepareCandidate(from:)`, `install(_:)`, `discoverVoice()`, and `discard(_:)`.

- [ ] **Step 1: Write a failing Swift check**

Create a test that synthesizes quiet, clipped, short, and valid 16 kHz mono WAV fixtures. Assert precise rejection reasons, native conversion to 24 kHz mono PCM16, SHA-256 manifest values, discovery only after full validation, and preservation of the previous pack when candidate installation fails.

- [ ] **Step 2: Run the focused check and verify failure**

Run:

```bash
swiftc native/Tests/TTSLabPersonalVoiceStoreCheck.swift \
  native/Sources/Infrastructure/TTSLab/TTSLabPersonalVoiceStore.swift \
  native/Sources/Infrastructure/TTSLab/TTSLabVoice.swift \
  -framework AVFoundation -framework CryptoKit \
  -o /tmp/TTSLabPersonalVoiceStoreCheck
```

Expected: FAIL because `TTSLabPersonalVoiceStore.swift` does not exist.

- [ ] **Step 3: Implement the store**

Implement:

```swift
struct TTSLabPersonalVoiceMetrics: Equatable {
    let duration: TimeInterval
    let peak: Float
    let rms: Float
    let clippedSampleRatio: Double
}

enum TTSLabPersonalVoiceValidationError: LocalizedError, Equatable {
    case tooShort
    case tooLong
    case tooQuiet
    case clipped
    case unsupportedFormat
}

struct TTSLabPersonalVoiceCandidate {
    let directoryURL: URL
    let referenceURL: URL
    let metrics: TTSLabPersonalVoiceMetrics
}

final class TTSLabPersonalVoiceStore {
    static let voiceID = "zipvoice-my-voice"
    static let referenceText = "清晰自然，稳定可靠。"

    func validateRecording(at sourceURL: URL) throws -> TTSLabPersonalVoiceMetrics
    func prepareCandidate(from sourceURL: URL) throws -> TTSLabPersonalVoiceCandidate
    func install(_ candidate: TTSLabPersonalVoiceCandidate) throws
    func discoverVoice() -> TTSLabVoice?
    func discard(_ candidate: TTSLabPersonalVoiceCandidate)
}
```

Use `AVAudioFile` and `AVAudioConverter`, stream samples when calculating RMS/peak/clipping, write `reference.txt` and a deterministic JSON manifest, validate all files and hashes before discovery, and replace via a sibling backup directory that is restored on failure.

- [ ] **Step 4: Run the focused check**

Run the compiled check and expect:

```text
TTSLabPersonalVoiceStoreCheck passed
```

- [ ] **Step 5: Commit the pipeline**

Commit only the new store, focused test, and any explicit build source-list update with:

```bash
git commit -m "feat(tts): add native personal voice pack pipeline"
```

### Task 2: Guided Recording Sheet

**Files:**
- Create: `native/Sources/Presentation/Main/TTSMyVoiceRecordingViewController.swift`
- Create: `native/Tests/TTSMyVoiceRecordingSourceCheck.sh`
- Reuse without modification unless compilation requires it: `native/Sources/Infrastructure/Audio/AudioRecorder.swift`

**Interfaces:**
- Consumes: `AudioRecorder`, `PermissionDiagnosticsProvider`, `TTSLabPersonalVoiceStore`, and a clone-preview closure supplied by the main controller.
- Produces: `TTSMyVoiceRecordingViewController(onSaved:)`, which calls `onSaved(TTSLabVoice)` only after atomic installation.

- [ ] **Step 1: Write a failing source-boundary test**

Assert that the sheet contains the exact prompt and privacy copy, the states `idle/countdown/recording/validating/ready/previewing/saving/failed`, a 0.8-second countdown, a 3-second automatic stop, cancellation cleanup, recorder task isolation, microphone permission handling, original preview, clone preview, rerecord, and save actions.

- [ ] **Step 2: Run the source check and verify failure**

Run:

```bash
bash native/Tests/TTSMyVoiceRecordingSourceCheck.sh
```

Expected: FAIL because the recording controller does not exist.

- [ ] **Step 3: Implement the AppKit sheet**

Build a fixed-width sheet with:

```swift
enum PersonalVoiceRecordingState: Equatable {
    case idle
    case countdown
    case recording
    case validating
    case ready
    case previewing
    case saving
    case failed(String)
}
```

Use a large prompt card, local-only privacy note, elapsed-time label, lightweight level meter driven by `AudioRecorder.onInputLevelDb`, and state-specific buttons. Start capture only after the countdown; allow manual stop after one second; automatically stop at three seconds. On close, invalidate timers, stop capture/player, and delete candidate and preview files.

- [ ] **Step 4: Wire preview and save**

Original preview uses `AVAudioPlayer`. Clone preview calls the supplied closure with the candidate reference directory and a fixed test sentence, then plays the returned WAV. Save remains disabled until native validation and clone preview generation succeed.

- [ ] **Step 5: Run the source check**

Expected:

```text
TTSMyVoiceRecordingSourceCheck passed
```

- [ ] **Step 6: Commit the sheet**

Commit the sheet and its test with:

```bash
git commit -m "feat(tts): add guided personal voice recorder"
```

### Task 3: Reading Lab Integration and Dynamic Voice Discovery

**Files:**
- Modify: `native/Sources/Presentation/Main/TTSReadingLabView.swift`
- Modify: `native/Sources/Presentation/Main/MainViewController+TTSReadingLab.swift`
- Modify: `native/Sources/Application/TTSReadingLabService.swift`
- Modify: `native/Tests/TTSReadingLabViewSourceCheck.sh`
- Modify: `native/Tests/TTSLabVoiceCatalogCheck.swift`
- Create: `native/Tests/TTSMyVoiceIntegrationCheck.sh`

**Interfaces:**
- Consumes: `TTSLabPersonalVoiceStore.discoverVoice()` and `TTSMyVoiceRecordingViewController`.
- Produces: a “录制我的声音” action and a dynamically appended, auto-selected `TTSLabVoice(id: "zipvoice-my-voice", ...)`.

- [ ] **Step 1: Add failing integration assertions**

Assert that the recording button is in the action row, opens the sheet, leaves the reading text/model untouched, appends only a fully valid personal voice after the four qualified presets, saves the selected voice ID, and refreshes the menu after successful save.

- [ ] **Step 2: Run integration checks and verify failure**

Run:

```bash
bash native/Tests/TTSReadingLabViewSourceCheck.sh
bash native/Tests/TTSMyVoiceIntegrationCheck.sh
```

Expected: the new recording-button and dynamic-discovery assertions fail.

- [ ] **Step 3: Add the entry point**

Add:

```swift
let recordMyVoiceButton = NSButton(title: "录制我的声音", target: nil, action: nil)
var onRecordMyVoice: (() -> Void)?
```

Place it after replay in the action row, give it an explicit accessibility label, and disable it only while reading playback is active.

- [ ] **Step 4: Discover and refresh the personal voice**

Keep `TTSLabVoiceCatalog.candidates(for:)` static. After qualification filtering, append `personalVoiceStore.discoverVoice()` to the retained ZipVoice model if valid. On save, rebuild the model voice array, rebuild the popup, select `zipvoice-my-voice`, persist it, and preserve the current text/model.

- [ ] **Step 5: Add candidate clone preview**

Expose a narrowly scoped reading-lab service method that starts ZipVoice using a supplied candidate reference directory and fixed test text, returns its output URL, and uses the same worker protocol and post-processing as normal playback without installing the candidate first.

- [ ] **Step 6: Run focused and regression checks**

Run:

```bash
bash native/Tests/TTSReadingLabViewSourceCheck.sh
bash native/Tests/TTSMyVoiceIntegrationCheck.sh
swiftc native/Tests/TTSLabVoiceCatalogCheck.swift \
  native/Sources/Infrastructure/TTSLab/TTSLabVoice.swift \
  -o /tmp/TTSLabVoiceCatalogCheck && /tmp/TTSLabVoiceCatalogCheck
python3 native/Tests/ZipVoiceWorkerVoiceCheck.py
python3 native/Tests/TTSZipVoiceTextNormalizationCheck.py
python3 native/Tests/TTSZipVoicePostProcessingCheck.py
```

Expected: all checks print `passed`.

- [ ] **Step 7: Commit integration**

Commit only the reading-lab integration and tests with:

```bash
git commit -m "feat(tts): expose personal voice in reading lab"
```

### Task 4: Product Documentation, Design Review, and Installed Build

**Files:**
- Modify: `docs/开发日志.md`
- Modify: `native/Sources/Presentation/VersionHistory/VersionHistoryViewController.swift`
- Modify: files automatically updated by `native/build_and_log.sh` for the unique build number and build log.

**Interfaces:**
- Consumes: completed recording workflow.
- Produces: a signed, installed `/Applications/TypeWhale Pro.app` with a unique build number and durable release notes.

- [ ] **Step 1: Update product records**

Document the guided local recording flow, native dependency boundary, fixed reference text, dynamic voice discovery, atomic replacement, and explicitly unchanged preset/OpenClaw/Reader Demo behavior.

- [ ] **Step 2: Run the complete relevant test suite**

Run all focused checks from Tasks 1–3 plus the repository’s TTS and build validation commands. Expected: zero failures.

- [ ] **Step 3: Perform design-quality review**

Use the `design-review` skill against the completed sheet and Sounds-page integration. Review hierarchy, copy, countdown/recording/validation transitions, button enablement, cancellation, focus, accessibility, clipping at minimum window size, and whether any state flashes or loses context. Fix all material findings and rerun focused tests.

- [ ] **Step 4: Build and install**

Recheck branch, status, source mtimes, and active build processes, then run:

```bash
./native/build_and_log.sh
```

Expected: build number increments once, `/Applications/TypeWhale Pro.app` is replaced and opened, code signature verification succeeds, and the build log is updated.

- [ ] **Step 5: Validate the installed app**

In the installed app, open Sounds → Reading Test, open the sheet, verify the complete idle/countdown/record/validate/preview/save/cancel flow, confirm “我的声音” is selected after save and persists after relaunch, and confirm all four existing voices still play. If microphone interaction cannot be automated, record the exact unverified hardware-dependent path.

- [ ] **Step 6: Final scope review and commit**

Run `git status --short`, exclude all protected untracked directories, review the final diff, and commit the build-specific code/docs/log changes with:

```bash
git commit -m "build: ship personal voice recording"
```
