# Model Setup

This repository does not include ASR or VAD model files.

## macOS

Prepare SenseVoice model files:

```text
~/Library/Application Support/TypeWhale/Models/sensevoice-native/model.onnx
~/Library/Application Support/TypeWhale/Models/sensevoice-native/tokens.txt
```

Prepare Silero VAD:

```text
~/Library/Application Support/TypeWhale/Models/vad/silero_vad.onnx
```

Then build with:

```bash
TYPESPEAKER_MODEL_SOURCE="$HOME/Library/Application Support/TypeWhale/Models/sensevoice-native" \
TYPEWHALE_VAD_MODEL_SOURCE="$HOME/Library/Application Support/TypeWhale/Models/vad/silero_vad.onnx" \
./native/build_native_app.sh
```

## Windows

Place model files under:

```text
windows/TypeWhale.Windows/Models/sensevoice-native/model.onnx
windows/TypeWhale.Windows/Models/sensevoice-native/tokens.txt
windows/TypeWhale.Windows/Models/vad/silero_vad.onnx
```

These files are intentionally ignored by git.

## License Reminder

Model files have their own licenses and redistribution terms. Review [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md) before distributing a build that bundles models.
