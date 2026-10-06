# GPT-OSS Local Admission Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Do not dispatch subagents for this plan because the repository rules require explicit user authorization for subagent work and the live model tests must run serially.

**Goal:** Prove whether a TypeWhale-controlled, offline MLX process can safely load the existing LM Studio `gpt-oss-20b-MXFP4-Q8` files and meet TypeWhale's performance, Harmony-output, rewrite, translation, cancellation, and local-import admission requirements.

**Architecture:** Add a repository-only evaluation harness under `tools/local-llm-eval/` with a dependency-free controller and an MLX worker launched through the installed TypeWhale Python runtime. The worker owns model memory and emits sanitized JSONL; the controller validates the external model read-only, enforces timeouts, tests process termination/restart, and writes non-private evidence without linking any probe code into the App.

**Tech Stack:** Python 3.10 standard library, TypeWhale installed runtime (`mlx-lm 0.30.5`, MLX, Transformers), JSON/JSONL, `resource.getrusage`, APFS `cp -c`, `unittest`.

## Global Constraints

- Work only on `codex/typewhale-pro-asr-hotwords` in `$HOME/Pictures/macOSwinOSCoding/TypeSpeaker`; do not create a worktree.
- Before every write, live model run, stage, or commit, rerun branch/status/build-process checks and protect `.superpowers/`, `native/Helpers/CapsuleConceptGallery/`, and `native/Sources/Presentation/Capsule/Concepts/`.
- Treat `$HOME/.lmstudio/models/mlx-community/gpt-oss-20b-MXFP4-Q8` as read-only; never modify, move, rename, delete, chmod, or write into it.
- Do not call LM Studio or Ollama services and do not reuse their private backend executables.
- Disable network fallback: pass `local_files_only=True`, set `HF_HUB_OFFLINE=1` and `TRANSFORMERS_OFFLINE=1`, and fail if any required local file is absent.
- Use `$HOME/Library/Application Support/TypeWhale Pro/Runtimes/mlx-asr/v1/python/bin/python3.10`; do not use the broken installed `mlx_lm.generate` shebang and do not install packages.
- Use `Reasoning: low`, disable tools, use deterministic sampling, and return only a valid Harmony `final` channel.
- Do not print, persist, or include the Harmony `analysis` channel in JSONL, reports, logs, exceptions, or test diagnostics.
- Do not read TypeWhale user history. Use only checked-in synthetic fixtures.
- Keep the probe outside every App target. Do not modify `SelectedSmartAITextEngine`, Ollama routes, ASR, VAD, UI, paste, history, user settings, build number, or installed App.
- Live model runs are serial. Stop if another model/build session starts or if memory pressure makes the machine unsafe.
- Pure probe/document changes do not invoke `build_and_log.sh`; they require focused tests, evidence review, scoped status review, and a git commit.

---

## File Map

### New focused units

- `tools/local-llm-eval/gpt_oss_probe_lib.py`: dependency-free model validation, Harmony token-state parser, case assertions, and sanitized result types.
- `tools/local-llm-eval/gpt_oss_worker.py`: MLX-only worker that loads one local model, runs JSONL requests, records timing/memory, and never emits analysis.
- `tools/local-llm-eval/run_gpt_oss_admission.py`: parent controller for validation, worker lifecycle, timeouts, cancellation/restart, APFS clone feasibility, and evidence output.
- `tools/local-llm-eval/gpt_oss_cases.json`: synthetic TypeWhale rewrite/translation admission cases and machine-checkable invariants.
- `tools/local-llm-eval/test_gpt_oss_probe.py`: standard-library unit tests that do not load the 11GB model.
- `docs/research/2026-07-24-gpt-oss-local-admission.md`: sanitized human-readable admission report generated from the live JSON result.

### Existing files changed

- `docs/superpowers/plans/2026-07-24-gpt-oss-local-admission.md`: execution checkboxes and final evidence references only.
- `docs/开发日志.md`: persistent architecture and admission decision record.

---

### Task 1: Lock Offline Contracts and Harmony Final Parsing

**Files:**
- Create: `tools/local-llm-eval/gpt_oss_probe_lib.py`
- Create: `tools/local-llm-eval/test_gpt_oss_probe.py`

**Interfaces:**
- Produces: `ModelValidation`, `validate_model_directory(path: Path) -> ModelValidation`.
- Produces: `HarmonyTokenIDs`, `extract_harmony_final(token_ids: list[int], ids: HarmonyTokenIDs, decode: Callable[[list[int]], str]) -> str`.
- Produces: `evaluate_case(case: dict[str, Any], output: str) -> list[str]`, returning failure reasons only.

- [x] **Step 1: Write failing model-validation tests**

Create temporary fixture directories with `config.json`, `tokenizer.json`, `tokenizer_config.json`, `chat_template.jinja`, `model.safetensors.index.json`, and three non-empty shard files. Assert:

```python
validation = validate_model_directory(valid_root)
self.assertEqual(validation.model_type, "gpt_oss")
self.assertEqual(validation.architecture, "GptOssForCausalLM")
self.assertEqual(validation.shard_count, 3)
self.assertEqual(validation.missing, ())
self.assertTrue(validation.valid)
```

Also assert rejection of a missing shard, zero-byte shard, path outside a directory, wrong `model_type`, wrong architecture, malformed index JSON, and an index that references a fourth undeclared shard.

- [x] **Step 2: Write failing Harmony parser tests**

Use synthetic token IDs:

```python
ids = HarmonyTokenIDs(
    channel=10,
    message=11,
    end=12,
    return_token=13,
    analysis=(20,),
    final=(21,),
)
self.assertEqual(
    extract_harmony_final(
        [10, 20, 11, 90, 91, 12, 10, 21, 11, 100, 101, 13],
        ids,
        lambda values: "".join({100: "你", 101: "好"}.get(v, "") for v in values),
    ),
    "你好",
)
```

Assert rejection when final is absent, final is empty, a control token occurs inside final, two final channels occur, or only analysis is present. Exception strings may identify the structural reason but must not contain decoded analysis text.

- [x] **Step 3: Run tests and verify RED**

Run:

```bash
/usr/bin/python3 tools/local-llm-eval/test_gpt_oss_probe.py -v
```

Expected: import failure because `gpt_oss_probe_lib.py` does not exist.

- [x] **Step 4: Implement dependency-free contracts**

Use frozen dataclasses and exact structural validation:

```python
@dataclass(frozen=True)
class ModelValidation:
    model_type: str
    architecture: str
    shard_count: int
    total_bytes: int
    missing: tuple[str, ...]
    errors: tuple[str, ...]

    @property
    def valid(self) -> bool:
        return not self.missing and not self.errors


@dataclass(frozen=True)
class HarmonyTokenIDs:
    channel: int
    message: int
    end: int
    return_token: int
    analysis: tuple[int, ...]
    final: tuple[int, ...]
```

`extract_harmony_final` must scan token IDs, recognize `channel + final + message`, collect only its content until `end` or `return_token`, and never call `decode` for analysis tokens.

- [x] **Step 5: Implement machine-checkable case assertions**

Support these exact fixture keys:

```python
def evaluate_case(case: dict[str, Any], output: str) -> list[str]:
    failures: list[str] = []
    stripped = output.strip()
    for required in case.get("must_contain", []):
        if required not in stripped:
            failures.append(f"missing:{required}")
    for forbidden in case.get("must_not_contain", []):
        if forbidden in stripped:
            failures.append(f"forbidden:{forbidden}")
    max_chars = int(case.get("max_output_chars", 0))
    if max_chars and len(stripped) > max_chars:
        failures.append(f"too_long:{len(stripped)}>{max_chars}")
    if not stripped:
        failures.append("empty")
    return failures
```

Fixture strings are synthetic and may be included in diagnostics; model analysis text may not.

- [x] **Step 6: Run tests and verify GREEN**

Run:

```bash
/usr/bin/python3 tools/local-llm-eval/test_gpt_oss_probe.py -v
/usr/bin/python3 -m py_compile tools/local-llm-eval/gpt_oss_probe_lib.py tools/local-llm-eval/test_gpt_oss_probe.py
```

Expected: all tests pass and compilation exits `0`.

---

### Task 2: Add Synthetic Cases and the Isolated MLX Worker

**Files:**
- Create: `tools/local-llm-eval/gpt_oss_cases.json`
- Create: `tools/local-llm-eval/gpt_oss_worker.py`
- Modify: `tools/local-llm-eval/test_gpt_oss_probe.py`

**Interfaces:**
- Consumes: `extract_harmony_final` and `HarmonyTokenIDs` from Task 1.
- Consumes: JSONL commands `{"type":"generate","request_id":str,"task":"rewrite|translate","text":str,"max_tokens":int}` and `{"type":"shutdown"}`.
- Produces: one sanitized `ready` event after load and one `result` event per request.

- [x] **Step 1: Add failing fixture-contract tests**

Require unique IDs and these case categories:

```python
required_categories = {
    "short_chat",
    "development_request",
    "no_answer",
    "short_instruction",
    "zh_to_en",
    "en_to_zh",
    "technical_terms",
}
self.assertTrue(required_categories.issubset({case["category"] for case in cases}))
self.assertTrue(all(case["text"].strip() for case in cases))
self.assertTrue(all(case["max_tokens"] <= 256 for case in cases))
```

No case may contain an email address, phone number, absolute user path, or text copied from TypeWhale history.

- [x] **Step 2: Add the synthetic fixture**

Include at least these machine-checkable cases:

```json
[
  {
    "id": "short-chat-repetition",
    "category": "short_chat",
    "task": "rewrite",
    "text": "好好，我们再回顾一下下这个问题。",
    "must_contain": ["我们", "回顾", "问题"],
    "must_not_contain": ["以下是", "总结如下", "作为"],
    "max_output_chars": 40,
    "max_tokens": 96
  },
  {
    "id": "no-answer-request",
    "category": "no_answer",
    "task": "rewrite",
    "text": "帮我回复用户，说我们先确认原因，不要承诺今天上线。",
    "must_contain": ["回复用户", "确认原因", "不要承诺今天上线"],
    "must_not_contain": ["您好", "感谢您的反馈", "我们将在今天上线"],
    "max_output_chars": 70,
    "max_tokens": 128
  },
  {
    "id": "technical-terms",
    "category": "technical_terms",
    "task": "rewrite",
    "text": "SwiftUI 这块不要走 Ollama，Qwen3-ASR 继续保持热加载。",
    "must_contain": ["SwiftUI", "Ollama", "Qwen3-ASR", "热加载"],
    "must_not_contain": ["冷加载"],
    "max_output_chars": 70,
    "max_tokens": 128
  }
]
```

Add development-request, short-instruction, Chinese-to-English, and English-to-Chinese cases with equivalent required/forbidden invariants.

- [x] **Step 3: Run fixture tests and verify RED**

Run:

```bash
/usr/bin/python3 tools/local-llm-eval/test_gpt_oss_probe.py -v
```

Expected: failure because the fixture and worker contract are not complete.

- [x] **Step 4: Implement the MLX worker**

The worker must import MLX modules only in `main`, load from the provided absolute local path, and use:

```python
model, tokenizer = load(
    str(model_dir),
    tokenizer_config={"local_files_only": True, "trust_remote_code": False},
    lazy=False,
)
prompt = tokenizer.apply_chat_template(
    messages,
    tokenize=False,
    add_generation_prompt=True,
    reasoning_effort="low",
)
sampler = make_sampler(temp=0.0)
responses = stream_generate(
    model,
    tokenizer,
    prompt,
    max_tokens=max_tokens,
    sampler=sampler,
)
```

Collect only response token IDs. Build `HarmonyTokenIDs` with:

```python
HarmonyTokenIDs(
    channel=tokenizer.convert_tokens_to_ids("<|channel|>"),
    message=tokenizer.convert_tokens_to_ids("<|message|>"),
    end=tokenizer.convert_tokens_to_ids("<|end|>"),
    return_token=tokenizer.convert_tokens_to_ids("<|return|>"),
    analysis=tuple(tokenizer.encode("analysis", add_special_tokens=False)),
    final=tuple(tokenizer.encode("final", add_special_tokens=False)),
)
```

Decode only final content with `tokenizer.decode(final_ids, skip_special_tokens=True)`.

- [x] **Step 5: Record separated timing and memory**

Emit sanitized numeric metrics:

```python
{
    "type": "result",
    "request_id": request_id,
    "status": "ok",
    "final": final_text,
    "load_ms": load_ms,
    "prefill_and_ttft_ms": ttft_ms,
    "completion_ms": completion_ms,
    "generated_tokens": generated_tokens,
    "decode_tokens_per_second": decode_tps,
    "peak_rss_bytes": resource.getrusage(resource.RUSAGE_SELF).ru_maxrss,
}
```

On macOS, `ru_maxrss` is bytes. Errors emit only exception type plus a fixed structural code; do not embed raw generated text.

- [x] **Step 6: Run offline tests and verify GREEN**

Run:

```bash
/usr/bin/python3 tools/local-llm-eval/test_gpt_oss_probe.py -v
/usr/bin/python3 -m py_compile tools/local-llm-eval/gpt_oss_worker.py
```

Expected: all tests pass without importing MLX or loading the model.

---

### Task 3: Add the Admission Controller and Process-Recovery Tests

**Files:**
- Create: `tools/local-llm-eval/run_gpt_oss_admission.py`
- Modify: `tools/local-llm-eval/test_gpt_oss_probe.py`

**Interfaces:**
- Consumes: model validator, cases JSON, and worker JSONL protocol.
- Produces: `--output-json` sanitized evidence and `--output-report` Markdown summary.
- Produces exit `0` only when structural, inference, case, cancellation/restart, and APFS-clone checks all pass.

- [x] **Step 1: Write failing controller tests with a fake worker**

Create the fake worker dynamically in a test temporary directory. Verify:

- the controller rejects a non-absolute model path;
- environment contains `HF_HUB_OFFLINE=1`, `TRANSFORMERS_OFFLINE=1`, and `HF_DATASETS_OFFLINE=1`;
- three sequential result events are accepted from one PID;
- a worker that exceeds timeout is terminated;
- cancellation is followed by a fresh worker PID and a successful health generation;
- output JSON excludes keys named `analysis`, `thinking`, `raw_tokens`, and `raw_output`;
- a failed case makes the controller exit non-zero.

- [x] **Step 2: Run controller tests and verify RED**

Run:

```bash
/usr/bin/python3 tools/local-llm-eval/test_gpt_oss_probe.py -v
```

Expected: failure because the controller does not exist.

- [x] **Step 3: Implement guarded worker lifecycle**

Launch with an explicit interpreter and environment:

```python
environment = {
    **os.environ,
    "HF_HUB_OFFLINE": "1",
    "TRANSFORMERS_OFFLINE": "1",
    "HF_DATASETS_OFFLINE": "1",
    "TOKENIZERS_PARALLELISM": "false",
    "PYTHONNOUSERSITE": "1",
}
process = subprocess.Popen(
    [python_path, str(worker_path), "--model-dir", str(model_dir)],
    stdin=subprocess.PIPE,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
    bufsize=1,
    env=environment,
    start_new_session=True,
)
```

Timeout/cancel first sends `SIGTERM` to the worker process group, waits five seconds, and uses `SIGKILL` only if still alive. Never signal a PID not created by this controller.

- [x] **Step 4: Implement live admission sequence**

Run exactly this order:

1. validate external model structure and record file metadata;
2. cold-start worker and wait for `ready`;
3. execute all synthetic cases serially;
4. execute the first three cases again in the same worker to prove warm continuity;
5. shut down cleanly;
6. start a cancellation worker with a long synthetic generation and terminate it after the configured deadline;
7. start a fresh recovery worker and run one minimal rewrite;
8. shut down recovery worker cleanly;
9. run APFS clone feasibility in a controller-created `mkdtemp` directory and clean only that directory.

- [x] **Step 5: Implement APFS clone feasibility safely**

Use `cp -cR` only into the controller-created temporary directory:

```python
temp_root = Path(tempfile.mkdtemp(prefix="typewhale-gpt-oss-clone-"))
clone_root = temp_root / "model"
try:
    subprocess.run(["cp", "-cR", str(model_dir), str(clone_root)], check=True)
    clone_validation = validate_model_directory(clone_root)
    if not clone_validation.valid or clone_validation.total_bytes != source_validation.total_bytes:
        raise RuntimeError("clone_validation_failed")
finally:
    shutil.rmtree(temp_root)
```

Before deletion, assert `temp_root.name.startswith("typewhale-gpt-oss-clone-")`, `temp_root.parent == Path(tempfile.gettempdir()).resolve()`, and `clone_root.is_relative_to(temp_root)`.

- [x] **Step 6: Generate sanitized evidence**

Write JSON with model metadata, runtime versions, numeric measurements, final fixture outputs, assertion failures, worker PIDs, cancel/recovery status, and clone status. Generate Markdown from this JSON. Do not include analysis, raw token streams, environment variables, unrelated filesystem paths, or private user text.

- [x] **Step 7: Run tests and verify GREEN**

Run:

```bash
/usr/bin/python3 tools/local-llm-eval/test_gpt_oss_probe.py -v
/usr/bin/python3 -m py_compile tools/local-llm-eval/run_gpt_oss_admission.py
git diff --check
```

Expected: all tests pass; no model is loaded during unit tests.

---

### Task 4: Run the Real Model Admission and Record the Decision

**Files:**
- Create: `docs/research/2026-07-24-gpt-oss-local-admission.md`
- Modify: `docs/superpowers/plans/2026-07-24-gpt-oss-local-admission.md`
- Modify: `docs/开发日志.md`
- Runtime-only evidence: a controller-created JSON file under `/tmp`, summarized into the Markdown report but not committed.

**Interfaces:**
- Consumes: Tasks 1–3 and the installed TypeWhale Python runtime.
- Produces: explicit `ADMIT`, `REJECT`, or `INCONCLUSIVE` decision for production-planning eligibility only.

- [x] **Step 1: Recheck concurrency and protected state**

Run:

```bash
git branch --show-current
git status --short
pgrep -lf 'build_and_log\.sh|release_local_build\.sh|build_native_app\.sh|swiftc|xcodebuild' || true
```

Expected: correct branch, only protected pre-existing directories plus this plan/probe files, and no build process. Otherwise stop before model load.

- [x] **Step 2: Run the live admission**

Run:

```bash
PROBE_PYTHON='$HOME/Library/Application Support/TypeWhale Pro/Runtimes/mlx-asr/v1/python/bin/python3.10'
PROBE_MODEL='$HOME/.lmstudio/models/mlx-community/gpt-oss-20b-MXFP4-Q8'
"$PROBE_PYTHON" tools/local-llm-eval/run_gpt_oss_admission.py \
  --python "$PROBE_PYTHON" \
  --model-dir "$PROBE_MODEL" \
  --cases tools/local-llm-eval/gpt_oss_cases.json \
  --output-json /tmp/typewhale-gpt-oss-admission.json \
  --output-report docs/research/2026-07-24-gpt-oss-local-admission.md \
  --request-timeout-seconds 30 \
  --cancel-after-seconds 1
```

Expected: no network activity or model download, source model remains unmodified, and the command returns a decision with complete evidence.

- [x] **Step 3: Independently verify source immutability and evidence privacy**

Record source metadata before and after and compare file paths, sizes, and modification times. Run:

```bash
rg -n -i 'analysis|thinking|raw_tokens|raw_output|@|$HOME' \
  /tmp/typewhale-gpt-oss-admission.json \
  docs/research/2026-07-24-gpt-oss-local-admission.md
```

Expected: no analysis/thinking/raw-token fields, no email-like private data, and no absolute user path in the committed report. The temporary JSON may contain the explicitly tested model path only if required for local reproducibility; the committed report must use `~/.lmstudio/...`.

- [x] **Step 4: Apply the admission decision**

Use these rules:

- `ADMIT`: structure valid; cold load succeeds; at least three continuous requests succeed; every response has exactly one non-empty final; all fixture assertions pass; cancellation terminates the owned worker; recovery worker succeeds; APFS clone validates; metrics are complete.
- `REJECT`: reproducible incompatibility, unsafe output parsing, persistent semantic failure, cancellation/recovery failure, source mutation, or clone corruption.
- `INCONCLUSIVE`: environmental interruption, concurrent build/model load, resource pressure, or missing evidence that is not itself a model/runtime failure.

The decision grants or denies entry into a separate production implementation plan. It does not change the default model or production routing.

- [x] **Step 5: Run final verification**

Run:

```bash
/usr/bin/python3 tools/local-llm-eval/test_gpt_oss_probe.py -v
/usr/bin/python3 -m py_compile \
  tools/local-llm-eval/gpt_oss_probe_lib.py \
  tools/local-llm-eval/gpt_oss_worker.py \
  tools/local-llm-eval/run_gpt_oss_admission.py
git diff --check
git status --short
```

Expected: tests and compilation pass; the protected directories remain untouched; no build/version/install files changed.

- [x] **Step 6: Commit only the isolated admission work**

Review `git diff --stat` and `git status --short`, then stage only:

```bash
git add \
  docs/superpowers/plans/2026-07-24-gpt-oss-local-admission.md \
  docs/research/2026-07-24-gpt-oss-local-admission.md \
  docs/开发日志.md \
  tools/local-llm-eval/gpt_oss_probe_lib.py \
  tools/local-llm-eval/gpt_oss_worker.py \
  tools/local-llm-eval/run_gpt_oss_admission.py \
  tools/local-llm-eval/gpt_oss_cases.json \
  tools/local-llm-eval/test_gpt_oss_probe.py
git commit -m "test: admit local gpt-oss MLX runtime"
```

Do not stage `.superpowers/`, `native/Helpers/CapsuleConceptGallery/`, or `native/Sources/Presentation/Capsule/Concepts/`.

## Acceptance Checklist

- Existing LM Studio model is read-only and no model weight is downloaded.
- The installed TypeWhale Python runtime loads the model through its real Python entry point.
- Cold load, TTFT, completion, decode throughput, peak RSS, and continuous warm calls are recorded separately.
- Exactly one Harmony final is returned; analysis never leaves the worker.
- Rewrite and translation fixtures pass or produce explicit case-level rejection evidence.
- Cancellation affects only the controller-owned worker and a clean worker can recover afterward.
- APFS clone-on-write succeeds and validates, or the decision explicitly rejects/inconclusively records that requirement.
- No App target, production route, UI, version, build, installed App, or protected dirty directory changes.

## Execution Result

- Runtime architecture: `PASS`.
- Combined default-model admission: `REJECT`.
- The model passed independent loading, Harmony final-only parsing, performance, continuous calls, cancellation/recovery, APFS clone-on-write, source immutability, translation, no-answer, constraint, short-instruction, and technical-term checks.
- The model failed the strict rewrite-noise case by retaining the unambiguous stutter `一下下` after the probe prompt was aligned with TypeWhale's production cleanup priority.
- Final sanitized evidence: `docs/research/2026-07-24-gpt-oss-local-admission.md`.
