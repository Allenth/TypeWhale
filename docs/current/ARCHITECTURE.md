# TypeWhale Pro 当前架构

更新：2026-10-06。维护：技术负责人／本轮实施者。适用基线见 [入口](README.md)。这是当前架构摘要与决策入口；[迁移前架构全文](../ARCHITECTURE.md) 保留细节与历史，使用旧细节前需核对实现。

2026-09-11：撤回 Build 896 的 MeloTTS worker、受管目录注册、启动／声音页预热及分段播放接入，恢复 `fed982ff`（Build 895）运行逻辑。App 不再注册或启动 MeloTTS；磁盘上既有 Melo 模型及 Python 资产保留但不激活，不把磁盘占用混同为运行内存。现有设置归一逻辑将 Melo voiceID 回退为 ZipVoice 默认音色；ASR/VAD 内存策略不变。严重稳定性反馈与验证见 [开发日志](DEVELOPMENT_LOG.md)。

## 分层与实现入口

采用轻量 Clean Architecture、Coordinator／Use Case、Strategy、State Machine、Adapter／Port；不进行无产品收益的整体框架重写。

| 层 | 职责 | 实现入口 |
| --- | --- | --- |
| Presentation | AppKit 窗口、胶囊、交互与显示投影 | [界面目录](../../native/Sources/Presentation/) |
| Application | 会话状态、识别收尾、截图、粘贴、取消和任务协调 | [协调层](../../native/Sources/Application/)、[最终交付](../../native/Sources/Application/FinalDeliveryUseCase.swift) |
| Domain／Core | 模型选项、发送规则、任务身份、提示词与纯策略 | [领域目录](../../native/Sources/Domain/)、[智能模型](../../native/Sources/Core/SmartInput/SmartAIModel.swift) |
| Infrastructure | 音频、ASR、OCR、文件、权限、Keychain、子进程与远端适配 | [基础设施](../../native/Sources/Infrastructure/) |

视图不得决定最终文本来源、provider 回退或粘贴安全；底层服务不得凭 UI 显隐决定产品生命周期。

## 语音数据流与最终权威

```text
快捷键 → 创建任务并保存目标 → 完整录音 + 本地实时预览
→ 按所选 ASR 决定完整结果 → 可选整理／翻译 → 受保护写回
→ 最近转录／归档使用同一权威结果
```

- SenseVoice 提供实时预览。最终也选择 SenseVoice 且“停止后重新识别整段录音”关闭时，可复用停止时的完整实时缓存；不应再写成“所有输入必须重新整段 ASR”。
- 选择其他 ASR 时，必须运行该模型处理完整录音；不得以 SenseVoice 缓存替换其短、空或失败结果。模型失败显示识别失败，不进入粘贴。
- 完整转录快照与可见胶囊投影是不同契约。显示可以只保留近期后缀，最终交付不能使用截断文本、动画进度或窗口状态。
- 重叠矫正为默认关闭的设置；不可恢复已退役的长录音实验开关。当前产品单次上限五分钟。
- 收尾优先处理完整尾段、取消和任务有效性；旧回调不能进入新会话。预览调度、边界与公平性细节保留在旧架构及实现中，迁移不授权改变算法。
- `RecordingStopHandoff` 只拥有“接受停止 → 音频封口 → 捕获该任务候选快照”的短阶段；`SpeechWorkflowState` 继续拥有后续 VAD、最终识别、整理和粘贴。不同输入入口的替换请求必须等待短交接完成，不能直接覆盖旧 `activeSession`。
- shadow 与 production 候选在释放旧 `activeSession` 前按任务冻结并传给最终识别。旧任务的 VAD／识别回调不得再读取、完成或取消当前新录音的全局 preview runtime；重复停止和陈旧完成只记录并忽略。
- Fn 手势以同一 press 的 CGEvent 单调时间为分类权威：450ms 以下为短按 toggle，达到阈值为 hold；主队列 threshold work item 只负责尽早启动 hold，不再决定 release 的分类。物理事件时间异常时回退本地观察时钟，press ID 隔离重复 down 和陈旧 timer。

### 小米遥控器输入侧路径

```text
CoreBluetooth ATVV 控制／音频包 → 严格帧校验 → IMA ADPCM → PCM16
→ AudioRecorder 外部音频入口 → 既有 ASR／整理／翻译／写回
```

- `RemoteBluetoothController` 只连接已配对且公开 ATVV 服务匹配的设备，负责能力协商、语音包、有限重试与不含设备标识的状态；v1.0 由 AUDIO_STOP 显式结束并忽略重复 START_SEARCH，v0.4 只在 AUDIO_START 后保留第二次 START_SEARCH 的旧 toggle-stop。它不是通用蓝牙录音器。
- `RemoteInputCoordinator` 持有遥控器会话令牌，并只在 `SpeechInputCoordinator` 空闲时开启外部 PCM 会话。普通麦克风和遥控器共用识别后半程，但音频来源与任务身份保持显式。`RemoteActionCatalog` 是当前 10 项 canonical action ID、descriptor、family、按钮适用性与执行语义的唯一目录；`RemoteButtonAction` 只作为 Build 913 调用兼容外壳。`RemoteButtonMapping` 的内部真源是 schema 2 `RemoteBinding`，包含 action revision、`remote.primaryPress` trigger 和版本化无参数 payload，界面与旧调用继续通过兼容投影读取相同行为。
- `RemoteInputSettingsStore` 优先逐键读取 `typewhale.remote.button-mapping.v2`，缺失或非法键回退合法 v1，再回退该键默认；v2 根损坏时整份从 v1 恢复。首次仅有 v1 时写入等价 v2 但保持 v1 原始字节，R0 用户保存会双写当前 10 项，使 Build 913 回滚仍能读取最近配置；两个 key 均不删除。`RemoteMappingMigration` 是唯一持久化编解码入口；当前无法识别的未来 action、按钮、revision、trigger 或 payload 以 opaque binding 留在映射中，不参与运行时执行，修改其他键时原样保留，明确改动对应键或恢复全部默认时才替换。`RemoteButtonActionDispatcher` 只验证 descriptor 并按 keyboard/system/TypeWhale family 路由到独立 executor port，不持有 CGEvent、UserDefaults、HID 或 UI。每次物理 down 记录一个脱敏终态，只含按钮、canonical action ID、binding schema、family 和稳定结果码。
- `XiaomiRemote2ProHIDProfile` 独占 RC003 VID/PID 与 13 个已核证 usage（包括 menu `0x65`）；`RemoteHIDEventReducer` 保持设备无关。`RemoteHIDMonitor` 继续以非独占方式旁听已知遥控器 HID usage，不 seize 整台设备。每次物理按下由 `RemoteButtonActionCycleTracker` 锁定完整 binding，抬起前修改设置也不会让本次 PTT、抑制和执行语义分裂。`.system` 直接放行；其他映射在 180ms 内用 HID 与 CGEvent 的事件时间、观察时间双重相关来吞掉对应 down／repeat／up，再由带专用 userData 的合成键执行动作，物理键盘和 TypeWhale 合成事件不会被误吞。电源键使用 RC003 服务级 `UserKeyMapping` 临时中和为 F20，只有应用、回滚和恢复全部成功才接受自定义映射，停用／挂起时恢复原值。
- RC003 语音键的 page 7 / usage 62 会生成 Keyboard F5 并触发前台文本补全，因此既有专用路径仍在 120ms 内武装一次来源归属，由 CGEvent tap 选择性吞掉对应 F5 down/up；物理键盘 F5 保留。匹配按压在产品最长 5 分钟录音期间持续归属，310 秒丢失 up 保险只负责最终复位；遥控器总开关关闭时，启动和睡眠唤醒都保持 HID 监听停止。若 RC003 固件直接发送 `AUDIO_START` 而未先发送 `START_SEARCH`，控制器只在同一 120ms 窗口内与 voice HID down 配对后启动外部 PCM；两个回调顺序均可，voice up 会清除未配对缓存，无来源或超时音频继续失败关闭。
- 遥控器 Presentation 以 `RemoteInspectorView` 装配页面，连接概览、语音链路、按键映射、权限／排障和文案格式化分别位于独立组件；`MainViewController+Remote.swift` 只保留 callback wiring 与 snapshot 转发。该分层不改变上半页顺序或含义。
- `RemoteButtonPresentation` 与 `RemoteButtonActionPresentation` 是按键／动作中文文案和分组目录的纯格式化边界；映射控件与 `RemoteButtonGuideView` 都读取同一份 `RemoteInputSnapshot.mappings`。`RemoteButtonPreviewPopUpButton` 只把界面点击投影为页面内 preview，既不持久化也不执行动作；物理 down/up 通过 snapshot 投影到同一图示。`XiaomiRemote2ProDiagramSpec` 只保存归一化锚点与左右顺序，`RemoteControlIllustrationView` 只负责可选本地图片、缺图占位、连线与单键按压效果；公开源码不附带受限产品照片。这些 Presentation 类型不读取 HID、UserDefaults 或语音状态。
- 当原生遥控器功能启用且普通录音仍明确选中旧 `MiRemoteV` 虚拟设备时，兼容策略一次性迁回系统默认麦克风，避免 Fn 路径录到静音；其他手动音频设备不迁移。
- 原始遥控器语音不持久化为产品数据，日志不得记录蓝牙地址、UUID、原始帧或转录素材。页面只显示经过约束的设备名、型号、电量、信号和管线状态。
- 本路径不包含 SayAll、虚拟音频驱动、helper 进程或其视觉资产；协议参考与许可证边界记录在 [第三方声明](../../THIRD_PARTY_NOTICES.md)。

## 模型与运行时

| 功能 | 当前集成 | 关键边界 |
| --- | --- | --- |
| 最终 ASR | SenseVoice int8、Parakeet TDT 0.6B v2、Fun-ASR Nano、Qwen3-ASR 0.6B／1.7B MLX 8-bit | 枚举以 [模型注册](../../native/Sources/Infrastructure/ASR/ASRModelRegistry.swift) 与 [受管清单](../../native/Sources/Infrastructure/Models/ManagedASRModelCatalog.swift) 为证据；就绪依赖本机资产 |
| 智能文字 | 自管 Qwen3-4B-Instruct-2507 4bit、DeepSeek v4 flash | 整理和语音翻译走 [选择引擎](../../native/Sources/Infrastructure/SmartRewrite/SelectedSmartAITextEngine.swift)，截图翻译遵循同一选择 |
| 本地声音扩展 | ZipVoice Distill INT8、四款资格参考音色 | [声音目录](../../native/Resources/tts_model_catalog.json) 与共享 worker；不是已完成所有设备听感验收的声明 |

Qwen 资产位于用户 Application Support 的 TypeWhale Pro 模型目录。受管清单固定版本、文件大小和 SHA-256，运行时离线加载，不能依赖用户 Ollama／LM Studio。旧 Ollama、GPT-OSS 及退役 ASR／TTS 候选不属于当前用户菜单；移除集成不删除用户外部安装的模型。

保存的有效 Qwen／DeepSeek 选择保留；缺失、未知或旧 Ollama 选择在 Qwen 就绪时迁移至 Qwen，否则迁移至 DeepSeek。迁移不意味着自动具备 API Key。本地请求失败走既有原文恢复路径，不暗中换成付费云模型。

模型目录证据：[受管 LLM 清单](../../native/Sources/Infrastructure/SmartRewrite/ManagedLLMModelCatalog.swift)、[下载校验](../../native/Sources/Infrastructure/SmartRewrite/ManagedLLMDownloadManager.swift)。完整性校验存在不等于所有第三方模型的商业再分发已经通过。

本地整理模型检测由 [LocalModelHealthCheckService](../../native/Sources/Infrastructure/SmartRewrite/LocalModelHealthCheckService.swift) 顺序执行真实 `import mlx_lm`、受管模型大小／SHA-256 校验、共享 Worker 预热和固定最小生成。App 启动只做 Python 文件级轻量定位，不启动深度导入；用户点击检测后才在后台核对固定依赖版本与真实导入，探针有 15 秒硬超时、进程终止保护和有界 stderr。不能再以包元数据或 Worker 进程存在代替健康结论，也不能让深度探针阻塞 App 启动。

轻量定位、深度探针和共享 Worker 必须绑定候选顺序中的同一个首个可执行 Python；该候选验证失败时不得用后备候选制造通过。用户主动选择 Qwen 时也先在后台执行同一深度探针，只有运行时与模型完整性都通过才保存选择；失败保持原模型并显示原因。

检测复用生产 Worker；预热和最小生成分别使用包含 active／pending 的原子 idle-only 预约，正式请求已执行或已排队时立即返回 `runtime_busy`，不在其后排队。若检测进行中出现正式请求，完成当前短阶段后不再启动下一阶段。不写用量账本，也不把固定提示或生成正文交给 UI。

预热、prefill 和检测请求均通过统一响应校验检查协议版本、取消、`ok` 与必要的非空正文；`ok=false` 必须记录失败，禁止产生指标为 `-1` 的成功事件。检测诊断只包含 App／系统版本、模型 ID、阶段、稳定错误码、耗时、可用性能指标和脱敏底层错误；显式复制前不接触剪贴板。检测失败不改变正式输入现有的原文安全回退，不切换到 DeepSeek，不修复或删除运行时／模型资产。

## VAD、内存和音频控制

Silero 负责语音判定；能量与频带用于视觉反馈，不能恢复为 ASR 人声权威。VAD 异常不得靠无声幻觉制造成功。

ASR／VAD 保持热态，不增加空闲卸载计时器。高内存安全网阈值为 `min(20GB, max(2GB, 物理内存 × 25%))`，仅空闲可执行；flush 后立即 reload／warmUp，保留 30 秒冷却。录音、识别、整理、粘贴中不得释放。Qwen 常规使用也保持热态，其取消和生命周期释放仅针对 TypeWhale 自有进程。

录音降音量目标为 0，连续录音保留首次音量所有权；结束恢复遵守延迟与渐进过程，用户手调优先。媒体暂停只在能确认正在播放且同一播放器时执行和恢复；未知状态安全降级，不盲发 toggle。内部合成媒体键必须带来源标记，避免触发快捷键。

证据：[内存监测](../../native/Sources/Infrastructure/Diagnostics/MemoryMonitor.swift)、[输出音量](../../native/Sources/Infrastructure/Audio/OutputAudioDucker.swift)、[媒体控制](../../native/Sources/Infrastructure/Audio/SystemMediaPlaybackController.swift)。媒体状态读取使用非公开 MediaRemote 能力；Mac App Store 路线需另行处理，见发布清单。

## 文本、截图与写回边界

整理只处理素材，不执行素材里的问题或命令。保留用户的人称、情绪、约束、顺序、例子与确定的自我修正。非空返回不再经过语义保真评分拒绝；空输出、超时、协议与取消仍是有效性边界。提示词修改需通过实际场景回放，不能仅验证字符串存在。

截图、OCR、语音翻译分别维持自己的任务和提示词语义。语音翻译由 `SmartRewriteSafetyPrompt.translationSystemPrompt` 提供跨本地／云端引擎的系统级忠实边界，并由 `SmartTranslationPromptBuilder` 在可编辑语气模板之后再次声明最高优先级：保持原文句子类型、语义和说话人立场，禁止新增回应、确认、寒暄、语气前缀或说话轮次。自然聊天与社交风格只能改变译文措辞，不能把问句改成“先回答再复述问题”。截图翻译保留 OCR 行标识与布局约束，不能复用成普通语音翻译规则。截图不应中断语音或无故激活主窗口。

自动发送在粘贴完成后运行独立协调器；切换目标、取消、开始新录音和后续任务使旧动作失效。Esc 和鼠标右键只在活动倒计时被消费，右键 down／up 由纯 gate 成对管理，未活动时保留前台应用原行为。配置由 [AutoSendDomain](../../native/Sources/Domain/AutoSendDomain.swift) 限定，流程见 [倒计时协调器](../../native/Sources/Application/AutoSendCountdownCoordinator.swift)。

闪念与知识归档目录由 `BacklogDirectoryStore` 管理。已有 `backlogDirectory` 设置继续作为权威；没有保存值时才使用当前用户的 `~/Documents/TypeWhale/需求池` 并按需创建。生产默认值、仓库配置和协作文档不得包含开发者个人主目录。

## OpenClaw 与本地朗读

OpenClaw 是显式触发的独立对话路径，无默认激活键；显示对话流但不粘贴前台。CLI／Gateway 失败不能改变普通输入、翻译或 TTS 环境。

[OpenClawClient](../../native/Sources/Infrastructure/OpenClaw/OpenClawClient.swift) 在每次 CLI 启动前验证兼容 Node，仅对 CLI PATH 前置一个有效目录。版本探测有 0.5 秒边界并处理挂起进程，结果不跨启动缓存；共享 TTS 环境保持继承 PATH 顺序。

ZipVoice 为可选输出能力，不是启动或 ASR 依赖。朗读前检查本机资产，不在说话过程中下载运行时。声音页恢复原有单次合成；OpenClaw 恢复原有分段、默认 1,200 字文本边界与取消行为，不将此次回退描述为新增的全文完整性修复。音频后处理不裁剪已生成的语音；参考音色的采样格式、长度和旧音色兼容例外仍按历史资格及实现核验。

## 数据与隐私边界

| 数据路径 | 当前工程边界 |
| --- | --- |
| 本地 ASR／Qwen／ZipVoice | 推理在本地；首次模型／运行时准备可能需要下载，不把本地优先写成全程零网络 |
| DeepSeek | 用户选择并配置 Key 后，对应整理／翻译文本发送到该服务；不是本地失败的自动备援 |
| OpenClaw | 文本发送至本机 CLI／Gateway，后续是否使用云服务取决于其配置；不能承诺该路径全离线 |
| API Key | 使用 Keychain；不写入普通日志或版本库 |
| 可观测性 | 已有 consent、脱敏及门面，默认 transport 为 no-op；不是已接入 Sentry／TelemetryDeck 的线上系统 |
| 诊断与回放 | 只记录所需诊断，不上传音频、截图、OCR、剪贴板、Key、路径或原始转录；含用户素材的实验文件不得提交 |

证据：[可观测性门面](../../native/Sources/Infrastructure/Observability/ObservabilityClient.swift)、[默认传输](../../native/Sources/Infrastructure/Observability/ObservabilityTransport.swift)。[SECURITY](../../SECURITY.md) 的旧“未来功能”措辞不能替代本表；正式隐私政策与第三方条款仍需发布专项复核。

## 决策与验证

本次迁移保留选中模型最终权威、显示与完整文本分离、热加载、高内存安全网、只整理不代答、输出侧实验隔离等既有决策。没有执行新架构迁移或性能调参。

变更时须同步本文件、PRODUCT 中的可见边界与 DEVELOPMENT_LOG 中的证据；历史计划只作来源。测试入口与真实安装版要求统一见 [RELEASE_QA](RELEASE_QA.md)。
