# Short Utterance Effective Rewrite Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 Qwen3 4B 对存在口语问题的短句进行有效、克制的整理，同时保留原本准确的短句，并补齐疑问、笔记与正式陈述的回放验收。

**Architecture:** 保持现有 `SmartRewritePromptStore → SmartRewritePromptBuilder → 本地/在线整理引擎` 数据流不变。通过精简共享契约、增加原文后的短模式动作和强化真实模型回放判定改善 4B 行为，不新增运行时判断器或回退路径。

**Tech Stack:** Swift、Qwen3 4B MLX worker、现有可执行 Swift 契约测试、TypeWhale 原生构建脚本。

## Global Constraints

- 不修改 ASR、模型路由、失败不降级、粘贴、倒计时和自动发送。
- 不覆盖用户自定义模板。
- 不添加生产提示词固定答案示例。
- 不要求自然准确的短句必须改变。
- 所有智能整理仍只做信息转移，不回答、不建议、不执行。

---

### Task 1: Add failing product-quality replay checks

**Files:**
- Modify: `native/Tests/AllRewriteModesSemanticReplayCheck.swift`

**Interfaces:**
- Consumes: `SmartRewritePromptBuilder.prompt(rawText:mode:context:preference:)`
- Produces: `RewriteReplayCase` quality expectations for meaningful edits, list structure, natural formal wording, and preserved questions.

- [ ] **Step 1: Extend replay-case expectations**

Add `mustDifferFromSource`, `minimumListItems`, and case-specific forbidden awkward phrases. Add an awkward short utterance in developer-requirement and polish modes while retaining `你要确保他成功` as the clean-short control.

- [ ] **Step 2: Make the long summary remain a question/request**

Set the long summary case to require first-person question/request markers and reject impersonal forms such as `需排查`.

- [ ] **Step 3: Require multiple-point note structure**

For the “三件事” case, require at least three distinct bullet or numbered lines.

- [ ] **Step 4: Run the current three-round replay and observe RED**

Run:

```bash
./native/Tests/run_all_rewrite_modes_semantic_replay.sh --rounds 3
```

Expected: FAIL because the current prompt copies the awkward short utterance and/or loses question/list structure.

### Task 2: Refine prompt contracts for Qwen3 4B

**Files:**
- Modify: `native/Sources/Core/SmartInput/SmartRewritePromptBuilder.swift`
- Modify: `native/Sources/Core/SmartInput/SmartRewritePromptStore.swift`
- Modify: `native/Tests/SmartRewritePromptCheck.swift`
- Modify: `native/Tests/PromptFixtureCheck.swift`

**Interfaces:**
- Consumes: existing editable templates and `ModeContract.text(for:)`
- Produces: compact shared contract and a final mode action for every smart mode.

- [ ] **Step 1: Add failing deterministic prompt assertions**

Assert that the rendered prompt distinguishes meaningful short-sentence cleanup from artificial synonym changes, and that all seven smart modes have a non-empty final action after the raw text.

- [ ] **Step 2: Run contract tests and observe RED**

Run:

```bash
./native/Tests/run_smart_rewrite_prompt_contract_checks.sh
```

Expected: FAIL on the missing compact short-sentence action and missing non-developer mode contracts.

- [ ] **Step 3: Implement the compact shared contracts**

Remove duplicated no-answer wording while preserving the same product boundary. State explicitly that “保持一句” is structural, not an instruction to copy wording.

- [ ] **Step 4: Add concise mode-final actions**

Return a short final contract for developer statement, Commit, polish, note, chat, and exhaustive summary; tighten developer requirement without adding sample answers.

- [ ] **Step 5: Update default templates and exact legacy migration**

Replace ambiguous “short means minimal/no changes” wording with “correct clear oral defects when present, remain restrained when already natural”. Add each Build 845 default to its mode’s exact legacy set so customized text remains untouched.

- [ ] **Step 6: Run deterministic checks and observe GREEN**

Run:

```bash
./native/Tests/run_smart_rewrite_prompt_contract_checks.sh
```

Expected: all prompt contracts pass.

### Task 3: Validate against the real local model

**Files:**
- Modify if needed: `native/Tests/AllRewriteModesSemanticReplayCheck.swift`
- Output only: `.artifacts/all-rewrite-modes-semantic-replay/<timestamp>/result.md`

**Interfaces:**
- Consumes: installed Qwen3 4B MLX model and production prompt builder
- Produces: three-round product evidence with text and timing.

- [ ] **Step 1: Run the complete three-round replay**

Run:

```bash
./native/Tests/run_all_rewrite_modes_semantic_replay.sh --rounds 3
```

Expected: every case passes without fallback.

- [ ] **Step 2: Inspect every generated output**

Confirm exact-copy rejection only applies to awkward inputs; the clean control remains faithful; questions, list structure, names, numbers, negation, and first-person stance remain intact.

- [ ] **Step 3: Re-run deterministic regression checks**

Run:

```bash
./native/Tests/run_smart_rewrite_prompt_contract_checks.sh
```

Expected: all checks pass after any replay-driven prompt refinement.

### Task 4: Document, build, install, and commit

**Files:**
- Modify: `docs/开发日志.md`
- Modify: `native/Sources/Presentation/VersionHistory/VersionHistoryViewController.swift`
- Modified by build: version/build records and `docs/构建日志.md`

**Interfaces:**
- Consumes: passing contract and local-model replay results
- Produces: unique installed daily build and a scoped git commit.

- [ ] **Step 1: Record behavior and validation**

Add the root cause, prompt strategy, test coverage, model output evidence, unchanged boundaries, and manual test steps to the development log and version history.

- [ ] **Step 2: Recheck concurrency and repository scope**

Run branch/status/process/mtime checks again. Stop if overlapping work appears.

- [ ] **Step 3: Build and install**

Run:

```bash
./native/build_and_log.sh
```

Expected: build number increments from 845, the app installs to `/Applications/TypeWhale Pro.app`, launches, and passes signing verification.

- [ ] **Step 4: Verify installed version and final tests**

Check the installed `CFBundleVersion`, running process, signature, prompt contracts, and the final three-round replay report.

- [ ] **Step 5: Review and commit only owned files**

Run `git status --short` and `git diff --check`, stage only this task’s tracked files, and commit without touching protected untracked directories.
