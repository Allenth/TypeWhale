# Windows 测试交接清单

本文记录当前 Windows 版从 macOS 侧移交到 Windows 真机测试前的真实状态。它不是发布说明，也不代表 Windows 版已经可交付。

后续开发优先级、分阶段验收和技术风险见 [WINDOWS_DEVELOPMENT_PLAN.md](./WINDOWS_DEVELOPMENT_PLAN.md)。

## 当前状态

- Windows 项目目录已建立在 `windows/`。
- WPF 主程序、录音、热键、VAD、final ASR、粘贴和最近历史的 MVP 源码已落地。
- SenseVoice 与 VAD 模型已从 macOS app 包复制到 Windows 项目目录。
- macOS 版源码、架构和 app bundle 没有因为本次复制而修改。
- 当前 macOS 环境未安装 `dotnet`，也不能验证 Windows 全局热键、麦克风和 DLL 加载。

## 已就绪资源

```text
windows/TypeWhale.Windows/Models/sensevoice-native/model.onnx
windows/TypeWhale.Windows/Models/sensevoice-native/tokens.txt
windows/TypeWhale.Windows/Models/vad/silero_vad.onnx
windows/TypeWhale.Windows/THIRD_PARTY_NOTICES.md
```

这些资源来自：

```text
macos/TypeWhale.app/Contents/Resources/Models/
macos/TypeWhale.app/Contents/Resources/THIRD_PARTY_NOTICES.md
```

已在 macOS 上用 SHA-256 校验模型副本，Windows 目录与 macOS app 包中的源文件一致。

## 仍缺资源

Windows 仍需要单独准备 Windows 版动态库：

```text
windows/TypeWhale.Windows/runtimes/win-x64/native/TypeSpeakerNativeASR.dll
windows/TypeWhale.Windows/runtimes/win-x64/native/sherpa-onnx-c-api.dll
windows/TypeWhale.Windows/runtimes/win-x64/native/onnxruntime.dll
```

macOS 的 `.dylib` 不能用于 Windows，没有复制，也不应复用。

## Windows 首次验证顺序

在 Windows 机器上从仓库根目录执行：

```powershell
cd windows
.\scripts\Build-App.ps1
```

这一步只验证 WPF 项目能否编译，不要求 native DLL 和模型完整可运行。

然后准备 sherpa-onnx Windows C API 包，执行：

```powershell
.\scripts\Build-Native.ps1 -SherpaOnnxRoot C:\path\to\sherpa-onnx
```

再检查运行布局：

```powershell
.\scripts\Check-WindowsLayout.ps1
```

最后运行应用，按顺序测试：

1. 主窗口启动，不崩溃。
2. 默认 `Ctrl + Alt + Space` 可开始和停止录音，也可在主窗口自定义组合键。
3. 长按当前组合键时开始录音，松开后停止。
4. 静音录音不会进入粘贴。
5. 中文语音能 final 识别。
6. 识别结果能粘贴到记事本。
7. 粘贴后剪贴板内容尽量恢复。
8. 再测微信、浏览器、Word 或常用输入目标。

## 和 macOS 版的已知差距

- Windows 版没有非激活录音胶囊。
- Windows 版没有实时预览和七频段波形。
- Windows 版已有基础热键配置 UI，可自定义一个组合键；冲突检测仍未完成。
- Windows 版最近历史仅内存展示，尚未持久化。
- Windows 版没有托盘后台生命周期、开机启动、安装包和签名。
- Windows 版剪贴板恢复是 MVP 简化版，兼容性需要真机验证。

## 下一轮建议

优先级保持窄：

1. 先修到 `Build-App.ps1` 通过。
2. 再修到 `Build-Native.ps1` 通过并复制 DLL。
3. 然后验证 `录音 -> VAD -> final ASR -> 粘贴`。
4. 主链路跑通后，再补托盘、胶囊、热键配置和安装包。
