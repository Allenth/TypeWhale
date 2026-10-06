# Recording Audio Mute Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the existing recording volume-duck option reduce writable system output volume to `0.0` while preserving the established restore and user-intent protections.

**Architecture:** Keep `OutputAudioDucker` ownership, generation, delay, and ramp behavior unchanged. Change only the owned target scalar, prove it through the existing injected-volume executable, then record and install the next unique daily build.

**Tech Stack:** Swift, CoreAudio, shell build scripts, existing focused Swift executable checks.

## Global Constraints

- Work only on `codex/typewhale-pro-asr-hotwords` in the main repository.
- Do not stage or modify protected Smart Rewrite, artifact, or capsule-concept paths.
- The mute target is exactly `Float32(0.0)`; do not change the system mute property.
- Do not modify media pause, OpenClaw, hotkey, recorder, or UI layout behavior.
- Build only through `./native/build_and_log.sh`, producing the next unique build and committing owned files.

---

### Task 1: Change the recording duck target to zero

**Files:**
- Modify: `native/Tests/OutputAudioDuckerCheck.swift`
- Modify: `native/Sources/Infrastructure/Audio/OutputAudioDucker.swift`

**Interfaces:**
- Consumes: `OutputAudioDucker.duckIfNeeded(enabled:)`, `restore()`, injected volume access and scheduler.
- Produces: the same APIs with an owned duck target of `0.0`.

- [x] **Step 1: Write the failing expectations**

Change the consecutive-recording assertions to require `0.0` after both starts and update the disabled-path diagnostic from “5%” to “muted”.

- [x] **Step 2: Run RED**

```bash
xcrun swiftc \
  native/Sources/Infrastructure/Audio/OutputAudioDucker.swift \
  native/Tests/OutputAudioDuckerCheck.swift \
  -o /tmp/typewhale-output-audio-ducker-check
/tmp/typewhale-output-audio-ducker-check
```

Expected: precondition failure because the current implementation writes `0.05`.

- [x] **Step 3: Implement the minimal change**

Set:

```swift
private static let duckedVolume: Float32 = 0.0
```

Do not alter restore timing, tolerance, snapshots, CoreAudio addressing, or ownership logic.

- [x] **Step 4: Run GREEN and focused boundaries**

Run the Task 1 executable again, followed by:

```bash
bash native/Tests/RecordingAudioPolicyCoordinatorBoundaryCheck.sh
bash native/Tests/RecordingAudioPolicySettingsBoundaryCheck.sh
git diff --check
```

Expected: all checks pass.

### Task 2: Record, build, install, and commit Build 889

**Files:**
- Modify: `docs/开发日志.md`
- Modify: `native/Sources/Presentation/VersionHistory/VersionHistoryViewController.swift`
- Modify automatically: `README.md`
- Modify automatically: `macos/README.md`
- Modify automatically: `docs/构建日志.md`
- Modify automatically: `native/build_native_app.sh`

**Interfaces:**
- Consumes: the verified zero-volume target.
- Produces: signed and installed `2.0.58 (Build 889)` plus one owned-files commit.

- [x] **Step 1: Add the Build 889 narrative**

Record the exact zero-volume behavior, preserved consecutive baseline, user manual volume protection, and unchanged media-pause/shortcut boundaries in both persistent histories.

- [x] **Step 2: Recheck concurrency and build**

```bash
git branch --show-current
git status --short
pgrep -fl 'build_and_log.sh|release_local_build.sh|build_native_app.sh|swiftc|xcodebuild' || true
./native/build_and_log.sh
```

Expected: Build 889 compiles, installs to `/Applications/TypeWhale Pro.app`, opens, and passes signature verification.

- [x] **Step 3: Run fresh post-build verification**

Repeat Task 1 GREEN, both recording policy boundary checks, `git diff --check`, installed plist version/build checks, process check, and deep strict codesign verification.

- [x] **Step 4: Commit only owned files**

Explicitly stage Task 1, Task 2, spec/plan, and automatic build-record files. Confirm protected paths are absent, then commit:

```bash
git commit -m "fix(audio): mute system output while recording"
```
