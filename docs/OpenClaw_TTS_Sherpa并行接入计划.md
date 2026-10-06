> 文档迁移（2026-09-05）：[现行文档](current/ARCHITECTURE.md)。下方为历史计划，现行 TTS 已采用 ZipVoice；不再作为待执行的默认路线。

# OpenClaw TTS Sherpa 并行接入计划

日期：2026-07-11
分支：`codex/typewhale-pro-asr-hotwords`
状态：执行计划，尚未代表已完成实现

## 目标

在不破坏现有 MeloTTS Python 朗读链路的前提下，将已验证听感可接受的 `sherpa stock 44.1k` 作为第二条 OpenClaw 朗读引擎并行接入。

本轮按用户要求采用约 2 小时的执行切片，优先完成可验证架构骨架，而不是一次性完成所有产品化细节。

## 当前事实

- 当前主线已合入 MeloTTS Python 方案：
  - 语音包目录：`Models/tts/melotts-zh`
  - 运行方式：`openclaw_tts_worker.py` 调用 `melo.api.TTS`
  - 资源要求：固定 Python runtime、`models/melotts-chinese`、`models/bert-base-multilingual-uncased`、`nltk_data`
- 用户确认的 Sherpa 方案是另一条路线：
  - 本地验证目录：`/tmp/typewhale-tts-candidates/sherpa/vits-melo-tts-zh_en`
  - 核心文件：`model.onnx`、`lexicon.txt`、`tokens.txt`、`dict/`、`number.fst`、`phone.fst`、`date.fst`
  - 运行方式：`sherpa-onnx OfflineTts`
  - 输出采样率：`44100 Hz`
  - 不依赖 BERT、MeloTTS 官方 Python 包或运行时联网补依赖

## 两小时执行切片

### Phase 1：并行架构骨架

交付：

- 新增 `OpenClawVoiceEngine`，至少包含：
  - `melotts`
  - `sherpa_melo_44k`
- `OpenClawVoiceSettings` 增加 `engine` 字段。
- 默认值保持 `melotts`，不改变现有用户行为。
- 设置存储支持保存/读取引擎；旧配置缺失时回退到 `melotts`。
- 新增 `SherpaMeloTTSVoicePack`，负责校验 Sherpa 44.1k 模型包。
- 模型管理列表新增 `Sherpa 极速中文 44.1k` 条目，并使用独立目录：

```text
Models/tts/sherpa-vits-melo-tts-zh_en
```

验收：

- 现有 MeloTTS 默认设置不变。
- 缺少 Sherpa 模型时不影响 MeloTTS。
- Sherpa 包校验能区分缺少 `model.onnx`、`lexicon.txt`、`tokens.txt`、`dict/` 等情况。

### Phase 2：Worker 双引擎基础能力

交付：

- `openclaw_tts_worker.py` 新增 `--engine` 参数。
- `engine=melotts` 继续走现有 `MeloTTSRunner`。
- `engine=sherpa_melo_44k` 新增 `SherpaMeloRunner`，使用 `sherpa_onnx.OfflineTts`。
- 两套 runner 保持统一 JSONL 命令：
  - `warmup`
  - `synthesize`
  - `shutdown`
- 保持离线约束，worker 不在运行时联网下载模型或依赖。

验收：

- worker 单测能 mock 两套引擎并生成合法 WAV。
- MeloTTS 旧测试继续通过。
- Sherpa runner 能通过本地模型包路径生成 WAV。

## 暂不做

- 不把默认引擎切到 Sherpa。
- 不删除 MeloTTS Python 方案。
- 不恢复 Qwen3-TTS、CosyVoice2、音色、角色选择。
- 不引入原生 sherpa-onnx TTS bridge；该路线等 Sherpa Python sidecar 验证稳定后再评估。
- 不运行时下载 BERT、MeloTTS 依赖或 Sherpa 模型。

## 后续阶段

### Phase 3：播放器路由

- `OpenClawVoicePlayer` 根据设置选择 backend。
- active sidecar 绑定 `engine + packDirectory`。
- 切换 engine 时释放旧 sidecar。
- 日志统一带 `engine` 字段。

### Phase 4：设置页与模型状态完善

- 设置页暴露“朗读引擎”选择。
- 缺模型时显示未就绪。
- 模型管理器支持下载、校验、修复、删除 Sherpa 语音包。

### Phase 5：安装版试听与默认值决策

- 安装版对比 MeloTTS 与 Sherpa。
- 记录首句延迟、内存、CPU、听感。
- 用户确认后再决定是否把默认值切为 `sherpa_melo_44k`。

## 回滚

- 若 Sherpa worker 或包校验失败，隐藏或禁用 `sherpa_melo_44k` 选项即可。
- `melotts` 路径必须保持可用。
- 旧设置中缺少 engine 字段时必须回退到 `melotts`。

## 关键禁止事项

- 禁止把 Sherpa ONNX 包复用 `MeloTTSVoicePack` 校验。
- 禁止把 Sherpa 方案命名为 MeloTTS，避免和当前 MeloTTS Python 路线混淆。
- 禁止让 Sherpa worker 依赖 `melo.api.TTS`、BERT 或 NLTK。
- 禁止为了接入 Sherpa 改动 OpenClaw 消息 UI、胶囊逻辑、ASR 链路或当前 MeloTTS 资源结构。
