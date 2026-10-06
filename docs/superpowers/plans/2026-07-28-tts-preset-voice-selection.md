# TTS Preset Voice Selection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add truthful per-model preset voice selection to the installed TypeWhale Pro reading lab for both Qwen Core ML variants and Kokoro v1.1.

**Architecture:** Introduce a typed voice catalog and keep voice qualification separate from model qualification. The UI persists a stable voice ID per model, while the shared worker protocol carries `voiceID`; engine adapters resolve that ID to a Qwen string voice or Kokoro integer speaker ID. A standalone offline qualification tool tests all 121 model/voice combinations represented by 112 unique presets before the UI exposes them.

**Tech Stack:** Swift/AppKit, Foundation `Process`, JSONL, TTSKit/Core ML, sherpa-onnx, Python qualification tooling, WAV validation.

## Global Constraints

- Only model-bundled preset voices are in scope; no reference audio, cloning, recording, imported voice library, Voice Design, style, emotion, or speed control.
- Qwen has 9 presets per model; Kokoro v1.1 has 103 speakers. Both Qwen variants must be qualified independently.
- Current defaults remain `uncle-fu` for Qwen and `zf_086` / speaker ID 50 for Kokoro.
- A voice is selectable only after Chinese, English, and mixed samples all produce valid non-silent finite WAV files.
- Reader Demo, OpenClaw, ASR, VAD, smart rewrite, paste, auto-send, model cleanup, and final model selection are do-not-touch.
- Input text remains private. Results may store model ID, voice ID, character count, text hash, metrics, and output filename, but never the text.
- Production changes use RED → GREEN TDD, atomic commits, design review, a unique build number, installation to `/Applications/TypeWhale Pro.app`, launch, signature verification, and installed-app playback.
- Existing unrelated untracked directories are protected and must never be staged.

---

## File Structure

**Create**

- `native/Sources/Infrastructure/TTSLab/TTSLabVoice.swift`: stable voice identity, engine value, display metadata, qualification state, and built-in catalogs.
- `native/Sources/Infrastructure/TTSLab/TTSLabVoiceQualificationStore.swift`: loads versioned per-model voice qualification evidence from Application Support.
- `native/Tests/TTSLabVoiceCatalogCheck.swift`: exact Qwen/Kokoro count, uniqueness, grouping, and default checks.
- `native/Tests/TTSLabVoiceQualificationStoreCheck.swift`: fingerprint and fallback behavior.
- `tools/tts_voice_qualification.py`: offline 121-combination qualification runner and atomic evidence writer.
- `native/Tests/TTSVoiceQualificationCheck.py`: temporary-worker test for pass/fail, uniqueness, identical-audio rejection, and atomic output.

**Modify**

- `native/Sources/Infrastructure/TTSLab/TTSLabModel.swift`: expose qualified voices without conflating voice and model qualification.
- `native/Sources/Infrastructure/Settings/TTSReadingLabSettings.swift`: persist one stable voice ID per model.
- `native/Sources/Infrastructure/TTSLab/TTSLabWorkerClient.swift`: send `voiceID`, decode the actual voice ID returned by the worker, and return it with metrics.
- `native/Resources/tts_benchmark_worker.py`: validate/echo `voiceID` and map Kokoro names to speaker IDs.
- `native/Helpers/TTSKitBridge/Sources/TypeWhaleTTSKitWorker/main.swift`: remove hard-coded `uncle-fu`, validate Qwen voice IDs, and echo the selected voice.
- `native/Sources/Application/TTSReadingLabService.swift`: accept a selected voice and persist actual usage.
- `native/Sources/Infrastructure/TTSLab/TTSLabResultStore.swift`: add `voiceID`.
- `native/Sources/Presentation/Main/TTSReadingLabView.swift`: add the voice row and callback.
- `native/Sources/Presentation/Main/MainViewController+TTSReadingLab.swift`: populate, restore, lock, and pass voice selection.
- Relevant Swift/Python/source boundary tests, docs, version history, and build metadata.

---

### Task 1: Define the Voice Catalog and Qualification Boundary

**Files:**
- Create: `native/Sources/Infrastructure/TTSLab/TTSLabVoice.swift`
- Create: `native/Sources/Infrastructure/TTSLab/TTSLabVoiceQualificationStore.swift`
- Modify: `native/Sources/Infrastructure/TTSLab/TTSLabModel.swift`
- Test: `native/Tests/TTSLabVoiceCatalogCheck.swift`
- Test: `native/Tests/TTSLabVoiceQualificationStoreCheck.swift`

**Interfaces:**
- Produces: `TTSLabVoice`, `TTSLabVoiceCatalog.candidates(for:)`, `TTSLabVoiceQualificationStore.qualifiedVoiceIDs(modelID:fingerprint:)`, and `TTSLabModel.withVoices(_:)`.
- Consumers: Tasks 2–6 use stable `voice.id` and `voice.engineValue`.

- [ ] **Step 1: Write the failing catalog test**

```swift
let qwen06 = TTSLabVoiceCatalog.candidates(for: "qwen3-tts-06b-coreml")
let qwen17 = TTSLabVoiceCatalog.candidates(for: "qwen3-tts-17b-coreml")
let kokoro = TTSLabVoiceCatalog.candidates(for: "kokoro-int8-multi-lang-v1_1")
precondition(qwen06.count == 9)
precondition(qwen17.count == 9)
precondition(kokoro.count == 103)
precondition(qwen06.map(\.id) == qwen17.map(\.id))
precondition(Set(kokoro.map(\.id)).count == 103)
precondition(qwen06.first(where: \.isDefault)?.id == "uncle-fu")
precondition(kokoro.first(where: \.isDefault)?.id == "zf_086")
precondition(kokoro.first(where: { $0.id == "zf_086" })?.speakerID == 50)
precondition(TTSLabVoiceCatalog.candidates(for: "sherpa-vits-melo-tts-zh_en").isEmpty)
```

- [ ] **Step 2: Run the catalog test and verify RED**

Run:

```bash
swiftc native/Sources/Infrastructure/TTSLab/TTSLabVoice.swift \
  native/Tests/TTSLabVoiceCatalogCheck.swift \
  -o /tmp/TTSLabVoiceCatalogCheck
```

Expected: compile failure because `TTSLabVoice` and its catalog do not exist.

- [ ] **Step 3: Implement the immutable voice model and exact official catalogs**

```swift
enum TTSLabVoiceGroup: String, Codable {
    case qwen, chineseFemale, chineseMale, english
}

struct TTSLabVoice: Codable, Equatable, Identifiable {
    let id: String
    let displayName: String
    let detail: String
    let group: TTSLabVoiceGroup
    let speakerID: Int?
    let isDefault: Bool
}

enum TTSLabVoiceCatalog {
    static func candidates(for modelID: String) -> [TTSLabVoice] {
        switch modelID {
        case "qwen3-tts-06b-coreml", "qwen3-tts-17b-coreml":
            return qwenVoices
        case "kokoro-int8-multi-lang-v1_1":
            return kokoroVoices
        default:
            return []
        }
    }
}
```

Encode all 9 Qwen entries from `Qwen3Speaker` and all 103 official Kokoro mappings from the approved spec. Do not derive missing IDs by sequence because the official `zf_*`/`zm_*` names are sparse.

- [ ] **Step 4: Write the failing qualification-store test**

```swift
try evidence.write(to: root.appendingPathComponent("qwen.json"))
let store = TTSLabVoiceQualificationStore(root: root)
precondition(
    store.qualifiedVoiceIDs(modelID: "qwen", fingerprint: "coreml-v1")
        == Set(["uncle-fu", "serena"])
)
precondition(
    store.qualifiedVoiceIDs(modelID: "qwen", fingerprint: "coreml-v2").isEmpty
)
```

- [ ] **Step 5: Implement versioned, containment-safe evidence loading**

Evidence schema:

```json
{
  "modelID": "qwen3-tts-06b-coreml",
  "fingerprint": "qwen3-tts-coreml-0.6b-v1",
  "suite": ["zh-short-v1", "en-short-v1", "mixed-v1"],
  "voices": {"uncle-fu": "passed", "serena": "passed"}
}
```

Malformed, mismatched, symlink-escaped, or stale-fingerprint evidence returns an empty set.

- [ ] **Step 6: Run both tests**

Expected: both print `passed`, with 9/9/103 counts and stale evidence rejected.

- [ ] **Step 7: Commit**

```bash
git add native/Sources/Infrastructure/TTSLab/TTSLabVoice.swift \
  native/Sources/Infrastructure/TTSLab/TTSLabVoiceQualificationStore.swift \
  native/Sources/Infrastructure/TTSLab/TTSLabModel.swift \
  native/Tests/TTSLabVoiceCatalogCheck.swift \
  native/Tests/TTSLabVoiceQualificationStoreCheck.swift
git commit -m "feat(tts): define qualified preset voice catalogs"
```

### Task 2: Generalize the Worker Protocol from Speaker IDs to Voice IDs

**Files:**
- Modify: `native/Sources/Infrastructure/TTSLab/TTSLabWorkerClient.swift`
- Modify: `native/Resources/tts_benchmark_worker.py`
- Modify: `native/Helpers/TTSKitBridge/Sources/TypeWhaleTTSKitWorker/main.swift`
- Test: `native/Tests/TTSBenchmarkProtocolCheck.py`
- Test: `native/Tests/TTSLabWorkerCancellationCheck.swift`
- Test: `native/Tests/TTSKitCoreMLProbe.sh`

**Interfaces:**
- Consumes: Task 1 `TTSLabVoice.id` and `speakerID`.
- Produces: `TTSLabSynthesisResult(metrics:actualVoiceID:)` and `TTSLabWorkerClient.synthesize(text:outputURL:voice:)`.

- [ ] **Step 1: Extend the fake-worker test and verify RED**

Send:

```python
{
    "id": "synthesize",
    "type": "synthesize",
    "text": "你好 TypeWhale",
    "output": str(output),
    "voiceID": "test-voice",
}
```

Assert:

```python
assert synthesized["voiceID"] == "test-voice"
```

Expected: FAIL because the worker currently only accepts `speakerID`.

- [ ] **Step 2: Implement protocol validation and Kokoro resolution**

For `fake`, echo any non-empty `voiceID`. For Kokoro, use an exact immutable name-to-ID map and call:

```python
voice_id = request.get("voiceID")
speaker_id = KOKORO_SPEAKER_IDS[voice_id]
samples = engine.generate(text, mark_first_audio, speaker_id)
```

Unknown or empty IDs return `ok: false` with `unknown voice`, never speaker 0 fallback.

- [ ] **Step 3: Write the failing Swift client test**

```swift
let result = try client.synthesize(
    text: "你好",
    outputURL: output,
    voice: TTSLabVoice.test(id: "test-voice")
)
precondition(result.actualVoiceID == "test-voice")
```

- [ ] **Step 4: Return typed synthesis results**

```swift
struct TTSLabSynthesisResult {
    let metrics: TTSLabMetrics
    let actualVoiceID: String
}
```

Decode `voiceID` from worker responses and reject a mismatch between requested and actual voice.

- [ ] **Step 5: Make the TTSKit worker accept official Qwen IDs**

Replace:

```swift
voice: "uncle-fu"
```

with:

```swift
guard let voiceID = request["voiceID"] as? String,
      Qwen3Speaker(rawValue: voiceID) != nil else {
    throw WorkerError.invalidArguments("unknown voice")
}
let result = try await tts.generate(text: text, voice: voiceID, language: language)
```

Echo `voiceID` in the completion response.

- [ ] **Step 6: Run protocol, Core ML health, unknown-ID, and cancellation tests**

Expected: known voices echo exactly, unknown voices fail, cancellation remains bounded, and neither Qwen worker contains a hard-coded generation voice.

- [ ] **Step 7: Commit**

```bash
git add native/Sources/Infrastructure/TTSLab/TTSLabWorkerClient.swift \
  native/Resources/tts_benchmark_worker.py \
  native/Helpers/TTSKitBridge/Sources/TypeWhaleTTSKitWorker/main.swift \
  native/Tests/TTSBenchmarkProtocolCheck.py \
  native/Tests/TTSLabWorkerCancellationCheck.swift \
  native/Tests/TTSKitCoreMLProbe.sh
git commit -m "feat(tts): carry stable voice IDs through workers"
```

### Task 3: Persist Per-Model Voice Choice and Result Evidence

**Files:**
- Modify: `native/Sources/Infrastructure/Settings/TTSReadingLabSettings.swift`
- Modify: `native/Sources/Infrastructure/TTSLab/TTSLabResultStore.swift`
- Modify: `native/Sources/Application/TTSReadingLabService.swift`
- Test: `native/Tests/TTSReadingLabSettingsCheck.swift`
- Test: `native/Tests/TTSReadingLabServiceCheck.swift`

**Interfaces:**
- Consumes: Task 2 synthesis result.
- Produces: `loadVoiceID(modelID:availableVoices:)`, `saveVoiceID(_:modelID:)`, and `start(text:model:voice:)`.

- [ ] **Step 1: Write failing settings tests**

```swift
settings.saveVoiceID("serena", modelID: "qwen-06")
settings.saveVoiceID("zf_086", modelID: "kokoro")
precondition(settings.loadVoiceID(modelID: "qwen-06", availableVoices: qwen) == "serena")
precondition(settings.loadVoiceID(modelID: "kokoro", availableVoices: kokoro) == "zf_086")
precondition(
    settings.loadVoiceID(modelID: "qwen-06", availableVoices: [.uncleFu])
        == "uncle-fu"
)
```

- [ ] **Step 2: Implement one dictionary-valued UserDefaults key**

Use `ttsReadingLabVoiceIDsByModel`. Store only model-to-voice strings. On missing or invalid IDs, return the available default, otherwise the first available voice.

- [ ] **Step 3: Write failing service and privacy-result tests**

Call:

```swift
service.start(text: "你好", model: model, voice: voice)
```

Assert the fake worker receives `voice.id`, and `results.jsonl` contains `"voiceID":"test-voice"` but not the input text.

- [ ] **Step 4: Thread selected and actual voice through the service**

The service passes the selected voice to the worker. On completion, the controller stores the worker-confirmed actual voice. A mismatch or missing voice is a controlled failure and deletes the partial WAV.

- [ ] **Step 5: Run settings, service, WAV, and privacy tests**

Expected: independent model selections survive; invalid selection falls back; actual voice is recorded; input text remains absent.

- [ ] **Step 6: Commit**

```bash
git add native/Sources/Infrastructure/Settings/TTSReadingLabSettings.swift \
  native/Sources/Infrastructure/TTSLab/TTSLabResultStore.swift \
  native/Sources/Application/TTSReadingLabService.swift \
  native/Tests/TTSReadingLabSettingsCheck.swift \
  native/Tests/TTSReadingLabServiceCheck.swift
git commit -m "feat(tts): persist model-specific preset voices"
```

### Task 4: Qualify All Preset Voices Offline

**Files:**
- Create: `tools/tts_voice_qualification.py`
- Create: `native/Tests/TTSVoiceQualificationCheck.py`
- Modify: `native/Sources/Infrastructure/TTSLab/TTSLabEvaluationSuite.swift`
- Test: `native/Tests/TTSLabEvaluationSuiteCheck.swift`

**Interfaces:**
- Consumes: Tasks 1–2 catalogs and protocol.
- Produces: versioned evidence JSON consumed by Task 1’s store.

- [ ] **Step 1: Write a failing temporary qualification test**

The fake worker must model:

- two passing voices with different PCM;
- one silent voice;
- one non-finite/invalid voice;
- one voice that returns the same PCM as another voice.

Assert only the two distinct valid voices are marked `passed`, evidence is written atomically, and an interrupted run does not replace prior evidence.

- [ ] **Step 2: Implement the fixed three-sample runner**

Use exact IDs:

```python
SAMPLES = {
    "zh-short-v1": "你好，欢迎使用 TypeWhale 本地朗读测试。",
    "en-short-v1": "The quick brown fox jumps over the lazy dog.",
    "mixed-v1": "TypeWhale 使用 Core ML 完成本地 TTS 测试。",
}
```

For each model/voice, launch offline, prepare once, synthesize all three, validate WAV, and store per-sample metrics and SHA-256.

- [ ] **Step 3: Implement same-model distinctness validation**

For the same text, compare decoded PCM SHA-256. Identical output across different requested voices marks the later voice `failed: voice_parameter_ineffective`. Do not compare files including WAV metadata.

- [ ] **Step 4: Run the temporary qualification test**

Expected: exact pass/fail counts, no partial evidence, no network, and no input text in evidence.

- [ ] **Step 5: Run the real 121-combination matrix**

Run:

```bash
python3 tools/tts_voice_qualification.py \
  --repo "$PWD" \
  --model-root "$HOME/Library/Application Support/TypeWhale Pro/Models/tts" \
  --runtime-root "$HOME/Library/Application Support/TypeWhale Pro/Runtimes/tts" \
  --output-root "$HOME/Library/Application Support/TypeWhale Pro/TTSLab/VoiceQualifications"
```

Expected:

- Qwen 0.6B: 9 attempted.
- Qwen 1.7B: 9 attempted.
- Kokoro: 103 attempted.
- Every exposed voice passes all three samples and distinctness checks.
- Failures remain absent from product menus and retain diagnostic evidence.

- [ ] **Step 6: Commit tooling and tests**

Do not commit generated WAV or Application Support evidence.

```bash
git add tools/tts_voice_qualification.py \
  native/Tests/TTSVoiceQualificationCheck.py \
  native/Sources/Infrastructure/TTSLab/TTSLabEvaluationSuite.swift \
  native/Tests/TTSLabEvaluationSuiteCheck.swift
git commit -m "test(tts): qualify preset voices offline"
```

### Task 5: Add the Voice Dropdown to the Reading Lab

**Files:**
- Modify: `native/Sources/Presentation/Main/TTSReadingLabView.swift`
- Modify: `native/Sources/Presentation/Main/MainViewController+TTSReadingLab.swift`
- Modify: `native/Sources/Presentation/Main/MainViewController.swift`
- Modify: `native/Tests/TTSReadingLabViewSourceCheck.sh`

**Interfaces:**
- Consumes: qualified voices, per-model settings, and `start(text:model:voice:)`.
- Produces: `voicePopup`, `onVoiceChange`, `refreshTTSReadingLabVoiceMenu()`.

- [ ] **Step 1: Write failing source/UI boundary checks**

Require:

```text
let voicePopup = NSPopUpButton()
setAccessibilityLabel("朗读音色")
onVoiceChange
ttsReadingLabSettings.saveVoiceID
ttsReadingLabService.start(text: text, model: model, voice: voice)
voicePopup.isEnabled = false
```

Also assert no OpenClaw voice settings type appears in reading-lab files.

- [ ] **Step 2: Add the voice row**

Place it directly below the model row:

```swift
let voiceRow = NSStackView(views: [
    NSTextField(labelWithString: "音色"),
    voicePopup,
])
```

Use the existing system font, row alignment, spacing, width, and popup styling.

- [ ] **Step 3: Populate qualified voices and fixed-state copy**

On model change:

- empty official catalog → one disabled `固定音色`;
- official catalog but zero qualified → one disabled `暂无可用音色`;
- qualified catalog → grouped menu, restore stored/default voice, enable.

Disabled group headings must not be interpreted as selected voices.

- [ ] **Step 4: Pass and persist selection**

Saving occurs on user change. Playback resolves the selected item’s represented voice ID and refuses to start if the model requires a voice but none is valid.

- [ ] **Step 5: Lock selection during active work**

`applyTTSReadingLabState` disables both popups for preparing, generating, and playing. Idle, completed, stopped, and failed restore availability without losing selection or text.

- [ ] **Step 6: Run view, settings, service, Reader Demo, and OpenClaw boundary tests**

Expected: UI/source checks pass; fixed models remain playable with disabled voice control; qualifying models require a valid voice.

- [ ] **Step 7: Commit**

```bash
git add native/Sources/Presentation/Main/TTSReadingLabView.swift \
  native/Sources/Presentation/Main/MainViewController+TTSReadingLab.swift \
  native/Sources/Presentation/Main/MainViewController.swift \
  native/Tests/TTSReadingLabViewSourceCheck.sh
git commit -m "feat(tts): add qualified preset voice picker"
```

### Task 6: Review, Build, Install, and Verify

**Files:**
- Modify: `docs/开发日志.md`
- Modify: `native/Sources/Presentation/VersionHistory/VersionHistoryViewController.swift`
- Modify via build: `README.md`, `macos/README.md`, `native/build_native_app.sh`, `docs/构建日志.md`

**Interfaces:**
- Consumes: complete feature.
- Produces: signed installed build and manual evidence.

- [ ] **Step 1: Run concurrency and protected-worktree checks**

Verify correct branch, status, build processes, mtimes, and existing protected untracked directories before documentation or build writes.

- [ ] **Step 2: Update documentation for the next build**

Document:

- supported models and counts;
- validation filtering;
- defaults unchanged;
- cloning explicitly out of scope;
- Reader/OpenClaw boundary unchanged.

- [ ] **Step 3: Run all relevant automated checks**

Run the new catalog, store, protocol, qualification, settings, service, UI, packaging, Reader Demo, and OpenClaw tests plus `git diff --check`.

- [ ] **Step 4: Perform design review**

Review installed-width label fit, 103-item Kokoro navigation, grouping, disabled fixed-state clarity, focus order, playback locking, no flicker, and persistence after relaunch. Apply only in-scope findings with regression checks.

- [ ] **Step 5: Build and install**

Run:

```bash
./native/build_and_log.sh
```

Expected: build number increments from 855, the app installs to `/Applications/TypeWhale Pro.app`, launches, and passes deep/strict signature validation.

- [ ] **Step 6: Verify the real installed app**

Required manual matrix:

- Qwen 0.6B: select `uncle-fu` and `serena`; both play, outputs differ.
- Qwen 1.7B: select `dylan` and `vivian`; both play, outputs differ.
- Kokoro: select one qualified Chinese female and one qualified Chinese male; both play.
- Switch away and back; each model restores its voice.
- Relaunch; selections and editable text persist.
- The other five models show disabled `固定音色` and still play.
- Stop and replay continue to work.

- [ ] **Step 7: Re-run post-build evidence**

Verify installed worker hashes, installed version, signature, core tests, voice evidence counts, and `git status --short`.

- [ ] **Step 8: Commit the build record**

Stage only build-generated version files and this task’s docs:

```bash
git commit -m "build: install TypeWhale Pro 2.0.58 build 856"
```

Do not stage unrelated untracked directories.
