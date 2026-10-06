# ZipVoice-Only TTS Consolidation Design

**Status:** Approved for staged execution
**Date:** 2026-07-28
**Decision owner:** TypeWhale product owner

## Goal

TypeWhale Pro retains one local TTS model, `zipvoice-distill-int8-zh-en-emilia`,
with its four qualified reference voices. The Sounds reading experience and
OpenClaw use the same ZipVoice model, voice catalog, validation rules, and
worker protocol. All other TypeWhale Pro TTS models and their exclusive
runtimes are retired only after the installed application proves that ZipVoice
has taken over every production TTS path.

## Scope

In scope:

- ZipVoice as the only TypeWhale Pro TTS model.
- The existing four qualified voices:
  `zipvoice-default`, `zipvoice-serena`, `zipvoice-cosy`, and
  `zipvoice-video-reference`.
- OpenClaw prewarm, synthesis, playback, queueing, interruption, cancellation,
  volume, speech rate, and persisted voice selection.
- The Sounds reading panel, TTS model catalog, runtime resolution, managed model
  catalog, build resources, tests, notices, and cleanup tooling.
- Recoverable removal of retired TypeWhale Pro TTS assets after all gates pass.

Out of scope and do-not-touch:

- Reader Demo and all resources below its Application Support root.
- ASR, VAD, punctuation, LLM, rewriting, hotwords, and screenshot/OCR paths.
- Permanent deletion or emptying of macOS Trash.
- Removing the four ZipVoice references, their manifests, licenses, lexicon,
  vocoder, or runtime dependencies.
- Rewriting historical release notes merely because they mention retired
  engines.

## Architecture

Both product surfaces depend on one persistent ZipVoice session boundary:

```text
Sounds reading panel ─┐
                      ├─ ZipVoice session → validated worker → WAV → playback
OpenClaw ──────────────┘
```

The session owns process lifecycle, warm reuse, request/response identity,
selected and actual voice identity, output validation, cancellation, and
shutdown. OpenClaw keeps its product policies—final reply versus manual
preview, queueing versus interruption, volume, and speech rate—but no longer
selects a TTS engine.

The current Python-backed ZipVoice worker is the first migration target because
it is already qualified and supports a persistent JSON-lines protocol. Native
Sherpa execution remains a separate follow-up experiment: the cleanup must not
claim that Python has been removed until a native ZipVoice implementation has
passed the same contract and quality gates.

## Persisted Settings

- Existing OpenClaw engine values migrate to the single ZipVoice engine.
- OpenClaw persists a ZipVoice `voiceID`.
- Invalid or retired voice IDs resolve to `zipvoice-default`.
- A worker response with a missing or different `voiceID` is a controlled
  failure; it must not play the generated file.
- Reading-panel and OpenClaw voice choices may remain independent, but both draw
  from the same immutable four-voice catalog and qualification evidence.

## Failure and Recovery

- Missing or invalid ZipVoice assets produce an explicit local-model error.
- There is no silent fallback to Melo, Kokoro, Qwen, CosyVoice, MOSS, or
  VoxCPM.
- Cancellation terminates the active synthesis and removes partial output.
- Cleanup is locked until installed-app verification passes.
- Retired assets are moved to uniquely named locations in macOS Trash with a
  manifest recording original path, trash path, byte count, and timestamp.
- Any migration regression before physical cleanup rolls back by restoring the
  previous build. Any regression after cleanup additionally restores assets
  from the recorded Trash locations.

## Cleanup Manifest and Safety Gates

The cleanup planner uses exact absolute paths and separates:

1. protected assets;
2. retained ZipVoice assets;
3. retired TypeWhale Pro models;
4. runtimes exclusive to retired models;
5. staging residue;
6. evaluation outputs that require an explicit retention rule;
7. legacy `LocalTTSLab` assets that require separate provenance verification.

It rejects a plan when a target is a symlink, is outside an approved root, is
the root itself, overlaps Reader Demo, or contains the retained ZipVoice pack.
Execution supports dry-run and requires a signed verification record from the
current installed build before it can move anything.

## Verification Gates

Before cleanup:

- Four ZipVoice voices pass qualification and reference hash validation.
- OpenClaw cold start, warm reuse, long Chinese, English, mixed text, three
  consecutive replies, stop, latest-wins interruption, and queued playback pass.
- Runtime evidence reports the ZipVoice model ID and actual voice ID.
- No production route selects a retired engine.
- The installed app is signed and the packaged worker matches the source.

After cleanup:

- Sounds exposes one model and four voices.
- OpenClaw exposes voice choice but not engine choice.
- The app succeeds offline after restart.
- Retired model and exclusive runtime paths are absent from TypeWhale Pro.
- Reader Demo hashes and directory inventory are unchanged.
- Actual reclaimed bytes match the manifest within filesystem metadata
  tolerance.
- Build resources, production code, catalogs, download entries, and active
  tests contain no retired runtime path. Historical documents remain intact.

## Retirement Order

1. Add audit manifest and safety tests.
2. Add shared ZipVoice session contract and migrate OpenClaw behind tests.
3. Remove retired choices and acquisition paths from product code.
4. Build, install, and verify the real app.
5. Generate a fresh dry-run cleanup manifest.
6. Move only verified retired assets to Trash.
7. Restart and repeat installed-app verification.
8. Commit cleanup evidence and retain rollback information.

## Reopen Triggers

Reopen this decision if ZipVoice cannot satisfy the OpenClaw interruption or
long-form quality gates, if peak memory materially exceeds the established
baseline, if one of the four voice licenses prevents product use, or if native
ZipVoice quality differs from the qualified Python-backed path.
