# ZipVoice Four Preset Voices Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add four qualified, selectable local ZipVoice reference voices to the TypeWhale Pro reading lab.

**Architecture:** Generate machine-local reference packs with exact transcripts and hash manifests, then make the ZipVoice worker resolve stable voice IDs through a contained manifest instead of a hard-coded WAV. Extend the existing qualified voice catalog and UI path; no general cloning UI is introduced.

**Tech Stack:** Swift/AppKit, Python JSONL worker, sherpa-onnx ZipVoice, ffmpeg, WAV PCM16, SHA-256, JSON qualification evidence.

## Global Constraints

- Four candidates: existing default news female, Qwen 0.6B Serena, current CosyVoice, and the user-supplied video voice.
- Video voice uses a neutral label and no inferred real-person identity.
- Reference processing is offline and remains in TypeWhale-managed Application Support.
- No Reader Demo, OpenClaw, ASR/VAD, rewrite, paste, auto-send, model elimination, or general cloning UI changes.
- Unknown or invalid voice IDs fail closed; no silent substitution.
- Only voices passing Chinese, English, mixed, long Chinese, and five-run stability checks appear.
- Code changes require Build 857, installation, signature verification, installed-app UI review, and a commit.

---

### Task 1: Reference Pack Contract and Builder

**Files:**
- Create: `tools/zipvoice_reference_pack.py`
- Create: `native/Tests/ZipVoiceReferencePackCheck.py`

**Interfaces:**
- Produces: `build_pack(source_audio, transcript, voice_id, output_root) -> Path`
- Produces on disk: `references/<voice-id>/{reference.wav,reference.txt,reference.json}`
- Consumers: Task 2 worker resolver and Task 3 local reference generation.

- [ ] **Step 1: Write the failing pack test**

Create a temporary mono WAV, call `build_pack`, and assert:

```python
manifest = json.loads((pack / "reference.json").read_text())
assert manifest["voiceID"] == "zipvoice-test"
assert manifest["sampleRate"] == 24000
assert manifest["channels"] == 1
assert manifest["audioSHA256"] == sha256(pack / "reference.wav")
assert (pack / "reference.txt").read_text() == "完全匹配的参考文字\n"
```

- [ ] **Step 2: Verify RED**

Run:

```bash
python3 native/Tests/ZipVoiceReferencePackCheck.py
```

Expected: import failure because `zipvoice_reference_pack.py` does not exist.

- [ ] **Step 3: Implement atomic normalization**

Implement `build_pack` using `ffmpeg` with:

```text
-vn -ac 1 -ar 24000 -c:a pcm_s16le
silenceremove=start_periods=1:start_duration=0.1:start_threshold=-50dB:
stop_periods=1:stop_duration=0.2:stop_threshold=-50dB,
loudnorm=I=-22:TP=-2:LRA=11
```

Reject unsafe voice IDs, blank transcripts, duration outside 3–30 seconds, silence, clipping over 2%, and failed atomic replacement.

- [ ] **Step 4: Verify GREEN**

Run:

```bash
python3 native/Tests/ZipVoiceReferencePackCheck.py
python3 -m py_compile tools/zipvoice_reference_pack.py
```

Expected: both pass.

- [ ] **Step 5: Commit**

```bash
git add tools/zipvoice_reference_pack.py native/Tests/ZipVoiceReferencePackCheck.py
git commit -m "feat(tts): define ZipVoice reference packs"
```

---

### Task 2: Strict ZipVoice Voice Resolution

**Files:**
- Modify: `native/Resources/tts_benchmark_worker.py`
- Modify: `native/Sources/Infrastructure/TTSLab/TTSLabWorkerClient.swift`
- Test: `native/Tests/TTSBenchmarkProtocolCheck.py`
- Create: `native/Tests/ZipVoiceWorkerVoiceCheck.py`

**Interfaces:**
- Consumes: request field `voiceID: String`
- Produces: response field `voiceID: String`
- Resolves: `<pack>/references/<voiceID>/reference.json`

- [ ] **Step 1: Write failing protocol tests**

Cover:

```python
assert synthesize("zipvoice-default")["voiceID"] == "zipvoice-default"
assert synthesize("../escape")["ok"] is False
assert synthesize("missing")["ok"] is False
assert synthesize("tampered-hash")["ok"] is False
```

- [ ] **Step 2: Verify RED**

Run:

```bash
python3 native/Tests/ZipVoiceWorkerVoiceCheck.py
```

Expected: current worker ignores `voiceID` and uses `news-female.wav`.

- [ ] **Step 3: Implement resolver**

Add a `ZipVoiceReference` loader that:

- accepts only `[A-Za-z0-9._-]+`;
- resolves paths inside `<pack>/references`;
- decodes `reference.json`;
- verifies voice ID, WAV/text hashes, PCM16 mono 24 kHz, and non-empty transcript;
- passes selected audio and transcript to `OfflineTts.generate`;
- echoes the selected voice ID.

Remove the hard-coded `news-female.wav` and transcript after the default pack is generated.

- [ ] **Step 4: Verify GREEN and compatibility**

Run:

```bash
python3 native/Tests/ZipVoiceWorkerVoiceCheck.py
python3 native/Tests/TTSBenchmarkProtocolCheck.py native/Resources/tts_benchmark_worker.py /usr/local/bin/python3
python3 -m py_compile native/Resources/tts_benchmark_worker.py
```

Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add native/Resources/tts_benchmark_worker.py \
  native/Sources/Infrastructure/TTSLab/TTSLabWorkerClient.swift \
  native/Tests/TTSBenchmarkProtocolCheck.py \
  native/Tests/ZipVoiceWorkerVoiceCheck.py
git commit -m "feat(tts): resolve ZipVoice reference voices safely"
```

---

### Task 3: Generate Four Local Reference Packs

**Files:**
- Local output only: `~/Library/Application Support/TypeWhale Pro/Models/tts/zipvoice-distill-int8-zh-en-emilia/references/`

**Interfaces:**
- Consumes: Task 1 `build_pack`.
- Produces: four reference packs consumed by Task 2.

- [ ] **Step 1: Generate common source text**

Use the exact source:

```text
今天我们用同一段声音测试 TypeWhale 的本地朗读。清晰、自然和稳定同样重要，也要正确读出 Core ML 与 ZipVoice。
```

- [ ] **Step 2: Generate Serena source**

Run the Qwen Core ML worker with `voiceID=serena`, save a WAV, then build `zipvoice-serena`.

- [ ] **Step 3: Generate CosyVoice source**

Run the current CosyVoice worker with the same exact text, save a WAV, then build `zipvoice-cosy`.

- [ ] **Step 4: Generate video source**

Build `zipvoice-video-reference` from:

```text
但是 ATS3 这个玩意儿居然能拍 10 比特 422，有 4K 120 帧，有着无比纯净的夜景。我记得当时我们拼尽了全力来给你做了一期评测，想和你分享那种兴奋感。
```

Use the supplied MP4 as source and retain the original only at its user-owned location.

- [ ] **Step 5: Migrate default**

Build `zipvoice-default` from `test_wavs/news-female.wav` and its exact bundled transcript.

- [ ] **Step 6: Validate manifests**

Run the pack checker against all four. Expected: four distinct IDs, valid hashes, mono PCM16 24 kHz, duration 3–30 seconds.

---

### Task 4: Catalog and Qualification

**Files:**
- Modify: `native/Sources/Infrastructure/TTSLab/TTSLabVoice.swift`
- Modify: `tools/tts_voice_qualification.py`
- Modify: `native/Tests/TTSLabVoiceCatalogCheck.swift`
- Modify: `native/Tests/TTSVoiceQualificationCheck.py`

**Interfaces:**
- Produces four `TTSLabVoice` values for model `zipvoice-distill-int8-zh-en-emilia`.
- Produces fingerprint `zipvoice-distill-int8-reference-voices-v1`.

- [ ] **Step 1: Write failing catalog tests**

Assert:

```swift
let voices = TTSLabVoiceCatalog.candidates(for: "zipvoice-distill-int8-zh-en-emilia")
precondition(voices.map(\.id) == [
    "zipvoice-default", "zipvoice-serena",
    "zipvoice-cosy", "zipvoice-video-reference",
])
precondition(voices.first?.isDefault == true)
```

- [ ] **Step 2: Verify RED**

Compile and run `TTSLabVoiceCatalogCheck`; expect empty ZipVoice candidates.

- [ ] **Step 3: Add catalog and qualification adapter**

Add concise experimental menu details and teach the qualification runner to start ZipVoice once, pass each voice ID, execute four fixed samples plus five mixed repeats, and write fingerprinted evidence atomically.

- [ ] **Step 4: Run full real qualification**

Expected matrix: 4 voices × 9 generations = 36 valid WAV files. Any failed voice is marked failed and omitted from the UI.

- [ ] **Step 5: Verify tests and commit**

```bash
swiftc native/Sources/Infrastructure/TTSLab/TTSLabVoice.swift \
  native/Tests/TTSLabVoiceCatalogCheck.swift -o /tmp/TTSLabVoiceCatalogCheck
/tmp/TTSLabVoiceCatalogCheck
python3 native/Tests/TTSVoiceQualificationCheck.py
git add native/Sources/Infrastructure/TTSLab/TTSLabVoice.swift \
  tools/tts_voice_qualification.py \
  native/Tests/TTSLabVoiceCatalogCheck.swift \
  native/Tests/TTSVoiceQualificationCheck.py
git commit -m "feat(tts): qualify four ZipVoice preset voices"
```

---

### Task 5: Installed App Integration and Release

**Files:**
- Modify: `docs/开发日志.md`
- Modify: `native/Sources/Presentation/VersionHistory/VersionHistoryViewController.swift`
- Build-managed version files and `docs/构建日志.md`

**Interfaces:**
- Consumes existing generic model voice menu and per-model settings.
- Produces installed Build 857.

- [ ] **Step 1: Run source and service regression tests**

Run catalog, qualification, worker protocol, settings, service, view source, runtime packaging, and Reader/OpenClaw boundary checks.

- [ ] **Step 2: Update release narrative**

Record the four experimental voices, local-only privacy boundary, qualification counts, neutral video label, and unchanged Reader/OpenClaw scope for Build 857.

- [ ] **Step 3: Check concurrency**

Run branch/status, build-process, and mtime checks. Stop if another session overlaps release files.

- [ ] **Step 4: Build and install**

```bash
./native/build_and_log.sh
```

Expected: `2.0.58 (857)`, installed, opened, and strict signature verification passed.

- [ ] **Step 5: Design and interaction review**

In the installed app:

- select ZipVoice;
- verify four qualified menu items and no truncation;
- play Serena and video reference voices;
- verify menus lock while generating;
- switch models and return to confirm persistence;
- verify result JSONL contains actual voice ID and excludes text.

- [ ] **Step 6: Commit release files**

Stage only the intended version, docs, log, and source changes after `git status --short` review.
