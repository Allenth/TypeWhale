# Configurable Auto-Send Countdown Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users configure the existing paste auto-send countdown as a global integer from 1–10 seconds, defaulting to 2 seconds.

**Architecture:** Extend `AutoSendConfiguration` with a backwards-compatible normalized duration, expose it through the existing main-window paste settings, and inject a duration provider into `AutoSendCountdownCoordinator`. Each scheduled countdown snapshots the current saved duration so an in-flight countdown never changes.

**Tech Stack:** Swift, AppKit, UserDefaults/Codable, existing standalone Swift checks, native TypeWhale build scripts.

## Global Constraints

- Default countdown is exactly 2 seconds.
- Allowed values are integer seconds from 1 through 10, with a 1-second step.
- The setting is global, not per application.
- Existing cancellation, focus protection, application action, translation, Idea Pill, and OpenClaw boundaries remain unchanged.
- Use native AppKit controls and system fonts; add no font or third-party dependency.
- Do not touch protected untracked `.artifacts`, `.superpowers`, capsule concept gallery, or capsule concept source files.
- After code changes, update release narratives, run automated checks, increment the build through `./native/build_and_log.sh`, install `/Applications/TypeWhale Pro.app`, open and verify it, then commit only this feature's files.

---

### Task 1: Backwards-Compatible Countdown Configuration

**Files:**
- Modify: `native/Sources/Domain/AutoSendDomain.swift`
- Modify: `native/Sources/Infrastructure/Settings/AutoSendSettingsStore.swift`
- Modify: `native/Tests/AutoSendSettingsStoreCheck.swift`

**Interfaces:**
- Produces: `AutoSendConfiguration.countdownSeconds: Int`
- Produces: `AutoSendConfiguration.defaultCountdownSeconds == 2`
- Produces: `AutoSendConfiguration.normalizedCountdownSeconds(_:) -> Int`

- [x] **Step 1: Write a failing standalone settings test**

Create checks that decode legacy JSON without `countdownSeconds` as 2, round-trip 1 and 10, and normalize 0 to 1 and 11 to 10 through `AutoSendSettingsStore.normalized`.

- [x] **Step 2: Run the new check and verify failure**

Run:

```bash
xcrun swiftc -parse-as-library \
  native/Sources/Domain/AutoSendDomain.swift \
  native/Sources/Infrastructure/Settings/AutoSendSettingsStore.swift \
  native/Tests/AutoSendSettingsStoreCheck.swift \
  -o /tmp/AutoSendSettingsStoreCheck && \
  /tmp/AutoSendSettingsStoreCheck
```

Expected: compilation fails because `countdownSeconds` and its normalization API do not exist.

- [x] **Step 3: Implement the configuration field and migration**

Add the stored integer field, include it in coding keys, decode missing values as 2, encode it, and clamp at the configuration/store boundary:

```swift
static let countdownSecondsRange = 1...10
static let defaultCountdownSeconds = 2

static func normalizedCountdownSeconds(_ value: Int) -> Int {
    min(countdownSecondsRange.upperBound, max(countdownSecondsRange.lowerBound, value))
}
```

Update every production and test initializer to pass a countdown, using 2 unless the test specifically exercises another value. Preserve the value when `AutoSendSettingsStore.normalized` rebuilds the configuration.

- [x] **Step 4: Run the settings check**

Run the targeted compile/run command from Step 2 again.

Expected: `AutoSendSettingsStoreCheck passed`.

### Task 2: Dynamic Countdown Scheduling

**Files:**
- Modify: `native/Sources/Application/AutoSendCountdownCoordinator.swift`
- Modify: `native/Sources/Application/SpeechInputCoordinator.swift`
- Modify: `native/Tests/AutoSendCountdownCoordinatorCheck.swift`

**Interfaces:**
- Consumes: `AutoSendConfiguration.normalizedCountdownSeconds(_:) -> Int`
- Produces: `AutoSendCountdownCoordinator.init(..., durationSeconds: @escaping () -> Int, ...)`

- [x] **Step 1: Change coordinator tests to inject 1-second and longer durations**

Inject a mutable `durationSeconds` closure, assert the initial snapshot equals the selected duration, assert no emission before its deadline, and assert emission at the exact deadline. Keep all existing cancellation, replacement, focus-change, and emission-failure assertions.

- [x] **Step 2: Run the coordinator check and verify failure**

Run the standalone `AutoSendCountdownCoordinatorCheck` compile command documented in the existing countdown implementation plans.

Expected: compilation fails because the coordinator initializer has no duration provider.

- [x] **Step 3: Implement duration snapshotting**

Replace the fixed duration with an injected closure. In `schedule`, normalize once and use that value for both `deadline` and the initial snapshot. Include the effective duration in diagnostics. In `SpeechInputCoordinator`, provide:

```swift
durationSeconds: {
    AutoSendSettingsStore.load().countdownSeconds
}
```

- [x] **Step 4: Run countdown domain and coordinator checks**

Expected: both checks print their `passed` messages and existing cancellation behavior remains green.

### Task 3: Main-Window Countdown Setting

**Files:**
- Modify: `native/Sources/Presentation/Main/MainViewController.swift`
- Modify: `native/Sources/Presentation/Main/MainViewController+Configuration.swift`
- Modify: `native/Sources/Presentation/Main/MainViewController+PanelLayout.swift`
- Modify: `native/Sources/Presentation/Main/MainViewController+Actions.swift`

**Interfaces:**
- Consumes: `AutoSendConfiguration.countdownSeconds`
- Produces: `MainViewController.autoSendCountdownSeconds: NSStepper`
- Produces: `MainViewController.autoSendCountdownValueLabel: NSTextField`
- Produces: `saveAutoSendCountdownSeconds()` action

- [x] **Step 1: Add native controls and accessibility configuration**

Create a label plus `NSStepper` with minimum 1, maximum 10, increment 1, integer wrapping disabled, accessibility label “自动发送倒计时”, and tooltip explaining that users can cancel before the send action fires.

- [x] **Step 2: Place the setting in the paste-and-send group**

Add an `optionRow("发送倒计时", ...)` directly below the auto-send switch and above application scope. Render the value as `N 秒` and keep the existing explanatory note.

- [x] **Step 3: Load and immediately persist changes**

During `configureAutoSendControls`, load the saved value into both controls. On stepper action, clamp the integer, update the label, save the complete existing configuration, and set detail text to `自动发送倒计时已设为 N 秒`.

- [x] **Step 4: Compile the presentation layer**

Run the project build/check entry far enough to compile all Swift sources.

Expected: no type, selector, constraint, or accessibility errors.

### Task 4: Regression Checks and UI Review

**Files:**
- Modify only files required to repair failures within this feature boundary.

**Interfaces:**
- Consumes all interfaces from Tasks 1–3.

- [x] **Step 1: Run relevant automated checks**

Run configuration, application-scope editor, countdown domain, countdown coordinator, and auto-send integration boundary checks.

Expected: every command exits 0 and prints its success marker.

- [x] **Step 2: Run the full native automated check suite**

Use the repository's native build/check entry without installing or bumping a build if a read-only check mode exists; otherwise use the targeted scripts before the required release build.

Expected: all checks pass.

- [x] **Step 3: Apply `design-review` to the changed setting UI**

Review hierarchy, label clarity, alignment, control sizing, accessibility, and discoverability. Confirm the extra row does not crowd the “粘贴与发送” group and does not change the existing countdown capsule animation.

- [x] **Step 4: Re-run affected checks after review fixes**

Expected: checks remain green.

### Task 5: Release Narrative, Build, Install, and Commit

**Files:**
- Modify: `docs/开发日志.md`
- Modify: `native/Sources/Presentation/VersionHistory/VersionHistoryViewController.swift`
- Modify as required by build script: version/build metadata and `docs/构建日志.md`
- Include: `docs/superpowers/plans/2026-08-03-configurable-auto-send-countdown.md`

**Interfaces:**
- Produces a uniquely numbered installed TypeWhale Pro build containing the feature.

- [x] **Step 1: Re-run concurrency safety checks**

Check branch, status, diffs, build processes, and mtimes. Stop if another session overlaps feature, version, history, or build-log files.

- [x] **Step 2: Update narrative documentation before building**

Record the configurable 1–10 second global countdown, default/migration behavior, preserved cancellation protections, and verification coverage in both required release narratives.

- [x] **Step 3: Build, bump, install, open, and verify**

Run:

```bash
./native/build_and_log.sh
```

Expected: build number increments exactly once, `/Applications/TypeWhale Pro.app` is replaced and opened, signing verification passes, and the build log records the new build.

- [x] **Step 4: Verify the installed app**

Confirm the installed bundle version/build and running process. Inspect the real settings UI when available: default/current seconds are visible, stepper range is 1–10, and the row aligns with neighboring controls. Record any real-interaction path that cannot be exercised automatically.

- [x] **Step 5: Review and commit only this feature**

Run `git status --short`, `git diff --check`, relevant tests, and inspect the staged diff. Do not stage protected untracked files. Commit with:

```bash
git commit -m "feat: configure auto-send countdown"
```

Expected: the commit contains implementation, tests, design/plan, required release metadata, and build log only; protected unrelated files remain untracked.
