# TypeWhale

TypeWhale is a local-first desktop speech input tool. It records from the microphone, runs local ASR through a native sherpa-onnx / ONNX Runtime pipeline, previews recognition in a compact capsule, and inserts the final text back into the active app.

## Download

[Download TypeWhale-1.6.7-457.dmg](https://github.com/Allenth/TypeWhale/releases/download/v1.6.7-build457/TypeWhale-1.6.7-457.dmg)

This is a public test build. It is not notarized with Developer ID yet, so macOS may require manual approval in System Settings.

中文用户可以直接点击上面的链接下载安装包。如果浏览器没有开始下载，请右键链接选择“链接另存为”，或打开 [TypeWhale 1.6.7 (Build 457) Release](https://github.com/Allenth/TypeWhale/releases/tag/v1.6.7-build457) 页面，在 **Assets** 区域下载 `TypeWhale-1.6.7-457.dmg`。

Current public release build in this repository is `1.6.7 (Build 457)`. It has been built, packaged as a DMG, uploaded to GitHub Releases, and copied to the local Downloads folder.

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
- Screenshot capture via a dedicated hotkey: region selection with resize handles, translucent hover-to-select window capture, inline annotation tools (rectangle, arrow, pen, text, undo), OCR text recognition, English-to-Chinese screenshot translation with source-text covering, copy to clipboard, and direct save to the configured folder.
- Configurable hotkeys for recording, screenshot, auto-translation toggle, and opening the main panel. Auto-translation and main-panel hotkeys are unset by default.
- Clipboard-based final insertion with clipboard restoration.
- Recent transcription history keeps the latest 20 items and supports double-click copy.
- Microphone, Accessibility, hotkey, model, and login-item status in the main window.
- Optional launch at login.
- Early Windows WPF MVP scaffold in `windows/`.

## Repository Scope

This open-source repository contains source code, build scripts, icons, notices, and the current architecture reference in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

It intentionally does not include:

- macOS `.app` bundles.
- DMG / ZIP release artifacts.
- ASR model files such as `model.onnx` or `silero_vad.onnx`.
- ONNX Runtime / sherpa-onnx dynamic libraries.
- Developer certificates, notarization assets, local caches, or generated build folders.

See [docs/MODEL_SETUP.md](docs/MODEL_SETUP.md) for model placement.

## macOS Build

Requirements:

- macOS 14 or later.
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

---

# TypeWhale 中文说明

TypeWhale 是一个本地优先的桌面语音输入工具。它会在本机录音、本机识别，然后把最终文本粘贴回你原本正在输入的应用里。

当前 macOS 版本的核心流程是：

```text
按快捷键开始录音 -> 胶囊显示录音状态和实时预览 -> 松开或再次按快捷键结束 -> 本地识别 -> 自动粘贴最终文本
```

实时预览只用于让你知道应用正在听、正在理解，不会提前写入输入框。真正粘贴的内容来自完整录音的最终识别结果。

## 下载和安装

测试版 DMG 可以在 GitHub Releases 下载：

[TypeWhale 1.6.7 (Build 457) Release](https://github.com/Allenth/TypeWhale/releases/tag/v1.6.7-build457)

当前测试版 DMG 直链：

[TypeWhale-1.6.7-457.dmg](https://github.com/Allenth/TypeWhale/releases/download/v1.6.7-build457/TypeWhale-1.6.7-457.dmg)

如果点击直链没有反应，可以打开 Release 页面，在底部 **Assets** 区域下载 `TypeWhale-1.6.7-457.dmg`，或右键链接选择“链接另存为”。

下载后：

1. 打开 `TypeWhale-*.dmg`。
2. 将 `TypeWhale.app` 拖到 `Applications` 文件夹。
3. 从 `Applications` 启动 TypeWhale。

注意：当前公开 DMG 是测试版，还没有 Developer ID 公证。macOS 可能提示“无法打开”或“来自未知开发者”。如果你信任该测试包，可以在：

```text
系统设置 -> 隐私与安全性
```

里找到被拦截的 TypeWhale，并选择允许打开。

## 第一次启动需要授权

TypeWhale 需要两个系统权限：

- 麦克风：用于录音。
- 辅助功能：用于把识别结果粘贴回你正在输入的应用。

第一次打开后，主面板会显示权限状态。如果看到“未开启”或“检测中”，可以点击面板里的对应设置按钮，跳转到系统设置。

建议确认：

```text
系统设置 -> 隐私与安全性 -> 麦克风 -> TypeWhale 已开启
系统设置 -> 隐私与安全性 -> 辅助功能 -> TypeWhale 已开启
```

## 状态栏图标

TypeWhale 运行后会出现在 macOS 顶部状态栏。状态栏图标是黄色小图标。

点击状态栏图标，会看到菜单：

- 打开 TypeWhale 面板
- 第三方组件与模型授权
- 完全退出 TypeWhale

如果主窗口被关闭了，应用仍然可以在后台运行。你可以从状态栏菜单重新打开控制面板。

## 如何打开控制面板

有三种方式：

1. 启动 `TypeWhale.app` 后自动显示。
2. 点击状态栏图标，选择“打开 TypeWhale 面板”。
3. 如果应用已经在后台运行，再次打开 `TypeWhale.app` 也会唤起主面板。

控制面板可以用来查看：

- 当前录音状态。
- 麦克风权限状态。
- 辅助功能权限状态。
- 全局快捷键监听状态。
- 主快捷键和备用快捷键。
- 截图、自动翻译和唤起主页快捷键。
- 本地识别模型状态。
- 最近转录记录。

## 如何录音输入

默认主快捷键是 `Fn`。

你可以用两种方式录音：

- 单击快捷键：开始录音；再次单击：结束录音并粘贴。
- 长按快捷键：按住开始说话；松开后结束录音并粘贴。

录音期间会出现一个小胶囊，显示：

- 当前是否正在录音。
- 麦克风波形。
- 实时预览文字。

录音结束后，TypeWhale 会使用完整录音做最终识别，并自动粘贴到你开始录音时所在的应用。

## 主面板里的常用选项

### 主快捷键

主快捷键默认是 `Fn`。你可以点击“录入”重新设置。

### 备用快捷键

备用快捷键可以作为第二个入口，例如右 Option。适合你想保留两个不同触发方式的情况。

### 截图快捷键

截图快捷键默认是双击右 Option。触发后会进入截图覆盖层，不会主动把 TypeWhale 主面板切到最前。

截图时可以：

- 拖拽选择区域。
- 悬停窗口并单击，TypeWhale 会先置顶该窗口，再重新截图并自动对齐窗口边框。
- 在选区内直接标注矩形、箭头、画笔和文字。
- OCR 识别选区文字并复制到剪贴板。
- 对英文截图选区进行英译中，按 OCR 行级坐标遮盖英文原文并贴入中文译文；双击复制和保存本地都会包含译文层。
- 复制截图或直接保存到配置的截图保存位置。

### 自动翻译快捷键

自动翻译快捷键默认未设置。设置后，它只用于快速打开或关闭自动翻译，不占用录音快捷键。

### 唤起主页快捷键

唤起主页快捷键默认未设置。这样可以避免和默认主录音快捷键 `Fn` 冲突。需要这个能力时，可以在快捷键设置中自行录入。

### 录音时降低电脑声音

开启后，录音时会临时降低电脑播放声音，减少外放声音被麦克风录进去。

### 停顿自动完成

开启后，说话停顿一段时间会自动结束录音。长按说话时仍以松开快捷键为准。

### 胶囊实时预览

开启后，录音胶囊会显示实时预览文字。关闭后，仍然会在录音结束后做最终识别和粘贴。

### 智能整理

智能整理会在本地最终识别完成后、粘贴前整理文本。可选模式包括自动、原文、润色、开发需求和极致归纳。

自动模式会根据目标 App、Bundle ID、窗口标题和本次口述内容选择整理方式。例如编程窗口默认倾向开发需求；口述里包含“总结、归纳、要点、行动项”等意图时，会自动使用极致归纳。自动范围、提示词、开发术语词库和 DeepSeek API Key 可在偏好设置里配置。

智能整理需要配置 DeepSeek API Key；未配置、超时或达到成本限制时，会回退到本地识别原文。

### 开机自动启动

开启后，登录 macOS 时自动启动 TypeWhale。系统可能要求你在登录项设置里确认。

## 最近转录

主面板底部会显示最近几条识别结果。每条记录旁边有复制按钮，可以把历史文本重新复制到剪贴板。

这些记录只保存在本机。

## 如何完全退出

关闭主窗口不等于退出应用。TypeWhale 会继续在后台运行，以便快捷键还能工作。

如果要完全退出：

1. 点击 macOS 顶部状态栏里的 TypeWhale 图标。
2. 选择“完全退出 TypeWhale”。

完全退出后：

- 状态栏图标会消失。
- 全局快捷键不再监听。
- 录音胶囊不会再出现。

再次使用时，重新打开 `TypeWhale.app` 即可。

## 隐私说明

TypeWhale 的设计目标是本地优先：

- 录音文件保存在本机缓存目录。
- 识别在本机运行。
- 不需要把音频上传到云端。
- 只有在启用智能整理、自动翻译或截图翻译并配置 DeepSeek API Key 后，对应文本才会发送给 DeepSeek 处理。
- 自动粘贴时会短暂改写剪贴板，然后尽量恢复原剪贴板内容。

如果未来加入联网识别或遥测，必须在代码、界面和文档里明确说明。

## 模型和授权说明

开源仓库不包含模型文件和运行时二进制。测试版 DMG 可能包含本地识别所需的运行库和模型。

第三方组件和模型来源见：

[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)

重要提醒：SenseVoice / FunASR 模型的公开再分发和商业使用需要进一步确认。正式商业发布前，应取得明确授权或替换为授权更清晰的模型。
