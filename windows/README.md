# TypeWhale Windows

这是 TypeWhale 的 Windows 版本项目目录，目标是保持和 macOS 主线一致的产品基线：

```text
全局快捷键录音 -> final 本地识别 -> 一次性粘贴最终文本
```

当前 Windows MVP 使用 .NET 8 WPF：

- 默认快捷键：`Ctrl + Alt + Space`，可在主窗口中自定义。
- 支持单击开始/停止，以及长按说话、松开停止。
- 使用 NAudio 录制 16 kHz mono WAV。
- 通过 `TypeSpeakerNativeASR.dll` 调用 sherpa-onnx SenseVoice final 识别。
- 使用 Silero VAD 避免粘贴空文本。
- 识别完成后写入剪贴板并发送 `Ctrl + V`，随后尽量恢复原剪贴板。
- 主窗口显示模型状态、录音状态和最近 5 条识别历史。

首次切到 Windows 真机测试前，建议先看 [WINDOWS_TEST_HANDOFF.md](./WINDOWS_TEST_HANDOFF.md)。
后续开发优先级和验收标准见 [WINDOWS_DEVELOPMENT_PLAN.md](./WINDOWS_DEVELOPMENT_PLAN.md)。

## 目录

```text
windows/
├── README.md
├── WINDOWS_TEST_HANDOFF.md
├── WINDOWS_DEVELOPMENT_PLAN.md
├── TypeWhale.Windows.sln
├── TypeWhale.Windows/
│   ├── Application/
│   ├── Domain/
│   ├── Infrastructure/
│   ├── Presentation/
│   ├── Models/
│   └── runtimes/win-x64/native/
├── scripts/
│   ├── Build-App.ps1
│   ├── Build-Native.ps1
│   └── Check-WindowsLayout.ps1
└── native/
    └── CMakeLists.txt
```

## 运行要求

- Windows 10 19041 或更高版本。
- .NET 8 SDK。
- Visual Studio 2022 或 `dotnet` CLI。
- sherpa-onnx Windows C API 动态库。
- SenseVoice 模型文件：

```text
TypeWhale.Windows/Models/sensevoice-native/model.onnx
TypeWhale.Windows/Models/sensevoice-native/tokens.txt
TypeWhale.Windows/Models/vad/silero_vad.onnx
```

当前仓库里的 Windows 目录已从 macOS app 包复制上述模型文件。模型是 ONNX/文本资源，可跨平台复用；macOS 的 `.dylib` 运行库没有复制给 Windows 使用。

运行时原生库放在：

```text
TypeWhale.Windows/runtimes/win-x64/native/TypeSpeakerNativeASR.dll
TypeWhale.Windows/runtimes/win-x64/native/sherpa-onnx-c-api.dll
TypeWhale.Windows/runtimes/win-x64/native/onnxruntime.dll
```

## 构建

在 Windows 上：

```powershell
cd windows
dotnet restore .\TypeWhale.Windows.sln
dotnet build .\TypeWhale.Windows.sln -c Debug -p:Platform=x64
```

构建 native bridge：

```powershell
cd windows
.\scripts\Build-Native.ps1 -SherpaOnnxRoot C:\path\to\sherpa-onnx
```

脚本会把生成的 `TypeSpeakerNativeASR.dll` 和 sherpa-onnx/ONNX Runtime 依赖 DLL 复制到：

```text
windows/TypeWhale.Windows/runtimes/win-x64/native/
```

检查运行文件是否齐全：

```powershell
.\scripts\Check-WindowsLayout.ps1
```

构建或发布 WPF 应用：

```powershell
.\scripts\Build-App.ps1
.\scripts\Build-App.ps1 -CheckRuntime
.\scripts\Build-App.ps1 -Configuration Release -Publish
```

## 当前差异

macOS 版默认使用 Fn 和侧向修饰键。Windows MVP 默认使用 `Ctrl + Alt + Space`，也可以在主窗口中改成用户自己的组合键。Windows 对 Fn 键通常不向应用层暴露，左右修饰键仍需要更多键盘和输入法布局验证。

## Windows 验证顺序

第一次到 Windows 环境建议按这个顺序走：

1. 安装 .NET 8 SDK、Visual Studio 2022 C++ CMake 工具和 CMake。
2. 执行 `.\scripts\Build-App.ps1`，先确认 WPF 项目能编译。
3. 准备 sherpa-onnx Windows C API 包，执行 `.\scripts\Build-Native.ps1 -SherpaOnnxRoot C:\path\to\sherpa-onnx`。
4. 确认 SenseVoice 和 VAD 模型已在 `TypeWhale.Windows\Models\`。
5. 执行 `.\scripts\Check-WindowsLayout.ps1`。
6. 运行应用，验证麦克风录音、静音不粘贴、中文识别、目标输入框粘贴和剪贴板恢复。

Windows 版后续优先级：

1. 热键配置 UI 和冲突检测。
2. 非激活录音胶囊与实时音量反馈。
3. 托盘后台生命周期、开机启动和退出菜单。
4. MSIX/installer 打包、签名和卸载策略。
5. 常用 App 粘贴兼容性矩阵。
