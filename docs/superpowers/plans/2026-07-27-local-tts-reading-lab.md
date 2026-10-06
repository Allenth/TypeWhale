# Local TTS Reading Lab Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a production-quality Reading Lab section to TypeWhale's Sound page that plays entered text with qualified offline models and displays comparable performance metrics.

**Architecture:** The UI consumes only qualification manifests produced by the asset plan. A dedicated `TTSReadingLabService` owns a single cancellable worker and audio player, exposes typed state updates, and remains isolated from `OpenClawVoicePlayer` and its settings.

**Tech Stack:** Swift/AppKit, AVFoundation, Foundation Process/JSONL, UserDefaults, Python/CLI model workers, existing shell-based Swift test harness, macOS 14+.

## Global Constraints

- Implement this plan only after `2026-07-27-local-tts-assets-qualification.md` has produced at least one passing model.
- Do not change OpenClaw voice settings, queue, prewarm, interruption, or default engine behavior.
- Show only models whose `typewhale-model.json` has `qualification.status == "passed"`.
- Stop must cancel generation and playback and leave no background model process.
- Persist entered text, not temporary generated audio paths or running state.
- Store outputs below `~/Library/Application Support/TypeWhale Pro/TTSLab/Outputs/`.
- Keep Reader Demo untouched.
- Run design-review after UI implementation.
- After code changes, update logs/history, increment build, install `/Applications/TypeWhale Pro.app`, open it, validate it, and commit.

---

### Task 1: Define the qualified model catalog and metric types

**Files:**
- Create: `native/Sources/Infrastructure/TTSLab/TTSLabModel.swift`
- Create: `native/Sources/Infrastructure/TTSLab/TTSLabModelCatalog.swift`
- Test: `native/Tests/TTSLabModelCatalogCheck.swift`

**Interfaces:**
- Produces: `TTSLabModel`, `TTSLabRuntime`, `TTSLabCapabilities`, `TTSLabMetrics`.
- Produces: `TTSLabModelCatalog.qualifiedModels(root:fileManager:) throws -> [TTSLabModel]`.

- [ ] **Step 1: Write the failing catalog test**

Create passed, failed, malformed, and symlink-escaped manifests in a temporary root. Assert only the passed contained directory is returned and ordering is tier then display name.

- [ ] **Step 2: Compile and verify failure**

Run a focused `swiftc` command matching existing standalone model checks.
Expected: FAIL because TTSLab types do not exist.

- [ ] **Step 3: Implement exact types**

```swift
struct TTSLabMetrics: Codable, Equatable {
    let cold: Bool
    let prepareSeconds: Double
    let firstAudioSeconds: Double
    let synthesisSeconds: Double
    let audioSeconds: Double
    let rtf: Double
    let peakRSSBytes: Int64
}

struct TTSLabModel: Codable, Equatable, Identifiable {
    let id: String
    let displayName: String
    let tier: Int
    let runtime: TTSLabRuntime
    let capabilities: TTSLabCapabilities
    let directory: URL
}
```

Decode manifests, resolve containment, require passing qualification, required files, and license path.

- [ ] **Step 4: Compile and run**

Expected: `TTSLabModelCatalogCheck passed`.

- [ ] **Step 5: Commit**

```bash
git add native/Sources/Infrastructure/TTSLab native/Tests/TTSLabModelCatalogCheck.swift
git commit -m "feat: add qualified TTS lab catalog"
```

### Task 2: Implement the isolated worker client and state machine

**Files:**
- Create: `native/Sources/Infrastructure/TTSLab/TTSLabWorkerClient.swift`
- Create: `native/Sources/Application/TTSReadingLabService.swift`
- Test: `native/Tests/TTSReadingLabServiceCheck.swift`
- Test: `native/Tests/TTSLabWorkerCancellationCheck.swift`

**Interfaces:**
- Produces: `enum TTSReadingLabState { idle, preparing, generating, playing, completed(TTSLabMetrics, URL), stopped, failed(String) }`.
- Produces: `start(text:model:)`, `stop()`, `replayLastOutput()`.
- Consumes: JSONL worker protocol from the asset plan.

- [ ] **Step 1: Write failing lifecycle tests**

Use a fake worker that emits ready/metrics and a slow worker that blocks. Assert exact state order, one active task, stop latency below two seconds, no callback from an obsolete generation, and no use of `OpenClawVoiceSettingsStore`.

- [ ] **Step 2: Compile and verify failure**

Expected: missing service/client types.

- [ ] **Step 3: Implement the JSONL client**

Use dedicated stdout/stderr queues, request IDs, bounded waits, process generation tokens, safe pipe closing, and terminate/interrupt escalation. Reject mismatched IDs and malformed responses.

- [ ] **Step 4: Implement the service**

Own one serial state queue, one worker, and one `AVAudioPlayer`. Generate a UUID WAV under the lab output root, publish state on the main queue, stop old work before new work, retain the last valid output, and never call `OpenClawVoicePlayer`.

- [ ] **Step 5: Run lifecycle and cancellation tests**

Expected: both checks print `passed`.

- [ ] **Step 6: Commit**

```bash
git add native/Sources/Infrastructure/TTSLab native/Sources/Application/TTSReadingLabService.swift native/Tests/TTSReadingLabServiceCheck.swift native/Tests/TTSLabWorkerCancellationCheck.swift
git commit -m "feat: add cancellable TTS reading lab service"
```

### Task 3: Persist test text and structured results

**Files:**
- Create: `native/Sources/Infrastructure/Settings/TTSReadingLabSettings.swift`
- Create: `native/Sources/Infrastructure/TTSLab/TTSLabResultStore.swift`
- Test: `native/Tests/TTSReadingLabSettingsCheck.swift`

**Interfaces:**
- Produces: `TTSReadingLabSettingsStore.loadText() -> String`, `saveText(_:)`.
- Produces: `TTSLabResultStore.append(model:text:metrics:outputURL:) throws`.

- [ ] **Step 1: Write failing persistence tests**

Assert default corpus, round-trip Unicode text, no running state keys, newline-delimited JSON result append, and omission of full input text from diagnostics logs; store a SHA-256 plus character count for privacy.

- [ ] **Step 2: Compile and verify failure**

Expected: missing settings and result store.

- [ ] **Step 3: Implement stores**

Use `ttsReadingLabText` in UserDefaults. Write results to `TTSLab/Results/results.jsonl` with ISO-8601 time, model ID, text hash/count, metrics, and output filename.

- [ ] **Step 4: Run tests**

Expected: `TTSReadingLabSettingsCheck passed`.

- [ ] **Step 5: Commit**

```bash
git add native/Sources/Infrastructure/Settings/TTSReadingLabSettings.swift native/Sources/Infrastructure/TTSLab/TTSLabResultStore.swift native/Tests/TTSReadingLabSettingsCheck.swift
git commit -m "feat: persist TTS lab text and metrics"
```

### Task 4: Build the AppKit Reading Lab section

**Files:**
- Create: `native/Sources/Presentation/Main/TTSReadingLabView.swift`
- Create: `native/Sources/Presentation/Main/MainViewController+TTSReadingLab.swift`
- Modify: `native/Sources/Presentation/Main/MainViewController.swift`
- Modify: `native/Sources/Presentation/Main/MainViewController+PanelLayout.swift`
- Modify: `native/Sources/Presentation/Main/MainViewController+Configuration.swift`
- Test: `native/Tests/TTSReadingLabViewSourceCheck.sh`

**Interfaces:**
- Consumes: qualified catalog, service state, text settings.
- Produces: one inspector group titled `朗读测试`.

- [ ] **Step 1: Write the failing source/structure test**

Assert the voice page contains exactly one `inspectorGroup("朗读测试", ...)`, the view has text/model/play/replay/status/metrics controls, accessibility labels, and no binding to OpenClaw setting controls.

- [ ] **Step 2: Run and verify failure**

Run: `bash native/Tests/TTSReadingLabViewSourceCheck.sh`
Expected: FAIL because the view is absent.

- [ ] **Step 3: Implement the focused view**

`TTSReadingLabView` owns presentation controls only. Use an `NSScrollView` containing an `NSTextView`, a model popup, primary `播放/停止` button, secondary `重播最近音频` button, status label, and compact metrics grid. Use system fonts and existing `UITheme`.

- [ ] **Step 4: Wire the controller**

Load qualified models on page creation, persist text on change/end editing, disable play for empty text or no models, update button title and enabled states from service state, and format metrics as seconds, `RTF %.2f`, and MB/GB.

- [ ] **Step 5: Add layout constraints**

Place the group after `小龙虾声音`, give the text area a 120-point minimum height, preserve scroll behavior, and prevent status/error text from widening the inspector.

- [ ] **Step 6: Run source test**

Expected: `TTSReadingLabViewSourceCheck passed`.

- [ ] **Step 7: Commit**

```bash
git add native/Sources/Presentation/Main native/Tests/TTSReadingLabViewSourceCheck.sh
git commit -m "feat: add TTS reading lab sound section"
```

### Task 5: Integrate worker packaging and build guards

**Files:**
- Modify: `native/build_native_app.sh`
- Modify: `native/Resources/tts_benchmark_worker.py`
- Create: `native/Tests/TTSLabRuntimePackagingCheck.sh`
- Modify: `THIRD_PARTY_NOTICES.md`

**Interfaces:**
- Consumes: model manifests that name their runtime executable.
- Produces: installed app worker resources and explicit runtime diagnostics.

- [ ] **Step 1: Write failing packaging test**

Build a temporary profile and assert the app contains the worker/catalog, no model weights are bundled into the DMG by default, and third-party notices cover TTSKit, Qwen3-TTS, Sherpa/Kokoro/ZipVoice, CosyVoice, MOSS, and VoxCPM when qualified.

- [ ] **Step 2: Run and verify failure**

Expected: missing packaged catalog/guard.

- [ ] **Step 3: Implement packaging**

Copy only worker scripts and catalog metadata. Resolve large models exclusively from Application Support. Fail packaging if a referenced packaged helper is missing; do not fail the app build merely because an optional external model is absent.

- [ ] **Step 4: Run packaging check**

Expected: `TTSLabRuntimePackagingCheck passed`.

- [ ] **Step 5: Commit**

```bash
git add native/build_native_app.sh native/Resources/tts_benchmark_worker.py native/Tests/TTSLabRuntimePackagingCheck.sh THIRD_PARTY_NOTICES.md
git commit -m "build: package TTS reading lab runtime"
```

### Task 6: Run automated and installed-app functional verification

**Files:**
- Modify: `docs/开发日志.md`
- Modify: `native/Sources/Presentation/VersionHistory/VersionHistoryViewController.swift`
- Modify: `docs/ARCHITECTURE.md` if the final runtime boundary differs from existing documentation.

**Interfaces:**
- Produces: verified installed build and durable release narrative.

- [ ] **Step 1: Run all focused checks**

Run every TTS asset, protocol, catalog, service, settings, source, packaging, OpenClaw integration, and cancellation check.
Expected: all print `passed`; existing OpenClaw voice checks remain green.

- [ ] **Step 2: Run offline smoke tests**

Disconnect workers from network and generate one sample with every UI-visible model.
Expected: valid WAV and complete metrics for each.

- [ ] **Step 3: Update durable documentation before build**

Record user-visible section, isolation from OpenClaw, qualified models, cleanup result, known failed candidates, performance result location, and rollback boundary in development log and version history.

- [ ] **Step 4: Recheck concurrency**

Run branch/status, build-process checks, and recent mtime checks required by AGENTS.md.
Expected: no active overlapping build or tracked dirty file from another session.

- [ ] **Step 5: Build, bump, install, open, sign-check, and log**

Run: `./native/build_and_log.sh`.
Expected: build number increments exactly once, `/Applications/TypeWhale Pro.app` is replaced and opened, signature validation passes, build log is appended.

- [ ] **Step 6: Test the real installed app**

In Sound → Reading Lab: test empty input, every qualified model, play, stop during generation, stop during playback, replay, long text, model switching, error layout, metrics, restart persistence, and offline replay. Also trigger an OpenClaw final reply and confirm its existing engine/settings remain unchanged.

### Task 7: Independent design review and final commit

**Files:**
- Modify only files needed to fix review findings.

**Interfaces:**
- Consumes: installed app and approved design.
- Produces: reviewed UI with no unresolved P0/P1 issue.

- [ ] **Step 1: Invoke `design-review`**

Review the real installed Sound page, including hierarchy, spacing, text area behavior, progress/state transitions, flashing/jumps, stop feedback, failure copy, long text, and window resizing.

- [ ] **Step 2: Fix actionable findings with focused regression tests**

For each accepted finding, add or update a test first, reproduce failure, apply the smallest product-correct fix, and rerun focused checks.

- [ ] **Step 3: Rebuild after any code/UI fix**

Run `./native/build_and_log.sh` again only if code changed; this must create a new unique build number.

- [ ] **Step 4: Review scope**

Run: `git status --short` and `git diff --stat`.
Expected: only this feature's files plus required build/version/docs records; protected pre-existing untracked directories remain unstaged.

- [ ] **Step 5: Commit the verified build**

```bash
git add \
  native/Sources/Infrastructure/TTSLab \
  native/Sources/Infrastructure/Settings/TTSReadingLabSettings.swift \
  native/Sources/Application/TTSReadingLabService.swift \
  native/Sources/Presentation/Main/TTSReadingLabView.swift \
  native/Sources/Presentation/Main/MainViewController+TTSReadingLab.swift \
  native/Sources/Presentation/Main/MainViewController.swift \
  native/Sources/Presentation/Main/MainViewController+PanelLayout.swift \
  native/Sources/Presentation/Main/MainViewController+Configuration.swift \
  native/Resources/tts_model_catalog.json \
  native/Resources/tts_benchmark_worker.py \
  native/Tests/TTSLabModelCatalogCheck.swift \
  native/Tests/TTSReadingLabServiceCheck.swift \
  native/Tests/TTSLabWorkerCancellationCheck.swift \
  native/Tests/TTSReadingLabSettingsCheck.swift \
  native/Tests/TTSReadingLabViewSourceCheck.sh \
  native/Tests/TTSLabRuntimePackagingCheck.sh \
  native/build_native_app.sh \
  THIRD_PARTY_NOTICES.md \
  docs/ARCHITECTURE.md \
  docs/开发日志.md \
  docs/构建日志.md \
  native/Sources/Presentation/VersionHistory/VersionHistoryViewController.swift
git commit -m "feat: add local TTS reading lab"
```

- [ ] **Step 6: Report handoff**

Report qualified/failed models, exact cleanup and reclaimed bytes, installed version/build, automatic checks, real-app test paths, design-review outcome, and any device-limited risk.
