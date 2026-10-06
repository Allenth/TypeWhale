# ASR Candidate Retirement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Completely retire six unsuitable ASR candidates from TypeWhale product code, UI, downloads, tests, documentation, and this Mac's model storage while preserving five supported ASR backends.

**Architecture:** Collapse the public ASR domain and registry to five candidates, migrate all retired persisted values to SenseVoice, and delete provider-specific branches from the shared Sherpa, FunASR, and MLX adapters without removing shared runtimes. Remove downloaded model directories by moving only prevalidated absolute targets to a timestamped Trash directory after the installed build no longer exposes those models.

**Tech Stack:** Swift 5/AppKit, C/sherpa-onnx, Python JSONL sidecars, shell boundary tests, JSON admission evidence, Markdown product documentation, macOS build/sign/install scripts.

## Global Constraints

- Retire Paraformer Contextual, Paraformer zh, SeACo Paraformer, Whisper Small MLX, Qwen3-ASR 0.6B Sherpa int8, and Zipformer bilingual zh-en Sherpa int8.
- Preserve SenseVoice int8, Parakeet TDT 0.6B v2 Sherpa int8, Fun-ASR Nano, Qwen3-ASR 0.6B MLX 8-bit, and Qwen3-ASR 1.7B MLX 8-bit.
- Preserve shared Sherpa, FunASR, and MLX runtimes; preserve FSMN-VAD.
- Remove CT-Punc because no retained backend consumes it.
- Migrate every retired backend raw value, `qwen3ASR`, and `whisperTinyMLX` to SenseVoice and persist the migration.
- Do not rewrite historical release facts; update current product truth and append a new retirement record.
- Move exact model directories to Trash; never recursively target a parent models/cache directory.
- Do not touch or stage `.superpowers/`, `native/Helpers/CapsuleConceptGallery/`, or `native/Sources/Presentation/Capsule/Concepts/`.
- Build only through `./native/build_and_log.sh`; the daily build must advance Build 833 to a unique next build, install `/Applications/TypeWhale Pro.app`, launch it, verify signing, and append the build log.

---

## File Map

### Product domain and migration

- Modify `native/Sources/Domain/ASRDomain.swift`: five public backends, stable menu tags, retired raw-value migration.
- Modify `native/Sources/Domain/ASRBenchmarkDomain.swift`: five benchmark candidate IDs.
- Create `native/Tests/RetiredASRCandidateBoundaryCheck.sh`: one source-of-truth retirement and migration gate.
- Modify `native/Tests/ExpandedASRBackendDomainCheck.sh`: assert the five-backend domain.
- Modify `native/Tests/FunASRBackendDomainCheck.sh`: Fun-ASR Nano only.

### Registries, workers, native routes, and UI

- Modify `native/Sources/Infrastructure/ASR/ASRModelRegistry.swift`.
- Modify `native/Sources/Infrastructure/ASR/ASRProviderCapabilities.swift`.
- Modify `native/Sources/Application/ProviderAwareFinalASR.swift`.
- Modify `native/Sources/Application/LocalASREngineAdapters.swift`.
- Modify `native/Sources/Application/SpeechInputCoordinator.swift`.
- Modify `native/Sources/Infrastructure/ASR/FunASRSidecarProtocol.swift`.
- Modify `native/Sources/Infrastructure/ASR/FunASRSidecar.swift`.
- Modify `native/Sources/Infrastructure/ASR/SenseVoiceASR.swift`.
- Modify `native/Sources/Infrastructure/ASR/SherpaBenchmarkAdapter.swift`.
- Modify `native/Helpers/TypeWhaleSherpaASR.swift`.
- Modify `native/TypeSpeakerNativeASR.h`.
- Modify `native/TypeSpeakerNativeASR.c`.
- Modify `native/Resources/funasr_asr_worker.py`.
- Modify `native/Resources/mlx_asr_worker.py`.
- Modify `native/Resources/local-candidate-admission.json`.
- Modify `tools/asr-eval/run_local_candidate_matrix.py`.
- Modify `tools/asr-eval/run_funasr_eval.py`.

### Model management

- Modify `native/Sources/Infrastructure/Models/ModelManifests.swift`.
- Modify `native/Sources/Infrastructure/Models/ManagedASRModelCatalog.swift`.
- Modify `native/Sources/Infrastructure/Models/ManagedASRModelDownloader.swift`.
- Modify `native/Sources/Presentation/Main/MainViewController+Actions.swift`.
- Delete `native/Tests/ZipformerSherpaModelIntegrationCheck.sh`.
- Delete `native/Tests/FunASRPunctuationDirectoryBoundaryCheck.sh`.
- Update affected registry, catalog, worker, sidecar, capability, selection, manifest, and downloader tests under `native/Tests/`.

### Product records

- Modify `docs/开发日志.md`.
- Modify `docs/产品需求文档.md`.
- Modify `docs/ARCHITECTURE.md`.
- Modify `docs/TYPEWHALE_PRO_ASR_STRATEGY.md`.
- Modify `docs/asr-eval/README.md`.
- Modify `README.md`.
- Modify `macos/README.md`.
- Modify `native/Sources/Presentation/VersionHistory/VersionHistoryViewController.swift`.

---

### Task 1: Lock the five-model product domain and legacy migration

**Files:**
- Create: `native/Tests/RetiredASRCandidateBoundaryCheck.sh`
- Modify: `native/Sources/Domain/ASRDomain.swift`
- Modify: `native/Sources/Domain/ASRBenchmarkDomain.swift`
- Modify: `native/Tests/ExpandedASRBackendDomainCheck.sh`
- Modify: `native/Tests/FunASRBackendDomainCheck.sh`
- Modify: `native/Tests/FunASRBackendUIBoundaryCheck.sh`

**Interfaces:**
- Produces: `ASRBackend` cases `senseVoice`, `parakeetSherpa`, `funASRNano`, `qwen3MLX06B`, `qwen3MLX17B`.
- Produces: `ASRCandidateID` cases `senseVoiceInt8`, `parakeetTDT06B`, `funASRNano2512`, `qwen3MLX06B`, `qwen3MLX17B`.
- Produces: `ASRBackend.load()` migration from retired raw values to `.senseVoice`.

- [ ] **Step 1: Add a failing retirement boundary test**

```bash
#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
DOMAIN="$ROOT_DIR/native/Sources/Domain/ASRDomain.swift"
CANDIDATES="$ROOT_DIR/native/Sources/Domain/ASRBenchmarkDomain.swift"

for retired in zipformerSherpa qwen3Sherpa paraformerContextual paraformerZH seacoParaformer whisperSmallMLX; do
  ! grep -Eq "case .*\\b${retired}\\b" "$DOMAIN"
done
for retained in senseVoice parakeetSherpa funASRNano qwen3MLX06B qwen3MLX17B; do
  grep -Eq "case .*\\b${retained}\\b" "$DOMAIN"
done
grep -Fq '"zipformerSherpa"' "$DOMAIN"
grep -Fq '"qwen3ASR"' "$DOMAIN"
grep -Fq 'return .senseVoice' "$DOMAIN"
! grep -Fq 'zipformer-bilingual-zh-en-sherpa-int8' "$CANDIDATES"
! grep -Fq 'whisper-small-mlx' "$CANDIDATES"
echo "RetiredASRCandidateBoundaryCheck passed"
```

- [ ] **Step 2: Run the new test and verify RED**

Run:

```bash
bash native/Tests/RetiredASRCandidateBoundaryCheck.sh
```

Expected: non-zero because the retired enum cases still exist.

- [ ] **Step 3: Reduce the domain to five backends and add explicit migration**

Target shape:

```swift
enum ASRBackend: String, CaseIterable, Codable {
    case senseVoice
    case parakeetSherpa
    case funASRNano
    case qwen3MLX06B
    case qwen3MLX17B

    private static let retiredRawValues: Set<String> = [
        "zipformerSherpa",
        "qwen3Sherpa",
        "paraformerContextual",
        "paraformerZH",
        "seacoParaformer",
        "whisperSmallMLX",
        "whisperTinyMLX",
        "qwen3ASR",
    ]
}
```

`load()` must first return retained raw values, retain the two historical MLX name migrations, then persist and return `.senseVoice` for every retired value. Menu tags become `0...4` in retained display order.

- [ ] **Step 4: Reduce benchmark IDs and update domain tests**

`ASRCandidateID.allCases` must contain exactly the five retained IDs. Rewrite existing positive shell checks so they assert five cases and explicit retired migration instead of checking removed cases.

- [ ] **Step 5: Run domain tests and verify GREEN**

Run:

```bash
bash native/Tests/RetiredASRCandidateBoundaryCheck.sh
bash native/Tests/ExpandedASRBackendDomainCheck.sh
bash native/Tests/FunASRBackendDomainCheck.sh
bash native/Tests/FunASRBackendUIBoundaryCheck.sh
```

Expected: all print `passed`.

- [ ] **Step 6: Commit the domain change**

```bash
git add native/Sources/Domain/ASRDomain.swift \
  native/Sources/Domain/ASRBenchmarkDomain.swift \
  native/Tests/RetiredASRCandidateBoundaryCheck.sh \
  native/Tests/ExpandedASRBackendDomainCheck.sh \
  native/Tests/FunASRBackendDomainCheck.sh \
  native/Tests/FunASRBackendUIBoundaryCheck.sh
git commit -m "refactor: retire unsuitable ASR domain cases"
```

### Task 2: Remove retired runtime routes and provider-specific code

**Files:**
- Modify: `native/Sources/Infrastructure/ASR/ASRModelRegistry.swift`
- Modify: `native/Sources/Infrastructure/ASR/ASRProviderCapabilities.swift`
- Modify: `native/Sources/Application/ProviderAwareFinalASR.swift`
- Modify: `native/Sources/Application/LocalASREngineAdapters.swift`
- Modify: `native/Sources/Application/SpeechInputCoordinator.swift`
- Modify: `native/Sources/Infrastructure/ASR/FunASRSidecarProtocol.swift`
- Modify: `native/Sources/Infrastructure/ASR/FunASRSidecar.swift`
- Modify: `native/Sources/Infrastructure/ASR/SenseVoiceASR.swift`
- Modify: `native/Sources/Infrastructure/ASR/SherpaBenchmarkAdapter.swift`
- Modify: `native/Helpers/TypeWhaleSherpaASR.swift`
- Modify: `native/TypeSpeakerNativeASR.h`
- Modify: `native/TypeSpeakerNativeASR.c`
- Modify: `native/Resources/funasr_asr_worker.py`
- Modify: `native/Resources/mlx_asr_worker.py`
- Modify: `native/Resources/local-candidate-admission.json`
- Modify: `tools/asr-eval/run_local_candidate_matrix.py`
- Modify: `tools/asr-eval/run_funasr_eval.py`

**Interfaces:**
- Consumes: five-case `ASRBackend` and `ASRCandidateID`.
- Produces: FunASR worker supporting only `fun-asr-nano-2512`.
- Produces: MLX worker supporting only Qwen3-ASR 0.6B/1.7B.
- Produces: Sherpa helper supporting only Parakeet.

- [ ] **Step 1: Extend the retirement boundary test to runtime files**

Add exact production files to a loop and reject the retired provider IDs:

```bash
RUNTIME_FILES=(
  "$ROOT_DIR/native/Sources/Infrastructure/ASR/ASRModelRegistry.swift"
  "$ROOT_DIR/native/Sources/Infrastructure/ASR/ASRProviderCapabilities.swift"
  "$ROOT_DIR/native/Resources/funasr_asr_worker.py"
  "$ROOT_DIR/native/Resources/mlx_asr_worker.py"
  "$ROOT_DIR/native/Helpers/TypeWhaleSherpaASR.swift"
  "$ROOT_DIR/native/Resources/local-candidate-admission.json"
)
for file in "${RUNTIME_FILES[@]}"; do
  for retired_id in \
    zipformer-bilingual-zh-en-sherpa-int8 \
    qwen3-asr-0.6b-sherpa-int8 \
    paraformer-hotword-contextual \
    paraformer-zh \
    seaco-paraformer \
    whisper-small-mlx; do
    ! grep -Fq "$retired_id" "$file"
  done
done
```

- [ ] **Step 2: Run the boundary test and verify RED**

Run:

```bash
bash native/Tests/RetiredASRCandidateBoundaryCheck.sh
```

Expected: non-zero on the first retired provider reference.

- [ ] **Step 3: Collapse registry, capabilities, and routing**

Delete retired descriptors and switch cases. `ProviderAwareFinalASR.providerID(for:)` becomes:

```swift
private func providerID(for backend: ASRBackend) -> String? {
    switch backend {
    case .senseVoice, .parakeetSherpa, .qwen3MLX06B, .qwen3MLX17B:
        return nil
    case .funASRNano:
        return "fun-asr-nano-2512"
    }
}
```

The registry descriptor count and admission evidence count become five.

- [ ] **Step 4: Remove CT-Punc and multi-provider FunASR protocol**

Remove `punctuationDirectory`, `punctuation_dir`, `punctuation_model`, `CT_Transformer`, and all three Paraformer provider specs. Keep this worker contract:

```python
SUPPORTED_PROVIDERS = {"fun-asr-nano-2512"}
```

`FunASRLocalEngineAdapter` must warm and transcribe Fun-ASR Nano without a punctuation resolver. Remove the CT-Punc closure from `SpeechInputCoordinator`.

- [ ] **Step 5: Remove Whisper from MLX**

Target provider set:

```python
SUPPORTED_PROVIDERS = {"qwen3-asr-0.6b-mlx", "qwen3-asr-1.7b-mlx"}
```

Remove `_whisper_transcribe`, `initial_prompt` handling, and Whisper-specific result branches. Keep Qwen chunking, 25-second windows, one-second overlap, and deterministic merge unchanged.

- [ ] **Step 6: Remove Qwen Sherpa and Zipformer native routes**

Delete `TypeSpeakerNativeQwen3RecognizerCreate` and `TypeSpeakerNativeZipformerRecognizerCreate` declarations/definitions and their helper/benchmark switch cases. Keep SenseVoice and Parakeet native functions unchanged. Reduce `TypeWhaleSherpaASR.makeBridge` to Parakeet:

```swift
guard provider == "parakeet-tdt-0.6b-v2-sherpa-int8" else {
    throw HelperError.unsupportedProvider(provider)
}
```

- [ ] **Step 7: Update evaluation tools and runtime tests**

Convert Whisper MLX protocol tests to Qwen provider fixtures. Convert Qwen/Zipformer Sherpa tests to Parakeet. Convert four-provider FunASR tests to Fun-ASR Nano-only tests and remove punctuation assertions. Update:

```bash
native/Tests/ASRModelRegistryCheck.swift
native/Tests/ASRProviderCapabilitiesCheck.swift
native/Tests/FunASRFourProviderMatrixCheck.py
native/Tests/FunASRSidecarProtocolCheck.swift
native/Tests/FunASRWorkerProtocolCheck.py
native/Tests/MLXASRSidecarCheck.swift
native/Tests/MLXASRSidecarProtocolCheck.swift
native/Tests/MLXASRWorkerProtocolCheck.py
native/Tests/ProviderAwareFinalASRCheck.swift
native/Tests/SherpaASRSidecarCheck.swift
native/Tests/SherpaBenchmarkAdapterCheck.swift
native/Tests/UnifiedLocalASRAdapterCheck.swift
```

Delete `native/Tests/FunASRPunctuationDirectoryBoundaryCheck.sh`.

- [ ] **Step 8: Run focused runtime tests**

Run:

```bash
bash native/Tests/RetiredASRCandidateBoundaryCheck.sh
python3 native/Tests/FunASRFourProviderMatrixCheck.py
python3 native/Tests/FunASRWorkerProtocolCheck.py
python3 native/Tests/MLXASRWorkerProtocolCheck.py
```

Expected: all print their pass message and no retired provider ID appears in current runtime files.

- [ ] **Step 9: Typecheck through the native build compiler**

Run:

```bash
./native/build_native_app.sh
```

Expected: Swift/C compilation succeeds. Do not install this intermediate artifact.

- [ ] **Step 10: Commit runtime retirement**

Stage only the Task 2 files after `git status --short`, then:

```bash
git commit -m "refactor: remove retired ASR runtime routes"
```

### Task 3: Remove download and model-management surfaces

**Files:**
- Modify: `native/Sources/Infrastructure/Models/ModelManifests.swift`
- Modify: `native/Sources/Infrastructure/Models/ManagedASRModelCatalog.swift`
- Modify: `native/Sources/Infrastructure/Models/ManagedASRModelDownloader.swift`
- Modify: `native/Sources/Presentation/Main/MainViewController+Actions.swift`
- Delete: `native/Tests/ZipformerSherpaModelIntegrationCheck.sh`
- Modify: `native/Tests/LocalSherpaModelManifestCheck.swift`
- Modify: `native/Tests/ManagedASRModelCatalogCheck.swift`
- Modify: `native/Tests/ManagedASRModelDownloaderProcessScanCheck.swift`
- Modify: `native/Tests/LocalASRModelSelectionBoundaryCheck.sh`

**Interfaces:**
- Consumes: retained model IDs from Task 1.
- Produces: model manager entries for Fun-ASR Nano and FSMN-VAD only in the FunASR catalog; local MLX models remain registry-discovered.

- [ ] **Step 1: Extend the retirement boundary to model-management files**

Reject all retired IDs plus `ct-punc` in `ModelManifests.swift`, `ManagedASRModelCatalog.swift`, `ManagedASRModelDownloader.swift`, and `MainViewController+Actions.swift`.

- [ ] **Step 2: Run the boundary test and verify RED**

Run:

```bash
bash native/Tests/RetiredASRCandidateBoundaryCheck.sh
```

Expected: non-zero because Zipformer, Paraformer, and CT-Punc management still exists.

- [ ] **Step 3: Remove model catalog entries and special downloader**

`ManagedASRModelCatalog.asrModels` must contain only:

```swift
[
    "fun-asr-nano-2512",
    "fsmn-vad",
]
```

Delete `ZipformerBilingualModelManifest`, `Qwen3ASRModelManifest`, the Zipformer archive URL/untar branch, Paraformer/SeACo required paths, Whisper selection discovery, and CT-Punc readiness UI.

- [ ] **Step 4: Update and delete obsolete tests**

Delete `ZipformerSherpaModelIntegrationCheck.sh`. Reduce `LocalSherpaModelManifestCheck.swift` to retained Parakeet coverage. Assert the catalog has exactly Fun-ASR Nano and FSMN-VAD, and that downloader process scanning ignores only unrelated retained model staging paths.

- [ ] **Step 5: Run model-management tests**

Run:

```bash
bash native/Tests/RetiredASRCandidateBoundaryCheck.sh
bash native/Tests/LocalASRModelSelectionBoundaryCheck.sh
```

Then run `./native/build_native_app.sh`.

Expected: boundary tests pass and compilation succeeds.

- [ ] **Step 6: Commit model-management removal**

```bash
git status --short
git commit -m "refactor: remove retired ASR model management"
```

Stage only Task 3 files before the commit.

### Task 4: Update current product truth and release records

**Files:**
- Modify: `docs/开发日志.md`
- Modify: `docs/产品需求文档.md`
- Modify: `docs/ARCHITECTURE.md`
- Modify: `docs/TYPEWHALE_PRO_ASR_STRATEGY.md`
- Modify: `docs/asr-eval/README.md`
- Modify: `README.md`
- Modify: `macos/README.md`
- Modify: `native/Sources/Presentation/VersionHistory/VersionHistoryViewController.swift`

**Interfaces:**
- Produces: current documentation that names five supported models and six explicitly retired models.
- Preserves: historical dated entries below the new release record.

- [ ] **Step 1: Add a documentation truth gate**

Extend `RetiredASRCandidateBoundaryCheck.sh` so current-domain sections and the new top release entry contain all six retired display names plus the sentence `不适合 TypeWhale 当前产品目标`. Do not require old historical sections to remove their names.

- [ ] **Step 2: Run the gate and verify RED**

Run:

```bash
bash native/Tests/RetiredASRCandidateBoundaryCheck.sh
```

Expected: non-zero because the new retirement record does not exist.

- [ ] **Step 3: Update current product documentation**

Document the decision in product language:

```text
Paraformer Contextual、Paraformer zh、SeACo Paraformer、Whisper Small MLX、
Qwen3-ASR 0.6B Sherpa 与 Zipformer 已完成真实测试。它们在准确率、资源占用、
启动速度或 TypeWhale 输入场景适配性上不达标，不适合 TypeWhale 当前产品目标，
不再作为可选、可下载或可执行模型。
```

Keep historical research findings, but label the strategy rows `已评估并退役`.

- [ ] **Step 4: Prepare Build 834 records**

Add a top `VersionEntry` for `版本 2.0.58 (Build 834)` and a matching top development-log section before running the unique build. Update the current build references in `README.md` and `macos/README.md`. Include UI removal, legacy migration, exact weight cleanup, retained five-model boundary, and validation status. If a concurrent build advances the repository beyond 833 before the build gate, recompute all four records to the next available build instead of reusing 834.

- [ ] **Step 5: Run documentation gate**

```bash
bash native/Tests/RetiredASRCandidateBoundaryCheck.sh
git diff --check
```

Expected: pass and no whitespace errors.

- [ ] **Step 6: Commit documentation truth**

```bash
git commit -m "docs: record retired ASR candidates"
```

Stage only the Task 4 files.

### Task 5: Move retired model weights to Trash

**Files:**
- External recoverable move only; no repository files.

**Interfaces:**
- Produces: `~/.Trash/TypeWhale-retired-asr-20260726-<time>/` containing exact retired model directories.
- Preserves: every retained model and runtime directory.

- [ ] **Step 1: Stop TypeWhale before moving loaded weights**

Use normal application termination so no retired worker keeps deleted files open. Confirm TypeWhale and its owned ASR workers are no longer running before moving data.

- [ ] **Step 2: Resolve and validate the exact targets**

Use an explicit array containing only:

```text
$HOME/Library/Application Support/TypeWhale Pro/Models/funasr/paraformer-hotword-contextual
$HOME/Library/Application Support/TypeWhale Pro/Models/funasr/paraformer-zh
$HOME/Library/Application Support/TypeWhale Pro/Models/funasr/ct-punc
$HOME/Library/Application Support/TypeWhale Pro/Models/mlx-asr/whisper-small-mlx
$HOME/Library/Application Support/TypeWhale Pro/Models/zipformer-bilingual-zh-en-int8
$HOME/Library/Application Support/TypeWhale/Models/qwen3-asr-0.6b-int8
$HOME/.cache/modelscope/hub/models/iic/speech_seaco_paraformer_large_asr_nat-zh-cn-16k-common-vocab8404-pytorch
$HOME/.cache/modelscope/hub/models/._____temp/iic/speech_seaco_paraformer_large_asr_nat-zh-cn-16k-common-vocab8404-pytorch
```

Reject any target whose canonical parent is not one of the four expected model/cache parents. Record `du -sk` before moving.

- [ ] **Step 3: Move existing targets into timestamped Trash**

Create one explicit Trash directory and move each existing target under a unique label. Missing targets are reported as already absent. Do not use `rm`, globs, or recursive parent moves.

- [ ] **Step 4: Verify retained data remains**

Verify these exact paths still exist:

```text
/Applications/TypeWhale Pro.app/Contents/Resources/Models/sensevoice-native
$HOME/Library/Application Support/TypeWhale Pro/Models/funasr/fun-asr-nano-2512
$HOME/Library/Application Support/TypeWhale Pro/Models/funasr/fsmn-vad
$HOME/.cache/huggingface/hub/models--mlx-community--Qwen3-ASR-0.6B-8bit
$HOME/.cache/huggingface/hub/models--mlx-community--Qwen3-ASR-1.7B-8bit
```

Report actual moved size and Trash recovery path.

### Task 6: Final regression, build, installed-app review, and release commit

**Files:**
- Modify: `native/build_native_app.sh` (daily build number advanced by the build workflow).
- Modify: `docs/构建日志.md` (successful installed-build record).
- Modify: `README.md` (current build reference if the build guard changes the planned number).
- Modify: `macos/README.md` (current build reference if the build guard changes the planned number).
- Modify: `docs/开发日志.md` (build verification outcome and any guard-directed build-number correction).
- Modify: `native/Sources/Presentation/VersionHistory/VersionHistoryViewController.swift` (matching build entry if the guard-directed number changes).
- No unrelated files.

**Interfaces:**
- Produces: installed TypeWhale Pro 2.0.58 Build 834.
- Produces: one release commit containing the exact built source and generated build records.

- [ ] **Step 1: Re-run concurrency and worktree safety checks**

Run:

```bash
git branch --show-current
git status --short
pgrep -alf 'build_and_log\.sh|release_local_build\.sh|build_native_app\.sh|swiftc|xcodebuild' || true
```

Expected: branch `codex/typewhale-pro-asr-hotwords`, no concurrent build, and only known task changes plus the three protected untracked paths.

- [ ] **Step 2: Run focused tests**

Run all updated shell/Python retirement, domain, worker, registry, capability, selection, sidecar, downloader, and failure-authority checks. Expected: every command exits zero and no test still expects a retired candidate.

- [ ] **Step 3: Scan current production code**

Run:

```bash
rg -n -i 'zipformer|qwen3Sherpa|qwen3-asr-0\\.6b-sherpa|paraformerContextual|paraformer-hotword-contextual|paraformerZH|paraformer-zh|seacoParaformer|seaco-paraformer|whisperSmallMLX|whisper-small-mlx|ct-punc' \
  native/Sources native/Resources native/Helpers native/TypeSpeakerNativeASR.h native/TypeSpeakerNativeASR.c
```

Expected: no current production references.

- [ ] **Step 4: Build, install, launch, sign, and log**

Run:

```bash
./native/build_and_log.sh
```

Expected: Build 834 compiles, overwrites `/Applications/TypeWhale Pro.app`, launches, passes deep/strict signing verification, and appends `docs/构建日志.md`.

- [ ] **Step 5: Review the installed UI**

Open the model tab and common status selector. Confirm exactly five ASR choices, no blank/disabled retired entries, no clipped layout, and correct selection after a retired UserDefaults fixture migrates to SenseVoice. This UI review must cover layout and the user-visible migration state.

- [ ] **Step 6: Smoke-test retained routes**

Verify SenseVoice starts, Parakeet can be selected and warmed, Fun-ASR Nano remains downloadable/selectable, and both Qwen MLX entries remain available. A short real recording through the current selected backend must finish without invoking a retired provider.

- [ ] **Step 7: Review final diff and commit**

Run:

```bash
git status --short
git diff --check
git diff --stat
```

Stage only release/build files created after the earlier task commits, then:

```bash
git commit -m "chore: release retired ASR model lineup"
```

- [ ] **Step 8: Final evidence**

Report:

- five retained UI models;
- six retired candidates absent from current production code;
- Build 834 install/sign/launch status;
- actual Trash path and moved size;
- automated and manual checks completed;
- any interaction path that could not be physically exercised.
