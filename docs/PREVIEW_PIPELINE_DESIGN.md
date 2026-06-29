# TypeWhale Preview Pipeline Design

> Iteration note: the product and visual interaction decisions for the small recording capsule are tracked in `docs/预览层小胶囊迭代记录.md`.

> **现状更新（1.5.8–1.5.10，2026-06-29）：实时预览改为「分块提交」流水线。**
> 录音切成块，只对「当前块」反复重识别（开销恒定，封住长录音的 O(n²) 重识别）；块满即把识别结果冻结进 `committedPreviewText`、永不再改，显示 = `已提交前缀 + 当前块尾巴`。块最终快照走专用队列 `pendingFinalSnapshots`、绝不丢弃。
> 块边界**停顿对齐**：块到软目标(10s)后等 Silero 判定的停顿出现再在停顿处提交（避免切词），一直不停顿则硬上限(18s)兜底。与 1.4.30 删除的「停顿后重置窗口」不同：本方案**冻结前缀、永不重置已显示文本**。
> 相关代码：`SpeechInputCoordinator.applyRealtimePreview`、`AudioRecorder`（分块/停顿对齐）、`SpeechInputState.SpeechSession`。

## Problem

The current realtime preview is built from rolling audio snapshots. Each snapshot is transcribed independently, then merged into a visual preview.

This can cause:

- duplicated fragments
- broken word starts or endings
- Chinese repeated fragments
- English partial words
- visible jumping
- preview text differing from final transcript
- product confusion about whether preview is final text

## Design Principle

Realtime preview is not final transcription.

It is a confidence anchor whose goals are:

- let the user clearly see what TypeWhale currently thinks they are saying
- appear quickly enough to support live self-correction
- remain readable across natural pauses and silence
- avoid obvious duplication
- avoid heavy backward jumping
- give the user enough certainty to continue speaking

Final paste must use full audio transcription.

## Target Flow

```text
Audio cumulative snapshot
-> raw realtime ASR text
-> RecordingCapsuleView visual cache
```

## Current Product Choice

The active product path follows a stability-first variant of the v1.2 baseline:

- realtime snapshots are cumulative during a recording
- the realtime ASR result is passed to the capsule only after realtime VAD
- the capsule owns only visual catch-up state
- ordinary pauses must not reset the realtime audio window
- realtime audio buffers are not trimmed during a normal recording; preserving context is more important than minimizing snapshot size
- final paste never consumes realtime preview text

Do not commit/reset the realtime preview window on short natural pauses. A short
silence, breath, or thinking pause is part of normal speech; treating it as a
segment boundary causes the capsule to restart the preview too often and makes
the text appear to jump.

Do not trim the realtime audio window on a short sliding horizon while the user
is still recording. A sliding offline-ASR window can cut the sentence head after
silence or a long pause, causing the next recognition result to lose context and
visibly diverge from the previously displayed text. The proven workaround for
the current non-streaming ASR architecture is cumulative context.

For the current cumulative-snapshot architecture, the capsule should restore
the v1.2 visual cache behavior: refresh the already-visible character span from
the latest cumulative ASR result, then animate any newly appended tail. Do not
apply the later short-segment "clean replacement" rule to this path; that rule
was a workaround for reset/sliding-window previews, and it made the capsule feel
less stable than the 1.2 baseline.

## Capsule View Responsibility

`RecordingCapsuleView` should not decide text strategy.

Current active behavior:

- owns the v1.2-style visual catch-up cache
- renders text, waveform, and capsule transitions
- receives raw realtime draft text from the coordinator
- never participates in final paste
- may refresh the current visible span from the latest cumulative ASR result
- must not receive short-window segment drafts that would make positional refresh mix unrelated text

Future target:

- draw the capsule
- animate text display
- apply visual styling
- render `CapsulePreviewViewModel`

It should not:

- merge ASR text
- decide committed text
- infer language-specific rules
- correct duplicate fragments

## Minimum Test Scenarios

- Chinese continuous sentence
- Chinese repeated fragments
- English continuous sentence
- English partial word at snapshot start
- English repeated tail
- mixed Chinese and English
- disconnected snapshot
- pending realtime snapshot after stop
- final transcript arrives while preview is still active

## Non-goals

- Do not use preview as final paste text.
- Do not add language model correction in this phase.
- Do not redesign ASR engine in this phase.
- Do not create a candidate selection UI in this phase.
