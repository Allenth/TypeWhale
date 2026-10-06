# OpenClaw TTS Continuity Design

Status: Approved for Python-baseline text preparation; C API requires an isolated experiment
Date: 2026-07-12
Scope: OpenClaw reply speech output only
Decision owner: TypeWhale product and engineering

## Problem And Why Now

The current Python Sherpa sidecar keeps its model hot, but its shared input preparation turns Markdown headings into very short speech units and does not express parentheses as natural spoken pauses. The isolated native CLI candidate compounds this with one process and model initialization per unit. A real 477-character reply became 15 units; several next units required longer to synthesize than the prior unit took to play, producing audible gaps. The user also observed unnatural reading of Markdown, technical punctuation, and parenthetical content.

The product objective is continuous, natural local reading. The objective is not merely a Python-free implementation.

## Protected Invariants

- `sherpa_melo_44k` Python sidecar remains the only user-available OpenClaw voice engine until a replacement passes installed-app quality QA.
- OpenClaw text replies, ASR, realtime preview, capsule, message window, hotkeys, paste, copying, links, and screenshots remain independent from TTS success.
- TTS failures stop only voice output; they do not block or alter text replies.
- No user-facing TTS lexicon editor is introduced. The TypeWhale lexicon remains repository-maintained.
- The native CLI is retained only as a recorded experiment and must not be enabled by default or placed in the settings UI.

## Evidence Ledger

### Confirmed Facts

- `OpenClawVoiceRuntime.speechSegments` splits on every newline and uses a 90-character hard limit.
- The player prefetches only one next unit while the current unit plays.
- The native CLI creates a new process for every synthesis request.
- The Python Sherpa sidecar loads `OfflineTts` once and remains warm across requests.
- A real mixed Chinese/English reply produced 15 speech units. With the 4-thread CLI, a 0.61-0.82 second heading unit was followed by a 1.4-1.8 second next-unit synthesis; prefetch cannot hide that difference.
- The same CLI logs ignored Markdown and technical punctuation characters such as `**`, `:`, `/`, and `→`.
- The packaged native CLI can run 4 threads but still requires a process and model initialization per unit.

### External Facts

- sherpa-onnx exposes a C API and documents shared/static build artifacts including the C header and C API library. It supports TTS on macOS. [Official C API documentation](https://k2-fsa.github.io/sherpa/onnx/c-api/index.html)

### Inferences

- A native helper process backed by the C API can retain an `OfflineTts` model between JSONL synthesis requests, removing per-unit CLI startup from the playback critical path.
- C API alone cannot improve a model's pronunciation of malformed Markdown or unnormalized punctuation. Shared input preparation must be fixed first.

### Constraints

- Local processing only; no cloud TTS fallback.
- No Python dependency in the eventual native path.
- Native runtime remains isolated until signing, third-party notices, quality, interruption, and release gates pass.

## Decision

### Accepted: Repair Shared Speech Preparation First

Create a deterministic speech-preparation layer inside `OpenClawVoiceRuntime`. It receives the final OpenClaw Markdown reply and produces speech-safe text before either backend sees it.

Rules:

1. Preserve link labels and remove URL/Markdown decoration.
2. Merge headings with their following prose; a heading must never become a standalone 7-character speech request.
3. Convert paired Chinese and ASCII parentheses into comma-delimited parenthetical clauses, preserving the inner words and producing a natural pause before and after the clause.
4. Normalize table separators, bullets, arrows, colon-delimited labels, and repeated presentation punctuation into speech punctuation; retain technical terms themselves for the TypeWhale lexicon.
5. Segment only at natural sentence boundaries. Do not use newline as an unconditional boundary and do not split inside an ASCII technical token or parenthetical clause.
6. Prefer units large enough that the warmed Python sidecar can finish the next synthesis before current playback ends. The exact size is a tested implementation detail, not a product constant.

### Experiment Required: Native C API Helper

Do not directly bind the entire sherpa C ABI from `OpenClawVoicePlayer`. Instead create a small native helper executable that owns one loaded `OfflineTts` model and communicates with the existing Swift player over the current JSONL-style request/response boundary.

Why this route:

- It preserves the established queue, prewarm, stop, notification, and voice-only failure boundary in Swift.
- The helper can be restarted after a crash without taking down the App.
- It removes the CLI's per-unit process/model startup without coupling Swift to raw C allocation, audio-buffer, and thread ownership.

The helper may become a candidate only when the isolated experiment proves all of the following:

- The model is created once per helper lifetime and reused for at least two synthesis requests.
- Stop terminates the helper or current job promptly and the next request can recover cleanly.
- On the same normalized reply, first-audible latency is no worse than the Python baseline and no sentence boundary waits for a cold model load.
- The App signs and discovers the helper and required libraries correctly.
- A helper failure leaves the OpenClaw text reply fully usable.

## Candidate Comparison

| Candidate | Continuity | Pronunciation / Markdown | Dependency | Decision |
| --- | --- | --- | --- | --- |
| Keep current Python sidecar without text repair | Warm model, but short Markdown units still harm pacing | Parentheses and presentation symbols remain wrong | Python | Rejected as sufficient |
| Fix shared preparation, keep Python baseline | Warm model and correct units | Directly addresses current user feedback | Python | Accepted now |
| Native CLI per unit | Repeated model startup creates gaps | Shares current text defects | No Python | Rejected for product use |
| Native C API helper with shared preparation | One warm native model, continuous requests | Uses the corrected text layer and lexicon | No Python in final route | Experiment required |

## Execution Contract

### Stage 1: Shared Preparation And Segment Tests

- Allowed changes: `OpenClawVoiceRuntime`, focused Swift tests, planning and release notes.
- Required evidence: failing tests first for parenthetical clauses, headings, Markdown, technical tokens, and safe segment boundaries; then installed isolated-app listening QA on the Python baseline.
- Rollback: retain the prior pure Markdown-stripping behavior behind a single revert; no persistence or model migration exists.

### Stage 2: C API Build Spike

- Allowed changes: a temporary isolated C/C++ helper build, header/library discovery test, direct helper smoke test, and third-party inventory update.
- Forbidden: routing any user-visible App setting to C API or changing the production default.
- Required evidence: a helper can create one model, synthesize two normalized requests without a second model creation, emit valid 44.1 kHz WAV output, and exit cleanly.
- Cleanup: remove the spike artifacts and runtime copy if any required C API, signing, license, or latency gate fails.

### Stage 3: Native Helper Integration

- Allowed changes: a new `OpenClawTTSBackend` implementation using the native JSONL helper, isolated runtime packaging/signing, cancellation tests, and isolated build validation.
- Required evidence: message display continues during helper failure; Stop works; continuous multi-sentence playback does not have cold-start pauses; memory and CPU are recorded.
- Rollback: leave the stored engine at `sherpa_melo_44k`, omit native helper packaging, and retain the Python sidecar.

## Remaining Work

1. Shared preparation and segment repair on the stable Python path.
2. Installed-app listening QA for parentheses, headings, Markdown links/tables, `GitHub`/`MiniMax`/`OpenAI`, numbers, and mixed Chinese/English text.
3. Isolated C API helper spike, including static/shared packaging choice, code-signing, dependency attribution, and two-request warm-model proof.
4. Native helper integration, cancellation and failure-degradation regression tests.
5. Product-quality listening, first-audible latency, CPU, memory, and Stop QA before any exposure decision.
6. Explicit retirement of the CLI candidate or its replacement in the architecture record.
7. The separately requested in-page full-exit button remains pending location and exit-semantics confirmation; it is intentionally out of scope for this TTS work.

## Review Triggers

- The repaired Python baseline still sounds unnatural with the representative parenthetical and Markdown cases.
- C API cannot keep a model warm, cannot be signed, or cannot cancel safely.
- C API does not beat or match the Python baseline on normalized text.
- User listening QA identifies poor pronunciation that originates in the model rather than the text layer.
