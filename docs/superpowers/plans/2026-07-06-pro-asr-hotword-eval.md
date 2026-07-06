# Pro ASR Hotword Evaluation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a measured Pro ASR path for Chinese-English mixed dictation and developer hotwords before connecting any experimental model to final paste.

**Architecture:** Start with a repeatable evaluation set, then add provider capability metadata, isolated model runners, segment-level routing, and a merger. The stable current ASR remains fallback until the new path beats baseline on recorded samples.

**Tech Stack:** macOS AppKit app, Swift native app, shell/Python stdlib validation scripts, FunASR / ModelScope models in user Application Support, local sidecar runners for Python/PyTorch providers.

## Global Constraints

- Audio and model inference must remain local for this Pro ASR path.
- Do not route experimental ASR into final paste until offline evaluation passes.
- Current ASR fallback must remain available.
- Hotword support must be effective in acoustic, decoder, contextual, KWS, or word-spotter stage; text-only post-processing is not enough.
- The first shipped iteration should optimize recognition accuracy and speed, not streaming.
- Model files live under `/Users/waykingah/Library/Application Support/TypeWhale Pro/Models/funasr/` and must survive app rebuilds or overwrite installs.
- Commercial redistribution rights for FunASR / SenseVoice family models remain unresolved and must not be claimed as closed.

---

## File Structure

- `docs/TYPEWHALE_PRO_ASR_STRATEGY.md`: product and technical strategy, already created.
- `docs/superpowers/plans/2026-07-06-pro-asr-hotword-eval.md`: this execution plan.
- `docs/asr-eval/README.md`: operator guide for recording, labeling, and running model comparisons.
- `docs/asr-eval/pro-hotword-eval-cases.json`: versioned seed manifest for Chinese-English hotword test cases.
- `native/Tests/ProASREvalManifestCheck.sh`: schema and coverage guard for the evaluation manifest.
- Future: `tools/asr-eval/run_funasr_eval.py`: isolated offline runner for FunASR / Paraformer providers.
- Future: `native/Sources/Infrastructure/ASR/ASRProviderCapabilities.swift`: provider capability metadata used by UI, logs, and router.
- Future: `native/Sources/Core/ASR/HotwordMergeCandidate.swift`: neutral model for hotword-sidecar and merger output.

---

### Task 1: Phase 0 Evaluation Manifest

**Files:**
- Create: `docs/asr-eval/README.md`
- Create: `docs/asr-eval/pro-hotword-eval-cases.json`
- Create: `native/Tests/ProASREvalManifestCheck.sh`
- Modify: `docs/开发日志.md`
- Modify: `native/Sources/Presentation/VersionHistory/VersionHistoryViewController.swift`

**Interfaces:**
- Produces: JSON object with `version`, `updatedAt`, `defaultHotwords`, and `cases`.
- Produces: each case has `id`, `priority`, `languageProfile`, `expectedText`, `requiredHotwords`, `protectedTerms`, `audioPath`, and `recordingStatus`.
- Consumes: no model runtime yet.

- [ ] **Step 1: Write the failing manifest guard**

```bash
native/Tests/ProASREvalManifestCheck.sh
```

The script must fail when `docs/asr-eval/pro-hotword-eval-cases.json` is absent, malformed, has fewer than 12 cases, has fewer than 8 mixed-language cases, or does not cover the required developer hotwords.

- [ ] **Step 2: Run test to verify it fails**

Run: `bash native/Tests/ProASREvalManifestCheck.sh`

Expected: FAIL because `docs/asr-eval/pro-hotword-eval-cases.json` does not exist.

- [ ] **Step 3: Add the manifest and operator README**

Create 12 seed cases covering `Codex`, `Obsidian`, `Qwen3-ASR`, `SpeechInputCoordinator`, `sherpa-onnx`, `FunASR`, `Paraformer Contextual`, `ModelScope`, `hotword config`, `CT-Punc`, and `FSMN-VAD`.

- [ ] **Step 4: Run test to verify it passes**

Run: `bash native/Tests/ProASREvalManifestCheck.sh`

Expected: PASS with `ProASREvalManifestCheck passed`.

- [ ] **Step 5: Commit**

```bash
git add docs/asr-eval docs/superpowers/plans/2026-07-06-pro-asr-hotword-eval.md native/Tests/ProASREvalManifestCheck.sh docs/开发日志.md native/Sources/Presentation/VersionHistory/VersionHistoryViewController.swift
git commit -m "test: add Pro ASR hotword evaluation manifest"
```

---

### Task 2: Provider Capability Metadata

**Files:**
- Create: `native/Sources/Infrastructure/ASR/ASRProviderCapabilities.swift`
- Create: `native/Tests/ASRProviderCapabilitiesCheck.swift`
- Modify: `native/Sources/Infrastructure/ASR/SenseVoiceASR.swift`
- Modify: `native/Sources/Infrastructure/Models/ManagedASRModelCatalog.swift`

**Interfaces:**
- Consumes: provider IDs from current ASR settings and managed model catalog.
- Produces: `ASRProviderCapability` with `supportsHotwords`, `supportsCodeSwitching`, `supportsStreaming`, `supportsLanguageHint`, `recommendedUse`, and `verificationStatus`.

- [ ] **Step 1: Write failing tests for capability truth**

Run: `swift native/Tests/ASRProviderCapabilitiesCheck.swift`

Expected: FAIL because `ASRProviderCapability` is missing.

- [ ] **Step 2: Implement metadata only**

Mark current SenseVoice and Qwen3-ASR paths as not verified for Pro hotwords. Mark Paraformer Contextual as hotword candidate, Fun-ASR-Nano as code-switching candidate, and Paraformer zh as comparison.

- [ ] **Step 3: Run focused tests**

Run: `swift native/Tests/ASRProviderCapabilitiesCheck.swift`

Expected: PASS.

---

### Task 3: Isolated FunASR Offline Runner

**Files:**
- Create: `tools/asr-eval/run_funasr_eval.py`
- Create: `tools/asr-eval/hotwords-dev.txt`
- Create: `native/Tests/FunASREvalRunnerContractCheck.sh`
- Modify: `docs/asr-eval/README.md`

**Interfaces:**
- Consumes: manifest cases with `audioPath` pointing to local WAV files.
- Produces: JSONL rows with `caseId`, `provider`, `rawText`, `elapsedMs`, `requiredHotwordHits`, `missingHotwords`, `error`.

- [x] **Step 1: Write contract test**

Run: `bash native/Tests/FunASREvalRunnerContractCheck.sh`

Expected: FAIL because runner is missing.

- [x] **Step 2: Implement runner shell**

The runner must support `--manifest`, `--provider`, `--model-dir`, `--hotwords`, and `--output`. It may skip cases without audio and must write a structured skipped row instead of crashing.

- [x] **Step 3: Run without model dependency**

Run: `python3 tools/asr-eval/run_funasr_eval.py --manifest docs/asr-eval/pro-hotword-eval-cases.json --provider dry-run --output /tmp/typewhale-asr-eval.jsonl`

Expected: JSONL contains one row per case with `provider=dry-run`.

---

### Task 4: First Real Model Comparison

**Files:**
- Modify: `docs/asr-eval/README.md`
- Create: `docs/asr-eval/results/.gitkeep`
- Create local untracked output: `docs/asr-eval/results/YYYY-MM-DD-local.jsonl`

**Interfaces:**
- Consumes: recorded WAV files and Task 3 runner.
- Produces: local results file summarizing baseline, Paraformer Contextual, Fun-ASR-Nano, and Paraformer zh.

- [ ] **Step 1: Record at least 12 P0 WAV samples**

Use the exact `expectedText` strings from the manifest. Store recordings locally under `docs/asr-eval/audio/` or another local path not committed if privacy-sensitive.

- [ ] **Step 2: Run baseline and candidates**

Run the runner once per provider and compare `requiredHotwordHits`, missing hotwords, elapsed time, and failure mode.

- [ ] **Step 3: Decide provider order**

Promote only providers that improve hotword recall without obvious Chinese regression.

---

### Task 5: Router + Merger Prototype

**Files:**
- Create: `native/Sources/Core/ASR/HotwordMergeCandidate.swift`
- Create: `native/Sources/Core/ASR/HotwordSegmentMerger.swift`
- Create: `native/Tests/HotwordSegmentMergerCheck.swift`

**Interfaces:**
- Consumes: baseline ASR text and timestamped hotword candidates.
- Produces: merged final text and merge explanation.

- [ ] **Step 1: Test obvious replacement**

Input baseline: `把千问三asr接到 speech input coordinator`

Candidate: `Qwen3-ASR`, `SpeechInputCoordinator`

Expected output: `把 Qwen3-ASR 接到 SpeechInputCoordinator`

- [ ] **Step 2: Test conservative non-replacement**

If candidate confidence is below threshold or overlaps unrelated Chinese text, merger must keep baseline.

---

### Task 6: Experimental Final ASR Switch

**Files:**
- Modify: `native/Sources/Application/SpeechInputCoordinator.swift`
- Modify: `native/Sources/Infrastructure/Settings/AppSettings.swift`
- Modify: `native/Sources/Presentation/Main/MainViewController+PanelLayout.swift`
- Create: `native/Tests/ExperimentalASRSwitchCheck.swift`

**Interfaces:**
- Consumes: provider capability metadata and merger.
- Produces: disabled-by-default Pro ASR experiment switch.

- [ ] **Step 1: Test default-off behavior**

The stable final ASR path must remain unchanged when the switch is off.

- [ ] **Step 2: Add experiment logs**

Every experimental run must log provider, hotwords used, elapsed time, missing hotwords, fallback reason, and final chosen text.

---

## Self-Review

- Spec coverage: The plan covers the current product judgment, Phase 0 evaluation, hotword-capable provider metadata, sidecar evaluation, first real model comparison, router/merger, and final experimental switch.
- Placeholder scan: No task uses `TBD`, `TODO`, or unspecified implementation language.
- Type consistency: Task outputs flow from manifest to runner to provider metadata to merger to final switch.
