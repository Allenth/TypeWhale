# ZipVoice-Only TTS Consolidation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make ZipVoice with four qualified voices the only TypeWhale Pro TTS model, migrate OpenClaw to it, and recoverably retire all other TypeWhale Pro TTS assets.

**Architecture:** A single persistent ZipVoice JSON-lines worker contract serves both the Sounds reading panel and OpenClaw. A manifest-driven cleanup gate proves asset boundaries, installed-app takeover, and rollback metadata before moving exact retired paths to macOS Trash.

**Tech Stack:** Swift/AppKit, Python 3 standard library, sherpa-onnx ZipVoice, AVFoundation, shell source-boundary tests, macOS code signing and Application Support.

## Global Constraints

- Preserve Reader Demo, ASR, VAD, punctuation, LLM, rewriting, hotwords, and screenshot/OCR behavior.
- Preserve `zipvoice-distill-int8-zh-en-emilia` and exactly four qualified voice IDs.
- Do not permanently delete assets; move verified exact paths to macOS Trash.
- Do not use recursive wildcard deletion.
- Keep historical release notes intact.
- Use test-first RED/GREEN cycles for each behavior change.
- Build, increment the build number, install, launch, sign-verify, visually review, and commit before physical cleanup.
- Stop physical cleanup if any installed-app or OpenClaw gate fails.

---

### Task 1: Auditable Cleanup Planner

**Files:**
- Create: `tools/tts_zipvoice_cleanup.py`
- Create: `native/Tests/TTSZipVoiceCleanupCheck.py`

**Interfaces:**
- Produces: `build_plan(models_root, runtimes_root, protected_roots) -> dict`
- Produces: CLI modes `--plan`, `--verify-gate`, and `--execute-to-trash`
- Produces: JSON entries with original path, byte count, disposition, reason, and optional trash path

- [ ] **Step 1: Write the failing boundary test**

Test exact retained ZipVoice path, all retired model paths, exclusive runtime
paths, staging paths, Reader Demo exclusion, symlink rejection, root rejection,
stable byte accounting, deterministic JSON, dry-run behavior, and refusal to
execute without a valid installed-build verification record.

- [ ] **Step 2: Run RED**

Run:

```bash
python3 native/Tests/TTSZipVoiceCleanupCheck.py
```

Expected: fail because `tools/tts_zipvoice_cleanup.py` does not exist.

- [ ] **Step 3: Implement the planner and trash mover**

Use `pathlib.Path.resolve`, `lstat`, explicit approved roots, containment checks,
and `os.rename` into a unique path below `~/.Trash`. Never follow symlinks and
never accept an approved root itself as a target. Write reports atomically.

- [ ] **Step 4: Run GREEN**

Run the test and expect `TTSZipVoiceCleanupCheck passed`.

- [ ] **Step 5: Generate a dry-run inventory**

Write the machine-readable report to
`docs/tts/zipvoice-only-cleanup-plan.json`; verify that it retains ZipVoice,
excludes Reader Demo, and reports expected reclaimable bytes.

- [ ] **Step 6: Commit**

Commit the planner, test, and dry-run report separately from product migration.

---

### Task 2: OpenClaw ZipVoice Contract

**Files:**
- Modify: `native/Sources/Infrastructure/Settings/OpenClawVoiceSettings.swift`
- Modify: `native/Sources/Infrastructure/OpenClaw/OpenClawVoicePlayback.swift`
- Modify: `native/Sources/Infrastructure/TTSLab/TTSLabWorkerClient.swift`
- Modify: `native/Sources/Infrastructure/TTSLab/TTSLabRuntimeResolver.swift`
- Test: `native/Tests/OpenClawVoiceSettingsCheck.swift`
- Test: `native/Tests/OpenClawVoicePlaybackCheck.swift`
- Test: `native/Tests/OpenClawVoicePlaybackIntegrationCheck.sh`
- Create: `native/Tests/OpenClawZipVoiceBoundaryCheck.sh`

**Interfaces:**
- Consumes: `TTSLabVoiceCatalog.candidates(for:)`
- Produces: one productized `OpenClawVoiceEngine.zipVoice`
- Produces: persisted `voiceID` validated against the four-voice catalog
- Produces: OpenClaw backend that starts the qualified ZipVoice descriptor and rejects mismatched actual voice identity

- [ ] **Step 1: Add failing settings tests**

Assert all legacy engine values migrate to ZipVoice, missing/invalid voices fall
back to `zipvoice-default`, and each of the four valid voices round-trips.

- [ ] **Step 2: Run RED**

Compile and run `OpenClawVoiceSettingsCheck`; expect failure because ZipVoice
is not an OpenClaw engine and no voice ID is persisted.

- [ ] **Step 3: Implement minimal settings migration**

Replace productized engine choices with ZipVoice while retaining decoding of
legacy raw values solely for migration. Add normalized `voiceID`.

- [ ] **Step 4: Run settings GREEN**

Expect `OpenClawVoiceSettingsCheck passed`.

- [ ] **Step 5: Add failing playback contract tests**

Assert OpenClaw starts the ZipVoice worker, sends `voiceID`, validates the
returned ID, reuses a warm process, stops/cancels safely, removes partial WAV,
and never selects the Melo pack.

- [ ] **Step 6: Run playback RED**

Expect the old Sherpa Melo backend selection to violate the new assertions.

- [ ] **Step 7: Implement shared ZipVoice backend lifecycle**

Adapt the existing persistent worker client behind `OpenClawTTSBackend`; keep
OpenClaw queue, interruption, notification, volume, speech-rate, and output
ownership semantics unchanged.

- [ ] **Step 8: Run playback GREEN and regressions**

Run OpenClaw settings, playback, integration, reply lifecycle, source-boundary,
TTS worker voice, WAV validator, and cancellation checks.

- [ ] **Step 9: Commit**

Commit the OpenClaw takeover before removing any legacy route or asset.

---

### Task 3: Product and Build Surface Consolidation

**Files:**
- Modify: `native/Resources/tts_model_catalog.json`
- Modify: `native/Sources/Infrastructure/TTSLab/TTSLabModelCatalog.swift`
- Modify: `native/Sources/Infrastructure/TTSLab/TTSLabRuntimeResolver.swift`
- Modify: `native/Sources/Infrastructure/Models/ManagedASRModelCatalog.swift`
- Modify: `native/Sources/Presentation/Main/MainViewController+TTSReadingLab.swift`
- Modify: `native/Sources/Presentation/Main/MainViewController+PanelLayout.swift`
- Modify: `native/build_native_app.sh`
- Modify: `THIRD_PARTY_NOTICES.md`
- Modify or remove only active legacy TTS workers and engines proven unused by boundary tests
- Test: `native/Tests/TTSLabModelCatalogCheck.swift`
- Test: `native/Tests/TTSLabRuntimeResolverCheck.swift`
- Test: `native/Tests/TTSReadingLabViewSourceCheck.sh`
- Test: `native/Tests/TTSLabRuntimePackagingCheck.sh`
- Modify: `native/Tests/OpenClawTTSBackendBoundaryCheck.sh`

**Interfaces:**
- Produces: one installed TTS model and four voices
- Produces: no OpenClaw engine selector
- Produces: build package with only resources required by ZipVoice

- [ ] **Step 1: Add failing single-model/source-boundary tests**

Assert the active catalog contains only ZipVoice, the Sounds model selector is
removed or fixed, the OpenClaw engine selector is absent, retired download
entries are absent, and packaged resources exclude TTSKit and retired Python
engines.

- [ ] **Step 2: Run RED**

Expect catalog counts, UI source checks, and packaging checks to fail against
the current multi-engine implementation.

- [ ] **Step 3: Remove retired production choices and build dependencies**

Keep reusable historical tests only when they validate preserved contracts;
remove or archive tests that require retired models. Do not edit historical
release notes.

- [ ] **Step 4: Run GREEN and full TTS/OpenClaw regression**

Run all active TTS, ZipVoice, OpenClaw playback, packaging, privacy, and model
boundary checks. Run `git diff --check`.

- [ ] **Step 5: Commit**

Commit product surface consolidation separately from disk cleanup.

---

### Task 4: Installed-App Gate

**Files:**
- Modify: `docs/开发日志.md`
- Modify: `native/Sources/Presentation/VersionHistory/VersionHistoryViewController.swift`
- Build-managed version and build-log files
- Create: `docs/tts/zipvoice-only-installed-verification.json`

**Interfaces:**
- Produces: signed installed build verification record consumed by cleanup execution

- [ ] **Step 1: Update release narrative**

Record the ZipVoice-only boundary, four voices, OpenClaw takeover, retained
Python dependency, rollback behavior, and protected Reader Demo boundary.

- [ ] **Step 2: Check concurrency and build**

Run `./native/build_and_log.sh`; require a unique build number, successful
install, app launch, and strict signature verification.

- [ ] **Step 3: Verify real Sounds UI**

Confirm one model, four untruncated voices, editable text, playback state,
metrics, replay, and restart persistence.

- [ ] **Step 4: Verify real OpenClaw behavior**

Exercise four voices, cold and warm synthesis, long Chinese, English, mixed
text, three sequential replies, latest-wins interruption, queueing, stop, and
restart. Inspect logs/processes to prove the ZipVoice model and actual voice ID.

- [ ] **Step 5: Write signed gate evidence**

Record build/version, app worker hash, ZipVoice pack manifest hash, qualification
fingerprint, test results, playback evidence, Reader Demo inventory hash, and
timestamp. The cleanup tool validates these fields against current state.

- [ ] **Step 6: Design review and commit**

Review Sounds and OpenClaw UI in the installed app, then commit release records
and verification evidence.

---

### Task 5: Recoverable Physical Cleanup and Post-Cleanup Verification

**Files:**
- Create: `docs/tts/zipvoice-only-cleanup-report.json`
- Modify: `docs/开发日志.md`
- Build-managed release records only if post-cleanup fixes are required

**Interfaces:**
- Consumes: dry-run plan and installed verification record
- Produces: exact original-to-Trash recovery map and reclaimed byte total

- [ ] **Step 1: Regenerate and compare the plan**

Fail closed if model paths, byte totals, protected hashes, build identity, or
source-boundary results differ from the verified plan.

- [ ] **Step 2: Execute exact-path moves to Trash**

Move retired TypeWhale Pro model directories, exclusive runtimes, and staging
residue one entry at a time. Do not touch `LocalTTSLab` in this pass unless its
provenance is separately proven. Do not empty Trash.

- [ ] **Step 3: Verify post-cleanup filesystem state**

Assert ZipVoice hashes and four references are unchanged, retired TypeWhale Pro
paths are absent, Reader Demo inventory is unchanged, and reclaimed bytes match.

- [ ] **Step 4: Restart installed app and repeat critical paths**

Repeat Sounds four-voice playback and OpenClaw cold/warm/interrupt/stop checks
offline. A failure triggers restoration from the recorded Trash paths.

- [ ] **Step 5: Run fresh full regression**

Run all active automated checks, strict signature verification, resource
inspection, process inspection, `git diff --check`, and `git status --short`.

- [ ] **Step 6: Record and commit cleanup evidence**

Commit only repository reports and documentation. Keep the branch in the main
workspace; do not push, merge, or delete it without an explicit request.
