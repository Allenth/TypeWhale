# ASR 候选模型崩溃隔离与热词兼容设计

## 目标

修复 Qwen3-ASR 0.6B Sherpa 在最终识别阶段因错误使用 contextual-biasing API 导致主 App `exit(255)` 的问题，并确保其他候选 ASR 的加载、预热或推理失败不能终止 TypeWhale Pro。

## 已确认根因

Qwen3 Sherpa 被声明为 `sherpaInline` 热词模型。正式识别将开发术语词库编码为字符串，随后创建 `SherpaOnnxCreateOfflineStreamWithHotwords`。该 Qwen3 模型不是支持 contextual biasing 的 Transducer；sherpa-onnx 不返回错误，而是主动结束调用进程。相同 WAV 在无热词时成功，传入任意热词时稳定退出 255。

## 架构

### 主进程边界

- SenseVoice 保持现有进程内实现，继续承担实时预览、VAD 后的稳定最终识别和候选失败回退。
- Qwen3 Sherpa 与 Parakeet Sherpa 的候选最终识别不再直接加载到主进程，统一通过受管 Sherpa helper 子进程执行。
- FunASR / Paraformer 与 MLX 保持现有 sidecar 隔离。
- helper 或 sidecar 的异常退出、协议错误、超时、空结果均转换为普通 Swift 错误；正式识别只回退 SenseVoice 一次。

### Sherpa helper 协议

- App 启动 helper 时传入受管命令：`warmup`、`transcribe`、`shutdown`。
- 请求携带唯一 ID、provider ID、模型目录、音频路径与已编码热词载荷。
- 响应携带相同 ID、成功状态、engine、load/inference 时间、文本或错误。
- helper stdout 只输出逐行 JSON；诊断输出进入 stderr。
- App 检测进程退出并完成所有在途请求，禁止无限等待或重复 completion。
- Qwen3 与 Parakeet 可在 helper 内热加载，但模型切换、热词变化或 shutdown 必须安全释放。

## 热词能力真值

- SenseVoice：不支持，不传。
- Qwen3 Sherpa：不支持，不传；UI 不再显示原生热词。
- Parakeet Sherpa：不支持，不传。
- Fun-ASR Nano：`nativeList`，保留完整短语。
- Paraformer Contextual / Paraformer zh / SeACo：`nativeSpaceSeparated`；只保留不含空白的词项。含空格短语按目标格式判定为不可表达并跳过，同时记录数量，不得阻止模型预热或加载。
- Whisper Small MLX：`contextPrompt`，属于上下文提示而非原生热词。
- Qwen3 MLX 0.6B / 1.7B：不支持，不传。

对测速输入继续保持严格：用户明确输入了目标格式无法表达的临时热词时应显示错误，避免静默改变 A/B 测试条件。兼容过滤只应用于生产开发术语库。

## 就绪语义

- “文件已安装”只代表静态完整性。
- 常用页“已就绪”必须至少满足：静态模型完整、运行时/helper 存在、历史真实非空转写准入有效、当前生产热词可编码。
- 本轮真实矩阵失败的模型必须禁用，并显示具体失败原因，不能继续作为可切换模型。

## 验收标准

1. 使用导致崩溃的原始 WAV，Qwen3 Sherpa 在正式词库下成功转写或返回可处理错误，主 App 不退出。
2. 在 helper 中故意传入会触发 sherpa-onnx 退出的请求，主 App 捕获子进程退出并安全回退 SenseVoice。
3. Paraformer 三模型不会再因 `Claude Code` 等带空格短语而拒绝预热；日志记录跳过项数量。
4. 10 个模型使用同一真实 WAV 逐个完成冷加载、热加载和非空转写；失败者不进入安装版可切换列表。
5. 安装版逐个切换并录音时，日志能区分 requested engine、actual engine、fallback count 与失败原因。
6. 切换模型、录音、实时胶囊、最终识别、AI 整理和粘贴主流程无崩溃。

## 不在本轮范围

- 不把 SenseVoice 实时预览迁出主进程。
- 不为原生不支持热词的模型伪造后处理热词命中。
- 不改变智能整理、翻译或胶囊视觉设计。
