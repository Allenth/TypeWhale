> 文档迁移（2026-09-05）：[现行文档](current/ARCHITECTURE.md)。下方保留迁移前架构全文与技术细节；旧“唯一当前架构”措辞由新入口接替，使用细节前需核对实现。

# TypeWhale Architecture

Last updated: 2026-08-24

This document is the single current architecture source for TypeWhale. Older architecture notes and ADR files are historical context only. If code or product behavior changes an architecture boundary, update this file and record the concrete work in `docs/开发日志.md`.

## Product Main Path

TypeWhale is a resident macOS input productivity app. The main path is:

```text
global hotkey
-> record complete microphone audio
-> show realtime capsule preview as confidence feedback
-> if SenseVoice is selected, use its complete stop-time realtime cache by default
-> if another model is selected, run that exact model on the complete recording
-> optional smart rewrite or translation
-> paste the chosen final text into the original target app
```

The selected ASR backend owns final recognition. SenseVoice remains the realtime preview provider and, when it is also selected for final recognition, may reuse its complete stop-time cache while “停止后重新识别整段录音” is off. Selecting Fun-ASR Nano or any other non-SenseVoice backend always runs that exact backend on the complete recording, regardless of the switch. Its short, empty, or failed result is preserved as that backend's real outcome; neither SenseVoice nor the realtime cache may replace it. A provider failure shows “识别失败”, delivers no text, and does not enter paste. Final paste, recent history, and backlog records use only the authoritative result plus approved smart processing.

Current production boundary: “重叠矫正” is a default-off product setting under “录音与预览”. It reuses the existing cross-boundary correction pipeline and takes effect from the next recording when capsule realtime preview is enabled. The former “长录音增量输出（实验）” control remains unavailable, and the product has a five-minute recording cap; the lower-level long-form types do not mean current builds support multi-hour recording.

The complete transcript and the visible capsule projection are separate contracts. `CompleteTranscriptSnapshot` carries the full stable text, volatile tail, lifecycle, revision and source identity without a character limit. `PreviewDisplaySnapshot` / `PreviewViewState` are presentation projections and may keep only a recent suffix such as 160 characters. Both are produced from the same recognition state, but only the complete snapshot may enter `RealtimePreviewDeliveryCache` / `ProductionRealtimePreviewDeliveryCache` and final delivery. UI visibility, animation progress and window state have no final-delivery authority.

The current chunk policy uses a short-word experiment for the first chunk: after real voice has been observed, the first chunk may close at a VAD pause from 3 seconds onward; continuous speech still reaches the 18-second hard boundary. Once that first chunk closes for either reason, the next chunk resets its own timer and all later chunks return to the 10-second VAD soft boundary plus the same 18-second hard boundary. Initial silence cannot consume the first short-word chunk. The correction path recognizes an approximately 22.5-second cross-boundary window after about 9.5 seconds of right context. The fast lane owns live display through provisional text keyed by chunk ID; entering a new chunk retains earlier unconfirmed chunks. The correction lane validates overlap but may confirm only through the previous real `PreviewBoundary`, after which the corresponding provisional fast chunks are discarded. Confirmed prefix segments are immutable; only the mutable tail may be replaced. A stop-tail request is finalization-only and must never create a next-chunk anchor from its `Int.max` sentinel ID. During recording, the single-engine scheduler uses monotonic enqueue time. Selection order is stop-tail, backlog-pressure correction when two corrections are pending with a 1:1 fast quota, one forced correction after four consecutive fast completions, fast waiting at least 700ms, fast immediately after a correction, then ordinary fast/correction work. These fairness rules outrank the fast deadline so sustained overdue fast traffic cannot starve correction. Real correction boundaries remain FIFO and are not silently dropped. Each lane logs queue, recognition, audio, and end-to-end duration through asynchronous serialized diagnostics so measurement does not perform synchronous file I/O on the main actor. Long-form confirmed segments are written idempotently on a utility queue, while the in-memory reducer state remains authoritative for final assembly. Long-form disk-capacity probes are also utility-queue work, rate-limited to 30 seconds and guarded against overlapping requests; audio-meter callbacks must never synchronously perform filesystem-capacity queries on the main actor. A long-form session must finish tail reconciliation and persistence before another recording can claim the singleton preview pipeline.

Realtime recognition text is screened before reducer/reconciler mutation by `RealtimeRecognitionHallucinationFilter`. Both the overlap-correction pipeline and the local SenseVoice snapshot provider suppress whole-result known silence phrases such as `我`、`我想`、`Yeah` and `I`, while longer real utterances such as `我想修改这个功能` and `Yeah，我们继续` pass unchanged. Unknown short results are not delayed or dropped solely because of length: a real two-character tail must remain deliverable on its first result. Suppression leaves the prior transcript state untouched, so a known bad fragment cannot reach capsule projection or the realtime delivery cache. Presentation code remains responsible only for projection, stable/volatile composition and animation. Unknown silence hallucinations require later VAD/audio-evidence work rather than a generic short-text quarantine.

OpenClaw voice mode is an explicit side path, not a replacement for the main paste path:

```text
user-configured OpenClaw activation key
-> record complete microphone audio with the same ASR pipeline
-> show red OpenClaw capsule with lobster badge
-> choose final text with the same preview-cache-first policy
-> send the chosen final text to the local OpenClaw CLI/Gateway
-> display/log a non-pasting OpenClaw message stream
```

The OpenClaw path must stay isolated from normal dictation. It has no default activation key, does not auto-fall back to F6 after unknown key storage, and must not enqueue paste, toggle translation, or reuse the frontmost-app insertion workflow.
The screen notification is an OpenClaw message stream, not a paste preview and not a raw JSON inspector. It may show the user utterance, local send/waiting states, safe OpenClaw status/progress/tool-summary events, completion/failure states, and final assistant replies as separate stacked messages. Raw JSON, IDs, usage blobs, traces, and internal metadata must not be shown directly. Long replies may scroll inside the notification card, but the notification window must remain non-activating and must not steal text focus from the foreground app.
The OpenClaw CLI child process owns a runtime-specific PATH boundary. Before every CLI launch, a Node directory may precede the parent app's inherited PATH only after its executable has been found and its semantic version has been verified against OpenClaw's supported ranges; results are not cached across launches, so a runtime upgrade can recover without restarting TypeWhale. Each version probe has a short hard timeout, drains output concurrently, and terminates a hung candidate before continuing. Missing and incompatible candidates are skipped. All inherited PATH entries keep their relative order after that single Node override, and generic Homebrew locations remain fallback entries. This ordering applies only to the OpenClaw CLI environment: shared ZipVoice/TTS environments retain inherited-first ordering, and neither the app nor the login-shell environment is mutated.

Local TTS is an output-side experimental path, not a replacement for ASR, smart rewrite, paste, or OpenClaw text display:

```text
user-enabled TTS capability
-> check local TTS sidecar health
-> send text and voice options through a local adapter
-> receive an audio file or local stream
-> play audio or surface a diagnosable failure
```

The local natural-voice backend is ZipVoice Distill INT8 with four qualified reference voices. The sounds lab and OpenClaw share the same model, worker protocol, stable voice IDs, and the `zipvoice-distill-int8-reference-voices-v2` qualification fingerprint. Model weights and reference packs live under user Application Support and are not bundled in the default DMG. TypeWhale never downloads runtime assets while speaking. TTS availability is never a startup or main-dictation dependency. New single-speaker cloned reference packs must use transcript-aligned mono PCM16 audio at 24 kHz and remain between 1 and 3 seconds; longer prompts are rejected because they increase latency and can introduce sentence-onset artifacts. Reference packaging must preserve enough natural trailing silence to avoid leaking a clipped final phoneme into generated speech. Long-form synthesis remains a single generation request because sentence-by-sentence concatenation resets breath, rate, and emotion. Before inference, the shared ZipVoice worker turns display-oriented text into speakable text: Markdown horizontal rules and decoration, emoji, ornamental quotes, and empty lines are removed; em-dash runs become comma pauses; non-empty lines are joined while preserving inline spaces and authored punctuation. The normalizer must never drop ordinary Chinese, English, numbers, or sentence punctuation. Every ZipVoice result then passes through the shared dependency-free output conditioner before PCM encoding: a 45 Hz high-pass, 11.5 kHz low-pass, and whole-buffer peak scaling only when the filtered peak exceeds 0.95. The conditioner must preserve the exact sample count and never trim generated speech. The legacy `zipvoice-video-reference` pack is a temporary explicit compatibility exception because shortening it caused unacceptable speaker-similarity regression; replacing that exception requires human similarity listening, clean onset, and complete first-phoneme acceptance together.

## Layers

TypeWhale uses lightweight Clean Architecture with AppKit-friendly coordinators. Do not introduce a broad framework rewrite.

```text
Presentation
- AppKit views, panels, popovers, dialogs, drawing, visual state.
- User-event forwarding.
- Local visual animation and display buffers; capsule visible-text suffix measurement is cached by text and viewport width to keep drawing cost bounded across long recordings.

Application
- Coordinators, use cases, workflow state, command dispatch.
- Recording, screenshot, lifecycle, finalization, paste orchestration.
- Product workflow policies that span multiple infrastructure services.

Domain
- Stable product concepts and pure rules.
- ASR configuration, recording task identity, hotkey bindings, paste outcomes.
- Text normalization and pure gates such as final speech gating.

Infrastructure
- macOS and external capabilities: audio, ASR, VAD, OCR, AI provider APIs, hotkeys, pasteboard, permissions, keychain, model files, diagnostics, observability, build/distribution resources.
```

Boundary rule: views should not decide final paste safety, provider routing, cross-window lifecycle, or ASR/VAD product policy. Infrastructure should not know product workflow state beyond small ports/adapters.

## Current Source Map

- `native/Sources/Presentation`: main window, recording capsule, notch preview, screenshot overlay UI, shared AppKit components, version history.
- `native/Sources/Application`: `SpeechInputCoordinator`, `SpeechInputState`, `AppLifecycleCoordinator`.
- `native/Sources/Domain`: ASR, hotkey, paste, final speech gate, recognition text normalization/filtering.
- `native/Sources/Core`: smart input domain services, prompt building, usage ledger, developer lexicon, backlog.
- `native/Sources/Infrastructure`: audio recorder, ASR bridge/router, hotkey monitor, paste coordinator, model installer, permissions, settings, diagnostics, observability, AI provider clients, OpenClaw CLI/Gateway adapter, local TTS sidecar adapter.

Known concentration points:

- `SpeechInputCoordinator` still owns too many application concerns: hotkeys, recording, VAD, realtime preview, final ASR, smart rewrite/translation, paste, screenshot entry, memory safety.
- Screenshot Version B has completed its first architecture pass: toolbar command policy, pending-state rules, operation-token invalidation, and translation layout policy now have explicit state/command models and checks. `ScreenshotOverlayView` still owns AppKit rendering and side-effect execution, but this is the accepted boundary for the current pass.

These files should be split through explicit state models, use cases, commands, and adapter ports, not through an app-wide rewrite.

## Stable Invariants

### Voice Input

- When SenseVoice is selected and “停止后重新识别整段录音” is off, final inserted text comes from the stop-time complete realtime preview cache. This cache is application state (`committedPreviewText + latestPreviewText` or equivalent), not the visible capsule suffix/window.
- Selecting a non-SenseVoice backend always runs that backend on the completed WAV. Its result cannot be replaced by SenseVoice, realtime cache, shadow output, or the UI-visible tail; provider failure is terminal for that recording.
- Realtime preview is a confidence anchor: it should appear quickly, remain readable through natural pauses, and avoid obvious jumping or duplication.
- Existing good capsule behavior must be preserved or compared against historical good versions before changing animation or preview strategy.
- OpenClaw voice mode uses final ASR as the outbound message source, but it does not insert text into the foreground app. Its result is treated as an external conversation outcome, not a dictation paste.
- Recording task identity must be explicit. Do not couple finalization to `latest.wav`.
- Recording, recognition, smart processing, and paste must ignore stale callbacks from older tasks.
- Empty-recording protection is allowed, but VAD must not silently discard speech when realtime evidence exists.
- Pause auto-finish is a domain policy, not a view or realtime-preview side effect. Realtime preview and pause auto-finish remain independently configurable.
- Recording-time VAD probes carry the recording task ID. A callback from an older task must not update voice state, disable VAD, or finish the current recording.

### Preview Pipeline

Current active preview direction, as of 2026-06-29/2026-06-30, is the 1.5 chunk-commit preview path:

- Audio is divided into preview chunks.
- Only the current chunk is repeatedly recognized for realtime preview.
- When a chunk reaches the soft target and Silero reports a pause, or when it reaches the hard limit, the chunk text is frozen into `committedPreviewText`.
- Display text is `committedPreviewText + latestPreviewText`.
- Final chunk snapshots use a dedicated queue and should not be dropped.
- Final paste uses the stop-time complete realtime preview cache by default; complete-recording ASR is used only when the re-recognition switch is enabled.

This supersedes the older ADR-010 rule that `committedPreviewText` must be removed. The older rule was correct for the failed short-pause reset/sliding-window path, but it is no longer the current source of truth. The current line keeps the key guardrail: never reset already displayed text on ordinary short pauses.

Preview non-goals:

- Do not use the UI-visible preview suffix/window as final paste text. Only the complete stop-time preview cache may become final text.
- Do not add language-model correction to realtime preview by default.
- Do not make `RecordingCapsuleView` merge ASR text or infer language-specific strategy.

Historical long-form SenseVoice experiment, added on 2026-07-10 and later removed from the active product path:

- `10–18s` chunks remain resource boundaries, but experimental chunk completion no longer means immediate permanent string concatenation.
- `AudioRecorder` retains bounded context and emits a correction snapshot centered around each VAD/hard boundary after right-side context arrives.
- `ExperimentalRealtimePreviewPipeline` owns request admission. Stop-tail work outranks correction work, correction work outranks latest-only fast preview, and callbacks require session/epoch/request identity.
- `PreviewTranscriptReducer` is the experiment's text authority. It converts relative token timestamps to absolute audio time, aligns the overlap of windows with different start times, freezes confirmed segments, and only replaces mutable tail.
- `IncrementalTranscriptStore` appends confirmed segments under Application Support. Long-form stop drains queued corrections, appends the remaining tail, and sends the assembled text into the existing downstream workflow without whole-recording ASR.
- The long-form experiment uses a four-hour safety cap and ignores ordinary pause/no-text auto-finish. Manual stop, route failure, write failure, disk safety, and the full audio evidence remain authoritative safeguards.
- Capsule state stays bounded to recent confirmed context plus mutable tail; the app does not rebuild an hour of text every 0.5 seconds.
- These rules describe the retained historical implementation, not a selectable capability in the current build. Current sessions use the existing chunk-commit preview, preview-cache-first final text selection, optional complete-recording re-recognition, and a five-minute cap.

Current production-source realtime finalization boundary, updated on 2026-07-23:

- The production main capsule owns an independent `ProductionPreviewStateBridge -> ProductionPreviewTextCoordinator` subscription for every recording. It starts before the optional shadow runtime gate and remains alive if shadow preview is disabled, overflows, or fails. Shadow teardown must never cancel the production bridge, production text coordinator, or production delivery cache; only whole-session cancellation or normal finalization may end them.
- The main capsule keeps bounded typewriter motion as presentation-only behavior: at most eight trailing characters are animated at 50ms per character. This animation may delay paint by at most about 400ms but cannot reject, rewrite, clear, or feed text back into the delivery cache.
- `RealtimeChunkBoundaryPolicy` owns one `6/10/18` rule: the first chunk may soft-finalize after 6 seconds when speech has been observed and VAD reports a pause; later chunks use 10 seconds; every chunk retains the 18-second hard limit. Initial silence never consumes the first-chunk rule.
- `SpeechSession` freezes the “re-recognize the complete recording after stop” setting when recording begins, and `RecordingTask` inherits it. Changing the UI switch during a recording affects only the next recording.
- When complete-recording SenseVoice Final ASR is disabled, stop ordering is: drain ordinary realtime work, run one bounded `stopTail` reconciliation, read the resulting production preview text, complete `ProductionRealtimePreviewDeliveryCache`, then clear the session. UI and capsule code do not reconcile text. A selected non-SenseVoice backend runs after this preview finalization and remains the sole final-text authority.
- `SpeechInputCoordinator` emits a full `CompleteTranscriptSnapshot` to the production cache and a separate `PreviewDisplaySnapshot` to presentation subscribers. Delivery caches do not accept `PreviewDisplaySnapshot`; Final-ASR-on fallback receives the complete cache text, never the visible capsule suffix.
- `PreviewTranscriptReducer` exposes a behavior-neutral ownership transition for each admitted result: input/replacement/confirmation/promotion ranges and removed fast chunk IDs. `RealtimeTranscriptTrace` persists these transitions off the UI queue as bounded JSONL with per-session salted hashes; production never writes transcript bodies. `ProductionRealtimePreviewDeliveryCache.complete()` emits the exact completed snapshot to the same trace, so diagnostics can distinguish Reducer loss from cache/delivery loss without influencing either path.
- `stopTail` has a three-second overall deadline. Failure or timeout marks recovery and delivers the current realtime cache; it must not return empty merely because tail reconciliation failed, and it must not silently invoke complete-recording Final ASR.
- When complete-recording SenseVoice Final ASR is enabled, `stopTail` is skipped and SenseVoice Final ASR remains the sole stop-time authority.
- Build 800 contains this implementation and passed full compilation, overwrite installation, launch, binary-marker and code-signing checks. Real 20-second, 2-minute and 5-minute recording acceptance remains required before declaring the behavior production-proven.

Online ASR shadow providers, added behind the same isolated shadow-preview boundary on 2026-07-12:

- Online provider selection is independently persisted as `off`, Doubao ASR, or MiMo‑V2.5-ASR; `off` is the missing/unknown default and a recording session freezes exactly one selection at start.
- Doubao and MiMo API keys live only in separate macOS Keychain services. UI reads only credential existence and never displays, logs, or persists the key value in UserDefaults or plist.
- Saving a key does not authorize transmission. Audio can leave the device only when the user selects that provider and starts the next recording; changing selection never hot-switches an active session.
- A missing key prevents online Provider creation and PCM subscription. The shadow runtime falls back to `LegacyPreviewShadowAdapter`, while the old capsule, complete-recording final ASR, VAD, rewrite, history, and paste remain unchanged.
- Doubao owns bounded continuous-PCM WebSocket transport. MiMo owns bounded complete-WAV snapshot requests with streamed SSE text response; these vendor mechanics do not cross the unified `TranscriptionEvent` boundary.
- A continuous online transport emits one vendor-neutral completion signal only after its final text message. `OnlineTranscriptionProvider` owns the unified `finalized -> completed` ordering, terminal idempotency, one disconnect, event-stream finish and cancel-wins behavior; transport-specific socket state never enters the Reducer or capsule layers.
- Online failure is fail-open and shadow-only. It cannot finish recording, mutate production preview strings, submit final text, or trigger paste.
- Build 702 proves protocol fixtures, Keychain/UI boundaries and installed no-key fail-open behavior. It does not prove real authentication, provider latency, pricing, rate limits, retention policy, or production readiness.

Capsule themes, shadow diagnostics, and MiMo request adaptation, updated on 2026-07-23:

- Production offers three mutually exclusive main-capsule themes: classic, notch, and minimal black. Minimal black is an independent `MinimalBlackPreviewPresenter` and `MinimalBlackPreviewView`, not a `RecordingPanel` color branch; exactly one selected product Presenter exists at a time.
- The former candidate visual direction is now the minimal-black main theme. Its black surface, subdued green border, stable/volatile text separation and bounded text motion were recovered under `MinimalBlack` names. The candidate coordinator, runtime, adjacent-window positioning and three-capsule layout remain deleted. No product state carries a “candidate” badge or a second concurrent product preview.
- Technical Shadow remains one optional diagnostics window. It can test the local SenseVoice provider, MiMo, or Doubao through `ShadowTranscriptionRuntime`, but cannot write production preview state, final text, history, or paste state.
- Main-capsule theme replacement rebinds the existing `ProductionPreviewTextCoordinator` sink while its production subscription stays authoritative. `MinimalBlackPreviewPresenter` receives only `PreviewDisplaySnapshot` plus existing presentation commands; it owns no `AsyncStream`, Provider, Reconciler, Final delivery or Paste decision.
- Flash Idea and OpenClaw continue to force the classic main-capsule style; the theme preference applies to ordinary production recording only.
- MiMo snapshot/SSE replay is normalized inside `MiMoSnapshotProvider` by `MiMoRequestPartialProjection`. Snapshot IDs and accepted request baselines never cross the Provider boundary.
- SenseVoice snapshot, local streaming and MiMo all continue through the same `TranscriptionEvent → TranscriptReducer → PreviewViewState` contract; the common Reducer and Projector contain no provider switch.
- MiMo request partials and completed snapshots reject strict text shortening relative to the accepted snapshot baseline/projected text. This vendor-specific rollback rule remains inside `Infrastructure/RealtimeTranscription/MiMo*` and never enters Candidate code.
- Starting with the Build 716 source route, online selection off or a missing key assembles the bounded `SenseVoiceSnapshotProvider` and feeds PCM through the existing capacity-8 fan-out. `LegacyPreviewShadowAdapter` remains only as fail-open safety when the active recording configuration is unexpectedly unavailable. The original capsule remains authoritative; this route activation requires installed 20-second/2-minute CPU, RSS, cancellation and consecutive-session acceptance before Stage 9A can close.
- Local snapshot accumulation requires adjacent correction audio ranges to overlap. Build 716 violated this invariant by scheduling corrections every 10 seconds while retaining only 8 seconds, so the core could never accumulate confirmed text and repeatedly exposed only the 3-second fast tail. Build 717 uses a 6-second correction cadence with the same bounded 8-second window, preserving approximately 2 seconds of reconciliation context; this policy remains entirely inside `SenseVoiceSnapshotProvider`.
- Build 719 sends every successful local fast/correction result through one Provider-local audio-time assembler. Overlap midpoint advances a monotonic confirmed frontier using validated timestamps or proportional token positions; word equality is never the commit gate. One `.reconciled` event appends newly confirmed segments and replaces the volatile tail in one Reducer state, so one recognition cannot cause finalized/partial double redraw or a seam diagnostic UI clear. MiMo explicitly retains its separately validated lexical snapshot strategy; online streaming providers retain partial/finalized events.
- With a ready online Provider, the runtime consumes Provider PCM/events instead of the legacy adapter, but MiMo remains bounded complete-WAV snapshot input with streamed response text. A capsule theme cannot upgrade that transport into continuous audio streaming.
- Build 804 is retained as evidence of a rejected implementation: its `.minimalBlack` route reused `RecordingPanel(visualStyle:)` and therefore produced only a black skin over the classic capsule. The corrected source deletes `MainCapsuleVisualStyle` and routes `.minimalBlack` to the independent Presenter. Build 805 is the first installed and visually reviewed build containing this correction.
- `realtimePreviewEnabled` is a capsule-text preference, not a capsule-visibility or data-pipeline switch. The selected `PreviewPresenting` implementation always shows recording state and waveform. `ProductionPreviewTextCoordinator.begin(states:deliversText:)` is the sole presentation gate: when disabled it projects production state but does not deliver text snapshots to the capsule. The recorder, main-window transcript, complete delivery cache and optional overlap correction continue independently.

### VAD, ASR, And Memory

- Silero VAD is the authoritative recording-time voice signal.
- Final ASR candidates are registered once in `ASRModelRegistry` and routed through the shared local adapter boundary. Realtime preview remains SenseVoice, but final authority follows the selected backend.
- The selectable set is limited to SenseVoice int8, Parakeet TDT 0.6B v2, Fun-ASR Nano and Qwen3-ASR 0.6B/1.7B MLX 8-bit. Paraformer Contextual, Paraformer zh, SeACo Paraformer, Whisper Small MLX, Qwen3 Sherpa and Zipformer are retired as unsuitable for the current TypeWhale product target.
- FunASR and MLX backends run in separate persistent JSONL sidecars using TypeWhale-managed, version-pinned Python runtimes under Application Support. Runtimes are checksum-verified, health-checked, installed atomically, offline during inference, and independent of the user's system Python.
- Qwen3-ASR MLX receives no hotword/context field until the installed `mlx_audio` API exposes and passes a verified native mechanism.
- Qwen3-ASR MLX splits PCM WAV recordings longer than 25 seconds into 25-second windows with one-second overlap and deterministic text-overlap reconciliation. Each segment uses the model-native Chinese language parameter; this protects the current five-minute recording cap from single-context truncation without claiming multi-hour transcription support.
- A candidate becomes selectable only after model files, managed runtime and checked-in real-WAV admission evidence pass. Warmup or transcription failure is terminal for that recording: the App shows “识别失败”, delivers no text, performs no paste, and never calls SenseVoice as fallback.
- Fun-ASR Nano remains warm during normal use, while high-memory release follows the same idle-only flush-and-immediate-reload invariant as native ASR.
- Energy bands and peak level are visual/readout signals, not final voice truth.
- Pause auto-finish decisions are evaluated only from completed task-scoped Silero probes. A qualifying `no_speech` result arms a candidate; a second consecutive qualifying result confirms it. Any speech result clears the candidate, and per-buffer timers must not finish while a probe may still be in flight.
- VAD probes waiting behind a slow inference run use a small FIFO, not latest-only replacement. A finish decision cannot commit while newer audio remains unprocessed. If the bounded FIFO fills, auto-finish is disabled for that recording rather than dropping possible speech evidence.
- Initial empty-recording protection requires a `no_speech` probe captured at least 8 seconds after recording began and no meaningful realtime preview evidence; it cancels the empty recording without submitting final ASR.
- Final VAD is a soft gate: if realtime preview or recording-time VAD shows speech evidence, final ASR must still run even when final VAD says `no_speech`.
- ASR/VAD resources stay warm during normal use.
- Do not reintroduce idle timer unloading.
- High-memory safety may flush and immediately warm-load the native ASR/VAD arena only when the app is idle and above the dynamic warning threshold.
- Current memory warning threshold source of truth is `MemoryMonitor.warnThresholdMB = min(20GB, max(2GB, totalPhysicalMemoryMB * 25%))`; the high threshold follows that value by about 20% and is capped at 24GB.
- Never release model resources while recording, recognizing, smart-processing, or pasting.

### Local TTS Sidecar

- TTS is output-side only. It must not change final ASR, realtime preview, smart rewrite, paste safety, or OpenClaw text-message delivery.
- The main app talks to TTS through a small adapter/port with health check, model metadata, synthesize request, timeout, cancellation, and structured failure reporting.
- TTS sidecar failure is a degraded-output state, not an app failure. Dictation, screenshot, OpenClaw text replies, model downloads, and paste must continue to work.
- OpenClaw and the sounds lab use the same `sherpa-zipvoice` worker, model directory, and four validated reference voice IDs. Unknown IDs, modified reference hashes, missing files, or path escapes fail closed instead of silently switching voices.
- `OpenClawVoicePlayer` owns queueing, prewarm, interrupt policy, speaking notifications, cancellation, and failure degradation. The worker process is cancellable and remains isolated from ASR and text delivery.
- Native TTS must not become the visible default until installed-app QA shows no product-visible regression in first-audible latency, mixed Chinese/English pronunciation, memory, CPU, interruption, and missing-runtime failure behavior.
- TTS models are managed under user-level Application Support if a model manager is enabled. Large TTS models are not bundled into the app or public DMG by default.
- Candidate TTS models must pass licensing review before any commercial default. Code license, weight license, redistribution, attribution, and use restrictions are separate checks.
- OpenClaw automatic TTS is user-controlled and additive to the existing text notification stack; a TTS failure must never suppress the text reply.
- Temporary TTS Native test builds may use a separate app name, executable, bundle id, and install path to avoid colliding with parallel worktree QA. That profile is test scaffolding only: before native TTS is declared stable or shipped, the build must return to the production identity (`TypeWhale Pro`, `TypeWhalePro`, `com.waykingah.typewhale.pro`, `/Applications/TypeWhale Pro.app`) or record an explicit permanent developer-profile decision.

### Screenshot, OCR, And Translation

- Screenshot mode observes the desktop; entering it must not show, hide, restore, or otherwise manage the TypeWhale main window.
- Screenshot overlay may become key enough to receive input without activating the main TypeWhale app window.
- Screenshot presentation must not depend on `MainViewController`, main-panel status tones, or app reopen suppression. Screenshot status is screenshot-owned and may use non-activating transient feedback only.
- Screenshot overlay windows must remain non-activating panels; they must not become the app's main window.
- Window-level capture may raise the explicitly selected target window and recapture in place.
- During screenshot OCR/translation pending state, actions that export or mutate unstable output must be disabled or guarded. Cancel remains allowed.
- Stale OCR/translation callbacks must be ignored after cancel or superseding operations.
- Screenshot annotations are create-only after placement: existing markups must not be hit-tested for selection, dragged, resized, deleted as selected objects, or decorated with a blue dashed selection outline. The only correction path for placed markups is undo/redo.
- Screenshot mosaic is an annotation tool whose product effect is Gaussian blur, not blocky pixelation. It follows the same create-only, undo/redo-only correction model as rectangles, arrows, pen, and text.
- Screenshot archive is an OCR + knowledge-writing workflow. It writes Markdown to the backlog archive date directory and must preserve the original screenshot under that date directory's `附件/` subfolder, referenced from the Markdown with a relative path.
- Screenshot translation is a separate OCR workflow. It must use the ScreenshotTranslation prompt/engine path, default to English OCR -> Chinese translation, and preserve OCR line ids for layout. Do not route it through the voice SmartTranslation prompt builder with a special `triggeredBy` branch.
- Screenshot translation layout and product acceptance details live in `docs/SCREENSHOT_TRANSLATION_SPEC.md`.

### Main Window Lifecycle

- Main-window visibility is governed only by explicit user actions, the configured main-window shortcut, status-item/menu commands, and approved first-install/default-open behavior.
- Login-item/background launch must not unexpectedly surface the main window.
- Screenshot and recording flows must not take ownership of main-window visibility. Screenshot close/copy/save/OCR/translation/cancel paths must not register reopen suppression or call `showMainWindow()`.
- Main-window layout follows the Classic Mac inspector direction: left side is the stable current-session workspace, right side is a tabbed control panel with vertical scrolling only. Do not reintroduce a horizontal settings panel scroller or navigation by horizontal scroll position.
- The Common tab is for operational settings such as screenshot save location, system/device toggles, and preview theme. Smart processing controls belong in the Intelligence tab: dictation rewrite mode, idea pill rewrite mode, screenshot archive rewrite mode, auto-translation, translation direction, model selection, prompt editing, rules, and lexicon.

### Smart Rewrite

- Prompt rendering is layered as compact global safety contract, editable mode template, isolated raw-text block, shared semantic-structure contract, and a short final mode action. Raw text never participates in placeholder substitution, so literal strings such as `{rawText}`, `{targetAppName}`, and `{developerGlossary}` inside dictated content remain user content. The final mode action is intentionally closest to generation because the local Qwen3 4B follows concise recent instructions more reliably than repeated synonymous guardrails.
- Local Qwen startup prefill, production rewrite requests, and semantic replay tools must all use `SmartRewriteSafetyPrompt.localRewriteLead` through the same shared system-prompt builder. A replay-only lead is invalid evidence because even a small lead change can switch the 4B model between meaningful cleanup and verbatim copying.
- `ModeContract` holds the final non-negotiable action for every smart mode, not copyable calibration answers. Developer requirement keeps first-person task/feedback voice and semantic cleanup; formal statement avoids synonym upgrading and nominalization; polish requires a meaningful local edit only when the source actually needs one; note distinguishes single content from explicit multiple points; chat preserves natural speech; exhaustive summary preserves first-person question/request status.
- Smart Rewrite must never answer questions or generate final advice from dictated content. If raw speech contains reply-writing, consultation, advice, reassurance, guidance, or script instructions, the output remains that instruction/request itself rather than a direct message to the final recipient.
- Smart Rewrite does not perform post-generation semantic fidelity scoring. Once the selected model returns non-empty text, that text is delivered directly and the user judges its accuracy; TypeWhale must not reject it because an English term, number, constraint word, question marker, or source-character overlap differs. Empty output, model errors, timeout, protocol errors, output sanitization and the no-provider-fallback policy remain technical validity boundaries.
- Default templates own tone and output structure, while shared and final contracts own invariant behavior. They must not duplicate the same prohibition in several phrasings: dense repetition makes the 4B model choose verbatim copying as the lowest-risk output.
- All editable smart rewrite templates, including `即时归纳` (`RewriteMode.note`), must remain available from the Intelligence tab prompt editor. Raw and command are bypass modes and do not have editable templates.
- Default templates must not contain `原始语音文本：{rawText}`. Raw text is appended only by `RawTextBlock.render(rawText)` after template rendering.
- `raw` and `command` do not use the Smart Rewrite prompt chain. `raw` is a bypass that returns the original text; future command-agent behavior should use a separate command prompt builder instead of inheriting Smart Rewrite's "do not execute commands" safety contract.
- Developer requirement mode is designed for text that may be pasted directly into Codex, Cursor, Claude Code, ChatGPT, terminals, IDEs, or other coding agents.
- Chat mode is the automatic-mode target for real messaging and day-to-day communication windows such as WeChat, iMessage, Telegram, WhatsApp, Slack, Feishu, DingTalk, and QQ. Do not make neutral `polish` social again to solve chat dryness; keep `polish` objective and route chat surfaces to `chat`.
- Chat mode should preserve short-message immediacy: lunch, scheduling, "reply later", and casual check-in dictation should stay short, natural, and human, not become formal polish, summaries, requirements documents, or bullet lists.
- AI coding targets such as Codex, Cursor, Claude Code, and ChatGPT must continue to route to developer requirement mode even when their bundle identifiers contain words like `chat`.
- Developer requirement mode defaults to lightweight task cleanup, not requirements-document generation. Structure is a tool for complex or explicitly requested cases, not the default output shape.
- Developer requirement mode must understand product/technical meaning before rewriting. It should correct context-supported Chinese ASR homophones and near-sound errors instead of mechanically copying wrong characters after removing fillers.
- Voice language translation belongs to the SmartInput/Smart Rewrite product surface: its prompts and settings stay with intelligent text processing. It handles recognized speech text and must not carry screenshot OCR layout rules.
- Developer requirement mode inherits the 1.4.20 semantic-preservation lesson: preserve explicit tasks, background reasons, constraints, ordering, risks, acceptance hints, subjective experience, and judgment intensity. Short content may stay short, but short content with cause, feeling, constraint, order, or risk must not be compressed into a single command.
- Developer requirement mode must also preserve examples used to explain a concern or forbidden rewrite, explicit `first/second/third/finally` ordering, both sides of a time contrast, and trailing scope limits such as “only organize, do not execute, do not expand this into a technical plan”. Explicit steps are separated and numbered; surrounding explanation remains natural prose rather than being forced into a full requirements template.
- Semantic correction is not only a fixed replacement list. When the ASR literal text is incoherent but the development-feedback context has an obvious homophone or near-sound candidate, restore the user's likely intent while preserving uncertain code, paths, commands, logs, and proper nouns.
- Chat mode is a first-class smart rewrite mode for social media and private-message contexts. Automatic mode should route WeChat, Messages, Slack, Discord, Telegram, WhatsApp, LINE, Signal, Threads, X/Twitter, Instagram, Rednote/Xiaohongshu, and similar chat windows to `chat`, unless a higher-priority content rule such as summary intent matches first.
- Chat mode prompt design should remain a coherent whole, not a patch list or a library of copyable calibration answers. It removes genuine speech-recognition residue while preserving the user's natural wording, attitude, person and question form. It does not add emoji unless the source already contains one.
- Developer requirement output must preserve the user's speaking position. First-person and second-person expressions such as "我觉得", "我要求", "你看", "告诉我", "我们开始", and "给我" must not be rewritten into third-person summaries such as "用户要求" or "要求对方告知".
- Short developer directions must stay short. If the raw text is a single brief direction, command, or intent, such as "先从模型段解决文同", rewrite only speech-recognition errors, terminology, punctuation, and word order; do not expand it into goal/context/constraints/completion-standard fields.
- Multiple tasks may use short bullets. Full goal/context/constraints/completion-standard templates are allowed only when the user explicitly asks for a full requirement, acceptance criteria, or plan, or when the raw text already contains enough fields to justify that structure.
- If the raw text itself contains a prompt, rule block, boundary note, or bullet list intended for a coding agent, preserve the original directive tone, bullet structure, and first/second-person stance. Do not collapse it into a generic summary like "用户要求优化提示词".
- These guardrails apply both to manual developer requirement mode and to automatic mode when target/context rules choose developer requirement mode.
- Custom template required-placeholder injection is mode-specific. Developer requirement, developer statement, and code commit templates are auto-patched with `{developerGlossary}` if missing; polish and exhaustive summary templates are respected as written.
- Exhaustive summary mode may compress wording, but must preserve high-priority semantic boundaries: prohibitions, "must/never" constraints, privacy/security warnings, secrets, upload/commit/publication limits, destructive actions, payment/permission/data-loss risks, and required destinations such as "configure this in Vercel env vars instead of pushing `.env` to GitHub".
- Exhaustive summary mode may remove filler and merge repeated wording, but it must retain contrast pairs, examples that define correctness, ordered actions, and every explicitly prohibited action. Compression is invalid when it drops one side of a time contrast or reduces “only organize, do not execute, do not expand” to a weaker single restriction.
- Idea pill recordings use a dedicated `IdeaPillRewriteModeStore`, not the main dictation smart-rewrite dropdown. The default is `即时归纳` (`RewriteMode.note`), and Markdown front matter should record the actual mode used for that idea pill task.
- Term normalizer fuzzy matching is opt-in per term through `DeveloperTerm.allowsFuzzy`. User-created aliases default to exact matching to avoid accidental English-word rewrites.
- Term normalization must not merge related but distinct product names. In particular, standalone `GPT` is not an alias of `ChatGPT`, while explicit ASR variants such as `chatGTP` may normalize to `ChatGPT`. Stored historical default glossary entries are migrated conservatively; user-authored custom terms and prompts are preserved.
- Fixed-recording prompt replay reports ASR output and rewrite output as separate layers and routes generated text through the production `SmartInputRouter` before declaring the final delivery successful. A question reversal or other uncertain ASR error must be reported as an ASR observation instead of being silently repaired by the rewrite prompt. Local replay artifacts may contain transcripts and therefore stay under `.artifacts` and out of version control.

### AI Providers

- The user-facing AI model domain contains exactly two choices: local direct-drive `Qwen3-4B-Instruct-2507 4bit` and online `DeepSeek v4 flash`. `SmartAIModelStore` is the single selection authority shared by smart rewrite, voice translation, and screenshot OCR translation.
- Qwen is the preferred default only when its managed model and runtime are structurally ready. A missing, unknown, or retired Ollama selection is migrated and persisted as Qwen when ready, otherwise DeepSeek. A valid saved Qwen or DeepSeek choice is preserved.
- DeepSeek v4 flash remains an explicit paid cloud option, not an automatic fallback from local failures.
- `Qwen3-4B-Instruct-2507 4bit` routes through `SmartAIProvider.typeWhaleMLX`. `SelectedSmartAITextEngine` handles rewrite and voice translation; `SelectedScreenshotTranslationEngine` independently follows the same selected model and the Qwen engine uses `ScreenshotTranslationPromptBuilder` so OCR line IDs and layout rules are preserved.
- Qwen model ownership is entirely under `Application Support/TypeWhale Pro/Models/LLM/qwen3-4b-instruct-2507-4bit`. Production discovery, validation, execution and logs must not depend on Ollama, LM Studio, a terminal, or another model-host application.
- The managed Qwen catalog pins immutable revision `50d427756c6b1b2fe0c0a10f67fbda1fc8e82c1b`, 13 exact artifact sizes, and SHA-256 values. Selection is committed only after the complete model and pinned TypeWhale MLX runtime validate; validation runs off the main actor and failure restores the prior menu selection.
- `ManagedLLMRuntimeService.shared` owns one hidden JSONL helper. Qwen requests use the tokenizer's standard chat template, offline/local-only loading, generated-token-only decoding, bounded final-text responses, ID matching, timeout and cancellation. Prompts, raw transcripts, generated token streams, and model paths must not enter UI or diagnostics.
- Managed Qwen stays hot during ordinary use and has no idle-unload timer. Switching away, sleep, power-off, app termination, and final-input cancellation stop or cancel only the TypeWhale-owned helper. High-memory release is allowed only while no recording, final rewrite, voice translation, or paste work is active, and Qwen is immediately background-warmed again when it remains selected.
- A managed request failure or timeout returns this request to the existing original-text fallback. It must not silently switch to DeepSeek or another provider.
- TypeWhale owns no active Ollama engine, process supervisor, warm-up, health probe, capsule indicator, menu item, or download link. Retirement of TypeWhale integration never deletes or changes a user's separately installed Ollama app or weights.
- MiniMax remains non-user-facing unless it later passes intent-preservation tests.
- Future providers must enter through adapter/strategy boundaries and pass smart rewrite, voice translation, and screenshot translation quality fixtures before becoming visible.
- Observability must never upload audio, screenshots, OCR text, clipboard contents, API keys, file paths, or raw transcripts.

## Accepted Architecture Decisions

### Architecture Governance

- Use lightweight Clean Architecture plus Coordinator / Use Case, Strategy, State Machine, Command, and Adapter / Port.
- Do not do a broad rewrite.
- Refactor one stable workflow boundary at a time.
- Extract abstractions from verified product behavior, not speculation.

### Workflow Patterns

- Coordinator / Use Case: speech input, screenshot capture, app lifecycle, permission checks, paste submission.
- Strategy: ASR providers, AI text providers, translation direction, paste behavior, OCR/screenshot translation providers, preview-theme variations.
- State Machine: long-running or cancelable workflows such as screenshot selection/translation and speech recording/finalization/paste.
- Command: toolbar actions, screenshot annotation actions, global hotkey actions, recent-transcription copy/save, undoable operations.
- Adapter / Port: macOS APIs, model runtimes, keychain, pasteboard, observability, network providers, screen capture.

### Historical Decisions Still Active

- Final transcription is independent from realtime preview.
- Speech input tasks may carry a product purpose. Normal dictation can paste to the target app; `ideaPill` reuses recording, final ASR, realtime preview, and smart rewrite, but saves Markdown notes and must not enter the automatic paste queue.
- Smart rewrite preference is purpose-specific. Normal dictation uses the user's current global smart rewrite preference; `ideaPill` always uses `.developerRequirement` so quick captured thoughts land in the backlog as actionable product/development material instead of inheriting chat, polish, or exhaustive summary.
- Automatic paste must not post Command-V immediately after writing `NSPasteboard.general`. `PasteCoordinator` must first verify that the pasteboard string reads back as the current request text; unreadable same-change-count states retry briefly, and different text after a changeCount advance is treated as a stolen clipboard and must cancel paste without restoring over the user's newer clipboard.
- “整理范围”和“粘贴后自动发送”共用一个按需加载的应用目录与编辑窗口，但分别保存到 `SmartRewriteAutoRuleStore` 和 `AutoSendSettingsStore`。窗口内只编辑草稿，保存时统一提交，取消不得写入。
- 自动发送动作在普通听写进入粘贴队列前由 `AutoSendPolicy` 冻结；`PasteCoordinator` 只接收已决定的动作。文字成功触发粘贴后，它立即把动作与原目标交给 `AutoSendCountdownCoordinator`，自身仍按原有 0.3 秒节奏恢复剪贴板、结束请求并释放队列，不等待倒计时。
- 自动发送倒计时固定为 2 秒。Presenter 每次显示时只读取 `PreviewPresenting.presentationFrame`，将浮层以 10px 间距优先放在生产胶囊上方并横向居中；上方空间不足时放到下方，无胶囊 frame 时回退到原屏幕底部位置。该 frame 只用于展示定位，不进入 ASR、实时缓存、粘贴队列或按键发送决策。
- `AutoSendCountdownCoordinator` 是待发送请求、唯一 token 和 2 秒计时器的唯一所有者。到期前切换应用、新录音、后续任务替换旧任务、程序停止，或用户手动按下 Return / 数字键盘 Enter，均取消旧请求且不补发；到期时再次核对目标进程，只允许一次按键发送。
- `AutoSendCountdownPresenter` 只展示无焦点浮层并转发“取消”点击，不读取设置、不管理计时器、不发送按键。Esc 复用 `HotkeyMonitor` 现有事件监听，只有确实取消了待发送请求时才吞掉成对的 Esc down/up；手动 Return / Enter 只取消倒计时而不吞键。TypeWhale 自动发送事件必须携带 `eventSourceUserData` 标记，避免被同一监听器误判为用户提前发送。
- 鼠标全局快捷键采用“匹配后独占、未匹配放行”策略：`HotkeyMonitor` 只有在某个鼠标按下/抬起事件成功匹配 TypeWhale 已配置快捷键时才吞掉原始事件，避免截图等动作与前台应用的前进/返回同时发生；未绑定侧键保留系统行为。鼠标按钮测试暂停真实快捷键处理并继续纯旁听，不得为了测试吞掉事件。
- 翻译（含失败回退）、闪念和 OpenClaw 均不得触发自动发送。自动发送总开关仍是整体回滚入口；该功能不得进入 ASR、实时缓存、胶囊或整理链路。
- `ApplicationCatalog` 只在应用范围窗口打开时扫描应用，关闭时取消；它不得常驻、观察录音或进入实时识别、缓存和胶囊链路。应用图标只由 UI 为可见行按需加载。
- Screenshot overlay must not activate or reorder the TypeWhale main window.
- Automatic smart rewrite rules may match target context and content text separately.
- Capsule preview is a presentation pipeline with bounded realtime work and stale-callback protection.
- AI provider work must preserve user intent over model novelty.
- ASR/VAD memory safety must prefer response latency over aggressive unloading.

## Historical Or Superseded Decisions

Historical records remain in `docs/开发日志.md`. These decisions should not be copied back into active code without a fresh review:

- The `PreviewComposer` / committed-volatile preview experiment failed the real capsule experience and was removed.
- The old short-pause segment reset / sliding-window preview path was rejected because it caused visible jumps and lost context.
- ADR-010's blanket removal of `committedPreviewText` is superseded by the current chunk-commit preview path. The rejected part is reset-on-pause / sliding-window behavior, not every form of frozen preview prefix.
- ADR-002's "MVVM + Coordinator" wording is narrowed by the current governance rule: use AppKit-friendly coordinators and small view models where useful, but do not convert the app to a heavy MVVM rewrite.

## Architecture Governance Plan

Each version must preserve the stable main path unless a behavior change is explicitly approved.

### Review Action Items: 2026-06-30

These items come from the code review before the next refactor pass. They are concrete blockers or ambiguity sources that must be addressed by the staged plan below.

#### Version A Resolved In First Pass

- `TypeSpeakerApp.applicationDidFinishLaunching` no longer calls `lifecycle.showMainWindow()` unconditionally. Launch now records an explicit hidden-by-default launch visibility policy.
- Dock/Finder reopen is an explicit user entry point and should call `AppLifecycleCoordinator.showMainWindow()`. Screenshot overlay shutdown no longer registers reopen suppression; screenshot copy/cancel/save/OCR/translation paths stay outside main-window lifecycle.
- `SpeechInputCoordinator.beginScreenshotFromHotkey(...)` no longer calls `hideMainWindow()` before entering screenshot mode. Screenshot entry keeps the TypeWhale main-window state unchanged.
- `ScreenshotOverlayView` now limits toolbar interaction during translation pending state to cancel only. Copy, save, OCR, annotation, undo, redo, and done are disabled while translation is in flight.
- Screenshot translation callbacks are guarded by an overlay-local generation token and are invalidated on close, cancel, replace/recapture, and pending recapture.
- Screenshot annotation edit history is managed by `ScreenshotEditHistory`: undo removes the latest placed markup into redo history, redo restores it, and adding a new markup clears redo history.
- Screenshot toolbar sizing is managed by `ScreenshotToolbarLayout`; adding toolbar commands must keep the 800pt overlay fit check green before shipping.

#### Version A Remaining Review Items

- First-install/default-open policy is not yet product-specified. Current implemented policy is hidden-by-default on normal launch.

#### Version B Resolved In First Pass

- Added `ScreenshotSessionState` with explicit `idle`, `selecting`, `selected`, `windowRecapturePending`, `translating`, `completed`, `cancelled`, and `failed` phases.
- Added `ScreenshotToolbarCommand` availability rules and wired toolbar hit-testing, drawing, pointer handling, and keyboard shortcuts through the same command gate.
- Added `ScreenshotSessionStateCheck` so pending-state command availability is covered without instantiating AppKit overlay windows.
- Build 449 corrected a Build 448 regression: if the overlay already has a usable selection, `idle` or `selecting` must not disable ordinary screenshot toolbar commands. Translation and window-recapture pending still allow cancel only.
- Build 450 corrected screenshot translation layout: line-level translation blocks align to each OCR source line's starting x position, with right-edge fallback only when needed.
- Build 451 added `ScreenshotCommandDispatcher`, a pure command reducer that maps screenshot command context to command availability and effects. `ScreenshotOverlayView` now renders and executes effects, while command policy lives in the testable model.
- Build 452 added `ScreenshotOperationToken` / `ScreenshotOperationTokens`, replacing ad hoc generation counters for window recapture, OCR, screenshot translation, and transient status reset.
- Build 454 added `ScreenshotTranslationLayoutCheck` so Build 450 source-line x alignment and right-edge fallback are covered by a formal lightweight test instead of a temporary shell snippet.
- Build 454 added `docs/SCREENSHOT_OVERLAY_QA.md` as the real installed-app verification checklist for the remaining Version B gate.
- B5 real installed-app overlay QA passed manually on 2026-06-30 using `docs/SCREENSHOT_OVERLAY_QA.md` shortest critical path. Covered ordinary region screenshot, toolbar availability, translation pending cancel-only behavior, stale callback safety by Esc/right-click cancel, copy/save/OCR/translate/annotation/undo, and main-window visibility preservation.

#### Version B Remaining Review Items

- None for the current Version B gate. Future screenshot interaction changes must still include real installed-app overlay QA because Build 448 proved code-level state tests alone are insufficient.

#### Refined Version B Plan

Version B should finish screenshot architecture before Version C starts. The goal is not to add a broad framework; the goal is to make screenshot behavior explainable, testable, and hard to regress.

1. `B2 ScreenshotCommandDispatcher`
   - Status: first pass complete in Build 451.
   - `ScreenshotCommandContext` carries current session state, real usable selection, operation generation, annotation mode, and undo/redo availability.
   - `ScreenshotCommandDispatcher` returns command availability and `ScreenshotCommandEffect` values such as copy, save, OCR, translate, select tool, undo, redo, done, cancel, or ignore.
   - The dispatcher does not render AppKit views, crop images, call OCR, call DeepSeek, write files, or touch the pasteboard.
   - `ScreenshotOverlayView` keeps rendering, event forwarding, and side-effect execution.

2. `B3 Screenshot Operation Tokens`
   - Status: first pass complete in Build 452.
   - Consolidated translation, OCR, and window recapture invalidation into one explicit operation token model.
   - Cancel, close, replace/recapture, and superseding actions invalidate outstanding callbacks.
   - Old callbacks may finish, but they must not mutate markups, status, pasteboard, saved files, or overlay state.
   - The same token model also guards transient status reset so a newer screenshot operation is not overwritten by an older success timeout.

3. `B4 Screenshot Layout Policy`
   - Status: first pass complete in Build 454.
   - Keep screenshot translation layout policy in `ScreenshotTranslationLayout`.
   - Preserve Build 450 behavior: translation blocks align to source-line starting x; only right-edge overflow may shift left.
   - Do not move line-level translation placement into `ScreenshotOverlayView` drawing code.
   - `ScreenshotTranslationLayoutCheck` is the current lightweight regression for this policy.

4. `B5 Real Overlay Verification Gate`
   - Status: passed manually on 2026-06-30 against installed `1.6.6 (Build 454)`.
   - Verified installed app behavior for ordinary region selection, toolbar buttons, translation pending cancel-only state, stale callback safety, copy/save/OCR/translation/annotation/undo, Esc/right-click cancel, and main-window visibility preservation.
   - Window-selection and recapture behavior remain covered by the QA checklist for future screenshot passes; no blocker remains for entering Version C.
   - Use `docs/SCREENSHOT_OVERLAY_QA.md` as the checklist for this gate.

Exit criteria for Version B:

- Met for the current architecture pass. `ScreenshotCoordinator` / `ScreenshotOverlayView` still execute AppKit side effects, but command policy, pending-state availability, operation invalidation, and layout policy now live behind explicit state/command/layout models.
- Version C may begin next, preserving all screenshot invariants above.

#### Version C Blockers

- `SpeechInputCoordinator` remains the main concentration point for hotkeys, recording, VAD, realtime preview, final ASR, smart rewrite/translation, paste, screenshot entry, and memory safety. Action: split through speech workflow state/use cases after Version A/B stabilize user-visible state.
- Final ASR, smart processing, paste, target tracking, and ASR memory safety are interleaved in one coordinator. Action: define use cases for final recognition, smart processing, paste submission, and idle memory safety before moving logic.

#### Version C Resolved In First Pass

- Build 455 introduced `SpeechWorkflowState`, a pure task-identity and stale-callback gate for the voice workflow.
- `SpeechWorkflowState` now owns the latest submitted task id, completed final task de-duplication, realtime callback acceptance, UI update eligibility, and processed-result submission eligibility.
- `SpeechInputCoordinator` still orchestrates recording, VAD, realtime preview, final ASR, smart processing, paste, target tracking, and memory safety, but old task callbacks now pass through one workflow gate before mutating UI, history, backlog, paste queues, or realtime preview state.
- `SpeechWorkflowStateCheck` covers new-recording invalidation of older tasks, final submission de-duplication, processed-result stale gating, realtime callback acceptance, and the completed-final task retention limit.
- Build 456 introduced `FinalRecognitionUseCase`, which owns the final ASR adapter call, raw ASR response parsing, recognition text cleanup, model-error handling, and empty-result classification.
- `SpeechInputCoordinator` still owns final VAD gating, UI progress, smart rewrite/translation, paste submission, target app lookup, and memory safety. The final recognition boundary now returns only `recognized`, `empty`, or `failed`.
- `FinalRecognitionUseCaseCheck` covers successful final recognition parsing, empty-result classification, model error propagation, and the fake-ASR callback path.
- Build 457 tightened microphone input release: `AudioRecorder` now tracks tap installation, logs explicit input-session release reasons, performs delayed idle release after stop/cancel, and lets background health checks clear any idle residual input session.
- Build 458 added a startup route-stability guard for Bluetooth microphones: `AudioRecorder` snapshots the intended input device at recording start and ignores same-device `AVAudioEngineConfigurationChange` / device-list churn during the short startup window, while still cancelling on real input switches.
- Build 459 made that guard recoverable: if the same-device startup configuration change leaves `AVAudioEngine` stopped, `AudioRecorder` immediately attempts to restart the engine before falling back to route-change cancellation.
- Build 674 replaces cancel-on-route-change with a single-session microphone switch state machine. Every hardware buffer is converted to canonical 16 kHz mono Float32 before WAV, waveform, VAD, and preview processing, so manual input changes preserve the active task and recorded evidence. A disconnected manual device permanently downgrades the saved preference to follow-system; reconnecting it does not auto-restore.
- Build 679 splits capture by routing semantics: system-default input uses `AVAudioEngine`, while an explicitly selected hardware device uses `ManualAudioInputCapture` backed by a dedicated AUHAL AudioUnit and render callback. Explicit capture never mutates an AVAudioEngine input node, preventing configuration-change rebuild loops while preserving the shared canonical conversion, VAD, preview, and recording pipeline.
- Build 677 keeps same-device `AVAudioEngineConfigurationChange` recovery inside `AudioRecorder`: the stale tap is removed and rebuilt against the post-change format before restarting the existing engine. Internal recovery never emits a user switch-success event. User-initiated microphone results are presented through the global toast layer, while the recording capsule remains authoritative for waveform and transcript context.

#### Version C Next Review Items

- Verify Build 456 installed-app voice main path before extracting the next boundary.
- Extract smart processing next, using the stable `FinalRecognitionOutcome` contract as input.
- Extract paste submission only after smart processing has a stable task/result contract.
- Keep ASR/VAD memory safety in the coordinator until recording/finalizing/pasting state transitions are fully represented in the workflow model.

#### Preview Pipeline Blocker

- Build 692 resolves the final-chunk ownership gap with a two-phase commit. `AudioRecorder` freezes the chunk buffers behind an immutable `ChunkCommitTicket`, but does not advance the authoritative chunk index/start frame until the final snapshot write succeeds. The snapshot queue retries once; repeated failure retains frozen ownership and emits `final_chunk_snapshot_write_failed`. Only after the complete recording is successfully materialized may stop mark the pending range `recoveredFromFullRecording` and release it. New realtime snapshots do not cross an unresolved final boundary; full-recording final ASR remains the production fallback and authority.
- Build 718 makes final WAV materialization an explicit ownership boundary: `AudioRecorder.stop()` drains all queued writes and releases the retained `AVAudioFile` writer before reopening the pending URL. Final ASR, VAD, history, and paste must never consume a WAV while its writer still owns an unfinalized header.

### Next Section Handoff

The next coding section should start from this document, not from chat history.

Read order:

1. `docs/ARCHITECTURE.md`: stable invariants, review action items, and the staged Version A-D plan.
2. `docs/开发日志.md`: latest Build 454 entry for screenshot layout check and overlay QA gate, Build 453 for active documentation consistency, Build 452 for screenshot operation tokens, Build 451 for screenshot command dispatcher, Build 450 for screenshot translation layout, Build 449 for the screenshot toolbar regression fix, then Build 448 for the original Version B state model work.
3. `native/Sources/Presentation/Screenshot/ScreenshotSessionState.swift`: session state, toolbar command availability, command context, dispatcher, pure command effects, and operation token model.
4. `native/Sources/Presentation/Screenshot/ScreenshotCoordinator.swift`: current screenshot overlay rendering, event forwarding, command effect execution, and token-gated async callbacks.
5. `native/Tests/ScreenshotTranslationLayoutCheck.swift`: current lightweight layout regression for Build 450 translation placement.
6. `docs/SCREENSHOT_OVERLAY_QA.md`: real installed-app checklist required before declaring Version B done.
7. `native/Sources/Application/SpeechWorkflowState.swift`: current pure task identity and stale-callback gate for Version C.
8. `native/Tests/SpeechWorkflowStateCheck.swift`: current lightweight regression for Version C task gating.
9. `native/Sources/Application/SpeechInputCoordinator.swift`: current speech workflow orchestration and still-large concentration point.
10. `native/TypeSpeakerApp.swift`: current hidden-by-default launch policy and explicit main-window entry points.

Recommended next action:

- Continue Version C only after Build 456 installed-app voice path verification. Preserve Build 455 `SpeechWorkflowState` task gate, Build 456 final recognition use-case boundary, Build 449 command availability, Build 450 translation layout, Build 451 command dispatcher boundaries, Build 452 operation-token invalidation, Build 454 formal layout regression, and the 2026-06-30 B5 installed-app overlay QA result.
- Do not start with a broad `SpeechInputCoordinator` rewrite. Next split smart processing behind a small use-case boundary, then paste submission and idle memory safety in small verified steps.
- Preserve the Build 450 behavior: screenshot entry does not own TypeWhale main-window visibility, launch is hidden by default unless an explicit user action opens the main interface, normal screenshot toolbars stay usable after selection, translation/window-recapture pending allow cancel only, and translation blocks align to their OCR source-line starting x.

Current verification baseline:

- Full Swift typecheck passed after Build 456 changes.
- `ScreenshotSessionStateCheck` passed, including dispatcher availability/effect checks and operation-token invalidation checks.
- `ScreenshotTranslationLayoutCheck` passed, preserving Build 450 source-line x alignment and right-edge fallback.
- `SpeechWorkflowStateCheck` passed, preserving Version C task identity and stale-callback gating.
- `FinalRecognitionUseCaseCheck` passed, preserving final recognition response parsing and empty-result classification.
- `git diff --check` passed.
- `./native/build_and_log.sh` installed and opened `/Applications/TypeWhale.app` as `1.6.6 (Build 456)`.
- Manual B5 installed-app overlay QA shortest critical path passed per user report on 2026-06-30.

### Version A: State And Window-Lifecycle Corrections

Purpose: repair product-semantics regressions before adding more abstractions.

Scope:

- Screenshot entry observes the desktop without managing TypeWhale main-window visibility.
- Main-window visibility is governed by explicit user actions and approved launch behavior only.
- Screenshot translation pending state allows cancel but disables or guards copy, save, OCR, annotation, undo, and other unstable-output actions.
- Stale translation callbacks after cancel or superseding operations are ignored.
- UI controls that promise unwired runtime behavior are either wired or hidden.

Verification:

- Manual screenshot QA with TypeWhale main window hidden, behind another app, and visible in front.
- Pending screenshot translation QA: copy/save do not export unstable images.
- Relevant checks for changed state policy.
- Code changes must follow the repository build rule in `AGENTS.md`: run `./native/build_and_log.sh`, overwrite `/Applications/TypeWhale.app`, open the installed app, and report any verification gap.

### Version B: Screenshot Session State Machine And Toolbar Commands

Purpose: reduce screenshot coordinator/view state coupling without changing the user-visible workflow.

Scope:

- Introduce `ScreenshotSessionState` for idle, selecting, selected, window-recapture-pending, translating, completed, cancelled, and failed.
- Convert toolbar actions to command-style dispatch with per-state availability.
- Keep annotation rendering in presentation; move action policy out of mouse handlers.
- Make window recapture and translation cancellation generation-based and testable.

Verification:

- Lightweight checks for allowed actions per screenshot state.
- `ScreenshotTranslationLayoutCheck` for screenshot translation placement.
- Manual QA: region selection, window selection, Esc cancel, translate, copy, save, undo.

### Version C: Speech Workflow State Machine And Use Cases

Purpose: keep voice input stable while making recording/finalization/paste states explicit.

Scope:

- Extract speech recording state transitions from `SpeechInputCoordinator` into a state model or reducer.
- Separate use cases for start recording, finish recording, final recognition, smart processing, paste, and recovery.
- Keep realtime preview as presentation feedback only.
- Preserve ASR/VAD warm-resource policy and high-memory flush boundary.

Verification:

- Long press, toggle recording, auto-finish, quiet speech, empty recording, wake recovery, paste target regression.
- Existing ASR/VAD and `FinalSpeechGate` checks continue to pass.

### Version D: Provider, Adapter, And Observability Hardening

Purpose: make external systems swappable and diagnosable without leaking experiments into the product path.

Scope:

- Keep DeepSeek as the only active AI provider until another provider passes intent-preservation tests.
- Keep AI, OCR, ASR, paste, keychain, observability, and screen-capture APIs behind adapters.
- Add provider-quality validation fixtures before future providers return to UI.
- Enforce observability privacy boundaries.
- Add a source-of-truth consistency audit for active docs and code comments. Priority terms: memory thresholds, build/install rules, version baselines, cost/token limits, screenshot pending-state semantics, and ASR/VAD warm-resource policy.
- Historical logs and version history may retain old values as historical facts; active docs (`AGENTS.md`, `docs/ARCHITECTURE.md`, PRD, release docs, current code comments) must not present superseded values as current behavior.

Verification:

- Provider route tests.
- Privacy checklist for observability events.
- Consistency audit checklist: `rg` for stale threshold/version/build-rule terms; confirm active docs point to code-level source of truth; record intentional historical references separately.
- Manual main-path QA after behavior-affecting changes.

## Verification Gates

For architecture work, choose the narrowest meaningful checks, but do not declare a workflow refactor done without proving the affected path.

Minimum for docs-only architecture changes:

- Links and references point to `docs/ARCHITECTURE.md`.
- Current behavior and historical behavior are separated.
- No old architecture document still presents superseded behavior as current.

Minimum for code architecture changes:

- `git diff --check`.
- Relevant unit/lightweight Swift checks.
- Main voice path remains valid: hotkey, recording, realtime preview, final ASR, paste.
- Screenshot path remains valid when touched: region selection, window selection, cancel, copy/save, OCR/translation.
- UI/interaction changes receive design review or a clearly stated verification gap.
- Code changes must follow `AGENTS.md`: run `./native/build_and_log.sh`, overwrite `/Applications/TypeWhale.app`, open the installed app, and report verification gaps. Pure docs-only changes do not require a build unless requested.

## Documentation Rules

- Current architecture belongs here.
- Chronological implementation details belong in `docs/开发日志.md`.
- Current numeric thresholds and operational policies must point to their code-level source of truth when one exists; do not duplicate stale literals such as memory limits across active docs.
- UI/visual rules belong in `DESIGN.md`.
- Screenshot translation product specifics belong in `docs/SCREENSHOT_TRANSLATION_SPEC.md`.
- Screenshot overlay installed-app verification belongs in `docs/SCREENSHOT_OVERLAY_QA.md`.
- Model setup belongs in `docs/MODEL_SETUP.md`.
- Security/privacy policy belongs in `SECURITY.md` and relevant architecture privacy notes here.
- Old architecture files are migration stubs and must not become current sources again.
