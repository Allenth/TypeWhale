# Managed MLX Prefix Cache Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reduce hot Qwen3 4B time-to-first-token by reusing exact common prompt-token prefixes without changing prompts, sampling, routing, or output semantics.

**Architecture:** Add a small in-memory LRU-like prefix cache to the persistent Python MLX worker. Each generation receives a deep-copied MLX cache representing the longest safe common token prefix, evaluates only the remainder, then stores the resulting cache; Swift decodes and logs optional cache metrics while remaining compatible with old worker responses.

**Tech Stack:** Python 3.10 `unittest`, MLX/`mlx_lm` prompt cache APIs, Swift `Codable`, shell-based Swift checks, TypeWhale native build scripts.

## Global Constraints

- Do not change the Qwen3 4B model, quantization, prompts, sampling parameters, DeepSeek route, ASR, paste behavior, or auto-send countdown.
- Prompt caches remain memory-only, have a fixed small capacity, and clear when the loaded model changes.
- Never log prompt text, source text, generated text, or KV data; log only cache status and token counts.
- Every request uses a deep-copied cache so generation cannot mutate an entry retained for later requests.
- Any unsafe match, unsupported trim, clone failure, or cache exception falls back to the existing full-prompt path.
- Existing worker response fields and error behavior remain compatible.
- Preserve unrelated untracked files and do not stage them.

---

## File map

- `native/Resources/managed_mlx_llm_worker.py`: owns `PromptPrefixCache`, integrates MLX cache reuse, clears it on model load changes, and emits cache metrics.
- `native/Tests/test_managed_mlx_llm_worker.py`: pure-Python red/green coverage using fake cache objects; no model load required.
- `native/Sources/Infrastructure/SmartRewrite/ManagedMLXLLMProtocol.swift`: optional cache metric fields with backward-compatible decoding.
- `native/Tests/ManagedMLXLLMProtocolCheck.swift`: new- and old-response decoding checks.
- `native/Tests/benchmark_managed_mlx_prefix_cache.py`: persistent-worker cold/hot real-model benchmark.
- `native/Sources/Infrastructure/SmartRewrite/TypeWhaleLocalLLMEngine.swift`: completion log fields for cache diagnostics.
- `native/Sources/Presentation/VersionHistory/VersionHistoryViewController.swift`: installed-build history entry.
- `docs/开发日志.md`: product reason, scope, and verification record.
- `docs/构建日志.md`: written by the canonical build script.

### Task 1: Pure prompt-prefix cache behavior

**Files:**
- Modify: `native/Tests/test_managed_mlx_llm_worker.py`
- Modify: `native/Resources/managed_mlx_llm_worker.py`

**Interfaces:**
- Produces: `PromptCacheMatch(cache, remaining_tokens, reused_tokens)`
- Produces: `PromptPrefixCache(max_size: int)`
- Produces: `PromptPrefixCache.fetch(model_key, tokens, can_trim, trim) -> PromptCacheMatch`
- Produces: `PromptPrefixCache.insert(model_key, tokens, prompt_cache) -> None`
- Produces: `PromptPrefixCache.clear() -> None`

- [ ] **Step 1: Add failing pure-Python tests**

Add fake mutable caches and tests equivalent to:

```python
class FakeCache:
    def __init__(self, values):
        self.values = list(values)


def fake_can_trim(caches):
    return all(isinstance(cache, FakeCache) for cache in caches)


def fake_trim(caches, count):
    for cache in caches:
        del cache.values[-count:]


def test_shorter_cached_prefix_is_cloned_and_reused(self):
    cache = worker.PromptPrefixCache(max_size=2)
    original = [FakeCache([1, 2, 3])]
    cache.insert("model-a", [10, 11, 12], original)

    match = cache.fetch(
        "model-a", [10, 11, 12, 13, 14],
        can_trim=fake_can_trim, trim=fake_trim,
    )

    self.assertEqual(match.reused_tokens, 3)
    self.assertEqual(match.remaining_tokens, [13, 14])
    self.assertIsNot(match.cache, original)
    match.cache[0].values.append(99)
    self.assertEqual(original[0].values, [1, 2, 3])


def test_longer_cached_sequence_trims_to_safe_common_prefix(self):
    cache = worker.PromptPrefixCache(max_size=2)
    cache.insert("model-a", [10, 11, 12, 20], [FakeCache([10, 11, 12, 20])])

    match = cache.fetch(
        "model-a", [10, 11, 12, 30],
        can_trim=fake_can_trim, trim=fake_trim,
    )

    self.assertEqual(match.reused_tokens, 3)
    self.assertEqual(match.remaining_tokens, [30])
    self.assertEqual(match.cache[0].values, [10, 11, 12])


def test_model_mismatch_and_clear_are_misses(self):
    cache = worker.PromptPrefixCache(max_size=2)
    cache.insert("model-a", [1, 2], [FakeCache([1, 2])])
    self.assertEqual(cache.fetch("model-b", [1, 2, 3], can_trim=fake_can_trim, trim=fake_trim).reused_tokens, 0)
    cache.clear()
    self.assertEqual(cache.fetch("model-a", [1, 2, 3], can_trim=fake_can_trim, trim=fake_trim).reused_tokens, 0)


def test_untrimmable_longer_cache_falls_back_to_miss(self):
    cache = worker.PromptPrefixCache(max_size=2)
    cache.insert("model-a", [1, 2, 3], [FakeCache([1, 2, 3])])
    match = cache.fetch("model-a", [1, 9], can_trim=lambda _: False, trim=fake_trim)
    self.assertEqual(match.reused_tokens, 0)
    self.assertEqual(match.remaining_tokens, [1, 9])
    self.assertIsNone(match.cache)
```

- [ ] **Step 2: Run the worker unit tests and verify RED**

Run:

```bash
python3 -m unittest native/Tests/test_managed_mlx_llm_worker.py
```

Expected: failures because `PromptPrefixCache` and `PromptCacheMatch` do not exist.

- [ ] **Step 3: Implement the minimal cache**

Use `collections.OrderedDict` keyed by `(model_key, tuple(tokens))`. On fetch, choose the entry with the longest common prefix. Deep-copy a shorter/equal cache and return the unprocessed suffix. For a longer cache, deep-copy and call the injected MLX-compatible trim function; retain at least one input token when the request is an exact prefix. Catch copy/trim exceptions and return a miss. Evict the oldest item when `max_size` is exceeded.

- [ ] **Step 4: Run the worker unit tests and verify GREEN**

Run the Step 2 command.

Expected: all worker unit tests pass with no model import or network access.

- [ ] **Step 5: Commit Task 1**

Stage only the two task files and commit:

```bash
git commit -m "feat: add managed MLX prompt prefix cache"
```

### Task 2: Integrate cache reuse into MLX generation

**Files:**
- Modify: `native/Tests/test_managed_mlx_llm_worker.py`
- Modify: `native/Resources/managed_mlx_llm_worker.py`

**Interfaces:**
- Consumes: `PromptPrefixCache`
- Produces: `PreparedGeneration(cache, input_tokens, hit, reused_tokens)`
- Produces in worker metrics: `prompt_cache_hit`, `prompt_cache_reused_tokens`, `prompt_tokens_evaluated`

- [ ] **Step 1: Add failing worker integration tests**

Extract prompt preparation into a testable method and assert:

```python
def test_prepare_generation_cache_uses_remainder_on_hit(self):
    state = worker.WorkerState()
    state.model_directory = "/model"
    state.prompt_prefix_cache.insert(
        "/model", [1, 2, 3], [FakeCache([1, 2, 3])]
    )

    prepared = state._prepare_generation_cache(
        prompt_tokens=[1, 2, 3, 4],
        make_cache=lambda _: [FakeCache([])],
        can_trim=fake_can_trim,
        trim=fake_trim,
    )

    self.assertTrue(prepared.hit)
    self.assertEqual(prepared.input_tokens, [4])
    self.assertEqual(prepared.reused_tokens, 3)


def test_prepare_generation_cache_creates_empty_cache_on_miss(self):
    state = worker.WorkerState()
    state.model = object()
    prepared = state._prepare_generation_cache(
        prompt_tokens=[7, 8],
        make_cache=lambda model: [FakeCache([])],
        can_trim=fake_can_trim,
        trim=fake_trim,
    )
    self.assertFalse(prepared.hit)
    self.assertEqual(prepared.input_tokens, [7, 8])
```

Also verify `_metrics(...)` returns zero/false cache values on miss and real values on hit.

- [ ] **Step 2: Run the worker tests and verify RED**

Expected: missing `_prepare_generation_cache` and metric fields.

- [ ] **Step 3: Wire MLX cache APIs into `_generate`**

Tokenize the completed chat template once. Import `make_prompt_cache`, `can_trim_prompt_cache`, and `trim_prompt_cache` inside the redirected MLX section. Pass the prepared cache through:

```python
for response in stream_generate(
    self.model,
    self.tokenizer,
    prepared.input_tokens,
    max_tokens=max_tokens,
    sampler=self.sampler,
    prompt_cache=prepared.cache,
):
    ...
```

After successful generation, insert `prompt_tokens + response_token_ids` with the mutated request cache. Clear `PromptPrefixCache` whenever `_load` replaces the model. Report original prompt tokens separately from tokens actually evaluated.

- [ ] **Step 4: Run Python regressions and syntax validation**

Run:

```bash
python3 -m unittest native/Tests/test_managed_mlx_llm_worker.py
python3 -m py_compile native/Resources/managed_mlx_llm_worker.py
```

Expected: all tests pass and compilation exits 0.

- [ ] **Step 5: Commit Task 2**

Commit:

```bash
git commit -m "perf: reuse managed MLX prompt prefixes"
```

### Task 3: Propagate optional cache metrics through Swift

**Files:**
- Modify: `native/Tests/ManagedMLXLLMProtocolCheck.swift`
- Modify: `native/Sources/Infrastructure/SmartRewrite/ManagedMLXLLMProtocol.swift`
- Modify: `native/Sources/Infrastructure/SmartRewrite/TypeWhaleLocalLLMEngine.swift`

**Interfaces:**
- Produces: `ManagedLLMMetrics.promptCacheHit: Bool?`
- Produces: `ManagedLLMMetrics.promptCacheReusedTokens: Int?`
- Produces: `ManagedLLMMetrics.promptTokensEvaluated: Int?`

- [ ] **Step 1: Make the Swift protocol check fail**

Extend the fixture:

```swift
let metrics = ManagedLLMMetrics(
    loadMS: 1_658.5,
    ttftMS: 473.7,
    completionMS: 1_146.5,
    tokensPerSecond: 121.6,
    peakRSSBytes: 13_046_824_960,
    promptTokens: 123,
    completionTokens: 45,
    promptCacheHit: true,
    promptCacheReusedTokens: 100,
    promptTokensEvaluated: 23
)
precondition(decodedResponse.metrics?.promptCacheHit == true)
precondition(decodedResponse.metrics?.promptCacheReusedTokens == 100)
precondition(decodedResponse.metrics?.promptTokensEvaluated == 23)
```

Decode a second JSON response whose metrics omit the three new keys and assert all three properties are `nil`.

- [ ] **Step 2: Compile and run the protocol check to verify RED**

Run:

```bash
xcrun swiftc \
  native/Sources/Infrastructure/SmartRewrite/ManagedMLXLLMProtocol.swift \
  native/Tests/ManagedMLXLLMProtocolCheck.swift \
  -o /tmp/ManagedMLXLLMProtocolCheck &&
  /tmp/ManagedMLXLLMProtocolCheck
```

Expected: compile failure because the new fields are absent.

- [ ] **Step 3: Add optional Codable fields and completion logging**

Add optional properties with coding keys:

```swift
case promptCacheHit = "prompt_cache_hit"
case promptCacheReusedTokens = "prompt_cache_reused_tokens"
case promptTokensEvaluated = "prompt_tokens_evaluated"
```

Append these values to `managed_mlx request_done`, defaulting missing values to `false`, `0`, and `promptTokens`.

- [ ] **Step 4: Run the Swift protocol check**

Run the Step 2 command.

Expected: `ManagedMLXLLMProtocolCheck passed`. The complete native build in Task 4 compiles the changed local engine with its production dependencies.

- [ ] **Step 5: Commit Task 3**

Commit:

```bash
git commit -m "feat: report managed MLX cache metrics"
```

### Task 4: Real-model performance gate and product build

**Files:**
- Create: `native/Tests/benchmark_managed_mlx_prefix_cache.py`
- Modify: `native/Sources/Presentation/VersionHistory/VersionHistoryViewController.swift`
- Modify: `docs/开发日志.md`
- Modified by build: `docs/构建日志.md` and version/build metadata files selected by `native/build_and_log.sh`

**Interfaces:**
- Consumes: worker JSON-lines protocol and installed Qwen3 4B directory.
- Produces: a uniquely numbered installed `/Applications/TypeWhale Pro.app`.

- [ ] **Step 1: Run an isolated two-request real-model benchmark**

Create a benchmark that launches one persistent worker, sends `warmup`, then two rewrite requests with the same system prompt and different user text:

```python
#!/usr/bin/env python3
import json
from pathlib import Path
import subprocess
import sys
import uuid

root = Path(__file__).resolve().parents[2]
runtime = (
    Path.home()
    / "Library/Application Support/TypeWhale Pro/Runtimes/mlx-asr/v1/python/bin/python3"
)
worker = root / "native/Resources/managed_mlx_llm_worker.py"
model = (
    Path.home()
    / "Library/Application Support/TypeWhale Pro/Models/LLM/qwen3-4b-instruct-2507-4bit"
)
process = subprocess.Popen(
    [str(runtime), str(worker)],
    stdin=subprocess.PIPE,
    stdout=subprocess.PIPE,
    text=True,
)

def request(command, system="", user="", max_tokens=64):
    payload = {
        "protocol_version": 1,
        "id": str(uuid.uuid4()),
        "command": command,
        "model_directory": str(model),
        "system_prompt": system,
        "user_prompt": user,
        "reasoning": "low",
        "max_tokens": max_tokens,
    }
    assert process.stdin is not None and process.stdout is not None
    process.stdin.write(json.dumps(payload, ensure_ascii=False) + "\n")
    process.stdin.flush()
    return json.loads(process.stdout.readline())

system = "只整理原文，不回答问题，只输出整理后的正文。"
try:
    assert request("warmup")["ok"]
    first = request("rewrite", system, "请把这句话整理得更清楚。")
    second = request("rewrite", system, "请把另一句话也整理得更清楚。")
    assert first["ok"] and first["final_text"]
    assert second["ok"] and second["final_text"]
    assert first["metrics"]["prompt_cache_hit"] is False
    assert second["metrics"]["prompt_cache_hit"] is True
    assert second["metrics"]["prompt_cache_reused_tokens"] > 0
    print(json.dumps({
        "first_ttft_ms": first["metrics"]["ttft_ms"],
        "second_ttft_ms": second["metrics"]["ttft_ms"],
        "reused_tokens": second["metrics"]["prompt_cache_reused_tokens"],
    }, ensure_ascii=False))
finally:
    process.terminate()
```

Run:

```bash
$HOME/Library/Application\ Support/TypeWhale\ Pro/Runtimes/mlx-asr/v1/python/bin/python3 native/Tests/benchmark_managed_mlx_prefix_cache.py
```

Expected: one JSON object with cold and hot TTFT, `reused_tokens > 0`, and exit 0. If the second request does not improve materially or output is invalid, stop and do not ship the optimization.

- [ ] **Step 2: Run the focused and boundary regression suite**

Run:

```bash
python3 -m unittest native/Tests/test_managed_mlx_llm_worker.py
xcrun swiftc native/Sources/Infrastructure/SmartRewrite/ManagedMLXLLMProtocol.swift native/Tests/ManagedMLXLLMProtocolCheck.swift -o /tmp/ManagedMLXLLMProtocolCheck && /tmp/ManagedMLXLLMProtocolCheck
zsh native/Tests/ManagedLLMLifecycleBoundaryCheck.sh
zsh native/Tests/ManagedLLMModelPanelBoundaryCheck.sh
```

Expected: zero failures.

- [ ] **Step 3: Update durable product records**

Add the upcoming build entry to `VersionHistoryViewController` and record:

- fixed prompts now reuse a memory-only MLX token prefix;
- cache clears on model changes and never writes user content to disk;
- worker metrics expose hit/reused/evaluated token counts;
- measured cold-cache and hot-cache TTFT from Step 1.

Update `docs/开发日志.md` with the same behavior boundary and verification evidence.

- [ ] **Step 4: Recheck concurrent workspace safety**

Run branch, status, build-process, source mtime, and version checks. Stop if another process is building or any protected dirty file overlaps this plan.

- [ ] **Step 5: Build, increment build number, install, launch, and verify**

Run:

```bash
./native/build_and_log.sh
```

Expected: compile succeeds, build number increments exactly once, `/Applications/TypeWhale Pro.app` is replaced and launched, code signing validates, and the build log is appended.

- [ ] **Step 6: Validate the installed app**

Perform three short dictations with local Qwen selected. Confirm the second and third `managed_mlx request_done` lines report cache hits and lower evaluated-token counts; verify output, paste, cancellation, and auto-send countdown behavior remain unchanged.

- [ ] **Step 7: Review scope and commit the build**

Run `git status --short`, `git diff --check`, inspect every staged file, exclude unrelated untracked files, and commit:

```bash
git commit -m "perf: accelerate Qwen3 rewrite prompt prefill"
```
