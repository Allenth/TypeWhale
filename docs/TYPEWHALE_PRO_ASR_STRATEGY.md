# TypeWhale Pro 中英混合与热词 ASR 改造策略

最后更新：2026-07-05
适用分支：`codex/typewhale-pro-asr-hotwords`  
状态：产品与技术决策记录，尚未代表已实现功能。

## 1. 背景

TypeWhale Pro 的目标用户是高频中英混合输入者，典型口述不是纯中文或纯英文，而是中文骨架中夹英文模型名、代码名、产品名、API 名和命令，例如：

```text
把 Qwen3-ASR 的 hotword config 接到 SpeechInputCoordinator。
```

近期讨论确认了几个关键事实：

- 用户可以接受 Pro 版使用更高本地资源预算：模型空间约 15GB 以上，内存预算可到约 23GB。
- 当前主 ASR 模型不支持热词；如果第一遍 ASR 已经把英文实体识别错，后处理和整理模型往往没有足够证据恢复真实英文。
- 中英混合、热词保真、本地整理模型同等重要，但优先级不是“整理模型猜回热词”，而是“音频识别阶段先尽量抓住热词”。
- 后处理 canonicalizer 只能做兜底，例如把 `qwen3 asr` 修为 `Qwen3-ASR`；不能承担从完全错误中文文本里凭空猜英文实体的职责。

## 2. 产品判断

TypeWhale Pro 不应继续把“中英混合 + 热词”寄托在不支持热词的单一中文 ASR 上。正确路线是：

```text
中文 ASR 负责中文骨架
英文/热词 ASR 或 KWS 负责英文实体
合并器负责把多路结果拼成自然中英混合文本
整理模型负责最终格式、标点、空格和术语保真
```

必须避免的错误路线：

- 只在 ASR 完成后做热词替换。
- 整句级硬切换：整句判中文就只走中文 ASR，整句判英文就只走英文 ASR。
- 让整理模型从完全错误的 ASR 文本里猜测英文专有词。
- 粗暴屏蔽所有短英文来防静音幻觉。
- 在未验证前把实验 ASR 接入稳定 final paste 主链路。

## 3. 调研结论

### 3.1 Code-switching 是独立 ASR 难题

中英文 code-switching 不是普通中文 ASR 的附带能力。ASRU 2019 Mandarin-English Code-Switching Challenge 总结中提到，E2E track 中语言识别、合理建模单元和数据增强对结果很重要。参考：[ASRU 2019 paper](https://arxiv.org/abs/2007.05916)。

### 3.2 语言路由可行，但不应做粗粒度硬切

Language-Routing Mixture of Experts 这类研究使用 frame-wise language routing，让模型内部按帧选择语言专家。它证明“语言路由/专家切换”方向成立，但产品外置实现时需要音频段级或帧级思路，不能只做整句切换。参考：[LR-MoE, Interspeech 2023](https://www.isca-archive.org/interspeech_2023/wang23sa_interspeech.pdf)。

### 3.3 热词必须在声学侧或解码侧生效

sherpa-onnx 官方明确 hotwords/contextual biasing 只支持 transducer models，其他模型不支持。参考：[sherpa-onnx hotwords](https://k2-fsa.github.io/sherpa/onnx/hotwords/index.html)。

这与用户反馈一致：当前模型不支持热词时，后处理不能解决第一遍识别已经错掉的问题。

### 3.4 KWS / Word Spotter 是更贴近问题的侧路方案

KWS 或 CTC Word Spotter 的意义是直接从音频中检测候选热词，而不是等待主 ASR 输出文本后再修。可参考：

- [sherpa-onnx keyword spotting](https://k2-fsa.github.io/sherpa/onnx/kws/index.html)
- [NVIDIA NeMo Word Boosting](https://docs.nvidia.com/nemo-framework/user-guide/latest/nemotoolkit/asr/asr_customization/word_boosting.html)
- [Fast Context-Biasing for CTC and Transducer ASR models with CTC-based Word Spotter](https://arxiv.org/html/2406.07096v1)

### 3.5 FunASR 2pass 可评估，但 online hotword 必须实测

FunASR runtime 支持 online/offline/2pass 服务模式，适合作为中文 ASR 工程对照。参考：[FunASR online runtime guide](https://github.com/alibaba-damo-academy/FunASR/blob/main/runtime/docs/SDK_advanced_guide_online.md)。

但技术社区中有在线模式 hotword 是否生效的疑问，因此不能未经验证就作为 Pro 主线。参考：[FunASR issue #2713](https://github.com/modelscope/FunASR/issues/2713)。

### 3.6 2026-07-05 下载前模型边界确认

本轮下载前确认的原则是：只把官方路径中明确暴露 `hotwords`、`--hotword` 或 contextual hotword 能力的模型列入主测试；仅有普通中英识别能力、但没有可验证热词入口的模型，不进入热词主测试。

| 模型 / 路径 | 类型 | 热词能力边界 | 中英混合边界 | 下载决策 |
| --- | --- | --- | --- | --- |
| Fun-ASR-Nano-2512 PyTorch / AutoModel | LLM-ASR，约 800M 参数 | 官方 AutoModel 与 vLLM 示例暴露 `hotwords=[...]`，可作为热词主候选 | 官方说明支持中文、英文、日文；中文含方言和口音，适合先测开发场景专有词 | 下载，作为 Pro 主候选 |
| Fun-ASR-Nano-2512 GGUF / llama.cpp | CPU / edge 量化路径 | 官方示例未暴露热词参数；不能作为热词主验证 | 可作为后续 CPU 低内存路线评估 | 第一轮不下载或只作为性能备选 |
| Paraformer contextual hotword | Contextual Paraformer / 中文 ASR 热词模型 | FunASR runtime 明确支持 `--hotword` 文件与权重，官方文档指定 contextual hotword 模型 | 中文主路强，英文专有词需实测，适合作为中文骨架 + 热词召回候选 | 下载，作为热词主候选 |
| paraformer-zh | 普通 Paraformer 中文 / 中英 ASR | Python `generate(..., hotword=...)` 有官方教程入口，但主验证仍应优先 contextual hotword 或 runtime 路径 | 官方 HF 卡片标注 Chinese + English mixed recognition | 下载，作为 Paraformer 对照 |
| fsmn-vad | VAD 辅助模型 | 不支持热词；只做分段 | 不承担识别 | 下载，供 FunASR pipeline 使用 |
| ct-punc | 标点恢复模型 | 不支持热词；只做标点 | 可改善最终文本可读性 | 可延后；第一轮热词召回不依赖它 |
| Paraformer quant ONNX | 量化 ONNX 快速路径 | 未确认完整 hotword/contextual 能力 | 只适合 smoke test | 不进入第一轮主测试 |

下载位置统一使用 Pro 用户级模型目录，避免把未验证模型放进 App bundle 或仓库：

```text
/Users/waykingah/Library/Application Support/TypeWhale Pro/Models/funasr/
  fun-asr-nano-2512/
  paraformer-hotword-contextual/
  paraformer-zh/
  fsmn-vad/
  ct-punc/
```

第一轮下载顺序：

1. `FunAudioLLM/Fun-ASR-Nano-2512`：验证中英混合和 `hotwords` 对 `Codex`、`Obsidian`、`Qwen3-ASR`、`SpeechInputCoordinator` 的召回。
2. `damo/speech_paraformer-large-contextual_asr_nat-zh-cn-16k-common-vocab8404`：验证 FunASR runtime `--hotword` 权重文件是否能在音频/解码阶段提升热词召回。
3. `damo/speech_paraformer-large_asr_nat-zh-cn-16k-common-vocab8404-pytorch`：作为非 contextual Paraformer 对照，验证普通 pipeline 与 contextual 路线差异。
4. `damo/speech_fsmn_vad_zh-cn-16k-common-onnx`：仅作为 FunASR pipeline 分段依赖。
5. `damo/punc_ct-transformer_cn-en-common-vocab471067-large-onnx`：如果第一轮只看热词召回，可延后下载。

### 3.7 本地打包与 App 联动边界

技术结论：FunASR / Fun-ASR-Nano 可以与 TypeWhale Pro 在本地联动；但第一阶段不应直接把 PyTorch / FunASR 大模型完整塞进稳定 App bundle 作为默认分发形态。

推荐顺序：

1. 用户级模型目录 + 本地 ASR sidecar worker：模型放在 `/Users/waykingah/Library/Application Support/TypeWhale Pro/Models/funasr/`，App 通过本机进程、stdin/stdout、HTTP 或 WebSocket 调用。音频不出本机，便于实验热词、日志、崩溃隔离和替换模型。
2. App 管理下载和完整性校验：下载后记录模型 ID、revision、文件大小、hash、license note；主 App 只负责选择 provider、传入音频和 hotwords、接收结果。
3. 稳定后再评估内置资源：如果选定的是 ONNX / GGUF / 可签名的轻量 runtime，可以像当前 SenseVoice / VAD 一样打进 `Contents/Resources/Models`；如果仍依赖 PyTorch / Python / vLLM，则不建议作为普通 macOS App 的默认内置形态。

工程边界：

- 当前 TypeWhale Pro 已支持内置模型资源和用户级模型目录两类来源；新增 FunASR provider 应复用这个模式。
- Fun-ASR-Nano PyTorch 路径依赖 Python、FunASR、PyTorch/torchaudio 和模型 remote code，适合作为本地 sidecar 或实验 provider，不适合直接混进主 App 进程。
- Contextual Paraformer 的 runtime / server 形态适合先作为本地 sidecar 验证 `--hotword`，待热词效果确认后再考虑是否改成更轻的本地 runtime。
- 用户可见承诺应写成“本地使用 / 音频不离开本机”，不要在授权未闭环前写成“模型已随商业版永久授权分发”。

商业分发边界：

- FunASR 模型协议允许在协议下使用、复制、修改和分享，并要求注明来源、作者信息并保留相关模型名称。
- 但协议包含“参考和学习使用”、自担风险、自动终止和后续修订等自定义条款；正式付费公开分发前，应保存明确授权确认，或采用用户安装/首次下载模型的方式降低再分发风险。
- 内测、开发机、董事长独享 Pro 版本可以先使用用户目录下载和本地 sidecar；公开售卖版本需补齐 `THIRD_PARTY_NOTICES.md`、应用内第三方授权页、模型 license / revision / hash 记录。

## 4. 推荐架构

```text
Audio Stream
 -> Silero VAD / 录音分段
 -> Language & Hotword Router
    -> 中文 ASR 主路
    -> 英文 ASR / hotword ASR 侧路
    -> KWS / CTC-WS 热词声学检测侧路
    -> 不确定片段双路识别
 -> Segment Merger
 -> 本地整理模型
 -> Safety Gate
 -> Paste / Recent History
```

### 4.1 中文 ASR 主路

职责：

- 保留中文骨架。
- 继续覆盖普通中文输入。
- 在新链路未验证前作为稳定 fallback。

限制：

- 当前模型不支持热词，不能作为中英混合热词主引擎。

### 4.2 英文/热词 ASR 侧路

职责：

- 处理英文实体、模型名、代码名、API 名。
- 优先选择支持 hotwords/contextual biasing 的 ASR。
- 对疑似英文/术语片段或不确定片段参与识别。

验收重点：

- `Qwen3-ASR`
- `sherpa-onnx`
- `SpeechInputCoordinator`
- `Obsidian`
- `Codex`

### 4.3 KWS / CTC-WS 热词声学侧路

职责：

- 在主 ASR 识别前或并行过程中直接从音频里检测热词。
- 给合并器提供“这个时间段可能出现了某个热词”的强候选。

这是解决“第一遍 ASR 已经把英文听没了”的关键层。

### 4.4 Language & Hotword Router

路由不能只看 ASR 文本，因为文本可能已经错。第一版可以用：

- VAD 分段。
- 音频窗口级 spoken language identification。
- KWS 命中。
- 热词候选置信度。
- 不确定状态双路并跑。

路由结果至少包括：

```text
zh
en
mixed
hotwordCandidate
uncertain
```

### 4.5 Segment Merger

职责：

- 保留中文 ASR 的中文骨架。
- 用英文 ASR 或 KWS 命中的热词替换对应时间段。
- 处理重复、重叠、大小写、连字符、中英文空格和标点。

示例：

```text
中文 ASR: 把千问三asr的热点词配置接到 speech input coordinator
KWS: Qwen3-ASR @ 0.8-1.4s
英文 ASR: SpeechInputCoordinator @ 3.2-4.1s

合并:
把 Qwen3-ASR 的 hotword config 接到 SpeechInputCoordinator。
```

### 4.6 本地整理模型

整理模型是最后一公里，不是热词主识别器。

职责：

- 修标点。
- 修中英文空格。
- 保留专有名词大小写和连字符。
- 保留用户发话位置。
- 不把技术词翻译成中文。

非职责：

- 不从完全错误的 ASR 文本里凭空猜英文热词。
- 不替代 KWS、hotword ASR 或语言路由。

## 5. 开发阶段

### Phase 0：建立 Pro ASR 评测集

交付：

- 建立 30-100 条真实中英混合录音样本。
- 每条记录 expected output、必须保留热词、允许变体、失败类型。
- 覆盖静音/呼吸/键盘声等失败路径。

验收：

- 当前 ASR baseline 可跑。
- 后续每个候选 ASR、KWS、合并器都用同一批样本比较。

### Phase 1：热词声学侧路实验

交付：

- 隔离实验工具：输入 `wav + hotwords.txt`，输出当前 ASR 文本、KWS/热词检测结果、英文 ASR 结果和合并候选。
- 不接入主粘贴链路。

验收：

- 至少能证明部分热词在音频侧被抓出来，而不是文本后处理猜出来。
- 记录误触发率。

### Phase 2：ASR Provider 能力层

交付：

- 为 ASR provider 标记能力：
  - `supportsHotwords`
  - `supportsStreaming`
  - `supportsCodeSwitching`
  - `supportsLanguageHint`
  - `recommendedUse: preview/final/both/sidecar`
- 当前模型明确标记为 hotword unsupported 或未验证。

验收：

- 不支持热词的模型不再静默接收无效 hotwords。
- 日志能解释本次 ASR 为什么没有使用热词。

### Phase 3：Router + Merger 原型

交付：

- 对一段完整录音输出多路识别与合并结果。
- 先离线评测，不接 final paste。

验收：

- 合并器能把中文骨架和英文热词拼回自然文本。
- 不确定片段双路并跑时不会破坏中文骨架。

### Phase 4：接入 final ASR 实验开关

交付：

- 仅在 Pro 分支实验开关下启用。
- 现有中文 ASR 保持 fallback。
- 所有增强失败时回退现有 final ASR 文本。

验收：

- 主链路不因实验 provider 崩溃或超时而丢文本。
- 日志记录每次路由、热词命中和合并原因。

### Phase 5：再评估实时预览

实时预览承担信心锚点，风险高。只有 final ASR 改造稳定后，才允许评估是否把 router/sidecar 能力接入胶囊预览。

## 6. 验收指标

P0：

- 静音/噪声不粘贴 `The.` 等幻觉。
- 中文骨架不明显退化。
- 当前 ASR fallback 始终可用。
- 支持热词的路径必须在音频/解码侧生效，而不是仅后处理。

P1：

- 30 条中英混合样本中，核心热词召回明显优于当前 ASR。
- `Qwen3-ASR`、`sherpa-onnx`、`SpeechInputCoordinator` 等专有词可被稳定保留。
- 整理模型不翻译、不改写受保护技术词。

P2：

- UI 中可配置热词和模式。
- 支持项目词库、当前窗口上下文词库。
- 实时预览可利用部分路由能力且不破坏胶囊稳定体验。

## 7. 风险与边界

- KWS/Word Spotter 可能误触发，必须保留置信度和日志，不能无条件替换主 ASR 文本。
- 语言切换器对短英文实体可能不稳定，因此短热词不能只依赖 LID。
- 多模型并跑会增加内存和延迟，Pro 版允许更高资源预算，但输入工具不能让系统卡顿。
- 任何 ASR 实验都必须先离线评测，再进入 final 实验开关，最后才考虑影响实时预览。
- 模型授权和商业再分发仍需单独复核，尤其是 FunASR/SenseVoice 相关模型。

## 8. 当前明确决策

- 当前不支持热词的 ASR 不作为 Pro 中英混合热词主引擎。
- 后处理 canonicalizer 不是主方案，只能作为兜底层。
- Pro ASR 改造优先验证热词声学侧路和支持 hotwords/contextual biasing 的 ASR。
- 双模型方案成立，但必须是音频段级路由、KWS/CTC-WS 侧路和合并器组合，而不是整句硬切换。
- 整理模型继续重要，但职责是保真和格式化，不是弥补 first-pass ASR 完全丢失的英文实体。
