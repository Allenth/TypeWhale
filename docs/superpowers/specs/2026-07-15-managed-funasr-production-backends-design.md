# Managed FunASR Production Backends

Date: 2026-07-15
Status: Accepted
Decision owner: TypeWhale product owner

## Goal

Keep SenseVoice as the default, stable speech-recognition backend and add Fun-ASR Nano and Paraformer Contextual as fully usable final-recognition choices. TypeWhale must manage the runtime, model validation, prewarming, health, failures, and fallback. Users must not install or configure Python manually.

## Product scope

The user-facing backend list contains exactly:

- SenseVoice — default and authoritative fallback.
- Fun-ASR Nano — local mixed-language and hotword-capable final recognition.
- Paraformer Contextual — local Chinese contextual-hotword final recognition.

Paraformer zh remains an internal comparison provider. FSMN-VAD and CT-Punc are dependencies and are not selectable recognition engines. This change does not alter the smart-rewrite model, recording semantics, Silero VAD, paste flow, or SenseVoice realtime preview.

## Architecture decision

Use a managed, persistent local sidecar behind the existing final-ASR contract.

- The main app owns provider selection, lifecycle requests, timeouts, cancellation, fallback, and user-visible state.
- A versioned runtime manager owns an isolated Python environment under TypeWhale's Application Support directory. It pins the Python/runtime contract and verifies required modules before declaring a provider available.
- A long-lived sidecar process loads one selected FunASR provider, accepts newline-delimited JSON requests over stdin/stdout, prewarms the model, transcribes WAV files, and returns structured results and timings.
- The sidecar never enters the app process. A crash, import error, model error, timeout, malformed response, or empty output is contained and causes one automatic SenseVoice fallback for the same recording.
- SenseVoice remains the default when no explicit preference exists. Missing runtime or invalid model state cannot silently change the selected backend.

The decision is architecture-significant because it adds a runtime/deployment unit, changes provider lifecycle ownership, and affects the final paste reliability boundary.

## Runtime and model integrity

The runtime uses a versioned manifest with required Python modules and provider-specific required files. Installation occurs on demand through the existing model-management surface, reports progress, and is staged before atomic activation. Partial downloads and incomplete environments are never considered available.

Runtime readiness requires all of the following:

1. The managed interpreter exists and starts.
2. Pinned `funasr`, `torch`, `torchaudio`, and `modelscope` imports succeed.
3. The selected provider's required model files exist.
4. A sidecar health request succeeds.
5. Provider warmup succeeds.

Model files stay in the existing user-level `Models/funasr` directories. Runtime and models are not added to the app bundle or Git repository.

## Control flow

1. Recording and Silero VAD complete through the existing path.
2. The final-ASR adapter reads the captured backend selection.
3. SenseVoice requests continue through the native sherpa-onnx bridge.
4. Fun-ASR requests go to the prewarmed sidecar with audio path, provider ID, language mode, and the current developer hotword list.
5. A valid non-empty response enters the existing canonicalization, smart rewrite, recent-history, and paste pipeline.
6. A sidecar failure is logged against the recording task, the sidecar is marked unhealthy, and the same audio is transcribed once by SenseVoice.
7. The fallback result is the only result allowed to continue; stale sidecar completions are discarded by task identity.

## Lifecycle and memory

Only the explicitly selected FunASR provider is prewarmed. Switching providers stops the old sidecar before warming the new provider so large Python model processes do not accumulate. SenseVoice remains warm according to the existing memory-governance rules because it is the safety path. No idle timer unloads ASR models. High-memory recovery must not terminate a provider while recording, recognizing, rewriting, or pasting.

## UI behavior

- SenseVoice is selected by default.
- Installed and healthy providers are selectable.
- A downloaded model without a ready runtime shows `需要安装运行环境`; it is not reported as ready.
- Selecting an unavailable provider opens the managed installation action instead of persisting a broken choice.
- The status area distinguishes model missing, runtime missing, warming, ready, unhealthy, and fallback-active states.
- Realtime preview remains SenseVoice-only. FunASR selections affect final recognition and say so in the UI.

## Failure, recovery, and observability

Each sidecar request has a request ID and recording task ID. Logs include provider, model directory, warmup duration, inference duration, timeout, exit status, fallback reason, and final engine. Logs never include raw audio or secrets.

The app performs at most one automatic fallback per recording. Cancellation terminates the pending request and suppresses late output. A crashed or protocol-invalid sidecar is restarted only for the next request or explicit health recovery; the current recording falls back immediately rather than waiting through repeated retries.

## Verification gates

Production wiring is allowed only after an isolated spike proves both providers can load and transcribe a real local WAV through the managed interpreter. The production exit gate requires:

- Contract tests for protocol parsing, request identity, timeout, cancellation, and malformed output.
- Provider availability tests for missing runtime, partial runtime, missing model, and valid model.
- Integration tests proving each provider result reaches the existing final-ASR adapter.
- Forced crash, timeout, empty result, and missing-model tests proving one SenseVoice fallback and no lost paste.
- A shared local evaluation set comparing SenseVoice, Fun-ASR Nano, and Paraformer Contextual for text, hotword recall, Chinese skeleton regression, latency, and runtime errors.
- A clean local build, overwrite installation to `/Applications/TypeWhale Pro.app`, signature verification, launch, backend switching, real dictation, restart persistence, and fallback verification.

## Rollback and retirement

Rollback is a configuration-safe return to SenseVoice: if runtime health or provider verification fails, the app preserves the user's explicit selection for diagnosis but routes the current recording through SenseVoice and clearly reports fallback. Removing the feature deletes the sidecar adapter, runtime manager, provider menu cases, runtime manifest, and managed runtime directory without altering user recordings or SenseVoice resources.

## Protected invariants

- SenseVoice is the default and remains usable throughout installation and failures.
- Recording, Silero VAD, realtime preview, smart rewrite, translation, recent history, and paste semantics do not regress.
- No unverified provider controls final paste.
- Audio stays local.
- The app never depends on a user-managed Python installation.
- Model resources are not unloaded after ordinary idle time.
