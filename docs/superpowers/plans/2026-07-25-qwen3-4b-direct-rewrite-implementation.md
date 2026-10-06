# Qwen3 4B Direct Rewrite Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Qwen3-4B-Instruct-2507 4bit selectable from TypeWhale’s existing rewrite-model menus and run it through the App-owned MLX worker while removing GPT-OSS from the product.

**Architecture:** Add Qwen as a first-class `SmartAIModel` whose provider routes to the existing managed MLX runtime. Replace GPT-OSS-specific catalog and Harmony output handling with a pinned Qwen descriptor and standard generated-token decoding, then remove the separate managed-model switch UI.

**Tech Stack:** Swift/AppKit, Python 3.10, MLX/`mlx_lm`, JSON-lines worker protocol, CryptoKit, shell boundary checks.

## Global Constraints

- Qwen repository revision is exactly `50d427756c6b1b2fe0c0a10f67fbda1fc8e82c1b`.
- The model directory is exactly `qwen3-4b-instruct-2507-4bit` below TypeWhale’s managed LLM root.
- The App must not depend on Ollama, LM Studio, or a visible terminal for this model.
- Qwen failures preserve source text and never silently route to a cloud model.
- Screenshot translation, ASR, VAD, hotwords, and capsule concepts remain unchanged.
- No LLM weights are bundled into the App or DMG.
- Existing unrelated untracked files must not be staged or modified.

---

## File map

- `native/Sources/Core/SmartInput/SmartAIModel.swift`: unified model identity, provider, menu and persistence behavior.
- `native/Sources/Core/SmartInput/ManagedLLMSelection.swift`: legacy GPT-OSS setting migration only; no active selection authority.
- `native/Sources/Infrastructure/SmartRewrite/ManagedLLMModelCatalog.swift`: pinned Qwen artifact manifest and readiness.
- `native/Sources/Infrastructure/SmartRewrite/SelectedSmartAITextEngine.swift`: provider-based routing to managed MLX.
- `native/Sources/Infrastructure/SmartRewrite/TypeWhaleLocalLLMEngine.swift`: Qwen display/profile and readiness-backed engine construction.
- `native/Resources/managed_mlx_llm_worker.py`: standard Qwen prompt and generated-token decoding.
- `native/Sources/Presentation/Main/*`: unified menu state, removal of GPT-OSS panel and switch actions.
- `native/Tests/*`: red/green coverage for identity, migration, catalog, routing, worker and UI boundaries.
- `docs/ARCHITECTURE.md`, `docs/开发日志.md`, `native/Sources/Presentation/VersionHistory/VersionHistoryViewController.swift`: durable product and release records.

### Task 1: Unify Qwen model identity and retire GPT-OSS selection authority

**Files:**
- Modify: `native/Sources/Core/SmartInput/SmartAIModel.swift`
- Modify: `native/Sources/Core/SmartInput/ManagedLLMSelection.swift`
- Modify: `native/Tests/SmartAIModelCheck.swift`
- Modify: `native/Tests/ManagedLLMSelectionCheck.swift`

**Interfaces:**
- Produces: `SmartAIProvider.typeWhaleMLX`
- Produces: `SmartAIModel.typeWhaleQwen3_4BInstruct`
- Produces: `ManagedLLMModelID.qwen3_4BInstruct2507_4bit`
- Produces: `ManagedLLMSelectionStore.retireLegacySelection()`

- [ ] **Step 1: Write failing identity and migration checks**

Add assertions equivalent to:

```swift
precondition(SmartAIModel.typeWhaleQwen3_4BInstruct.provider == .typeWhaleMLX)
precondition(SmartAIModel.typeWhaleQwen3_4BInstruct.displayName == "本地直驱 Qwen3 4B Instruct")
precondition(
    SmartAIModel.fromStoredRawValue("typewhale-qwen3-4b-instruct-2507-4bit")
        == .typeWhaleQwen3_4BInstruct
)
store.save(.init(selectedModel: .qwen3_4BInstruct2507_4bit, isEnabled: true, returnModel: .deepSeekV4Flash))
store.retireLegacySelection()
precondition(store.load().isEnabled == false)
```

- [ ] **Step 2: Run checks and confirm RED**

Run:

```bash
xcrun swiftc native/Sources/Core/SmartInput/SmartAIModel.swift native/Tests/SmartAIModelCheck.swift -o /tmp/SmartAIModelCheck && /tmp/SmartAIModelCheck
xcrun swiftc native/Sources/Core/SmartInput/SmartAIModel.swift native/Sources/Core/SmartInput/ManagedLLMSelection.swift native/Tests/ManagedLLMSelectionCheck.swift -o /tmp/ManagedLLMSelectionCheck && /tmp/ManagedLLMSelectionCheck
```

Expected: compile failure because the Qwen provider/model/ID and retirement method do not exist.

- [ ] **Step 3: Implement minimal domain changes**

Add the provider and model cases, include Qwen in `allCases`, and keep stable raw values. Make `retireLegacySelection()` write a disabled selection without changing the user’s standard `SmartAIModelStore` value.

- [ ] **Step 4: Run both checks and confirm GREEN**

Expected: both executables print their `passed` markers.

- [ ] **Step 5: Commit Task 1**

Stage only the four listed files and commit `feat: add Qwen3 4B rewrite model identity`.

### Task 2: Replace the GPT-OSS manifest with the pinned Qwen catalog

**Files:**
- Modify: `native/Sources/Infrastructure/SmartRewrite/ManagedLLMModelCatalog.swift`
- Modify: `native/Sources/Infrastructure/SmartRewrite/ManagedLLMDownloadManager.swift`
- Modify: `native/Tests/ManagedLLMModelCatalogCheck.swift`
- Modify: `native/Tests/ManagedLLMDownloadManagerCheck.swift`

**Interfaces:**
- Consumes: `ManagedLLMModelID.qwen3_4BInstruct2507_4bit`
- Produces: `ManagedLLMModelCatalog.qwen3_4BInstruct2507_4bit`

- [ ] **Step 1: Write failing production-manifest checks**

Require revision, directory, artifact count, weight SHA and total bytes:

```swift
let production = ManagedLLMModelCatalog.qwen3_4BInstruct2507_4bit
precondition(production.revision == "50d427756c6b1b2fe0c0a10f67fbda1fc8e82c1b")
precondition(production.directoryName == "qwen3-4b-instruct-2507-4bit")
precondition(production.artifacts.count == 13)
precondition(
    production.artifacts.first { $0.name == "model.safetensors" }?.sha256
        == "2a73c6c248601ab904e035548abd8e6abb65ea27dcb5f342fb0a8910eb44173f"
)
```

- [ ] **Step 2: Run catalog/download checks and confirm RED**

Compile using the same source lists recorded in the existing checks. Expected: missing Qwen descriptor.

- [ ] **Step 3: Add the exact 13-artifact manifest**

Use the verified local values:

```text
.gitattributes 1570 34448b82c17d60fec9b65b1f093c115ddbaadc04beb1b0140b6bfed2e012a930
README.md 969 7b17ce562d7ea121c86d2ffdf660eed3726ac5b52cacfa9f1de11a65969f5657
added_tokens.json 707 c0284b582e14987fbd3d5a2cb2bd139084371ed9acbae488829a1c900833c680
chat_template.jinja 4040 40c21f34cf67d8c760ef72f8ad3ae5afad514299d4b06e91dd9a8d705af7b541
config.json 938 574349e5a343236546fda55e4744a76e181f534182d7dc60ff1bad7e7a502849
generation_config.json 238 835fffe355c9438e7a25be099b3fccaa98350b83451f9fd2d99512e74f1ade48
merges.txt 1671853 8831e4f1a044471340f7c0a83d7bd71306a5b867e95fd870f74d0c5308a904d5
model.safetensors 2263022417 2a73c6c248601ab904e035548abd8e6abb65ea27dcb5f342fb0a8910eb44173f
model.safetensors.index.json 63964 388d811b8b7c2608dd04cce1bcb04a8bf715d19b42790894e6d3427ff429a777
special_tokens_map.json 613 76862e765266b85aa9459767e33cbaf13970f327a0e88d1c65846c2ddd3a1ecd
tokenizer.json 11422654 aeb13307a71acd8fe81861d94ad54ab689df773318809eed3cbe794b4492dae4
tokenizer_config.json 5440 4397cc477eb6d79715ccd2000accd6b3531928f30029665832fa1b255f24d2b9
vocab.json 2776833 ca10d7e9fb3ed18575dd1e277a2579c16d108e32f27439684afa0e10b1440910
```

Point the descriptor to `https://huggingface.co/mlx-community/Qwen3-4B-Instruct-2507-4bit/resolve` and make the download manager default to Qwen.

- [ ] **Step 4: Run checks and verify GREEN**

Expected: catalog and download-manager checks print `passed`.

- [ ] **Step 5: Commit Task 2**

Commit `feat: manage pinned Qwen3 4B artifacts`.

### Task 3: Convert the worker from Harmony parsing to Qwen final-text decoding

**Files:**
- Create: `native/Tests/test_managed_mlx_llm_worker.py`
- Modify: `native/Resources/managed_mlx_llm_worker.py`
- Delete: `native/Sources/Infrastructure/SmartRewrite/HarmonyFinalOutputParser.swift`
- Delete: `native/Tests/HarmonyFinalOutputParserCheck.swift`
- Modify: `native/Tests/ManagedLLMModelPanelBoundaryCheck.sh`

**Interfaces:**
- Consumes: existing JSON request fields.
- Produces: `decode_generated_text(tokenizer, prompt_token_count, generated_tokens) -> str`
- Produces: unchanged JSON `final_text` response field.

- [ ] **Step 1: Write failing Python worker tests**

Import the worker module and assert:

```python
def test_decode_generated_text_excludes_prompt_and_special_tokens():
    tokenizer = FakeTokenizer(decoded="  整理后的正文  ")
    assert worker.decode_generated_text(tokenizer, [10, 11, 12]) == "整理后的正文"

def test_decode_generated_text_rejects_empty_output():
    tokenizer = FakeTokenizer(decoded="  ")
    with pytest.raises(worker.WorkerRequestError, match="empty_final_text"):
        worker.decode_generated_text(tokenizer, [10])
```

Also assert the source no longer contains `HarmonyTokenIDs`, `reasoning_effort=`, or `extract_harmony_final`.

- [ ] **Step 2: Run tests and confirm RED**

Run:

```bash
python3 -m unittest native/Tests/test_managed_mlx_llm_worker.py
```

Expected: missing `decode_generated_text` or Harmony-specific source assertion failure.

- [ ] **Step 3: Implement standard Qwen generation**

Load with `mlx_lm.load(model_directory, lazy=False)`, call `apply_chat_template(..., add_generation_prompt=True, tokenize=False)`, stream tokens, collect only generated token IDs, then decode with `skip_special_tokens=True`. Keep metrics, cancellation, one-model cache, local-directory enforcement and JSON protocol unchanged.

- [ ] **Step 4: Run Python and protocol regressions**

Expected: worker unit tests and `ManagedMLXLLMProtocolCheck` pass; the shell boundary check reports no GPT-OSS/Harmony UI or worker dependency.

- [ ] **Step 5: Commit Task 3**

Commit `refactor: adapt managed MLX worker for Qwen3`.

### Task 4: Route unified model selection to the Qwen runtime

**Files:**
- Modify: `native/Sources/Infrastructure/SmartRewrite/SelectedSmartAITextEngine.swift`
- Modify: `native/Sources/Infrastructure/SmartRewrite/TypeWhaleLocalLLMEngine.swift`
- Modify: `native/Tests/SelectedSmartAITextEngineCheck.swift`
- Modify: `native/Tests/TypeWhaleLocalLLMEngineCheck.swift`

**Interfaces:**
- Consumes: `SmartAIModel.typeWhaleQwen3_4BInstruct`
- Consumes: `ManagedLLMModelID.qwen3_4BInstruct2507_4bit`
- Produces: provider-based Qwen route without `ManagedLLMSelectionStore` as selection authority.

- [ ] **Step 1: Write failing routing checks**

Assert the selection provider returns only `SmartAIModel`, Qwen calls the managed factory exactly once, and Ollama/DeepSeek routes remain unchanged. Assert Qwen display name, request directory and non-thinking request profile.

- [ ] **Step 2: Run both engine checks and confirm RED**

Expected: exhaustiveness or missing Qwen-route failure.

- [ ] **Step 3: Implement minimal route**

Change `SelectedSmartAITextEngine` to read `SmartAIModelStore.load()`. Route `.typeWhaleMLX` to the managed Qwen engine; delete active use of `.managed(ManagedLLMModelID)` selection. In the local engine, use the Qwen descriptor display name and retain the existing safety prompts and fallback semantics.

- [ ] **Step 4: Run both engine checks and confirm GREEN**

Expected: Qwen, all Ollama options and DeepSeek pass routing checks.

- [ ] **Step 5: Commit Task 4**

Commit `feat: route Qwen3 4B through managed MLX`.

### Task 5: Replace the GPT-OSS panel with unified-menu readiness behavior

**Files:**
- Modify: `native/Sources/Presentation/Main/MainViewController.swift`
- Modify: `native/Sources/Presentation/Main/MainViewController+Configuration.swift`
- Modify: `native/Sources/Presentation/Main/MainViewController+PanelLayout.swift`
- Modify: `native/Sources/Presentation/Main/MainViewController+Actions.swift`
- Modify: `native/Sources/Presentation/Main/MainViewController+Lifecycle.swift`
- Delete: `native/Sources/Presentation/Main/ManagedLLMModelPanel.swift`
- Modify: `native/Tests/ManagedLLMModelPanelBoundaryCheck.sh`
- Modify: `native/Tests/InspectorModelTabLayoutCheck.sh`

**Interfaces:**
- Consumes: Qwen model/provider and registry readiness.
- Produces: one synchronized model selection in both existing popup menus.

- [ ] **Step 1: Make UI boundary tests fail**

Require Qwen menu construction via `SmartAIModel.allCases`, forbid `ManagedLLMModelPanel`, `测试 GPT-OSS`, `启用 GPT-OSS`, and any code that disables both model popups because a managed switch is enabled.

- [ ] **Step 2: Run boundary checks and confirm RED**

Expected: GPT-OSS panel and disabling logic are still present.

- [ ] **Step 3: Implement unified selection gate**

Before saving Qwen, verify catalog readiness and runtime state. On failure, restore the previous model in both menus and set actionable status text. On success, save Qwen, stop any existing managed worker before model change, and issue a detached bounded warm-up. Remove the GPT-OSS panel properties, layout, actions and lifecycle rendering.

- [ ] **Step 4: Run boundary checks and build-level compile check**

Expected: shell checks pass and `./native/build_native_app.sh` compiles without GPT-OSS panel references.

- [ ] **Step 5: Commit Task 5**

Commit `feat: expose Qwen3 4B in rewrite model menus`.

### Task 6: Documentation, full verification, install and visual review

**Files:**
- Modify: `docs/ARCHITECTURE.md`
- Modify: `docs/开发日志.md`
- Modify: `native/Sources/Presentation/VersionHistory/VersionHistoryViewController.swift`
- Modify: build/version files changed by `native/build_and_log.sh`
- Modify: `docs/构建日志.md`

**Interfaces:**
- Produces: installed `/Applications/TypeWhale Pro.app` with a unique incremented build number.

- [ ] **Step 1: Update durable records before build**

Record unified selection, Qwen revision, no-external-app architecture, GPT-OSS retirement, fallback boundaries and exact automated/manual validation.

- [ ] **Step 2: Run the complete relevant automated suite**

Run all modified Swift checks, Python worker tests, shell boundary checks and `git diff --check`. Expected: every command exits zero.

- [ ] **Step 3: Re-run concurrency safety check**

Verify branch, status, build processes, relevant mtimes and exact file ownership. Stop if overlapping writes appear.

- [ ] **Step 4: Build, bump build number, install and open**

Run:

```bash
./native/build_and_log.sh
```

Expected: unique build number, successful compile, install to `/Applications/TypeWhale Pro.app`, launch, signature validation and build-log append.

- [ ] **Step 5: Perform real Qwen smoke test**

Select Qwen in the installed App, confirm the duplicate menu syncs, run “我们回顾一下这个问题。”, verify non-empty final text with no `<think>`, record load/TTFT/total/TPS, run a second warm request, then switch away and verify the worker exits.

- [ ] **Step 6: Run design review**

Use the `design-review` skill against the installed App. Check menu width, label truncation, state feedback, failed-selection recovery, no visual remnants of GPT-OSS, and both Smart/Model tabs.

- [ ] **Step 7: Final scope audit and commit**

Review `git status --short`, separate protected unrelated files, stage only this implementation/build’s files, and commit `feat: replace GPT-OSS with Qwen3 4B direct rewrite`.
