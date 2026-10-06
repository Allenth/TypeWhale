# TypeWhale Third-Party Notices

Last reviewed: 2026-09-13

This file records third-party runtime libraries and bundled models currently shipped with TypeWhale. It is documentation for attribution and license review. It is not legal advice.

## Xiaomi Remote Protocol References

### Android TV Virtual Remote Control (ATVV)

- Reference: Android Open Source Project Bluetooth voice/HID protocol material.
- Source: https://android.googlesource.com/platform/system/bt/
- License: Apache License 2.0 for the referenced AOSP source material.
- Use in TypeWhale: public protocol identifiers and message-layout facts only; no AOSP binary is bundled for this feature.

### mi-ao

- Project: `fanxeon/mi-ao`.
- Source: https://github.com/fanxeon/mi-ao
- Reference commit: `d6019bcede80ff71d225385b5c44b6f5f84a4832`.
- License: MIT.
- Copyright: 2026 FanXeon@Poemcoder with Codex.
- Use in TypeWhale: interoperability evidence for the Xiaomi Remote Control 2 Pro HID profile and ATVV framing. TypeWhale's production implementation is maintained in its own Domain/Application/Infrastructure boundaries.

### SayAll / remote-mic-app code exclusion

- Project reviewed: `HD838A/remote-mic-app` (SayAll), GPL-3.0-only, with separately restricted logo assets.
- Source: https://github.com/HD838A/remote-mic-app
- Code distribution decision: TypeWhale does not copy, link, bundle, translate, or derive its remote implementation from SayAll source, binaries, driver/helper, logo, app icon, or product photo.

### RC003 product photo

- Component: `RC003-remote-photo.png`.
- Source: https://github.com/HD838A/remote-mic-app/blob/2fa4067ebfe68b874683341efc62555a0b650a6a/Resources/RC003-remote-photo.png
- Reference commit: `2fa4067ebfe68b874683341efc62555a0b650a6a`.
- SHA-256: `658d9333853958c13ff721eb76e1a6816c1dbea16006a84e8577ad410812549f`.
- Public-source decision: this repository intentionally omits this photo because the public redistribution documents are not included in the repository. The open-source build remains functional and displays an explicit placeholder while keeping all mapping controls available.
- Optional local use: a distributor who independently holds sufficient rights may provide the exact file at `native/Resources/Remote/RC003-remote-photo.png` before building. The build script copies resources without downloading anything at runtime.
- Rights boundary: copyright and trademark rights in the image and depicted product remain with their respective owners. This notice does not grant rights to download, copy, bundle, or redistribute the referenced image.

## Bundled Runtime Libraries

### sherpa-onnx

- Component: `libsherpa-onnx-c-api.dylib`
- Project: `k2-fsa/sherpa-onnx`
- Source: https://github.com/k2-fsa/sherpa-onnx
- License: Apache License 2.0
- Bundled location: `TypeWhale.app/Contents/Resources/NativeASR/lib/libsherpa-onnx-c-api.dylib`
- Notice requirement: keep the Apache-2.0 license reference and any upstream NOTICE text if present in the distributed artifact.

### Optional Sherpa Native CLI TTS Runtime (internal validation only)

- Component: `sherpa-onnx-offline-tts`, `libsherpa-onnx-c-api.dylib`, `libsherpa-onnx-cxx-api.dylib`.
- Version: `v1.13.2` macOS arm64 shared runtime.
- Project: `k2-fsa/sherpa-onnx`.
- Source: https://github.com/k2-fsa/sherpa-onnx/releases/tag/v1.13.2
- Archive: `sherpa-onnx-v1.13.2-osx-arm64-shared.tar.bz2`.
- SHA-256: `50c5c04d93113602432a13454d6bf8e5d2624206b985fbd0dd4698454ae6c509`.
- License: Apache License 2.0.
- Internal validation bundle location: `TypeWhale Pro TTS Native.app/Contents/Resources/NativeTTS/sherpa/`.
- Distribution gate: this runtime is only approved for isolated local validation. Before public distribution, record the exact archive, SHA-256, bundled dependency list, upstream NOTICE files, and final release approval.

### ONNX Runtime

- Component: `libonnxruntime.1.24.4.dylib`
- Project: `microsoft/onnxruntime`
- Source: https://github.com/microsoft/onnxruntime
- License: MIT
- Copyright notice: Microsoft Corporation
- Bundled location: `TypeWhale.app/Contents/Resources/NativeASR/lib/libonnxruntime.1.24.4.dylib`
- Notice requirement: keep the MIT license reference and copyright notice.
- Optional native TTS runtime dependency: the validated Sherpa Native CLI archive also includes `libonnxruntime.1.24.4.dylib`; the same MIT notice applies.

## Bundled Models

### Silero VAD

- Component: `silero_vad.onnx`
- Project: `snakers4/silero-vad`
- Source: https://github.com/snakers4/silero-vad
- License: MIT
- Copyright notice: Silero Team
- Bundled location: `TypeWhale.app/Contents/Resources/Models/vad/silero_vad.onnx`
- Notice requirement: keep the MIT license reference and copyright notice.

### SenseVoice / FunASR Model

- Component: SenseVoice int8 ONNX model and tokens.
- Runtime source used by this project: https://huggingface.co/csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17
- Upstream model family: https://huggingface.co/FunAudioLLM/SenseVoiceSmall
- Upstream project: https://github.com/FunAudioLLM/SenseVoice
- Related model license: https://github.com/modelscope/FunASR/blob/main/MODEL_LICENSE
- Bundled location: `TypeWhale.app/Contents/Resources/Models/sensevoice-native`

Current review status:

- The Hugging Face SenseVoiceSmall page labels the model license as `model-license`.
- The related FunASR model license allows use, copy, modification, and sharing under its agreement, and requires source and author attribution.
- The same model license also contains reference/learning-purpose wording and custom termination/revision terms.
- Because of those custom terms, TypeWhale should not treat this model as already cleared for paid commercial redistribution without written confirmation from the model owner or a replacement model with explicit commercial redistribution terms.

Release policy:

- Local development and internal test builds may include this model with this source and authorization note.
- Public paid builds should keep this notice and additionally store written commercial authorization, or replace the model before sale.

## Optional Local TTS Reading Lab Models

The following model families are downloaded into the user's Application Support
directory for local evaluation. Their weights are not bundled in the TypeWhale app
or its DMG. A model becomes selectable only after its local license file, required
files, and three-round offline qualification all pass.

- Sherpa ONNX ZipVoice: upstream `k2-fsa/sherpa-onnx` and `k2-fsa/ZipVoice`;
  Apache-2.0 runtime and model notices are stored beside the local model.
- The four local reference voices remain experimental. Redistribution requires
  a separate review of the reference audio and source-model rights.
