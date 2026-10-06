# Qwen3 4B 本地直驱整理模型设计

日期：2026-07-25
状态：已确认

## 产品目标

让用户在 TypeWhale 现有“整理模型”下拉菜单中直接选择 `Qwen3-4B-Instruct-2507 4bit`，由 App 自带 MLX 运行时在本机完成智能整理和语音翻译，不依赖 Ollama、LM Studio 或其他外部模型应用。

GPT-OSS 20B 因实际速度与可用性不符合产品要求，本轮从产品入口和运行链路中下线。已经下载到 TypeWhale 专属目录的 GPT-OSS 权重同时删除；通用 MLX 直驱能力继续保留并服务于 Qwen3 4B。

## 用户场景与当前痛点

模型权重已经存在于：

`~/Library/Application Support/TypeWhale Pro/Models/LLM/qwen3-4b-instruct-2507-4bit`

但当前 App 的普通“整理模型”下拉只认识 Ollama 和 DeepSeek。GPT-OSS 则使用独立模型面板和启用开关，启用后反而禁用普通下拉菜单。用户无法从统一入口选择刚下载的 Qwen3 4B，也无法完成真实 App 内测试。

## 范围

### In scope

- 在“智能”页和“模型”页共用的“整理模型”下拉菜单中新增“本地直驱 Qwen3 4B Instruct”。
- 选择该模型后，智能整理与语音翻译走 TypeWhale 自带 MLX worker。
- 为 Qwen3 4B 增加固定 revision、文件大小和 SHA-256 清单校验。
- 将现有 MLX worker 从 GPT-OSS Harmony 专用输出解析改造为按模型协议解析。
- Qwen3 4B 使用标准 chat template，直接返回最终正文，不输出或暴露思考内容。
- 切换到 Qwen3 4B 时检查模型与运行时；未就绪时拒绝保存并恢复原选择。
- 切换模型时停止不再需要的本地 worker；首次选择后后台预热。
- 迁移旧 GPT-OSS 启用状态，回到安全的标准整理模型选择。
- 移除 GPT-OSS 用户入口、专属文案、专属模型定义与 Harmony 解析。
- 更新测试、架构记录、开发日志和应用内版本历史。

### Out of scope

- 不让 Qwen3 4B 接管截图翻译。
- 不改变 Ollama 2B、9B、35B、35B Rewrite 或 DeepSeek 的现有请求行为。
- 不引入 Qwen3.5、视觉模型、代码模型或新的外部模型服务。
- 不把大模型权重打进 App 或 DMG。
- 不新增空闲定时卸载策略。

### Do not touch

- 不修改 ASR、VAD、热词和胶囊概念稿功能。
- 不读取、迁移或删除 LM Studio、Ollama 的模型文件。
- 不静默回退到云端模型并产生费用。
- 不在整理失败时覆盖用户原文。

## 方案选择

### 采用：统一整理模型选择

Qwen3 4B 成为 `SmartAIModel` 中一个正式模型，与 Ollama 和 DeepSeek 模型共用现有菜单、持久化与双入口同步机制。模型本身由新的 TypeWhale 本地直驱 provider 路由。

这让用户只需要理解一个“整理模型”选择，不再维护“普通下拉 + GPT-OSS 独立开关”两套互斥状态。

### 不采用：保留独立受管模型开关

该方案延续当前选择冲突，用户仍需在两个区域判断当前生效模型，并且普通下拉会被禁用。

### 不采用：通过 Ollama 或 LM Studio 加载

该方案虽然复用外部服务，但违背 App 自管模型和直接驱动目标，也会增加产品安装依赖与运行状态不确定性。

## 架构设计

### 模型身份与路由

- `SmartAIProvider` 新增 TypeWhale 本地 MLX provider。
- `SmartAIModel` 新增稳定 raw value 的 Qwen3 4B case。
- 下拉菜单继续由 `SmartAIModel.allCases` 构建，两个页面用同一 tag 和同一设置同步。
- `SelectedSmartAITextEngine` 根据 provider 将 Qwen 路由到 `ManagedLLMRuntimeService`，其他模型保持原路由。
- 旧 `ManagedLLMSelection` 不再作为运行时选择来源；已有 GPT-OSS 启用数据在启动或读取时迁移并清除。

### 模型目录与校验

- Qwen 模型 ID：`qwen3-4b-instruct-2507-4bit`。
- 固定 Hugging Face revision：`50d427756c6b1b2fe0c0a10f67fbda1fc8e82c1b`。
- Catalog 记录运行必需文件的字节数与 SHA-256。
- Registry 只接受 TypeWhale 受管目录内的普通文件或不逃逸目录的符号链接。
- 选择前必须通过完整校验；校验结果沿用基于 revision、路径、大小和修改时间的缓存。

### Worker 与输出协议

- Swift 与 worker 之间继续使用一行一个 JSON 请求/响应的现有协议。
- 请求增加或利用模型身份，使 worker 明确选择输出策略。
- GPT-OSS Harmony channel 与 reasoning effort 专属处理删除。
- Qwen3 4B 使用 tokenizer 自带 chat template 生成 prompt。
- 生成结果仅解码新生成 token，清理特殊 token 和外围空白后作为 `final_text`。
- 若输出为空、包含协议错误或进程异常，返回结构化失败；Swift 层不伪造成功结果。

### 生命周期与性能

- 选择 Qwen 后后台发送极小预热请求，避免第一次正式整理承担全部加载时间。
- worker 在连续请求之间保持模型热加载。
- 切换离开 Qwen 时停止其 worker，释放大模型资源。
- 取消、超时、helper 崩溃自动重启一次和最大响应大小限制继续沿用现有实现。
- 本轮不增加空闲定时卸载。

## UI 与交互

- 两个“整理模型”下拉菜单增加“本地直驱 Qwen3 4B Instruct”。
- 删除 GPT-OSS 独立模型面板及其安装、测试、启用和删除按钮。
- 选择 Qwen 成功时状态区显示已切换并开始后台预热。
- 模型缺失、校验失败或运行时不可用时：
  - 不保存 Qwen 为当前生效模型；
  - 两个下拉菜单恢复到此前模型；
  - 状态区显示可操作的失败原因；
  - 不自动切换到 DeepSeek。
- 不新增弹窗式日常切换流程，保持现有下拉菜单的轻量交互。

## 数据迁移

- 若旧 `managedLLM.selection` 表示 GPT-OSS 已启用，升级后不再尝试启动 GPT-OSS。
- 保留用户此前的标准 `SmartAIModel` 选择；若该值无效则使用当前默认模型。
- 完成迁移后清除或标记旧受管选择状态，防止后续版本再次误判。
- GPT-OSS 模型目录缺失属于正常下线状态，不展示错误。

## 错误与安全边界

- Qwen 本地推理失败时沿用现有“保留原文”行为。
- 不静默调用 DeepSeek、MiniMax、Ollama 或其他外部引擎。
- 模型路径必须在 TypeWhale 受管 LLM 根目录内。
- worker 仅接受本地绝对目录，不允许远程模型 ID 触发运行时下载。
- 日志记录模型 ID、路由、耗时和错误类型，不记录完整用户正文。

## 测试策略

### 自动化

- `SmartAIModel`：
  - Qwen case 的 provider、显示名、raw value、菜单 tag 和持久化迁移。
- Catalog/Registry：
  - revision、13 个文件清单、总大小、关键 SHA-256；
  - 缺失、大小错误、哈希错误和目录逃逸均拒绝。
- 路由：
  - 选中 Qwen 时只调用 TypeWhale MLX engine；
  - 其他五个现有模型保持原 engine；
  - Qwen 失败不会调用云端或 Ollama fallback。
- Worker：
  - 标准 Qwen chat template；
  - 只解码生成 token；
  - 空输出、异常、取消和超时返回正确错误。
- UI 边界：
  - 两个菜单都出现 Qwen；
  - GPT-OSS 面板和文案消失；
  - 两个菜单保持同步。

### 真实安装版

1. 打开“智能”页和“模型”页，确认两个下拉菜单均有 Qwen3 4B。
2. 在任一页面选择 Qwen，确认另一页面同步。
3. 使用“我们回顾一下这个问题”执行智能整理，确认返回非空正文且没有 `<think>`。
4. 测量首次加载、首字延迟、总耗时和生成速度。
5. 连续执行第二次整理，确认模型保持热加载且速度改善。
6. 切换回 Ollama 或 DeepSeek，确认 Qwen worker 停止。
7. 临时模拟模型缺失，确认选择不生效、原选择恢复且原文保留。
8. 回归自动翻译、取消、普通整理、35B Rewrite 和 DeepSeek 路径。

## 验收标准

- 用户能从现有“整理模型”下拉菜单选择 Qwen3 4B，无需终端或外部模型应用。
- 安装版 App 能使用已下载模型完成中文智能整理。
- 输出不包含 `<think>`、Harmony channel 或其他协议标记。
- 模型失败不会覆盖原文，也不会静默产生云端调用。
- GPT-OSS 不再出现在产品 UI、活动模型路由或模型目录中。
- 现有 Ollama、DeepSeek、截图翻译、ASR、VAD 和热词功能没有行为回归。
