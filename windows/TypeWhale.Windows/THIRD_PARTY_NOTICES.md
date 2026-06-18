# TypeWhale Third-Party Notices

Last reviewed: 2026-06-15

This file records third-party runtime libraries and bundled models currently shipped with TypeWhale. It is documentation for attribution and license review. It is not legal advice.

## Bundled Runtime Libraries

### sherpa-onnx

- Component: `libsherpa-onnx-c-api.dylib`
- Project: `k2-fsa/sherpa-onnx`
- Source: https://github.com/k2-fsa/sherpa-onnx
- License: Apache License 2.0
- Bundled location: `TypeWhale.app/Contents/Resources/NativeASR/lib/libsherpa-onnx-c-api.dylib`
- Notice requirement: keep the Apache-2.0 license reference and any upstream NOTICE text if present in the distributed artifact.

### ONNX Runtime

- Component: `libonnxruntime.1.24.4.dylib`
- Project: `microsoft/onnxruntime`
- Source: https://github.com/microsoft/onnxruntime
- License: MIT
- Copyright notice: Microsoft Corporation
- Bundled location: `TypeWhale.app/Contents/Resources/NativeASR/lib/libonnxruntime.1.24.4.dylib`
- Notice requirement: keep the MIT license reference and copyright notice.

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
