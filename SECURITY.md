> 文档迁移（2026-09-05）：[现行文档](docs/current/ARCHITECTURE.md)。本专项文件继续保留；下方关于外发仅属未来功能的措辞是旧快照，现有 DeepSeek／OpenClaw 数据流与工程边界见新架构，发布前需专项复核。

# Security Policy

TypeWhale handles sensitive local data:

- microphone audio,
- recognized text,
- clipboard contents,
- Accessibility-controlled paste events.

The intended security posture is local-first. Audio and recognized text should not leave the machine unless a future feature explicitly documents and asks for that behavior.

## Reporting Security Issues

Please open a private security advisory on GitHub if available, or contact the maintainer through the repository issue tracker with minimal reproduction details. Do not post private audio, clipboard contents, access tokens, or personal documents in public issues.

## Expected Behavior

- Recordings are local cache files.
- Clipboard data is temporarily replaced only for paste and then restored when safe.
- Microphone permission is required for recording.
- Accessibility permission is required for global insertion into other apps.
- Models and runtime binaries are not committed to this repository.

## Release Safety

Public macOS distribution should use:

- Developer ID signing,
- notarization,
- Gatekeeper validation,
- model license review,
- third-party notice verification.
