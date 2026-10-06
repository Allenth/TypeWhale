# TTS 预置音色选择设计

日期：2026-07-28
状态：已获产品负责人批准

## 目标

在 TypeWhale Pro 的“声音 → 朗读测试”中增加模型级音色选择。只接入模型权重本身提供、可离线枚举的预置音色，不接入参考音频克隆、录音导入、用户音色库或文字式 Voice Design。

本轮优先保证能力真实：官方宣称存在的音色必须先在本机通过固定验证，才能作为 TypeWhale 可选项出现。不能出现菜单可选但声音未变化、生成失败、静音或非有限采样的假能力。

## 范围

### In scope

- Qwen3-TTS 0.6B Core ML 的 9 个官方内置音色。
- Qwen3-TTS 1.7B Core ML 的 9 个官方内置音色。
- Kokoro INT8 多语言 v1.1 的 103 个官方 speaker。
- 模型级音色目录、验证状态、选择持久化、worker 协议与朗读实验室 UI。
- 中文、英文和中英混合的音色资格测试。
- Build 递增、真实安装版逐模型验证、设计复核与必要文档。

### Out of scope

- ZipVoice、CosyVoice3、MOSS-TTS 和 VoxCPM2 的参考音频克隆能力。
- 用户导入、录制、编辑或删除参考音频。
- Voice Design、情绪、风格、语速或自然语言指令控件。
- 为固定单音色 Sherpa VITS Melo 制造不存在的音色选项。
- 最终模型淘汰和资源删除。

### Do not touch

- Reader Demo。
- OpenClaw 朗读引擎、音量、语速、播放内容和打断策略。
- ASR、VAD、智能改写、粘贴与自动发送。
- 现有候选模型权重和运行时目录的删除策略。

## 能力事实

### Qwen3-TTS Core ML

TTSKit 为两档 Qwen CustomVoice 模型公开同一组 9 个内置音色：

| Voice ID | 显示名 | 原生语言/特征 |
|---|---|---|
| `ryan` | Ryan | 英语，动态男声 |
| `aiden` | Aiden | 英语，清晰阳光男声 |
| `ono-anna` | Ono Anna | 日语，轻快女声 |
| `sohee` | Sohee | 韩语，温暖女声 |
| `eric` | Eric | 中文，成都男声 |
| `dylan` | Dylan | 中文，北京男声 |
| `serena` | Serena | 中文，温和年轻女声 |
| `vivian` | Vivian | 中文，明亮年轻女声 |
| `uncle-fu` | Uncle Fu | 中文，成熟低沉男声 |

当前 TypeWhale 固定使用 `uncle-fu`。升级后首次使用仍以它为默认，避免默认听感变化。

### Kokoro v1.1

官方目录包含 103 个 speaker：

- ID 0–1：American female。
- ID 2：British female。
- ID 3–57：55 个 Chinese female。
- ID 58–102：45 个 Chinese male。

当前 TypeWhale 使用 ID 50，对应 `zf_086`。它已通过既有中文稳定性验证，因此继续作为默认。

### 固定音色模型

Sherpa VITS Melo、ZipVoice、Fun-CosyVoice3、MOSS-TTS 和 VoxCPM2 在当前 TypeWhale 推理配置中没有可直接枚举的预置音色。它们在本轮 UI 中显示“固定音色”，不接入参考音频。

## 方案选择

采用“全量验证后动态开放”：

1. 以官方预置目录建立静态、可审计的候选音色表。
2. 对 Qwen 每档 9 个音色、Kokoro 103 个 speaker 运行固定验证。
3. 只有通过全部必需样本和 WAV 校验的音色进入可选目录。
4. 失败音色保留测试证据但不出现在下拉菜单；不得影响同模型其他音色。

不采用“全部官方音色直接上线”，因为官方支持不等于当前本机适配已验证；也不采用少量精选音色，因为当前仍处于全面比较阶段。

## 领域模型

新增 `TTSLabVoice`，至少包含：

- `id`：跨进程稳定 ID。Qwen 使用字符串 voice ID；Kokoro 使用官方 speaker 名称。
- `displayName`：用户可理解的名称。
- `engineValue`：worker 实际需要的字符串或 speaker ID。
- `nativeLanguage`：原生语言提示。
- `genderCategory`：只用于 Kokoro 分组显示，不推断官方未声明信息。
- `qualification`：`unverified / passed / failed`。
- `isDefault`：模型首次使用的安全默认音色。

`TTSLabModel` 暴露已通过资格的 `voices`。模型权重状态、运行时就绪、模型资格和音色资格保持四个独立事实，不能互相覆盖。

## UI 与交互

在模型行下方增加“音色”行：

- Qwen 与 Kokoro：下拉框启用，只列出资格通过音色。
- 固定音色模型：下拉框禁用，值为“固定音色”。
- 没有任何音色通过时：下拉框禁用，值为“暂无可用音色”，播放按钮也禁用。
- 播放、准备、生成和播放音频期间，模型与音色下拉框均锁定；完成、失败或停止后恢复。
- 切换模型时立即恢复该模型上次选中的音色。
- 持久化值不存在、资格失效或目录变化时，自动回退到该模型默认音色，不显示错误弹窗。

显示文案：

- Qwen：`Uncle Fu · 中文 · 成熟低沉男声` 等。
- Kokoro：`中文女声 086 · ID 50`、`中文男声 009 · ID 58`、`Maple · 英文女声 · ID 0`。
- 不用原始 `zf_086` 作为唯一用户文案，但保留在诊断和测试记录中。

Kokoro 103 项使用菜单分组：

1. 中文女声
2. 中文男声
3. 英文音色

分组标题不可选择；模型默认音色保持实际选中状态。

## 数据流和协议

1. UI 根据当前模型读取资格通过音色目录。
2. `TTSReadingLabSettingsStore` 按模型 ID 保存 voice ID。
3. 播放时将选中的 `TTSLabVoice` 与文本、模型一起传给 `TTSReadingLabService`。
4. `TTSLabWorkerClient.synthesize` 发送标准字段 `voiceID`，并在兼容层生成引擎参数：
   - Qwen：`voiceID` 直接映射到 TTSKit voice。
   - Kokoro：目录将 `voiceID` 映射成 `speakerID`。
   - 固定音色模型：发送模型默认值，worker 忽略音色。
5. worker 回应必须回传实际使用的 `voiceID`；结果存储记录 voice ID、模型 ID 和性能指标，不保存输入原文。

不得继续把所有引擎的音色都抽象成无语义的整数 `speakerID`，否则无法安全承载 Qwen 字符串音色。

## 音色资格验证

每个候选音色至少运行：

- 中文短句。
- 英文短句。
- 中英混合短句。

每条输出必须满足：

- worker 协议成功。
- WAV 头、采样率、通道和长度有效。
- 不含 NaN/Inf。
- 不是静音。
- 不发生明显削波。
- 同模型两个不同音色对同一文本的音频内容不能完全相同；若完全相同，视为音色参数未生效。

Kokoro 已知默认 speaker 0 对中文曾产生 NaN，因此不能因为英文通过就开放；必须完成三类文本。

资格证据写在 Application Support 的实验结果目录，不修改模型权重。音色目录版本或运行时 fingerprint 变化后，旧资格不得无条件沿用。

## 错误处理

- 未知 voice ID：worker 返回受控错误，不回退到另一个音色冒充成功。
- 持久化 voice ID 失效：UI 在播放前回退到默认音色并更新存储。
- 音色生成失败：显示模型和音色的可理解名称，不暴露绝对路径。
- 生成失败或取消：删除不完整 WAV，保留既有最近成功音频。
- 固定音色模型收到外部 voice ID：拒绝或忽略必须由协议测试固定，产品 UI 不产生该请求。

## 测试与验收

### 自动化

- 官方 Qwen 9 音色表和 Kokoro 103 speaker 映射完整、ID 唯一、默认值存在。
- 设置按模型独立保存并在失效时回退。
- JSONL 协议传递和回传实际 voice ID。
- Qwen worker 不再硬编码 `uncle-fu`。
- Kokoro speaker 名称正确映射到 ID。
- 固定音色模型不启用音色控件。
- 播放期间锁定模型和音色控件。
- Reader Demo 和 OpenClaw 边界检查继续通过。

### 真实安装版

1. 两档 Qwen 均显示通过资格的内置音色，并至少选择两个中文音色生成不同有效 WAV。
2. Kokoro 显示按类型分组的通过音色，并至少选择一男一女播放成功。
3. 切换模型后各自记住音色；重启 App 后仍恢复。
4. 其余五个模型显示禁用的“固定音色”。
5. 播放、停止、重播、状态与性能指标无退化。
6. Build 号唯一，覆盖安装到 `/Applications/TypeWhale Pro.app`，启动和签名验证通过。

## 资料来源

- TTSKit 官方仓库：`https://github.com/argmaxinc/argmax-oss-swift`
- sherpa-onnx Kokoro v1.1 官方 speaker 表：`https://k2-fsa.github.io/sherpa/onnx/tts/all/Chinese-English/kokoro-multi-lang-v1_1.html`
- 本机 TTSKit `Qwen3Speaker` 源码和当前 TypeWhale worker。
