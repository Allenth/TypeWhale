# Local TTS Candidate Evaluation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make all eight managed local TTS candidates genuinely testable in the installed TypeWhale Pro reading lab, collect comparable listening/performance evidence, then prepare a separately approved cleanup of losing candidates.

**Architecture:** Keep the App-facing `TTSReadingLabService` independent of individual inference frameworks. A runtime resolver launches one model-specific local adapter behind a shared JSONL protocol; native/Core ML/ONNX paths are preferred, while managed isolated Python environments are allowed only for experimental reference inference. Runtime readiness, benchmark qualification, and installed weights remain separate states.

**Tech Stack:** Swift/AppKit, AVFoundation, Foundation `Process`, JSONL workers, sherpa-onnx, Core ML/TTSKit, llama.cpp + ONNX Runtime, managed Python virtual environments, WAV validation, shell/Python/Swift regression checks.

## Global Constraints

- Evaluation order is listening experience first, resource usage second, deployment purity third.
- All inference must work offline; no cloud fallback or runtime network fetch is allowed.
- Testing may use TypeWhale-managed isolated Python, but must not require user-installed Python, Conda, or Homebrew.
- Reader Demo, OpenClaw voice playback, ASR, VAD, smart rewrite, and paste flows must not change.
- One candidate worker may run at a time; switching models cancels and terminates the previous experimental worker.
- No candidate, runtime, cache, or duplicate weight may be deleted before the product owner reviews the exact cleanup inventory.
- Final cleanup prefers moving recoverable assets to Trash and must be followed by a residue scan and offline replay of retained candidates.
- Every production-code change follows RED → GREEN TDD, gets an atomic commit, then the completed UI change receives design review and installed-app verification.

---

## File Structure

**Create**

- `native/Sources/Infrastructure/TTSLab/TTSLabRuntimeDescriptor.swift`: executable, arguments, environment, and readiness contract for one model.
- `native/Sources/Infrastructure/TTSLab/TTSLabRuntimeResolver.swift`: maps catalog models to native or managed experimental runtimes without UI branching.
- `native/Sources/Infrastructure/TTSLab/TTSLabRuntimeReadinessStore.swift`: persists runtime readiness separately from weight qualification.
- `native/Sources/Infrastructure/TTSLab/TTSLabWaveValidator.swift`: rejects empty, silent, clipped, NaN, or Inf output.
- `native/Sources/Infrastructure/TTSLab/TTSLabEvaluationSuite.swift`: fixed sample IDs and repeat protocol.
- `native/Resources/tts_runtime_worker.py`: common JSONL host for managed reference engines.
- `native/Resources/tts_engines/kokoro_engine.py`: Kokoro reference/diagnostic engine.
- `native/Resources/tts_engines/cosyvoice3_engine.py`: official CosyVoice3 adapter.
- `native/Resources/tts_engines/moss_tts_engine.py`: official MOSS adapter used only if torch-free executable is unavailable.
- `native/Resources/tts_engines/voxcpm2_engine.py`: official VoxCPM2 adapter.
- `native/Helpers/TTSKitBridge/`: checked source/build wrapper for the downloaded TTSKit Core ML models.
- `native/Helpers/MOSSTTSBridge/`: checked source/build wrapper for llama.cpp + ONNX MOSS inference.
- `native/Scripts/tts_runtime_bootstrap.py`: installs locked experimental dependencies into Application Support.
- `native/Scripts/tts_cleanup_inventory.py`: reports exact candidate/runtime/cache paths, references, sizes, and duplicate hashes without deleting.
- `native/Tests/TTSLabRuntimeResolverCheck.swift`
- `native/Tests/TTSLabRuntimeReadinessStoreCheck.swift`
- `native/Tests/TTSLabWaveValidatorCheck.swift`
- `native/Tests/TTSLabEvaluationSuiteCheck.swift`
- `native/Tests/test_tts_runtime_worker.py`
- `native/Tests/test_tts_cleanup_inventory.py`
- `native/Tests/KokoroStabilityProbe.py`
- `native/Tests/TTSKitCoreMLProbe.sh`
- `native/Tests/MOSSTorchFreeProbe.sh`
- `native/Tests/CosyVoice3Probe.sh`
- `native/Tests/VoxCPM2Probe.sh`
- `docs/tts-evaluation/README.md`: manual blind-listening protocol and result interpretation.

**Modify**

- `native/Sources/Infrastructure/TTSLab/TTSLabModel.swift`: add runtime readiness without conflating it with qualification.
- `native/Sources/Infrastructure/TTSLab/TTSLabModelCatalog.swift`: load runtime descriptors and preserve installed-weight truth.
- `native/Sources/Infrastructure/TTSLab/TTSLabWorkerClient.swift`: launch an arbitrary resolved executable and support health/cancel/shutdown.
- `native/Sources/Application/TTSReadingLabService.swift`: enforce one active worker, validate WAV before playback, remove partial outputs.
- `native/Sources/Presentation/Main/MainViewController+TTSReadingLab.swift`: present honest runtime states and disable only models that are not testable.
- `native/Sources/Presentation/Main/TTSReadingLabView.swift`: add a compact runtime-status label and blind-sample action only after runtime plumbing is green.
- `native/Resources/tts_model_catalog.json`: add runtime adapter IDs and pinned runtime metadata.
- `native/build_native_app.sh`: package workers/bridges but never package model weights.
- `native/Tests/TTSLabRuntimePackagingCheck.sh`: assert all required workers and native bridges are packaged.
- `docs/开发日志.md` and `native/Sources/Presentation/VersionHistory/VersionHistoryViewController.swift`: document each shipped build.

---

### Task 1: Separate Weight, Runtime, and Qualification State

**Files:**
- Create: `native/Sources/Infrastructure/TTSLab/TTSLabRuntimeDescriptor.swift`
- Create: `native/Sources/Infrastructure/TTSLab/TTSLabRuntimeReadinessStore.swift`
- Modify: `native/Sources/Infrastructure/TTSLab/TTSLabModel.swift`
- Modify: `native/Sources/Infrastructure/TTSLab/TTSLabModelCatalog.swift`
- Test: `native/Tests/TTSLabRuntimeReadinessStoreCheck.swift`
- Test: `native/Tests/TTSLabModelCatalogCheck.swift`

**Interfaces:**
- Produces: `enum TTSLabRuntimeReadiness`, `struct TTSLabRuntimeDescriptor`, `TTSLabRuntimeReadinessStore.load(modelID:runtimeFingerprint:)`, and `save(_:modelID:runtimeFingerprint:)`.
- Consumers: Tasks 2–9 use readiness to decide whether playback is enabled.

- [ ] **Step 1: Write failing readiness and catalog tests**

```swift
precondition(model.weightState == .installed)
precondition(model.runtimeReadiness == .missing)
store.save(.ready, modelID: model.id, runtimeFingerprint: "coreml-v1")
precondition(store.load(modelID: model.id, runtimeFingerprint: "coreml-v1") == .ready)
precondition(store.load(modelID: model.id, runtimeFingerprint: "coreml-v2") == .unknown)
```

- [ ] **Step 2: Verify RED**

Run:

```bash
swiftc native/Sources/Infrastructure/TTSLab/TTSLabModel.swift \
  native/Sources/Infrastructure/TTSLab/TTSLabRuntimeReadinessStore.swift \
  native/Tests/TTSLabRuntimeReadinessStoreCheck.swift \
  -o /tmp/TTSLabRuntimeReadinessStoreCheck
```

Expected: compile failure because the new readiness types do not exist.

- [ ] **Step 3: Implement minimal state types**

```swift
enum TTSLabRuntimeReadiness: String, Codable, Equatable {
    case unknown, preparing, ready, failed, unavailable
}

enum TTSLabWeightState: String, Codable, Equatable {
    case installed, missing
}
```

`TTSLabModel` must expose both properties and retain `qualification` as independent benchmark history.

- [ ] **Step 4: Run readiness and catalog tests**

Expected: both print `passed`; the existing catalog order and symlink containment checks remain green.

- [ ] **Step 5: Commit**

```bash
git add native/Sources/Infrastructure/TTSLab/TTSLabModel.swift \
  native/Sources/Infrastructure/TTSLab/TTSLabModelCatalog.swift \
  native/Sources/Infrastructure/TTSLab/TTSLabRuntimeDescriptor.swift \
  native/Sources/Infrastructure/TTSLab/TTSLabRuntimeReadinessStore.swift \
  native/Tests/TTSLabRuntimeReadinessStoreCheck.swift \
  native/Tests/TTSLabModelCatalogCheck.swift
git commit -m "feat: separate TTS runtime readiness from model weights"
```

### Task 2: Generalize the Worker Protocol and Validate Audio

**Files:**
- Create: `native/Sources/Infrastructure/TTSLab/TTSLabRuntimeResolver.swift`
- Create: `native/Sources/Infrastructure/TTSLab/TTSLabWaveValidator.swift`
- Modify: `native/Sources/Infrastructure/TTSLab/TTSLabWorkerClient.swift`
- Modify: `native/Sources/Application/TTSReadingLabService.swift`
- Test: `native/Tests/TTSLabRuntimeResolverCheck.swift`
- Test: `native/Tests/TTSLabWaveValidatorCheck.swift`
- Test: `native/Tests/TTSLabWorkerCancellationCheck.swift`
- Test: `native/Tests/TTSReadingLabServiceCheck.swift`

**Interfaces:**
- Consumes: Task 1 `TTSLabRuntimeDescriptor`.
- Produces: `TTSLabRuntimeResolver.resolve(model:)`, `TTSLabWaveValidator.validate(url:)`, and worker commands `health`, `prepare`, `synthesize`, `cancel`, `shutdown`.

- [ ] **Step 1: Write failing resolver and invalid-WAV tests**

```swift
let descriptor = try resolver.resolve(model: qwen06B)
precondition(descriptor.adapterID == "qwen3-tts-coreml")
precondition(descriptor.environment["HF_HUB_OFFLINE"] == "1")

try silentPCM.write(to: output)
precondition(throws: { try TTSLabWaveValidator().validate(url: output) })
```

- [ ] **Step 2: Verify RED**

Expected: compile failure for missing resolver and validator.

- [ ] **Step 3: Implement executable-based worker launch**

```swift
struct TTSLabRuntimeDescriptor: Equatable {
    let adapterID: String
    let executableURL: URL
    let arguments: [String]
    let environment: [String: String]
    let fingerprint: String
}
```

Remove hard-coded `/usr/local/bin/python3` from the default product path. Test fakes may still inject a Python executable.

- [ ] **Step 4: Add WAV validation before playback**

On invalid output, delete the partial WAV and publish `.failed("生成的音频无效：…")`. On cancel, send `cancel`, terminate after a bounded grace interval, and remove unfinished output.

- [ ] **Step 5: Run all four checks**

Expected: resolver, WAV validator, cancellation, and reading-lab service checks print `passed`.

- [ ] **Step 6: Commit**

```bash
git add native/Sources/Infrastructure/TTSLab/TTSLabRuntimeResolver.swift \
  native/Sources/Infrastructure/TTSLab/TTSLabWaveValidator.swift \
  native/Sources/Infrastructure/TTSLab/TTSLabWorkerClient.swift \
  native/Sources/Application/TTSReadingLabService.swift \
  native/Tests/TTSLabRuntimeResolverCheck.swift \
  native/Tests/TTSLabWaveValidatorCheck.swift \
  native/Tests/TTSLabWorkerCancellationCheck.swift \
  native/Tests/TTSReadingLabServiceCheck.swift
git commit -m "feat: add runtime-neutral TTS worker protocol"
```

### Task 3: Reproduce and Resolve Kokoro NaN

**Files:**
- Create: `native/Tests/KokoroStabilityProbe.py`
- Create: `native/Resources/tts_engines/kokoro_engine.py`
- Modify: `native/Resources/tts_benchmark_worker.py`
- Modify: `native/Resources/tts_model_catalog.json`
- Test: `native/Tests/TTSBenchmarkProtocolCheck.py`

**Interfaces:**
- Consumes: Task 2 protocol.
- Produces: deterministic Kokoro stability report containing iteration, input sample ID, voice ID, finite-sample check, peak, RMS, and runtime version.

- [ ] **Step 1: Run the existing sherpa path for at least 12 deterministic iterations**

Run with fixed text/voice/thread count and write JSON results outside the repository.

Expected: reproduce the prior NaN or prove the old failure is not reproducible under the exact installed runtime.

- [ ] **Step 2: Add a failing finite-sample protocol test**

```python
assert response["validation"]["finite"] is True
assert response["validation"]["silent"] is False
```

- [ ] **Step 3: Trace the first non-finite boundary**

Check raw model output before PCM conversion, alternate voice IDs, INT8 versus available non-INT8 weights, and fresh-process versus repeated in-process generation. Record one root-cause hypothesis at a time.

- [ ] **Step 4: Implement the smallest root-cause fix**

Use one of: fresh inference state per request, known-stable voice selection, non-INT8 weight, or alternate local adapter. Do not clamp NaN to zero because that hides model failure.

- [ ] **Step 5: Verify**

Run 12 short/mixed/long generations, cancellation, and an offline rerun. Expected: zero non-finite or silent results.

- [ ] **Step 6: Commit**

```bash
git add native/Tests/KokoroStabilityProbe.py \
  native/Resources/tts_engines/kokoro_engine.py \
  native/Resources/tts_benchmark_worker.py \
  native/Resources/tts_model_catalog.json \
  native/Tests/TTSBenchmarkProtocolCheck.py
git commit -m "fix: stabilize Kokoro TTS evaluation"
```

### Task 4: Connect Both Qwen3-TTS Core ML Candidates

**Files:**
- Create: `native/Helpers/TTSKitBridge/`
- Create: `native/Tests/TTSKitCoreMLProbe.sh`
- Modify: `native/Sources/Infrastructure/TTSLab/TTSLabRuntimeResolver.swift`
- Modify: `native/Resources/tts_model_catalog.json`
- Modify: `native/build_native_app.sh`
- Test: `native/Tests/TTSLabRuntimePackagingCheck.sh`

**Interfaces:**
- Produces executable contract:
  `typewhale-ttskit-worker --model-root <path> --variant <0.6b|1.7b>`.
- JSONL responses match Task 2 and never download at runtime.

- [ ] **Step 1: Write packaging and offline probe tests**

Assert both catalog IDs resolve to the Core ML adapter and the packaged bridge launches with `HF_HUB_OFFLINE=1`.

- [ ] **Step 2: Verify RED**

Expected: missing bridge executable.

- [ ] **Step 3: Build the checked TTSKit bridge**

Use the existing downloaded `qwen3_tts/*/12hz-*-customvoice` assets. The bridge must accept Chinese, English, and mixed text and write PCM WAV.

- [ ] **Step 4: Verify both variants**

For 0.6B and 1.7B run cold, three warm, mixed text, long text, cancel, and offline checks. Store metrics outside the repository.

- [ ] **Step 5: Commit**

```bash
git add native/Helpers/TTSKitBridge native/Tests/TTSKitCoreMLProbe.sh \
  native/Sources/Infrastructure/TTSLab/TTSLabRuntimeResolver.swift \
  native/Resources/tts_model_catalog.json native/build_native_app.sh \
  native/Tests/TTSLabRuntimePackagingCheck.sh
git commit -m "feat: connect Qwen3 TTS Core ML candidates"
```

### Task 5: Connect MOSS Through the Torch-Free Path

**Files:**
- Create: `native/Helpers/MOSSTTSBridge/`
- Create: `native/Tests/MOSSTorchFreeProbe.sh`
- Create: `native/Resources/tts_engines/moss_tts_engine.py`
- Modify: `native/Sources/Infrastructure/TTSLab/TTSLabRuntimeResolver.swift`
- Modify: `native/Resources/tts_model_catalog.json`
- Modify: `native/build_native_app.sh`

**Interfaces:**
- Preferred executable: `typewhale-moss-tts-worker` backed by llama.cpp + ONNX.
- Fallback adapter: managed official Python reference only if the downloaded Local Transformer weights cannot run through the torch-free path.

- [ ] **Step 1: Write the failing offline readiness probe**

Assert the worker rejects missing GGUF/ONNX assets with an actionable `runtime_unavailable` result instead of hanging.

- [ ] **Step 2: Verify current asset compatibility**

Compare the installed safetensors Local Transformer model with the official torch-free asset requirements. Download/convert additional experimental assets only inside the approved 50 GB total budget.

- [ ] **Step 3: Implement the preferred worker or explicit managed fallback**

Never silently label Python fallback as torch-free. Include the actual runtime family in metrics.

- [ ] **Step 4: Verify short, long, cancel, warm, and offline**

Expected: valid WAV or an explicit evidence-backed incompatibility report. No fake audio.

- [ ] **Step 5: Commit**

```bash
git add native/Helpers/MOSSTTSBridge native/Tests/MOSSTorchFreeProbe.sh \
  native/Resources/tts_engines/moss_tts_engine.py \
  native/Sources/Infrastructure/TTSLab/TTSLabRuntimeResolver.swift \
  native/Resources/tts_model_catalog.json native/build_native_app.sh
git commit -m "feat: connect MOSS TTS evaluation runtime"
```

### Task 6: Add Managed Experimental Runtime for CosyVoice3 and VoxCPM2

**Files:**
- Create: `native/Scripts/tts_runtime_bootstrap.py`
- Create: `native/Resources/tts_runtime_worker.py`
- Create: `native/Resources/tts_engines/cosyvoice3_engine.py`
- Create: `native/Resources/tts_engines/voxcpm2_engine.py`
- Create: `native/Tests/test_tts_runtime_worker.py`
- Create: `native/Tests/CosyVoice3Probe.sh`
- Create: `native/Tests/VoxCPM2Probe.sh`
- Modify: `native/Sources/Infrastructure/TTSLab/TTSLabRuntimeResolver.swift`
- Modify: `native/build_native_app.sh`

**Interfaces:**
- Runtime root: `Application Support/TypeWhale Pro/Runtimes/tts/<fingerprint>/`.
- Bootstrap accepts `--adapter cosyvoice3|voxcpm2 --offline-after-install`.
- Worker imports only from its managed environment and emits Task 2 JSONL.

- [ ] **Step 1: Write bootstrap and worker protocol tests**

Assert locked dependency metadata, runtime containment, offline environment variables, health response, cancellation, and no system-site-packages.

- [ ] **Step 2: Verify RED**

Expected: managed runtime and adapter modules missing.

- [ ] **Step 3: Bootstrap CosyVoice3 from the official implementation**

Pin exact dependency versions and save a runtime fingerprint. Do not use the Rust port as the only quality baseline.

- [ ] **Step 4: Bootstrap VoxCPM2 from the official implementation**

Run single-process/single-model only. Set a bounded prepare timeout and terminate on cancel.

- [ ] **Step 5: Verify each adapter**

Run Chinese, English/mixed where supported, long text, three warm repeats, cancellation, and offline restart. Record unsupported languages honestly.

- [ ] **Step 6: Commit**

```bash
git add native/Scripts/tts_runtime_bootstrap.py native/Resources/tts_runtime_worker.py \
  native/Resources/tts_engines/cosyvoice3_engine.py \
  native/Resources/tts_engines/voxcpm2_engine.py \
  native/Tests/test_tts_runtime_worker.py native/Tests/CosyVoice3Probe.sh \
  native/Tests/VoxCPM2Probe.sh \
  native/Sources/Infrastructure/TTSLab/TTSLabRuntimeResolver.swift \
  native/build_native_app.sh
git commit -m "feat: add isolated TTS reference runtimes"
```

### Task 7: Build the Fixed Evaluation Suite and Blind Listening Outputs

**Files:**
- Create: `native/Sources/Infrastructure/TTSLab/TTSLabEvaluationSuite.swift`
- Create: `native/Tests/TTSLabEvaluationSuiteCheck.swift`
- Create: `docs/tts-evaluation/README.md`
- Modify: `native/Sources/Infrastructure/TTSLab/TTSLabResultStore.swift`

**Interfaces:**
- Produces fixed sample IDs `zh-short-v1`, `en-short-v1`, `mixed-v1`, `zh-long-v1`.
- Produces anonymized output filenames and records model/runtime/weight fingerprints without storing free-form user text.

- [ ] **Step 1: Write failing sample/privacy tests**

Assert stable sample IDs, randomized blind labels, no model name in blind filename, and no free-form source text in persisted metrics.

- [ ] **Step 2: Implement the fixed suite**

Use product-representative Chinese, English, mixed technical terms, dates, numbers, and a long paragraph.

- [ ] **Step 3: Run the suite across all ready models**

Expected per ready model: one cold, three warm, one long, one cancel, one switch-back, and offline restart.

- [ ] **Step 4: Commit**

```bash
git add native/Sources/Infrastructure/TTSLab/TTSLabEvaluationSuite.swift \
  native/Sources/Infrastructure/TTSLab/TTSLabResultStore.swift \
  native/Tests/TTSLabEvaluationSuiteCheck.swift docs/tts-evaluation/README.md
git commit -m "feat: add blind local TTS evaluation suite"
```

### Task 8: Present Honest Runtime State in the Reading Lab

**Files:**
- Modify: `native/Sources/Presentation/Main/MainViewController+TTSReadingLab.swift`
- Modify: `native/Sources/Presentation/Main/TTSReadingLabView.swift`
- Modify: `native/Tests/TTSReadingLabViewSourceCheck.sh`
- Modify: `docs/开发日志.md`
- Modify: `native/Sources/Presentation/VersionHistory/VersionHistoryViewController.swift`

**Interfaces:**
- Consumes: Tasks 1–7 readiness and evaluation state.
- Produces model labels `权重已下载`, `运行时准备中`, `可测试`, `测试失败`, `资格通过`, or `已淘汰`.

- [ ] **Step 1: Write failing presentation checks**

Assert unavailable models cannot play, ready models can play, and “已下载” never implies “可测试”.

- [ ] **Step 2: Implement minimal UI**

Keep all eight candidates visible. Show actionable errors without absolute paths. Add blind-sample generation only after all runtime commands are stable.

- [ ] **Step 3: Run UI/source/service regression checks**

Expected: all pass, including OpenClaw backend boundary and Reader Demo non-interference checks.

- [ ] **Step 4: Perform design review**

Verify hierarchy, disabled-state clarity, long labels, progress, cancel feedback, no flicker, and no loss of typed text.

- [ ] **Step 5: Commit**

```bash
git add native/Sources/Presentation/Main/MainViewController+TTSReadingLab.swift \
  native/Sources/Presentation/Main/TTSReadingLabView.swift \
  native/Tests/TTSReadingLabViewSourceCheck.sh docs/开发日志.md \
  native/Sources/Presentation/VersionHistory/VersionHistoryViewController.swift
git commit -m "feat: show truthful TTS runtime readiness"
```

### Task 9: Build, Install, and Run the Full Candidate Matrix

**Files:**
- Modify: `native/Tests/TTSLabRuntimePackagingCheck.sh`
- Modify: `docs/构建日志.md` via `./native/build_and_log.sh`
- Modify: `README.md`, `macos/README.md`, `native/build_native_app.sh` via build bump.

- [ ] **Step 1: Re-run concurrency checks**

Confirm correct branch, protected dirty files, build processes, and recent mtimes.

- [ ] **Step 2: Run all TTS checks**

```bash
zsh native/Tests/TTSReadingLabViewSourceCheck.sh
zsh native/Tests/TTSLabRuntimePackagingCheck.sh
zsh native/Tests/OpenClawTTSBackendBoundaryCheck.sh
python3 native/Tests/TTSBenchmarkProtocolCheck.py
python3 native/Tests/test_tts_runtime_worker.py
```

Expected: all pass with no network access during inference.

- [ ] **Step 3: Build and install**

```bash
./native/build_and_log.sh
```

Expected: unique build number, `/Applications/TypeWhale Pro.app` overwritten and opened, signature valid.

- [ ] **Step 4: Verify the installed App**

For every candidate, generate fixed samples, play audio, stop mid-generation, switch away/back, and capture metrics. Verify Reader Demo and OpenClaw remain unchanged.

- [ ] **Step 5: Commit the build record**

Stage only build-generated version files and commit `build: install TypeWhale Pro 2.0.58 build <N>`.

### Task 10: Produce Cleanup Inventory Without Deleting

**Files:**
- Create: `native/Scripts/tts_cleanup_inventory.py`
- Create: `native/Tests/test_tts_cleanup_inventory.py`
- Create: `docs/tts-evaluation/cleanup-inventory.md` from the final local scan.

**Interfaces:**
- Produces JSON/Markdown with exact path, bytes, asset kind, model owner, shared references, duplicate hash group, and proposed action.
- Does not expose a delete flag.

- [ ] **Step 1: Write failing containment/reference/duplicate tests**

Use temporary model/runtime/cache trees and verify paths outside approved roots are reported but never proposed for automatic removal.

- [ ] **Step 2: Implement read-only inventory**

Approved roots are explicit Application Support TTS roots, known old lab roots, managed runtime roots, and identified cache directories. No glob-based deletion is permitted.

- [ ] **Step 3: Generate the real inventory**

Include retained 1–2 candidates only after the product owner completes blind listening. Until then mark every candidate `decision_pending`.

- [ ] **Step 4: Stop for destructive approval**

Present exact targets and recoverability. Only after explicit approval may a separate cleanup execution plan move losing assets to Trash and verify residue.

- [ ] **Step 5: Commit inventory tooling**

```bash
git add native/Scripts/tts_cleanup_inventory.py \
  native/Tests/test_tts_cleanup_inventory.py docs/tts-evaluation/cleanup-inventory.md
git commit -m "chore: inventory experimental TTS assets"
```
