# Smart Rewrite Semantic Structure Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every smart-rewrite mode and every selected rewrite model organize mixed utterances by semantic role instead of forcing requirements, test content, questions, and constraints into one sentence.

**Architecture:** Add one immutable semantic-structure contract to `SmartRewritePromptBuilder` after the raw-text block, so every mode receives the same final output instruction closest to generation. Qwen3 and DeepSeek already consume the same builder output, so no engine-specific code changes are needed.

**Tech Stack:** Swift, shell-based Swift contract checks, managed MLX Qwen3 4B replay, native macOS build scripts.

> Build 841 correction: the concrete calibration answer introduced by this plan leaked into unrelated short utterances. The production prompt now keeps only generic structure rules, and simple single-sentence exhaustive-summary input bypasses the rewrite model after term normalization.

## Global Constraints

- Do not change ASR, model selection, failure handling, paste behavior, UI, or saved custom templates.
- Do not restore or replace the deleted App-side semantic fidelity guard.
- Keep chat and polish modes natural; do not force headings, numbering, or lists when the source has no clear semantic grouping.
- Preserve numbers, proper names, negation relationships, and question tone while reorganizing structure.
- Do not touch protected untracked directories: `.artifacts/`, `.superpowers/`, `native/Helpers/CapsuleConceptGallery/`, or `native/Sources/Presentation/Capsule/Concepts/`.

---

### Task 1: Shared Semantic Structure Contract

**Files:**
- Modify: `native/Tests/SmartRewritePromptCheck.swift`
- Modify: `native/Sources/Core/SmartInput/SmartRewritePromptBuilder.swift`

**Interfaces:**
- Consumes: `SmartRewritePromptBuilder.prompt(rawText:mode:context:preference:) -> String`
- Produces: `SemanticStructureContract.text`, included in every non-raw/non-command smart rewrite prompt

- [x] **Step 1: Write the failing contract test**

Add the fixed utterance and these checks inside the existing loop over `SmartRewritePromptStore.editableModes`:

```swift
let semanticStructureText = "响应速度不能改为影响速度。测试包含 Gpt chatgpt12345 和今天真的可以吗？"

let semanticStructurePrompt = SmartRewritePromptBuilder.prompt(
    rawText: semanticStructureText,
    mode: mode,
    context: context,
    preference: .automatic
)
precondition(semanticStructurePrompt.contains("先区分同一段话中的要求、测试内容、疑问、限制和步骤"))
precondition(semanticStructurePrompt.contains("使用自然分句、换行或列表"))
precondition(semanticStructurePrompt.contains("不得为了简短把不同语义强行拼成一句"))
precondition(semanticStructurePrompt.contains("原文没有明确分类时，不强制添加标题、编号或固定模板"))
precondition(semanticStructurePrompt.contains("保留数字、专有名词、否定关系和疑问语气"))
precondition(semanticStructurePrompt.contains(semanticStructureText))
```

- [x] **Step 2: Run the test and verify RED**

Run:

```bash
./native/Tests/run_smart_rewrite_prompt_contract_checks.sh
```

Expected: `SmartRewritePromptCheck` stops at the first new `precondition` because the shared rule is absent.

- [x] **Step 3: Add the minimal shared contract**

Insert the contract into the prompt assembly:

```swift
return [
    GlobalSafetyContract.text,
    ModeContract.text(for: mode),
    renderedTemplate,
    RawTextBlock.render(rawText),
    SemanticStructureContract.text,
]
```

Define the immutable contract in the same focused prompt builder file:

```swift
private enum SemanticStructureContract {
    static let text = """
    通用语义结构规则：
    - 先区分同一段话中的要求、测试内容、疑问、限制和步骤；存在不同语义时，使用自然分句、换行或列表清楚区分。
    - 不得为了简短把不同语义强行拼成一句；原文没有明确分类时，不强制添加标题、编号或固定模板。
    - 调整结构时必须保留数字、专有名词、否定关系和疑问语气，不得改变它们之间的关系。
    """
}
```

- [x] **Step 4: Run the contract suite and verify GREEN**

Run:

```bash
./native/Tests/run_smart_rewrite_prompt_contract_checks.sh
```

Expected: exit code `0`, with `DeveloperTermNormalizerCheck`, `SmartRewritePromptCheck`, and `PromptFixtureCheck` all completing.

- [x] **Step 5: Commit the tested behavior**

```bash
git add -- native/Tests/SmartRewritePromptCheck.swift native/Sources/Core/SmartInput/SmartRewritePromptBuilder.swift
git commit -m "feat: structure mixed smart rewrite utterances"
```

### Task 2: Real Qwen3 4B Output Verification

**Files:**
- No tracked files changed.
- Temporary replay files must stay under a `mktemp -d` directory, not `.artifacts/`.

**Interfaces:**
- Consumes: the production `SmartRewritePromptBuilder` output and `native/Resources/managed_mlx_llm_worker.py`
- Produces: captured local Qwen3 4B outputs for at least `.developerRequirement` and `.exhaustiveSummary`

- [x] **Step 1: Generate the exact production prompts**

Compile a temporary Swift replay driver against the same prompt sources used by the App. Its fixed input is:

```swift
let rawText = "响应速度不能改为影响速度。测试包含 Gpt chatgpt12345 和今天真的可以吗？"
```

The driver must print JSON containing prompts for:

```swift
[RewriteMode.developerRequirement, RewriteMode.exhaustiveSummary]
```

- [x] **Step 2: Run both prompts through the installed managed MLX runtime**

Use:

```text
~/Library/Application Support/TypeWhale Pro/Runtimes/mlx-asr/v1/python/bin/python3
```

with `native/Resources/managed_mlx_llm_worker.py`, command `rewrite`, and model directory:

```text
~/Library/Application Support/TypeWhale Pro/Models/LLM/qwen3-4b-instruct-2507-4bit
```

Use the same system prompt lead as production and record `final_text`, `ttft_ms`, and `completion_ms`.

- [x] **Step 3: Inspect results against the product requirement**

For each mode, manually verify and report:

- “测试内容”和“注意事项” are visibly separated.
- `GPT`, `ChatGPT`, and `12345` remain distinguishable.
- “响应速度不能改为影响速度” remains a negated correction relationship.
- “今天真的可以吗？” remains a question.
- No App-side score, rejection, or source fallback is involved.

If a mode still joins the semantic groups, refine only `SemanticStructureContract.text`, add the missing requirement to the contract test first, and repeat Task 1 RED/GREEN.

### Task 3: Product Records, Build, Install, and Final Verification

**Files:**
- Modify: `docs/开发日志.md`
- Modify: `native/Sources/Presentation/VersionHistory/VersionHistoryViewController.swift`
- Generated by build: version/build metadata and `docs/构建日志.md`

**Interfaces:**
- Consumes: the verified shared prompt behavior from Task 1 and Qwen output from Task 2
- Produces: one uniquely numbered installed `/Applications/TypeWhale Pro.app` build and a commit containing all release records

- [x] **Step 1: Record the product behavior before building**

Add a new top entry to both product records stating:

```text
所有智能整理模式和整理模型现在共用语义结构规则；要求、测试内容、疑问、限制和步骤会按原文层次自然分句或换行，不再为了简短挤成一句。
数字、专有名词、否定关系和疑问语气继续保留；没有明确分类的短句不会被强制套标题或固定模板。
本轮不修改 ASR、模型选择、失败不降级、粘贴流程，也不恢复 App 侧语义保真检查。
```

Use the build number expected by the build script after rechecking current version metadata.

- [x] **Step 2: Recheck concurrency immediately before build**

Run:

```bash
git branch --show-current
git status --short
pgrep -afil 'build_and_log\.sh|release_local_build\.sh|build_native_app\.sh|swiftc|xcodebuild' || true
```

Expected: branch `codex/typewhale-pro-asr-hotwords`, only this task’s tracked changes plus protected untracked directories, and no unrelated build.

- [x] **Step 3: Run focused and broader automated checks**

Run:

```bash
./native/Tests/run_smart_rewrite_prompt_contract_checks.sh
```

Expected: the command exits `0`; the full native build in the next step compiles the broader Smart Input production source set.

- [x] **Step 4: Build, increment build number, install, open, and sign-check**

Run:

```bash
./native/build_and_log.sh
```

Expected: a new unique build number, successful compilation, replacement of `/Applications/TypeWhale Pro.app`, App launch, signature verification, and one new build-log row.

- [x] **Step 5: Verify the installed binary and repository state**

Run:

```bash
codesign --verify --deep --strict "/Applications/TypeWhale Pro.app"
git diff --check
git status --short
```

Expected: signature verification exits `0`; no whitespace errors; only the intended tracked build records and protected untracked directories remain.

- [x] **Step 6: Commit the build and records**

Stage only the files shown by the preceding status review:

```bash
git add -- docs/开发日志.md docs/构建日志.md native/Sources/Presentation/VersionHistory/VersionHistoryViewController.swift native/build_native_app.sh
git commit -m "chore: build shared semantic structure rules"
```

If the build updates additional tracked version metadata, review and add only those exact files.

- [x] **Step 7: Final user handoff**

Report:

- the exact local Qwen3 outputs for both tested modes;
- what changed in product language;
- the installed version and build number;
- automated checks actually run;
- a manual test path covering local Qwen3 and DeepSeek, with the expected semantic separation;
- any unverified online DeepSeek output if no paid request was safely available.
