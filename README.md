# TypeWhale

TypeWhale is a local-first desktop speech input tool. It records from the microphone, runs local ASR through a native sherpa-onnx / ONNX Runtime pipeline, previews recognition in a compact capsule, and inserts the final text back into the active app.

The current macOS baseline is:

```text
Global hotkey -> record audio -> capsule preview -> final ASR -> paste final text
```

Realtime preview is only used as feedback. The final inserted text comes from the complete recording.

## Features

- Native macOS app built with Swift and AppKit.
- Global hotkey recording: press to start/stop, or hold to talk and release to finish.
- Non-activating recording capsule with animated microphone waveform.
- Local SenseVoice / sherpa-onnx ASR integration.
- Clipboard-based final insertion with clipboard restoration.
- Recent transcription history.
- Microphone, Accessibility, hotkey, model, and login-item status in the main window.
- Optional launch at login.
- Early Windows WPF MVP scaffold in `windows/`.

## Repository Scope

This open-source repository contains source code, build scripts, icons, notices, and architecture notes.

It intentionally does not include:

- macOS `.app` bundles.
- DMG / ZIP release artifacts.
- ASR model files such as `model.onnx` or `silero_vad.onnx`.
- ONNX Runtime / sherpa-onnx dynamic libraries.
- Developer certificates, notarization assets, local caches, or generated build folders.

See [docs/MODEL_SETUP.md](docs/MODEL_SETUP.md) for model placement.

## macOS Build

Requirements:

- macOS 13 or later.
- Xcode Command Line Tools.
- A local sherpa-onnx installation that provides C headers and dynamic libraries.
- Local model files prepared outside this repository.

Build:

```bash
cd TypeWhale
TYPESPEAKER_MODEL_SOURCE="$HOME/Library/Application Support/TypeWhale/Models/sensevoice-native" \
TYPEWHALE_VAD_MODEL_SOURCE="$HOME/Library/Application Support/TypeWhale/Models/vad/silero_vad.onnx" \
./native/build_native_app.sh
```

The app bundle is generated at:

```text
macos/TypeWhale.app
```

Local development builds may use an Apple Development or ad-hoc signature. Public distribution requires Developer ID signing, notarization, and Gatekeeper validation.

## Windows

The `windows/` directory contains an early WPF MVP scaffold and handoff notes. It is not yet at the same release maturity as the macOS app.

Model and runtime binaries are not committed. Follow [windows/README.md](windows/README.md) and [windows/WINDOWS_DEVELOPMENT_PLAN.md](windows/WINDOWS_DEVELOPMENT_PLAN.md).

## Privacy

TypeWhale is designed as a local-first tool:

- Audio is recorded locally.
- ASR is intended to run locally.
- The app needs Microphone permission for recording.
- The app needs Accessibility permission to restore focus and insert text into other apps.
- Clipboard contents are temporarily replaced during paste, then restored.

Do not add network transcription or telemetry without making it explicit in code, UI, and documentation.

## Third-Party Notices

Third-party runtime and model provenance is documented in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

Important: SenseVoice / FunASR model redistribution terms need explicit review before paid public redistribution. This repository does not grant model redistribution rights.

## License

Source code in this repository is released under the MIT License. See [LICENSE](LICENSE).

Third-party components and models remain under their own licenses and terms.
