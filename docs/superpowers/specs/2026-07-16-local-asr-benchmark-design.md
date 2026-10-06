# TypeWhale 本地 ASR 模型测速设计

日期：2026-07-16

状态：已批准，实施中

决策：采用“模型注册表 + 独立引擎适配器”的隔离测速架构

## 1. 产品目标

TypeWhale 在本机已经存在多套完整 ASR 权重，但它们分属 sherpa-onnx、FunASR 和 MLX 等不同运行引擎。用户需要在真实安装版中用同一段录音逐个测试这些模型，直接比较速度、资源占用、识别文本和热词效果，再决定哪些模型值得进入正式语音输入链路。

本功能包含两个相互隔离但共享准入事实的产品表面：一个只在本机运行、不会自动粘贴的评测入口，以及扩充后的正式“识别模型”下拉框。测速负责产生模型是否可用的证据；正式下拉框只启用已经通过完整准入的模型。SenseVoice 继续作为默认稳定链路和单次安全 fallback。

## 2. 当前痛点

- 本地权重分散在 App Resources、Application Support、Hugging Face cache 和 ModelScope cache，现有 UI 不能统一发现和验证。
- “模型文件存在”不等于“运行环境可用”，尤其是 MLX 模型当前缺少受管运行时接线。
- 不同引擎的热词格式不同，不能把统一字符串直接传给所有模型。
- 重新录音会引入语速、音量、停顿差异，无法公平比较速度和准确度。
- 正式 ASR 链路带有 fallback；测速如果自动回退 SenseVoice，会掩盖目标模型的真实失败。

## 3. 范围

### 3.1 In scope

- 在“模型”页增加独立的“ASR 模型测速”入口。
- 录制或导入一段固定 WAV，并在整个评测会话中复用。
- 发现、校验并展示所有本机完整 ASR 模型权重。
- 为 sherpa-onnx、FunASR、MLX 建立隔离的测速适配器。
- 串行运行选定模型，显示冷启动、热态转写、总耗时、实时系数、峰值内存、识别文本和热词命中。
- 从正式热词库复制一份临时测试热词，允许临时修改，但不回写正式词库。
- 按目标模型原生格式序列化热词，并对热词能力做格式验证与行为验证。
- 为失败模型显示准确且可操作的原因，不做静默 fallback。
- 保存本地评测结果，支持清除和重新测试。
- 扩充正式“识别模型”下拉框，列出全部已登记 ASR 候选。
- 只有通过文件、运行时、真实 WAV、取消和资源释放验证的候选才能在正式下拉框中启用并持久化。
- 正式 final ASR router 使用与测速相同的已验证 adapter，不重新实现另一套模型调用逻辑。

### 3.2 Out of scope

- 除用户主动选择的 final ASR adapter 外，不改变日常录音、实时预览、智能整理、翻译、历史记录或粘贴流程。
- 不增加在线 ASR，也不上传音频、热词或结果。
- 不以测速面板替代正式模型管理器。
- 不在本轮恢复多小时长录音产品能力；测速样本只验证完整 WAV 转写。
- 不把 VAD、标点模型或 forced aligner 当作独立 ASR 候选。
- 不用转写后文本替换、词典纠错或智能整理冒充热词效果。

### 3.3 Do not touch

- SenseVoice 仍是默认稳定 final ASR，升级后不得自动切换用户当前选择。
- 现有三个正式 final 后端及其一次 SenseVoice fallback 语义保持不变；新增后端必须遵守相同安全边界。
- 现有 ASR/VAD 热加载与高内存 flush 后立即 reload 的治理规则保持不变。
- 测速运行时、测试音频和结果不能进入正式语音任务状态机。
- 不复用或扩大 `SpeechInputCoordinator` 的职责；测速由独立 coordinator 管理。

## 4. 已知候选清单

候选以“模型权重 + 推理引擎”为唯一身份；同名模型的不同引擎版本分别测速。

| 候选 | 引擎 | 当前已知状态 | 热词分类初值 |
|---|---|---|---|
| SenseVoice int8 | 原生 sherpa-onnx | 已用于正式链路 | 不支持 |
| Qwen3-ASR 0.6B int8 | 原生 sherpa-onnx | Application Support 权重完整 | 待运行时验证 |
| Parakeet TDT 0.6B v2 int8 | 原生 sherpa-onnx | Application Support 权重完整 | 待运行时验证 |
| Fun-ASR Nano 2512 | FunASR | 已完成真实 WAV 与 hotwords 验证 | 原生列表参数 |
| Paraformer Contextual | FunASR | 已完成真实 WAV 与 hotword 验证 | 原生字符串参数 |
| Paraformer zh | FunASR | 权重完整 | 待格式与 A/B 验证 |
| SeACo Paraformer | FunASR | ModelScope 权重完整 | 待格式与 A/B 验证 |
| Whisper Small | MLX | 本机模型已完成加载验证，接入受管离线运行时 | 仅上下文提示，不计作原生热词 |
| Qwen3-ASR 0.6B 8-bit | MLX | 本机模型已完成加载验证，接入受管离线运行时 | 当前 API 未证实前标记不支持 |
| Qwen3-ASR 1.7B 8-bit | MLX | 本机模型已完成加载验证，接入受管离线运行时 | 当前 API 未证实前标记不支持 |

### 4.1 2026-07-16 集成决策补充

本轮不采用“只登记模型名称”的轻量路径，因为它会让用户选中后实际回退 SenseVoice，形成假可用；也不采用把 MLX 直接链接进 App 进程的路径，因为 Python/MLX 依赖和大模型内存会扩大主进程故障面。继续采用已批准的受管本地 sidecar：SenseVoice 保留原生 sherpa-onnx 路线，Whisper Small 与两款 Qwen MLX 共用受管、离线、持久 sidecar，并通过统一 adapter 进入正式 final ASR 与测速。另一个 session 已完成的本地模型发现与选择语义需要合入，但其“尚未接最终执行器”状态必须由真实执行准入替代。

该清单不是把任意缓存目录都当作模型。注册表必须用必需文件、非零大小、配置可解析和运行时 probe 四层校验决定 `ready`。FSMN-VAD、Silero VAD、CT-Punc 和其他辅助资源只显示为候选依赖，不进入测速排名。下载引用、临时目录、残缺快照和空权重不进入列表。

## 5. 总体架构

### 5.1 `ASRBenchmarkModelRegistry`

注册表是候选清单和能力元数据的唯一来源。每个 descriptor 至少包含：

- 稳定候选 ID、显示名、引擎类型和模型版本。
- 权重发现位置与必需文件规则。
- 是否为 bundled、managed 或 external cache。
- 运行时要求与 readiness probe。
- 音频约束：采样率、声道、最大时长及是否需要转换。
- 热词策略和经过验证的能力状态。
- 依赖模型，例如 CT-Punc。

注册表与正式选择状态分离，但它同时为测速 UI 和正式下拉框提供描述符。候选进入注册表只代表“本机发现”；只有 `productionReady` 准入状态才能被正式选择和持久化，避免缓存目录或未验证运行时自动变成生产后端。

### 5.2 `ASRBenchmarkEngineAdapter`

所有引擎实现同一个窄接口：

- `probe(model)`：检查权重、运行时和关键依赖。
- `warmUp(model)`：显式加载模型并返回加载耗时。
- `transcribe(request)`：转写固定 WAV，返回原始文本、模型报告和耗时。
- `sampleResources()`：获取 sidecar 或本进程的峰值 RSS 等指标。
- `cancel()`：终止当前请求。
- `unload()`：退出或释放当前测速引擎。

实现分为三类：

1. `SherpaBenchmarkAdapter`：复用原生 sherpa-onnx 动态库，但使用独立 recognizer，不改动正式 `NativeASR` 的当前模型。
2. `FunASRBenchmarkAdapter`：使用 TypeWhale 受管 Python 运行时和专用 JSONL sidecar；可复用已验证依赖版本，但使用独立 benchmark 请求/响应协议。
3. `MLXBenchmarkAdapter`：使用独立、版本锁定、校验完整的受管 MLX sidecar，不依赖用户系统 Python，不允许运行时自动从网络补下载权重。

### 5.3 `ASRBenchmarkCoordinator`

Coordinator 独立拥有录音、候选选择、串行调度、取消、结果聚合与临时文件生命周期。它不能调用正式 final recognition use case，也不能写入最近转写、剪贴板或粘贴队列。

同一时刻只允许一个模型运行。开始下一个模型前先终止或卸载上一候选，等待资源回落后再加载下一候选，防止多个大模型叠加造成内存和速度失真。

### 5.4 正式 final ASR 路由

扩充后的正式下拉框显示注册表中的全部 ASR 候选，并区分：

- **可使用**：已通过生产准入，可选择并持久化。
- **验证中**：权重存在但尚未完成真实转写或资源释放验证，显示但禁用。
- **不可用**：文件、运行时或依赖失败，显示但禁用，并提供进入测速页查看原因的入口。

用户选择可使用候选后，正式 final router 通过同一个 engine adapter 执行完整录音转写。实时预览继续固定使用 SenseVoice，不因 final 模型选择改变。正式请求失败时只允许一次 SenseVoice fallback，并在状态详情中明确告知实际使用了 fallback；测速请求永远不 fallback。

生产准入至少要求：权重完整、运行时固定、冷/热态真实 WAV 成功、取消成功、资源释放成功、超时边界明确。热词支持不是进入下拉框的必要条件，但能力标签必须真实；不支持热词的候选收到空热词配置。

## 6. 热词契约

### 6.1 强类型策略

测速核心使用 `BenchmarkHotwordStrategy` 表达能力，而不是一个通用字符串：

- `unsupported`：不向模型传任何热词参数。
- `nativeList`：适配器传原生字符串数组，例如 Fun-ASR Nano 的 `hotwords`。
- `nativeSpaceSeparated`：按模型要求完成转义和空格拼接，再传 `hotword`。
- `sherpaHotwordFile`：生成临时 UTF-8 热词文件，并按 sherpa 模型实际要求编码 token、分数或 boost。
- `contextPrompt`：仅作为上下文提示，UI 明确标注“非原生热词”，不参与原生热词榜。

每个策略负责规范化、去空、去重、长度限制、字符集检查和临时文件清理。包含空格的英文短语不能因简单空格拼接被错误拆分；适配器必须采用该模型官方格式允许的短语表示法。无法无损表达的词条在运行前被拒绝，并显示具体词条和原因。

### 6.2 两级验证门禁

只有同时满足以下条件，候选才能显示“原生热词支持”：

1. **格式验证**：官方接口、当前锁定运行时和本地调用路径均确认接受该参数格式；sidecar 回显实际采用的策略、词条数量和安全摘要。
2. **行为验证**：同一 WAV 连续执行无热词与有热词 A/B；结果、日志和原始响应证明目标词进入模型或解码上下文。行为没有变化不自动判失败，但不能升级为“已验证有效”。

禁止以下做法：

- 转写完成后替换相似词。
- 把 DeveloperTermNormalizer 或智能整理结果当作 ASR 热词命中。
- 把 Whisper `initial_prompt` 与原生 contextual biasing 合并排名。
- 把在线 Qwen API 的 context 参数推断为本地 MLX 权重能力。
- 在未知格式时试传参数并吞掉错误。

## 7. 用户体验

### 7.1 入口

“模型”页保留现有模型管理列表，在其上方或标题区增加“ASR 模型测速”按钮。打开独立窗口，不在主设置页塞入完整评测表格。

现有“识别模型”下拉框同步扩充为全部注册候选。菜单项显示模型名和引擎后缀，避免两个 Qwen3-ASR 0.6B 版本混淆，例如“Qwen3-ASR 0.6B · Sherpa int8”和“Qwen3-ASR 0.6B · MLX 8-bit”。禁用项附带“验证中”或“不可用”，不能通过键盘、旧 UserDefaults 或未知 raw value 绕过准入。

### 7.2 顶部样本区

- “开始录音 / 停止”按钮。
- “导入音频”作为补充入口。
- 显示时长、采样率、声道和文件大小。
- 可播放、重录、重新导入。
- 新样本会使旧结果标记为过期，但不静默删除。

内部统一生成 16 kHz、单声道 PCM WAV，原始导入文件不被修改。所有候选使用同一个归一化 WAV。

### 7.3 临时热词区

- 初次打开时复制当前正式热词库。
- 用户可在本次评测中添加、删除和恢复正式热词快照。
- 明确提示“仅用于本次测速，不会修改正式热词”。
- 测试开始时冻结一份热词快照，运行中编辑只影响下一次测试。

### 7.4 模型列表

每行展示：

- 模型名、引擎、权重体积。
- 状态：检查中、可测试、运行时未就绪、文件不完整、运行中、完成、失败或已取消。
- 热词徽标：原生支持、待验证、仅上下文提示、不支持。
- 操作：“测试此模型”“无热词/有热词 A/B”“取消”“重试”。
- 结果摘要：冷启动、热态转写、总耗时、RTF、峰值内存、热词命中数。

提供“按当前顺序测试全部”，但仍严格串行。默认排序先轻量后重量，避免一开始加载 1.7B 模型让用户误以为工具卡死。

### 7.5 结果详情

展开行显示：

- 原始识别文本，不经过智能整理。
- 命中和未命中的临时热词。
- 实际热词策略与参数摘要，不记录完整隐私词表到普通日志。
- 冷启动、预热后第一遍、第二遍热态结果。
- 音频时长、RTF 和峰值 RSS。
- 失败阶段、错误类别、建议动作。

## 8. 测速口径

- `coldLoadMs`：目标进程或 recognizer 尚未加载时，从加载开始到 readiness 通过。
- `firstInferenceMs`：预热完成后第一次完整 WAV 转写。
- `warmInferenceMs`：同一模型、同一配置、同一 WAV 的第二次转写。
- `totalFirstUseMs`：`coldLoadMs + firstInferenceMs`。
- `realTimeFactor`：`warmInferenceSeconds / audioDurationSeconds`，越低越快。
- `peakRSSMB`：本次候选进程或本地 adapter 测试阶段峰值常驻内存。

速度排名默认按热态 RTF，同时显示首次使用总耗时。原生热词候选和无原生热词候选分组比较，避免速度榜掩盖产品能力差异。A/B 测试使用相同解码配置；除热词参数外不得改变语言、温度、beam 或采样策略。

## 9. 数据流

1. 用户录制或导入音频。
2. Sample store 生成并校验统一 WAV，计算内容哈希。
3. 用户启动单模型或串行全量测试。
4. Coordinator 冻结 sample hash、热词快照和候选 descriptor。
5. Registry probe 重新检查权重与运行时。
6. Hotword adapter 校验并构造目标模型原生参数。
7. Engine adapter 冷加载、第一次转写、第二次热态转写，并采集资源指标。
8. Coordinator 写入结构化本地结果；UI 只渲染结果模型。
9. 切换候选前卸载上一引擎并确认进程退出或资源释放。
10. 用户清除会话时删除测试 WAV、临时热词文件和结果。

正式选择额外遵循：菜单读取注册表生产状态；保存前再次执行 readiness 快速检查；新录音开始时冻结选定 descriptor 和 adapter；final 完成或一次 fallback 后进入既有整理、历史和粘贴流程。运行中切换只影响下一轮录音。

每个异步回调必须携带 benchmark session ID、sample hash 和 run ID。取消、换样本或关闭窗口后，旧回调不得更新 UI 或覆盖新结果。

## 10. 错误处理

测速不允许 fallback。错误必须归类到明确阶段：

- `modelMissing`：权重或配置缺失。
- `modelCorrupt`：大小、校验或解析失败。
- `runtimeMissing`：引擎未安装。
- `runtimeIncompatible`：依赖版本或架构不匹配。
- `dependencyMissing`：例如要求的标点或 tokenizer 缺失。
- `hotwordUnsupported`：目标适配器不支持热词。
- `hotwordInvalid`：词条无法按目标格式无损表达。
- `loadFailed`：模型初始化失败。
- `transcriptionTimedOut`：目标模型超过独立超时。
- `transcriptionFailed`：推理返回错误或空的无效响应。
- `cancelled`：用户取消。

失败不会阻塞下一模型。若 sidecar 崩溃，Coordinator 收集退出码和受限 stderr，销毁进程并继续后续候选。UI 不显示 Python traceback 原文，而显示用户可理解的结论和可展开技术详情。

## 11. 本地数据与隐私

- 测试音频、临时热词和结果只存于 TypeWhale Application Support 的 benchmark 专用目录。
- 文件名不包含热词和识别文本。
- 普通诊断日志只记录候选 ID、阶段、耗时、计数、错误码和不可逆摘要。
- 测速 sidecar 禁止网络补下载；缺少权重或运行时必须明确报告。
- 提供“清除本次测试数据”，并在会话关闭后清理临时热词文件。

## 12. 测试与验收

### 12.1 自动化

- 注册表覆盖全部已知候选，辅助模型不会进入排名。
- 每个候选的必需文件和 runtime probe 有 fixture 测试。
- 热词策略覆盖中文词、英文单词、含空格短语、重复项、非法/过长词条。
- 不支持模型不会收到热词字段。
- 原生列表、字符串和 sherpa 文件格式生成结果符合锁定运行时要求。
- A/B 两次运行除热词参数外配置完全一致。
- 计时和 RTF 计算使用单调时钟。
- 取消、换样本、关闭窗口和 sidecar 崩溃不会产生 stale UI 更新。
- 测速结果不会写入最近转写、剪贴板或正式热词库。
- 未通过生产准入的模型不能被正式下拉框保存。
- 新增正式 backend 的失败只触发一次 SenseVoice fallback，且不会递归重入。
- 录音中切换模型只影响下一轮任务。

### 12.2 真实模型验证

每个完整候选必须在当前 Mac 上：

1. readiness 通过；
2. 冷加载成功；
3. 对固定 WAV 返回非空真实文本；
4. 第二次热态转写成功；
5. 能取消并释放资源；
6. 若宣称原生热词支持，完成无热词/有热词 A/B 并保留证据。

“权重存在但运行时未接通”不能算完成。实现阶段必须接通受管运行时或把该候选明确判为不可运行并说明阻塞；产品交付目标是让当前完整权重全部通过真实转写。

### 12.3 安装版验收

- 从 `/Applications/TypeWhale.app` 打开模型页并进入测速窗口。
- 录制一段包含中英文热词的 15–30 秒音频。
- 同一 WAV 逐个测试全部 ready 候选。
- 每行能看到冷启动、热态速度、RTF、峰值内存、文本和热词状态。
- 运行“测试全部”时严格串行，没有多模型内存叠加。
- 正式“识别模型”下拉框列出所有候选；全部完整且已完成准入的候选可选择，重复模型名带引擎后缀。
- 逐个选择新增候选并完成一次真实快捷键录音，最终文本经过既有整理/粘贴链路正常输出。
- 人为制造一个新增 adapter 失败时，安装版明确提示并只执行一次 SenseVoice fallback。
- 关闭或取消测试后，日常快捷键录音、final ASR、智能整理和粘贴仍正常。
- 深色与浅色主题下信息层级、滚动、展开结果和错误状态可读。

## 13. 完成定义

本功能只有在以下条件同时满足时才可交付验收：

- 所有本机完整 ASR 候选均被注册并显示。
- 每个候选在真实安装版完成固定 WAV 转写，不以 fallback 冒充成功。
- 全部通过生产准入的完整候选出现在正式下拉框并能用于真实 final 录音；默认选择仍保持 SenseVoice 或用户原有选择。
- 所有热词标签与实际目标模型格式一致；未验证能力不得显示为支持。
- 同一 WAV、相同配置和串行资源隔离保证比较公平。
- 测速不会改变正式 ASR 选择、正式热词或任何粘贴行为。
- 聚焦自动化、完整构建、覆盖安装、签名检查和真实 UI 验证通过。

## 14. 依据

- FunASR 官方仓库和示例将 Paraformer 热词作为 `hotword` 参数传入，Fun-ASR Nano 当前本地实现使用其 `hotwords` 接口；最终格式以锁定的 FunASR runtime 和真实 A/B 为准。
- Sherpa-ONNX 官方将 hotwords 定义为 contextual biasing，并有独立热词格式；是否适用于某个具体 recognizer 必须由该模型 adapter probe 确认。
- MLX Whisper 支持 `initial_prompt` 一类解码上下文，但它不是与 Paraformer contextual hotword 等价的能力。
- Qwen3-ASR 官方本地说明支持离线、流式和长音频；本设计不从在线 API 的 context 参数推断 MLX 本地热词能力。
