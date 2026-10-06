# Local TTS Assets and Qualification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Consolidate, download, benchmark, qualify, and safely deduplicate TypeWhale's approved offline TTS candidates without touching Reader Demo.

**Architecture:** A repository-owned catalog describes every candidate, source, runtime, license, and required artifact. A resumable staging tool downloads or copies candidates into isolated directories, a common JSONL benchmark runner measures them, and only passing manifests are atomically promoted into TypeWhale's model root.

**Tech Stack:** Python 3.11+, zsh, SHA-256, Hugging Face/ModelScope CLIs, sherpa-onnx, Core ML/TTSKit CLI, PyTorch/MPS model-specific runtimes, WAV/JSONL.

## Global Constraints

- Never read, write, move, or delete anything below `~/Library/Application Support/Reader Demo/`.
- Use `~/Library/Application Support/TypeWhale Pro/Models/tts/` as the only promoted TTS model root.
- Queue all first- and second-tier candidates together with at most 3 concurrent downloads.
- Stop new downloads when promoted plus staging TTS assets reach 50 GB or free disk space would fall below 15 GB.
- A model is selectable only after valid WAV generation, cancellation, three stable runs, metrics capture, and disconnected rerun.
- Delete a source only after source/target hashes match, the promoted model passes speech and cancellation checks, and no retained tool depends on the source.
- Preserve existing OpenClaw behavior and do not change its selected engine in this plan.
- Do not add Supertonic 3, Fish Speech S2, or IndexTTS2.

---

### Task 1: Freeze the asset inventory and safety boundary

**Files:**
- Create: `tools/tts_asset_inventory.py`
- Test: `native/Tests/TTSAssetInventoryCheck.py`
- Create: `docs/tts/local-tts-inventory.json`

**Interfaces:**
- Consumes: filesystem roots supplied by `--scan-root`.
- Produces: `InventoryEntry(path: str, bytes: int, sha256: str, category: str, protected: bool)` JSON records.

- [ ] **Step 1: Write the failing inventory safety test**

```python
with tempfile.TemporaryDirectory() as tmp:
    root = Path(tmp)
    reader = root / "Reader Demo"; reader.mkdir()
    (reader / "model.onnx").write_bytes(b"protected")
    result = subprocess.run(
        [sys.executable, str(tool), "--scan-root", str(root), "--protected-root", str(reader), "--json"],
        check=True, capture_output=True, text=True,
    )
    rows = json.loads(result.stdout)
    assert rows[0]["protected"] is True
    assert rows[0]["sha256"] == ""
```

- [ ] **Step 2: Run the test and verify it fails**

Run: `python3 native/Tests/TTSAssetInventoryCheck.py`
Expected: FAIL because `tools/tts_asset_inventory.py` does not exist.

- [ ] **Step 3: Implement the read-only inventory**

Implement `classify(path)`, streamed `sha256(path)`, protected-root containment using resolved paths, and JSON output. Protected entries may report paths and sizes but must not open or hash files.

- [ ] **Step 4: Run the test and capture the real inventory**

Run:

```bash
python3 native/Tests/TTSAssetInventoryCheck.py
python3 tools/tts_asset_inventory.py \
  --scan-root "$HOME/Library/Application Support/TypeWhale Pro/Models/tts" \
  --scan-root "$HOME/Library/Application Support/LocalTTSLab/models" \
  --scan-root "$HOME/.cache/huggingface/hub" \
  --protected-root "$HOME/Library/Application Support/Reader Demo" \
  --output docs/tts/local-tts-inventory.json
```

Expected: test prints `TTSAssetInventoryCheck passed`; inventory contains no hash from Reader Demo.

- [ ] **Step 5: Commit**

```bash
git add tools/tts_asset_inventory.py native/Tests/TTSAssetInventoryCheck.py docs/tts/local-tts-inventory.json
git commit -m "tool: inventory local TTS assets safely"
```

### Task 2: Define the approved catalog and bounded downloader

**Files:**
- Create: `native/Resources/tts_model_catalog.json`
- Create: `tools/tts_model_stage.py`
- Test: `native/Tests/TTSModelStageCheck.py`

**Interfaces:**
- Consumes: catalog entries with `id`, `tier`, `source`, `runtime`, `license`, `requiredPaths`.
- Produces: `<root>/.staging/<id>/download-state.json` and promoted `<root>/<id>/typewhale-model.json`.

- [ ] **Step 1: Write failing tests for concurrency and budgets**

Use fake 1 KB downloads and assert `peakActive <= 3`, a 50 MB test budget rejects the next 40 MB artifact after 20 MB is staged, and a mocked 14 GB free-space value rejects all new downloads.

- [ ] **Step 2: Run the test and verify it fails**

Run: `python3 native/Tests/TTSModelStageCheck.py`
Expected: FAIL because the staging tool and catalog are absent.

- [ ] **Step 3: Add exact catalog entries**

Catalog these IDs:

```json
[
  {"id":"sherpa-vits-melo-tts-zh_en","tier":1,"runtime":"sherpa_onnx","acquisition":"existing"},
  {"id":"qwen3-tts-06b-coreml","tier":1,"runtime":"ttskit","acquisition":"ttskit-prefetch"},
  {"id":"qwen3-tts-17b-coreml","tier":1,"runtime":"ttskit","acquisition":"ttskit-prefetch"},
  {"id":"kokoro-int8-multi-lang-v1_1","tier":1,"runtime":"sherpa_onnx","acquisition":"local-copy"},
  {"id":"zipvoice-distill-int8-zh-en-emilia","tier":1,"runtime":"sherpa_onnx","acquisition":"local-copy"},
  {"id":"fun-cosyvoice3-0.5b","tier":2,"runtime":"isolated-python-mps","acquisition":"huggingface"},
  {"id":"moss-tts-local-transformer-v1.5","tier":2,"runtime":"isolated-python-mps","acquisition":"huggingface"},
  {"id":"voxcpm2","tier":2,"runtime":"isolated-python-mps","acquisition":"huggingface"}
]
```

Each full entry must include official repository/model identifiers, immutable revision, expected license filename, and required paths discovered from the official model card before download.

- [ ] **Step 4: Implement bounded concurrent staging**

Use `ThreadPoolExecutor(max_workers=3)`, streamed writes to `.part`, resumable HTTP/CLI acquisition, byte accounting under the TTS root, `shutil.disk_usage`, and atomic `os.replace` only after required-path and hash checks.

- [ ] **Step 5: Run tests**

Run: `python3 native/Tests/TTSModelStageCheck.py`
Expected: `TTSModelStageCheck passed`.

- [ ] **Step 6: Commit**

```bash
git add native/Resources/tts_model_catalog.json tools/tts_model_stage.py native/Tests/TTSModelStageCheck.py
git commit -m "tool: add bounded TTS model staging"
```

### Task 3: Migrate complete local assets without deleting sources

**Files:**
- Modify: `native/Resources/tts_model_catalog.json`
- Create: `docs/tts/local-tts-migration-report.json`

**Interfaces:**
- Consumes: inventory from Task 1 and staging tool from Task 2.
- Produces: staged Kokoro, ZipVoice, Vocos, and recorded legacy Qwen source dispositions.

- [ ] **Step 1: Recheck concurrency and disk**

Run: `git branch --show-current && git status --short` and `pgrep -af 'build_and_log.sh|release_local_build.sh|build_native_app.sh|swiftc|xcodebuild'`.
Expected: Pro ASR branch, no overlapping tracked edits, no active TypeWhale build.

- [ ] **Step 2: Dry-run local copies**

Run:

```bash
python3 tools/tts_model_stage.py --catalog native/Resources/tts_model_catalog.json \
  --root "$HOME/Library/Application Support/TypeWhale Pro/Models/tts" \
  --only kokoro-int8-multi-lang-v1_1,zipvoice-distill-int8-zh-en-emilia --dry-run
```

Expected: sources resolve only below LocalTTSLab; no Reader Demo paths.

- [ ] **Step 3: Copy and hash local assets**

Run the same command without `--dry-run`; ZipVoice staging must include `vocos_24khz.onnx`. Record source path, destination path, bytes, source hash, and target hash in the migration report.

- [ ] **Step 4: Verify source preservation**

Run inventory again and assert every LocalTTSLab source still exists.
Expected: migration is copy-only at this stage.

- [ ] **Step 5: Commit report and catalog revisions**

```bash
git add native/Resources/tts_model_catalog.json docs/tts/local-tts-migration-report.json
git commit -m "docs: record staged local TTS migration"
```

### Task 4: Stage every approved remote candidate together

**Files:**
- Modify: `docs/tts/local-tts-migration-report.json`

**Interfaces:**
- Consumes: catalog and staging tool.
- Produces: complete staged/promoted assets or per-model actionable failures.

- [ ] **Step 1: Start the complete queue**

Run:

```bash
python3 tools/tts_model_stage.py --catalog native/Resources/tts_model_catalog.json \
  --root "$HOME/Library/Application Support/TypeWhale Pro/Models/tts" \
  --all --max-concurrency 3 --budget-gb 50 --reserve-free-gb 15
```

Expected: all eight candidates are queued; at most three show `downloading`.

- [ ] **Step 2: Resume until every candidate reaches a terminal acquisition state**

Re-run the same command after recoverable network interruption.
Expected: completed bytes are reused; each model ends as `staged`, `promoted`, or `failed` with a reason.

- [ ] **Step 3: Verify licenses and exact disk use**

Run: `python3 tools/tts_model_stage.py ... --audit`.
Expected: no promoted entry lacks its license and total managed assets are at most 50 GB.

- [ ] **Step 4: Record acquisition outcomes**

Update the migration report with revisions, bytes, duration, and failures. Do not hand-edit a failed model into a passing state.

- [ ] **Step 5: Commit**

```bash
git add docs/tts/local-tts-migration-report.json
git commit -m "docs: record TTS candidate acquisition"
```

### Task 5: Build the isolated benchmark protocol and runners

**Files:**
- Create: `tools/tts_benchmark.py`
- Create: `native/Resources/tts_benchmark_worker.py`
- Test: `native/Tests/TTSBenchmarkProtocolCheck.py`
- Create: `docs/tts/benchmark-corpus.json`

**Interfaces:**
- JSONL request: `{"id":str,"type":"prepare|synthesize|cancel|shutdown","text":str?,"output":str?}`.
- JSONL response: `{"id":str,"ok":bool,"phase":str,"metrics":object?,"error":str?}`.
- Produces per-run `prepareSeconds`, `firstAudioSeconds`, `synthesisSeconds`, `audioSeconds`, `rtf`, `peakRSSBytes`, `thermalState`, `cold`.

- [ ] **Step 1: Write a failing fake-worker protocol test**

The test must exercise ready, cold prepare, synthesis to a valid PCM WAV, cancellation within two seconds, warm synthesis, shutdown, and rejection of malformed JSON.

- [ ] **Step 2: Run and verify failure**

Run: `python3 native/Tests/TTSBenchmarkProtocolCheck.py`
Expected: FAIL because the worker and harness do not exist.

- [ ] **Step 3: Implement the common harness**

Measure monotonic time, first audio callback/first non-empty output, WAV duration, RTF, and worker RSS sampled with `ps -o rss=`. Write one JSON object per run and preserve generated WAVs below `~/Library/Application Support/TypeWhale Pro/TTSLab/Outputs/`.

- [ ] **Step 4: Add model adapters**

Implement explicit adapters for Sherpa VITS, Sherpa Kokoro, ZipVoice+Vocos, TTSKit 0.6B/1.7B CLI, CosyVoice3, MOSS-TTS, and VoxCPM2. Each adapter must import only inside its isolated runtime and implement cancellation by cooperative callback or terminating its own child process.

- [ ] **Step 5: Run protocol tests**

Run: `python3 native/Tests/TTSBenchmarkProtocolCheck.py`
Expected: `TTSBenchmarkProtocolCheck passed`.

- [ ] **Step 6: Commit**

```bash
git add tools/tts_benchmark.py native/Resources/tts_benchmark_worker.py native/Tests/TTSBenchmarkProtocolCheck.py docs/tts/benchmark-corpus.json
git commit -m "tool: add isolated TTS benchmark protocol"
```

### Task 6: Qualify models and publish selectable manifests

**Files:**
- Create: `docs/tts/local-tts-benchmark-results.json`
- Create: `docs/tts/local-tts-qualification.md`
- Modify: promoted `typewhale-model.json` files outside git.

**Interfaces:**
- Consumes: staged models and benchmark protocol.
- Produces: `qualification.status = "passed"|"failed"`; UI later consumes only `passed`.

- [ ] **Step 1: Run the complete connected benchmark**

Run: `python3 tools/tts_benchmark.py --all --runs 3 --corpus docs/tts/benchmark-corpus.json`.
Expected: per-model cold run, two warm runs, cancellation run, and WAV outputs.

- [ ] **Step 2: Perform listening review**

Listen to short Chinese, mixed technical text, numbers/symbols, and long paragraph for each model. Record omissions, truncation, garbling, unnatural pauses, and subjective quality without converting subjective notes into fabricated numeric scores.

- [ ] **Step 3: Run the disconnected benchmark**

Disable network access for each worker process and rerun one complete corpus pass.
Expected: no passing model attempts a network request.

- [ ] **Step 4: Write qualification state atomically**

Mark passed only when all required runs, listening checks, cancellation, and offline rerun pass. Failed manifests retain exact failure phases and remain invisible to the future UI.

- [ ] **Step 5: Commit results**

```bash
git add docs/tts/local-tts-benchmark-results.json docs/tts/local-tts-qualification.md
git commit -m "docs: qualify local TTS candidates"
```

### Task 7: Delete only verified duplicates and residuals

**Files:**
- Create: `tools/tts_verified_cleanup.py`
- Test: `native/Tests/TTSVerifiedCleanupCheck.py`
- Create: `docs/tts/local-tts-cleanup-report.json`

**Interfaces:**
- Consumes: migration hashes plus passing qualification manifests.
- Produces: exact deletion plan and executed cleanup report.

- [ ] **Step 1: Write failing deletion-guard tests**

Tests must reject Reader Demo paths, hash mismatch, failed qualification, missing target, symlink escape, broad roots, and a source still listed as required by a retained runtime.

- [ ] **Step 2: Run and verify failure**

Run: `python3 native/Tests/TTSVerifiedCleanupCheck.py`
Expected: FAIL because cleanup tool is absent.

- [ ] **Step 3: Implement dry-run-first cleanup**

Require `--plan`, refuse deletion without exact file paths, and default to macOS Trash for material files. Delete empty staging directories directly only after containment validation.

- [ ] **Step 4: Review the exact plan**

Run: `python3 tools/tts_verified_cleanup.py --report ... --qualification ... --dry-run`.
Expected: no Reader Demo path, no unqualified model source, and every deletion lists recoverability and bytes.

- [ ] **Step 5: Execute and verify**

Run with `--execute`, then rerun inventory and one offline benchmark per passing model.
Expected: promoted models still work; cleanup report records reclaimed bytes.

- [ ] **Step 6: Commit**

```bash
git add tools/tts_verified_cleanup.py native/Tests/TTSVerifiedCleanupCheck.py docs/tts/local-tts-cleanup-report.json docs/tts/local-tts-inventory.json
git commit -m "tool: clean verified TTS duplicates safely"
```
