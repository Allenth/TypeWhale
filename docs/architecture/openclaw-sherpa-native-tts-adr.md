> 文档迁移（2026-09-05）：[现行文档](../current/ARCHITECTURE.md)。下方为历史条件性决策，不再作为现行 TTS 选型。

# OpenClaw Sherpa Native TTS Backend Decision

Status: Conditional
Date: 2026-07-11
Scope: OpenClaw local TTS synthesis backend only
Decision owner: TypeWhale product and engineering
Adjacent owners: release and license review, QA

## Problem And Why Now

The current OpenClaw TTS experience is usable through a Python Sherpa sidecar, but a distributed desktop app should not require Python or pip. A native Sherpa CLI path now runs from the isolated TypeWhale app bundle. Its observed cold synthesis time is materially slower than the existing low-memory Python Sherpa baseline, so it cannot silently become the user-facing default.

## Architecture Significance

This changes the local runtime, deployment artifact, cancellation behavior, dependency and licensing surface behind a shared playback boundary. It does not change the authoritative OpenClaw text reply path.

## Protected Invariants

- OpenClaw text replies remain authoritative and visible even when TTS fails.
- ASR, realtime preview, paste, screenshot, capsule, hotkeys, copying, links, and OpenClaw message UI do not depend on TTS success.
- The current Python Sherpa sidecar remains the default and rollback path.
- The native runtime is only bundled in the isolated `TypeWhale Pro TTS Native` validation app until distribution review passes.

## Evidence Ledger

- Confirmed: official `sherpa-onnx v1.13.2` macOS arm64 shared runtime passed SHA-256 verification and can generate a 44.1 kHz WAV from the packaged app resource directory.
- Confirmed: official CLI requires `--key=value` arguments and uses a `bin/sherpa-onnx-offline-tts` plus `lib/` layout; TypeWhale now supports both this layout and the earlier flat layout.
- Confirmed: the packaged native CLI synthesized a mixed Chinese/English sample in `3.153s` for `4.9s` of audio.
- Confirmed: the historical local Python Sherpa probe recorded roughly `0.662s` for a shorter Chinese sample. This is not a controlled apples-to-apples benchmark.
- Inference: repeated CLI process startup and model loading are likely a material part of the native first-audible delay.
- Unknown: interactive first-audible latency, interruption feel, memory and CPU for real OpenClaw replies; mixed Chinese/English pronunciation quality in the installed app.
- Constraint: native TTS must not worsen the established rapid-response experience or introduce a Python dependency into the shipped path.

## Candidates

### Keep Python Sherpa Sidecar

Benefits: current default, proven TypeWhale lexicon behavior, lower observed local latency.

Liabilities: Python runtime remains a packaging and product-completeness concern.

### Native Sherpa CLI

Benefits: no Python process, bounded child-process crash domain, isolated packaging and rollback.

Liabilities: one process and model initialization per synthesis request; current measured cold synthesis is product-visible.

### Native Sherpa C API Bridge

Benefits: can retain a loaded model or native helper across requests, removing CLI startup from the critical path.

Liabilities: dylib signing, memory ownership, lifecycle, crash containment, version drift, and a larger implementation surface.

## Conditional Decision

Keep the Python sidecar as the default. Keep the native CLI in the isolated validation app only. Authorize a C API bridge experiment only when all predicates are true:

1. Interactive QA confirms the native CLI pronunciation and interruption behavior are acceptable.
2. A controlled benchmark shows first-audible latency is materially worse than the Python baseline and attributes the difference to CLI process/model startup rather than network or OpenClaw response time.
3. The C API can be built, signed, and cancelled inside the isolated app without expanding the failure blast radius beyond voice output.

## Execution Contract

- Allowed: isolated runtime packaging, latency instrumentation, native helper or C API spike behind `OpenClawTTSBackend`, and regression tests.
- Forbidden: replacing the production default, exposing an unfinished native setting in the main UI, removing the Python rollback, or bundling the native runtime into public DMG output.
- Rollback: store `openClawVoiceEngine = sherpa_melo_44k`, omit `TYPEWHALE_SHERPA_NATIVE_TTS_RUNTIME`, and retain the existing sidecar.
- Retirement: remove the CLI route and isolated runtime profile if its QA or licensing gate fails; remove the Python route only after a separately accepted product and release decision.

## Review Triggers

- Native first-audible latency is within a product-visible margin of the Python baseline.
- Interactive QA finds pronunciation, interruption, memory, CPU, or failure-degradation regression.
- Runtime licensing, dependency attribution, or signing verification fails.
- A C API bridge demonstrates lower first-audible latency while preserving cancellation and voice-only failure isolation.
