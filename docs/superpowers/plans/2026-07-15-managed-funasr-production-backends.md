# Managed FunASR Production Backends Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Fun-ASR Nano and Paraformer Contextual as production final-recognition choices while SenseVoice remains the default and automatic fallback.

**Architecture:** Keep native SenseVoice unchanged and route only final recognition through a provider-aware transcriber. FunASR runs in a persistent, newline-delimited JSON sidecar outside the app process; a Swift supervisor owns lifecycle, task identity, timeout, cancellation, health, and one-shot SenseVoice fallback.

**Tech Stack:** Swift/AppKit, Foundation `Process` and pipes, Python 3.10 managed virtual environment, FunASR/PyTorch/ModelScope, JSONL IPC, existing shell/Swift boundary checks.

## Global Constraints

- SenseVoice is the default and remains usable during every installation and failure state.
- Do not change recording, Silero VAD, realtime preview, smart rewrite, translation, recent-history, or paste semantics.
- FunASR affects final recognition only; realtime preview remains SenseVoice-only.
- Audio remains local and raw text/audio is not added to diagnostics.
- The app never depends on a user-configured Python environment.
- Do not add an idle ASR unload timer.
- After code changes, use `./native/build_and_log.sh`, overwrite `/Applications/TypeWhale Pro.app`, launch it, and verify the installed build.

---

### Task 1: Prove both downloaded models through an isolated runtime

**Files:**
- Modify: `tools/asr-eval/run_funasr_eval.py`
- Create: `tools/asr-eval/funasr_runtime_requirements.txt`
- Test: `native/Tests/FunASREvalRunnerContractCheck.sh`

**Interfaces:**
- Consumes: provider ID, model directory, WAV path, hotword list.
- Produces: one JSONL row with `status`, `rawText`, `elapsedMs`, `engine`, `error`, and hotword scoring.

- [ ] Add a failing contract assertion that a non-dry provider no longer returns `provider_runtime_not_wired` when `TYPEWHALE_FUNASR_SPIKE=1` and the managed interpreter is supplied.
- [ ] Run `bash native/Tests/FunASREvalRunnerContractCheck.sh`; expect the new assertion to fail.
- [ ] Pin the runtime packages in `funasr_runtime_requirements.txt` and implement provider loaders with `funasr.AutoModel`, local model paths, CPU/MPS-safe device selection, `disable_update=True`, and provider-specific hotword arguments.
- [ ] Create the isolated runtime outside the repository, install the pinned requirements, and transcribe a real local WAV with Fun-ASR Nano and Paraformer Contextual.
- [ ] Record load time, inference time, output, peak process memory, and any model-specific compatibility fix. Do not continue if either provider cannot produce text.
- [ ] Re-run the contract check and the real spike; expect both providers to return `status=ok`.
- [ ] Commit the runner and dependency lock.

### Task 2: Define production provider and availability contracts

**Files:**
- Modify: `native/Sources/Domain/ASRDomain.swift`
- Modify: `native/Sources/Infrastructure/ASR/ASRProviderCapabilities.swift`
- Modify: `native/Sources/Infrastructure/Models/ManagedASRModelCatalog.swift`
- Create: `native/Sources/Infrastructure/ASR/FunASRRuntimeManifest.swift`
- Test: `native/Tests/ASRProviderCapabilitiesCheck.swift`
- Test: `native/Tests/ManagedASRModelCatalogCheck.swift`
- Create: `native/Tests/FunASRRuntimeManifestCheck.swift`

**Interfaces:**
- Produces: `ASRBackend.funASRNano`, `ASRBackend.paraformerContextual`, stable menu tags, runtime version, required modules, and provider model validation.

- [ ] Add failing assertions for the exact three user-facing backends, SenseVoice default resolution, stable raw values, provider capabilities, and strict required-file validation.
- [ ] Run the focused Swift checks; expect failures for missing cases and manifest types.
- [ ] Add the two backend cases without changing persisted SenseVoice behavior; remove `automatic` from the user-visible path and migrate legacy `automatic` to SenseVoice.
- [ ] Add provider-specific required-file lists and a versioned runtime manifest. A directory containing only an arbitrary regular file must not count as installed.
- [ ] Run the focused checks; expect passes.
- [ ] Commit the provider contracts.

### Task 3: Build and verify the managed runtime installer

**Files:**
- Create: `native/Sources/Infrastructure/ASR/ManagedFunASRRuntime.swift`
- Create: `native/Sources/Infrastructure/ASR/FunASRRuntimeInstaller.swift`
- Create: `native/Resources/funasr_runtime_requirements.txt`
- Modify: `native/Sources/Infrastructure/Paths/AppPaths.swift`
- Create: `native/Tests/ManagedFunASRRuntimeCheck.swift`

**Interfaces:**
- Produces: `FunASRRuntimeState`, `ManagedFunASRRuntime.current`, `install(progress:completion:)`, `verify()`, and `pythonURL`.

- [ ] Write tests for missing, staging, invalid, ready, and version-mismatch states using temporary directories and injected process/download functions.
- [ ] Run the focused check; expect failure because the runtime manager is absent.
- [ ] Implement staging installation, fixed runtime versioning, dependency installation from the bundled lock file, import verification, activation by atomic directory replacement, and cleanup of failed staging directories.
- [ ] Ensure production discovery accepts only the TypeWhale-managed runtime root; system Python may be injected only by tests and the isolated developer spike.
- [ ] Run the focused check; expect all state transitions to pass.
- [ ] Commit the managed runtime installer.

### Task 4: Implement the persistent FunASR JSONL sidecar and Swift supervisor

**Files:**
- Create: `native/Resources/funasr_asr_worker.py`
- Create: `native/Sources/Infrastructure/ASR/FunASRSidecarProtocol.swift`
- Create: `native/Sources/Infrastructure/ASR/FunASRSidecar.swift`
- Create: `native/Tests/FunASRWorkerProtocolCheck.py`
- Create: `native/Tests/FunASRSidecarProtocolCheck.swift`

**Interfaces:**
- Worker requests: `health`, `warmup`, `transcribe`, `shutdown` with UUID request IDs.
- Worker responses: same ID, `ok`, `text`, `engine`, `duration_sec`, `error`.
- Supervisor: `warmUp(backend:)`, `transcribe(audio:configuration:completion:)`, `stop()`.

- [ ] Write failing protocol tests for health, warmup, transcription, malformed input, mismatched IDs, process exit, timeout, and late output.
- [ ] Run Python and Swift focused tests; expect missing worker/supervisor failures.
- [ ] Implement a one-model-at-a-time worker that imports models only after startup, emits JSON only on stdout, redirects library chatter to stderr, and never downloads or updates models during inference.
- [ ] Implement the serial Swift supervisor using `Process`, stdin/stdout pipes, per-request deadlines, task IDs, and deterministic process teardown.
- [ ] Run protocol tests; expect passes without loading real models by using an injected fake loader/worker.
- [ ] Run one real warmup/transcription through the installed runtime for both providers.
- [ ] Commit the sidecar and supervisor.

### Task 5: Route final recognition with one-shot SenseVoice fallback

**Files:**
- Create: `native/Sources/Application/ProviderAwareFinalASR.swift`
- Modify: `native/Sources/Application/FinalRecognitionASRAdapter.swift`
- Modify: `native/Sources/Application/SpeechInputCoordinator.swift`
- Create: `native/Tests/ProviderAwareFinalASRCheck.swift`
- Modify: `native/Tests/FinalRecognitionUseCaseCheck.swift`

**Interfaces:**
- `ProviderAwareFinalASR` conforms to `FinalASRTranscribing`.
- It delegates SenseVoice directly, delegates FunASR through the sidecar, and on failure/empty output invokes SenseVoice exactly once for the same audio/configuration.

- [ ] Write failing tests for direct SenseVoice, successful FunASR, model missing, runtime missing, timeout, crash, empty output, exactly-one fallback, and suppression of late sidecar completion.
- [ ] Run focused tests; expect missing router failures.
- [ ] Implement the provider-aware transcriber and inject it into `FinalRecognitionUseCase`; leave realtime and VAD bridges native.
- [ ] Add diagnostics containing provider, request/task ID, duration, error class, fallback reason, and final engine without raw audio/text.
- [ ] Run focused tests; expect passes.
- [ ] Commit the production final-ASR routing.

### Task 6: Complete the model-selection and runtime-state UI

**Files:**
- Modify: `native/Sources/Presentation/Main/MainViewController+Configuration.swift`
- Modify: `native/Sources/Presentation/Main/MainViewController+Actions.swift`
- Modify: `native/Sources/Application/SpeechInputCoordinator.swift`
- Modify: `native/Tests/PrimaryMicrophoneUIBoundaryCheck.sh` or create `native/Tests/FunASRBackendUIBoundaryCheck.sh`

**Interfaces:**
- The menu contains SenseVoice, Fun-ASR Nano, and Paraformer Contextual.
- Status states are model missing, runtime missing, installing, warming, ready, unhealthy, and fallback active.

- [ ] Add failing UI boundary checks for the exact labels, default selection, unavailable-selection installation action, final-only preview copy, and persistence.
- [ ] Run the UI check; expect failure.
- [ ] Implement menu/state behavior. Do not persist an unavailable backend until its runtime and model verify successfully.
- [ ] Show that FunASR selections use SenseVoice realtime preview and FunASR final recognition.
- [ ] Run UI checks; expect passes.
- [ ] Commit the UI integration.

### Task 7: Regression suite, documentation, versioning, build, install, and real verification

**Files:**
- Modify: `README.md`
- Modify: `macos/README.md`
- Modify: `docs/ARCHITECTURE.md`
- Modify: `docs/开发日志.md`
- Modify: `native/Sources/Presentation/VersionHistory/VersionHistoryViewController.swift`
- Generated by build: `docs/构建日志.md`

- [ ] Run all ASR/provider/runtime/sidecar focused tests and `git diff --check`; expect zero failures.
- [ ] Run the shared evaluation runner for SenseVoice, Fun-ASR Nano, and Paraformer Contextual on real WAV input; verify non-empty text, engine labels, and recorded latency.
- [ ] Force missing runtime, missing model, worker crash, timeout, and empty output; verify each current recording falls back once to SenseVoice and remains pasteable.
- [ ] Perform an independent design-quality review of the selector/status changes using the `design-review` skill and fix all P0/P1 findings.
- [ ] Update architecture, developer log, version history, READMEs, runtime/model provenance, and manual verification steps.
- [ ] Re-run the concurrency safety check, then run `./native/build_and_log.sh` and allow the script to choose build-only versus full-version according to repository policy.
- [ ] Verify `/Applications/TypeWhale Pro.app` version/signature, launch the installed app, select all three providers, restart for persistence, dictate real Chinese and mixed-language samples, and force a fallback.
- [ ] Inspect installed-build logs for the requested and final engines and confirm no private audio/text was logged.
- [ ] Review `git status --short`, commit only this task's release/documentation changes when repository policy requires it, and leave unrelated work untouched.
