# TypeWhale Windows 开发计划

本文用于把当前 Windows MVP 代码交接给 Windows 开发同学。它记录当前真实状态、主链路、开发优先级、验收标准和已知风险。

## 当前真实状态

- Windows 目录已建立在 `windows/`，使用 `.NET 8 WPF`。
- 已有 MVP 主链路代码：全局热键、录音、VAD、final ASR、粘贴和最近历史。
- SenseVoice 与 Silero VAD 模型已放在 `windows/TypeWhale.Windows/Models/`。
- Windows native bridge 的 CMake 入口和 PowerShell 构建脚本已经准备好。
- 当前尚未在 Windows 真机上完成编译、DLL 加载、麦克风、热键和粘贴验证。
- macOS 的 `.dylib` 不能用于 Windows，Windows 需要单独准备 `.dll` 运行库。

## 产品基线

Windows 版第一阶段不要扩展成新产品，先复刻 TypeWhale 的稳定主链路：

```text
全局快捷键录音
-> 生成完整 WAV
-> Silero VAD 判断是否有人声
-> SenseVoice final 本地识别
-> 写入剪贴板
-> 发送 Ctrl + V
-> 尽量恢复原剪贴板
```

实时预览、胶囊动画、AI 改写、热词和开发者词库都不是 P0。P0 的目标是先让 Windows 版可靠输入中文。

## 当前架构

```text
TypeWhale.Windows/
├── Application/
│   └── SpeechInputCoordinator.cs
├── Domain/
│   └── ASRConfiguration.cs
├── Infrastructure/
│   ├── ASR/NativeSenseVoiceBridge.cs
│   ├── Audio/WavRecorder.cs
│   ├── Hotkeys/GlobalKeyboardHook.cs
│   └── Paste/WindowsPasteCoordinator.cs
└── Presentation/
    └── MainWindow.xaml(.cs)
```

职责边界：

- `Presentation`：只负责窗口展示、按钮和最近记录绑定。
- `Application`：负责录音任务编排和状态流转。
- `Infrastructure/Audio`：只负责 WAV 录制。
- `Infrastructure/ASR`：只负责加载 native DLL、VAD 和 final ASR。
- `Infrastructure/Hotkeys`：只负责系统热键事件。
- `Infrastructure/Paste`：只负责剪贴板写入、发送 `Ctrl + V` 和恢复。

## P0：让 Windows 主链路跑通

目标：在 Windows 真机上证明 MVP 可用。

### P0-1 编译 WPF 项目

任务：

- 安装 .NET 8 SDK。
- 在 Windows 上运行：

```powershell
cd windows
.\scripts\Build-App.ps1
```

验收：

- `dotnet restore` 成功。
- `dotnet build` 成功。
- 没有 XAML、nullable、平台目标或 NuGet 还原错误。

### P0-2 构建 native bridge 和 DLL 布局

任务：

- 准备 sherpa-onnx Windows C API 包。
- 确认包内有 `include/sherpa-onnx/c-api/c-api.h`。
- 确认包内能找到：
  - `sherpa-onnx-c-api.dll`
  - `onnxruntime.dll`
- 运行：

```powershell
cd windows
.\scripts\Build-Native.ps1 -SherpaOnnxRoot C:\path\to\sherpa-onnx
.\scripts\Check-WindowsLayout.ps1
```

验收：

- `TypeSpeakerNativeASR.dll` 构建成功。
- 三个 native DLL 被复制到 `TypeWhale.Windows\runtimes\win-x64\native\`。
- `Check-WindowsLayout.ps1` 通过。

### P0-3 验证录音与音频文件

任务：

- 运行 Windows App。
- 按 `Ctrl + Alt + Space` 开始/停止录音。
- 验证长按说话、松开停止。
- 检查录音文件输出。

验收：

- App 不崩溃。
- 能生成 16 kHz mono WAV。
- 静音录音不会粘贴空文本。
- 麦克风被占用或无输入时有可理解提示。

### P0-4 验证 VAD 和 final ASR

任务：

- 用 2 秒、5 秒、10 秒中文语音测试。
- 分别测试普通话短句、标点停顿和较慢语速。

验收：

- 有人声时进入 final ASR。
- 无人声时停止在“没有检测到人声”。
- 中文短句能稳定识别。
- ASR 错误能显示到 UI，不直接崩溃。

### P0-5 验证粘贴主链路

任务：

- 在记事本、浏览器输入框、微信/企业微信、Word 中测试。
- 测试旧剪贴板恢复。
- 测试目标窗口切换或焦点丢失。

验收：

- 识别文本能粘贴到当前输入框。
- 旧剪贴板尽量恢复。
- 粘贴失败时不清空用户剪贴板。
- 连续两次录音不会把前一次文本粘贴到后一次目标。

## P1：补齐产品体验

目标：从“能跑”变成“可日常试用”。

### P1-1 状态机和任务隔离

- 引入明确的录音任务状态：`Idle`、`Recording`、`CheckingSpeech`、`Recognizing`、`Pasting`、`Failed`。
- 每次录音冻结 task id、音频路径、目标窗口和粘贴回调。
- 连续录音时，旧任务不能抢焦点粘贴。

### P1-2 热键配置和冲突检测

- 默认保留 `Ctrl + Alt + Space`。
- 增加热键录入 UI。
- 检测系统或 App 冲突。
- 明确 Windows 上通常不能捕获 Fn 的限制。

### P1-3 后台生命周期

- 增加托盘图标。
- 支持关闭窗口后后台运行。
- 增加退出菜单。
- 增加开机启动开关。

### P1-4 录音反馈

- 先做简单非抢焦点小浮窗或状态条。
- 后续再评估是否移植 macOS 胶囊和七频段波形。
- 录音反馈不得抢目标输入框焦点。

### P1-5 粘贴兼容性矩阵

至少覆盖：

- 记事本
- Chrome/Edge 输入框
- 微信/企业微信
- Word
- VS Code
- 远程桌面或虚拟机输入目标

记录每个目标的：

- 是否能粘贴。
- 是否会粘旧剪贴板。
- 是否需要延迟。
- 是否会破坏剪贴板恢复。

## P2：发布和商业化准备

目标：进入可分发、可安装、可回滚。

- 选择安装形态：MSIX、传统安装器或便携版。
- 代码签名证书和 SmartScreen 风险评估。
- 模型授权复核，尤其是 SenseVoice/FunASR 商业再分发。
- 用户数据目录和卸载清理策略。
- 崩溃日志、诊断日志和隐私说明。
- Windows Defender/杀软误报检查。
- 自动更新方案评估。

## 技术风险

### native DLL 风险

Windows 需要严格匹配 x64、Release/Debug、CRT 和依赖 DLL。DLL 找不到或 ABI 不一致时，ASR 会在运行时失败。

缓解：

- 优先用 `Check-WindowsLayout.ps1` 检查文件。
- 首次加载 native bridge 时输出明确错误。
- 不要混用 macOS 动态库。

### 热键风险

低层键盘 hook 可能被安全软件、远程桌面或高权限窗口影响。

缓解：

- P0 先验证普通桌面环境。
- P1 再补热键配置和冲突检测。

### 剪贴板风险

Windows 剪贴板可能被目标 App、输入法、远程桌面或安全软件异步占用。

缓解：

- P0 先保留简化恢复策略。
- P1 建立兼容性矩阵后，再决定是否引入粘贴模式或更严格事务。

### 音频设备风险

通话软件、蓝牙耳机和虚拟声卡可能切走输入设备。

缓解：

- P0 先用系统默认输入设备。
- P1 增加输入设备选择和诊断。

## 首次交接清单

Windows 开发同学拿到代码后，按这个顺序执行：

1. 阅读 `windows/README.md`。
2. 阅读 `windows/WINDOWS_TEST_HANDOFF.md`。
3. 阅读本文档。
4. 在 Windows 真机执行 `.\scripts\Build-App.ps1`。
5. 准备 sherpa-onnx Windows C API 包。
6. 执行 `.\scripts\Build-Native.ps1`。
7. 执行 `.\scripts\Check-WindowsLayout.ps1`。
8. 跑通 `录音 -> VAD -> final ASR -> 粘贴`。
9. 把失败点记录回本文档或新增测试记录。

## 当前不做

- 不做 AI 改写。
- 不做实时预览参与最终输出。
- 不做云端识别。
- 不做 Windows Fn 键承诺。
- 不做发布级安装包，直到 P0 主链路在 Windows 真机稳定。
