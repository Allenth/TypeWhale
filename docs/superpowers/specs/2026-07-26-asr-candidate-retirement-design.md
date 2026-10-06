# TypeWhale ASR 候选模型退役设计

**日期：** 2026-07-26
**状态：** 已获产品负责人设计确认，等待规格复核后实施

## 产品目标

TypeWhale 不再向用户提供仅有实验价值、但在准确率、启动速度、资源占用或产品适配性上不达标的 ASR 候选。产品线从十一种本地 ASR 收缩为五种有明确用途的模型，减少选择负担、下载体积、运行时分支和后续维护成本。

本轮退役以下六种模型：

- Paraformer Contextual
- Paraformer zh
- SeACo Paraformer
- Whisper Small MLX
- Qwen3-ASR 0.6B Sherpa int8
- Zipformer bilingual zh-en Sherpa int8

正式保留：

- SenseVoice int8
- Parakeet TDT 0.6B v2 Sherpa int8
- Fun-ASR Nano
- Qwen3-ASR 0.6B MLX 8-bit
- Qwen3-ASR 1.7B MLX 8-bit

## 退役原因

这些模型不适合继续作为 TypeWhale 产品能力：

- Paraformer Contextual、Paraformer zh、SeACo Paraformer 的冷启动和常驻内存成本过高，真实输入体验差，热词收益不足以抵消资源与交互成本。
- Whisper Small MLX 在真实测试中出现英文错词和重复幻觉，稳定性不满足输入法最终文本要求。
- Qwen3 Sherpa 的真实中文语义准确率明显低于 Qwen3 MLX 0.6B，且没有可用的热词优势，形成重复且较弱的产品路线。
- Zipformer 虽然推理速度快，但真实中文和中英混合准确率不足，不适合作为最终输入模型。

历史实验结果仍保留在开发日志和历史规格中，不能改写为“从未支持”。当前产品文档必须明确标注这些路线已经退役，不能继续将其描述为当前可选能力。

## 产品与代码边界

### 必须移除

- `ASRBackend` 与 `ASRCandidateID` 中对应的六个候选。
- 模型选择界面、模型管理列表和下载入口。
- 能力声明、模型注册表、正式识别路由、独立测速矩阵和准入数据。
- FunASR worker 中三个 Paraformer provider。
- MLX worker 中 Whisper provider。
- Sherpa helper/bridge 中仅服务 Qwen3 Sherpa 和 Zipformer 的创建与路由代码。
- Zipformer 专用下载、解包和模型 manifest。
- 只为 Paraformer 标点恢复服务的 CT-Punc 产品目录、下载入口和运行接线。
- 对应的生产测试、边界测试和测试 fixture；共享测试改为覆盖保留模型。

### 必须保留

- SenseVoice 原生实时预览与最终识别能力。
- Parakeet Sherpa helper 和共享 Sherpa/ONNX Runtime 基础设施。
- Fun-ASR Nano 及其 App 自带 Python runtime。
- Qwen3 MLX 0.6B/1.7B 及共享 MLX runtime。
- FSMN-VAD。它不在本轮明确退役范围内，不因删除 Paraformer 而顺手删除。
- 历史版本记录和旧开发日志中的事实性条目。
- 与本任务无关的胶囊、翻译、整理、粘贴、录音和快捷键行为。

## 旧配置迁移

如果 `UserDefaults` 中保存的是任一被退役的 backend 原始值，启动时迁移到 `SenseVoice int8` 并写回。迁移必须覆盖当前六个 raw value 以及已经存在的 Whisper 旧名称兼容值，避免升级后出现无效选中项或不可录音状态。

Qwen3 Sherpa 的旧兼容值 `qwen3ASR` 同样迁移到 SenseVoice，不再迁移到已退役的 Sherpa backend。

## 本机模型数据清理

实施完成后，把下列已确认目录移入一个带时间戳的废纸篓目录，保持可恢复，不使用不可恢复的递归删除：

- `~/Library/Application Support/TypeWhale Pro/Models/funasr/paraformer-hotword-contextual`
- `~/Library/Application Support/TypeWhale Pro/Models/funasr/paraformer-zh`
- `~/Library/Application Support/TypeWhale Pro/Models/funasr/ct-punc`
- `~/Library/Application Support/TypeWhale Pro/Models/mlx-asr/whisper-small-mlx`
- `~/Library/Application Support/TypeWhale Pro/Models/zipformer-bilingual-zh-en-int8`
- `~/Library/Application Support/TypeWhale/Models/qwen3-asr-0.6b-int8`
- `~/.cache/modelscope/hub/models/iic/speech_seaco_paraformer_large_asr_nat-zh-cn-16k-common-vocab8404-pytorch`
- 对应的空临时 SeACo 下载目录（若仍存在）。

清理前再次解析和核对每个绝对路径。不得使用未解析变量、通配符或宽泛父目录作为移动目标。不得触碰 Qwen3 MLX Hugging Face cache、Parakeet、Fun-ASR Nano、SenseVoice、FSMN-VAD 或共享 runtime。

## 文档更新

- `docs/开发日志.md`：新增本次退役决策、原因、影响范围、迁移行为、删除体积和验证结果。
- `docs/产品需求文档.md`：当前 ASR 产品线只描述五个保留模型，明确六个退役模型不适合本软件。
- `docs/ARCHITECTURE.md`：更新正式 backend、sidecar、热词、长音频和模型生命周期说明，删除已退役模型作为当前架构能力的表述。
- `docs/TYPEWHALE_PRO_ASR_STRATEGY.md`：把六条路线标记为已评估并退役，避免后续 session 重新接回。
- 应用内版本历史：记录用户可见的模型列表收缩和旧设置迁移。

## 错误与恢复

- 升级后发现旧 backend 值时必须自动恢复到 SenseVoice，不能提示用户重新下载已退役模型。
- 已退役模型目录不存在时，清理步骤记为“已不存在”，不能使构建失败。
- 权重移动失败时停止清理并报告具体路径；代码构建与本机数据清理结果必须分别记录，不能把部分清理误报为全部完成。
- 保留模型的 warmup 或识别失败语义不在本轮修改。

## 验收标准

1. 安装版模型选择和模型管理界面只显示五个保留模型。
2. 六个退役名称不能出现在当前产品枚举、注册表、下载目录或可执行路由中。
3. 旧 backend 值逐一测试后都会迁移到 SenseVoice。
4. SenseVoice、Parakeet、Fun-ASR Nano、Qwen3 MLX 0.6B/1.7B 的选择、预热和最终识别路由保持可编译、可测试。
5. 本机八个精确目标目录已移入废纸篓或确认原本不存在，并记录实际释放体积。
6. 自动化测试、完整源码编译、build 号递增、覆盖安装、打开和签名校验通过。
7. 真实安装版界面复核确认退役项消失，保留项布局正常，旧设置不会显示空白或无效选中。
8. 提交前只 stage 本轮文件，不包含现有 `.superpowers/` 和 Capsule Concept 未跟踪目录。

## 回滚

代码回滚使用本轮独立 git commit。模型数据可从废纸篓中的时间戳目录恢复到原路径。回滚不能依赖重新下载模型，也不能覆盖用户后来下载的新文件。
