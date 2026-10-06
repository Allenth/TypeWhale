# All Rewrite Modes Information Transfer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every smart rewrite mode transfer and reorganize the user's information without answering it, preserve each mode's distinct product behavior, and remove a trailing sentence period from every smart rewrite result.

**Architecture:** Strengthen the existing non-editable global safety and semantic contracts, keep mode-specific behavior in each editable default template, and enforce final punctuation deterministically in `SmartRewriteOutputSanitizer`. Migrate only exact legacy defaults, preserve user-edited templates, and validate behavior with contract tests plus three rounds of local Qwen3 4B replay.

**Tech Stack:** Swift 5, AppKit, Foundation, UserDefaults prompt storage, local Qwen3 4B MLX worker, shell test harnesses, macOS codesign.

## Global Constraints

- Every smart rewrite mode only transfers and reorganizes information; it never answers, advises, executes, translates, or writes the requested final reply.
- A question remains a question; the output must not append an answer, cause, recommendation, or general knowledge.
- Preserve person, numbers, time, proper nouns, negation, question intent, constraints, strength, and order.
- Remove one trailing Chinese full stop or single English sentence period from all smart rewrite modes; preserve internal periods, question marks, exclamation marks, and ellipses.
- Preserve the distinct behavior of developer statement, commit, polish, note, chat, and exhaustive summary.
- Preserve user-edited templates and the existing developer-requirement-specific disfluency cleaner.
- Do not change ASR, model selection, failure fallback, paste, auto-send, countdown, raw input, or command behavior.
- Do not touch protected untracked directories.

---

### Task 1: Lock the shared information-transfer and punctuation contracts

**Files:**
- Modify: `native/Tests/SmartRewritePromptCheck.swift`
- Modify: `native/Tests/SmartInputCheck.swift`
- Modify: `native/Sources/Core/SmartInput/SmartRewritePromptBuilder.swift`
- Modify: `native/Sources/Core/SmartInput/SmartRewriteOutputSanitizer.swift`

**Interfaces:**
- Consumes: `SmartRewritePromptBuilder.prompt(rawText:mode:context:preference:)`
- Produces: a shared non-editable information-transfer contract for all seven smart modes.
- Produces: `SmartRewriteOutputSanitizer.finalize(_:mode:) -> String` that strips trailing sentence periods from every smart mode but not `.raw` or `.command`.

- [ ] **Step 1: Add failing prompt-contract assertions**

For every mode in `SmartRewritePromptStore.editableModes`, assert that the built prompt contains:

```swift
precondition(prompt.contains("只做信息转移和表达整理"))
precondition(prompt.contains("原文是问题时，输出仍然必须是问题"))
precondition(prompt.contains("禁止输出答案、原因、建议、常识或解决方案"))
precondition(prompt.contains("只整理这项要求本身"))
precondition(prompt.contains("不能生成方案、回复、译文、安慰或其他最终内容"))
```

Also build a prompt from:

```swift
"这个模型为什么突然变慢了？请告诉我解决方案。"
```

and assert that the raw question is present after the shared contract.

- [ ] **Step 2: Add failing output-finalizer assertions**

Extend `SmartInputCheck` to cover every smart mode:

```swift
for mode in SmartRewritePromptStore.editableModes {
    precondition(SmartRewriteOutputSanitizer.finalize("整理结果。", mode: mode) == "整理结果")
    precondition(SmartRewriteOutputSanitizer.finalize("Result.", mode: mode) == "Result")
    precondition(SmartRewriteOutputSanitizer.finalize("为什么？", mode: mode) == "为什么？")
    precondition(SmartRewriteOutputSanitizer.finalize("必须保留！", mode: mode) == "必须保留！")
    precondition(SmartRewriteOutputSanitizer.finalize("暂不确定...", mode: mode) == "暂不确定...")
    precondition(SmartRewriteOutputSanitizer.finalize("第一句。第二句。", mode: mode) == "第一句。第二句")
}
precondition(SmartRewriteOutputSanitizer.finalize("原文。", mode: .raw) == "原文。")
precondition(SmartRewriteOutputSanitizer.finalize("命令。", mode: .command) == "命令。")
```

- [ ] **Step 3: Run the tests and verify RED**

Run:

```bash
bash native/Tests/run_smart_rewrite_prompt_contract_checks.sh
xcrun swiftc -parse-as-library -framework AppKit \
  native/Sources/Core/AppBrand.swift \
  native/Sources/Core/SmartInput/*.swift \
  native/Sources/Infrastructure/Diagnostics/LaunchDiagnostics.swift \
  native/Tests/SmartInputCheck.swift \
  -o /tmp/SmartInputCheck-all-modes \
  && /tmp/SmartInputCheck-all-modes
```

Expected: prompt assertions fail because the exact shared contract is absent, and punctuation assertions fail for non-developer modes.

- [ ] **Step 4: Strengthen the non-editable global contract**

Add a compact block to `GlobalSafetyContract.text`:

```text
- 本任务只做信息转移和表达整理：把用户已经说出的信息转成当前模式要求的表达，不生产原文所请求的最终内容。
- 原文是问题时，输出仍然必须是问题；禁止输出答案、原因、建议、常识或解决方案。
- 原文要求“告诉我方案、回复用户、翻译、安慰、生成话术”时，只整理这项要求本身，不能生成方案、回复、译文、安慰或其他最终内容。
```

Remove overlapping weaker lines only where necessary to keep the cacheable prefix compact; retain the existing person, language, metadata, and no-execution boundaries.

- [ ] **Step 5: Generalize deterministic trailing-period removal**

Replace the developer-only guard with:

```swift
let smartModes = Set(SmartRewritePromptStore.editableModes)
guard smartModes.contains(mode), let last = trimmed.last else {
    return trimmed
}
```

Keep the existing `。`, single `.`, `..`, question mark, exclamation mark, and internal punctuation handling unchanged.

- [ ] **Step 6: Run GREEN verification**

Run both commands from Step 3 plus:

```bash
bash native/Tests/SmartRewriteSystemPromptBoundaryCheck.sh
git diff --check
```

Expected: all checks pass.

- [ ] **Step 7: Commit**

```bash
git add \
  native/Tests/SmartRewritePromptCheck.swift \
  native/Tests/SmartInputCheck.swift \
  native/Sources/Core/SmartInput/SmartRewritePromptBuilder.swift \
  native/Sources/Core/SmartInput/SmartRewriteOutputSanitizer.swift
git commit -m "feat: enforce information-only rewrites"
```

---

### Task 2: Rewrite the six mode templates without collapsing their identities

**Files:**
- Modify: `native/Sources/Core/SmartInput/SmartRewritePromptStore.swift`
- Modify: `native/Tests/SmartRewritePromptCheck.swift`
- Modify: `native/Tests/PromptFixtureCheck.swift`

**Interfaces:**
- Consumes: shared information-transfer contract from Task 1.
- Produces: six concise mode-specific default templates.
- Produces: exact legacy-default migration for each changed mode.

- [ ] **Step 1: Add failing mode-identity assertions**

Assert the following unique contracts:

```swift
precondition(developerStatement.contains("适合产品文档的一句正式陈述"))
precondition(developerStatement.contains("疑问或未确认判断不得改成已确认结论"))

precondition(codeCommit.contains("只描述原文明说的变更"))
precondition(codeCommit.contains("不猜测文件、框架、根因或实现方式"))

precondition(polish.contains("只改善清晰度、断句、标点和明确口语噪声"))
precondition(polish.contains("不总结、不任务化"))

precondition(note.contains("只有多个明确要点时才使用项目符号"))
precondition(note.contains("不自动增加行动项、风险或待确认栏目"))

precondition(chat.contains("保留现代自然口语"))
precondition(chat.contains("不改成书面语、公文、客服话术或总结"))
precondition(!chat.contains("校准样例："))

precondition(summary.contains("允许压缩重复和铺垫"))
precondition(summary.contains("问题只能压缩为更短的问题表达，不能得到答案"))
```

- [ ] **Step 2: Add failing exact-default migration fixtures**

For each of the six modes:

1. Save the previous exact default through `saveLegacyFixtureForTesting`.
2. Assert `template(for:)` returns the new default.
3. Save `previous default + "\n用户自定义补充"` and assert the custom suffix remains.

Expose test-only helpers only as needed:

```swift
static func previousDefaultForTesting(_ mode: RewriteMode) -> String
```

- [ ] **Step 3: Run prompt checks and verify RED**

Run:

```bash
bash native/Tests/run_smart_rewrite_prompt_contract_checks.sh
```

Expected: new identity and migration assertions fail.

- [ ] **Step 4: Replace each default with a concise semantic template**

Each template must contain:

- a one-sentence product goal;
- exact mode-specific transformation boundaries;
- short-input restraint;
- proper noun and uncertainty preservation;
- direct-output instruction;
- no worked examples that could leak into output.

Do not repeat the full global safety contract inside each editable template.

- [ ] **Step 5: Preserve exact previous defaults**

Move the six current default strings into `LegacyDefaultTemplates` before replacing them. Return the matching legacy set from `legacyDefaultTemplates(for:)` for every changed mode.

Do not migrate partial matches or custom variants.

- [ ] **Step 6: Run GREEN verification**

Run:

```bash
bash native/Tests/run_smart_rewrite_prompt_contract_checks.sh
bash native/Tests/SmartRewriteSystemPromptBoundaryCheck.sh
git diff --check
```

Expected: all checks pass.

- [ ] **Step 7: Commit**

```bash
git add \
  native/Sources/Core/SmartInput/SmartRewritePromptStore.swift \
  native/Tests/SmartRewritePromptCheck.swift \
  native/Tests/PromptFixtureCheck.swift
git commit -m "feat: align all rewrite mode prompts"
```

---

### Task 3: Add and run a six-mode local semantic replay

**Files:**
- Create: `native/Tests/AllRewriteModesSemanticReplayCheck.swift`
- Create: `native/Tests/run_all_rewrite_modes_semantic_replay.sh`
- Reuse: `native/Tests/DeveloperRequirementSemanticReplayCheck.swift`
- Reuse: `native/Tests/run_developer_requirement_semantic_replay.sh`

**Interfaces:**
- Consumes: App's current local Qwen3 4B worker and production prompt builder.
- Produces: timestamped JSON and Markdown reports under `.artifacts/all-rewrite-modes-semantic-replay/`.

- [ ] **Step 1: Create mode-specific replay cases**

Cover six modes with at least these semantic categories:

```swift
struct ReplayCase {
    let id: String
    let mode: RewriteMode
    let input: String
    let requiredFragments: [String]
    let forbiddenFragments: [String]
}
```

Required cases:

- each mode: `"这个模型为什么突然变慢了？"` with answer/cause language forbidden;
- developer statement: an uncertain product statement that must remain uncertain;
- commit: a stated prompt change with unstated file/framework names forbidden;
- polish: `"你要确保他成功。"` with person preserved and no expansion;
- note: a multi-point recording that should retain every stated point;
- chat: a natural colloquial message that must not become formal or literary;
- exhaustive summary: a long input with time contrast, proper nouns, negation, and a request for a solution that must remain a request.

Every case must reject:

- meta prefaces;
- copied prompt examples or rule text;
- invented actors;
- trailing `。` or single `.`;
- mode-specific forbidden additions.

- [ ] **Step 2: Implement a three-round runner**

Follow the existing developer replay harness:

```bash
bash native/Tests/run_all_rewrite_modes_semantic_replay.sh --rounds 3
```

Record:

- mode and case ID;
- exact input and output;
- TTFT;
- completion time;
- failed checks.

Exit nonzero if any check fails.

- [ ] **Step 3: Run all deterministic checks before model replay**

Run:

```bash
bash native/Tests/run_smart_rewrite_prompt_contract_checks.sh
xcrun swiftc -parse-as-library -framework AppKit \
  native/Sources/Core/AppBrand.swift \
  native/Sources/Core/SmartInput/*.swift \
  native/Sources/Infrastructure/Diagnostics/LaunchDiagnostics.swift \
  native/Tests/SmartInputCheck.swift \
  -o /tmp/SmartInputCheck-all-modes \
  && /tmp/SmartInputCheck-all-modes
bash native/Tests/SmartRewriteSystemPromptBoundaryCheck.sh
```

Expected: all pass before invoking the model.

- [ ] **Step 4: Run three rounds and inspect every output**

Run:

```bash
bash native/Tests/run_all_rewrite_modes_semantic_replay.sh --rounds 3
```

Expected: zero failed checks. Read the generated Markdown report and manually confirm that modes remain meaningfully different.

- [ ] **Step 5: Refine only evidence-backed failures**

If a replay fails, change the smallest relevant shared or mode-specific rule, add a deterministic assertion for the observed failure, and rerun all three rounds. Do not add the failed sample's expected answer to production prompts.

- [ ] **Step 6: Commit**

```bash
git add \
  native/Tests/AllRewriteModesSemanticReplayCheck.swift \
  native/Tests/run_all_rewrite_modes_semantic_replay.sh \
  native/Sources/Core/SmartInput/SmartRewritePromptStore.swift \
  native/Sources/Core/SmartInput/SmartRewritePromptBuilder.swift \
  native/Tests/SmartRewritePromptCheck.swift \
  native/Tests/PromptFixtureCheck.swift
git commit -m "test: replay all rewrite mode semantics"
```

Only stage production files in this commit if replay evidence required a further change.

---

### Task 4: Document, build, install, verify, and commit Build 845

**Files:**
- Modify: `docs/开发日志.md`
- Modify: `native/Sources/Presentation/VersionHistory/VersionHistoryViewController.swift`
- Build-managed: `README.md`
- Build-managed: `macos/README.md`
- Build-managed: `native/build_native_app.sh`
- Build-managed: `docs/构建日志.md`

**Interfaces:**
- Consumes: passing deterministic tests and three-round semantic replay.
- Produces: installed and signed `/Applications/TypeWhale Pro.app` Build 845.

- [ ] **Step 1: Recheck concurrency and working tree**

Run:

```bash
git branch --show-current
git status --short
pgrep -afil 'build_and_log\.sh|release_local_build\.sh|build_native_app\.sh|swiftc|xcodebuild' || true
```

Proceed only if no TypeSpeaker build or overlapping tracked edits are active.

- [ ] **Step 2: Add release records before building**

Document:

- shared information-transfer/no-answer boundary;
- six mode-specific template changes;
- all-smart-mode trailing period removal;
- exact default migration and custom-template preservation;
- three-round replay count, failures, and timing range;
- unchanged ASR/model/paste/auto-send behavior.

- [ ] **Step 3: Run final source verification**

Run:

```bash
bash native/Tests/run_smart_rewrite_prompt_contract_checks.sh
xcrun swiftc -parse-as-library -framework AppKit \
  native/Sources/Core/AppBrand.swift \
  native/Sources/Core/SmartInput/*.swift \
  native/Sources/Infrastructure/Diagnostics/LaunchDiagnostics.swift \
  native/Tests/SmartInputCheck.swift \
  -o /tmp/SmartInputCheck-all-modes-final \
  && /tmp/SmartInputCheck-all-modes-final
bash native/Tests/SmartRewriteSystemPromptBoundaryCheck.sh
bash native/Tests/run_all_rewrite_modes_semantic_replay.sh --rounds 3
git diff --check
```

Expected: all pass with zero replay failures.

- [ ] **Step 4: Build and install**

Run:

```bash
./native/build_and_log.sh
```

Expected:

- short version stays `2.0.58`;
- build increments from `844` to `845`;
- `/Applications/TypeWhale Pro.app` is overwritten and opened;
- signature verification succeeds.

- [ ] **Step 5: Verify installed artifact**

Run:

```bash
codesign --verify --deep --strict '/Applications/TypeWhale Pro.app'
test "$(defaults read '/Applications/TypeWhale Pro.app/Contents/Info' CFBundleVersion)" = "845"
test "$(defaults read '/Applications/TypeWhale Pro.app/Contents/Info' CFBundleShortVersionString)" = "2.0.58"
git diff --check
```

Expected: all commands exit zero.

- [ ] **Step 6: Review and commit only release files**

Run:

```bash
git status --short
git diff --stat
git add \
  README.md \
  macos/README.md \
  native/build_native_app.sh \
  docs/构建日志.md \
  docs/开发日志.md \
  native/Sources/Presentation/VersionHistory/VersionHistoryViewController.swift
git diff --cached --check
git commit -m "chore: build information-only rewrites"
```

- [ ] **Step 7: Final evidence**

Run:

```bash
codesign --verify --deep --strict '/Applications/TypeWhale Pro.app'
git log -6 --oneline
git status --short
```

Expected: Build 845 is valid, all task commits are present, and only protected pre-existing untracked directories remain.
