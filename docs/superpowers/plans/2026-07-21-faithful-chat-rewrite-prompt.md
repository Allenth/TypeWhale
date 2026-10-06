# Faithful Chat Rewrite Prompt Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the default chat rewrite prompt with a faithful modern-conversational cleanup contract that removes ASR noise without literary rewriting, answering, or inventing content.

**Architecture:** Keep the existing prompt boundary and routing unchanged. Modify only the `.chat` default template in `SmartRewritePromptStore`; retain `GlobalSafetyContract`, provider system prompts, custom-template persistence, recognition, cache, translation, and paste behavior.

**Tech Stack:** Swift, `SmartRewritePromptBuilder`, executable Swift regression checks, TypeWhale native build scripts.

## Global Constraints

- Work only in `$HOME/Pictures/macOSwinOSCoding/TypeSpeaker`; do not create a worktree.
- Default to minimal edits: preserve the user's wording, sentence order, person, attitude, and conversational intensity.
- Allow removal of stutters, duplicated fragments, meaningless fillers, obvious ASR errors, punctuation errors, and broken sentence boundaries.
- Forbid literary/classical, official-document, customer-service, marketing, summary, and invented-emotion rewrites.
- Do not modify recognition, caching, final paste, routing, provider prompts, other rewrite modes, or custom-template persistence.
- Code changes require tests, a daily compiled build/install, build-number increment, development-log update, and a scoped git commit.

---

### Task 1: Replace the default chat prompt with a faithful conversational contract

**Files:**
- Modify: `native/Tests/SmartRewritePromptCheck.swift`
- Modify: `native/Sources/Core/SmartInput/SmartRewritePromptStore.swift`
- Modify: `docs/开发日志.md`

**Interfaces:**
- Consumes: `SmartRewritePromptStore.defaultTemplate(for: .chat) -> String` and `SmartRewritePromptBuilder.prompt(rawText:mode:context:preference:) -> String`.
- Produces: a `.chat` default template containing explicit minimal-edit, modern-spoken-Chinese, uncertainty-preservation, no-auto-emoji, and positive/negative calibration rules.

- [x] **Step 1: Write the failing prompt-contract assertions**

  Replace the old `.chat` assertions with checks for these exact behavioral clauses:

  ```swift
  precondition(prompt.contains("以保留原句为默认，只做最少必要修改"))
  precondition(prompt.contains("使用现代日常口语，不要改成书面语、文言或半文半白"))
  precondition(prompt.contains("原句已经通顺时，不换句式、不替换用户常用词"))
  precondition(prompt.contains("只合并明确重复与自我修正"))
  precondition(prompt.contains("判断不准时保留原文"))
  precondition(prompt.contains("不要主动添加 emoji"))
  precondition(prompt.contains("此外，聊天提示词尚需优化，盖因其将我的表达润饰得过于文言"))
  precondition(!prompt.contains("按真实意图重组"))
  precondition(!prompt.contains("可以自然加入 1-2 个表情"))
  ```

- [x] **Step 2: Run the focused check and verify RED**

  Run:

  ```bash
  xcrun swiftc native/Sources/Core/AppBrand.swift native/Sources/Infrastructure/Diagnostics/LaunchDiagnostics.swift $(find native/Sources/Core/SmartInput -name '*.swift' | sort) native/Tests/SmartRewritePromptCheck.swift -o /tmp/SmartRewritePromptCheck && /tmp/SmartRewritePromptCheck
  ```

  Expected: the executable stops on the first new `.chat` assertion because the current default template does not contain the faithful-edit clause.

- [x] **Step 3: Replace only the `.chat` default template**

  Rewrite the `.chat` template around these exact sections and rules:

  ```text
  任务定位：忠实整理聊天口述，不创作另一种说法。
  修改边界：以保留原句为默认，只做最少必要修改；只修复口吃、重复、明显 ASR 错误、标点和断句。
  口吻边界：使用现代日常口语；保留“我觉得、可能、要不要”等有实际语气作用的表达；禁止文言、半文半白、正式公文、客服或营销口吻。
  不确定性：判断不准时保留原文，不猜测专有名词或重写整句。
  输出边界：不总结、不扩写、不代答、不增加 emoji；只输出整理后的消息。
  校准样例：包含同一句话的合格现代口语版本和不合格文言版本。
  ```

  Preserve `{developerGlossary}` and `{targetAppName}` placeholders. Do not change any other switch case.

- [x] **Step 4: Run the focused check and verify GREEN**

  Run the same command from Step 2.

  Expected: exit code `0`, with no precondition failure.

- [x] **Step 5: Review the scoped diff and update the development log**

  Confirm the diff changes only the `.chat` template, its assertions, this plan, and the development log. Record the root cause, protected boundaries, RED/GREEN evidence, and user-facing test phrases in `docs/开发日志.md`.

- [x] **Step 6: Compile, install, and smoke-check the real app**

  Run:

  ```bash
  ./native/build_and_log.sh
  ```

  Expected: current source compiles, `CFBundleVersion` increments, `/Applications/TypeWhale Pro.app` is replaced and opened, signature verification passes, and the build log is appended.

- [x] **Step 7: Commit the scoped change**

  Run `git status --short`, exclude the pre-existing untracked capsule concept directories, stage only the files listed by this task plus build-version/log files changed by the official build script, then commit with:

  ```bash
  git commit -m "fix: keep chat rewrites conversational"
  ```

## Acceptance Scenarios

- “好，我们再复审一下问题，没有问题的话就进行开发。” remains everyday speech and must not become “若无异议，则着手开发”。
- “你现在用通俗的话语语讲述一下下目前……” removes duplicate syllables and repairs punctuation without changing the request into a summary.
- “为什么修复还没直接构建呢？已经覆盖安装了吗？” remains a question and is never answered.
- Technical names such as `Ollama`, `Final ASR`, and `Mimo` remain unchanged.
- Existing custom chat templates remain selected and are not overwritten by the new default.

---

### Task 2: Make mechanical speech-noise cleanup mandatory for small local models

**Status:** In progress after installed Build 802 showed that Qwen3.5 2B stayed conversational but copied obvious repetitions.

**Evidence:** Build 802 log records `mode=聊天`, `model=qwen3.5:2b-mlx`, `rawText_length=151`; the output retained `hello hello`, `然然后`, `不再不跟`, and repeated location wording. Routing is correct; the prompt priority is insufficiently explicit for the small local model.

**Files:**
- Modify: `native/Tests/SmartRewritePromptCheck.swift`
- Modify: `native/Sources/Core/SmartInput/SmartRewritePromptStore.swift`
- Modify: `docs/开发日志.md`
- Modify: `native/Sources/Presentation/VersionHistory/VersionHistoryViewController.swift`

**Interfaces:**
- Consumes: the Task 1 faithful `.chat` template.
- Produces: an explicit mandatory-cleanup priority plus one complete trip-planning calibration sample; no deterministic text processor and no change outside `.chat`.

- [x] **Step 1: Add failing assertions**

  Require the generated chat prompt to contain:

  ```swift
  precondition(prompt.contains("最少修改不等于原样照搬"))
  precondition(prompt.contains("以下明显语音噪声必须清理"))
  precondition(prompt.contains("hello hello → hello"))
  precondition(prompt.contains("然然后 → 然后"))
  precondition(prompt.contains("不再不跟他们一块逛街 → 不跟他们一块逛街"))
  precondition(prompt.contains("白天基本上就在南山那边"))
  precondition(prompt.contains("人物关系不明确，保留原文，不自行拆分或改写"))
  ```

- [x] **Step 2: Verify RED**

  Run the focused `SmartRewritePromptCheck` command from Task 1. Expected: failure at the first new mandatory-cleanup assertion.

- [x] **Step 3: Add one narrow prompt priority and calibration sample**

  Add a mandatory cleanup block before the minimal-edit boundary:

  ```text
  最少修改不等于原样照搬。连续重复词、叠字口吃、上下文明确的重复否定、相邻重复意思必须清理；清理后再保持其余原句不动。
  ```

  Add the reported trip-planning input and a minimally cleaned expected output. Preserve the ambiguous phrase `我爸和我二大爷妹妹他们` exactly and state that unclear people/relationships must not be guessed.

- [x] **Step 4: Verify GREEN and protected boundaries**

  Run `SmartRewritePromptCheck` and `git diff --check`. Confirm no changes to routing, model settings, ASR, cache, paste, or other rewrite-mode templates.

- [x] **Step 5: Update records, compile Build 803, install, and commit**

  Update development log and in-app version history, run `./native/build_and_log.sh`, verify installed version/hash/signature/process, then commit only this task and build-record files. Leave capsule concept directories untouched.
