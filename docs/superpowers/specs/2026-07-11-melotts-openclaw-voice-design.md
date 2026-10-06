# MeloTTS OpenClaw Voice Design

## Goal

Replace the user-visible Qwen3-TTS/CosyVoice2 OpenClaw speech path with a production-oriented MeloTTS Chinese voice backend. The backend must prewarm while OpenClaw is replying, synthesize sentence-sized audio with a hot target of 0.7–1.2 seconds, preserve existing playback controls, and release its 3–4 GB working set after 180 seconds of complete inactivity.

## Product decisions

- MeloTTS is the only local natural-voice engine delivered by this branch.
- Qwen3-TTS and CosyVoice2 are removed from the OpenClaw voice settings and playback path.
- The first MeloTTS release uses one fixed Chinese speaker. It does not expose speaker cloning, voice selection, or Qwen-style role instructions.
- The voice pack is downloaded and managed separately. It is not bundled in the default DMG and the app never runs `pip install` or downloads missing runtime assets while speaking.
- The settings retain: enable speech, volume, speech rate, playback content, and interruption policy.
- A second TTS solution is owned by another session. Its final engine selector and shared settings integration are intentionally outside this branch's ownership.

## Architecture

### MeloTTS voice pack

The model manager exposes one downloadable `melotts-zh` voice pack with a versioned manifest. A complete pack contains:

- a relocatable, pinned Python 3.10 inference runtime;
- the MeloTTS Chinese checkpoint and configuration;
- the pinned multilingual BERT files required by the Chinese frontend;
- the Chinese and minimal required text-normalization data;
- a manifest containing file hashes and pack version.

The pack supports resumable download, staging, hash validation, deletion, and a clear unavailable/corrupt state. The public DMG does not contain the pack.

### Worker

`openclaw_melotts_worker.py` is a JSONL sidecar with four commands:

- `warmup`: load MeloTTS, BERT, and run a short throwaway synthesis;
- `synthesize`: generate one WAV for a sentence and return timing metadata;
- `cancel`: stop accepting work for the active reply and discard pending output;
- `shutdown`: exit cleanly.

The worker is offline-only at runtime, uses CPU consistently on macOS, and does not initialize or move tensors to MPS. It returns structured errors and never writes logs to stdout outside the JSONL protocol.

### Swift backend

`MeloTTSVoiceBackend` owns worker launch, health, request/response correlation, timeouts, cancellation, EOF cleanup, diagnostics, and the 180-second warm lifetime. It produces sentence WAV URLs and does not own global playback policy.

The existing player continues to own text cleanup, sentence splitting, volume, speech rate, queueing, interruption, and `AVAudioPlayer` playback. Qwen-only model, speaker, and instruction parameters are removed.

## Runtime flow

1. OpenClaw enters the replying state.
2. If speech is enabled and the voice pack is valid, the Melo backend starts and warms in the background.
3. The final reply is cleaned and split at Chinese/English sentence boundaries and bounded lengths.
4. The first sentence is synthesized first and played immediately when ready.
5. Later sentences synthesize while prior audio is playing.
6. Existing stop-latest, queue, and do-not-interrupt policies remain authoritative.
7. Each warmup, synthesis, or playback activity renews the idle lease.
8. After 180 seconds with no recording, recognition, synthesis, or playback activity, the Melo worker shuts down and releases memory.

## Failure behavior

- Missing pack: report that a download is required; preserve OpenClaw text and all other features.
- Invalid pack/hash: refuse execution and expose a repair/redownload state.
- Warmup failure: record the failing stage and leave text response unaffected.
- Sentence timeout: cancel the current reply's remaining synthesis without blocking the app.
- Worker crash/EOF: clear pipe handlers and process state; allow a clean restart on the next reply.
- User interruption: stop current audio and cancel not-yet-played synthesis.
- Runtime network access or package installation: prohibited.

## Observability

Diagnostics record pack version, warm/cold state, warmup duration, sentence character count, synthesis duration, time to first playable sentence, cancellation reason, worker exit status, and 180-second idle release. Diagnostics never record full private reply text.

## Acceptance criteria

- Warm short-sentence synthesis targets 0.7–1.2 seconds and initially accepts P95 up to 1.8 seconds on the development Mac.
- The first sentence plays while later sentences continue generating.
- Consecutive replies within 180 seconds reuse one worker.
- A fully idle worker exits after 180 seconds and releases its 3–4 GB working set.
- Speech rates 0.75x, 1.0x, 1.25x, 1.5x, and 1.75x play correctly.
- All three interruption policies retain their semantics.
- Missing, corrupt, crashed, timed-out, and cancelled TTS paths do not affect OpenClaw text, ASR, screenshots, copying, or pasting.
- The installed app passes a real OpenClaw conversation, interruption, consecutive reply, and 180-second release test.

## Test strategy

- Swift checks for settings migration, request construction, sentence splitting, process lifecycle, and the 180-second lease.
- Worker checks for offline warmup, two consecutive syntheses, cancellation, structured errors, and no protocol noise.
- Integration checks for JSONL wiring, sidecar reuse, EOF cleanup, and degraded behavior.
- Voice-pack checks for staging, hashes, missing/corrupt states, and deletion.
- Installed-app verification using real OpenClaw replies and Activity Monitor/process diagnostics.

## Parallel ownership

This branch owns the Melo voice pack, Melo worker, Melo Swift backend, Qwen TTS removal, and Melo-specific tests. The other TTS session must keep its backend in separate files. The final shared engine selector, release version changes, build installation, and release-log merge are performed once, by one integration owner, after both branches are ready.
