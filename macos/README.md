> 文档迁移（2026-09-05）：[现行文档](../docs/current/README.md)。当前 macOS 使用与发布说明见新入口。下方保留历史正文与构建脚本维护的版本字段。

# 原生 macOS 应用

`TypeWhale Pro.app` 是本地构建出的原生 Swift/AppKit 应用。

它包含：

- 原生主窗口和权限诊断。
- 原生全局快捷键、录音、非激活胶囊浮窗和粘贴流程。
- 可配置的录音、截图、自动翻译和唤起主页快捷键；自动翻译与唤起主页默认未设置。
- 原生截图覆盖层：框选、带半透明候选蒙层的悬停窗口选择、窗口置顶后重新截图、创建型内联标注（含高斯模糊马赛克）、撤销/前进、OCR、复制和直接保存。
- 最近转录保留最近 20 条，支持双击左键复制。
- 智能整理支持自动范围规则，可按目标窗口或本次口述内容选择整理模式；智能 Tab 集中管理整理模式、闪念整理、归档整理、翻译方向和全部可编辑整理模板。
- 独立应用图标和稳定 Bundle Identifier。
- 基于 sherpa-onnx 原生 bridge 的本地 ASR 推理。
- 内置模型资源，不依赖运行时 Python worker。

构建和签名：

```bash
native/build_native_app.sh
```

面向用户的应用是原生 macOS App。ASR 识别通过打包进应用的 sherpa-onnx 原生 bridge 执行。

当前本地发布版本：`2.0.58 (919)`。`./native/build_and_log.sh` 默认编译当前源码、递增 build 号并覆盖安装到 `/Applications/TypeWhale Pro.app`，短版本号保持不变；需要同时递增短版本号时使用 `./native/build_and_log.sh --full-version`。如构建时只想生成 `macos/TypeWhale Pro.app`，设置 `TYPESPEAKER_SKIP_INSTALL=1`。
