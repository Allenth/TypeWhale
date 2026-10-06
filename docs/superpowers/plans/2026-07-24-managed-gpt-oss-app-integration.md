# Managed GPT-OSS App Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a production-grade, TypeWhale-managed GPT-OSS 20B MLX engine to the Models tab and real rewrite/translation path, while adding `qwen3.6-rewrite:latest` to the existing Ollama model selector.

**Architecture:** Keep the current `SmartAITextEngine` boundary and introduce `SmartAIEngineSelection`, which selects either a standard `SmartAIModel` or a TypeWhale-managed MLX model without placing GPT-OSS in the existing popup’s `CaseIterable` list. The managed path is backed by a TypeWhale-owned model catalog, downloader, JSONL helper runtime, and final-only Harmony parser; the current Ollama/DeepSeek choice remains persisted as the return target.

**Tech Stack:** Swift 5/AppKit/Foundation/URLSession/CryptoKit, Python 3.10, MLX/`mlx_lm`, JSONL over `Process` pipes, Hugging Face immutable revision downloads, shell/Python/Swift executable checks.

## Global Constraints

- Work only on `codex/typewhale-pro-asr-hotwords` in `$HOME/Pictures/macOSwinOSCoding/TypeSpeaker`.
- Before every write/build/stage/commit, re-run branch, dirty-worktree, build-process, and relevant mtime checks.
- Preserve all pre-existing `.superpowers/brainstorm`, `native/Helpers/CapsuleConceptGallery`, and `native/Sources/Presentation/Capsule/Concepts` files.
- Do not create a worktree unless the main worktree becomes unsafe and the user approves the isolation.
- Use TDD for every behavior change: write a failing test, observe the expected failure, implement the minimum, then rerun.
- GPT-OSS must remain opt-in and experimental; `SmartAIModel.defaultModel` remains `.ollamaQwen2BMLX`.
- Product code and UI must not detect, name, or depend on LM Studio.
- The one-time development APFS clone may receive an external source path only as an explicit tool argument; it must not persist or log that path.
- GPT-OSS must not depend on Ollama or open Terminal.
- GPT-OSS failures return original text and must never silently change provider.
- Harmony `analysis`, raw token IDs, prompts, and user test text must not be shown or persisted.
- Do not add an idle unload timer; never release LLM resources during recording, recognition, rewrite, translation, or paste.
- The first build may use the compatible TypeWhale-managed `mlx-asr/v1` Python runtime through a capability locator; production engine code must not hardcode that path.
- The immutable download revision is `773a7da77e569019bb0fd17a554b263738d669a3`.
- App target remains macOS 14 arm64 and uses only system fonts.
- After code changes: update architecture/development/version history, run tests, use `./native/build_and_log.sh`, install and open `/Applications/TypeWhale Pro.app`, perform installed-App visual/behavior checks, then commit only owned files.

---

## File Map

### Create

- `native/Sources/Core/SmartInput/ManagedLLMSelection.swift` — persistent opt-in state and remembered return model.
- `native/Sources/Infrastructure/SmartRewrite/ManagedLLMModelCatalog.swift` — immutable model/artifact manifest and structural/cryptographic validation.
- `native/Sources/Infrastructure/SmartRewrite/ManagedLLMDownloadManager.swift` — resumable user-triggered downloads, cancellation, staging, verification, and atomic promotion.
- `native/Sources/Infrastructure/SmartRewrite/HarmonyFinalOutputParser.swift` — final-only token-channel parser.
- `native/Sources/Infrastructure/SmartRewrite/ManagedMLXLLMProtocol.swift` — Codable JSONL request/response and metrics types.
- `native/Sources/Infrastructure/SmartRewrite/ManagedMLXRuntimeLocator.swift` — version/capability validation for the TypeWhale-managed Python runtime.
- `native/Sources/Infrastructure/SmartRewrite/ManagedMLXLLMRuntime.swift` — owned helper process lifecycle, request serialization, timeout, cancellation, and restart.
- `native/Sources/Infrastructure/SmartRewrite/TypeWhaleLocalLLMEngine.swift` — `SmartAITextEngine` adapter using existing prompt builders and sanitizer.
- `native/Sources/Presentation/Main/ManagedLLMModelPanel.swift` — independent Models-tab UI section.
- `native/Resources/managed_mlx_llm_worker.py` — offline MLX worker bundled into the App resources.
- `tools/local-llm-eval/bootstrap_managed_gpt_oss.py` — development-only APFS clone bootstrap.
- `native/Tests/ManagedLLMSelectionCheck.swift`
- `native/Tests/ManagedLLMModelCatalogCheck.swift`
- `native/Tests/ManagedLLMDownloadManagerCheck.swift`
- `native/Tests/HarmonyFinalOutputParserCheck.swift`
- `native/Tests/ManagedMLXLLMProtocolCheck.swift`
- `native/Tests/ManagedMLXRuntimeLocatorCheck.swift`
- `native/Tests/ManagedMLXLLMRuntimeCheck.swift`
- `native/Tests/TypeWhaleLocalLLMEngineCheck.swift`
- `native/Tests/ManagedLLMModelPanelBoundaryCheck.sh`
- `native/Tests/ManagedLLMLifecycleBoundaryCheck.sh`
- `tools/local-llm-eval/test_bootstrap_managed_gpt_oss.py`

### Modify

- `native/Sources/Core/SmartInput/SmartAIModel.swift`
- `native/Sources/Infrastructure/SmartRewrite/SelectedSmartAITextEngine.swift`
- `native/Sources/Infrastructure/SmartRewrite/SelectedScreenshotTranslationEngine.swift`
- `native/Sources/Presentation/Main/MainViewController.swift`
- `native/Sources/Presentation/Main/MainViewController+Configuration.swift`
- `native/Sources/Presentation/Main/MainViewController+Actions.swift`
- `native/Sources/Presentation/Main/MainViewController+PanelLayout.swift`
- `native/Sources/Application/SpeechInputCoordinator.swift`
- `native/TypeSpeakerApp.swift`
- `native/build_native_app.sh`
- `native/Tests/SmartAIModelCheck.swift`
- `native/Tests/SelectedSmartAITextEngineCheck.swift`
- `native/Tests/SelectedScreenshotTranslationEngineCheck.swift`
- `native/Tests/MainWindowLayoutBoundaryCheck.sh`
- `docs/ARCHITECTURE.md`
- `docs/开发日志.md`
- `native/Sources/Presentation/VersionHistory/VersionHistoryViewController.swift`

---

### Task 1: Add Qwen3.6 35B Rewrite to the existing selector

**Files:**
- Modify: `native/Sources/Core/SmartInput/SmartAIModel.swift`
- Modify: `native/Sources/Infrastructure/SmartRewrite/SelectedScreenshotTranslationEngine.swift`
- Modify: `native/Tests/SmartAIModelCheck.swift`
- Modify: `native/Tests/SelectedSmartAITextEngineCheck.swift`
- Modify: `native/Tests/SelectedScreenshotTranslationEngineCheck.swift`

**Interfaces:**
- Consumes: existing `SmartAIModel`, `SmartAIProvider`, and `SelectedSmartAITextEngine`.
- Produces: `SmartAIModel.ollamaQwen36Rewrite`, display name `本地 Qwen3.6 35B Rewrite`, engine name `qwen3.6-rewrite:latest`.

- [x] **Step 1: Extend model checks first**

Add these exact assertions to `SmartAIModelCheck`:

```swift
precondition(SmartAIModel.allCases.map(\.rawValue) == [
    "ollama-qwen3.5-2b-mlx",
    "ollama-qwen3.5-9b-mlx",
    "ollama-qwen3.6-35b-mlx",
    "ollama-qwen3.6-35b-rewrite",
    "deepseek-v4-flash",
])
precondition(SmartAIModel.ollamaQwen36Rewrite.provider == .ollama)
precondition(SmartAIModel.ollamaQwen36Rewrite.engineModelName == "qwen3.6-rewrite:latest")
precondition(SmartAIModel.fromStoredRawValue("qwen3.6-rewrite:latest") == .ollamaQwen36Rewrite)
```

Add an `ollamaRewrite` probe to `SelectedSmartAITextEngineCheck`, route `.ollamaQwen36Rewrite` to it, perform one rewrite, and assert exactly one call. Add the same exhaustive model case to `SelectedScreenshotTranslationEngine`, then assert `SelectedScreenshotTranslationEngineCheck` routes screenshot translation to the Rewrite model’s Ollama probe.

- [x] **Step 2: Run RED checks**

Run:

```bash
xcrun swiftc native/Sources/Core/SmartInput/SmartAIModel.swift native/Tests/SmartAIModelCheck.swift -o /tmp/SmartAIModelCheck
```

Expected: compile failure because `ollamaQwen36Rewrite` does not exist.

- [x] **Step 3: Implement the enum case and exhaustive switches**

Add:

```swift
case ollamaQwen36Rewrite = "ollama-qwen3.6-35b-rewrite"
```

Return `.ollama`, `本地 Qwen3.6 35B Rewrite`, `qwen3.6-rewrite:latest`, and `false` for provider/display/engine/usage switches. Map stored values `"qwen3.6-rewrite:latest"` and `"Qwen3.6-35B-Rewrite"` to this case. Add the case to all existing Ollama switch branches.

- [x] **Step 4: Run GREEN checks**

Run:

```bash
xcrun swiftc native/Sources/Core/SmartInput/SmartAIModel.swift native/Tests/SmartAIModelCheck.swift -o /tmp/SmartAIModelCheck
/tmp/SmartAIModelCheck
```

Expected: `SmartAIModelCheck passed`.

Run:

```bash
xcrun swiftc -parse-as-library -target arm64-apple-macosx14.0 -framework AppKit \
  native/Sources/Core/AppBrand.swift \
  $(find native/Sources/Core/SmartInput native/Sources/Core/ScreenshotTranslation native/Sources/Infrastructure/SmartRewrite -name '*.swift' -type f | sort) \
  native/Sources/Infrastructure/Diagnostics/LaunchDiagnostics.swift \
  native/Tests/SelectedSmartAITextEngineCheck.swift \
  -o /tmp/SelectedSmartAITextEngineCheck
/tmp/SelectedSmartAITextEngineCheck
```

Expected: `SelectedSmartAITextEngineCheck passed`.

Run:

```bash
xcrun swiftc -parse-as-library -target arm64-apple-macosx14.0 -framework AppKit \
  native/Sources/Core/AppBrand.swift \
  $(find native/Sources/Core/SmartInput native/Sources/Core/ScreenshotTranslation native/Sources/Infrastructure/SmartRewrite -name '*.swift' -type f | sort) \
  native/Sources/Infrastructure/Diagnostics/LaunchDiagnostics.swift \
  native/Tests/SelectedScreenshotTranslationEngineCheck.swift \
  -o /tmp/SelectedScreenshotTranslationEngineCheck
/tmp/SelectedScreenshotTranslationEngineCheck
```

Expected: `SelectedScreenshotTranslationEngineCheck passed`.

- [x] **Step 5: Commit Task 1**

```bash
git add native/Sources/Core/SmartInput/SmartAIModel.swift native/Sources/Infrastructure/SmartRewrite/SelectedScreenshotTranslationEngine.swift native/Tests/SmartAIModelCheck.swift native/Tests/SelectedSmartAITextEngineCheck.swift native/Tests/SelectedScreenshotTranslationEngineCheck.swift
git commit -m "feat: add Qwen 35B rewrite model"
```

---

### Task 2: Define managed model selection and immutable GPT-OSS catalog

**Files:**
- Create: `native/Sources/Core/SmartInput/ManagedLLMSelection.swift`
- Create: `native/Sources/Infrastructure/SmartRewrite/ManagedLLMModelCatalog.swift`
- Create: `native/Tests/ManagedLLMSelectionCheck.swift`
- Create: `native/Tests/ManagedLLMModelCatalogCheck.swift`

**Interfaces:**
- Produces:
  - `enum ManagedLLMModelID: String, CaseIterable, Codable`
  - `enum SmartAIEngineSelection: Equatable`
  - `struct ManagedLLMSelection: Equatable, Codable`
  - `struct ManagedLLMSelectionStore`
  - `struct ManagedLLMArtifact`
  - `struct ManagedLLMModelDescriptor`
  - `enum ManagedLLMReadiness: Equatable`
  - `struct ManagedLLMModelRegistry`

- [x] **Step 1: Write RED selection tests**

Use an isolated `UserDefaults(suiteName:)` and assert:

```swift
let defaults = UserDefaults(suiteName: "ManagedLLMSelectionCheck.\(UUID())")!
let store = ManagedLLMSelectionStore(defaults: defaults)
precondition(store.load() == ManagedLLMSelection(
    selectedModel: .gptOSS20BMXFP4Q8,
    isEnabled: false,
    returnModel: .ollamaQwen2BMLX
))
store.save(.init(selectedModel: .gptOSS20BMXFP4Q8, isEnabled: true, returnModel: .deepSeekV4Flash))
precondition(store.load().isEnabled)
precondition(store.load().returnModel == .deepSeekV4Flash)
```

- [x] **Step 2: Write RED catalog tests**

Create a temporary fixture with all ten required artifact names. Assert `.missing` before files exist, `.invalid("…")` for a wrong-size shard, and `.ready(modelURL)` after fixture descriptors inject small test sizes/hashes.

The production descriptor must contain revision `773a7da77e569019bb0fd17a554b263738d669a3`, total bytes `12_104_215_835`, and this complete artifact map:

```swift
("chat_template.jinja", 16_738, "a4c9919cbbd4acdd51ccffe22da049264b1b73e59055fa58811a99efbd7c8146")
("config.json", 33_998, "d1c1f73bf62116ed0bb37c068af80534543cd1de9b61d609fc01bf70920e842d")
("generation_config.json", 177, "f9970ada892d2d1f72e3ed0a6535ccebadd11897318794ca671d8c7014c957da")
("model-00001-of-00003.safetensors", 5_303_719_858, "57f4846924652b1b23537c6c6d6b65f64fde811e47369d4e23c5c45b4d7584a7")
("model-00002-of-00003.safetensors", 5_281_581_967, "4a862a873080e489db16125877e19553b958562ff4dd0246135bc061c3293652")
("model-00003-of-00003.safetensors", 1_490_905_743, "16c32bb8dbd1fa8d556815706589d6d6480d29946196cd2fe2b721d4daf84132")
("model.safetensors.index.json", 67_046, "6fa724aa7a9130561f9b97debcc06c56ba150d8fbd58fc1168f53a22d6a5490a")
("special_tokens_map.json", 440, "8464cabd6eda239fe46ebf8ae63b46c417721784a961a022f6b59174a2cda0e2")
("tokenizer.json", 27_868_174, "0614fe83cadab421296e664e1f48f4261fa8fef6e03e63bb75c20f38e37d07d3")
("tokenizer_config.json", 21_694, "2d8386578f85ea1fa698e78c58b2d8503e8122d6b110b61f93d3995601b07d91")
```

- [x] **Step 3: Run RED**

Run:

```bash
xcrun swiftc native/Sources/Core/SmartInput/SmartAIModel.swift native/Tests/ManagedLLMSelectionCheck.swift -o /tmp/ManagedLLMSelectionCheck
```

Expected: missing `ManagedLLMSelectionStore`.

Run:

```bash
xcrun swiftc -framework CryptoKit native/Sources/Infrastructure/Models/ModelManifests.swift native/Tests/ManagedLLMModelCatalogCheck.swift -o /tmp/ManagedLLMModelCatalogCheck
```

Expected: missing `ManagedLLMModelRegistry`.

- [x] **Step 4: Implement selection and catalog**

Define:

```swift
enum ManagedLLMModelID: String, CaseIterable, Codable {
    case gptOSS20BMXFP4Q8 = "gpt-oss-20b-mxfp4-q8"
}

enum SmartAIEngineSelection: Equatable {
    case standard(SmartAIModel)
    case managed(ManagedLLMModelID)
}

struct ManagedLLMSelection: Equatable, Codable {
    var selectedModel: ManagedLLMModelID
    var isEnabled: Bool
    var returnModel: SmartAIModel
}
```

`ManagedLLMSelectionStore` must expose `static let shared`, use keys under `managedLLM.*`, and default to disabled with the current normal model.

Catalog URL form:

```swift
https://huggingface.co/mlx-community/gpt-oss-20b-MXFP4-Q8/resolve/773a7da77e569019bb0fd17a554b263738d669a3/<artifact>?download=true
```

Validation must reject symlinks escaping the managed model directory, require exact size for every artifact, stream SHA-256 in 4 MiB chunks, and cache only a key containing path, size, and mtime.

- [x] **Step 5: Run GREEN**

Compile and run both checks with the new production files included.

Expected:

```text
ManagedLLMSelectionCheck passed
ManagedLLMModelCatalogCheck passed
```

- [x] **Step 6: Commit Task 2**

```bash
git add native/Sources/Core/SmartInput/ManagedLLMSelection.swift native/Sources/Infrastructure/SmartRewrite/ManagedLLMModelCatalog.swift native/Tests/ManagedLLMSelectionCheck.swift native/Tests/ManagedLLMModelCatalogCheck.swift
git commit -m "feat: define managed GPT-OSS model state"
```

---

### Task 3: Add the final-only Harmony protocol boundary

**Files:**
- Create: `native/Sources/Infrastructure/SmartRewrite/HarmonyFinalOutputParser.swift`
- Create: `native/Sources/Infrastructure/SmartRewrite/ManagedMLXLLMProtocol.swift`
- Create: `native/Tests/HarmonyFinalOutputParserCheck.swift`
- Create: `native/Tests/ManagedMLXLLMProtocolCheck.swift`

**Interfaces:**
- Produces:
  - `enum HarmonyFinalOutputError: Error, Equatable`
  - `struct HarmonyFinalOutputParser`
  - `struct ManagedMLXLLMRequest: Codable, Equatable`
  - `struct ManagedMLXLLMResponse: Codable, Equatable`
  - `struct ManagedLLMMetrics: Codable, Equatable`

- [x] **Step 1: Write parser RED tests**

Cover:

```swift
precondition(try parser.parse([
    .init(channel: "analysis", text: "private"),
    .init(channel: "final", text: "公开正文"),
]) == "公开正文")
```

Assert errors for analysis-only, two final channels, empty final, and unknown channel. Assert error descriptions never contain any channel text.

- [x] **Step 2: Write protocol RED tests**

Round-trip a request:

```swift
ManagedMLXLLMRequest(
    protocolVersion: 1,
    id: "fixture",
    command: .rewrite,
    modelDirectory: "/managed/model",
    systemPrompt: "system",
    userPrompt: "user",
    reasoning: .low,
    maxTokens: 256
)
```

Round-trip a successful response with only `finalText` and metrics, plus a cancellation response. Reflect encoded JSON keys and assert none equal `analysis`, `thinking`, `rawTokens`, or `rawOutput`.

- [x] **Step 3: Run RED**

Compile each test against the not-yet-existing files.

Expected: missing parser/protocol types.

- [x] **Step 4: Implement minimal parser and Codable protocol**

The parser accepts a token-channel sequence supplied by the worker, requires exactly one non-empty final channel, trims surrounding whitespace, and never stores rejected content inside an error.

The response schema is:

```swift
struct ManagedMLXLLMResponse: Codable, Equatable {
    let protocolVersion: Int
    let id: String
    let ok: Bool
    let finalText: String?
    let errorCode: String?
    let errorMessage: String?
    let metrics: ManagedLLMMetrics?
    let cancelled: Bool
}
```

- [x] **Step 5: Run GREEN**

Expected:

```text
HarmonyFinalOutputParserCheck passed
ManagedMLXLLMProtocolCheck passed
```

- [x] **Step 6: Commit Task 3**

```bash
git add native/Sources/Infrastructure/SmartRewrite/HarmonyFinalOutputParser.swift native/Sources/Infrastructure/SmartRewrite/ManagedMLXLLMProtocol.swift native/Tests/HarmonyFinalOutputParserCheck.swift native/Tests/ManagedMLXLLMProtocolCheck.swift
git commit -m "feat: add final-only local LLM protocol"
```

---

### Task 4: Build the owned helper runtime and offline worker

**Files:**
- Create: `native/Sources/Infrastructure/SmartRewrite/ManagedMLXRuntimeLocator.swift`
- Create: `native/Sources/Infrastructure/SmartRewrite/ManagedMLXLLMRuntime.swift`
- Create: `native/Resources/managed_mlx_llm_worker.py`
- Create: `native/Tests/ManagedMLXRuntimeLocatorCheck.swift`
- Create: `native/Tests/ManagedMLXLLMRuntimeCheck.swift`
- Modify: `native/build_native_app.sh`

**Interfaces:**
- Produces:
  - `enum ManagedMLXRuntimeState: Equatable`
  - `struct ManagedMLXRuntimeLocator`
  - `protocol ManagedLLMRuntime`
  - `final class ManagedMLXLLMRuntime: ManagedLLMRuntime`

- [x] **Step 1: Write RED runtime-locator tests**

Inject a temporary root and module verifier. Cover missing runtime, missing executable, failed module verification, and `.ready(pythonURL)`. The default resolver must receive `AppPaths.runtimes`, then test `mlx-llm/v1` followed by the compatible `mlx-asr/v1`; no absolute user path may exist in the source.

- [x] **Step 2: Write a deterministic fake worker and RED lifecycle tests**

The check creates a temporary executable Python worker supporting `warmup`, `rewrite`, `translate`, `sleep`, and `crash`. Assert:

- one process handles warmup plus three calls;
- matching request IDs are required;
- `sleep` times out and terminates only the owned process;
- cancellation returns cancellation, not failure;
- one crash restarts once;
- a second consecutive crash returns a stable error;
- `stop()` leaves no child process.

- [x] **Step 3: Run RED**

Expected: missing locator/runtime types.

- [x] **Step 4: Implement runtime locator**

`verifyModules` must execute the resolved interpreter with:

```python
import importlib.metadata
required = {"mlx-lm": "0.30.5", "transformers": "5.0.0rc3"}
for package, version in required.items():
    assert importlib.metadata.version(package) == version
```

Return user-readable structural errors without interpreter output.

- [x] **Step 5: Implement `ManagedMLXLLMRuntime`**

Use one serial queue and an owned `Process`. Set:

```swift
process.executableURL = pythonURL
process.arguments = [workerURL.path]
process.environment = ProcessInfo.processInfo.environment.merging([
    "HF_HUB_OFFLINE": "1",
    "TRANSFORMERS_OFFLINE": "1",
    "HF_DATASETS_OFFLINE": "1",
    "TOKENIZERS_PARALLELISM": "false",
]) { _, new in new }
```

Bound each response to 1 MiB, use `poll`, reject mismatched IDs, drain stderr without retaining content, and stop with TERM then KILL only the owned PID. Do not invoke a shell or Terminal.

- [x] **Step 6: Implement the product worker**

Port behavior, not file contents, from the admission worker:

- `local_files_only=True`, `trust_remote_code=False`;
- `reasoning_effort="low"`;
- deterministic generation;
- token-channel collection;
- decode only the unique final channel;
- JSONL stdout only;
- metrics without prompts or raw text;
- SIGTERM exits cleanly.

The worker must not import the probe package at runtime.

- [x] **Step 7: Package and test**

`native/build_native_app.sh` already copies `native/Resources`; add a pre-build existence check:

```zsh
[[ -f "$ROOT/native/Resources/managed_mlx_llm_worker.py" ]] || {
  echo "Missing managed MLX LLM worker" >&2
  exit 1
}
```

Run locator/runtime checks and:

```bash
"$HOME/Library/Application Support/TypeWhale Pro/Runtimes/mlx-asr/v1/python/bin/python3.10" -m py_compile native/Resources/managed_mlx_llm_worker.py
```

Expected: all checks exit 0 and no `__pycache__` remains in the repository.

- [x] **Step 8: Commit Task 4**

```bash
git add native/Sources/Infrastructure/SmartRewrite/ManagedMLXRuntimeLocator.swift native/Sources/Infrastructure/SmartRewrite/ManagedMLXLLMRuntime.swift native/Resources/managed_mlx_llm_worker.py native/Tests/ManagedMLXRuntimeLocatorCheck.swift native/Tests/ManagedMLXLLMRuntimeCheck.swift native/build_native_app.sh
git commit -m "feat: add managed MLX LLM runtime"
```

---

### Task 5: Route real rewrite and translation through the managed engine

**Files:**
- Create: `native/Sources/Infrastructure/SmartRewrite/TypeWhaleLocalLLMEngine.swift`
- Create: `native/Tests/TypeWhaleLocalLLMEngineCheck.swift`
- Modify: `native/Sources/Infrastructure/SmartRewrite/SelectedSmartAITextEngine.swift`
- Modify: `native/Tests/SelectedSmartAITextEngineCheck.swift`

**Interfaces:**
- Produces:
  - `final class TypeWhaleLocalLLMEngine: SmartAITextEngine`
  - `SelectedSmartAITextEngine` routing for `SmartAIEngineSelection.managed`

- [x] **Step 1: Write RED engine tests**

Use a fake `ManagedLLMRuntime`. Assert rewrite calls `SmartRewritePromptBuilder`, translation calls `SmartTranslationPromptBuilder`, `displayName == "GPT-OSS 20B（实验）"`, `logName == "managed_mlx"`, and `usesLocalCostGuard == false`.

Return `"我们再回顾一下下这个问题。"` from the fake and assert the engine returns it without claiming sanitizer quality that the model did not achieve.

Assert a runtime failure is thrown upward so the existing `SmartInputRouter` performs its original-text fallback.

- [x] **Step 2: Extend routing RED test**

Construct `SelectedSmartAITextEngine` with a managed probe factory and `.managed(.gptOSS20BMXFP4Q8)` selection. Assert rewrite and translation each reach that probe exactly once. Assert `.standard(.ollamaQwen2BMLX)` and `.standard(.deepSeekV4Flash)` routing remains unchanged.

- [x] **Step 3: Run RED**

Expected: missing managed selection route and engine.

- [x] **Step 4: Implement the engine and route**

`TypeWhaleLocalLLMEngine` receives a runtime, model directory closure, and timeout profile. It must use the same existing prompt builders/system boundaries as Ollama and return `SmartRewriteEngineOutput`/`SmartTranslationOutput` with no usage cost.

Change `SelectedSmartAITextEngine`’s provider closure to return `SmartAIEngineSelection`. Its default closure returns `.managed(selection.selectedModel)` only when `ManagedLLMSelectionStore.shared.load().isEnabled`; otherwise it returns `.standard(SmartAIModelStore.load())`. `engine(for:)` routes `.standard` through the existing Ollama/DeepSeek switch and `.managed(.gptOSS20BMXFP4Q8)` to the managed factory.

- [x] **Step 5: Run GREEN and router regression**

Run:

- `TypeWhaleLocalLLMEngineCheck`
- `SelectedSmartAITextEngineCheck`
- `SmartInputCheck`
- `SmartTranslationCheck`
- `SmartRewriteSystemPromptBoundaryCheck.sh`
- `TranslationRefusalGuardCheck.sh`

Expected: all pass with zero failures.

- [x] **Step 6: Commit Task 5**

```bash
git add native/Sources/Infrastructure/SmartRewrite/SelectedSmartAITextEngine.swift native/Sources/Infrastructure/SmartRewrite/TypeWhaleLocalLLMEngine.swift native/Tests/TypeWhaleLocalLLMEngineCheck.swift native/Tests/SelectedSmartAITextEngineCheck.swift
git commit -m "feat: route GPT-OSS through managed MLX"
```

---

### Task 6: Add production download management and development clone bootstrap

**Files:**
- Create: `native/Sources/Infrastructure/SmartRewrite/ManagedLLMDownloadManager.swift`
- Create: `native/Tests/ManagedLLMDownloadManagerCheck.swift`
- Create: `tools/local-llm-eval/bootstrap_managed_gpt_oss.py`
- Create: `tools/local-llm-eval/test_bootstrap_managed_gpt_oss.py`

**Interfaces:**
- Produces:
  - `enum ManagedLLMInstallState: Equatable`
  - `@MainActor final class ManagedLLMDownloadManager`
  - CLI `bootstrap_managed_gpt_oss.py --source <dir> --destination <dir>`

- [x] **Step 1: Write RED downloader state-machine tests**

Inject URL loading and file operations. Assert:

- install starts only by explicit call;
- progress is aggregate artifact bytes;
- cancel calls `cancel()` and emits `.missing` or resumable `.failed`;
- HTTP non-2xx fails;
- wrong size/hash never promotes staging;
- successful complete verification atomically moves staging to destination;
- deleting removes only the injected destination.

- [x] **Step 2: Write RED bootstrap tests**

Use tiny fixture artifacts and an injectable descriptor. Assert the tool:

- rejects missing/incorrect source;
- creates the destination through a staging directory;
- refuses an existing ready destination unless `--replace` is explicit;
- never modifies source metadata;
- prints only `status`, model ID, bytes, and elapsed time;
- output does not contain the source path.

- [x] **Step 3: Run RED**

Expected: missing downloader/bootstrap implementation.

- [x] **Step 4: Implement downloader**

Use background `URLSessionDownloadTask`, revision-pinned artifact URLs, per-artifact resume data where available, a 15 GB free-space gate, SHA-256 validation, `.installing-<model-id>` staging, `.backup-<model-id>` rollback, and atomic directory rename.

- [x] **Step 5: Implement clone bootstrap**

Use `subprocess.run(["cp", "-cR", source + "/.", staging], check=True)` with explicit resolved arguments, never a shell. Validate before and after, atomically promote, and remove only tool-created staging on failure.

- [x] **Step 6: Run GREEN**

Run:

```bash
/usr/bin/python3 -m unittest tools/local-llm-eval/test_bootstrap_managed_gpt_oss.py -v
```

Compile/run `ManagedLLMDownloadManagerCheck`.

Expected: all checks pass.

- [x] **Step 7: Perform the development bootstrap**

Resolve the managed destination from `AppPaths.models`:

```text
$HOME/Library/Application Support/TypeWhale Pro/Models/LLM/gpt-oss-20b-mxfp4-q8
```

Run the bootstrap with the existing identical source path only after a fresh concurrency check. Record pre/post source metadata and verify it is unchanged. Do not commit the 11 GB model.

- [x] **Step 8: Commit Task 6**

```bash
git add native/Sources/Infrastructure/SmartRewrite/ManagedLLMDownloadManager.swift native/Tests/ManagedLLMDownloadManagerCheck.swift tools/local-llm-eval/bootstrap_managed_gpt_oss.py tools/local-llm-eval/test_bootstrap_managed_gpt_oss.py
git commit -m "feat: manage GPT-OSS installation"
```

---

### Task 7: Build the independent Models-tab section and switch interaction

**Files:**
- Create: `native/Sources/Presentation/Main/ManagedLLMModelPanel.swift`
- Create: `native/Tests/ManagedLLMModelPanelBoundaryCheck.sh`
- Modify: `native/Sources/Presentation/Main/MainViewController.swift`
- Modify: `native/Sources/Presentation/Main/MainViewController+Configuration.swift`
- Modify: `native/Sources/Presentation/Main/MainViewController+Actions.swift`
- Modify: `native/Sources/Presentation/Main/MainViewController+PanelLayout.swift`
- Modify: `native/Tests/MainWindowLayoutBoundaryCheck.sh`

**Interfaces:**
- Produces:
  - `final class ManagedLLMModelPanel: NSView`
  - callbacks `onInstall`, `onCancelInstall`, `onDelete`, `onEnableChanged`, `onTest`, `onRetry`
  - `func render(_ viewState: ManagedLLMPanelViewState)`

- [x] **Step 1: Write RED UI boundary checks**

The shell check must require:

```text
inspectorGroup("本地直驱模型（实验）", buildManagedLLMModelContent())
setAccessibilityLabel("本地直驱模型")
setAccessibilityLabel("启用 GPT-OSS")
setAccessibilityLabel("测试 GPT-OSS")
```

It must also reject `LM Studio`, `.lmstudio`, and `Terminal` from product source files under the new managed-LLM feature.

- [x] **Step 2: Run RED**

Run:

```bash
native/Tests/ManagedLLMModelPanelBoundaryCheck.sh
```

Expected: fail because the section does not exist.

- [x] **Step 3: Implement focused panel**

Build one card using existing system font and `UITheme`, with:

- model popup;
- experimental badge and quality note;
- state dot/label;
- installed size and managed directory;
- progress indicator;
- download/cancel/delete;
- enable switch;
- test/retry;
- metric labels for load, TTFT, total, token/s, peak memory;
- error label with wrapping.

No custom font or unrelated inspector refactor.

- [x] **Step 4: Wire mutual exclusion**

When enable succeeds:

```swift
smartAIModelMode.isEnabled = false
modelTabSmartAIModelMode.isEnabled = false
```

When disabled or unavailable, restore both. Persist the existing selection as `returnModel`; leave `SmartAIModelStore` unchanged while GPT-OSS is active and write only `ManagedLLMSelectionStore` after model/runtime validation succeeds.

- [x] **Step 5: Run GREEN and layout regressions**

Run:

```bash
native/Tests/ManagedLLMModelPanelBoundaryCheck.sh
native/Tests/MainWindowLayoutBoundaryCheck.sh
native/Tests/InspectorModelTabLayoutCheck.sh
```

Expected: all pass.

- [x] **Step 6: Commit Task 7**

```bash
git add native/Sources/Presentation/Main/ManagedLLMModelPanel.swift native/Sources/Presentation/Main/MainViewController.swift native/Sources/Presentation/Main/MainViewController+Configuration.swift native/Sources/Presentation/Main/MainViewController+Actions.swift native/Sources/Presentation/Main/MainViewController+PanelLayout.swift native/Tests/ManagedLLMModelPanelBoundaryCheck.sh native/Tests/MainWindowLayoutBoundaryCheck.sh
git commit -m "feat: add managed LLM model panel"
```

---

### Task 8: Integrate lifecycle, prewarm, cancellation, memory safety, and App shutdown

**Files:**
- Create: `native/Tests/ManagedLLMLifecycleBoundaryCheck.sh`
- Modify: `native/Sources/Application/SpeechInputCoordinator.swift`
- Modify: `native/TypeSpeakerApp.swift`

**Interfaces:**
- Consumes: `ManagedMLXLLMRuntime`, `ManagedLLMSelectionStore`, `ManagedLLMModelRegistry`.
- Produces:
  - `prewarmManagedLLMIfNeeded(reason:)`
  - `stopManagedLLM(reason:)`
  - installed-App lifecycle ownership.

- [x] **Step 1: Write RED lifecycle boundary checks**

Require:

- prewarm only when enabled and registry/runtime are ready;
- no warmup on the main actor synchronously;
- cancellation is called from the same final-input cancellation path used by existing rewrite;
- sleep/power-off/app termination stop owned helper;
- memory release guard checks no active recording/session/rewrite/translation;
- no idle timer symbol.

- [x] **Step 2: Run RED**

Run:

```bash
native/Tests/ManagedLLMLifecycleBoundaryCheck.sh
```

Expected: fail because integration is absent.

- [x] **Step 3: Wire one shared runtime**

Construct one runtime for `SelectedSmartAITextEngine`, the UI test action, and lifecycle management. Do not create a new helper per request or per view refresh.

Prewarm after launch only when selection is enabled and both model/runtime validate. Prewarm after successful enable. Stop after disable/delete/sleep/power-off/app termination.

- [x] **Step 4: Wire memory safety**

Reuse the existing high-memory/idle gate. Managed LLM release may occur only when:

```swift
activeSession == nil &&
!recorder.isRecording &&
!isFinalRewriteInFlight &&
!isTranslationInFlight
```

If still enabled after a high-memory flush, schedule a new background warmup. Do not add an idle timer.

- [x] **Step 5: Run GREEN and application regressions**

Run:

- `ManagedLLMLifecycleBoundaryCheck.sh`
- `SpeechInputCoordinatorBoundaryCheck.sh`
- `AudioRecorderFinalizationBoundaryCheck.sh`
- `SmartInputCheck`
- full Swift typecheck/build command from `native/build_native_app.sh` without installation if a fast preflight is needed.

Expected: all pass.

- [x] **Step 6: Commit Task 8**

```bash
git add native/Sources/Application/SpeechInputCoordinator.swift native/TypeSpeakerApp.swift native/Tests/ManagedLLMLifecycleBoundaryCheck.sh
git commit -m "feat: manage local LLM lifecycle"
```

---

### Task 9: Documentation, full verification, build, install, and real-App QA

**Files:**
- Modify: `docs/ARCHITECTURE.md`
- Modify: `docs/开发日志.md`
- Modify: `native/Sources/Presentation/VersionHistory/VersionHistoryViewController.swift`
- Modify: `docs/superpowers/plans/2026-07-24-managed-gpt-oss-app-integration.md`

**Interfaces:**
- Produces: installed, signed TypeWhale Pro build and durable verification record.

- [x] **Step 1: Update narrative documentation before build**

Document:

- managed model ownership and immutable revision;
- JSONL helper/final-only boundary;
- opt-in mutual switching;
- no idle unload and high-memory reload;
- Qwen3.6 35B Rewrite Ollama option;
- GPT-OSS experimental quality caveat;
- tests performed and known cold-cache limitation.

Add the forthcoming build number to `VersionHistoryViewController` before invoking the build.

- [x] **Step 2: Run the complete automated suite**

Run every new check plus:

```bash
/usr/bin/python3 -m unittest discover -s tools/local-llm-eval -p 'test_*.py' -v
native/Tests/SmartRewriteSystemPromptBoundaryCheck.sh
native/Tests/TranslationRefusalGuardCheck.sh
native/Tests/MainWindowLayoutBoundaryCheck.sh
native/Tests/InspectorModelTabLayoutCheck.sh
native/Tests/SpeechInputCoordinatorBoundaryCheck.sh
git diff --check
```

Compile/run all modified Swift executable checks. Expected: zero failures.

- [x] **Step 3: Re-run concurrency and version guards**

Check:

```bash
git branch --show-current
git status --short
pgrep -af 'build_and_log\.sh|release_local_build\.sh|build_native_app\.sh|swiftc|xcodebuild'
```

Read current short version/build and relevant mtimes. Stop if another session overlaps.

- [x] **Step 4: Build and install**

Run:

```bash
./native/build_and_log.sh
```

Expected:

- build number increments exactly once;
- `/Applications/TypeWhale Pro.app` is replaced and opened;
- code signature verifies;
- build log is appended;
- no source mutation race.

- [x] **Step 5: Perform installed-App functional QA**

In `/Applications/TypeWhale Pro.app`:

1. Open Models tab.
2. Verify separate `本地直驱模型（实验）` group.
3. Verify `本地 Qwen3.6 35B Rewrite` in the existing selector.
4. Select Rewrite and run a real dictation rewrite.
5. Enable GPT-OSS; verify normal selector disables and no Terminal appears.
6. Run built-in synthetic test and record load/TTFT/total/token/s/RSS.
7. Run real polish, development requirement, no-answer, short instruction, zh→en, and en→zh cases.
8. Cancel during generation; verify no late paste and next request works.
9. Terminate the owned helper; verify one recovery.
10. Force repeated failure; verify original-text fallback and no provider switch.
11. Restart App; verify persisted install/selection and safe warmup.
12. Disable GPT-OSS; verify previous model returns.

- [x] **Step 6: Perform UI/design review**

Use the `design-review` skill on the installed App. Capture the Models tab and inspect hierarchy, spacing, truncation, disabled state, progress, errors, metrics, and accessibility. Fix issues through a new RED/GREEN loop, rebuild if code changes, and repeat review.

- [x] **Step 7: Final privacy/process/source checks**

Verify:

- no managed helper remains after disable/quit;
- no clone staging remains;
- source metadata from the development bootstrap is unchanged;
- logs do not contain prompts, user test text, analysis, raw tokens, or external source path;
- `rg -n 'LM Studio|\\.lmstudio' native/Sources native/Resources` returns no managed feature dependency.

- [x] **Step 8: Mark plan complete and commit release build**

Review `git status --short`, separate protected concurrent files, stage only owned implementation/version/docs/build-log files, and commit:

```bash
git commit -m "feat: integrate managed GPT-OSS local model"
```

Record the final commit, version/build, automated test count, installed-App observations, performance, and remaining model-quality caveat.

Completion note: Build 818 passed installed-App model-panel, mutual-switching, built-in real-model, full-exit, restart, signature, and design review. Physical Fn dictation/paste timing remains a user hand-test because desktop automation cannot synthesize the hardware Fn workflow; the same rewrite, translation, no-answer, short-instruction, cancellation, crash-recovery, failure-fallback, and no-provider-switch contracts passed isolated real-model and executable checks.
