# Remove Semantic Fidelity Guard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove TypeWhale's semantic judgment of smart-rewrite output so every non-empty model result is delivered directly to the user.

**Architecture:** Delete `RewriteFidelityGuard` and its rejection branch at the shared `SmartInputRouter` output boundary. Keep model error, timeout, empty-output, sanitization and no-provider-fallback behavior unchanged. Extend the fixed-audio replay so it asserts the text returned by the production router is the model-generated text.

**Tech Stack:** Swift 5, Foundation, TypeWhale SmartInput pipeline, MLX JSONL workers, shell regression scripts.

## Global Constraints

- Delete all content-level checks for English terms, numbers, constraint words, question signals and character overlap.
- A non-empty model response must be delivered without semantic scoring or automatic replacement by source text.
- Keep model errors, timeout, protocol errors, empty output and output sanitization behavior unchanged.
- Do not change ASR, term normalization, prompts, provider selection, no-provider-fallback policy or paste behavior.
- Do not add a settings switch, warning score or second-model review.
- Preserve unrelated untracked directories and `.artifacts`; never stage them.

---

### Task 1: Make Router Deliver Every Non-Empty Model Result

**Files:**
- Modify: `native/Tests/SmartInputCheck.swift`
- Modify: `native/Sources/Core/SmartInput/SmartInputRouter.swift`
- Delete: `native/Sources/Core/SmartInput/RewriteFidelityGuard.swift`
- Delete: `native/Tests/RewriteFidelityGuardCheck.swift`

**Interfaces:**
- Consumes: `SmartRewriteEngineOutput.text`, already sanitized by the selected engine.
- Produces: `SmartRewriteResult.text == rewritten` for every non-empty model result.
- Preserves: `SmartRewriteResult.didFallback` for empty output, timeout and engine errors only.

- [ ] **Step 1: Change the existing guard regression to require direct delivery**

  Replace the `contaminatedResult` expectations in `SmartInputCheck.swift` with:

  ```swift
  let modelOutput = "我的表达内容没有被准确理解和妥善处理，沟通中还存在曲解。"
  let directDeliveryRouter = SmartInputRouter(
      engine: FixedRewriteEngine(output: modelOutput)
  )
  let directDeliveryResult = await directDeliveryRouter.rewrite(
      rawText: "你说的这个方案让架构师过一遍。",
      preference: .developerRequirement,
      context: codex
  )
  precondition(!directDeliveryResult.didFallback)
  precondition(directDeliveryResult.text == modelOutput)
  ```

  Add the reported equivalent-constraint case:

  ```swift
  let equivalentConstraintOutput = "原文只说响应速度，不得改为影响速度。"
  let equivalentConstraintRouter = SmartInputRouter(
      engine: FixedRewriteEngine(output: equivalentConstraintOutput)
  )
  let equivalentConstraintResult = await equivalentConstraintRouter.rewrite(
      rawText: "原文只说响应速度，就不能改成影响速度。",
      preference: .exhaustiveSummary,
      context: codex
  )
  precondition(!equivalentConstraintResult.didFallback)
  precondition(equivalentConstraintResult.text == equivalentConstraintOutput)
  ```

- [ ] **Step 2: Run the focused test and verify RED**

  Compile and run `SmartInputCheck` with the same SmartInput source set used by the app build. Expected before implementation: the first new assertion fails because the router returns the source text with `didFallback == true`.

- [ ] **Step 3: Remove the semantic rejection branch**

  In `SmartInputRouter.rewrite`, keep:

  ```swift
  let rewritten = output.text.trimmingCharacters(in: .whitespacesAndNewlines)
  ```

  Delete the complete block from `let fidelityStartedAt` through the `SmartRewriteResult` returned for `.reject`. The next code must directly construct:

  ```swift
  return SmartRewriteResult(
      text: rewritten.isEmpty ? (normalizedText.isEmpty ? trimmed : normalizedText) : rewritten,
      rawText: rawText,
      mode: profile.mode,
      didFallback: rewritten.isEmpty,
      modelName: rewritten.isEmpty ? nil : engine.displayName,
      usage: rewritten.isEmpty ? nil : output.usage,
      normalizedText: normalizedText,
      termReplacements: normalization.replacements
  )
  ```

- [ ] **Step 4: Delete the guard implementation and dedicated test**

  Delete:

  ```text
  native/Sources/Core/SmartInput/RewriteFidelityGuard.swift
  native/Tests/RewriteFidelityGuardCheck.swift
  ```

- [ ] **Step 5: Run GREEN and source-boundary checks**

  Run the focused `SmartInputCheck`. Expected: both direct-delivery assertions pass.

  Run:

  ```bash
  ! rg -n 'RewriteFidelityGuard|RewriteFidelityReason|rewrite_fidelity_rejected|智能整理结果偏离原文' native/Sources native/Tests
  git diff --check
  ```

  Expected: both commands exit `0`.

- [ ] **Step 6: Commit the production behavior change**

  ```bash
  git add native/Sources/Core/SmartInput/SmartInputRouter.swift \
    native/Tests/SmartInputCheck.swift
  git add -u native/Sources/Core/SmartInput/RewriteFidelityGuard.swift \
    native/Tests/RewriteFidelityGuardCheck.swift
  git commit -m "fix: deliver smart rewrite output without semantic guard"
  ```

---

### Task 2: Cover Final Router Delivery in Fixed-Audio Replay

**Files:**
- Modify: `native/Tests/SmartRewritePromptReplayCheck.swift`
- Modify: `native/Tests/run_smart_rewrite_prompt_replay.sh`

**Interfaces:**
- Consumes: fixed WAV, production `DeveloperTermNormalizer`, `SmartInputRouter`, `SmartRewritePromptBuilder` and local Qwen3 4B worker.
- Produces: replay measurements whose `text` is the final `SmartRewriteResult.text` returned by the router.
- Failure semantics: replay exits non-zero if the final delivered text differs from the non-empty model response.

- [ ] **Step 1: Add a replay engine adapter**

  Add `ReplayRewriteEngine: SmartRewriteEngine` beside `JSONLineWorker`. Its `rewrite` method must build the production prompt, send it to the existing JSONL worker, store TTFT/completion metrics, and return:

  ```swift
  SmartRewriteEngineOutput(
      text: generatedText,
      usage: nil
  )
  ```

  Expose the latest generated text and metrics for the report:

  ```swift
  private(set) var lastGeneratedText = ""
  private(set) var lastTTFTMilliseconds = 0.0
  private(set) var lastCompletionMilliseconds = 0.0
  ```

- [ ] **Step 2: Route both replay modes through `SmartInputRouter`**

  Replace direct calls to the replay helper with:

  ```swift
  let engine = ReplayRewriteEngine(worker: llmWorker, modelDirectory: llmModelURL)
  let router = SmartInputRouter(engine: engine)
  let result = await router.rewrite(
      rawText: asrText,
      preference: preference,
      context: context
  )
  precondition(result.text == engine.lastGeneratedText)
  ```

  Construct each `RewriteMeasurement` from `result.text`, and add `delivery_not_model_output` to `failedChecks` instead of trapping when the values differ.

- [ ] **Step 3: Add required production sources to the replay compiler**

  Extend `run_smart_rewrite_prompt_replay.sh` with the exact SmartInput dependencies needed by `SmartInputRouter`, including:

  ```text
  SmartRewriteEngine.swift
  SmartInputRouter.swift
  SmartRewriteAutoRuleStore.swift
  SmartRewriteCostGuard.swift
  SmartUsage.swift
  ```

  Do not add the deleted guard source.

- [ ] **Step 4: Run the fixed recording**

  Run:

  ```bash
  ./native/Tests/run_smart_rewrite_prompt_replay.sh \
    --audio "$HOME/Library/Caches/TypeWhale Pro/Recordings/recording_20260726_151405_0C81E1C9.wav"
  ```

  Expected: exit `0`; both modes report `Failed checks: none`; the report contains the final router-delivered text.

- [ ] **Step 5: Commit replay coverage**

  ```bash
  git add native/Tests/SmartRewritePromptReplayCheck.swift \
    native/Tests/run_smart_rewrite_prompt_replay.sh
  git commit -m "test: cover final smart rewrite delivery"
  ```

---

### Task 3: Update Product Records, Build and Install

**Files:**
- Modify: `docs/ARCHITECTURE.md`
- Modify: `docs/开发日志.md`
- Modify: `native/Sources/Presentation/VersionHistory/VersionHistoryViewController.swift`
- Modify by build tooling: `README.md`
- Modify by build tooling: `macos/README.md`
- Modify by build tooling: `docs/构建日志.md`
- Modify by build tooling: `native/build_native_app.sh`

**Interfaces:**
- Documents: user owns final content judgment; TypeWhale validates only technical response availability.
- Build: next daily build after `2.0.58 (838)`, expected `2.0.58 (839)` unless a concurrent build advances it first.

- [ ] **Step 1: Update architecture and development log**

  Record:

  ```text
  Smart Rewrite no longer performs semantic fidelity scoring after generation.
  Every non-empty selected-model response is delivered directly.
  Empty output, model errors, timeout, protocol errors, sanitization and no-provider-fallback remain unchanged.
  ```

  Preserve the historical Build 803 entry describing when the removed guard was introduced; historical records must not be rewritten.

- [ ] **Step 2: Add the next version-history entry**

  Add a Build 839 entry stating that TypeWhale no longer rejects model text based on literal term, number, constraint, question or overlap checks, and that users judge final accuracy.

- [ ] **Step 3: Run focused and boundary tests**

  Run:

  ```bash
  ./native/Tests/run_smart_rewrite_prompt_contract_checks.sh
  ./native/Tests/SmartRewriteSystemPromptBoundaryCheck.sh
  "$HOME/Library/Application Support/TypeWhale Pro/Runtimes/mlx-asr/v1/python/bin/python3" \
    -m unittest native/Tests/test_managed_mlx_llm_worker.py
  git diff --check
  ```

  Expected: all exit `0`; Python reports `Ran 16 tests` and `OK`.

- [ ] **Step 4: Recheck concurrency and build**

  Confirm branch, status, build processes and source mtimes. If no overlapping writer exists, run:

  ```bash
  ./native/build_and_log.sh
  ```

  Expected: build number increments once, current source compiles, `/Applications/TypeWhale Pro.app` is replaced and opened, and signature verification succeeds.

- [ ] **Step 5: Verify installed app**

  Run:

  ```bash
  defaults read "/Applications/TypeWhale Pro.app/Contents/Info" CFBundleShortVersionString
  defaults read "/Applications/TypeWhale Pro.app/Contents/Info" CFBundleVersion
  codesign --verify --deep --strict --verbose=2 "/Applications/TypeWhale Pro.app"
  pgrep -alf "/Applications/TypeWhale Pro.app/Contents/MacOS/TypeWhalePro"
  ```

  Expected: `2.0.58`, the new build number, a valid signature and a running app process.

- [ ] **Step 6: Commit build and records**

  Stage only the documented product, version and build files. Do not stage `.artifacts`, `.superpowers`, capsule concept directories or unrelated changes.

  ```bash
  git commit -m "chore: build semantic guard removal"
  ```

---

## Final Manual Test

1. In TypeWhale, select `极致归纳` and local Qwen3 4B.
2. Dictate: `原文只说响应速度，就不能改成影响速度。`
3. Confirm the model may return `不得改为影响速度`, and TypeWhale pastes that model result instead of the original sentence.
4. Confirm no `rewrite_fidelity_rejected` appears in the current build log.
5. Disconnect or force a genuine model error separately and confirm TypeWhale does not switch to another provider.
