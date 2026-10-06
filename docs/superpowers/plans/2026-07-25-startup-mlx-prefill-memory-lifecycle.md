# Qwen Startup Prefill and Memory Lifecycle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the first real Qwen rewrite reuse a startup-built prompt prefix while monitoring the main app and owned MLX Worker as one memory footprint.

**Architecture:** Reuse the existing rewrite protocol for a private placeholder prefill so the Worker follows its already-tested cache path. Keep prompt ownership in the local engine/service, expose the owned Worker PID read-only, and let the coordinator apply lifecycle and memory-pressure policy.

**Tech Stack:** Swift 6/AppKit, Foundation `Process`, Darwin `proc_pid_rusage`, Python 3, MLX/MLX-LM, unittest.

## Global Constraints

- Only prefill when Qwen is selected, the managed model/runtime are ready, and physical memory is at least 16GB.
- Prefill contains no user text and produces no UI, paste, history, or disk record.
- DeepSeek switching, sleep, shutdown, cancellation, and prompt-token exact matching remain authoritative.
- ASR/VAD high-memory flush and immediate reload behavior must not change.
- Use the existing project workspace and protect unrelated untracked capsule-concept files.

---

### Task 1: Startup Prompt Prefill Request

**Files:**
- Modify: `native/Sources/Infrastructure/SmartRewrite/TypeWhaleLocalLLMEngine.swift`
- Modify: `native/Sources/Application/SpeechInputCoordinator.swift`
- Create: `native/Tests/ManagedMLXLLMPrefillCheck.swift`
- Modify: `native/Tests/benchmark_managed_mlx_prefix_cache.py`

**Interfaces:**
- Consumes: `ManagedLLMRuntime.perform(_:)`, `SmartRewriteSafetyPrompt.rewriteSystemPrompt(lead:)`, `ManagedLLMModelRegistry.readiness(for:)`.
- Produces: `ManagedLLMRuntimeService.prefillRewritePrefix(modelID:) async throws -> ManagedMLXLLMResponse`.

- [ ] **Step 1: Write the failing Swift and real-worker checks**

Create a check that captures the service request and asserts:

```swift
precondition(request.command == .rewrite)
precondition(request.systemPrompt == TypeWhaleLocalLLMEngine.rewriteSystemPrompt)
precondition(request.userPrompt == ManagedLLMRuntimeService.prefillPlaceholder)
precondition(request.maxTokens == ManagedLLMRuntimeService.prefillMaxTokens)
```

Extend the benchmark to send the same placeholder request after `warmup`, then assert the first real rewrite has:

```python
assert first["metrics"]["prompt_cache_hit"] is True
assert first["metrics"]["prompt_tokens_evaluated"] < first["metrics"]["prompt_tokens"]
```

- [ ] **Step 2: Run checks and verify RED**

Run the Swift check with the project’s existing source list and run:

```bash
python3 native/Tests/benchmark_managed_mlx_prefix_cache.py
```

Expected: Swift compile fails because the prefill API is absent; benchmark fails because the first real request is still a cache miss.

- [ ] **Step 3: Implement the minimal prefill API**

Expose the existing Qwen rewrite system prompt as one internal static value and add:

```swift
static let prefillPlaceholder = "[[TYPEWHALE_STARTUP_PREFILL]]"
static let prefillMaxTokens = 8

func prefillRewritePrefix(
    modelID: ManagedLLMModelID
) async throws -> ManagedMLXLLMResponse
```

The method must validate model readiness, send one `.rewrite` request, discard `finalText`, and return metrics only for logging.

- [ ] **Step 4: Connect startup prefill**

After the existing `.warmup` response, call `prefillRewritePrefix`. Gate the task with:

```swift
MemoryMonitor.totalPhysicalMemoryMB >= 16 * 1024
```

Log `managed_mlx prefill_done` with cache metrics; failure remains non-fatal.

- [ ] **Step 5: Verify GREEN**

Run the Swift check, Python worker unit tests, managed MLX compaction test, and real Qwen benchmark. Expected: first real rewrite is a cache hit and unique fixture text remains isolated.

- [ ] **Step 6: Commit**

```bash
git add native/Sources/Infrastructure/SmartRewrite/TypeWhaleLocalLLMEngine.swift native/Sources/Application/SpeechInputCoordinator.swift native/Tests/ManagedMLXLLMPrefillCheck.swift native/Tests/benchmark_managed_mlx_prefix_cache.py
git commit -m "perf: prefill Qwen rewrite prompt at startup"
```

### Task 2: Owned Worker Footprint

**Files:**
- Modify: `native/Sources/Infrastructure/Diagnostics/MemoryMonitor.swift`
- Modify: `native/Sources/Infrastructure/SmartRewrite/ManagedMLXLLMRuntime.swift`
- Create: `native/Tests/ManagedWorkerMemoryFootprintCheck.swift`

**Interfaces:**
- Produces: `MemoryMonitor.footprintBytes(processID: pid_t) -> UInt64`.
- Produces: `ManagedMLXLLMRuntime.ownedProcessIdentifier: pid_t?`.

- [ ] **Step 1: Write the failing footprint check**

Start the fake Worker, obtain its PID, and assert:

```swift
precondition(runtime.ownedProcessIdentifier != nil)
precondition(MemoryMonitor.footprintBytes(processID: pid) > 0)
```

After `runtime.stop()`, assert the PID is nil.

- [ ] **Step 2: Run and verify RED**

Expected: compile fails because both APIs are absent.

- [ ] **Step 3: Implement PID and footprint reading**

Expose only the PID under the runtime state lock. Use Darwin `proc_pid_rusage` with `rusage_info_v4` and return `ri_phys_footprint`; return zero for missing/exited processes.

- [ ] **Step 4: Verify GREEN**

Run `ManagedWorkerMemoryFootprintCheck` and the existing `ManagedMLXLLMRuntimeCheck`. Expected: both pass, including cancellation and stop cleanup.

- [ ] **Step 5: Commit**

```bash
git add native/Sources/Infrastructure/Diagnostics/MemoryMonitor.swift native/Sources/Infrastructure/SmartRewrite/ManagedMLXLLMRuntime.swift native/Tests/ManagedWorkerMemoryFootprintCheck.swift
git commit -m "feat: measure managed MLX worker memory"
```

### Task 3: Lifecycle and High-Memory Policy

**Files:**
- Modify: `native/Sources/Application/SpeechInputCoordinator.swift`
- Create: `native/Sources/Application/ManagedLLMLifecyclePolicy.swift`
- Create: `native/Tests/ManagedLLMLifecyclePolicyCheck.swift`

**Interfaces:**
- Consumes: main footprint, Worker footprint, selected provider, idle state, and current time.
- Produces: `ManagedLLMLifecyclePolicy.evaluate(_:) -> ManagedLLMLifecycleAction`.

- [ ] **Step 1: Write failing policy tests**

Cover these table cases:

```swift
safe + selected + cold       -> .prewarm
high + selected + running    -> .stopForMemory
high + selected + cold       -> .none
safe before cooldown expiry  -> .none
safe after cooldown expiry   -> .prewarm
DeepSeek selected            -> .none
```

- [ ] **Step 2: Run and verify RED**

Expected: compile fails because the policy types are absent.

- [ ] **Step 3: Implement the pure policy**

Use a 30-second recovery cooldown and a 75% recovery threshold. Keep this file free of AppKit, Worker, and UI dependencies.

- [ ] **Step 4: Wire combined memory**

In the idle memory check, calculate:

```swift
let totalMemoryMB = MemoryMonitor.currentFootprintMB
    + ManagedLLMRuntimeService.shared.workerFootprintMB
```

Stop Qwen when the combined value is high. Do not immediately prewarm; let the policy recover after cooldown. Keep the existing ASR `nativeASR.reload()` path unchanged.

- [ ] **Step 5: Restore after cancellation**

When a real Qwen request is cancelled, mark the Worker cold and schedule one policy-governed prewarm after the workflow returns idle.

- [ ] **Step 6: Verify GREEN**

Run policy, runtime, prompt prefill, memory, and existing ASR memory boundary checks. Expected: no immediate stop/prewarm loop and ASR still reloads immediately.

- [ ] **Step 7: Commit**

```bash
git add native/Sources/Application/ManagedLLMLifecyclePolicy.swift native/Sources/Application/SpeechInputCoordinator.swift native/Tests/ManagedLLMLifecyclePolicyCheck.swift
git commit -m "fix: govern Qwen worker memory lifecycle"
```

### Task 4: Release Verification

**Files:**
- Modify: `docs/开发日志.md`
- Modify: `native/Sources/Presentation/VersionHistory/VersionHistoryViewController.swift`
- Generated by build: `README.md`, `macos/README.md`, `docs/构建日志.md`, `native/build_native_app.sh`

- [ ] **Step 1: Update Build 828 release narrative**

Record startup prefill, combined memory monitoring, cancellation recovery, exact automated checks, and any physical paths not verified.

- [ ] **Step 2: Run the full targeted suite**

Run all new checks, existing managed MLX protocol/runtime tests, worker tests, cache compaction test, and installed-worker benchmark.

- [ ] **Step 3: Build and install**

After the required concurrency check, run:

```bash
./native/build_and_log.sh
```

Expected: `2.0.58 (828)` installed, launched, and signed.

- [ ] **Step 4: Verify the installed artifact**

Confirm Info.plist, deep/strict signature, running executable, source/package Worker SHA-256 equality, startup `prefill_done`, and first real benchmark cache hit.

- [ ] **Step 5: Commit release state**

Stage only files owned by this plan, review `git status --short` and cached diff, then commit:

```bash
git commit -m "release: install Qwen startup prefill build"
```
