# TypeWhale 自管 gpt-oss 本地导入与隔离验证设计

日期：2026-07-24

## 1. 目标

验证 TypeWhale 能否在不依赖 Ollama 或 LM Studio 服务、也不重新下载模型的前提下，复用用户本机已有的 MLX 模型文件，完成低延迟文字整理。

第一候选为：

- 模型：`mlx-community/gpt-oss-20b-MXFP4-Q8`
- 当前外部位置：`~/.lmstudio/models/mlx-community/gpt-oss-20b-MXFP4-Q8`
- 格式：MLX Safetensors
- 当前磁盘占用：约 11GB
- 当前验证设备：Apple M4 Max，128GB 统一内存

本轮先做隔离准入验证，不接入 TypeWhale 生产输入链路。

## 2. 已知产品信号

用户已在 LM Studio 的 MLX 后端中实测该模型：

- 约 1,110 token 输入上下文；
- 热状态首 token 约 0.87 秒；
- 热状态生成速度约 111.10 token/秒；
- 以 EOS 正常结束。

这证明该模型的热推理性能值得进入 TypeWhale 本地模型候选，但不证明独立运行时兼容性、完全冷加载速度、峰值内存或 TypeWhale 语义保真。

## 3. 范围

### In scope

- 只读发现 LM Studio 已有模型目录。
- 校验模型配置、tokenizer、Harmony 模板和 Safetensors 分片完整性。
- 使用与 TypeWhale 隔离的受控 MLX 运行时直接加载模型。
- 固定最低官方推理档 `Reasoning: low`。
- 解析 Harmony 输出，只接收 `final`，丢弃 `analysis`。
- 使用 TypeWhale 代表性文字整理和中英翻译样本验证质量。
- 记录冷加载、首 token、生成速度、完整完成时间、峰值 RSS 和取消行为。
- 验证后设计无重新下载的本地导入机制。

### Out of scope

- 不修改现有 `SelectedSmartAITextEngine` 或 Ollama 生产路径。
- 不修改 ASR、VAD、胶囊、粘贴、历史记录或截图链路。
- 不构建、不递增 build、不覆盖安装 `/Applications/TypeWhale Pro.app`。
- 不在本轮把 gpt-oss 设为默认模型。
- 不打包或重新分发模型权重。
- 不复用或复制 LM Studio 私有后端二进制。

### Do not touch

- 不修改、移动、重命名或删除 `~/.lmstudio` 下的任何文件。
- 不写入 LM Studio 模型目录。
- 不干预 LM Studio 已运行的模型实例。
- 不触碰当前工作区其他 session 留下的未跟踪 UI 文件。

## 4. 路线比较

### 路线 A：直接调用 LM Studio API

优点是实现最快，并能复现当前性能。缺点是把 Ollama 依赖替换成 LM Studio 依赖，无法满足 TypeWhale 自管模型的产品目标。

结论：仅可作为性能对照，不作为产品架构。

### 路线 B：永久直接读取 LM Studio 模型路径

优点是不下载也不复制。缺点是模型生命周期归 LM Studio 所有；用户删除、迁移或升级模型后，TypeWhale 会失去依赖，且外部格式变化不可控。

结论：可作为外部模型兼容模式，不作为默认导入方式。

### 路线 C：TypeWhale 自管运行时 + APFS 克隆导入

TypeWhale 只读发现并校验外部模型，通过同卷 APFS clone-on-write 将模型导入自己的 Application Support staging 目录；加载验证成功后原子切换为受管模型。克隆失败时，允许用户选择外部引用或普通复制，绝不自动重新下载。

结论：推荐的生产路线。它同时满足“不重复下载”“不立即重复占用 11GB”“不依赖 LM Studio 生命周期”和“TypeWhale 锁定已验证版本”。

## 5. 隔离验证架构

隔离验证由四个边界组成：

1. `ExternalMLXModelProbe`
   - 只读检查外部模型目录。
   - 生成模型文件清单、大小和校验结果。
   - 不修改源目录。

2. `ManagedLLMRuntimeProbe`
   - 使用独立、版本锁定的 MLX 运行环境。
   - 禁止运行时自动联网下载模型或依赖。
   - 模型加载与推理运行在独立进程，异常不能影响 TypeWhale App。

3. `HarmonyFinalOutputParser`
   - 识别 `analysis` 与 `final` 通道。
   - 永不打印、保存、上传或返回原始思维链。
   - 缺少合法 `final` 时判定失败，不把 `analysis` 当成正文。

4. `LocalLLMAdmissionHarness`
   - 运行固定样本。
   - 记录性能和资源指标。
   - 输出不含原始私人文本的本地结果报告。

本轮探针不得链接进 App target，也不得写入 TypeWhale 用户设置。

## 6. 推理策略

- gpt-oss 官方只支持 `low`、`medium`、`high` 推理档，不能宣称完全关闭 Think。
- TypeWhale 使用 `Reasoning: low`。
- 禁止工具调用。
- 限制上下文长度和最大输出 token，避免为短文本任务分配不必要的 KV cache。
- 整理使用确定性、低随机性的生成配置。
- 每个测试必须区分：
  - 模型加载时间；
  - prompt prefill；
  - time to first token；
  - decode token/second；
  - 完整结果时间。

## 7. 本地导入语义

未来产品中的“使用已有模型”执行以下流程：

1. 发现受支持的外部模型。
2. 展示来源、版本、大小和兼容状态。
3. 用户明确选择导入。
4. TypeWhale 在自己的 staging 目录尝试 APFS 克隆。
5. 校验目标文件与源文件的一致性。
6. 用 TypeWhale 自管运行时做一次加载和最小生成验证。
7. 成功后原子替换到正式受管目录。
8. 失败则删除 staging，不改变源模型和当前已用模型。

TypeWhale 删除受管模型时，只删除自己的导入目标，不删除外部来源。

外部引用模式必须标记为“由其他应用管理”。每次使用前做轻量完整性检查；来源消失时自动禁用并回退，不弹出阻断输入的错误。

## 8. 资源与生命周期

- 模型加载不得阻塞 App 启动、主窗口或录音。
- 生产接入后采用低优先级后台预热。
- 模型正常保持热加载，不新增空闲定时卸载。
- 录音、识别、整理、粘贴过程中不得释放模型。
- 高内存治理必须与现有 ASR/VAD 策略协调，且只能在空闲状态进行。
- 独立 helper 崩溃时，当前请求回退原文；下一次请求可受控重启 helper。

当前 M4 Max 128GB 设备可验证常驻体验，但不能据此放宽普通设备准入标准。正式模型推荐必须按统一内存档位验证。

## 9. 隔离验证样本

至少覆盖：

- 短聊天：去除口语残留但保持自然和简短。
- 开发需求：保留任务、原因、限制、顺序和第一人称立场。
- 禁止代答：整理“帮我回复用户……”时保留代答需求，不生成最终话术。
- 短指令：不得扩写为 PRD 或模板。
- 中译英和英译中：不得回答原文问题，只做翻译。
- 中英技术术语：保留 SwiftUI、Ollama、Qwen3-ASR 等术语。
- 拒绝与异常输出：空结果、只有 analysis、超长输出、取消和 helper 崩溃。

样本优先复用仓库现有非私人 fixture；不得读取或上传用户历史真实输入。

## 10. 准入标准

隔离验证通过必须同时满足：

- 不重新下载模型权重。
- 不修改 LM Studio 模型目录。
- 独立运行时能完成冷加载和至少三次连续推理。
- 每次只向调用方返回合法 `final`。
- 取消后进程与内存状态可恢复。
- 失败不影响 LM Studio 和当前 TypeWhale。
- 短文本整理不存在明显代答、扩写、主体改写或约束丢失。
- 中英翻译不存在回答问题、添加解释或泄漏 reasoning。
- 报告完整记录冷加载、首 token、生成速度、完成时间和峰值 RSS。

通过只代表“具备进入产品接入计划的资格”，不代表可以直接替换当前默认模型。

## 11. 后续实施边界

隔离验证通过后，另行制定生产实施计划，包含：

- `LocalLLMModelRegistry`
- `ManagedLLMImporter`
- `ManagedMLXLLMRuntime`
- `TypeWhaleLocalLLMEngine`
- Harmony 安全解析
- 设备推荐与模型管理 UI
- Ollama 迁移与回滚
- 自动化 fixture、真实安装版测试、构建、安装和提交

生产实现不得把探针脚本或临时运行时直接搬进稳定产品路径。
