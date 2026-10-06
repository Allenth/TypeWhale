# Developer Requirement Product Manager Role Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Redefine the developer-requirement prompt so it communicates as the user's product manager with limited product judgment, without semantic loss, invention, or role confusion.

**Architecture:** Keep the existing layered prompt builder. Put input isolation and factual fidelity in the global contracts, product-manager identity and judgment in the editable developer template, and only the non-overridable final behavior in `ModeContract`.

**Tech Stack:** Swift, Foundation, Qwen3 4B local managed LLM, shell-based Swift regression checks.

## Global Constraints

- Only `.developerRequirement` behavior changes.
- The model may surface product relationships already supported by the source, but may not invent facts, scenarios, technical solutions, acceptance numbers, or decisions.
- Existing untracked and unrelated working-tree files must not be staged or committed.
- Code changes require tests, build-number increment, installation to `/Applications/TypeWhale Pro.app`, launch, signature verification, documentation, and a scoped git commit.

---

### Task 1: Lock the product-manager prompt contract

**Files:**
- Modify: `native/Tests/SmartRewritePromptCheck.swift`
- Modify: `native/Sources/Core/SmartInput/SmartRewritePromptStore.swift`
- Modify: `native/Sources/Core/SmartInput/SmartRewritePromptBuilder.swift`

**Interfaces:**
- Consumes: `SmartRewritePromptStore.defaultTemplate(for:)` and `SmartRewritePromptBuilder.prompt(...)`
- Produces: a developer-requirement prompt with one role, bounded product judgment, and non-overlapping layer responsibilities

- [ ] Add assertions that the rendered prompt identifies the model as a product manager on the requirement owner's side, distinguishes product goals from implementation suggestions, preserves regression and phase signals, and forbids invented facts or solutions.
- [ ] Run `native/Tests/run_smart_rewrite_prompt_check.sh` and confirm the new assertions fail before implementation.
- [ ] Rewrite the default developer-requirement template as a complete role, judgment, and output contract instead of appending rules.
- [ ] Reduce the developer `ModeContract` to the minimum non-overridable final action without duplicating the full editable template.
- [ ] Run `native/Tests/run_smart_rewrite_prompt_check.sh` and confirm all checks pass.

### Task 2: Calibrate semantic behavior with local Qwen3 4B

**Files:**
- Modify: `native/Tests/DeveloperRequirementSemanticReplayCheck.swift`
- Output only: `.artifacts/developer-requirement-semantic-replay/<timestamp>/`

**Interfaces:**
- Consumes: the rendered developer-requirement prompt and installed local Qwen3 4B runtime
- Produces: recorded outputs and checks for direct action, regression feedback, investigation-only phases, implementation suggestions, complex requirements, uncertain terms, and prompt discussions

- [ ] Add compact replay cases that exercise the product-manager role and limited-judgment boundary.
- [ ] Run the existing semantic replay command discovered from the test header or repository scripts.
- [ ] Inspect every source/output pair for lost meaning, forgotten constraints, invented content, weakened judgment, third-person narration, and leaked prompt rules.
- [ ] Refine the prompt only when a failure is attributable to prompt behavior, then rerun the affected cases.

### Task 3: Document, build, install, and commit

**Files:**
- Modify: `docs/开发日志.md`
- Modify: `native/Sources/Presentation/VersionHistory/VersionHistoryViewController.swift`
- Modified by build tooling: version/build records and `docs/构建日志.md`

**Interfaces:**
- Consumes: verified source and replay results
- Produces: a uniquely numbered installed TypeWhale Pro build and a scoped git commit

- [ ] Record the product-visible prompt behavior and preserved boundaries in the development log and in-app version history before building.
- [ ] Recheck branch, status, build processes, target-file diffs, and mtimes.
- [ ] Run `./native/build_and_log.sh`; confirm compilation, build-number increment, installation, launch, code signature, and build log succeed.
- [ ] Run `git status --short` and inspect the complete scoped diff.
- [ ] Stage only this task's prompt, tests, documentation, version, and build-log files.
- [ ] Commit with a message describing the product-manager prompt redefinition.
