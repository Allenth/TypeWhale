# TypeWhale Preview Pipeline Design

> Iteration note: the product and visual interaction decisions for the small recording capsule are tracked in `docs/预览层小胶囊迭代记录.md`.

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

It is a temporary listening aid whose goals are:

- appear quickly
- remain readable
- avoid obvious duplication
- avoid heavy backward jumping
- give confidence that recording is working

Final paste must use full audio transcription.

## Target Flow

```text
Audio cumulative snapshot
-> raw realtime ASR text
-> RecordingCapsuleView visual cache
```

## Current Product Choice

The active product path follows the v1.1.1 baseline:

- realtime snapshots are cumulative during a recording
- the realtime ASR result is passed directly to the capsule
- the capsule owns only visual catch-up state
- final paste never consumes realtime preview text

## Capsule View Responsibility

`RecordingCapsuleView` should not decide text strategy.

Current active behavior:

- owns the v1.1.1-style visual catch-up cache
- renders text, waveform, and capsule transitions
- receives raw realtime draft text from the coordinator
- never participates in final paste

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
