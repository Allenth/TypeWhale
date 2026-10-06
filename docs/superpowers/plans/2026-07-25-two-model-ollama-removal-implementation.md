# Two-Model Ollama Removal Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Reduce TypeWhale's active smart-model product to Qwen3 4B local direct drive and DeepSeek v4 flash, migrate legacy selections safely, remove TypeWhale-owned Ollama runtime/UI behavior, and make screenshot translation follow the same selected model.

**Architecture:** `SmartAIModelStore` becomes the only model-selection authority and resolves defaults through an injected Qwen-readiness predicate. Both text and screenshot routers switch exhaustively between the two retained models. The managed Qwen engine gains the screenshot-specific prompt path. Ollama engine, process supervisor, health probe, capsule status and model-page links are retired without touching any user-installed Ollama application or model files.

**Tech Stack:** Swift/AppKit, UserDefaults, MLX JSON-lines worker protocol, shell boundary checks.

## Global Constraints

- Do not invoke Ollama, remove Ollama from the machine, or delete any Ollama-owned files.
- Keep `typewhale-qwen3-4b-instruct-2507-4bit` and `deepseek-v4-flash` as stable persisted raw values.
- If Qwen is ready, a missing or legacy selection resolves to Qwen; otherwise it resolves to DeepSeek and persists that result.
- A valid saved Qwen or DeepSeek selection remains unchanged.
- Qwen failures preserve existing caller fallback behavior and never silently call DeepSeek.
- Screenshot translation must use `ScreenshotTranslationPromptBuilder`, including line markers and layout-preservation instructions.
- DeepSeek key onboarding, the Qwen download UI, hardware eligibility and native Swift/MLX replacement are later phases.
- Preserve unrelated untracked files and historical version-history entries.

## Task 1: Establish the strict two-model domain and migration

**Files:**
- Modify: `native/Sources/Core/SmartInput/SmartAIModel.swift`
- Modify: `native/Sources/Core/SmartInput/ManagedLLMSelection.swift`
- Modify: `native/Tests/SmartAIModelCheck.swift`
- Modify: `native/Tests/ManagedLLMSelectionCheck.swift`

- [x] Replace identity assertions with exactly Qwen3 4B and DeepSeek, and add isolated-defaults migration checks for ready and unavailable Qwen.
- [x] Compile the checks and confirm RED because the store does not accept injectable defaults/readiness and still exposes Ollama cases.
- [x] Implement `SmartAIModelStore(defaults:qwenReadiness:)`, preserve static convenience APIs, persist legacy/unknown fallback, and remove legacy active enum/provider cases.
- [x] Simplify the retired managed-selection default so no Ollama enum case remains.
- [x] Re-run both checks and confirm GREEN.
- [x] Commit only Task 1 files as `refactor: reduce smart model domain to two choices`.

Commands:

```bash
xcrun swiftc native/Sources/Core/SmartInput/SmartAIModel.swift native/Tests/SmartAIModelCheck.swift -o /tmp/SmartAIModelCheck && /tmp/SmartAIModelCheck
xcrun swiftc native/Sources/Core/SmartInput/SmartAIModel.swift native/Sources/Core/SmartInput/ManagedLLMSelection.swift native/Tests/ManagedLLMSelectionCheck.swift -o /tmp/ManagedLLMSelectionCheck && /tmp/ManagedLLMSelectionCheck
```

## Task 2: Remove Ollama routing and add native Qwen screenshot translation

**Files:**
- Modify: `native/Sources/Infrastructure/SmartRewrite/SelectedSmartAITextEngine.swift`
- Modify: `native/Sources/Infrastructure/SmartRewrite/SelectedScreenshotTranslationEngine.swift`
- Modify: `native/Sources/Infrastructure/SmartRewrite/TypeWhaleLocalLLMEngine.swift`
- Modify: `native/Tests/SelectedSmartAITextEngineCheck.swift`
- Modify: `native/Tests/SelectedScreenshotTranslationEngineCheck.swift`
- Modify: `native/Tests/TypeWhaleLocalLLMEngineCheck.swift`

- [x] Rewrite router checks for only DeepSeek and managed Qwen; require the Qwen screenshot engine rather than an Ollama fallback.
- [x] Add a local-engine check that verifies screenshot prompt, screenshot system prompt, line-marker preservation command and output metadata.
- [x] Run the focused checks and confirm RED.
- [x] Remove Ollama factories from both selectors, add a managed screenshot factory, and make `TypeWhaleLocalLLMEngine` conform to `ScreenshotTranslationEngine`.
- [x] Build the local screenshot request with `ScreenshotTranslationPromptBuilder`; sanitize and reject empty output consistently.
- [x] Re-run focused checks and confirm GREEN.
- [x] Commit Task 2 as `feat: unify screenshot translation on selected model`.

## Task 3: Retire TypeWhale-owned Ollama runtime and capsule health behavior

**Files:**
- Delete: `native/Sources/Infrastructure/SmartRewrite/OllamaRewriteEngine.swift`
- Delete: `native/Sources/Infrastructure/SmartRewrite/OllamaServiceSupervisor.swift`
- Delete: `native/Tests/OllamaRewriteEngineCheck.swift`
- Delete: `native/Tests/OllamaServiceSupervisorCheck.swift`
- Delete: `native/Tests/OllamaOwnedProcessLifecycleCheck.sh`
- Modify: `native/Sources/Application/SpeechInputCoordinator.swift`
- Modify: `native/Sources/Presentation/Capsule/PreviewPresenting.swift`
- Modify: `native/Sources/Presentation/Capsule/RecordingPanel.swift`
- Modify: `native/Sources/Presentation/Capsule/MainCapsuleState.swift`
- Modify: `native/Sources/Presentation/MinimalBlackPreview/MinimalBlackPreviewPresenter.swift`
- Modify: `native/Sources/Presentation/Notch/NotchPreviewPresenter.swift`
- Modify: relevant capsule state/render/boundary checks

- [x] Add a source boundary check that rejects active Ollama engine/supervisor/health symbols while excluding historical docs and developer vocabulary.
- [x] Run it and confirm RED.
- [x] Remove Ollama warm-up, health timers/state/probes/toast, preview protocol method and green-health border state.
- [x] Delete production Ollama engine/supervisor and their dedicated tests.
- [x] Update capsule tests to describe only countdown and memory indicators.
- [x] Run source boundary and capsule-focused checks; confirm GREEN.
- [x] Commit Task 3 as `refactor: retire TypeWhale Ollama runtime`.

## Task 4: Remove Ollama product UI and stale product claims

**Files:**
- Modify: `native/Sources/Presentation/Main/ManagedASRModelListView.swift`
- Modify: `native/Sources/Presentation/Main/MainViewController+Configuration.swift`
- Modify: `native/Tests/ManagedLLMModelPanelBoundaryCheck.sh`
- Modify: `native/Tests/TranslationRefusalGuardCheck.sh`
- Modify: active comments in `native/Sources/Core/SmartInput/SmartRewriteSafetyPrompt.swift`

- [x] Extend the UI boundary check to require exactly two menu identities and reject Ollama links, selectors, URLs and tooltip claims.
- [x] Run the boundary checks and confirm RED.
- [x] Collapse the ASR model header to its actual ASR target-directory function; remove old large-model link row.
- [x] Update the smart-model tooltip to state that rewrite, voice translation and screenshot translation share the selected model.
- [x] Remove deleted Ollama file expectations from refusal-guard checks and update active shared-prompt comments.
- [x] Run all changed shell checks and confirm GREEN.
- [x] Commit Task 4 as `refactor: remove Ollama model UI`.

## Task 5: Product verification, visual review, installed build and records

**Files:**
- Modify: `docs/ARCHITECTURE.md`
- Modify: `docs/开发日志.md`
- Modify: `native/Sources/Presentation/VersionHistory/VersionHistoryViewController.swift`
- Automatically modified: `native/build_native_app.sh`
- Automatically modified: `docs/构建日志.md`

- [x] Run all focused Swift/Python/shell tests plus an active-source `rg` audit.
- [x] Update architecture and release records for the two-model boundary and build 824.
- [x] Run `design-review` against the model tab/dropdowns and verify layout behavior in the installed App.
- [x] Re-check branch, dirty scope, build processes and relevant mtimes.
- [x] Run `./native/build_and_log.sh`; confirm build 824, installation, launch and signature verification.
- [x] Verify current-machine migration remains Qwen because the pinned model is ready; exercise both dropdowns and the model page.
- [x] Run final verification commands from a clean evidence window.
- [x] Review `git status --short`, stage only this phase, and commit `release: ship two-model smart AI build 824`.

## Acceptance Criteria

- Both smart-model menus contain only Qwen3 4B local and DeepSeek v4 flash.
- Missing/legacy selection chooses Qwen when ready and DeepSeek otherwise; the resolved raw value is persisted.
- No active TypeWhale code starts, probes, routes to, or advertises Ollama.
- No user Ollama installation/model file is touched.
- Rewrite, voice translation and screenshot OCR translation all follow the selected model.
- Qwen screenshot translation uses the screenshot-specific prompt and preserves line markers.
- Qwen failure does not fall through to DeepSeek.
- Build 824 is uniquely compiled, signed, installed and opened; failed build numbers 822 and 823 are not reused.
