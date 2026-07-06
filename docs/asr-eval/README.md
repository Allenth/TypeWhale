# Pro ASR Hotword Evaluation

This folder is the first execution step for the TypeWhale Pro ASR upgrade. It defines a shared evaluation set for Chinese-English mixed dictation and developer hotwords before any experimental model is connected to final paste.

## Product Target

The Pro ASR path must improve recognition of developer terms at the audio or decoder stage. Text-only cleanup is not enough because the current failure mode often loses the English word before post-processing can see it.

Primary terms for the first round:

- `Codex`
- `Obsidian`
- `Qwen3-ASR`
- `SpeechInputCoordinator`
- `sherpa-onnx`
- `FunASR`
- `Paraformer Contextual`
- `ModelScope`

## Files

- `pro-hotword-eval-cases.json`: seed manifest of utterances to record and compare.
- `audio/`: local WAV recordings for the manifest cases. Do not commit private voice samples unless the recording is explicitly cleared for repository storage.
- `results/`: local JSONL outputs from model comparisons. Commit only summarized, non-sensitive results.

## First Round Procedure

1. Open `pro-hotword-eval-cases.json`.
2. Record each `expectedText` exactly once in a natural speaking style.
3. Save recordings as 16 kHz mono WAV files using the path in `audioPath`.
4. Change each recorded case from `recordingStatus: "needs_recording"` to `recordingStatus: "recorded"`.
5. Run:

```bash
bash native/Tests/ProASREvalManifestCheck.sh
```

6. Compare at least these providers:
   - current TypeWhale ASR baseline
   - Paraformer Contextual with hotword file
   - Fun-ASR-Nano-2512 with hotwords
   - Paraformer zh as non-contextual comparison

## Scoring

For every provider and case, record:

- raw recognized text
- elapsed milliseconds
- required hotwords hit
- required hotwords missing
- obvious Chinese skeleton regression
- model/runtime error

The first provider allowed into an experimental final-ASR switch must beat the current baseline on required hotword recall without obvious Chinese skeleton regression.

## Dry-Run Runner

Before wiring Python FunASR runtime, verify the manifest and result contract with:

```bash
python3 tools/asr-eval/run_funasr_eval.py \
  --manifest docs/asr-eval/pro-hotword-eval-cases.json \
  --provider dry-run \
  --hotwords tools/asr-eval/hotwords-dev.txt \
  --output /tmp/typewhale-asr-eval.jsonl
```

Expected first-version behavior:

- One JSONL row per manifest case.
- Missing local audio produces `status: "skipped"` and an `audio_missing` error.
- Rows always include `caseId`, `provider`, `rawText`, `elapsedMs`, `requiredHotwordHits`, `missingHotwords`, and `error`.

After recordings exist, the same runner contract will be reused for `paraformer-hotword-contextual`, `fun-asr-nano-2512`, and `paraformer-zh`.
