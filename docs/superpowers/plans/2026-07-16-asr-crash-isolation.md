# ASR Candidate Crash Isolation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prevent every optional ASR candidate from terminating TypeWhale Pro, correct production hotword payloads, and verify all ten models with one real WAV.

**Architecture:** Keep stable SenseVoice preview/fallback in the App. Run Qwen3 and Parakeet Sherpa candidates through a bundled line-JSON helper process; retain existing FunASR and MLX sidecars. Separate strict benchmark hotword encoding from production-compatible encoding so unsupported or unrepresentable production entries never block model loading.

**Tech Stack:** Swift 5, C sherpa-onnx bridge, Foundation `Process`/pipes, line-delimited Codable JSON, AppKit, shell and standalone Swift tests.

## Global Constraints

- Candidate native crashes must become helper/sidecar errors and a single SenseVoice fallback, never App termination.
- Qwen3 Sherpa, Parakeet, SenseVoice, and Qwen MLX receive no production hotwords.
- Paraformer production payload skips whitespace-containing entries and logs the skipped count; benchmark encoding remains strict.
- SenseVoice realtime preview and VAD remain in-process and unchanged.
- Any model failing the installed real-WAV matrix is not reported as verified for release.

---

### Task 1: Correct hotword capability and production encoding

**Files:**
- Modify: `native/Sources/Infrastructure/ASR/ASRModelRegistry.swift`
- Modify: `native/Sources/Infrastructure/ASR/ASRProviderCapabilities.swift`
- Modify: `native/Sources/Infrastructure/ASR/ASRHotwordEncoder.swift`
- Modify: `native/Sources/Application/UnifiedLocalASRAdapter.swift`
- Modify: `native/Sources/Application/ProviderAwareFinalASR.swift`
- Modify: `native/Tests/ASRHotwordEncoderCheck.swift`
- Modify: `native/Tests/ASRProviderCapabilitiesCheck.swift`

**Interfaces:**
- Produces `ASRHotwordEncoder.encodeProduction(words:strategy:) -> ASRProductionHotwordEncoding` with payload and skipped terms.
- Keeps strict `encode(words:strategy:)` unchanged for benchmark requests.

- [ ] Add failing tests requiring Qwen Sherpa `.unsupported`, production Paraformer filtering, and strict benchmark rejection.
- [ ] Run the tests and observe failures caused by the current `.sherpaInline` and all-or-nothing encoder.
- [ ] Implement the production encoder and use it in `ProviderAwareFinalASR` warmup/transcription while retaining strict benchmark behavior.
- [ ] Run hotword, capabilities, and provider-routing tests until green.

### Task 2: Build a crash-contained Sherpa helper

**Files:**
- Create: `native/Sources/Infrastructure/ASR/SherpaASRSidecarProtocol.swift`
- Create: `native/Sources/Infrastructure/ASR/SherpaASRSidecar.swift`
- Create: `native/Helpers/TypeWhaleSherpaASR.swift`
- Create: `native/Tests/Fixtures/fake_sherpa_asr_worker.py`
- Create: `native/Tests/SherpaASRSidecarCheck.swift`
- Create: `native/Tests/SherpaASRSidecarCrashCheck.swift`

**Interfaces:**
- `SherpaASRSidecar.warmUp(providerID:modelDirectory:completion:)` and `transcribe(providerID:audioURL:completion:)`.
- JSON commands `health`, `warmup`, `transcribe`, `shutdown`; responses carry request ID, engine, timings, text, or error.

- [ ] Add protocol round-trip and fake-worker success tests before implementation.
- [ ] Add a fake worker that exits 255 during transcribe and assert the Swift sidecar returns failure exactly once.
- [ ] Implement bounded line reading, process-exit handling, provider-aware warmup, and safe stop.
- [ ] Implement the bundled helper using the existing C bridge, accepting no hotwords for Qwen/Parakeet.
- [ ] Run success, crash, timeout, and protocol mismatch checks.

### Task 3: Route Sherpa candidates through the helper and package it

**Files:**
- Modify: `native/Sources/Application/LocalASREngineAdapters.swift`
- Modify: `native/Sources/Application/SpeechInputCoordinator.swift`
- Modify: `native/build_native_app.sh`
- Modify: `native/Tests/UnifiedLocalASRAdapterCheck.swift`
- Create: `native/Tests/SherpaCandidateIsolationBoundaryCheck.sh`

**Interfaces:**
- `SherpaLocalEngineAdapter` wraps `SherpaASRSidecar`; `UnifiedLocalASRAdapter` keeps its public API.
- Installed helper path is `Contents/Resources/TypeWhaleSherpaASR` with rpath to `Resources/NativeASR/lib`.

- [ ] Add failing boundaries rejecting production use of `SherpaBenchmarkAdapter` and requiring the helper resource.
- [ ] Wire the production engine map to the sidecar adapter, leaving benchmark UI behavior and SenseVoice fallback intact.
- [ ] Compile the helper with `TypeSpeakerNativeASR.o`, sign it as part of the App bundle, and verify its health command.
- [ ] Run typecheck and existing final-routing tests.

### Task 4: Real matrix, installed verification, and release

**Files:**
- Create: `native/Tests/InstalledASRMatrixCheck.swift` or an equivalent read-only matrix runner.
- Modify: `docs/开发日志.md`
- Modify: `native/Sources/Presentation/VersionHistory/VersionHistoryViewController.swift`
- Build-generated version files from `native/build_and_log.sh`.

**Interfaces:**
- Uses one existing real WAV and the current production lexicon to emit provider, cold/warm outcome, text, engine, and fallback count.

- [ ] Run the Qwen crash WAV directly through the helper with no hotwords and confirm nonempty output.
- [ ] Force the helper to exit during a request and confirm the App-side call returns a recoverable error.
- [ ] Run all ten models against one WAV; classify each as direct success, safe fallback, or unavailable with reason.
- [ ] Update release history with exact verified results, run full regression/typecheck/concurrency checks, then `./native/build_and_log.sh`.
- [ ] Verify installed version, signature, helper health, App survival, model switching, recording, fallback behavior, and restore the original model only if it is safe.
- [ ] Commit implementation and release outputs with a clean worktree.
