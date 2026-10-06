# MeloTTS OpenClaw Voice Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the OpenClaw Qwen/CosyVoice TTS path with one fixed Chinese MeloTTS voice delivered as a separately managed voice pack.

**Architecture:** A versioned voice-pack manifest resolves a pack-local Python runtime and offline model assets. A JSONL Melo worker runs behind the existing Swift sidecar/player, prewarms during OpenClaw reply generation, synthesizes sentence WAVs, and exits after a 180-second fully idle lease.

**Tech Stack:** Swift/AppKit/AVFoundation, Python 3.10, MeloTTS/PyTorch CPU, JSONL IPC, existing model downloader and shell/Swift checks.

## Global Constraints

- MeloTTS is the only user-visible local natural voice in this branch; remove Qwen3-TTS and CosyVoice2 TTS choices.
- One fixed Chinese speaker; no cloning, speaker picker, or role instruction.
- Keep enable, volume, 0.75x–1.75x rate, playback-content, and interruption controls.
- Voice pack is downloaded, hash-checked, repairable, and deletable; never bundled in the default DMG.
- Runtime speech is offline and must never run pip or download missing assets.
- Warm lease is exactly 180 seconds and may expire only when synthesis and playback are idle.
- Preserve OpenClaw text, ASR, screenshots, copy, and paste on every TTS failure.
- Do not modify the other session's TTS backend or final shared engine selector.

---

### Task 1: Settings migration and UI simplification

**Files:**
- Modify: `native/Sources/Infrastructure/Settings/OpenClawVoiceSettings.swift`
- Modify: `native/Sources/Presentation/Main/MainViewController+PanelLayout.swift`
- Modify: `native/Sources/Presentation/Main/MainViewController+Configuration.swift`
- Modify: UI save/load declarations located by `rg "openClawVoice(Model|Speaker|Style)" native/Sources/Presentation/Main`
- Test: `native/Tests/OpenClawVoiceSettingsCheck.swift`
- Test: `native/Tests/OpenClawVoiceSettingsTabCheck.sh`

**Interfaces:**
- Produces `OpenClawVoiceSettings(enabled:volume:speechRate:playbackPolicy:interruptPolicy:)` with no model/speaker/style fields.

- [ ] Write failing checks asserting legacy Qwen values load into the fixed Melo settings and the voice panel omits model, speaker, and role rows.
- [ ] Run `swift native/Tests/OpenClawVoiceSettingsCheck.swift native/Sources/Infrastructure/Settings/OpenClawVoiceSettings.swift` and `bash native/Tests/OpenClawVoiceSettingsTabCheck.sh`; expect failures referencing removed/expected controls.
- [ ] Remove the Qwen/Cosy enums and fields, preserve old UserDefaults keys only as ignored migration residue, and reduce the panel to enable/volume/rate/content/interruption.
- [ ] Run the two checks and expect PASS.
- [ ] Commit settings/UI migration.

### Task 2: Managed Melo voice-pack manifest

**Files:**
- Create: `native/Sources/Infrastructure/Models/MeloTTSVoicePack.swift`
- Modify: `native/Sources/Infrastructure/Models/ManagedASRModelCatalog.swift`
- Test: `native/Tests/MeloTTSVoicePackCheck.swift`
- Modify: `native/Tests/ManagedASRModelCatalogCheck.swift`

**Interfaces:**
- Produces `MeloTTSVoicePack.directory`, `runtimePythonURL`, `workerAssetsURL`, `modelDirectory`, `bertDirectory`, `manifestURL`, and `validate(fileManager:) throws`.

- [ ] Write failing tests for the catalog's sole `melotts-zh` TTS item and for missing runtime/model/BERT/manifest validation failures.
- [ ] Run the focused Swift checks; expect missing `MeloTTSVoicePack` and old catalog failures.
- [ ] Implement a pack manifest rooted at `Models/tts/melotts-zh` and replace all three old TTS catalog items with one primary Melo item whose detail explains the separate natural-voice pack.
- [ ] Run focused checks and expect PASS.
- [ ] Commit the voice-pack manifest and catalog.

### Task 3: Offline Melo JSONL worker

**Files:**
- Replace: `native/Resources/openclaw_tts_worker.py`
- Create: `native/Tests/OpenClawMeloTTSWorkerCheck.py`

**Interfaces:**
- Consumes `--pack-dir`.
- Commands: `{"type":"warmup","id":...}`, `{"type":"synthesize","id":...,"text":...,"output":...}`, `{"type":"shutdown","id":...}`.
- Responses include `ok`, `id`, `type`, and timing/error fields.

- [ ] Write a fake-module worker test proving stdout contains JSON only, warmup loads once, two syntheses reuse the runner, CPU/MPS stays consistent, shutdown exits, and missing assets fail structurally.
- [ ] Run `python3 native/Tests/OpenClawMeloTTSWorkerCheck.py`; expect failure because the worker still imports Qwen.
- [ ] Implement `MeloTTSRunner` with pack-local imports, offline environment, fixed `ZH` speaker, CPU-only torch behavior, warmup synthesis, and structured JSONL protocol.
- [ ] Run the worker check and `python3 -m py_compile native/Resources/openclaw_tts_worker.py`; expect PASS.
- [ ] Commit the worker replacement.

### Task 4: Swift Melo sidecar and 180-second lease

**Files:**
- Create: `native/Sources/Infrastructure/OpenClaw/MeloTTSVoiceBackend.swift`
- Modify: `native/Sources/Infrastructure/OpenClaw/OpenClawVoicePlayback.swift`
- Test: `native/Tests/MeloTTSVoiceBackendCheck.swift`
- Modify: `native/Tests/OpenClawVoicePlaybackCheck.swift`
- Modify: `native/Tests/OpenClawVoicePlaybackIntegrationCheck.sh`

**Interfaces:**
- Produces `MeloTTSVoiceBackend.ensureWarm()`, `synthesize(text:outputURL:)`, `cancel()`, `notePlaybackActivity()`, and `shutdown()`.
- Player requests contain only text/output/settings; pack paths are resolved by the backend.

- [ ] Write failing checks for pack-local Python launch, warmup command, synthesis without speaker/instruction, sidecar reuse, EOF cleanup, and a configurable lease whose production default is 180 seconds.
- [ ] Run focused checks; expect missing backend and old Qwen protocol failures.
- [ ] Move JSONL process ownership into `MeloTTSVoiceBackend`, add lease renewal/cancellation, and simplify the player request/runtime to Melo-only paths.
- [ ] Ensure stop-latest stops audio and cancels pending generation without killing a healthy warmed backend; explicit stop shuts down fully.
- [ ] Run all OpenClaw voice checks and expect PASS.
- [ ] Commit backend and playback integration.

### Task 5: Remove Qwen TTS residue and update active documentation

**Files:**
- Modify: `docs/产品需求文档.md`
- Modify: `docs/ARCHITECTURE.md`
- Modify: `docs/开发日志.md`
- Modify: `native/Sources/Presentation/VersionHistory/VersionHistoryViewController.swift`
- Modify tests found by `rg "qwen3-tts|Qwen3-TTS|cosyvoice2-05b|CosyVoice2" native/Tests`.

**Interfaces:**
- Active product docs describe Melo-only local natural voice, separate voice-pack download, and 180-second TTS lease; historical release entries remain historical.

- [ ] Add/adjust checks so active settings, catalog, worker, and integration no longer reference Qwen/Cosy TTS while ASR Qwen references remain untouched.
- [ ] Run the checks and confirm they fail on active residue.
- [ ] Update active documentation and current version-history entry; preserve old historical entries as an audit trail.
- [ ] Run `rg` with scoped exclusions and all voice/catalog checks; expect only historical Qwen/Cosy TTS references.
- [ ] Commit docs and residue removal.

### Task 6: Review, build, install, and real-app verification

**Files:**
- Build scripts/version records changed only by `./native/build_and_log.sh` according to repository policy.

**Interfaces:**
- Produces an installed `/Applications/TypeWhale.app` that launches and degrades safely when the downloadable Melo pack is absent.

- [ ] Recheck branch/status, build processes, relevant mtimes, and overlap with the other session; stop if shared release files are concurrently owned.
- [ ] Run the complete focused voice/model test suite plus `git diff --check`.
- [ ] Use `superpowers:requesting-code-review` and fix blocking findings.
- [ ] Update required current version/development-log narrative before build.
- [ ] Run `./native/build_and_log.sh`, verify signature, launch installed app, and verify missing-pack UI/degraded behavior.
- [ ] If a complete Melo voice pack artifact is available, verify real OpenClaw warmup, first sentence, continuous replies, interruption, rates, and 180-second process release; otherwise explicitly record that pack-backed installed-app audio remains blocked on artifact publication.
- [ ] Commit only this branch's release/build records after `git status --short` scope review.
