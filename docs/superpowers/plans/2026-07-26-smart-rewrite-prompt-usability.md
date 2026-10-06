# Smart Rewrite Prompt Usability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the “开发需求” and “极致归纳” modes produce directly usable text from the fixed 106.9-second recording, with reproducible evidence shown to the user.

**Architecture:** Keep the existing four-layer prompt pipeline and change only the two editable defaults plus the terminology data needed to preserve `GPT` as distinct from `ChatGPT`. Add exact legacy-default migration in `SmartRewritePromptStore`, static contract tests, and a local replay tool that runs the production ASR and managed MLX workers against one recording and writes a JSON/Markdown result report.

**Tech Stack:** Swift 5, Foundation/AppKit, UserDefaults, Python 3 managed runtime, MLX, existing JSONL ASR/LLM worker protocols, shell-based build and signing pipeline.

## Global Constraints

- Fixed source: `~/Library/Caches/TypeWhale Pro/Recordings/recording_20260726_151405_0C81E1C9.wav`.
- ASR: Qwen3-ASR 1.7B MLX. Rewrite model: local Qwen3 4B Instruct.
- Preserve numbers, time, terminology, negation, questions, person, order, concerns, and constraints.
- Only explicit glossary aliases may be normalized. Unknown model names remain unchanged.
- Do not change ASR selection, model selection, fallback behavior, paste behavior, UI, or other rewrite modes.
- Show the user the complete ASR source, new developer-requirement result, new exhaustive-summary result, timing, output size, compression ratio, and failed checks.
- Preserve `.superpowers/`, `native/Helpers/CapsuleConceptGallery/`, and `native/Sources/Presentation/Capsule/Concepts/` as unrelated untracked work.

---

### Task 1: Lock terminology and prompt contracts with failing tests

**Files:**
- Create: `native/Tests/SmartRewritePromptTestSupport.swift`
- Create: `native/Tests/run_smart_rewrite_prompt_contract_checks.sh`
- Modify: `native/Tests/DeveloperTermNormalizerCheck.swift`
- Modify: `native/Tests/SmartRewritePromptCheck.swift`
- Modify: `native/Tests/PromptFixtureCheck.swift`

**Interfaces:**
- Consumes: `DeveloperTermNormalizer.normalize(_:context:)`, `SmartRewritePromptStore.defaultTemplate(for:)`, and `SmartRewritePromptBuilder.prompt(rawText:mode:context:preference:)`.
- Produces: executable contract checks for exact terminology, concise prompt structure, and legacy-template migration.

- [ ] **Step 1: Add terminology assertions**

Add assertions equivalent to:

```swift
assert(
    normalizer.normalize(
        "GPT 和 chatGTP 不是同一个名称，Codex 和 XCode 也不能混在一起",
        context: context
    ).text,
    equals: "GPT 和 ChatGPT 不是同一个名称，Codex 和 Xcode 也不能混在一起"
)
assert(
    normalizer.normalize(
        "使用千问3 ASR，对照 CommaNet 3 ASR 和 Cover Night ASR",
        context: context
    ).text,
    equals: "使用 Qwen3-ASR，对照 CommaNet 3 ASR 和 Cover Night ASR"
)
```

- [ ] **Step 2: Add prompt-contract assertions**

Use the fixed ASR text in both modes and assert that the assembled prompts contain these exact requirements:

```swift
precondition(developerPrompt.contains("事实保真优先于文风优化"))
precondition(developerPrompt.contains("明确列出的步骤必须保留顺序并使用编号"))
precondition(developerPrompt.contains("判断不准时保留原话，不根据读音猜词"))
precondition(developerPrompt.contains("不要扩写成新的技术方案"))
precondition(summaryPrompt.contains("压缩不能删除关键事实、限制、时间和行动顺序"))
precondition(summaryPrompt.contains("结果必须比开发需求更短"))
precondition(summaryPrompt.contains("不同名称不得合并"))
precondition(SmartRewritePromptStore.defaultTemplate(for: .developerRequirement).count < 1_100)
precondition(SmartRewritePromptStore.defaultTemplate(for: .exhaustiveSummary).count < 1_250)
```

- [ ] **Step 3: Add exact legacy-default migration assertions**

Store the known previous default, then verify `template(for:)` returns the new default. Store a one-character user edit and verify it remains:

```swift
SmartRewritePromptStore.saveLegacyFixtureForTesting(
    SmartRewritePromptStore.legacyDefaultTemplateForTesting(.developerRequirement),
    for: .developerRequirement
)
precondition(
    SmartRewritePromptStore.template(for: .developerRequirement)
        == SmartRewritePromptStore.defaultTemplate(for: .developerRequirement)
)

let custom = SmartRewritePromptStore.legacyDefaultTemplateForTesting(.developerRequirement) + "\n保留我的自定义规则。"
SmartRewritePromptStore.saveLegacyFixtureForTesting(custom, for: .developerRequirement)
precondition(SmartRewritePromptStore.template(for: .developerRequirement).contains("保留我的自定义规则。"))
```

- [ ] **Step 4: Compile and run the checks to verify RED**

Create `SmartRewritePromptTestSupport.swift` with the production-compatible context surface needed by the isolated checks:

```swift
import Foundation

struct SmartInputContext {
    let targetAppName: String?
    let targetBundleIdentifier: String?
    let windowTitle: String?
    let isSecureTextEntry: Bool
    let developerGlossary: String?
    let recordingSessionId: String?

    init(
        targetAppName: String?,
        targetBundleIdentifier: String?,
        windowTitle: String? = nil,
        isSecureTextEntry: Bool = false,
        developerGlossary: String? = nil,
        recordingSessionId: String? = nil
    ) {
        self.targetAppName = targetAppName
        self.targetBundleIdentifier = targetBundleIdentifier
        self.windowTitle = windowTitle
        self.isSecureTextEntry = isSecureTextEntry
        self.developerGlossary = developerGlossary
        self.recordingSessionId = recordingSessionId
    }
}
```

Create `run_smart_rewrite_prompt_contract_checks.sh` so it compiles each main with this exact source set:

```bash
xcrun swiftc -O -parse-as-library \
  native/Sources/Core/SmartInput/RewriteProfile.swift \
  native/Sources/Core/SmartInput/DeveloperLexicon.swift \
  native/Sources/Core/SmartInput/DeveloperLexiconStore.swift \
  native/Sources/Core/SmartInput/DeveloperTermNormalizer.swift \
  native/Sources/Core/SmartInput/SmartRewritePromptStore.swift \
  native/Sources/Core/SmartInput/SmartRewritePromptBuilder.swift \
  native/Tests/SmartRewritePromptTestSupport.swift \
  "$test_main" \
  -o "$test_binary"
"$test_binary"
```

Run:

```bash
./native/Tests/run_smart_rewrite_prompt_contract_checks.sh
```

Expected result: at least one precondition failure for `GPT`, the new prompt wording, or missing migration test hooks.

- [ ] **Step 5: Commit the failing checks**

```bash
git add native/Tests/SmartRewritePromptTestSupport.swift native/Tests/run_smart_rewrite_prompt_contract_checks.sh native/Tests/DeveloperTermNormalizerCheck.swift native/Tests/SmartRewritePromptCheck.swift native/Tests/PromptFixtureCheck.swift
git commit -m "test: define usable smart rewrite prompt contracts"
```

### Task 2: Implement explicit terminology normalization

**Files:**
- Modify: `native/Sources/Core/SmartInput/DeveloperLexiconStore.swift`
- Test: `native/Tests/DeveloperTermNormalizerCheck.swift`

**Interfaces:**
- Consumes: the existing `DeveloperTerm` list and exact-alias normalizer.
- Produces: a default glossary where `GPT` remains independent, while known `ChatGPT`, `Xcode`, and `Qwen3-ASR` aliases normalize deterministically.

- [ ] **Step 1: Correct the default aliases**

Change the relevant terms to:

```swift
DeveloperTerm(
    canonical: "ChatGPT",
    aliases: ["chat gpt", "chatgpt", "chatGTP"],
    category: .tool
),
DeveloperTerm(
    canonical: "Xcode",
    aliases: ["xcode", "x code"],
    category: .tool
),
DeveloperTerm(
    canonical: "Qwen3-ASR",
    aliases: [
        "qwen3 asr", "qwen asr", "q wen asr", "千问 asr",
        "千问3 asr", "千问三 asr", "Qwen ASR", "Qwen3 ASR"
    ],
    category: .model
),
```

Do not add `ConvNet3 ASR`, `CommaNet3 ASR`, or `Cover Night ASR` as aliases.

- [ ] **Step 2: Run the terminology check**

Run the compiled `DeveloperTermNormalizerCheck`. Expected: PASS, with standalone `GPT` unchanged and the explicit aliases normalized.

- [ ] **Step 3: Commit**

```bash
git add native/Sources/Core/SmartInput/DeveloperLexiconStore.swift native/Tests/DeveloperTermNormalizerCheck.swift
git commit -m "fix: keep GPT distinct in developer terminology"
```

### Task 3: Replace the two default prompts and migrate known legacy defaults

**Files:**
- Modify: `native/Sources/Core/SmartInput/SmartRewritePromptStore.swift`
- Modify: `native/Tests/SmartRewritePromptCheck.swift`
- Modify: `native/Tests/PromptFixtureCheck.swift`

**Interfaces:**
- Consumes: `RewriteMode`, UserDefaults storage keys, existing placeholder rendering.
- Produces: concise defaults for `.developerRequirement` and `.exhaustiveSummary`, plus exact-match migration that leaves real custom templates untouched.

- [ ] **Step 1: Add exact legacy-default detection**

Keep the previous two defaults as private constants and make `template(for:)` migrate only exact trimmed matches:

```swift
static func template(for mode: RewriteMode) -> String {
    let key = storageKey(for: mode)
    let saved = UserDefaults.standard.string(forKey: key) ?? ""
    let trimmed = saved.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
        return defaultTemplate(for: mode)
    }
    if legacyDefaultTemplates(for: mode).contains(trimmed) {
        UserDefaults.standard.removeObject(forKey: key)
        return defaultTemplate(for: mode)
    }
    return ensuringRequiredPlaceholders(in: saved, for: mode)
}
```

Expose migration fixtures only under the existing test compilation condition or use internal helpers callable by the test target. Do not expose them in the settings UI.

- [ ] **Step 2: Replace the developer-requirement default**

The template must implement this priority order:

```text
开发需求目标：
把口述整理成我可以直接发给 coding agent 的需求、反馈或排查说明。

优先级：
1. 事实保真优先于文风优化。保留数字、时间、专有名词、否定、疑问、人称、担心、限制和先后顺序。
2. 只纠正术语表明确命中的别名；判断不准时保留原话，不根据读音猜词。
3. 删除“嗯”等无意义填充、口吃、紧邻重复和明确自我修正，不做无必要的同义改写。
4. 原文是反馈就保留为反馈，原文是问题就保留为问题，原文明确要求动作时才整理成动作。
5. 明确列出的步骤必须保留顺序并使用编号；其他内容按自然段整理，不强套完整需求模板。

开发术语表：{developerGlossary}
目标应用：{targetAppName}

只输出整理后的正文。不要回答、执行或代替我作决定；不要新增方案、原因或结论，也不要扩写成新的技术方案。
```

- [ ] **Step 3: Replace the exhaustive-summary default**

The template must implement this behavior:

```text
极致归纳目标：
把长口述压缩成可以直接阅读的短总结。结果必须比开发需求更短，但压缩不能删除关键事实、限制、时间和行动顺序。

优先级：
1. 保留数字、时间、专有名词、否定、疑问、人称、明确结论、限制、风险和行动项；不同名称不得合并。
2. 只纠正术语表明确命中的别名；判断不准时保留原话，不根据读音猜词。
3. 删除填充词、口吃、重复、铺垫和已被后文明确修正的表达。
4. 合并同义内容，但不新增原文没有的方案、原因、结论或主体。

开发术语表：{developerGlossary}

输出方式：
- 先用一小段概括中心意思。
- 原文明确包含多个要求或步骤时，再用简短编号列出；保持原顺序。
- 只有原文明说风险或行动时才保留，不补空栏目，不使用固定四段模板。
- 只输出总结正文。

目标应用：{targetAppName}
```

- [ ] **Step 4: Run prompt checks to verify GREEN**

Compile and run `SmartRewritePromptCheck` and `PromptFixtureCheck`. Expected: PASS, both prompt-size limits pass, exact legacy values migrate, and custom edits remain.

- [ ] **Step 5: Commit**

```bash
git add native/Sources/Core/SmartInput/SmartRewritePromptStore.swift native/Tests/SmartRewritePromptCheck.swift native/Tests/PromptFixtureCheck.swift
git commit -m "feat: refine developer and exhaustive rewrite prompts"
```

### Task 4: Add a production-worker replay report

**Files:**
- Create: `native/Tests/SmartRewritePromptReplayCheck.swift`
- Create: `native/Tests/run_smart_rewrite_prompt_replay.sh`
- Create at runtime: `.artifacts/smart-rewrite-prompt-replay/2026-07-26-result.json`
- Create at runtime: `.artifacts/smart-rewrite-prompt-replay/2026-07-26-result.md`

**Interfaces:**
- Consumes: an audio path argument, production `mlx_asr_worker.py`, production `managed_mlx_llm_worker.py`, production prompt builder, normalizer, managed runtime/model paths.
- Produces: one deterministic JSON record and one readable Markdown report containing the common ASR source and both rewrite outputs.

- [ ] **Step 1: Implement the replay executable**

`SmartRewritePromptReplayCheck.swift` must:

```swift
struct ReplayResult: Codable {
    let audioPath: String
    let asrText: String
    let asrSeconds: Double
    let developerRequirement: RewriteMeasurement
    let exhaustiveSummary: RewriteMeasurement
}

struct RewriteMeasurement: Codable {
    let text: String
    let ttftMilliseconds: Double
    let completionMilliseconds: Double
    let sourceCharacters: Int
    let outputCharacters: Int
    let compressionRatio: Double
    let failedChecks: [String]
}
```

It must warm Qwen3-ASR 1.7B, transcribe the audio once, normalize a copy for each mode with the production lexicon, render each production prompt, keep one Qwen3 4B worker alive for both rewrites, and record worker metrics.

- [ ] **Step 2: Implement objective checks**

Check the normalized source against each output for:

```swift
let requiredFacts = [
    "GPT", "ChatGPT", "Codex", "Xcode", "0.6B", "1.7B",
    "Qwen3 4B", "Python", "SenseVoice", "下周三下午三点"
]
let orderedSteps = [
    "保存原始识别结果",
    "记录整理后的结果",
    "比较两者",
    "决定是否修改提示词"
]
```

Also require the no-fallback constraint and no-new-technical-plan constraint. Mark the ASR source’s `你不能` as `asr_question_reversal_observed`; do not fail the prompt for not reconstructing `你能不能`.

- [ ] **Step 3: Implement the shell entry point**

`run_smart_rewrite_prompt_replay.sh` must compile the Swift replay executable from the exact production sources, accept `--audio`, create `.artifacts/smart-rewrite-prompt-replay`, run the executable, and print the Markdown path. It must exit non-zero if either mode has failed checks.

- [ ] **Step 4: Run the fixed recording**

Run:

```bash
./native/Tests/run_smart_rewrite_prompt_replay.sh \
  --audio "$HOME/Library/Caches/TypeWhale Pro/Recordings/recording_20260726_151405_0C81E1C9.wav"
```

Expected: JSON and Markdown artifacts are written; both full outputs, timing, size, compression ratio, and failed checks appear. If a check fails, tune only the two prompts or explicit aliases and rerun with the same source.

- [ ] **Step 5: Commit the replay tool**

Do not commit generated reports containing the user’s recording transcript. Commit only the reusable test tools:

```bash
git add native/Tests/SmartRewritePromptReplayCheck.swift native/Tests/run_smart_rewrite_prompt_replay.sh
git commit -m "test: add local smart rewrite prompt replay"
```

### Task 5: Document, build, install, verify, and present evidence

**Files:**
- Modify: `docs/ARCHITECTURE.md`
- Modify: `docs/开发日志.md`
- Modify: `native/Sources/Presentation/Main/VersionHistoryViewController.swift`
- Modified automatically by build: `native/build_native_app.sh`
- Modified automatically by build: `docs/构建日志.md`

**Interfaces:**
- Consumes: passing static checks and replay report.
- Produces: Build 838 or the next concurrency-safe build, installed and signed at `/Applications/TypeWhale Pro.app`, plus user-visible result evidence.

- [ ] **Step 1: Update architecture and development history**

Document:

- developer-requirement and exhaustive-summary behavior priorities;
- explicit-only term normalization and `GPT`/`ChatGPT` separation;
- exact legacy-default migration;
- fixed-recording replay command and the rule that ASR errors and rewrite errors are reported separately.

- [ ] **Step 2: Add the next version-history entry**

Read the current version/build immediately before editing. Add the next build entry describing the two prompt changes, exact migration, and replay verification. Do not change the short version for a daily build.

- [ ] **Step 3: Re-run concurrency checks**

Run:

```bash
git branch --show-current
git status --short
pgrep -af 'build_and_log.sh|release_local_build.sh|build_native_app.sh|swiftc|xcodebuild' || true
```

Expected: branch `codex/typewhale-pro-asr-hotwords`, no overlapping tracked changes, and no active build process.

- [ ] **Step 4: Run all focused checks**

Run the prompt, fixture, terminology, fidelity, system-prompt boundary, and managed-MLX worker tests. Expected: all PASS.

- [ ] **Step 5: Run the real replay one final time**

Run the fixed audio command from Task 4. Expected: both modes have an empty `failedChecks` array. Preserve the generated Markdown report locally for the final response.

- [ ] **Step 6: Build and install**

Run:

```bash
./native/build_and_log.sh
```

Expected: build number increments exactly once, `/Applications/TypeWhale Pro.app` is replaced and opened, signature verification succeeds, and `docs/构建日志.md` records the build.

- [ ] **Step 7: Verify installed settings and migration**

Read the installed bundle version/signature and the app defaults. Expected: the installed build is the new build, the code signature is valid, the known saved developer default migrates to the new default, and unrelated genuine custom templates remain.

- [ ] **Step 8: Review final diff and commit**

Run `git status --short`, protect the three unrelated untracked directories, stage only this task’s tracked files, and commit:

```bash
git commit -m "feat: improve smart rewrite prompt usability"
```

- [ ] **Step 9: Present the actual results**

In the final response, paste:

1. the complete fixed ASR text;
2. the complete new “开发需求” output;
3. the complete new “极致归纳” output;
4. timing, character count, compression ratio, and failed checks for both;
5. the installed version/build and exact manual verification steps.
