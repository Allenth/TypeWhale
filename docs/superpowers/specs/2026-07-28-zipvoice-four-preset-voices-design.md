# ZipVoice Four Preset Voices Design

## Goal

Give the TypeWhale Pro reading lab four local ZipVoice preset voices:

1. the existing bundled news female reference;
2. a reference generated locally by Qwen3-TTS 0.6B Serena;
3. a reference generated locally by the current CosyVoice implementation;
4. a reference extracted from the user-supplied video.

All four remain experimental candidates. This work does not select a final TTS engine.

## Product Scope

### In scope

- Generate and normalize three new local reference packs.
- Keep the existing ZipVoice reference as the compatibility default.
- Qualify all four voices with Chinese, English, mixed, and long Chinese samples.
- Show only qualified voices in the existing reading-lab voice selector.
- Persist one selected ZipVoice voice ID and record the actual voice ID used.
- Install and verify the production app.

### Out of scope

- General-purpose voice recording, importing, or cloning UI.
- Reader Demo and OpenClaw TTS behavior.
- Identifying or naming the person in the supplied video.
- Cloud upload, network inference, model elimination, or final commercial licensing claims.
- ASR, VAD, rewrite, paste, and auto-send behavior.

## Voice Identities

| Stable ID | Display name | Source |
|---|---|---|
| `zipvoice-default` | 默认新闻女声 | Existing `news-female.wav` and exact transcript |
| `zipvoice-serena` | Serena 克隆 | Qwen3-TTS 0.6B Serena output |
| `zipvoice-cosy` | CosyVoice 克隆 | Current CosyVoice output |
| `zipvoice-video-reference` | 视频参考音色 | User-supplied MP4 audio |

The video voice uses a neutral product label. TypeWhale must not infer or expose a real-person identity.

## Reference Pack Format

Each voice is an isolated directory beneath the managed ZipVoice model:

```text
references/<voice-id>/
├── reference.wav
├── reference.txt
└── reference.json
```

`reference.wav` is mono 24 kHz signed 16-bit PCM. `reference.txt` contains the exact spoken transcript. `reference.json` stores the stable ID, source category, SHA-256 hashes, duration, sample rate, channel count, and experimental status. It never stores a source-person identity.

Generated reference packs are machine-local evaluation assets. They are not committed to Git.

## Runtime Architecture

The Swift voice catalog exposes four ZipVoice candidates. The shared worker request carries the stable `voiceID`. The ZipVoice adapter resolves that ID against a fixed manifest inside the selected model directory, validates containment and hashes, then loads the corresponding WAV and transcript.

Unknown IDs, missing files, path traversal, transcript mismatch, or invalid WAV properties fail closed. The existing default remains available if and only if its own reference pack is valid; the worker never silently substitutes a different requested voice.

## Reference Creation

- Serena and CosyVoice generate the same carefully punctuated reference text so their cloning behavior is comparable.
- The user video is converted from AAC 44.1 kHz mono to 24 kHz mono PCM16.
- Leading/trailing silence is trimmed conservatively. Loudness is normalized without clipping.
- The video transcript begins from local Fun-ASR output and is corrected against the audible source before qualification.
- Source video and generated intermediates remain outside the repository.

## Qualification

Every voice must pass:

- worker response returns the requested `voiceID`;
- Chinese short, English short, mixed, and long Chinese synthesis succeeds;
- WAV is non-empty, finite, non-silent, and not materially clipped;
- output duration is plausible;
- output PCM is not identical across different voice IDs;
- five repeated mixed-text runs do not fail or drift into invalid audio.

Qualification evidence is fingerprinted separately from Qwen and Kokoro voice evidence. Failed voices remain in evidence but are not exposed in the UI.

## UI Behavior

- ZipVoice changes from “固定音色” to a four-item preset voice menu after qualification.
- The existing per-model persistence restores the last ZipVoice choice.
- Model and voice menus lock during generation.
- Status and performance labels remain unchanged.
- Experimental origin is shown in concise menu details without exposing file paths.

## Privacy and Rights Boundary

- Processing is fully local and offline.
- No reference audio or transcript is uploaded.
- The video voice is not named after or presented as a real person.
- These derived voices are evaluation assets. Shipping them commercially requires a separate source and voice-rights review.

## Failure Handling

- Reference generation is atomic: incomplete packs never replace a valid pack.
- One failed voice does not disable the other qualified ZipVoice voices.
- A requested voice mismatch is a controlled playback failure, not a fallback.
- Existing default behavior remains recoverable throughout migration.

## Acceptance Criteria

- Four distinct ZipVoice voice IDs exist and pass the complete qualification suite.
- All four appear under ZipVoice in the installed app.
- Selection persists across model switching and app restart.
- Real installed-app playback succeeds with at least one generated voice and the video reference voice.
- Result JSONL records the actual voice ID and still excludes the input text.
- Reader Demo, OpenClaw, and other models retain their current behavior.
