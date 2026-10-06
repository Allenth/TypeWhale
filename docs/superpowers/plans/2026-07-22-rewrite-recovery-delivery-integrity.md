# Rewrite, Recovery And Delivery Integrity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 阻止智能整理曲解原文、避免 Ollama 故障时打开桌面 App、彻底切断 UI 可见窗口与最终交付，并为长录音缓存缺失/重复建立可复现证据。

**Architecture:** 智能整理在 `SmartInputRouter` 的统一 Provider 出口增加确定性忠实度门；Ollama 恢复由无 GUI、单飞、带冷却的服务监督器负责；完整转录状态与 UI 投影使用不同合同，最终交付只接受完整状态；长录音先记录音频范围和所有权迁移，再调整 Reducer 合并算法。

**Tech Stack:** Swift 5、Foundation、AppKit、SenseVoice、Ollama HTTP/CLI、独立 Swift 回归检查、shell 边界测试。

## Global Constraints

- 只在主目录和 `codex/typewhale-pro-asr-hotwords` 分支开发，不创建 worktree。
- 每次只执行一个 Task；每个 Task 必须 RED → GREEN → 回归 → 更新本计划 → 独立提交。
- 保护未跟踪目录 `native/Helpers/CapsuleConceptGallery/` 与 `native/Sources/Presentation/Capsule/Concepts/`。
- UI 永不等待数据层；160 字限制只属于显示投影，不参与质量判断、整理、Final fallback 或粘贴。
- Final ASR 只有用户打开“停止后重新识别整段录音”时才执行。
- 智能整理失败、超时、不忠实或 Ollama 不可用时返回进入模型前的文本。
- 不使用第二次大模型判断忠实度；守卫必须是单次本地线性扫描。
- 日常验证按项目规则执行 install-only；不重新编译、不增加版本/build 号。代码改动测试通过后必须提交。
- 前三个实现提交完成后必须进行一次架构复审，再进入 Task 4。

---

### Task 1: Remove Prompt Contamination And Add Rewrite Fidelity Guard

**Files:**
- Create: `native/Sources/Core/SmartInput/RewriteFidelityGuard.swift`
- Create: `native/Tests/RewriteFidelityGuardCheck.swift`
- Modify: `native/Tests/SmartInputCheck.swift`
- Modify: `native/Tests/SmartRewriteSystemPromptBoundaryCheck.sh`
- Modify: `native/Sources/Core/SmartInput/SmartInputRouter.swift`
- Modify: `native/Sources/Core/SmartInput/SmartRewritePromptStore.swift`
- Modify: `native/Sources/Infrastructure/SmartRewrite/OllamaRewriteEngine.swift`
- Modify: `docs/开发日志.md`
- Modify: this plan

**Interfaces:**
- Produces: `RewriteFidelityGuard.evaluate(source:output:mode:) -> RewriteFidelityDecision`。
- Consumes: `rewriteText`（术语归一化后的模型输入）、模型输出和当前 `RewriteMode`。
- Failure semantics: `.reject(reason)` 时 `SmartInputRouter` 返回 `rewriteText`，`didFallback=true`，并记录 `rewrite_fidelity_rejected`。

- [x] **Step 1: Write RED for the reported contamination**

  `RewriteFidelityGuardCheck` 必须覆盖：

  ```swift
  reject(
      source: "你说的这个方案让架构师过一遍。",
      output: "我的表达内容没有被准确理解和妥善处理，沟通中还存在曲解。",
      mode: .developerRequirement
  )
  accept(
      source: "然然后我们继续测试这个方案。",
      output: "然后我们继续测试这个方案。",
      mode: .developerRequirement
  )
  accept(
      source: "为什么修复还没直接构建呢已经覆盖安装了吗",
      output: "为什么修复还没直接构建呢？已经覆盖安装了吗？",
      mode: .chat
  )
  reject when source contains `Ollama` / `35B` / `不要` and output drops those protected anchors.
  ```

- [x] **Step 2: Verify RED**

  Run a focused `swiftc` command containing `RewriteProfile.swift`, the new check and the not-yet-existing guard. Expected: compile failure because `RewriteFidelityGuard` does not exist.

- [x] **Step 3: Implement the linear guard**

  Normalize punctuation/whitespace once; scan source/output once to collect ASCII terms, numbers, strong constraint/negation tokens and CJK characters. Reject missing protected anchors. For `.chat` / `.polish` / `.developerRequirement`, reject only blatant divergence using conservative source-character coverage; make the short-text threshold stricter. Do not apply overlap rejection to `.note` / `.exhaustiveSummary` / `.codeCommit`; those modes still enforce protected anchors.

- [x] **Step 4: Wire the guard at the shared Router boundary**

  After model output sanitization and before constructing `SmartRewriteResult`, evaluate `rewriteText` against `rewritten`. A rejection returns `rewriteText`, sets fallback metadata, and records mode/provider/reason/counts without logging private text.

- [x] **Step 5: Remove contaminating prose examples**

  Remove the complete “主体不明参考” input/output triplet from `OllamaRewriteEngine.rewriteSystemPrompt`; retain the abstract rule that unspecified subjects must remain unspecified. Add a boundary assertion that the reported false output no longer occurs in any active system prompt.

- [x] **Step 6: Verify GREEN and regression**

  Run `RewriteFidelityGuardCheck`, `SmartInputCheck`, `SmartRewritePromptCheck`, `SmartRewriteSystemPromptBoundaryCheck.sh`, `OllamaRewriteEngineCheck`, and `git diff --check`. Expected: all pass.

- [x] **Step 7: Update records, install-only, and commit**

  Record the real WAV evidence and fallback contract in this plan and `docs/开发日志.md`; run `./native/build_and_log.sh`; verify signature and launch; stage only Task 1 files/build log; commit `fix: reject unfaithful smart rewrites`.

**Acceptance:**
- Reported WAV remains “你说的这个方案让架构师过一遍。” after an unrelated model response.
- Normal punctuation and stutter cleanup still passes.
- Guard adds no network/model call and logs measurable local decision time.

**Progress:** 2026-07-22 RED confirmed the guard type was absent, Router accepted the unrelated output, and active prompt checks found the exact leaked sentence in both the Ollama system prompt and exhaustive-summary template. GREEN adds a shared local guard, removes both copyable examples, preserves normal stutter/punctuation cleanup, and passes all focused checks. `./native/build_and_log.sh --install-only` 覆盖安装并验签现有 2.0.58 (803)；按项目规则未编译，因此真实功能验收等待下一次完整版本构建。

---

### Task 2: Restart Ollama Headlessly Without Opening The Desktop App

**Files:**
- Create: `native/Sources/Infrastructure/SmartRewrite/OllamaServiceSupervisor.swift`
- Create: `native/Tests/OllamaServiceSupervisorCheck.swift`
- Modify: `native/Sources/Infrastructure/SmartRewrite/OllamaRewriteEngine.swift`
- Modify: `native/Tests/OllamaRewriteEngineCheck.swift`
- Modify: `docs/开发日志.md`
- Modify: this plan

**Interfaces:**
- Produces: actor `OllamaServiceSupervisor.ensureReady(endpoint:model:reason:) async -> Bool`。
- Consumes: health probe, discovered Ollama CLI path, one supervised child process.
- Failure semantics: one request may trigger at most one start and one retry; failure enters cooldown and Router receives an error, therefore falls back to pre-model text.

- [x] **Step 1: Write RED lifecycle tests**

  Use injected health/start/clock functions to prove concurrent requests share one start, success retries once, failure enters cooldown, and no command contains `/usr/bin/open` or `-a Ollama`.

- [x] **Step 2: Verify RED**

  Compile/run the new supervisor check. Expected: failure because the supervisor does not exist and current recovery launches the GUI.

- [x] **Step 3: Implement the supervised headless start**

  Discover an executable CLI from `/opt/homebrew/bin/ollama`, `/usr/local/bin/ollama`, and `/Applications/Ollama.app/Contents/Resources/ollama`. Start `ollama serve` once, pipe and continuously drain stdout/stderr, retain only the PID started by TypeWhale, poll `/api/version`, and apply a bounded cooldown after failure.

- [x] **Step 4: Replace default GUI recovery**

  Route ordinary rewrite/translation recovery through the shared supervisor. Remove `open -gj -a Ollama`; keep screenshot translation’s existing passive behavior unchanged. Retry the original HTTP request once only after readiness succeeds.

- [x] **Step 5: Verify GREEN and regression**

  Run `OllamaServiceSupervisorCheck`, `OllamaRewriteEngineCheck`, selected-engine checks, and `git diff --check`. Fault test with service unavailable must show one headless start, no GUI activation, and original-text fallback if readiness fails.

- [x] **Step 6: Update records, install-only, and commit**

  Update plan/log, run install-only, inspect runtime logs for single start/cooldown, then commit `fix: recover ollama without opening its app`.

**Progress:** 2026-07-22 RED confirmed the supervisor contract did not exist and the old default recovery launched `/usr/bin/open -a Ollama`. The first concurrent test also exposed a stale-health race that could start twice; the actor now registers one shared readiness task before any awaited health check. GREEN adds CLI discovery, `ollama serve`, null-device stream draining, one owned process, readiness polling and 15-second failure cooldown. Default rewrite recovery uses it; screenshot translation remains passive. Supervisor, engine, both selected-engine checks and the source boundary check pass. Install-only cannot exercise newly edited source until the next full-version build, so runtime recovery validation remains deferred rather than claimed.

---

### Task 3: Remove UI Projection From Final Delivery Authority

**Files:**
- Create: `native/Sources/Domain/RealtimeTranscription/CompleteTranscriptSnapshot.swift`
- Modify: `native/Sources/Application/RealtimeTranscription/RealtimePreviewDeliveryCache.swift`
- Modify: `native/Sources/Application/RealtimeTranscription/ProductionRealtimePreviewDeliveryCache.swift`
- Modify: `native/Sources/Application/RealtimeTranscription/LegacyPreviewShadowAdapter.swift`
- Modify: `native/Sources/Application/FinalRecognitionUseCase.swift`
- Modify: `native/Sources/Application/FinalDeliveryUseCase.swift`
- Modify: `native/Sources/Application/SpeechInputCoordinator.swift`
- Modify: `native/Tests/RealtimePreviewDeliveryCacheCheck.swift`
- Modify: `native/Tests/FinalDeliveryUseCaseCheck.swift`
- Create: `native/Tests/VisiblePreviewDeliveryIsolationCheck.sh`
- Modify: `docs/ARCHITECTURE.md`
- Modify: `docs/开发日志.md`
- Modify: this plan

**Interfaces:**
- Produces: `CompleteTranscriptSnapshot` carrying full stable text, volatile tail, lifecycle, revision and source identity without any visible-character limit.
- UI consumes only `PreviewViewState` / `PreviewDisplaySnapshot` projections derived from complete state.
- Final delivery consumes only `RealtimePreviewDeliveryCache.deliverySnapshot()` built from `CompleteTranscriptSnapshot`.

**Code-walk addendum (before RED):** `FinalDeliveryUseCase` delegates the Final-ASR-off fallback to `FinalRecognitionUseCase`; the latter currently emits `realtime-preview-visible-cache`. Removing UI delivery authority therefore necessarily includes `FinalRecognitionUseCase`, while its Final-ASR-on empty/short result fallback will receive the complete cache text instead of UI text.

- [x] **Step 1: Write RED isolation tests**

  Assert a 500-character complete transcript projected to a 160-character UI tail still delivers all 500 characters. Assert `FinalDeliveryUseCase` contains no `realtime-preview-visible-cache` success path and no visible fallback text can become final output when Final ASR is off.

- [x] **Step 2: Verify RED**

  Run focused cache/final-delivery checks. Expected: failure because current cache consumes `PreviewDisplaySnapshot` and current final use case can select `realtime-preview-visible-cache`.

- [x] **Step 3: Introduce the complete-state contract**

  Move full stable/volatile/lifecycle data into `CompleteTranscriptSnapshot`. Project UI snapshots only after the complete cache has consumed the full state. Do not let view visibility limits flow backward into the contract.

- [x] **Step 4: Remove visible-cache delivery**

  Final ASR off: deliver the complete realtime cache when present; otherwise return explicit unavailable/partial state with however much the complete cache owns, never the UI tail. Final ASR on: whole-recording ASR remains authoritative and may fall back only to the complete realtime cache.

- [x] **Step 5: Verify GREEN and regression**

  Run cache, final-delivery, main-capsule projection, candidate/shadow isolation and unified-source boundary tests. Verify UI animation/render code is unchanged. Run `git diff --check`.

- [x] **Step 6: Update architecture, install-only, and commit**

  Record source-of-truth/projection boundary, install-only, then commit `refactor: isolate full transcript delivery from UI`.

**Progress:** 2026-07-22 code walk added the previously omitted `FinalRecognitionUseCase` dependency before RED. RED proved the delivery caches still accepted `PreviewDisplaySnapshot`, a 500-character full transcript had no complete-state contract, and Final-ASR-off could emit `realtime-preview-visible-cache`. GREEN introduces `CompleteTranscriptSnapshot`, gives production and legacy-adapter caches only that complete contract, and sends UI snapshots through their existing bridge separately. Final-ASR-off returns complete or partial cache text only; unavailable cache is explicit and never triggers Final ASR or visible-text substitution. Final-ASR-on may use only the complete cache as its empty/short safety net. Cache, final-recognition, final-delivery, candidate runtime, production bridge boundaries, three-capsule isolation, full tracked-source typecheck and `git diff --check` pass; no Presentation or animation source was modified. Install-only does not compile this source, so installed behavior awaits the next full-version build.

---

### Architecture Review Gate After Three Commits

- [x] Re-run architect review over the three commit diffs.
- [x] Confirm `RewriteFidelityGuard` is correctly isolated at the shared Router output and the complete delivery caches no longer accept UI projection types.
- [x] **Gate remediation A — close Ollama child ownership:** add explicit stop for the PID started by TypeWhale, clear/replace an unhealthy owned process, call the synchronous owned-process stop from `applicationWillTerminate`, and test failure/cooldown/shutdown lifecycle. Do not touch request routing or screenshot passive recovery. Commit separately.
- [x] **Gate remediation B — remove display text from voice gating:** experimental preview must store full `confirmedText + mutableTailText` as session evidence; `state.displayText` remains presentation-only. Add a boundary test proving `FinalSpeechGate` input cannot come from the 160-character projection. Do not change VAD policy, Final-ASR switch, 6/10/18 boundaries, stopTail or UI. Commit separately.
- [x] **Gate remediation C — fence app-exit recovery race:** app termination permanently closes the shared TypeWhale-owned process owner under the same lock used by `start`; a delayed recovery task can no longer start `ollama serve` after exit begins. External Ollama processes remain untouched.
- [x] Re-run the gate checks and confirm Task 4 may proceed.

**Review note:** the reviewer also requested a compile because the three changes used install-only. That request is rejected as inconsistent with the current repository rule: daily install uses the existing bundle without recompilation or build-number changes; only an explicit full-version/package action compiles. Source-level verification remains required and has passed, while installed behavior is correctly marked unverified until the next full-version build.

**Remediation A progress:** RED proved there was no stop dependency, shutdown API or app-exit hook. GREEN stops only the `Process` retained by TypeWhale before replacing an unhealthy child, stops it again after readiness failure before cooldown, clears it on termination, and synchronously terminates the owned child from `applicationWillTerminate`. Concurrent recovery, cooldown, explicit shutdown, no-GUI source boundary and one-request retry checks pass.

**Remediation B progress:** RED located the exact reverse dependency: `applyExperimentalPreviewState` assigned the Reducer's bounded `state.displayText` to `session.latestPreviewText`, which later feeds stop-time voice evidence. GREEN stores full `state.confirmedText` and `state.mutableTailText` in the session instead. The UI continues to receive the same bounded display projection. The new source boundary plus `FinalSpeechGateCheck` and `PreviewTranscriptReducerCheck` pass; VAD policy and all timing/finalization rules are unchanged.

**Remediation C progress:** final architecture review found one remaining exit race: `applicationWillTerminate` could stop the current child while a readiness task was still sleeping, allowing that task to start a new child afterward. RED reproduced the missing owner API. GREEN adds an irreversible shutdown flag guarded by the process-owner lock; exit atomically marks shutdown and detaches/terminates only the owned process, and every later `start` returns false. Supervisor, lifecycle, engine and no-GUI boundary checks pass. Task 4 may proceed.

---

### Task 4: Persist Long-Recording Ownership Evidence Before Changing Merge Logic

**Files:**
- Create: `native/Sources/Infrastructure/Diagnostics/RealtimeTranscriptTrace.swift`
- Modify: `native/Sources/Application/RealtimePreview/ExperimentalRealtimePreviewPipeline.swift`
- Modify: `native/Sources/Domain/RealtimeTranscription/PreviewTranscriptReducer.swift`
- Modify: `native/Sources/Application/SpeechInputCoordinator.swift`
- Create: `native/Tests/RealtimeTranscriptTraceCheck.swift`
- Modify: `native/Tests/PreviewTranscriptReducerCheck.swift`
- Modify: `docs/开发日志.md`
- Modify: this plan

**Interfaces:**
- Produces per-session JSONL diagnostics containing request ID, lane, chunk ID, absolute audio range, raw ASR text length/hash, confirmed/volatile lengths, replacement range, merge decision and final complete-cache length/hash.
- Diagnostic persistence is bounded, disabled from UI semantics, and never changes recognition/merge output.

**Code-walk addendum (before RED):** current production code already contains the earlier range-ownership repair: fast snapshots carry absolute `audioRange`; `promoteFastUnits(before:through:)` promotes fast-only prefixes before a correction takes ownership; `confirmFastChunks` removes only ranges covered by confirmation or the current correction. The remaining gap is evidence, not permission to redesign the merge. Task 4 will first expose a behavior-neutral Reducer ownership transition and persist it asynchronously. The historical 0–7s loss becomes a deterministic regression. Merge behavior changes only if a fixed-WAV replay produces a still-failing interval after this instrumentation.

- [x] **Step 1: Write RED trace-contract tests**

  Require absolute audio range and ownership transition fields for every fast/correction/stopTail merge. Require deterministic session ordering and bounded retention.

- [x] **Step 2: Verify RED**

  Run trace/reducer checks. Expected: failure because current evidence logs only lengths and does not persist exact ownership ranges and transitions. Production diagnostics must not persist transcript bodies by default; full text is permitted only for an explicit fixed-WAV developer replay.

- [x] **Step 3: Add diagnostics without changing merge behavior**

  Emit privacy-conscious hashes plus optional developer-mode text snapshots for the fixed WAV test. Keep writes off the realtime/UI critical queue and never wait for trace persistence.

- [x] **Step 4: Reproduce with the fixed two-minute WAV**

  Compare whole-file ASR against every range/merge decision. Identify exact missing, duplicated or replaced intervals; update this Task with the confirmed mechanism before any Reducer algorithm change.

- [x] **Step 5: Add the confirmed RED merge case**

  Convert the observed interval into a deterministic reducer test: correction may replace only the audio interval it covers; unowned fast-prefix/suffix text must remain; overlapping text must have one owner.

- [x] **Step 6: Implement the smallest ownership correction and verify**

  Modify only the confirmed merge point. Run reducer/scheduler/cache/final-delivery tests and replay the fixed WAV. Exit requires no missing interval, no duplicate interval, unchanged final tail, and no UI latency regression.

- [x] **Step 7: Update records, install-only, and commit**

  Record measured before/after counts and range evidence; install-only and commit `fix: preserve realtime transcript range ownership`.

**Progress:** 2026-07-22 RED proved there was no persisted range-transition contract and no exact final-cache completion hook. GREEN adds a behavior-neutral `PreviewOwnershipTransition` and an asynchronous bounded JSONL trace. Production records contain salted hashes and ranges, never transcript bodies; an explicit developer replay may authorize exactly one session. Architecture review initially rejected state capture and pre-cache final evidence; remediation now passes with no P0/P1. Fixed WAV `recording_20260721_223555_99B7BDF8.wav` replays as 129.657s: whole-file SenseVoice returns 751 characters and the current range-owned reducer returns 749, versus the historical 638-character cache. Trace shows five fast-only prefix promotions followed by covered-chunk removal, including the first `3.120–4.800s` promotion before `5.000–18.000s` confirmation. No uncovered speech interval or duplicate audio owner was found. Because the historical 113-character loss is no longer reproducible and remaining wording differences are model-context revisions, no additional merge behavior change is authorized. Focused reducer/trace/scheduler/stopTail/cache/final-delivery boundaries and full tracked-source typecheck pass. Install-only covered, opened and verified the existing signed 2.0.58 (803) bundle; per repository rule it does not compile this source, so installed trace validation waits for the next explicit full-version build.

## Final Acceptance

- The reported 3.4-second WAV is delivered faithfully even if the model emits the old prompt example.
- Stopping Ollama never opens its desktop UI; recovery is single-flight, headless and bounded.
- A 160-character capsule window can never truncate, validate or replace the full delivery text.
- The fixed two-minute recording has a reproducible range-by-range explanation before merge behavior changes.
- Final ASR switch semantics, capsule responsiveness, OpenClaw/闪念 paths and shortcut behavior remain unchanged.
