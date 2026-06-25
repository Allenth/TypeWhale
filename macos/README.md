# 原生 macOS 应用

`TypeWhale.app` 是本地构建出的原生 Swift/AppKit 应用。

它包含：

- 原生主窗口和权限诊断。
- 原生全局快捷键、录音、非激活胶囊浮窗和粘贴流程。
- 可配置的录音、截图、自动翻译和唤起主页快捷键；自动翻译与唤起主页默认未设置。
- 原生截图覆盖层：框选、悬停窗口选择、窗口置顶后重新截图、内联标注、OCR、复制和直接保存。
- 独立应用图标和稳定 Bundle Identifier。
- 基于 sherpa-onnx 原生 bridge 的本地 ASR 推理。
- 内置模型资源，不依赖运行时 Python worker。

构建和签名：

```bash
native/build_native_app.sh
```

面向用户的应用是原生 macOS App。ASR 识别通过打包进应用的 sherpa-onnx 原生 bridge 执行。

当前本地发布版本：`1.3.56 (264)`。构建脚本默认会覆盖安装到 `/Applications/TypeWhale.app`；如只想生成 `macos/TypeWhale.app`，设置 `TYPESPEAKER_SKIP_INSTALL=1`。
