# Developer Requirement Semantic Rewrite Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make “开发需求” turn disfluent speech into directly usable requirements through one local Qwen3 4B request, while removing only a final Chinese full stop or English sentence period.

**Architecture:** Keep the existing single-request `SmartRewritePromptBuilder` and routing path. Strengthen only the `.developerRequirement` default template and its exact-default migration, then apply a small mode-aware final-output policy in `SmartInputRouter`; add a dedicated local-Qwen semantic replay suite for product-level evidence.

**Tech Stack:** Swift, Foundation, AppKit, UserDefaults prompt migration, managed MLX Qwen3 4B worker, executable Swift checks, TypeWhale native build scripts.

## Global Constraints

- Only `.developerRequirement` behavior changes; other rewrite modes, ASR, model selection, fallback, paste, and auto-send remain unchanged.
- Output is direct requirement text with no confirmation preface, closing question, answer, execution, or invented technical plan.
- The model silently identifies object, requested behavior, operation, state/spatial relation, and explicitly retained behavior before writing.
- “中心对齐” must not be weakened to “水平中心对齐” unless the source explicitly limits the axis.
- Simple utterances stay short; multiple explicit requirements may be separated naturally; numbered lists require explicit source ordering.
- Unknown terms and relations remain unchanged instead of being guessed.
- `.developerRequirement` removes a single final `。` or sentence `.`; internal punctuation and semantic `?` / `!` remain.
- Existing custom templates remain; only exact known defaults migrate.
- Every production change follows RED → GREEN and the final local Qwen outputs are shown to the user.

---

### Task 1: Developer requirement semantic prompt contract and migration

**Files:**
- Modify: `native/Tests/SmartRewritePromptCheck.swift`
- Modify: `native/Tests/PromptFixtureCheck.swift`
- Modify: `native/Sources/Core/SmartInput/SmartRewritePromptStore.swift`

**Interfaces:**
- Consumes: `SmartRewritePromptStore.defaultTemplate(for:)`, `template(for:)`, `saveLegacyFixtureForTesting(_:for:)`.
- Produces: a `.developerRequirement` prompt that contains the silent semantic checklist, direct-output rule, full-center relation rule, no-final-period instruction, and an exact migration entry for the Build 843 default.

- [ ] **Step 1: Write failing prompt and migration assertions**

Add the countdown source fixture and assert the rendered developer prompt contains:

```swift
precondition(prompt.contains("先在内部理解，不要输出分析过程"))
precondition(prompt.contains("对象、希望改变的行为、操作方式、状态或位置关系"))
precondition(prompt.contains("要求保留的既有逻辑"))
precondition(prompt.contains("“中心对齐”不得缩窄成“水平中心对齐”"))
precondition(prompt.contains("不要添加“我理解你的需求是”"))
precondition(prompt.contains("正文末尾不要添加中文句号或英文句点"))
precondition(prompt.contains("两秒自动取消那个条不显不显示取消按钮"))
```

Save the exact Build 843 default through a new testing accessor and verify `template(for: .developerRequirement)` returns the new default while a modified custom template remains unchanged.

- [ ] **Step 2: Run the contract suite and verify RED**

Run:

```bash
bash native/Tests/run_smart_rewrite_prompt_contract_checks.sh
```

Expected: FAIL at the first missing semantic-checklist assertion.

- [ ] **Step 3: Replace only the developer default template**

Use a compact template with these sections and no concrete calibration answer:

```text
开发需求目标：
把口述整理成我可以直接发给 coding agent 的需求、反馈或排查说明。

内部理解步骤（只在内部完成，不要输出分析过程）：
1. 判断这是需求、反馈、问题、排查说明还是限制。
2. 识别对象、希望改变的行为、操作方式、状态或位置关系，以及要求保留的既有逻辑。
3. 删除填充词、口吃、紧邻重复和能够明确判断的自我修正。
4. 把断裂口语重组为直接、自然的需求正文，但不得添加原文没有的信息。

语义边界：
- 空间、时间、数量、否定和强度关系不得弱化；“中心对齐”不得缩窄成“水平中心对齐”，除非原文明说横向。
- 一个意思的短句保持一句；多个明确要求才自然分句；原文明列步骤时才编号。
- 无法确认的术语、主体或关系保留原话，不根据读音猜测。
- 保留数字、时间、专有名词、疑问、人称、担心、限制、先后顺序和明确保留项。

开发术语表：{developerGlossary}
目标应用：{targetAppName}

只输出整理后的正文。不要添加“我理解你的需求是”等前言，不要询问是否正确；不要回答、执行、代替我决定或扩写技术方案。正文末尾不要添加中文句号或英文句点。
```

Copy the previous exact default into `LegacyDefaultTemplates` and include it in `legacyDefaultTemplates(for: .developerRequirement)`. Do not migrate non-identical custom text.

- [ ] **Step 4: Run prompt checks and verify GREEN**

Run:

```bash
bash native/Tests/run_smart_rewrite_prompt_contract_checks.sh
```

Expected: `DeveloperTermNormalizerCheck passed`, `SmartRewritePromptCheck passed`, and `PromptFixtureCheck passed`.

- [ ] **Step 5: Commit the prompt contract**

```bash
git add native/Tests/SmartRewritePromptCheck.swift native/Tests/PromptFixtureCheck.swift native/Sources/Core/SmartInput/SmartRewritePromptStore.swift
git commit -m "feat: strengthen developer requirement understanding"
```

### Task 2: Mode-scoped final-period removal

**Files:**
- Modify: `native/Tests/SmartInputCheck.swift`
- Modify: `native/Sources/Core/SmartInput/SmartRewriteOutputSanitizer.swift`
- Modify: `native/Sources/Core/SmartInput/SmartInputRouter.swift`

**Interfaces:**
- Consumes: `SmartRewriteEngineOutput.text`, `RewriteMode`.
- Produces: `SmartRewriteOutputSanitizer.finalize(_:mode:) -> String`, called once by `SmartInputRouter` before a non-empty model result is delivered.

- [ ] **Step 1: Write failing delivery assertions**

Add fixed-engine cases:

```swift
precondition(
    developerPeriodResult.text
        == "倒计时条与胶囊横向、纵向中心完全重合"
)
precondition(questionResult.text == "这个问题为什么会发生？")
precondition(exclamationResult.text == "必须保留现有逻辑！")
precondition(polishResult.text == "普通润色仍保留句号。")
precondition(ellipsisResult.text == "这个术语暂时不确定...")
```

Also assert internal periods remain in a multi-sentence developer result.

- [ ] **Step 2: Run `SmartInputCheck` and verify RED**

Run:

```bash
xcrun swiftc -parse-as-library -framework AppKit \
  native/Sources/Core/AppBrand.swift \
  native/Sources/Core/SmartInput/*.swift \
  native/Sources/Infrastructure/Diagnostics/LaunchDiagnostics.swift \
  native/Tests/SmartInputCheck.swift \
  -o /tmp/SmartInputCheck && /tmp/SmartInputCheck
```

Expected: FAIL because `.developerRequirement` still delivers the trailing period.

- [ ] **Step 3: Add and connect the minimal finalizer**

Implement:

```swift
static func finalize(_ text: String, mode: RewriteMode) -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard mode == .developerRequirement,
          let last = trimmed.last else {
        return trimmed
    }
    if last == "。" {
        return String(trimmed.dropLast())
    }
    if last == ".", !trimmed.hasSuffix("..") {
        return String(trimmed.dropLast())
    }
    return trimmed
}
```

In `SmartInputRouter`, replace the direct trimming of non-empty model output with:

```swift
let rewritten = SmartRewriteOutputSanitizer.finalize(
    output.text,
    mode: profile.mode
)
```

- [ ] **Step 4: Run delivery and prompt regressions**

Run the `SmartInputCheck` command above, then:

```bash
bash native/Tests/run_smart_rewrite_prompt_contract_checks.sh
bash native/Tests/SmartRewriteSystemPromptBoundaryCheck.sh
```

Expected: all checks pass.

- [ ] **Step 5: Commit deterministic delivery behavior**

```bash
git add native/Tests/SmartInputCheck.swift native/Sources/Core/SmartInput/SmartRewriteOutputSanitizer.swift native/Sources/Core/SmartInput/SmartInputRouter.swift
git commit -m "feat: omit developer rewrite final periods"
```

### Task 3: Multi-case local Qwen3 4B semantic replay

**Files:**
- Create: `native/Tests/DeveloperRequirementSemanticReplayCheck.swift`
- Create: `native/Tests/run_developer_requirement_semantic_replay.sh`

**Interfaces:**
- Consumes: managed runtime at `~/Library/Application Support/TypeWhale Pro/Runtimes/mlx-asr/v1/python/bin/python3`, local model at `~/Library/Application Support/TypeWhale Pro/Models/LLM/qwen3-4b-instruct-2507-4bit`, production prompt builder, router, normalizer, and output finalizer.
- Produces: `.artifacts/developer-requirement-semantic-replay/<timestamp>/result.md` and `result.json`, containing every source, output, TTFT, completion time, and failed invariant.

- [ ] **Step 1: Add the six-case replay suite**

Use these product cases:

```swift
[
    "两秒自动取消那个条不显不显示取消按钮，点击整条后取消它的位置正好跟胶囊是中心对齐的。",
    "你要确保他成功。",
    "这个颜色不太好看，然后分贝那里的颜色恢复以前，绿色镜框也恢复成以前分贝单位一样的颜色。",
    "第一，保存原始识别结果；第二，记录整理结果；第三，比较删减和意思变化；最后再决定是否修改提示词。",
    "取消按钮去掉，但提前按回车取消倒计时、防止再次发送的逻辑要继续保留。",
    "先检查 Combinite 三 ASR 的表现，不确定这个名称时保留原话，不要猜成其他模型。"
]
```

For each case, route through `.developerRequirement`, record worker metrics, and check no confirmation preface, no closing confirmation question, no final `。` / sentence `.`, no invented technical plan, plus case-specific anchors. The countdown case must contain cancel-button removal, whole-strip cancellation, and full center alignment; `水平中心对齐` alone is a failure.

- [ ] **Step 2: Compile and run three rounds**

Run:

```bash
bash native/Tests/run_developer_requirement_semantic_replay.sh --rounds 3
```

Expected: eighteen outputs, zero failed invariants, and a generated Markdown report.

- [ ] **Step 3: Iterate prompt only when evidence fails**

If a case fails, adjust only the relevant abstract rule in `.developerRequirement`; do not add the source sentence or expected answer to the production prompt. Re-run contract tests and all three replay rounds until every invariant passes.

**Evidence amendment:** Three prompt-only rounds consistently preserved the same adjacent negative-prefix restart. The production fix therefore adds the evidence-driven narrow `DeveloperRequirementDisfluencyCleaner`: it removes only an identical restarted CJK prefix and separates a repeated two-character action when a later “也” clause introduces a parallel object. Contrast tests prove ordinary `不听不信` and non-parallel commas remain unchanged.

- [ ] **Step 4: Commit the replay harness**

```bash
git add native/Tests/DeveloperRequirementSemanticReplayCheck.swift native/Tests/run_developer_requirement_semantic_replay.sh
git commit -m "test: replay developer requirement semantics"
```

### Task 4: Release records, build, install, and final verification

**Files:**
- Modify: `docs/开发日志.md`
- Modify: `native/Sources/Presentation/VersionHistory/VersionHistoryViewController.swift`
- Build-managed: `README.md`
- Build-managed: `macos/README.md`
- Build-managed: `native/build_native_app.sh`
- Build-managed: `docs/构建日志.md`

**Interfaces:**
- Consumes: all passing contract, router, sanitizer, and three-round replay evidence.
- Produces: the next unique TypeWhale Pro build installed at `/Applications/TypeWhale Pro.app`.

- [ ] **Step 1: Recheck concurrency and protected worktree state**

Run branch/status, build-process, and relevant-mtime checks. Stop rather than overlap any other build or unknown tracked edit. Keep `.artifacts/`, `.superpowers/`, capsule gallery, and capsule concepts untouched.

- [ ] **Step 2: Add release narrative**

Record the new developer semantic understanding, direct-output style, no-final-period behavior, exact-default migration, multi-round local-Qwen results, protected boundaries, and any remaining model limitations in the development log and in-app version history.

- [ ] **Step 3: Run the full focused regression set**

Run:

```bash
bash native/Tests/run_smart_rewrite_prompt_contract_checks.sh
bash native/Tests/SmartRewriteSystemPromptBoundaryCheck.sh
```

Compile and run `SmartInputCheck`, then re-run:

```bash
bash native/Tests/run_developer_requirement_semantic_replay.sh --rounds 3
```

Expected: all deterministic checks pass and all eighteen local model outputs have zero failed invariants.

- [ ] **Step 4: Build and install**

Run:

```bash
./native/build_and_log.sh
```

Expected: unique build increment, successful compile, overwrite install, app launch, and valid deep/strict signature.

- [ ] **Step 5: Verify installed version and commit release records**

Check installed `CFBundleVersion`, signature, process, `git diff --check`, and exact status scope. Commit only tracked task/build files:

```bash
git commit -m "chore: build semantic developer rewrite"
```

- [ ] **Step 6: Report product evidence**

Show the user all replay inputs and outputs grouped by round, timing, failed invariants, installed build, and a concise manual test path. Do not begin modifying other rewrite prompts in this task.
