# Local ASR Benchmark and Production Backends Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every complete local ASR model discoverable and genuinely runnable, expose fair same-WAV benchmarking with native hotword formats, and enable production-ready models in the final-ASR dropdown.

**Architecture:** Add one model registry that owns discovery, capability and production-readiness facts; route sherpa-onnx, FunASR and MLX through isolated adapters behind one final/benchmark request contract. Keep benchmark state outside `SpeechInputCoordinator`; production final ASR reuses the same adapters with exactly one SenseVoice fallback while realtime preview remains SenseVoice.

**Tech Stack:** Swift/AppKit, C sherpa-onnx bridge, Python 3.10 managed sidecars, FunASR 1.3.14, MLX Audio 0.3.1, mlx-whisper, JSONL stdio, AVFoundation, shell/Python/Swift focused checks.

## Global Constraints

- Work only on `codex/typewhale-pro-asr-hotwords`; rerun branch/status/process/mtime checks before every write, build, install, stage or commit.
- Protect all dirty files not produced by this task; if another task overlaps, immediately return to read-only analysis.
- SenseVoice remains the default stable final ASR and the only one-shot production fallback.
- Realtime preview remains SenseVoice for every selected final backend.
- Benchmark inference never falls back, never pastes and never writes recent transcription history.
- Hotwords must use the target model's native format; text replacement and smart rewrite cannot count as hotword support.
- A model is production-selectable only after file, runtime, real-WAV, cancellation and resource-release admission checks pass.
- Benchmark runs are serial; unload the previous engine before loading the next.
- Sidecars cannot download weights at inference time and cannot depend on the user's system Python.
- Preserve ASR/VAD warm-loading and idle-only high-memory flush followed by immediate reload.
- Code changes require version records, `./native/build_and_log.sh`, `/Applications/TypeWhale.app` replacement, launch, signature verification and installed-app QA.
- UI changes require `design-review` and real installed-app inspection in light and dark themes.

---

## File Map

### New focused units

- `native/Sources/Domain/ASRBenchmarkDomain.swift`: candidate IDs, engine kind, hotword strategy, readiness, requests, measurements and results.
- `native/Sources/Infrastructure/ASR/ASRModelRegistry.swift`: complete local-model discovery and validation rules.
- `native/Sources/Infrastructure/ASR/ASRHotwordEncoder.swift`: native list/string/sherpa/context-prompt encoding and rejection reasons.
- `native/Sources/Infrastructure/ASR/SherpaBenchmarkAdapter.swift`: isolated native recognizers for SenseVoice, Qwen3 and Parakeet.
- `native/Sources/Infrastructure/ASR/MLXASRRuntimeManifest.swift`: pinned runtime/version/checksum requirements.
- `native/Sources/Infrastructure/ASR/ManagedMLXASRRuntime.swift`: structural and import health checks.
- `native/Sources/Infrastructure/ASR/MLXASRRuntimeInstaller.swift`: atomic managed-runtime installation.
- `native/Sources/Infrastructure/ASR/MLXASRSidecarProtocol.swift`: Codable JSONL contract.
- `native/Sources/Infrastructure/ASR/MLXASRSidecar.swift`: persistent sidecar process and timeout/cancel handling.
- `native/Resources/mlx_asr_worker.py`: local-only Whisper/Qwen MLX inference.
- `native/Resources/mlx_asr_runtime_requirements.txt`: exact dependency pins.
- `native/Sources/Application/UnifiedLocalASRAdapter.swift`: shared adapter boundary for benchmark and production.
- `native/Sources/Application/ASRBenchmarkCoordinator.swift`: session identity, serial scheduling, cancellation and metrics.
- `native/Sources/Infrastructure/ASR/ASRBenchmarkStore.swift`: benchmark WAV/result storage and cleanup.
- `native/Sources/Presentation/Main/ASRBenchmarkViewController.swift`: benchmark window and row rendering.
- `native/Sources/Presentation/Main/ASRBenchmarkWindowController.swift`: non-singleton window lifecycle.

### Existing files changed

- `native/Sources/Domain/ASRDomain.swift`: expanded production `ASRBackend` identifiers and stable migration.
- `native/TypeSpeakerNativeASR.h`, `native/TypeSpeakerNativeASR.c`: isolated Qwen/Parakeet recognizer creation and optional native hotword input.
- `native/Sources/Infrastructure/Models/ModelManifests.swift`: Qwen/Parakeet complete-file manifests.
- `native/Sources/Infrastructure/Models/ManagedASRModelCatalog.swift`: SeACo and discovered-cache metadata without treating dependencies as ASR.
- `native/Sources/Infrastructure/ASR/ASRProviderCapabilities.swift`: all candidate capabilities and verified hotword states.
- `native/Resources/funasr_asr_worker.py`: Paraformer zh and SeACo providers plus explicit hotword strategy echo.
- `native/Sources/Infrastructure/ASR/FunASRSidecarProtocol.swift`, `FunASRSidecar.swift`: strategy/result metadata.
- `native/Sources/Application/ProviderAwareFinalASR.swift`: replace FunASR-only switch with unified adapter route and one fallback.
- `native/Sources/Application/SpeechInputCoordinator.swift`: dependency assembly only; no benchmark workflow ownership.
- `native/Sources/Presentation/Main/MainViewController.swift`: benchmark button/window callback state.
- `native/Sources/Presentation/Main/MainViewController+Configuration.swift`: expanded backend menu and disabled readiness states.
- `native/Sources/Presentation/Main/MainViewController+Actions.swift`: readiness-gated persistence and benchmark opening.
- `native/Sources/Presentation/Main/MainViewController+PanelLayout.swift`: benchmark entry beside model management.
- `native/Sources/Presentation/VersionHistory/VersionHistoryViewController.swift`, `README.md`, `native/README.md`, `docs/ARCHITECTURE.md`, `docs/开发日志.md`: delivery records.

---

### Task 1: Lock Candidate Identity, Capabilities and Discovery

**Files:**
- Create: `native/Sources/Domain/ASRBenchmarkDomain.swift`
- Create: `native/Sources/Infrastructure/ASR/ASRModelRegistry.swift`
- Modify: `native/Sources/Domain/ASRDomain.swift`
- Modify: `native/Sources/Infrastructure/Models/ModelManifests.swift`
- Modify: `native/Sources/Infrastructure/Models/ManagedASRModelCatalog.swift`
- Modify: `native/Sources/Infrastructure/ASR/ASRProviderCapabilities.swift`
- Test: `native/Tests/ASRModelRegistryCheck.swift`
- Test: `native/Tests/ExpandedASRBackendDomainCheck.sh`

**Interfaces:**
- Produces: `ASRCandidateID`, `ASREngineKind`, `ASRHotwordStrategy`, `ASRReadiness`, `ASRModelDescriptor` and `ASRModelRegistry.descriptors()`.
- Produces: expanded `ASRBackend` raw values whose `candidateID` maps into the registry.

- [ ] **Step 1: Write the failing registry test**

```swift
let descriptors = ASRModelRegistry(environment: .fixture(root: fixtureRoot)).descriptors()
precondition(Set(descriptors.map(\.id)) == Set(ASRCandidateID.allCases))
precondition(descriptors.first { $0.id == .sileroVAD } == nil)
precondition(descriptors.first { $0.id == .ctPunc } == nil)
precondition(descriptors.first { $0.id == .qwen3Sherpa06B }?.readiness == .ready)
precondition(descriptors.first { $0.id == .qwen3MLX17B }?.engine == .mlx)
```

- [ ] **Step 2: Run the test and verify RED**

Run: `xcrun swiftc -parse-as-library native/Sources/Domain/ASRBenchmarkDomain.swift native/Sources/Infrastructure/ASR/ASRModelRegistry.swift native/Tests/ASRModelRegistryCheck.swift -o /tmp/ASRModelRegistryCheck && /tmp/ASRModelRegistryCheck`

Expected: compile failure because the new files/types do not exist.

- [ ] **Step 3: Add candidate and readiness domain types**

```swift
enum ASRCandidateID: String, CaseIterable, Codable {
    case senseVoiceInt8, qwen3Sherpa06B, parakeetTDT06B
    case funASRNano2512, paraformerContextual, paraformerZH, seacoParaformer
    case whisperSmallMLX, qwen3MLX06B, qwen3MLX17B
}

enum ASREngineKind: String, Codable { case sherpa, funASR, mlx }
enum ASRHotwordStrategy: Equatable, Codable {
    case unsupported
    case nativeList
    case nativeSpaceSeparated
    case sherpaInline
    case contextPrompt
}
enum ASRReadiness: Equatable { case ready, validating, unavailable(String) }

struct ASRModelDescriptor: Equatable {
    let id: ASRCandidateID
    let displayName: String
    let engine: ASREngineKind
    let modelDirectory: URL
    let requiredRelativePaths: [String]
    let hotwordStrategy: ASRHotwordStrategy
    let readiness: ASRReadiness
    let productionReady: Bool
}
```

- [ ] **Step 4: Implement deterministic discovery**

Use explicit roots for bundled models, `AppPaths.models`, legacy TypeWhale models, Hugging Face snapshot roots and the final ModelScope SeACo directory. Resolve HF snapshots from `refs/main`; reject `.incomplete`, `._____temp`, lock directories, dangling links, zero-byte required files and model configs whose `model_type` does not match.

```swift
func validate(_ candidate: CandidateManifest) -> ASRReadiness {
    for path in candidate.requiredRelativePaths {
        let url = candidate.modelDirectory.appendingPathComponent(path)
        guard regularFileSize(url) > 0 else { return .unavailable("缺少模型文件：\(path)") }
    }
    return .ready
}
```

- [ ] **Step 5: Expand production backend IDs with stable migration**

Add cases for all ten candidates. Preserve existing raw values for SenseVoice, Nano and Contextual. Map old `qwen3ASR` to `.qwen3Sherpa06B`; unknown values migrate to `.senseVoice`.

```swift
var candidateID: ASRCandidateID {
    switch self {
    case .senseVoice: return .senseVoiceInt8
    case .qwen3Sherpa: return .qwen3Sherpa06B
    case .parakeetSherpa: return .parakeetTDT06B
    case .funASRNano: return .funASRNano2512
    case .paraformerContextual: return .paraformerContextual
    case .paraformerZH: return .paraformerZH
    case .seacoParaformer: return .seacoParaformer
    case .whisperSmallMLX: return .whisperSmallMLX
    case .qwen3MLX06B: return .qwen3MLX06B
    case .qwen3MLX17B: return .qwen3MLX17B
    }
}
```

- [ ] **Step 6: Run focused tests and commit**

Run: `xcrun swiftc -parse-as-library native/Sources/Domain/ASRBenchmarkDomain.swift native/Sources/Infrastructure/ASR/ASRModelRegistry.swift native/Tests/ASRModelRegistryCheck.swift -o /tmp/ASRModelRegistryCheck && /tmp/ASRModelRegistryCheck`

Run: `bash native/Tests/ExpandedASRBackendDomainCheck.sh`

Expected: both print `passed`.

Commit: `git add native/Sources/Domain/ASRBenchmarkDomain.swift native/Sources/Domain/ASRDomain.swift native/Sources/Infrastructure/ASR/ASRModelRegistry.swift native/Sources/Infrastructure/ASR/ASRProviderCapabilities.swift native/Sources/Infrastructure/Models/ModelManifests.swift native/Sources/Infrastructure/Models/ManagedASRModelCatalog.swift native/Tests/ASRModelRegistryCheck.swift native/Tests/ExpandedASRBackendDomainCheck.sh && git commit -m "feat(asr): register all local ASR candidates"`

---

### Task 2: Enforce Native Hotword Formats

**Files:**
- Create: `native/Sources/Infrastructure/ASR/ASRHotwordEncoder.swift`
- Test: `native/Tests/ASRHotwordEncoderCheck.swift`
- Modify: `native/Sources/Infrastructure/ASR/ASRProviderCapabilities.swift`

**Interfaces:**
- Consumes: `ASRHotwordStrategy` from Task 1.
- Produces: `ASRHotwordPayload` and `ASRHotwordEncoder.encode(words:strategy:)`.

- [ ] **Step 1: Write failing payload tests**

```swift
precondition(try encode(["魔搭", "Qwen3-ASR"], .nativeList) == .list(["魔搭", "Qwen3-ASR"]))
precondition(try encode(["魔搭", "Qwen3-ASR"], .nativeSpaceSeparated) == .text("魔搭 Qwen3-ASR"))
precondition(try encode(["TypeWhale Pro"], .sherpaInline) == .text("TypeWhale Pro"))
precondition(try encode(["Codex"], .unsupported) == .none)
precondition(try encode(["Codex"], .contextPrompt) == .context("Codex"))
```

Also assert trimming, stable de-duplication, 64-word cap, 256-character word cap, NUL/newline rejection and that unsupported emits no model field.

- [ ] **Step 2: Run RED**

Run: `xcrun swiftc -parse-as-library native/Sources/Domain/ASRBenchmarkDomain.swift native/Sources/Infrastructure/ASR/ASRHotwordEncoder.swift native/Tests/ASRHotwordEncoderCheck.swift -o /tmp/ASRHotwordEncoderCheck && /tmp/ASRHotwordEncoderCheck`

Expected: failure because `ASRHotwordEncoder` is missing.

- [ ] **Step 3: Implement the closed payload enum and validation**

```swift
enum ASRHotwordPayload: Equatable {
    case none
    case list([String])
    case text(String)
    case context(String)
}

enum ASRHotwordEncodingError: LocalizedError, Equatable {
    case invalidCharacters(String)
    case wordTooLong(String)
    case tooManyWords(Int)
}
```

Do not create a generic dictionary payload. Each sidecar/native adapter switches exhaustively on the enum so an unsupported model cannot accidentally receive `hotwords`.

- [ ] **Step 4: Run GREEN and commit**

Run: `xcrun swiftc -parse-as-library native/Sources/Domain/ASRBenchmarkDomain.swift native/Sources/Infrastructure/ASR/ASRHotwordEncoder.swift native/Tests/ASRHotwordEncoderCheck.swift -o /tmp/ASRHotwordEncoderCheck && /tmp/ASRHotwordEncoderCheck`

Expected: `ASRHotwordEncoderCheck passed`.

Commit: `git add native/Sources/Infrastructure/ASR/ASRHotwordEncoder.swift native/Sources/Infrastructure/ASR/ASRProviderCapabilities.swift native/Tests/ASRHotwordEncoderCheck.swift && git commit -m "feat(asr): enforce model-native hotword payloads"`

---

### Task 3: Add Isolated Sherpa Recognizers for Qwen and Parakeet

**Files:**
- Modify: `native/TypeSpeakerNativeASR.h`
- Modify: `native/TypeSpeakerNativeASR.c`
- Create: `native/Sources/Infrastructure/ASR/SherpaBenchmarkAdapter.swift`
- Test: `native/Tests/SherpaCandidateBridgeBoundaryCheck.sh`
- Test: `native/Tests/SherpaBenchmarkAdapterCheck.swift`

**Interfaces:**
- Consumes: registry descriptor and encoded hotword payload.
- Produces: `SherpaBenchmarkAdapter.run(request:completion:)` and native `TypeSpeakerNativeParakeetRecognizerCreate`.

- [ ] **Step 1: Add failing source-boundary assertions**

Assert the C header exposes a Parakeet creator taking encoder, decoder, joiner and tokens paths; assert Qwen receives the registry-approved inline hotword text; assert SenseVoice is always created with an empty hotword because its capability is unsupported.

Run: `bash native/Tests/SherpaCandidateBridgeBoundaryCheck.sh`

Expected: fail because the Parakeet creator and isolated adapter do not exist.

- [ ] **Step 2: Add the Parakeet C creator**

```c
TypeSpeakerNativeRecognizer TypeSpeakerNativeParakeetRecognizerCreate(
    const char *encoder_path,
    const char *decoder_path,
    const char *joiner_path,
    const char *tokens_path,
    const char *hotwords,
    char **error_message);
```

Populate `config.model_config.transducer.encoder`, `.decoder`, `.joiner`, `tokens`, CPU provider and three threads. Use `modified_beam_search` only when the current sherpa API and real model support the supplied hotword stream; otherwise the registry must keep Parakeet hotwords unsupported.

- [ ] **Step 3: Implement the isolated Swift adapter**

```swift
struct ASREngineRequest {
    let runID: UUID
    let descriptor: ASRModelDescriptor
    let audioURL: URL
    let hotwords: ASRHotwordPayload
}

struct ASREngineResult {
    let text: String
    let engine: String
    let loadSeconds: Double
    let inferenceSeconds: Double
    let peakRSSMB: Double
}
```

The adapter owns its own serial queue and native recognizer pointer. It must not reuse the production `NativeSenseVoiceBridge` cache during benchmark runs. `cancel()` invalidates the run ID; `unload()` destroys the recognizer and calls cached-resource release only for its isolated session.

- [ ] **Step 4: Run bridge and adapter checks**

Run: `bash native/Tests/SherpaCandidateBridgeBoundaryCheck.sh`

Run: `xcrun swiftc -parse-as-library native/Sources/Domain/ASRBenchmarkDomain.swift native/Sources/Infrastructure/ASR/ASRHotwordEncoder.swift native/Sources/Infrastructure/ASR/SherpaBenchmarkAdapter.swift native/Tests/SherpaBenchmarkAdapterCheck.swift -o /tmp/SherpaBenchmarkAdapterCheck && /tmp/SherpaBenchmarkAdapterCheck`

Expected: both pass, including stale-run cancellation and deterministic engine labels.

- [ ] **Step 5: Execute real sherpa smoke tests and commit**

Use the bundled SenseVoice example/current benchmark WAV, Qwen test WAV and Parakeet `test_wavs/0.wav`. Require non-empty text, then unload each recognizer before loading the next.

Commit: `git add native/TypeSpeakerNativeASR.h native/TypeSpeakerNativeASR.c native/Sources/Infrastructure/ASR/SherpaBenchmarkAdapter.swift native/Tests/SherpaCandidateBridgeBoundaryCheck.sh native/Tests/SherpaBenchmarkAdapterCheck.swift && git commit -m "feat(asr): add isolated sherpa candidate adapters"`

---

### Task 4: Extend FunASR to Nano, Contextual, Paraformer zh and SeACo

**Files:**
- Modify: `native/Resources/funasr_asr_worker.py`
- Modify: `native/Sources/Infrastructure/ASR/FunASRSidecarProtocol.swift`
- Modify: `native/Sources/Infrastructure/ASR/FunASRSidecar.swift`
- Modify: `native/Sources/Infrastructure/Models/ManagedASRModelCatalog.swift`
- Test: `native/Tests/FunASRWorkerProtocolCheck.py`
- Test: `native/Tests/FunASRSidecarProtocolCheck.swift`
- Test: `native/Tests/FunASRFourProviderMatrixCheck.py`

**Interfaces:**
- Produces: provider IDs `fun-asr-nano-2512`, `paraformer-hotword-contextual`, `paraformer-zh`, `seaco-paraformer`.
- Produces: response metadata `hotword_strategy`, `hotword_count`, `load_sec`, `duration_sec`.

- [ ] **Step 1: Extend failing protocol tests**

```python
assert SUPPORTED_PROVIDERS == {
    "fun-asr-nano-2512", "paraformer-hotword-contextual",
    "paraformer-zh", "seaco-paraformer",
}
assert response["hotword_strategy"] == "native_space_separated"
assert response["hotword_count"] == 2
```

Verify Nano calls `generate(hotwords=[...])`; Contextual/Paraformer/SeACo call `generate(hotword="...")`; no provider performs result text replacement.

- [ ] **Step 2: Run RED**

Run: `python3 native/Tests/FunASRWorkerProtocolCheck.py && python3 native/Tests/FunASRFourProviderMatrixCheck.py`

Expected: fail because only two providers exist.

- [ ] **Step 3: Implement provider specifications**

```python
PROVIDER_SPECS = {
    "fun-asr-nano-2512": {"hotword": "list", "punctuation": False, "trust_remote_code": True},
    "paraformer-hotword-contextual": {"hotword": "space_separated", "punctuation": True},
    "paraformer-zh": {"hotword": "space_separated", "punctuation": True},
    "seaco-paraformer": {"hotword": "space_separated", "punctuation": True},
}
```

Return the strategy actually used. Reject a request whose payload kind disagrees with the provider spec. Load SeACo from its final ModelScope directory, never `._____temp`.

- [ ] **Step 4: Update Swift Codable protocol and timeout handling**

Add `hotwordStrategy`, `hotwordCount`, `loadSeconds` fields with explicit snake-case coding keys. Keep the 30-second request timeout per line, but allow the coordinator to set a larger candidate-specific timeout for 1.7B/slow cold loads in the unified adapter.

- [ ] **Step 5: Run focused checks and real A/B probes**

Run: `python3 native/Tests/FunASRWorkerProtocolCheck.py`

Run: `python3 native/Tests/FunASRFourProviderMatrixCheck.py`

Run: `xcrun swiftc -parse-as-library native/Sources/Infrastructure/ASR/FunASRSidecarProtocol.swift native/Tests/FunASRSidecarProtocolCheck.swift -o /tmp/FunASRSidecarProtocolCheck && /tmp/FunASRSidecarProtocolCheck`

Use one Chinese hotword WAV for all four providers. Save raw no-hotword/hotword outputs under the benchmark result store; only mark a capability behavior-verified when the target format was accepted and evidence was captured.

- [ ] **Step 6: Commit**

Commit: `git add native/Resources/funasr_asr_worker.py native/Sources/Infrastructure/ASR/FunASRSidecarProtocol.swift native/Sources/Infrastructure/ASR/FunASRSidecar.swift native/Sources/Infrastructure/Models/ManagedASRModelCatalog.swift native/Tests/FunASRWorkerProtocolCheck.py native/Tests/FunASRSidecarProtocolCheck.swift native/Tests/FunASRFourProviderMatrixCheck.py && git commit -m "feat(asr): support all local FunASR candidates"`

---

### Task 5: Build the Managed MLX Runtime and Sidecar

**Files:**
- Create: `native/Resources/mlx_asr_runtime_requirements.txt`
- Create: `native/Resources/mlx_asr_worker.py`
- Create: `native/Sources/Infrastructure/ASR/MLXASRRuntimeManifest.swift`
- Create: `native/Sources/Infrastructure/ASR/ManagedMLXASRRuntime.swift`
- Create: `native/Sources/Infrastructure/ASR/MLXASRRuntimeInstaller.swift`
- Create: `native/Sources/Infrastructure/ASR/MLXASRSidecarProtocol.swift`
- Create: `native/Sources/Infrastructure/ASR/MLXASRSidecar.swift`
- Test: `native/Tests/MLXASRWorkerProtocolCheck.py`
- Test: `native/Tests/ManagedMLXASRRuntimeCheck.swift`
- Test: `native/Tests/MLXASRSidecarProtocolCheck.swift`

**Interfaces:**
- Produces: persistent providers `whisper-small-mlx`, `qwen3-asr-0.6b-mlx`, `qwen3-asr-1.7b-mlx`.
- Produces: atomic runtime state `.missing`, `.invalid(String)`, `.ready(URL)`.

- [ ] **Step 1: Write failing worker and manifest tests**

Require health/warmup/transcribe/shutdown commands, local directory paths, no repository IDs, no network environment and deterministic JSONL responses. Require Whisper to accept only `.contextPrompt`; Qwen MLX must reject non-empty hotwords until its local `mlx_audio` API exposes a verified context field.

Run: `python3 native/Tests/MLXASRWorkerProtocolCheck.py`

Expected: file-not-found failure.

- [ ] **Step 2: Pin the runtime**

Use Python 3.10 managed archive machinery already proven by FunASR, but install into `AppPaths.runtimes/mlx-asr/v1`. Pin `mlx-audio[stt]==0.3.1` because both local Qwen model cards name that conversion runtime, plus `mlx-whisper==0.4.3`, `mlx==0.30.6`, `mlx-lm==0.30.5`, `transformers==5.0.0rc3`, `torch==2.11.0` and `numpy==1.26.4`. Generate and commit a hash-locked requirements file from exactly this resolver set; `MLXASRRuntimeManifest` verifies its SHA-256 and the imported module versions.

```swift
enum MLXASRRuntimeManifest {
    static let version = "v1"
    static let pythonVersion = "3.10"
    static let requiredModules = ["mlx", "mlx_audio", "mlx_whisper", "numpy"]
}
```

- [ ] **Step 3: Implement the local-only worker**

```python
def load_provider(provider: str, model_dir: str):
    assert Path(model_dir).is_dir()
    if provider == "whisper-small-mlx":
        return {"kind": "whisper", "model_dir": model_dir}
    if provider.startswith("qwen3-asr-"):
        from mlx_audio.stt.utils import load_model
        return {"kind": "qwen", "model": load_model(model_dir)}
    raise ValueError(f"unsupported provider: {provider}")
```

Whisper calls `mlx_whisper.transcribe(audio_path, path_or_hf_repo=model_dir, initial_prompt=context_or_none)`. Qwen calls `generate_transcription(model=loaded_model, audio_path=audio_path, output_path=None, format="txt", verbose=False)`. Set offline environment variables before importing Hugging Face libraries and reject any non-local model path.

- [ ] **Step 4: Implement atomic runtime install and Swift sidecar**

Mirror FunASR staging, version marker, import probe and atomic replacement. The JSONL sidecar must cap a response at 1 MiB, validate response IDs, capture bounded stderr, terminate on cancel and never leave a zombie process.

- [ ] **Step 5: Run protocol tests and real local inference**

Run: `python3 native/Tests/MLXASRWorkerProtocolCheck.py`

Run: `xcrun swiftc -parse-as-library native/Sources/Infrastructure/ASR/MLXASRRuntimeManifest.swift native/Sources/Infrastructure/ASR/ManagedMLXASRRuntime.swift native/Tests/ManagedMLXASRRuntimeCheck.swift -o /tmp/ManagedMLXASRRuntimeCheck && /tmp/ManagedMLXASRRuntimeCheck`

Run: `xcrun swiftc -parse-as-library native/Sources/Infrastructure/ASR/MLXASRSidecarProtocol.swift native/Tests/MLXASRSidecarProtocolCheck.swift -o /tmp/MLXASRSidecarProtocolCheck && /tmp/MLXASRSidecarProtocolCheck`

Then run one identical WAV through Whisper Small, Qwen 0.6B and Qwen 1.7B using only local snapshot paths. Require non-empty text and record cold/warm times.

- [ ] **Step 6: Commit**

Commit: `git add native/Resources/mlx_asr_runtime_requirements.txt native/Resources/mlx_asr_worker.py native/Sources/Infrastructure/ASR/MLXASRRuntimeManifest.swift native/Sources/Infrastructure/ASR/ManagedMLXASRRuntime.swift native/Sources/Infrastructure/ASR/MLXASRRuntimeInstaller.swift native/Sources/Infrastructure/ASR/MLXASRSidecarProtocol.swift native/Sources/Infrastructure/ASR/MLXASRSidecar.swift native/Tests/MLXASRWorkerProtocolCheck.py native/Tests/ManagedMLXASRRuntimeCheck.swift native/Tests/MLXASRSidecarProtocolCheck.swift && git commit -m "feat(asr): add managed MLX ASR runtime"`

---

### Task 6: Unify Benchmark and Production Adapter Routing

**Files:**
- Create: `native/Sources/Application/UnifiedLocalASRAdapter.swift`
- Modify: `native/Sources/Application/ProviderAwareFinalASR.swift`
- Modify: `native/Sources/Application/SpeechInputCoordinator.swift`
- Test: `native/Tests/UnifiedLocalASRAdapterCheck.swift`
- Test: `native/Tests/ProviderAwareFinalASRCheck.swift`

**Interfaces:**
- Consumes: registry descriptors, hotword encoder, Sherpa/FunASR/MLX adapters.
- Produces: `LocalASRRunning` for no-fallback benchmark calls and `ProviderAwareFinalASR` for one-fallback production calls.

- [ ] **Step 1: Write failing routing matrix tests**

```swift
for candidate in ASRCandidateID.allCases {
    let result = await fakeUnified.run(candidate: candidate, audio: wav, hotwords: words)
    precondition(result.engineCandidate == candidate)
}
precondition(fakeUnified.receivedPayload(for: .senseVoiceInt8) == .none)
precondition(fakeUnified.receivedPayload(for: .funASRNano2512) == .list(words))
```

Production tests assert target success never touches SenseVoice; target failure calls SenseVoice exactly once; fallback failure completes once; benchmark target failure never calls SenseVoice.

- [ ] **Step 2: Run RED**

Run: `xcrun swiftc -parse-as-library native/Sources/Domain/ASRBenchmarkDomain.swift native/Sources/Infrastructure/ASR/ASRHotwordEncoder.swift native/Sources/Application/UnifiedLocalASRAdapter.swift native/Tests/UnifiedLocalASRAdapterCheck.swift -o /tmp/UnifiedLocalASRAdapterCheck && /tmp/UnifiedLocalASRAdapterCheck`

Expected: failure because unified routing is absent.

- [ ] **Step 3: Implement the shared no-fallback protocol**

```swift
protocol LocalASRRunning: AnyObject {
    func probe(_ descriptor: ASRModelDescriptor) -> ASRReadiness
    func warmUp(_ descriptor: ASRModelDescriptor, completion: @escaping (Result<Double, Error>) -> Void)
    func transcribe(_ request: ASREngineRequest, completion: @escaping (Result<ASREngineResult, Error>) -> Void)
    func cancel(runID: UUID)
    func unload(completion: @escaping () -> Void)
}
```

`UnifiedLocalASRAdapter` switches only on `descriptor.engine`, not individual UI menu tags.

- [ ] **Step 4: Refactor production fallback around the unified adapter**

Freeze the selected descriptor and hotword snapshot when the recording task is created. Add a completion gate so target/fallback callbacks cannot complete twice. Keep diagnostic fields `requested`, `actual`, `reason`, and `fallback_count=1`.

- [ ] **Step 5: Keep coordinator changes assembly-only**

`SpeechInputCoordinator` constructs registry/adapters/installers and passes them into `ProviderAwareFinalASR`; it does not own benchmark rows, timings or result storage.

- [ ] **Step 6: Run tests and commit**

Run: `xcrun swiftc -parse-as-library native/Sources/Domain/ASRBenchmarkDomain.swift native/Sources/Infrastructure/ASR/ASRHotwordEncoder.swift native/Sources/Application/UnifiedLocalASRAdapter.swift native/Tests/UnifiedLocalASRAdapterCheck.swift -o /tmp/UnifiedLocalASRAdapterCheck && /tmp/UnifiedLocalASRAdapterCheck`

Run: `xcrun swiftc -parse-as-library native/Sources/Infrastructure/ASR/FunASRRuntimeManifest.swift native/Sources/Infrastructure/ASR/ManagedFunASRRuntime.swift native/Sources/Infrastructure/ASR/FunASRSidecarProtocol.swift native/Sources/Infrastructure/ASR/FunASRSidecar.swift native/Sources/Application/ProviderAwareFinalASR.swift native/Tests/ProviderAwareFinalASRCheck.swift -o /tmp/ProviderAwareFinalASRCheck && /tmp/ProviderAwareFinalASRCheck`

Run: `bash native/Tests/SpeechInputCoordinatorBoundaryCheck.sh`

Expected: all pass.

Commit: `git add native/Sources/Application/UnifiedLocalASRAdapter.swift native/Sources/Application/ProviderAwareFinalASR.swift native/Sources/Application/SpeechInputCoordinator.swift native/Tests/UnifiedLocalASRAdapterCheck.swift native/Tests/ProviderAwareFinalASRCheck.swift && git commit -m "refactor(asr): share verified local adapter routing"`

---

### Task 7: Implement Benchmark Session, Storage and Metrics

**Files:**
- Create: `native/Sources/Infrastructure/ASR/ASRBenchmarkStore.swift`
- Create: `native/Sources/Application/ASRBenchmarkCoordinator.swift`
- Test: `native/Tests/ASRBenchmarkCoordinatorCheck.swift`
- Test: `native/Tests/ASRBenchmarkStoreCheck.swift`

**Interfaces:**
- Produces: `ASRBenchmarkCoordinator.State`, `record()`, `importAudio(_:)`, `run(candidate:)`, `runAll()`, `cancel()` and `clear()`.
- Produces: persisted `ASRBenchmarkResult` keyed by sample SHA-256, candidate ID and hotword snapshot hash.

- [ ] **Step 1: Write failing state-machine tests**

Assert run-all order is lightweight-first; only one fake adapter is active; unload completes before next warmup; a replaced sample invalidates old callbacks; cancel prevents persistence; RTF is `warmSeconds / audioDuration`.

```swift
precondition(result.realTimeFactor == result.warmInferenceSeconds / result.audioDurationSeconds)
precondition(fake.maximumConcurrentRuns == 1)
precondition(fake.events == ["load:sense", "run:sense", "unload:sense", "load:whisper"])
```

- [ ] **Step 2: Run RED**

Run: `xcrun swiftc -parse-as-library native/Sources/Domain/ASRBenchmarkDomain.swift native/Sources/Application/ASRBenchmarkCoordinator.swift native/Tests/ASRBenchmarkCoordinatorCheck.swift -o /tmp/ASRBenchmarkCoordinatorCheck && /tmp/ASRBenchmarkCoordinatorCheck`

Expected: compile failure because coordinator is missing.

- [ ] **Step 3: Implement the result model and monotonic timing**

Use `ContinuousClock` for load/inference durations. Measure cold load, first inference and second warm inference separately. Capture peak RSS from the sidecar PID or current process task info. Store raw target text only; do not normalize it before hotword hit comparison.

- [ ] **Step 4: Implement benchmark-local recording and import**

Use a dedicated `AudioRecorder` instance and benchmark directory, never `latest.wav`. Imported audio goes through `CanonicalAudioConverter` into 16 kHz mono PCM WAV. File names use UUID/sample hash only.

- [ ] **Step 5: Implement atomic JSON result storage and cleanup**

Write to a sibling staging file, fsync/close, then replace. `clear()` removes benchmark WAV, JSON results and temporary hotword artifacts but never model weights or runtimes.

- [ ] **Step 6: Run checks and commit**

Run: `xcrun swiftc -parse-as-library native/Sources/Domain/ASRBenchmarkDomain.swift native/Sources/Application/ASRBenchmarkCoordinator.swift native/Tests/ASRBenchmarkCoordinatorCheck.swift -o /tmp/ASRBenchmarkCoordinatorCheck && /tmp/ASRBenchmarkCoordinatorCheck`

Run: `xcrun swiftc -parse-as-library native/Sources/Domain/ASRBenchmarkDomain.swift native/Sources/Infrastructure/ASR/ASRBenchmarkStore.swift native/Tests/ASRBenchmarkStoreCheck.swift -o /tmp/ASRBenchmarkStoreCheck && /tmp/ASRBenchmarkStoreCheck`

Expected: both pass.

Commit: `git add native/Sources/Application/ASRBenchmarkCoordinator.swift native/Sources/Infrastructure/ASR/ASRBenchmarkStore.swift native/Tests/ASRBenchmarkCoordinatorCheck.swift native/Tests/ASRBenchmarkStoreCheck.swift && git commit -m "feat(asr): add serial benchmark sessions and metrics"`

---

### Task 8: Build the Benchmark Window

**Files:**
- Create: `native/Sources/Presentation/Main/ASRBenchmarkViewController.swift`
- Create: `native/Sources/Presentation/Main/ASRBenchmarkWindowController.swift`
- Modify: `native/Sources/Presentation/Main/MainViewController.swift`
- Modify: `native/Sources/Presentation/Main/MainViewController+Actions.swift`
- Modify: `native/Sources/Presentation/Main/MainViewController+PanelLayout.swift`
- Test: `native/Tests/ASRBenchmarkUIBoundaryCheck.sh`
- Test: `native/Tests/ASRBenchmarkRowPresentationCheck.swift`

**Interfaces:**
- Consumes: benchmark coordinator state only.
- Produces: independent window opened from the Models page.

- [ ] **Step 1: Write failing UI boundary checks**

Assert the window contains record/stop, import, playback, temporary hotword editor, test-one, A/B, test-all, cancel, retry and clear actions. Assert the controller has no pasteboard, recent-transcription or `SpeechInputCoordinator` dependency.

Run: `bash native/Tests/ASRBenchmarkUIBoundaryCheck.sh`

Expected: fail because the UI files do not exist.

- [ ] **Step 2: Implement pure row presentation mapping**

```swift
struct ASRBenchmarkRowPresentation: Equatable {
    let title: String
    let subtitle: String
    let readinessText: String
    let hotwordBadge: String
    let timingText: String
    let resultText: String
    let canRun: Bool
    let canCancel: Bool
}
```

Map errors to concise Chinese copy and keep technical details expandable. Duplicate Qwen names always include `Sherpa int8` or `MLX 8-bit`.

- [ ] **Step 3: Implement the AppKit window layout**

Use a resizable window with a fixed sample/hotword header and scrollable candidate rows. Keep controls keyboard accessible, assign accessibility labels and prevent a running row from shifting layout when timing text updates.

- [ ] **Step 4: Wire the Models-page entry**

Add an `ASR 模型测速` button above `ManagedASRModelListView`. The main controller owns only a window controller reference/callback; benchmark lifecycle remains in its own coordinator.

- [ ] **Step 5: Run UI checks and commit**

Run: `bash native/Tests/ASRBenchmarkUIBoundaryCheck.sh`

Run: `xcrun swiftc -parse-as-library native/Sources/Domain/ASRBenchmarkDomain.swift native/Sources/Presentation/Main/ASRBenchmarkViewController.swift native/Tests/ASRBenchmarkRowPresentationCheck.swift -o /tmp/ASRBenchmarkRowPresentationCheck && /tmp/ASRBenchmarkRowPresentationCheck`

Expected: both pass.

Commit: `git add native/Sources/Presentation/Main/ASRBenchmarkViewController.swift native/Sources/Presentation/Main/ASRBenchmarkWindowController.swift native/Sources/Presentation/Main/MainViewController.swift native/Sources/Presentation/Main/MainViewController+Actions.swift native/Sources/Presentation/Main/MainViewController+PanelLayout.swift native/Tests/ASRBenchmarkUIBoundaryCheck.sh native/Tests/ASRBenchmarkRowPresentationCheck.swift && git commit -m "feat(asr): add local model benchmark window"`

---

### Task 9: Expand and Gate the Production Dropdown

**Files:**
- Modify: `native/Sources/Presentation/Main/MainViewController+Configuration.swift`
- Modify: `native/Sources/Presentation/Main/MainViewController+Actions.swift`
- Modify: `native/Sources/Presentation/Main/MainViewController.swift`
- Test: `native/Tests/ExpandedASRBackendUIBoundaryCheck.sh`
- Test: `native/Tests/ASRBackendReadinessGateCheck.swift`

**Interfaces:**
- Consumes: registry `productionReady` and `ASRBackend.candidateID`.
- Produces: all-candidate menu with enabled/disabled readiness and safe persistence.

- [ ] **Step 1: Write failing menu and persistence tests**

Require ten menu items, engine suffixes for duplicate Qwen names, disabled `validating/unavailable` items, and save rejection when readiness changes between menu construction and click.

Run: `bash native/Tests/ExpandedASRBackendUIBoundaryCheck.sh`

Expected: fail because the menu still has three items.

- [ ] **Step 2: Build registry-backed menu items**

```swift
for backend in ASRBackend.allCases {
    let descriptor = registry.descriptor(for: backend.candidateID)
    asrBackendMode.addItem(withTitle: descriptor.menuTitle)
    asrBackendMode.lastItem?.representedObject = backend.rawValue
    asrBackendMode.lastItem?.isEnabled = descriptor.productionReady
}
```

Append `（验证中）` or `（不可用）` to disabled entries and expose the exact reason in the tooltip.

- [ ] **Step 3: Gate save and active-session behavior**

Re-probe before persistence. If not ready, restore the prior selection and show “尚未通过真实转写验证，正式识别模型保持不变”. Continue the existing 3.5-second debounce. A recording already in progress keeps its frozen backend; selection affects the next recording only.

- [ ] **Step 4: Run checks and commit**

Run: `bash native/Tests/ExpandedASRBackendUIBoundaryCheck.sh`

Run: `xcrun swiftc -parse-as-library native/Sources/Domain/ASRBenchmarkDomain.swift native/Sources/Infrastructure/ASR/ASRModelRegistry.swift native/Tests/ASRBackendReadinessGateCheck.swift -o /tmp/ASRBackendReadinessGateCheck && /tmp/ASRBackendReadinessGateCheck`

Run: `bash native/Tests/FunASRBackendUIBoundaryCheck.sh`

Expected: all pass.

Commit: `git add native/Sources/Presentation/Main/MainViewController+Configuration.swift native/Sources/Presentation/Main/MainViewController+Actions.swift native/Sources/Presentation/Main/MainViewController.swift native/Tests/ExpandedASRBackendUIBoundaryCheck.sh native/Tests/ASRBackendReadinessGateCheck.swift && git commit -m "feat(asr): expand readiness-gated model dropdown"`

---

### Task 10: Run the Full Real-Model Admission Matrix

**Files:**
- Create: `tools/asr-eval/run_local_candidate_matrix.py`
- Create: `docs/asr-eval/local-candidate-admission.json`
- Test: `native/Tests/LocalASRCandidateAdmissionCheck.sh`

**Interfaces:**
- Consumes: installed app resources, managed runtimes and the same fixed WAV/hotword snapshot.
- Produces: machine-readable admission evidence used by registry production gating.

- [ ] **Step 1: Write the failing admission-schema check**

Require one record per candidate with candidate ID, engine, model hash/mtime identity, runtime version, cold/warm time, RTF, peak RSS, raw text, hotword strategy, no-hotword output, hotword output, format-verified flag and production-ready flag.

Run: `bash native/Tests/LocalASRCandidateAdmissionCheck.sh`

Expected: fail because the admission file is absent.

- [ ] **Step 2: Implement the matrix runner**

The runner talks to the installed app's adapter probe or exact bundled workers; it must not implement a fourth inference path. It runs candidates serially, terminates each process, waits for RSS recovery and writes JSON atomically.

- [ ] **Step 3: Record one shared 15–30 second bilingual WAV**

The spoken script must include at least `TypeWhale Pro`, `Codex`, `Obsidian`, `Qwen3-ASR`, `FunASR`, `Paraformer Contextual` and one Chinese correction pair already known to respond to hotwords. Store audio only in the local benchmark directory; commit only metadata/results, not the user's voice.

- [ ] **Step 4: Run all ten candidates**

Require non-empty cold and warm results for every complete model. For native-hotword candidates run no-hotword/hotword A/B. For Whisper record context-prompt separately. For Qwen MLX keep hotword unsupported unless its local API was explicitly validated.

- [ ] **Step 5: Fix every failed candidate at its adapter boundary and rerun**

Do not mark a failed candidate production-ready and do not add output rewriting. Repeat the candidate's focused adapter test followed by the whole serial matrix until all complete candidates pass real transcription.

- [ ] **Step 6: Run admission check and commit evidence**

Run: `bash native/Tests/LocalASRCandidateAdmissionCheck.sh`

Expected: `LocalASRCandidateAdmissionCheck passed` with ten production-ready candidates and truthful hotword classifications.

Commit: `git add tools/asr-eval/run_local_candidate_matrix.py docs/asr-eval/local-candidate-admission.json native/Tests/LocalASRCandidateAdmissionCheck.sh && git commit -m "test(asr): admit all complete local candidates"`

---

### Task 11: Regression, Documentation, Build and Installed-App QA

**Files:**
- Modify: `docs/ARCHITECTURE.md`
- Modify: `docs/开发日志.md`
- Modify: `README.md`
- Modify: `native/README.md`
- Modify: `native/Sources/Presentation/VersionHistory/VersionHistoryViewController.swift`
- Modify: version/build files selected by `native/build_and_log.sh`

**Interfaces:**
- Consumes: all completed tasks and admission evidence.
- Produces: installed, signed, user-testable TypeWhale build.

- [ ] **Step 1: Re-run concurrency and protected-worktree checks**

Run: `git branch --show-current && git status --short`

Run: `pgrep -af 'build_and_log|release_local_build|build_native_app|swiftc|xcodebuild' || true`

Inspect recent mtimes for native sources, build scripts, version history and logs. Stop if another task overlaps.

- [ ] **Step 2: Run focused and regression suites**

Run all new checks plus:

```bash
xcrun swiftc -parse-as-library native/Sources/Infrastructure/Models/MeloTTSVoicePack.swift native/Sources/Infrastructure/Models/ManagedASRModelCatalog.swift native/Sources/Infrastructure/ASR/ASRProviderCapabilities.swift native/Tests/ASRProviderCapabilitiesCheck.swift -o /tmp/ASRProviderCapabilitiesCheck && /tmp/ASRProviderCapabilitiesCheck
xcrun swiftc -parse-as-library native/Sources/Infrastructure/ASR/FunASRRuntimeManifest.swift native/Sources/Infrastructure/ASR/ManagedFunASRRuntime.swift native/Sources/Infrastructure/ASR/FunASRSidecarProtocol.swift native/Sources/Infrastructure/ASR/FunASRSidecar.swift native/Sources/Application/ProviderAwareFinalASR.swift native/Tests/ProviderAwareFinalASRCheck.swift -o /tmp/ProviderAwareFinalASRCheck && /tmp/ProviderAwareFinalASRCheck
xcrun swiftc -parse-as-library native/Sources/Domain/Text/RecognitionTextNormalizer.swift native/Sources/Domain/Text/RecognitionTextFilter.swift native/Sources/Application/FinalRecognitionUseCase.swift native/Tests/FinalRecognitionUseCaseCheck.swift -o /tmp/FinalRecognitionUseCaseCheck && /tmp/FinalRecognitionUseCaseCheck
bash native/Tests/FunASRBackendDomainCheck.sh
bash native/Tests/FunASRBackendUIBoundaryCheck.sh
bash native/Tests/SpeechInputCoordinatorBoundaryCheck.sh
bash native/Tests/TwoMinuteFinalRecognitionBoundaryCheck.sh
bash native/Tests/ReleaseVersionRuleCheck.sh
git diff --check
```

Expected: every command passes.

- [ ] **Step 3: Update architecture and release narrative before building**

Document the registry as source of truth, benchmark/production isolation, exact hotword strategies, MLX managed runtime, expanded dropdown, one SenseVoice fallback and unchanged realtime preview. Add the new version/build entry to all required records before invoking the release script.

- [ ] **Step 4: Run design review before final build**

Use the `design-review` skill on the benchmark window and expanded dropdown. Review hierarchy, row stability, scroll behavior, light/dark contrast, long error text, disabled menu clarity, recording/cancel feedback and whether any state visually implies false hotword support. Fix findings and rerun UI boundary tests.

- [ ] **Step 5: Build, install and verify signature**

Run: `./native/build_and_log.sh`

Expected: version guard succeeds, app replaces `/Applications/TypeWhale.app`, launches, and signature verification passes. If the three-build policy triggers a full version, complete the required release commit with only this task's files.

- [ ] **Step 6: Perform installed-app benchmark QA**

Open Models → ASR 模型测速. Record/import the shared WAV, verify all ten rows, run one candidate, A/B, cancel/retry and Test All. Confirm serial operation, timing fields, peak memory, raw text, truthful hotword badges and clear failures. Repeat visual inspection in light and dark themes.

- [ ] **Step 7: Perform installed-app production QA**

Select each enabled backend in the expanded dropdown and make a short real shortcut recording. Confirm final text reaches the existing rewrite/history/paste path. Force one adapter failure and confirm one visible SenseVoice fallback. Confirm selection during recording affects only the next session and default/current selection is not silently changed.

- [ ] **Step 8: Final verification and commit**

Run: `git status --short`

Run: `git diff --check`

Run: `codesign --verify --deep --strict /Applications/TypeWhale.app`

Commit only this task's documentation/version/build changes with `git commit -m "release: ship local ASR benchmark and backends"` when the build policy requires a complete-version release; otherwise leave the validated build-only changes recorded by the approved build workflow.

---

## Plan Self-Review Result

- Spec coverage: registry, ten candidates, native hotword formats, three isolated engines, benchmark recording/import, serial metrics, production dropdown, fallback, privacy, cancellation, real-model admission, UI review and installed build are each assigned to a task.
- Type consistency: all adapters consume `ASREngineRequest` and return `ASREngineResult`; benchmark uses the no-fallback `LocalASRRunning` contract; production adds fallback only in `ProviderAwareFinalASR`.
- Scope control: multi-hour recording remains excluded; VAD/CT-Punc remain dependencies; no online ASR or downstream rewrite changes are introduced.
- Placeholder scan: the plan contains no deferred implementation placeholders; Task 5 pins Python 3.10, MLX Audio 0.3.1, mlx-whisper 0.4.3, MLX 0.30.6, MLX-LM 0.30.5, Transformers 5.0.0rc3, Torch 2.11.0 and NumPy 1.26.4.
