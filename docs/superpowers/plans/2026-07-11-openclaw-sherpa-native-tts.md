# OpenClaw Sherpa Native TTS Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Python-free Sherpa native TTS path for OpenClaw while preserving the current working Sherpa Python sidecar as the behavior baseline and rollback path.

**Architecture:** Keep `OpenClawVoicePlayer` as the queue, prewarm, interrupt-policy, audio-playback, and speaking-notification owner. Replace only the synthesis backend behind a narrow adapter: current Python JSONL sidecar remains available, while the new native path first uses the Sherpa ONNX offline TTS executable and can later graduate to a C API bridge if the CLI path passes quality and packaging gates. Native TTS is output-side only and must not change ASR, realtime preview, paste, OpenClaw text display, message windows, or capsule behavior.

**Tech Stack:** Swift/AppKit/AVFoundation, `Process`, Sherpa ONNX native executable or C API runtime, existing `SherpaMeloTTSVoicePack`, existing TypeWhale Sherpa lexicon, shell/Swift focused tests, `./native/build_and_log.sh`.

## Global Constraints

- Work only inside `$HOME/Pictures/macOSwinOSCoding/TypeSpeaker/.worktrees/tts-native-backend` unless the user explicitly changes the worktree.
- Do not modify preview-window, realtime-preview, ASR, screenshot, paste, OpenClaw message UI, capsule, or hotkey behavior.
- Do not remove the current Python sidecar until the native path has passed installed-app voice QA and rollback criteria.
- Do not add App UI for TTS lexicon maintenance; TypeWhale-owned lexicon remains repository-maintained.
- Do not require users to install Python, pip packages, Homebrew packages, or command-line tools for the productized native path.
- Do not bundle large TTS models into the default public DMG without a separate release decision.
- TTS failure must degrade only voice output. OpenClaw text replies, ASR, screenshots, copying, pasting, and model management must keep working.
- Run concurrent-session safety checks before every write, build, install, stage, or commit: `git branch --show-current`, `git status --short`, and `pgrep -fl "build_and_log|release_local_build|build_native_app|swiftc|xcodebuild" || true`.
- Use TDD for implementation tasks: write or update a focused failing test first, run it to confirm failure, implement, rerun.
- Code changes require `./native/build_and_log.sh` verification unless the user explicitly says not to build.
- Full version builds require a git commit after successful build, installation, signing verification, and necessary QA.
- Temporary isolated app profiles are test scaffolding only. After Sherpa Native TTS is validated and ready to return to the normal product path, builds must use the production app name `TypeWhale Pro`, executable `TypeWhalePro`, bundle id `com.waykingah.typewhale.pro`, and install path `/Applications/TypeWhale Pro.app`; remove or explicitly retire any temporary `TypeWhale Pro TTS Native` profile before declaring the feature finished.

---

## File Structure

- Modify: `native/Sources/Infrastructure/Models/SherpaMeloTTSVoicePack.swift`
  Responsibility: validate the Sherpa model pack and expose native runtime artifact locations without deciding playback policy.

- Create: `native/Sources/Infrastructure/OpenClaw/OpenClawTTSBackend.swift`
  Responsibility: define the backend contract shared by Python sidecar and native Sherpa CLI backend.

- Modify: `native/Sources/Infrastructure/OpenClaw/OpenClawVoicePlayback.swift`
  Responsibility: keep queueing, prewarm, playback, speaking notifications, cancellation, idle release, logging, and backend selection.

- Create: `native/Sources/Infrastructure/OpenClaw/SherpaNativeTTSBackend.swift`
  Responsibility: run the Sherpa native CLI, synthesize WAV files, normalize output volume if needed, expose health errors, and never require Python.

- Modify: `native/Resources/sherpa_typewhale_lexicon.txt` only when product-owner supplied pronunciation fixes are needed.
  Responsibility: TypeWhale-maintained pronunciation overrides.

- Create: `native/Tests/SherpaNativeTTSRuntimeCheck.swift`
  Responsibility: lock runtime-artifact discovery and model-pack validation behavior.

- Create: `native/Tests/SherpaNativeTTSBackendSourceCheck.sh`
  Responsibility: enforce no Python dependency, exact CLI/backend selection boundaries, and protected no-touch areas.

- Create: `native/Tests/SherpaNativeTTSBackendCheck.swift`
  Responsibility: unit-test native backend command construction, lexicon selection, output-path behavior, and error mapping using a fake executable.

- Modify: `native/Tests/OpenClawVoicePlaybackCheck.swift`
  Responsibility: verify existing speech segmentation and request behavior still work with the backend split.

- Modify: `native/Tests/OpenClawVoicePlaybackIntegrationCheck.sh`
  Responsibility: require final OpenClaw replies still call voice playback and that both old sidecar and new native backend remain wired safely.

- Modify: `native/build_native_app.sh`
  Responsibility: package the native Sherpa runtime only after the spike proves the artifact shape. The first implementation may avoid this file by resolving a local native executable outside product builds.

- Modify: `docs/ARCHITECTURE.md`, `docs/开发日志.md`, `docs/产品需求文档.md`, and `native/Sources/Presentation/VersionHistory/VersionHistoryViewController.swift` only when the native path becomes product behavior rather than a local spike.

---

## Task 0: Temporary Isolated App Build Profile

**Status:** Completed.

**Why this exists:** During the Sherpa Native TTS test period, this worktree must be able to build and install a separate app so it does not overwrite `/Applications/TypeWhale Pro.app`, quit the main `TypeWhalePro` process, or reuse the production bundle id while another session is testing preview-window changes.

**Files:**
- Modify: `native/build_native_app.sh`
- Modify: `native/release_local_build.sh`
- Create: `native/Tests/BuildProfileIsolationCheck.sh`
- Modify: `docs/superpowers/plans/2026-07-11-openclaw-sherpa-native-tts.md`

**Interfaces:**
- Consumes optional environment overrides:
  - `TYPEWHALE_APP_DISPLAY_NAME`
  - `TYPEWHALE_APP_EXECUTABLE`
  - `TYPEWHALE_APP_BUNDLE_IDENTIFIER`
  - `TYPESPEAKER_INSTALL_APP_PATH`
- Produces a temporary isolated installed app when overrides are provided:
  - Display name: `TypeWhale Pro TTS Native`
  - Executable: `TypeWhaleProTTSNative`
  - Bundle id: `com.waykingah.typewhale.pro.tts-native`
  - Install path: `/Applications/TypeWhale Pro TTS Native.app`
  - App icon: defaults to the existing `assets/TypeWhaleAppIcon-origami.png` for temporary profiles, unless `TYPEWHALE_APP_ICON_SOURCE` is explicitly set.
  - status bar icon: adds a small amber `T` badge through `AppBrand.isTemporaryTTSNativeProfile`.

**Acceptance:**
- Default build behavior remains exactly `TypeWhale Pro`, `TypeWhalePro`, `com.waykingah.typewhale.pro`, and `/Applications/TypeWhale Pro.app`.
- Explicit override builds can install and open `/Applications/TypeWhale Pro TTS Native.app`.
- The temporary app must be visually distinguishable from the production app in Dock/App Switcher and in the status bar.
- The temporary profile is marked as removable after TTS Native stabilizes.
- Final product acceptance requires returning to the production app identity or documenting an approved permanent developer-profile policy; the temporary TTS Native app name and Bundle ID must not become the shipped default by accident.
- No ASR, preview, capsule, OpenClaw message UI, or TTS runtime code changes are included in this task.

- [x] **Step 1: Write failing build-profile source check**
- [x] **Step 2: Run source check and confirm it fails on hard-coded scripts**
- [x] **Step 3: Implement env overrides in build scripts**
- [x] **Step 4: Run source check and confirm it passes**
- [x] **Step 5: Run an isolated build/install using the temporary profile**
- [x] **Step 6: Update this plan with results**
- [x] **Step 7: Commit**

**Result:**
- Added `native/Tests/BuildProfileIsolationCheck.sh`.
- Added `native/Tests/TemporaryAppIconIdentityCheck.sh`.
- `native/build_native_app.sh` now supports `TYPEWHALE_APP_DISPLAY_NAME`, `TYPEWHALE_APP_EXECUTABLE`, and `TYPEWHALE_APP_BUNDLE_IDENTIFIER` while keeping production defaults unchanged.
- Temporary non-production profiles now use `assets/TypeWhaleAppIcon-origami.png` as the default app icon unless `TYPEWHALE_APP_ICON_SOURCE` is provided.
- `AppBrand.isTemporaryTTSNativeProfile` drives an amber `T` badge in the status bar icon so the menu-bar item is distinguishable from the production app.
- `native/release_local_build.sh` now derives the default install path from the effective display name.
- Verified source checks:
  - `bash native/Tests/BuildProfileIsolationCheck.sh`
  - `bash native/Tests/TemporaryAppIconIdentityCheck.sh`
- Verified installed isolated build:

```bash
TYPEWHALE_APP_DISPLAY_NAME="TypeWhale Pro TTS Native" \
TYPEWHALE_APP_EXECUTABLE="TypeWhaleProTTSNative" \
TYPEWHALE_APP_BUNDLE_IDENTIFIER="com.waykingah.typewhale.pro.tts-native" \
TYPESPEAKER_INSTALL_APP_PATH="/Applications/TypeWhale Pro TTS Native.app" \
TYPEWHALE_FULL_VERSION_EVERY=999 \
./native/build_and_log.sh
```

- Installed app verified:
  - Path: `/Applications/TypeWhale Pro TTS Native.app`
  - Display name: `TypeWhale Pro TTS Native`
  - Executable: `TypeWhaleProTTSNative`
  - Bundle ID: `com.waykingah.typewhale.pro.tts-native`
  - Version: `2.0.6 (675)`
- Confirmed `/Applications/TypeWhale Pro.app` and `/Applications/TypeWhale Pro TTS Native.app` both exist and both processes can run at the same time.
- Temporary removal trigger: when Sherpa Native TTS is stable enough to return to the normal production install path, remove the override-only isolated profile or fold it into an approved developer profile.
- Revert/retirement rule: before closing this native TTS plan, run `BuildProfileIsolationCheck.sh`, verify default build constants still resolve to the production app identity, and either delete the temporary profile support or keep it only as an explicitly documented non-production developer profile.

---

## Task 1: Native Runtime Contract And Validation

**Status:** Completed.

**Files:**
- Modify: `native/Sources/Infrastructure/Models/SherpaMeloTTSVoicePack.swift`
- Create: `native/Tests/SherpaNativeTTSRuntimeCheck.swift`

**Interfaces:**
- Consumes: `SherpaMeloTTSVoicePack.directory`, `modelURL`, `int8ModelURL`, `lexiconURL`, `tokensURL`, `dictDirectory`, `validate(fileManager:requireManifest:)`.
- Produces:
  - `var nativeRuntimeDirectory: URL`
  - `var nativeExecutableURL: URL`
  - `func nativeExecutableURL(fileManager:) throws -> URL`
  - `enum SherpaMeloTTSVoicePack.ValidationError.missingNativeRuntime`

- [x] **Step 1: Write the failing runtime validation test**

Create `native/Tests/SherpaNativeTTSRuntimeCheck.swift`:

```swift
import Foundation

@main
struct SherpaNativeTTSRuntimeCheck {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }

        let pack = SherpaMeloTTSVoicePack(modelsRoot: root)
        try FileManager.default.createDirectory(at: pack.directory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: pack.dictDirectory, withIntermediateDirectories: true)

        try Data("{}".utf8).write(to: pack.manifestURL)
        try Data("model".utf8).write(to: pack.modelURL)
        try Data("lexicon".utf8).write(to: pack.lexiconURL)
        try Data("tokens".utf8).write(to: pack.tokensURL)
        try Data("dict".utf8).write(to: pack.dictDirectory.appendingPathComponent("README.md"))
        try Data("fst".utf8).write(to: pack.directory.appendingPathComponent("number.fst"))
        try Data("fst".utf8).write(to: pack.directory.appendingPathComponent("phone.fst"))
        try Data("fst".utf8).write(to: pack.directory.appendingPathComponent("date.fst"))

        precondition(pack.nativeRuntimeDirectory.path.hasSuffix("sherpa-vits-melo-tts-zh_en/runtime/native"))
        precondition(pack.nativeExecutableURL.lastPathComponent == "sherpa-onnx-offline-tts")

        do {
            _ = try pack.nativeExecutableURL()
            preconditionFailure("missing native executable must fail validation")
        } catch SherpaMeloTTSVoicePack.ValidationError.missingNativeRuntime { }

        try FileManager.default.createDirectory(at: pack.nativeRuntimeDirectory, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: pack.nativeExecutableURL.path, contents: Data("#!/bin/sh\nexit 0\n".utf8))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: pack.nativeExecutableURL.path)

        let executable = try pack.nativeExecutableURL()
        precondition(executable.path == pack.nativeExecutableURL.path)
        try pack.validate(requireManifest: true)

        print("SherpaNativeTTSRuntimeCheck passed")
    }
}
```

- [x] **Step 2: Run test to verify it fails**

Run:

```bash
swiftc -o /tmp/typewhale-sherpa-native-runtime-check \
  native/Sources/Infrastructure/Models/SherpaMeloTTSVoicePack.swift \
  native/Tests/SherpaNativeTTSRuntimeCheck.swift && \
  /tmp/typewhale-sherpa-native-runtime-check
```

Expected: FAIL because `nativeRuntimeDirectory`, `nativeExecutableURL`, `nativeExecutableURL()`, or `missingNativeRuntime` is not defined.

- [x] **Step 3: Implement minimal runtime contract**

Modify `native/Sources/Infrastructure/Models/SherpaMeloTTSVoicePack.swift`:

```swift
struct SherpaMeloTTSVoicePack {
    enum ValidationError: Error, Equatable {
        case missingManifest
        case missingModelFile(String)
        case missingRuntime
        case missingNativeRuntime
    }

    var nativeRuntimeDirectory: URL {
        directory
            .appendingPathComponent("runtime", isDirectory: true)
            .appendingPathComponent("native", isDirectory: true)
    }

    var nativeExecutableURL: URL {
        nativeRuntimeDirectory.appendingPathComponent("sherpa-onnx-offline-tts")
    }

    func nativeExecutableURL(fileManager: FileManager = .default) throws -> URL {
        if fileManager.isExecutableFile(atPath: nativeExecutableURL.path) {
            return nativeExecutableURL
        }
        if let explicit = ProcessInfo.processInfo.environment["TYPEWHALE_SHERPA_NATIVE_TTS"],
           fileManager.isExecutableFile(atPath: explicit) {
            return URL(fileURLWithPath: explicit)
        }
        let candidates = [
            "/usr/local/bin/sherpa-onnx-offline-tts",
            "/opt/homebrew/bin/sherpa-onnx-offline-tts"
        ]
        for path in candidates where fileManager.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        throw ValidationError.missingNativeRuntime
    }
}
```

Keep existing `pythonURL(fileManager:)` unchanged.

- [x] **Step 4: Run runtime and existing pack tests**

Run:

```bash
swiftc -o /tmp/typewhale-sherpa-native-runtime-check \
  native/Sources/Infrastructure/Models/SherpaMeloTTSVoicePack.swift \
  native/Tests/SherpaNativeTTSRuntimeCheck.swift && \
  /tmp/typewhale-sherpa-native-runtime-check

swiftc -o /tmp/typewhale-sherpa-pack-check \
  native/Sources/Infrastructure/Models/SherpaMeloTTSVoicePack.swift \
  native/Tests/SherpaMeloTTSVoicePackCheck.swift && \
  /tmp/typewhale-sherpa-pack-check
```

Expected: both pass.

- [x] **Step 5: Commit**

```bash
git add native/Sources/Infrastructure/Models/SherpaMeloTTSVoicePack.swift native/Tests/SherpaNativeTTSRuntimeCheck.swift
git commit -m "feat: define Sherpa native TTS runtime contract"
```

**Result so far:**
- Added `native/Tests/SherpaNativeTTSRuntimeCheck.swift`.
- Confirmed the new test failed before implementation because `SherpaMeloTTSVoicePack` had no `nativeRuntimeDirectory`, `nativeExecutableURL`, or `missingNativeRuntime`.
- `SherpaMeloTTSVoicePack` now exposes `runtime/native/sherpa-onnx-offline-tts` as the preferred native executable path.
- Native runtime lookup now falls back to `TYPEWHALE_SHERPA_NATIVE_TTS`, then `/usr/local/bin/sherpa-onnx-offline-tts`, then `/opt/homebrew/bin/sherpa-onnx-offline-tts`.
- Python sidecar lookup remains unchanged.
- Verified:
  - `swiftc -o /tmp/typewhale-sherpa-native-runtime-check native/Sources/Infrastructure/Models/SherpaMeloTTSVoicePack.swift native/Tests/SherpaNativeTTSRuntimeCheck.swift && /tmp/typewhale-sherpa-native-runtime-check`
  - `swiftc -o /tmp/typewhale-sherpa-pack-check native/Sources/Infrastructure/Models/SherpaMeloTTSVoicePack.swift native/Tests/SherpaMeloTTSVoicePackCheck.swift && /tmp/typewhale-sherpa-pack-check`
  - Isolated installed build: `TypeWhale Pro TTS Native` at `/Applications/TypeWhale Pro TTS Native.app`, bundle id `com.waykingah.typewhale.pro.tts-native`, version `2.0.6 (676)`.

---

## Task 2: Local Native CLI Spike

**Status:** Completed.

**Files:**
- Create: `tools/openclaw_sherpa_native_tts_probe.sh`
- Create: `native/Tests/SherpaNativeTTSProbeCheck.sh`

**Interfaces:**
- Consumes:
  - `TYPEWHALE_SHERPA_NATIVE_TTS` optional executable override.
  - `TYPEWHALE_SHERPA_TTS_PACK` optional model-pack override.
  - Default model pack at `$HOME/Library/Application Support/TypeWhale Pro/Models/tts/sherpa-vits-melo-tts-zh_en`.
- Produces:
  - A local probe WAV at `/tmp/typewhale-sherpa-native-probe.wav`.
  - A printed command and elapsed-time summary for human listening and resource comparison.

- [x] **Step 1: Write failing source check**

Create `native/Tests/SherpaNativeTTSProbeCheck.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PROBE="$ROOT/tools/openclaw_sherpa_native_tts_probe.sh"

test -x "$PROBE"
grep -q 'TYPEWHALE_SHERPA_NATIVE_TTS' "$PROBE"
grep -q 'TYPEWHALE_SHERPA_TTS_PACK' "$PROBE"
grep -q 'sherpa-onnx-offline-tts' "$PROBE"
grep -q 'sherpa_typewhale_lexicon.txt' "$PROBE"
grep -q 'lexicon.typewhale.txt' "$PROBE"
grep -q 'model.int8.onnx' "$PROBE"
grep -q 'model.onnx' "$PROBE"
! grep -q 'python' "$PROBE"
! grep -q 'pip' "$PROBE"

echo "SherpaNativeTTSProbeCheck passed"
```

- [x] **Step 2: Run test to verify it fails**

Run:

```bash
bash native/Tests/SherpaNativeTTSProbeCheck.sh
```

Expected: FAIL because `tools/openclaw_sherpa_native_tts_probe.sh` does not exist.

- [x] **Step 3: Create the local probe script**

Create `tools/openclaw_sherpa_native_tts_probe.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PACK="${TYPEWHALE_SHERPA_TTS_PACK:-$HOME/Library/Application Support/TypeWhale Pro/Models/tts/sherpa-vits-melo-tts-zh_en}"
TEXT="${1:-OpenClaw 正在测试 GitHub、MiniMax、OpenAI、API、Kubernetes 和 TypeScript。}"
OUTPUT="${2:-/tmp/typewhale-sherpa-native-probe.wav}"

if [[ -n "${TYPEWHALE_SHERPA_NATIVE_TTS:-}" ]]; then
  EXE="$TYPEWHALE_SHERPA_NATIVE_TTS"
elif [[ -x "$PACK/runtime/native/sherpa-onnx-offline-tts" ]]; then
  EXE="$PACK/runtime/native/sherpa-onnx-offline-tts"
elif command -v sherpa-onnx-offline-tts >/dev/null 2>&1; then
  EXE="$(command -v sherpa-onnx-offline-tts)"
else
  echo "Missing native sherpa-onnx-offline-tts. Set TYPEWHALE_SHERPA_NATIVE_TTS to an executable." >&2
  exit 2
fi

MODEL="$PACK/model.onnx"
if [[ ! -f "$MODEL" && -f "$PACK/model.int8.onnx" ]]; then
  MODEL="$PACK/model.int8.onnx"
fi
for required in "$MODEL" "$PACK/lexicon.txt" "$PACK/tokens.txt" "$PACK/dict" "$PACK/number.fst" "$PACK/phone.fst" "$PACK/date.fst"; do
  if [[ ! -e "$required" ]]; then
    echo "Missing Sherpa TTS resource: $required" >&2
    exit 3
  fi
done

LEXICON="$PACK/lexicon.txt"
CUSTOM="$ROOT/native/Resources/sherpa_typewhale_lexicon.txt"
if [[ -f "$CUSTOM" ]]; then
  mkdir -p "$PACK/.typewhale"
  LEXICON="$PACK/.typewhale/lexicon.typewhale.txt"
  {
    sed '/^[[:space:]]*$/d' "$CUSTOM"
    cat "$PACK/lexicon.txt"
  } > "$LEXICON"
fi

START="$(date +%s)"
"$EXE" \
  --vits-model "$MODEL" \
  --vits-lexicon "$LEXICON" \
  --vits-tokens "$PACK/tokens.txt" \
  --vits-dict-dir "$PACK/dict" \
  --output-filename "$OUTPUT" \
  "$TEXT"
END="$(date +%s)"

test -s "$OUTPUT"
echo "wrote=$OUTPUT"
echo "seconds=$((END - START))"
echo "exe=$EXE"
```

Then make it executable:

```bash
chmod +x tools/openclaw_sherpa_native_tts_probe.sh
```

- [x] **Step 4: Run source check**

Run:

```bash
bash native/Tests/SherpaNativeTTSProbeCheck.sh
```

Expected: PASS.

- [x] **Step 5: Run real local probe when executable exists**

Run:

```bash
tools/openclaw_sherpa_native_tts_probe.sh \
  "昨天我用 Docker、Kubernetes、GitHub Actions、FastAPI、PostgreSQL、Redis 和 OpenAI API 部署了新服务。" \
  /tmp/typewhale-sherpa-native-probe.wav
afplay /tmp/typewhale-sherpa-native-probe.wav
```

Expected:
- If native executable exists: a WAV is generated and played.
- If native executable is missing: command exits with code `2` and a clear message asking for `TYPEWHALE_SHERPA_NATIVE_TTS`. This is acceptable for the spike until runtime artifact acquisition is implemented.

- [x] **Step 6: Commit**

```bash
git add tools/openclaw_sherpa_native_tts_probe.sh native/Tests/SherpaNativeTTSProbeCheck.sh
git commit -m "test: add Sherpa native TTS probe"
```

**Result so far:**
- Added `native/Tests/SherpaNativeTTSProbeCheck.sh`.
- Confirmed the source check failed before implementation because `tools/openclaw_sherpa_native_tts_probe.sh` did not exist.
- Added `tools/openclaw_sherpa_native_tts_probe.sh` as a local native CLI probe.
- Probe supports `TYPEWHALE_SHERPA_NATIVE_TTS`, `TYPEWHALE_SHERPA_TTS_PACK`, TypeWhale lexicon merge, model/tokens/dict/FST checks, and wav output timing.
- Verified source check:
  - `bash native/Tests/SherpaNativeTTSProbeCheck.sh`
- Real local probe result:
  - Current model pack resources exist at `$HOME/Library/Application Support/TypeWhale Pro/Models/tts/sherpa-vits-melo-tts-zh_en`.
  - No native `sherpa-onnx-offline-tts` executable is currently available in the pack runtime or PATH.
  - Probe exits with code `2` and message: `Missing native sherpa-onnx-offline-tts. Set TYPEWHALE_SHERPA_NATIVE_TTS to an executable.`
  - This is accepted for Task 2; acquiring or packaging the native executable remains a later task.
  - Isolated installed build: `TypeWhale Pro TTS Native` at `/Applications/TypeWhale Pro TTS Native.app`, bundle id `com.waykingah.typewhale.pro.tts-native`, version `2.0.6 (677)`.

---

## Task 3: Backend Interface Without Behavior Change

**Status:** Completed.

**Files:**
- Create: `native/Sources/Infrastructure/OpenClaw/OpenClawTTSBackend.swift`
- Modify: `native/Sources/Infrastructure/OpenClaw/OpenClawVoicePlayback.swift`
- Create: `native/Tests/OpenClawTTSBackendBoundaryCheck.sh`

**Interfaces:**
- Consumes: `OpenClawVoiceSynthesisRequest`, `OpenClawVoicePlaybackError`, `MeloTTSVoiceBackend`.
- Produces:
  - `protocol OpenClawTTSBackend: AnyObject`
  - `var isRunning: Bool { get }`
  - `func start(timeoutSeconds: TimeInterval) throws`
  - `func synthesize(_ request: OpenClawVoiceSynthesisRequest, timeoutSeconds: TimeInterval) throws`
  - `func stop()`

- [x] **Step 1: Write failing boundary check**

Create `native/Tests/OpenClawTTSBackendBoundaryCheck.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BACKEND="$ROOT/native/Sources/Infrastructure/OpenClaw/OpenClawTTSBackend.swift"
PLAYER="$ROOT/native/Sources/Infrastructure/OpenClaw/OpenClawVoicePlayback.swift"

test -f "$BACKEND"
grep -q 'protocol OpenClawTTSBackend: AnyObject' "$BACKEND"
grep -q 'var isRunning: Bool' "$BACKEND"
grep -q 'func start(timeoutSeconds: TimeInterval) throws' "$BACKEND"
grep -q 'func synthesize(_ request: OpenClawVoiceSynthesisRequest, timeoutSeconds: TimeInterval) throws' "$BACKEND"
grep -q 'func stop()' "$BACKEND"
grep -q 'final class MeloTTSVoiceBackend: OpenClawTTSBackend' "$PLAYER"
grep -q 'private var activeSidecar: OpenClawTTSBackend?' "$PLAYER"
grep -q 'activeSidecarEngine == settings.engine' "$PLAYER"
grep -q 'activeSidecarPackDirectory == probeRequest.packDirectory' "$PLAYER"
! rg -n 'OpenClawReplyPresenter|RecordingCapsule|RealtimePreview|SpeechInputCoordinator' "$BACKEND" "$PLAYER"

echo "OpenClawTTSBackendBoundaryCheck passed"
```

- [x] **Step 2: Run test to verify it fails**

Run:

```bash
bash native/Tests/OpenClawTTSBackendBoundaryCheck.sh
```

Expected: FAIL because `OpenClawTTSBackend.swift` does not exist.

- [x] **Step 3: Add backend protocol**

Create `native/Sources/Infrastructure/OpenClaw/OpenClawTTSBackend.swift`:

```swift
import Foundation

protocol OpenClawTTSBackend: AnyObject {
    var isRunning: Bool { get }
    func start(timeoutSeconds: TimeInterval) throws
    func synthesize(_ request: OpenClawVoiceSynthesisRequest, timeoutSeconds: TimeInterval) throws
    func stop()
}
```

Modify `native/Sources/Infrastructure/OpenClaw/OpenClawVoicePlayback.swift`:

```swift
private var activeSidecar: OpenClawTTSBackend?
```

Change:

```swift
final class MeloTTSVoiceBackend {
```

to:

```swift
final class MeloTTSVoiceBackend: OpenClawTTSBackend {
```

Keep all existing method bodies unchanged.

- [x] **Step 4: Run backend boundary and existing playback checks**

Run:

```bash
bash native/Tests/OpenClawTTSBackendBoundaryCheck.sh

bash native/Tests/OpenClawVoicePlaybackIntegrationCheck.sh

swiftc -o /tmp/typewhale-openclaw-voice-settings-check \
  native/Sources/Infrastructure/Settings/OpenClawVoiceSettings.swift \
  native/Tests/OpenClawVoiceSettingsCheck.swift && \
  /tmp/typewhale-openclaw-voice-settings-check
```

Expected: all pass.

- [x] **Step 5: Commit**

```bash
git add native/Sources/Infrastructure/OpenClaw/OpenClawTTSBackend.swift \
  native/Sources/Infrastructure/OpenClaw/OpenClawVoicePlayback.swift \
  native/Tests/OpenClawTTSBackendBoundaryCheck.sh
git commit -m "refactor: isolate OpenClaw TTS backend contract"
```

**Result so far:**
- Added `native/Tests/OpenClawTTSBackendBoundaryCheck.sh`.
- Confirmed the boundary check failed before implementation because `native/Sources/Infrastructure/OpenClaw/OpenClawTTSBackend.swift` did not exist.
- Added `native/Sources/Infrastructure/OpenClaw/OpenClawTTSBackend.swift`.
- `MeloTTSVoiceBackend` now conforms to `OpenClawTTSBackend`.
- `OpenClawVoicePlayer.activeSidecar` now stores `OpenClawTTSBackend?` while preserving existing engine and pack-directory reuse checks.
- Verified:
  - `bash native/Tests/OpenClawTTSBackendBoundaryCheck.sh`
  - `bash native/Tests/OpenClawVoicePlaybackIntegrationCheck.sh`
  - `swiftc -o /tmp/typewhale-openclaw-voice-settings-check native/Sources/Infrastructure/Settings/OpenClawVoiceSettings.swift native/Tests/OpenClawVoiceSettingsCheck.swift && /tmp/typewhale-openclaw-voice-settings-check`
- Isolated installed build:
  - Path: `/Applications/TypeWhale Pro TTS Native.app`
  - Display name: `TypeWhale Pro TTS Native`
  - Bundle ID: `com.waykingah.typewhale.pro.tts-native`
  - Version: `2.0.6 (680)`

---

## Task 4: Native CLI Backend With Fake Executable Test

**Status:** Completed.

**Files:**
- Create: `native/Sources/Infrastructure/OpenClaw/SherpaNativeTTSBackend.swift`
- Create: `native/Tests/SherpaNativeTTSBackendCheck.swift`
- Modify: `native/Tests/SherpaNativeTTSBackendSourceCheck.sh`

**Interfaces:**
- Consumes:
  - `OpenClawTTSBackend`
  - `OpenClawVoiceSynthesisRequest`
  - `SherpaMeloTTSVoicePack.nativeExecutableURL(fileManager:)`
  - `SherpaMeloTTSVoicePack.validate(fileManager:requireManifest:)`
- Produces:
  - `final class SherpaNativeTTSBackend: OpenClawTTSBackend`
  - `init(executableURL: URL, packDirectory: URL, fileManager: FileManager = .default)`
  - `static func arguments(for request: OpenClawVoiceSynthesisRequest, executableURL: URL, packDirectory: URL) throws -> [String]`

- [x] **Step 1: Write failing source check**

Create `native/Tests/SherpaNativeTTSBackendSourceCheck.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BACKEND="$ROOT/native/Sources/Infrastructure/OpenClaw/SherpaNativeTTSBackend.swift"

test -f "$BACKEND"
grep -q 'final class SherpaNativeTTSBackend: OpenClawTTSBackend' "$BACKEND"
grep -q 'Process()' "$BACKEND"
grep -q 'sherpa-onnx-offline-tts' "$ROOT/native/Sources/Infrastructure/Models/SherpaMeloTTSVoicePack.swift"
grep -q 'TYPEWHALE_SHERPA_NATIVE_TTS' "$ROOT/native/Sources/Infrastructure/Models/SherpaMeloTTSVoicePack.swift"
grep -q 'vits-model' "$BACKEND"
grep -q 'vits-lexicon' "$BACKEND"
grep -q 'vits-tokens' "$BACKEND"
grep -q 'vits-dict-dir' "$BACKEND"
grep -q 'output-filename' "$BACKEND"
! grep -q 'python' "$BACKEND"
! grep -q 'MeloTTSRunner' "$BACKEND"
! grep -q 'melo.api' "$BACKEND"

echo "SherpaNativeTTSBackendSourceCheck passed"
```

- [x] **Step 2: Write failing fake executable behavior test**

Create `native/Tests/SherpaNativeTTSBackendCheck.swift`:

```swift
import Foundation

@main
struct SherpaNativeTTSBackendCheck {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }

        let modelsRoot = root.appendingPathComponent("Models", isDirectory: true)
        let pack = SherpaMeloTTSVoicePack(modelsRoot: modelsRoot)
        try FileManager.default.createDirectory(at: pack.directory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: pack.dictDirectory, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: pack.manifestURL)
        try Data("model".utf8).write(to: pack.modelURL)
        try Data("lexicon".utf8).write(to: pack.lexiconURL)
        try Data("tokens".utf8).write(to: pack.tokensURL)
        try Data("dict".utf8).write(to: pack.dictDirectory.appendingPathComponent("README.md"))
        try Data("fst".utf8).write(to: pack.directory.appendingPathComponent("number.fst"))
        try Data("fst".utf8).write(to: pack.directory.appendingPathComponent("phone.fst"))
        try Data("fst".utf8).write(to: pack.directory.appendingPathComponent("date.fst"))

        let fakeExecutable = root.appendingPathComponent("fake-sherpa-onnx-offline-tts")
        let marker = root.appendingPathComponent("args.txt")
        let script = """
        #!/usr/bin/env bash
        printf '%s\\n' "$@" > "\(marker.path)"
        while [[ "$#" -gt 0 ]]; do
          if [[ "$1" == "--output-filename" ]]; then
            shift
            printf 'RIFFfakeWAVE' > "$1"
            exit 0
          fi
          shift
        done
        exit 7
        """
        try Data(script.utf8).write(to: fakeExecutable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeExecutable.path)

        let request = OpenClawVoiceSynthesisRequest(
            text: "测试 GitHub 和 MiniMax。",
            settings: OpenClawVoiceSettings(
                enabled: true,
                volume: 0.8,
                speechRate: 1.25,
                engine: .sherpaMelo44k,
                playbackPolicy: .finalReplyOnly,
                interruptPolicy: .stopPreviousAndPlayLatest
            ),
            workerScriptURL: URL(fileURLWithPath: "/tmp/unused-openclaw-worker.py"),
            modelsRoot: modelsRoot,
            outputURL: root.appendingPathComponent("out.wav")
        )

        let backend = SherpaNativeTTSBackend(executableURL: fakeExecutable, packDirectory: pack.directory)
        try backend.start(timeoutSeconds: 1)
        precondition(backend.isRunning)
        try backend.synthesize(request, timeoutSeconds: 5)
        precondition(FileManager.default.fileExists(atPath: request.outputURL.path))

        let args = try String(contentsOf: marker)
        precondition(args.contains("--vits-model"))
        precondition(args.contains(pack.modelURL.path))
        precondition(args.contains("--vits-lexicon"))
        precondition(args.contains(pack.lexiconURL.path))
        precondition(args.contains("--vits-tokens"))
        precondition(args.contains(pack.tokensURL.path))
        precondition(args.contains("--vits-dict-dir"))
        precondition(args.contains(pack.dictDirectory.path))
        precondition(args.contains("--output-filename"))
        precondition(args.contains(request.outputURL.path))

        backend.stop()
        precondition(!backend.isRunning)

        print("SherpaNativeTTSBackendCheck passed")
    }
}
```

- [x] **Step 3: Run tests to verify they fail**

Run:

```bash
bash native/Tests/SherpaNativeTTSBackendSourceCheck.sh

swiftc -o /tmp/typewhale-sherpa-native-backend-check \
  native/Sources/Infrastructure/Settings/OpenClawVoiceSettings.swift \
  native/Sources/Infrastructure/Models/SherpaMeloTTSVoicePack.swift \
  native/Sources/Infrastructure/OpenClaw/OpenClawTTSBackend.swift \
  native/Sources/Infrastructure/OpenClaw/OpenClawVoicePlayback.swift \
  native/Sources/Infrastructure/OpenClaw/SherpaNativeTTSBackend.swift \
  native/Tests/SherpaNativeTTSBackendCheck.swift && \
  /tmp/typewhale-sherpa-native-backend-check
```

Expected: FAIL because `SherpaNativeTTSBackend.swift` does not exist or does not implement required behavior.

- [x] **Step 4: Implement minimal native backend**

Create `native/Sources/Infrastructure/OpenClaw/SherpaNativeTTSBackend.swift`:

```swift
import Foundation

final class SherpaNativeTTSBackend: OpenClawTTSBackend {
    private let executableURL: URL
    private let packDirectory: URL
    private let fileManager: FileManager
    private var started = false

    var isRunning: Bool { started }

    init(executableURL: URL, packDirectory: URL, fileManager: FileManager = .default) {
        self.executableURL = executableURL
        self.packDirectory = packDirectory
        self.fileManager = fileManager
    }

    func start(timeoutSeconds: TimeInterval = 180) throws {
        guard fileManager.isExecutableFile(atPath: executableURL.path) else {
            throw OpenClawVoicePlaybackError.commandFailed("Missing native sherpa-onnx-offline-tts: \(executableURL.path)")
        }
        started = true
    }

    func synthesize(_ request: OpenClawVoiceSynthesisRequest, timeoutSeconds: TimeInterval = 180) throws {
        let arguments = try Self.arguments(for: request, executableURL: executableURL, packDirectory: packDirectory)
        let process = Process()
        let stderr = Pipe()
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = Pipe()
        process.standardError = stderr
        process.environment = OpenClawCommandClient.processEnvironment()

        do {
            try process.run()
        } catch {
            throw OpenClawVoicePlaybackError.commandFailed(error.localizedDescription)
        }

        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            process.terminate()
        }
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let err = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw OpenClawVoicePlaybackError.commandFailed(err)
        }
        guard fileManager.fileExists(atPath: request.outputURL.path) else {
            throw OpenClawVoicePlaybackError.commandFailed("Sherpa native TTS did not create output WAV")
        }
    }

    func stop() {
        started = false
    }

    static func arguments(
        for request: OpenClawVoiceSynthesisRequest,
        executableURL: URL,
        packDirectory: URL
    ) throws -> [String] {
        let modelURL = modelURL(in: packDirectory)
        let lexiconURL = typewhaleLexiconURL(in: packDirectory) ?? packDirectory.appendingPathComponent("lexicon.txt")
        return [
            "--vits-model", modelURL.path,
            "--vits-lexicon", lexiconURL.path,
            "--vits-tokens", packDirectory.appendingPathComponent("tokens.txt").path,
            "--vits-dict-dir", packDirectory.appendingPathComponent("dict", isDirectory: true).path,
            "--output-filename", request.outputURL.path,
            request.speechText
        ]
    }

    private static func modelURL(in packDirectory: URL) -> URL {
        let model = packDirectory.appendingPathComponent("model.onnx")
        if FileManager.default.fileExists(atPath: model.path) {
            return model
        }
        return packDirectory.appendingPathComponent("model.int8.onnx")
    }

    private static func typewhaleLexiconURL(in packDirectory: URL) -> URL? {
        let merged = packDirectory
            .appendingPathComponent(".typewhale", isDirectory: true)
            .appendingPathComponent("lexicon.typewhale.txt")
        return FileManager.default.fileExists(atPath: merged.path) ? merged : nil
    }
}
```

- [x] **Step 5: Run tests**

Run:

```bash
bash native/Tests/SherpaNativeTTSBackendSourceCheck.sh

swiftc -o /tmp/typewhale-sherpa-native-backend-check \
  native/Sources/Infrastructure/Settings/OpenClawVoiceSettings.swift \
  native/Sources/Infrastructure/Models/SherpaMeloTTSVoicePack.swift \
  native/Sources/Infrastructure/OpenClaw/OpenClawTTSBackend.swift \
  native/Sources/Infrastructure/OpenClaw/OpenClawVoicePlayback.swift \
  native/Sources/Infrastructure/OpenClaw/SherpaNativeTTSBackend.swift \
  native/Tests/SherpaNativeTTSBackendCheck.swift && \
  /tmp/typewhale-sherpa-native-backend-check
```

Expected: PASS.

- [x] **Step 6: Commit**

```bash
git add native/Sources/Infrastructure/OpenClaw/SherpaNativeTTSBackend.swift \
  native/Tests/SherpaNativeTTSBackendSourceCheck.sh \
  native/Tests/SherpaNativeTTSBackendCheck.swift
git commit -m "feat: add Sherpa native TTS backend"
```

**Result so far:**
- Added `native/Tests/SherpaNativeTTSBackendSourceCheck.sh`.
- Added `native/Tests/SherpaNativeTTSBackendCheck.swift`.
- Confirmed both checks failed before implementation because `SherpaNativeTTSBackend.swift` did not exist.
- Added `native/Sources/Infrastructure/OpenClaw/SherpaNativeTTSBackend.swift`.
- The backend runs a native executable with `--vits-model`, `--vits-lexicon`, `--vits-tokens`, `--vits-dict-dir`, and `--output-filename`, then verifies the output wav exists.
- The backend does not reference Python, `MeloTTSRunner`, or `melo.api`.
- Verified:
  - `bash native/Tests/SherpaNativeTTSBackendSourceCheck.sh`
  - `swiftc -o /tmp/typewhale-sherpa-native-backend-check native/Sources/Core/AppBrand.swift native/Sources/Infrastructure/Diagnostics/LaunchDiagnostics.swift native/Sources/Infrastructure/Settings/OpenClawVoiceSettings.swift native/Sources/Infrastructure/Models/MeloTTSVoicePack.swift native/Sources/Infrastructure/Models/SherpaMeloTTSVoicePack.swift native/Sources/Infrastructure/OpenClaw/OpenClawSettings.swift native/Sources/Infrastructure/OpenClaw/OpenClawClient.swift native/Sources/Infrastructure/OpenClaw/OpenClawTTSBackend.swift native/Sources/Infrastructure/OpenClaw/OpenClawVoicePlayback.swift native/Sources/Infrastructure/OpenClaw/SherpaNativeTTSBackend.swift native/Tests/SherpaNativeTTSBackendCheck.swift && /tmp/typewhale-sherpa-native-backend-check`
  - `bash native/Tests/OpenClawTTSBackendBoundaryCheck.sh`
- Isolated installed build:
  - Path: `/Applications/TypeWhale Pro TTS Native.app`
  - Display name: `TypeWhale Pro TTS Native`
  - Bundle ID: `com.waykingah.typewhale.pro.tts-native`
  - Version: `2.0.6 (681)`

---

## Task 5: Backend Selection And Rollback Routing

**Status:** Completed.

**Files:**
- Modify: `native/Sources/Infrastructure/Settings/OpenClawVoiceSettings.swift`
- Modify: `native/Sources/Infrastructure/OpenClaw/OpenClawVoicePlayback.swift`
- Modify: `native/Tests/OpenClawVoiceSettingsCheck.swift`
- Modify: `native/Tests/OpenClawVoicePlaybackIntegrationCheck.sh`

**Interfaces:**
- Consumes: `SherpaNativeTTSBackend`, `MeloTTSVoiceBackend`, `OpenClawVoiceEngine.sherpaMelo44k`.
- Produces:
  - `OpenClawVoiceEngine.sherpaMeloNative`
  - `OpenClawVoiceEngine.productized(_:)` migration that keeps user-visible default stable unless explicitly changed by this task.
  - `OpenClawVoicePlayer.ensureBackend(settings:) throws -> OpenClawTTSBackend`

- [x] **Step 1: Write failing settings expectation**

Modify `native/Tests/OpenClawVoiceSettingsCheck.swift` to assert both productized engines are known while the UI can still expose only the approved default:

```swift
precondition(OpenClawVoiceEngine.sherpaMelo44k.rawValue == "sherpa_melo_44k")
precondition(OpenClawVoiceEngine.sherpaMeloNative.rawValue == "sherpa_melo_native")
precondition(OpenClawVoiceEngine.productized(.meloTTS) == .sherpaMelo44k)
precondition(OpenClawVoiceEngine.productized(.sherpaMeloNative) == .sherpaMeloNative)
```

- [x] **Step 2: Run settings test to verify it fails**

Run:

```bash
swiftc -o /tmp/typewhale-openclaw-voice-settings-check \
  native/Sources/Infrastructure/Settings/OpenClawVoiceSettings.swift \
  native/Tests/OpenClawVoiceSettingsCheck.swift && \
  /tmp/typewhale-openclaw-voice-settings-check
```

Expected: FAIL because `.sherpaMeloNative` does not exist.

- [x] **Step 3: Add engine case without switching default**

Modify `native/Sources/Infrastructure/Settings/OpenClawVoiceSettings.swift`:

```swift
enum OpenClawVoiceEngine: String, CaseIterable {
    case meloTTS = "melotts"
    case sherpaMelo44k = "sherpa_melo_44k"
    case sherpaMeloNative = "sherpa_melo_native"

    static var allCases: [OpenClawVoiceEngine] {
        [.sherpaMelo44k]
    }

    static func productized(_ engine: OpenClawVoiceEngine?) -> OpenClawVoiceEngine {
        guard let engine else { return .sherpaMelo44k }
        switch engine {
        case .sherpaMelo44k: return .sherpaMelo44k
        case .sherpaMeloNative: return .sherpaMeloNative
        case .meloTTS: return .sherpaMelo44k
        }
    }

    var displayName: String {
        switch self {
        case .meloTTS: return "MeloTTS 自然中文"
        case .sherpaMelo44k: return "Sherpa 极速低内存"
        case .sherpaMeloNative: return "Sherpa Native 无 Python"
        }
    }

    var relativeDirectory: String {
        switch self {
        case .meloTTS: return "tts/melotts-zh"
        case .sherpaMelo44k, .sherpaMeloNative: return "tts/sherpa-vits-melo-tts-zh_en"
        }
    }
}
```

- [x] **Step 4: Route native engine in player**

Modify `native/Sources/Infrastructure/OpenClaw/OpenClawVoicePlayback.swift`:

```swift
private func ensureSidecar(settings: OpenClawVoiceSettings) throws -> OpenClawTTSBackend {
    guard let workerURL = OpenClawVoiceRuntime.workerScriptURL() else {
        throw OpenClawVoicePlaybackError.workerMissing
    }
    let probeRequest = OpenClawVoiceSynthesisRequest(
        text: "warmup",
        settings: settings,
        workerScriptURL: workerURL,
        modelsRoot: OpenClawVoiceRuntime.defaultModelsRoot,
        outputURL: OpenClawVoiceRuntime.defaultOutputDirectory.appendingPathComponent("warmup.wav")
    )

    if let activeSidecar,
       activeSidecarEngine == settings.engine,
       activeSidecarPackDirectory == probeRequest.packDirectory,
       activeSidecar.isRunning {
        return activeSidecar
    }

    activeSidecar?.stop()

    let next: OpenClawTTSBackend
    switch settings.engine {
    case .meloTTS:
        let pack = MeloTTSVoicePack(modelsRoot: OpenClawVoiceRuntime.defaultModelsRoot)
        do { try pack.validate() } catch { throw OpenClawVoicePlaybackError.modelMissing(pack.directory.path) }
        next = MeloTTSVoiceBackend(
            pythonURL: pack.runtimePythonURL,
            workerScriptURL: workerURL,
            engine: settings.engine,
            packDirectory: probeRequest.packDirectory
        )
    case .sherpaMelo44k:
        let pack = SherpaMeloTTSVoicePack(modelsRoot: OpenClawVoiceRuntime.defaultModelsRoot)
        do {
            try pack.validate(requireManifest: false)
            let pythonURL = try pack.pythonURL()
            next = MeloTTSVoiceBackend(
                pythonURL: pythonURL,
                workerScriptURL: workerURL,
                engine: settings.engine,
                packDirectory: probeRequest.packDirectory
            )
        } catch SherpaMeloTTSVoicePack.ValidationError.missingRuntime {
            throw OpenClawVoicePlaybackError.pythonMissing
        } catch {
            throw OpenClawVoicePlaybackError.modelMissing(pack.directory.path)
        }
    case .sherpaMeloNative:
        let pack = SherpaMeloTTSVoicePack(modelsRoot: OpenClawVoiceRuntime.defaultModelsRoot)
        do {
            try pack.validate(requireManifest: false)
            let executableURL = try pack.nativeExecutableURL()
            next = SherpaNativeTTSBackend(
                executableURL: executableURL,
                packDirectory: probeRequest.packDirectory
            )
        } catch SherpaMeloTTSVoicePack.ValidationError.missingNativeRuntime {
            throw OpenClawVoicePlaybackError.commandFailed("找不到 Sherpa Native TTS 运行时")
        } catch {
            throw OpenClawVoicePlaybackError.modelMissing(pack.directory.path)
        }
    }

    try next.start()
    activeSidecar = next
    activeSidecarEngine = settings.engine
    activeSidecarPackDirectory = probeRequest.packDirectory
    scheduleSidecarIdleShutdown()
    return next
}
```

If the current method name remains `ensureSidecar`, keep it for a small diff. Rename to `ensureBackend` only if all references are updated in the same task.

- [x] **Step 5: Update integration source check**

Modify `native/Tests/OpenClawVoicePlaybackIntegrationCheck.sh`:

```bash
grep -q 'SherpaNativeTTSBackend' "$ROOT/native/Sources/Infrastructure/OpenClaw/OpenClawVoicePlayback.swift"
grep -q 'case \\.sherpaMeloNative' "$ROOT/native/Sources/Infrastructure/OpenClaw/OpenClawVoicePlayback.swift"
grep -q 'nativeExecutableURL()' "$ROOT/native/Sources/Infrastructure/OpenClaw/OpenClawVoicePlayback.swift"
grep -q 'OpenClawVoicePlayer.shared.speak(response.replyText)' "$ROOT/native/Sources/Application/SpeechInputCoordinator.swift"
```

Do not remove existing assertions for Python sidecar, worker resource, speech segmentation, prewarm, stdout/stderr handling, and stop behavior.

- [x] **Step 6: Run tests**

Run:

```bash
swiftc -o /tmp/typewhale-openclaw-voice-settings-check \
  native/Sources/Infrastructure/Settings/OpenClawVoiceSettings.swift \
  native/Tests/OpenClawVoiceSettingsCheck.swift && \
  /tmp/typewhale-openclaw-voice-settings-check

bash native/Tests/OpenClawVoicePlaybackIntegrationCheck.sh

bash native/Tests/OpenClawTTSBackendBoundaryCheck.sh

bash native/Tests/SherpaNativeTTSBackendSourceCheck.sh
```

Expected: all pass.

- [x] **Step 7: Commit**

```bash
git add native/Sources/Infrastructure/Settings/OpenClawVoiceSettings.swift \
  native/Sources/Infrastructure/OpenClaw/OpenClawVoicePlayback.swift \
  native/Tests/OpenClawVoiceSettingsCheck.swift \
  native/Tests/OpenClawVoicePlaybackIntegrationCheck.sh
git commit -m "feat: route OpenClaw voice through Sherpa native backend"
```

**Result:**
- 架构审查后补充 `cancelSynthesis()`：native CLI 会保存并终止当前子进程；Python JSONL sidecar 保持热态，避免“播放最新”破坏既有预热体验。
- `OpenClawVoicePlayer` 统一使用 `activeBackend` 管理 Python/native 后端；停止事件会使尚未挂回的后端失效，避免并发停止与启动后出现后端复活。
- `OpenClawVoiceSynthesisRequest.workerScriptURL` 改为可选，仅 Python sidecar 路径需要它；native 路径不再因 worker 文件缺失而被提前阻断。
- `sherpa_melo_native` 作为受控设置值可路由，但 UI `allCases` 与默认值仍只保留 `.sherpaMelo44k`。缺 native runtime 时只记录朗读失败，不影响 OpenClaw 文本消息。
- TDD：先确认 settings、路由与取消测试失败，再通过 `OpenClawVoiceSettingsCheck`、`OpenClawVoicePlaybackIntegrationCheck`、`OpenClawTTSBackendBoundaryCheck`、`SherpaNativeTTSBackendSourceCheck`、`SherpaNativeTTSBackendCheck` 和 `SherpaNativeTTSBackendCancellationCheck`。

---

## Task 6: Native Runtime Packaging Strategy

**Status:** Completed for optional development packaging; official runtime acquisition and distributable-bundle approval remain gated.

**Files:**
- Modify: `native/build_native_app.sh`
- Create: `native/Tests/SherpaNativeRuntimePackagingCheck.sh`
- Modify: `THIRD_PARTY_NOTICES.md` when redistributing native Sherpa artifacts is approved.

**Interfaces:**
- Consumes:
  - `TYPESPEAKER_SHERPA_ROOT` existing build-time Sherpa root for ASR dylibs.
  - `TYPEWHALE_SHERPA_NATIVE_TTS_RUNTIME` optional build-time directory for native TTS executable and dependent dylibs.
- Produces:
  - App resource directory: `Contents/Resources/NativeTTS/sherpa/`
  - Runtime copy rule only when `TYPEWHALE_SHERPA_NATIVE_TTS_RUNTIME` is set.

- [x] **Step 1: Write failing packaging source check**

Create `native/Tests/SherpaNativeRuntimePackagingCheck.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BUILD="$ROOT/native/build_native_app.sh"

grep -q 'TYPEWHALE_SHERPA_NATIVE_TTS_RUNTIME' "$BUILD"
grep -q 'NativeTTS/sherpa' "$BUILD"
grep -q 'sherpa-onnx-offline-tts' "$BUILD"
grep -q 'codesign --force --sign "$SIGN_IDENTITY" "$file"' "$BUILD"

echo "SherpaNativeRuntimePackagingCheck passed"
```

- [x] **Step 2: Run test to verify it fails**

Run:

```bash
bash native/Tests/SherpaNativeRuntimePackagingCheck.sh
```

Expected: FAIL because packaging has not been added.

- [x] **Step 3: Add optional packaging block**

Modify `native/build_native_app.sh` near `NATIVE_ASR` definitions:

```zsh
NATIVE_TTS="$CONTENTS/Resources/NativeTTS/sherpa"
NATIVE_TTS_SOURCE="${TYPEWHALE_SHERPA_NATIVE_TTS_RUNTIME:-}"
```

After `ditto "$ROOT/native/Resources" "$CONTENTS/Resources"`:

```zsh
if [[ -n "$NATIVE_TTS_SOURCE" ]]; then
  if [[ ! -x "$NATIVE_TTS_SOURCE/sherpa-onnx-offline-tts" ]]; then
    echo "Missing native TTS executable: $NATIVE_TTS_SOURCE/sherpa-onnx-offline-tts" >&2
    exit 1
  fi
  rm -rf "$NATIVE_TTS"
  mkdir -p "$NATIVE_TTS"
  ditto "$NATIVE_TTS_SOURCE" "$NATIVE_TTS"
fi
```

Update the signing loop:

```zsh
for RUNTIME_DIR in "$NATIVE_ASR_LIB" "$NATIVE_TTS"; do
```

- [x] **Step 4: Run packaging check**

Run:

```bash
bash native/Tests/SherpaNativeRuntimePackagingCheck.sh
```

Expected: PASS.

- [x] **Step 5: Do not package native runtime into release until licensing is recorded**

Before running `./native/build_and_log.sh` with `TYPEWHALE_SHERPA_NATIVE_TTS_RUNTIME`, verify:

```bash
test -f THIRD_PARTY_NOTICES.md
rg -n "sherpa-onnx|onnxruntime|espeak|piper_phonemize" THIRD_PARTY_NOTICES.md
```

Expected:
- If notices are complete, proceed.
- If notices are incomplete, update `THIRD_PARTY_NOTICES.md` before any distributable build.

- [x] **Step 6: Commit**

```bash
git add native/build_native_app.sh native/Tests/SherpaNativeRuntimePackagingCheck.sh THIRD_PARTY_NOTICES.md
git commit -m "build: package optional Sherpa native TTS runtime"
```

If `THIRD_PARTY_NOTICES.md` was not changed because packaging remains local-only, omit it from `git add`.

**Result:**
- 新增 `TYPEWHALE_SHERPA_NATIVE_TTS_RUNTIME` 可选构建输入；只有显式传入且根目录包含可执行的 `sherpa-onnx-offline-tts` 时，才会复制到 `Contents/Resources/NativeTTS/sherpa/` 并纳入 Mach-O 签名循环。
- `SherpaMeloTTSVoicePack.nativeExecutableURL()` 现在会查找 App 包内 `Resources/NativeTTS/sherpa`，弥合“已打包、运行时却无法发现”的架构缺口。
- 新增源码检查、runtime 发现测试和隔离打包集成检查；未传 runtime 时构建行为保持不变。
- 本轮没有下载或捆绑第三方 native TTS runtime；`THIRD_PARTY_NOTICES.md` 已覆盖现有 sherpa-onnx/ONNX Runtime，但正式分发仍须在选定官方 runtime 后记录版本、校验值和其实际依赖许可。
- 后续隔离验证下载了官方 `sherpa-onnx v1.13.2` macOS arm64 shared archive，并用官方 `checksum.txt` 核对 SHA-256 `50c5c04d93113602432a13454d6bf8e5d2624206b985fbd0dd4698454ae6c509`；真实包采用 `bin/sherpa-onnx-offline-tts` 与 `lib/` 布局，且要求 `--key=value` 参数格式，已据此补齐实现与回归测试。

---

## Task 7: Installed-App Native TTS QA Gate

**Status:** In progress. Documentation, focused checks, isolated install, signature, packaged-runtime synthesis, and local Gateway availability are verified. Full interactive OpenClaw reply QA remains pending.

**Files:**
- Modify: `docs/开发日志.md`
- Modify: `docs/ARCHITECTURE.md`
- Modify: `docs/产品需求文档.md`
- Modify: `native/Sources/Presentation/VersionHistory/VersionHistoryViewController.swift`
- Test/Run: `./native/build_and_log.sh`

**Interfaces:**
- Consumes:
  - Completed Tasks 1-6.
  - A known-good native runtime directory or explicit `TYPEWHALE_SHERPA_NATIVE_TTS`.
  - Existing OpenClaw text reply and voice playback path.
- Produces:
  - Installed TypeWhale Pro build with native TTS available behind controlled routing.
  - Manual QA evidence for voice quality, latency, CPU, memory, interruption, and fallback.

- [x] **Step 1: Update active architecture documentation**

Modify `docs/ARCHITECTURE.md` under `### Local TTS Sidecar`:

```markdown
- OpenClaw TTS now has two Sherpa-compatible implementation paths behind the same playback boundary:
  - `sherpa_melo_44k`: current Python sidecar baseline using `sherpa_onnx`.
  - `sherpa_melo_native`: Python-free Sherpa native executable path for local validation and eventual productization.
- The playback queue, prewarm, interrupt policy, speaking notifications, and failure degradation remain owned by `OpenClawVoicePlayer`.
- The native path may be exposed as the default only after installed-app QA confirms no regression in first audible latency, mixed Chinese/English pronunciation, memory, CPU, and failure behavior.
```

- [x] **Step 2: Update PRD and development log**

Add to `docs/产品需求文档.md` near the TTS section:

```markdown
#### Sherpa Native TTS productization candidate

目标：在保留当前 Sherpa Python sidecar 可用体验的同时，验证一个不依赖 Python 的 Sherpa Native TTS 路径，提升桌面产品分发完整度。

验收：
- 用户机器不需要安装 Python、pip 或命令行依赖。
- OpenClaw 文本回复、消息弹窗、复制、链接、ASR、截图和粘贴不受 TTS 失败影响。
- 中英混读、技术词、数字和符号的朗读效果不明显退步。
- 速度接近当前 Sherpa 路径，内存明显低于 MeloTTS。
- 第三方代码、运行时和模型授权完成记录后才进入可分发默认路径。
```

Add to `docs/开发日志.md`:

```markdown
## 2026-07-11：OpenClaw Sherpa Native TTS 工作树计划

- 新建 `codex/tts-native-backend` worktree，用于隔离评估不依赖 Python 的 Sherpa Native TTS 路径，避免影响预览框重构和当前已可用朗读链路。
- 计划采用先 CLI native spike、再产品后端接入、最后评估 C API bridge 的递进方式。
- 当前 Python sidecar 作为效果基线和回滚路径保留；不改 OpenClaw 消息 UI、ASR、胶囊、截图或粘贴链路。
```

- [x] **Step 3: Run focused tests**

Run:

```bash
bash native/Tests/SherpaNativeTTSProbeCheck.sh
bash native/Tests/SherpaNativeTTSBackendSourceCheck.sh
bash native/Tests/OpenClawTTSBackendBoundaryCheck.sh
bash native/Tests/OpenClawVoicePlaybackIntegrationCheck.sh
bash native/Tests/SherpaNativeRuntimePackagingCheck.sh

swiftc -o /tmp/typewhale-sherpa-native-runtime-check \
  native/Sources/Infrastructure/Models/SherpaMeloTTSVoicePack.swift \
  native/Tests/SherpaNativeTTSRuntimeCheck.swift && \
  /tmp/typewhale-sherpa-native-runtime-check

swiftc -o /tmp/typewhale-openclaw-voice-settings-check \
  native/Sources/Infrastructure/Settings/OpenClawVoiceSettings.swift \
  native/Tests/OpenClawVoiceSettingsCheck.swift && \
  /tmp/typewhale-openclaw-voice-settings-check
```

Expected: all pass.

- [x] **Step 4: Build and install**

Before build:

```bash
git branch --show-current
git status --short
pgrep -fl "build_and_log|release_local_build|build_native_app|swiftc|xcodebuild" || true
```

Run:

```bash
./native/build_and_log.sh
```

Expected:
- App builds.
- App installs to `/Applications/TypeWhale Pro.app`.
- Signing verification passes.
- App opens.
- `docs/构建日志.md` receives a new row.

- [ ] **Step 5: Manual installed-app QA**

Run these product checks in the installed app:

1. Open the main TypeWhale Pro window.
2. Confirm OpenClaw connection status still appears correctly.
3. Trigger an OpenClaw conversation that returns a mixed Chinese/English reply:

```text
请用中文简单解释 GitHub Actions、FastAPI、PostgreSQL、Redis、Kubernetes、OpenAI API 和 MiniMax 的关系。
```

4. Confirm text reply appears in the OpenClaw message container.
5. Confirm voice starts automatically if voice is enabled.
6. Confirm Stop stops playback.
7. Confirm the voice toggle persists.
8. Confirm double-click copy still shows `复制成功`.
9. Confirm links in a Markdown reply remain clickable.
10. Confirm TTS failure, missing runtime, or disabled voice does not break text reply display.

Record observed:
- First audible latency.
- Whether English technical words are acceptable.
- Whether punctuation pauses are acceptable.
- Activity Monitor memory and CPU during synthesis and playback.

Current evidence:

- Isolated `TypeWhale Pro TTS Native 2.0.6 (684)` includes the signed official Sherpa runtime and generated a 44.1 kHz WAV from the app bundle.
- Local OpenClaw Gateway process is available on port `18789`; the isolated app keeps `sherpa_melo_44k` as its stored default, so the production-like path was not switched accidentally.
- Official native CLI synthesis elapsed `3.153s` for a 4.9s mixed Chinese/English sample. This is not sufficient to promote the CLI path to default before a direct comparison and interactive reply QA.
- A separate `agent:main:typewhale-native-qa` session returned a real 477-character mixed Chinese/English OpenClaw reply without touching `agent:main:typewhale-voice`. The initial native CLI run exposed its default single-thread behavior: 52.64s audio took 34.88s to synthesize. The native backend now explicitly requests `--num-threads=4`; from isolated Build 685, the same reply produced 52.30s audio in 9.36s (RTF 0.179, about 3.7x faster). This clears the accidental single-thread regression but does not by itself clear the interactive first-audible latency or quality gate.
- Computer-use UI automation could not establish its local native pipe, so the remaining reply display, Stop action, double-click copy, Markdown links, and user-perceived first-audible timing still require an interactive installed-app session.

- [ ] **Step 6: Commit**

```bash
git add native/Sources native/Tests native/build_native_app.sh docs/ARCHITECTURE.md docs/产品需求文档.md docs/开发日志.md native/Sources/Presentation/VersionHistory/VersionHistoryViewController.swift docs/构建日志.md
git status --short
git commit -m "feat: add OpenClaw Sherpa native TTS path"
```

If `./native/build_and_log.sh` triggered a full version build, ensure the commit includes the version bump, version history, development log, and build log.

---

## Task 8: Decision Gate For C API Bridge

**Files:**
- Create: `docs/architecture/openclaw-sherpa-native-tts-adr.md`
- No production code unless this ADR accepts C API bridge.

**Interfaces:**
- Consumes:
  - Installed-app QA results from Task 7.
  - Native CLI runtime packaging result.
  - License and redistribution review.
- Produces:
  - Decision: keep CLI backend, move to C API bridge, or abandon native path and keep Python sidecar.

- [x] **Step 1: Create ADR**

Create `docs/architecture/openclaw-sherpa-native-tts-adr.md`:

```markdown
# OpenClaw Sherpa Native TTS ADR

Status: Conditional
Date: 2026-07-11
Scope: OpenClaw local TTS synthesis backend only
Decision owner: TypeWhale product/engineering

## Problem

The current OpenClaw TTS path is usable but depends on a Python sidecar. The product goal is a desktop-native path that feels complete when distributed to another Mac.

## Protected invariants

- OpenClaw text replies remain authoritative and always visible.
- TTS failure affects only voice output.
- ASR, realtime preview, paste, screenshot, capsule, hotkeys, and OpenClaw message UI do not change.
- Current Sherpa Python sidecar remains rollback until native QA passes.

## Candidates

### Keep Python sidecar

Benefits: already working, fastest rollback, proven with TypeWhale lexicon.
Liabilities: Python dependency feels demo-like, packaging/runtime complexity remains visible to engineering.

### Native CLI backend

Benefits: no Python, bounded process boundary, easier rollback than C bridge, lower integration risk.
Liabilities: process startup may add latency unless runtime is fast enough; command-line arguments and artifact packaging must be stable.

### C API bridge

Benefits: best product architecture if stable, no per-request process startup, can keep model hot inside App process or a native helper.
Liabilities: dylib signing, Swift/C memory ownership, crash blast radius, build complexity, and C API version drift.

## Conditional decision

Use Native CLI backend first. Move to C API bridge only if installed-app QA proves the CLI path is good enough in pronunciation but fails latency specifically because of process startup overhead.

## Review triggers

- Native CLI first audible latency is worse than current Sherpa Python sidecar by a product-visible margin.
- Native CLI cannot use the TypeWhale lexicon.
- Runtime packaging or license review fails.
- C API bridge can be built and signed with lower total operational risk than CLI.
```

- [ ] **Step 2: Commit ADR**

```bash
git add docs/architecture/openclaw-sherpa-native-tts-adr.md
git commit -m "docs: record Sherpa native TTS backend decision"
```

---

## Execution Order

1. Task 1: Native runtime contract.
2. Task 2: Local native CLI spike.
3. Stop and listen to the generated WAV if a native executable is available.
4. If native CLI cannot generate acceptable audio, stop implementation and update ADR as rejected.
5. Task 3: Backend protocol, no behavior change.
6. Task 4: Native backend with fake executable tests.
7. Task 5: Route native engine behind controlled settings.
8. Task 6: Optional runtime packaging.
9. Task 7: Installed-app QA.
10. Task 8: Decide whether to stay CLI or graduate to C API.

## Rollback

- Set stored `openClawVoiceEngine` back to `sherpa_melo_44k`.
- Keep `OpenClawVoiceEngine.productized(.meloTTS) == .sherpaMelo44k` so old Melo settings never become user-visible again.
- If native runtime fails, remove `.sherpaMeloNative` from `OpenClawVoiceEngine.allCases` and preserve the Python sidecar path.
- If packaging fails, leave native backend only available through `TYPEWHALE_SHERPA_NATIVE_TTS` in development builds.

## Self-Review

- Spec coverage: covers Python-free native path, preservation of current Sherpa baseline, no App lexicon UI, no preview/ASR/UI changes, runtime packaging, installed-app QA, and C API decision gate.
- Placeholder scan: no implementation step depends on an undefined future task; every task has exact files, commands, expected outcomes, and commit points.
- Type consistency: `OpenClawTTSBackend`, `SherpaNativeTTSBackend`, `SherpaMeloTTSVoicePack.nativeExecutableURL()`, and `OpenClawVoiceEngine.sherpaMeloNative` are introduced before downstream usage.
