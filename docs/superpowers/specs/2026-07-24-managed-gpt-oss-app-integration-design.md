# TypeWhale 自管 GPT-OSS App 接入设计

日期：2026-07-24
状态：用户已确认产品方向，待 spec 最终审阅

## 1. 产品目标

把已经完成隔离验证的 GPT-OSS 20B MLX 运行能力接入 TypeWhale Pro，让用户无需 Terminal、LM Studio 或 Ollama 服务，即可在 App 内下载、管理、启用和测试本地直驱模型。

本次同时把本机已有的 `qwen3.6-rewrite:latest` 作为新的 Ollama 整理模型加入现有“整理模型”下拉菜单。

本轮不是把 GPT-OSS 设为默认模型。GPT-OSS 20B 当前仍未通过综合默认模型的严格文字整理准入，只作为用户主动启用的实验模型进入真实整理与翻译链路。

## 2. 使用场景与当前痛点

### 使用场景

- 用户在“模型”Tab 内看到独立的本地直驱模型分区。
- 用户由 TypeWhale 下载并管理 GPT-OSS 20B。
- 用户启用 GPT-OSS 后，真实听写的智能整理和自动翻译由 GPT-OSS 处理。
- 用户关闭 GPT-OSS 后，立即恢复此前选择的 Qwen 或 DeepSeek 模型。
- 用户可以在 App 内查看加载状态、内存和推理性能，并运行安全的合成文本测试。

### 当前痛点

- 隔离验证只能通过 Terminal 脚本启动，还不是产品能力。
- 现有本地整理模型依赖 Ollama HTTP 服务。
- 现有模型页没有展示自管 LLM 的安装、状态和性能。
- `qwen3.6-rewrite:latest` 已安装，但尚未列入整理模型下拉菜单。

## 3. 已确认的产品决策

1. GPT-OSS 位于“模型”Tab，不位于“智能”Tab。
2. “模型”Tab 新增独立的“本地直驱模型（实验）”分区。
3. GPT-OSS 与现有整理模型是互斥切换关系。
4. GPT-OSS 启用后参与真实听写整理和自动翻译。
5. GPT-OSS 不成为默认模型，不迁移老用户设置。
6. 正式产品的模型来源和运行生命周期与 LM Studio 完全无关。
7. 本次开发机允许用已有相同权重做一次 APFS clone 初始化，避免重复下载约 11GB；该外部路径不得进入产品代码、设置或界面。
8. “本地 Qwen3.6 35B Rewrite”加入现有整理模型下拉，继续通过 Ollama 运行。

## 4. 范围

### In scope

- 新增 TypeWhale 自管 MLX LLM provider 和模型路由。
- 新增 GPT-OSS 20B 受管模型清单、下载、校验、取消、删除和状态持久化。
- 新增隐藏 MLX helper 的启动、请求、取消、崩溃恢复和退出清理。
- Harmony 输出只接收合法 `final`。
- GPT-OSS 接入智能整理和自动翻译。
- 模型 Tab 新增独立管理分区。
- 现有整理模型下拉新增 Qwen3.6 35B Rewrite。
- 自动化测试、真实安装版构建、界面复核和真实语音验证。
- 更新架构、开发日志、版本历史和构建记录。

### Out of scope

- 不把 GPT-OSS 设为默认模型。
- 不把 GPT-OSS 接入截图 OCR 翻译；本轮只覆盖文字整理和语音自动翻译。
- 不读取用户历史输入作为模型测试样本。
- 不改变 ASR、VAD、胶囊交互或粘贴语义。
- 不打包或重新分发模型权重到 App bundle。
- 不依赖 LM Studio API、模型目录或私有后端。
- 不替换或删除现有 Ollama、DeepSeek 路径。

### Do not touch

- 不修改、移动、重命名或删除任何外部模型源文件。
- 不干预 LM Studio 或 Ollama 当前运行的模型实例。
- 不触碰当前工作区中其他 session 的未跟踪胶囊概念稿和 `.superpowers/brainstorm` 文件。
- 不恢复自动构建 Stop hook。

## 5. 产品信息架构

“模型”Tab 保持三个一级分区：

1. `ASR 模型`
2. `整理模型`
3. `本地直驱模型（实验）`

### 5.1 现有整理模型下拉

下拉选项调整为：

- 本地 Qwen3.5 2B
- 本地 Qwen3.5 9B
- 本地 Qwen3.6 35B
- 本地 Qwen3.6 35B Rewrite
- DeepSeek v4 flash

新增模型的引擎名为 `qwen3.6-rewrite:latest`，provider 仍为 Ollama。默认模型继续为 Qwen3.5 2B。

### 5.2 本地直驱模型分区

分区包含：

- 受管模型下拉，首个选项为 `GPT-OSS 20B MXFP4 Q8`。
- 实验标签和质量说明。
- 模型安装状态、版本、大小和磁盘位置说明。
- 下载、取消下载、校验和删除操作。
- “启用为当前模型”开关。
- “测试模型”操作。
- 运行状态：未下载、下载中、校验中、可用、加载中、当前使用、失败。
- 最近一次加载时间、首 Token、完整耗时、生成速度和峰值内存。
- 最近错误与重试入口。

### 5.3 互斥切换

- GPT-OSS 开启时，现有“整理模型”下拉禁用，但保留此前选择。
- 分区明确显示“当前由 GPT-OSS 接管整理与翻译”。
- GPT-OSS 关闭后，现有下拉恢复可用，并恢复此前选择。
- 用户切换回现有模型时，GPT-OSS helper 安全退出并释放内存。
- App 重启后恢复用户明确保存的启用状态；若模型或运行时校验失败，则不恢复为活动引擎。

## 6. 模型来源与存储

### 6.1 正式产品来源

TypeWhale 使用自己的版本化模型清单。清单至少包含：

- 稳定模型标识
- 展示名称
- 经过验证的远程制品地址
- 模型格式与架构
- 文件清单、大小和校验信息
- 所需运行时能力及最低版本
- 推荐统一内存

用户只有主动点击下载后才产生网络请求。下载进入 TypeWhale 自己的 staging 目录，支持进度、取消和失败续传。所有分片校验成功后再原子提升为正式受管模型。

建议受管目录：

```text
~/Library/Application Support/TypeWhale Pro/Models/LLM/
  gpt-oss-20b-mxfp4-q8/
```

TypeWhale 删除模型时只删除该受管目录。产品代码不搜索或引用 LM Studio 目录。

### 6.2 本次开发机初始化

为了避免在同一台机器重新下载相同约 11GB 权重，本次允许通过仓库内的开发工具执行一次 APFS clone：

1. 开发工具显式接收源目录和 TypeWhale 受管目标目录。
2. 校验源配置、tokenizer、权重分片和总大小。
3. 在 TypeWhale staging 中创建 clone。
4. 对目标重新校验。
5. 原子提升为正式受管目录。
6. 输出不含源绝对路径的结果摘要。

该工具不进入 App 产品调用链。App 只看到已经存在的 TypeWhale 受管模型，不知道初始化来源。

## 7. 运行架构

### 7.1 组件边界

新增或扩展以下职责：

- `SmartAIModel`
  - 增加 Qwen3.6 35B Rewrite。
  - 增加自管 GPT-OSS 模型和 `.managedMLX` provider。

- `ManagedLLMModelRegistry`
  - 读取 TypeWhale 模型清单。
  - 聚合安装、校验、下载和运行状态。

- `ManagedLLMDownloadManager`
  - 负责用户触发的下载、续传、取消、校验和原子安装。

- `ManagedMLXRuntimeLocator`
  - 解析 TypeWhale 版本锁定的 Python/MLX 能力。
  - 启动前验证 Python、`mlx`、`mlx_lm` 和 `transformers` 的兼容版本。
  - 引擎不直接硬编码 ASR runtime 路径。

- `ManagedMLXLLMRuntime`
  - 启动、复用、取消和停止隐藏 helper。
  - 管理 JSONL 请求协议、超时、进程组和运行指标。

- `TypeWhaleLocalLLMEngine`
  - 实现 `SmartAITextEngine`。
  - 复用现有整理与翻译 PromptBuilder。
  - 把 helper 输出映射为现有结果类型。

- `HarmonyFinalOutputParser`
  - 只解码并返回唯一合法的 `final`。
  - 永不返回、打印或保存 `analysis`。

- `SelectedSmartAITextEngine`
  - 根据活动模型路由到 DeepSeek、Ollama 或 managed MLX。

- `ManagedLLMModelPanel`
  - 展示模型生命周期、切换、测试和性能。

### 7.2 helper 协议

App 使用 Foundation `Process` 静默启动 helper，不打开 Terminal。stdin/stdout 使用逐行 JSON：

请求至少包含：

- 协议版本
- 请求 ID
- 操作类型：rewrite、translate、warmup、health
- 已构造的 system/user prompt
- reasoning 档位
- 最大输出 token
- 超时预算

响应至少包含：

- 请求 ID
- `final` 文本或结构化错误
- load、TTFT、completion、token/s 和内存指标
- 是否由取消结束

helper 的 stderr 进入受限诊断日志，不得包含原始用户文本、token 序列、analysis 或完整模型输出。

## 8. 推理与安全边界

- 固定 GPT-OSS `Reasoning: low`。
- 禁止工具调用和联网回退。
- 生成采用确定性配置。
- 复用 TypeWhale 现有整理和翻译提示词，不另建语义分叉。
- 输出继续经过 `SmartRewriteOutputSanitizer` 和术语归一化。
- 缺少合法 `final`、存在多个 `final`、输出为空或协议损坏均视为失败。
- 不把原始语音文本当成模型指令，不回答其中的问题。
- 不保存用户在“测试模型”里输入的文本；默认测试只使用仓库内合成 fixture。

## 9. 生命周期与内存

- App 启动不阻塞等待 GPT-OSS。
- 只有用户启用且模型校验通过时，才以低优先级后台预热。
- 正常保持热加载，不增加空闲定时卸载。
- 录音、识别、整理、翻译和粘贴期间禁止释放 helper。
- 高内存释放只能在完全空闲时执行；释放后若 GPT-OSS 仍处于启用状态，必须重新热加载。
- 用户关闭 GPT-OSS、删除模型或退出 App 时，终止自有 helper 并回收管道和临时文件。
- 取消只影响对应请求；必要时终止自有 helper 进程组，不影响 Ollama、LM Studio 或其他进程。

## 10. 失败与回退

- 下载失败：保留可续传 staging，显示原因，不改变当前模型。
- 校验失败：不得提升为正式模型，允许清理后重试。
- 预热失败：不得进入“当前使用”状态。
- 活动请求中 helper 首次崩溃：允许受控重启一次。
- 重启后仍失败：当前请求回退原文，GPT-OSS 保持明确错误状态。
- 不自动切换到 DeepSeek、Ollama 或任何其他 provider。
- 用户取消不显示为模型故障。
- 模型损坏或运行时不兼容时，录音、ASR、原文粘贴和其他模型路径仍可使用。

## 11. 测试设计

### 11.1 自动化测试

按 TDD 先写失败测试，再实现：

- `SmartAIModel` 新枚举、存储迁移、菜单顺序和引擎名称。
- Qwen3.6 35B Rewrite 路由到 Ollama。
- GPT-OSS provider 路由到 `TypeWhaleLocalLLMEngine`。
- GPT-OSS 开关与原模型记忆、互斥和重启恢复。
- 模型清单、下载状态、取消、校验失败和原子安装。
- helper JSONL 编解码、请求 ID 匹配和乱序防护。
- Harmony final-only、analysis-only、多 final、空输出和损坏协议。
- timeout、取消、崩溃一次恢复和连续失败回退。
- 日志与持久化中不出现 analysis、raw token 和测试原文。
- 模型页独立分区和辅助功能标签。

### 11.2 真实安装版测试

1. 在开发机用已有相同权重执行一次 APFS clone 初始化。
2. 构建并安装 `/Applications/TypeWhale Pro.app`。
3. 打开“模型”Tab，确认第三个独立分区完整显示。
4. 确认 Qwen3.6 35B Rewrite 出现在现有下拉，选择后完成真实整理。
5. 启用 GPT-OSS，确认现有下拉禁用且原选择被保留。
6. 从 App 内运行合成测试，检查 final-only 输出和性能指标。
7. 验证真实语音的润色、开发需求、禁止代答、短指令、中译英和英译中。
8. 在生成中取消，确认不粘贴迟到结果且下一次请求可用。
9. 终止 helper，确认一次恢复；制造连续失败，确认当前请求回退原文且不调用其他 provider。
10. 重启 App，确认安装状态、选择状态和 helper 生命周期正确。
11. 关闭 GPT-OSS，确认恢复原整理模型。
12. 对真实安装版执行截图和设计质量复核。

### 11.3 性能记录

至少记录：

- helper 启动与模型加载时间
- 首 Token
- 完整耗时
- token/s
- 峰值 RSS/统一内存
- 连续三次热调用
- 取消后的恢复时间

LM Studio 或操作系统页缓存可能影响完全冷盘读取；报告必须区分“新 helper 冷加载”和“重启机器后的冷盘加载”。

## 12. 可观察验收标准

以下条件必须全部满足：

- 使用 GPT-OSS 时不出现 Terminal 窗口。
- TypeWhale 产品代码和 UI 不依赖或提及 LM Studio。
- GPT-OSS 不依赖 Ollama 服务。
- Qwen3.6 35B Rewrite 可在现有下拉选择并完成真实整理。
- GPT-OSS 分区独立、状态完整、控件可访问。
- 开启后真实整理和翻译进入 GPT-OSS，关闭后恢复原模型。
- 失败不偷偷切换 provider，不影响录音和原文粘贴。
- analysis 不显示、不持久化、不进入日志。
- 取消、崩溃恢复和 App 重启路径可重复验证。
- 自动化测试、构建、签名、安装和真实安装版检查通过。
- 完成 UI/design review；若无法覆盖某些状态，明确记录风险。

## 13. 文档、构建与提交

实现完成后：

- 更新 `docs/ARCHITECTURE.md`。
- 更新 `docs/开发日志.md`。
- 更新应用内 `VersionHistoryViewController`。
- 运行相关自动化测试。
- 通过 `./native/build_and_log.sh` 递增 build、编译、安装、打开、验签并记录构建日志。
- 定向复核并提交本轮文件，不包含其他 session 的受保护改动。
