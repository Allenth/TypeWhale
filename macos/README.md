# 原生 macOS 应用

`TypeWhale.app` 是本地构建出的原生 Swift/AppKit 应用。

它包含：

- 原生主窗口和权限诊断。
- 原生全局快捷键、录音、非激活胶囊浮窗和粘贴流程。
- 独立应用图标和稳定 Bundle Identifier。
- 基于 sherpa-onnx 原生 bridge 的本地 ASR 推理。
- 内置模型资源，不依赖运行时 Python worker。

构建和签名：

```bash
native/build_native_app.sh
```

面向用户的应用是原生 macOS App。ASR 识别通过打包进应用的 sherpa-onnx 原生 bridge 执行。
