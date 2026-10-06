# TypeWhale 在线流式 ASR Readiness

## Decision

Status: CONDITIONAL / EXPERIMENT REQUIRED
Selected vendors: Doubao ASR; Xiaomi MiMo-V2.5-ASR
Selection policy: exactly one provider per recording session
Credential model: user-owned Keychain credentials
Default network behavior: off
Production authority: local old preview + complete-recording final ASR
Blocked evidence: provider retention/training terms, account pricing, real auth, latency, cancellation, rate limits

日期：2026-07-11
产品批准：豆包与 MiMo 在设置中二选一；Keychain；在线失败只结束旁路；后续工程细节由产品工程负责人按最佳安全方案决定。

## Product Boundaries

- 当前 TypeWhale 安装版没有真实在线 ASR Transport，不会向豆包或 MiMo 发送音频。
- 后续实现仍默认 `off`。保存凭证不代表授权发送音频；只有用户明确选择厂商，并开始下一轮录音，才允许创建网络 Transport。
- 录音开始时冻结本轮 Provider。录音中修改设置只影响下一轮，同一会话不切换厂商。
- 旧本地胶囊和完整录音 final ASR 始终是生产权威；在线文本只进入旁路胶囊，不参与 VAD、停止、整理、历史或粘贴。
- 网络、鉴权、限流、超时或协议失败后，不在当前会话切换 Provider。旁路显示短暂诊断后结束，旧链路继续。

## Privacy, Retention And Region

- TypeWhale 客户端不额外保留在线请求音频；Provider 私有临时文件必须在成功、失败和取消后删除。
- 凭证由用户持有，只存 macOS Keychain。UserDefaults、plist、日志、测试 fixture 和仓库均不得出现明文。
- 服务端音频/文本保留时长、训练使用与退出机制尚未按具体账号条款确认，因此真实音频测试仍被阻塞。
- 首个支持区域按中国大陆账号与 endpoint 设计；港澳台及海外地域不在无凭证阶段作可用承诺。
- 设置必须在选择在线 Provider 时明确提示“音频将发送给所选在线服务，不参与最终识别和粘贴”。

## Cost Policy

- 无 Key 阶段费用上限为 0：禁止访问真实厂商 endpoint。
- 获得 Key 后，先记录官方计费单位、免费额度、限流和估算单次 20 秒/2 分钟成本，再由产品负责人通过安装版进行有限测试。
- 鉴权失败和 4xx 不自动重试。MiMo 已提交完整音频后的自动重试默认关闭；豆包只允许在尚未发送音频前重连，避免重复计费。
- 未形成价格证据前，不默认开启、不后台试连、不执行长时压力请求。

## Vendor Protocol Evidence

### Doubao ASR

- 官方提供大模型双向流式 WebSocket：`wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_async`。
- 本计划采用新版控制台 `X-Api-Key` 与小时版资源 `volc.bigasr.sauc.duration`。
- 参考：[流式能力与地址](https://www.volcengine.com/docs/6561/162929?lang=zh)、[ResourceID 说明](https://www.volcengine.com/docs/6561/1476626?lang=zh)。

### Xiaomi MiMo-V2.5-ASR

- 官方接口为 `POST https://api.xiaomimimo.com/v1/chat/completions`，模型 `mimo-v2.5-asr`，使用 `api-key`。
- 请求输入是完整 WAV/MP3 Base64，官方 Base64 上限 10MB；`stream: true` 是 SSE 响应流，不是持续上传 PCM。
- 参考：[OpenAI 兼容 API](https://mimo.mi.com/docs/zh-CN/api/audio/Speech-Recognition)、[音频限制与流式响应](https://mimo.mi.com/docs/zh-CN/quick-start/usage-guide/audio/Speech-Recognition)。

## No-Key Baseline

- 分支：`codex/realtime-transcription-shadow`。
- 安装版：`2.0.11 (Build 692)`；`codesign --verify --deep --strict` 通过。
- `ChunkCommitStateCheck`、`ShadowPreviewIsolationCheck`、`AudioRecorderFanOutSourceCheck` 通过。
- 仓库当前不存在豆包/MiMo endpoint 或网络 Transport 生产代码，因此在线 ASR 出站请求数为 0。
- 最近安装版人工证据：正常录音、自然停顿、final、粘贴、取消恢复、连续录音无残留全部通过。

## Blocked Real-Key Evidence

在以下证据补齐前，两家厂商均保持 `CONDITIONAL / EXPERIMENT REQUIRED`：

- 具体账号可用的产品/资源 ID 与真实鉴权；
- 服务端保留、训练使用和地域条款；
- 当前价格、额度、并发和限流；
- 20 秒、2 分钟连接/首字/finalization/取消/断网测量；
- 豆包 PCM 队列、MiMo 快照/Base64/临时文件的容量与清理；
- 旧胶囊、完整 final 和粘贴零退化。

## Decision Update Trigger

厂商文档、endpoint、资源 ID、计费、隐私条款变化，或用户录入真实 Key 准备测试时，必须重新审查本文。即使厂商通过 shadow 验收，生产预览切换仍需独立批准。

## Implementation Readiness Update — Build 702

- Protocol fixture readiness: PASS
- Keychain/UI readiness: PASS
- Installed fail-open readiness: PASS
- Real Doubao connectivity: NOT USER-VALIDATED / NOT A CURRENT DELIVERY GATE
- Real MiMo connectivity: ACCEPTED / SNAPSHOT INPUT + STREAMED RESPONSE
- Production readiness: NOT APPROVED

Evidence:

- Build 702 的全量在线协议、Provider、有界队列、Keychain、隔离、SenseVoice 和 final-chunk suite 通过，安装版签名有效。
- 用户确认豆包/MiMo 缺 Key 即时提示和下一轮本地 fail-open 正常；日志累计 12 轮 missing credential 均使用 Legacy Adapter，在线 activity 为零，本地 final/paste 正常。
- dummy Key 的安全输入、保存、覆盖、重启持久化、不回显和清除全部通过；测试期间未录音，不产生无效网络请求。
- 取消、连续两轮、切回关闭及 dark/light theme 均通过；design-review 未发现需要代码修复的问题。
- 未使用真实 Key、未发送在线音频、未产生费用。真实鉴权、延迟、限流、取消、断网、计费和服务端保留条款仍须 Task 9 spike。

### MiMo Build 703 Real-Key Evidence

- Real authentication and request/response path succeeded after fixing 48kHz device PCM normalization.
- Observed sessions completed 2–15 bounded snapshot requests with `max_pending≤1`; temporary WAV files returned to zero and local final/paste remained healthy.
- The user rated recognition positively but rejected the experience as continuous streaming. This is consistent with the API contract: complete WAV snapshots are uploaded, while SSE streams only each snapshot's response text.
- MiMo must be presented and evaluated as snapshot shadow ASR, not continuous-audio streaming. Increasing snapshot frequency would repeat more complete audio, increasing cost/traffic without changing this semantic boundary.
- Current status is `CONDITIONAL / SNAPSHOT SHADOW`, pending confirmed pricing, retention/training terms, rate limits, disconnect/cancel matrix and 2-minute measurement. It is not approved for production or as the product's true-streaming option.

### Product Acceptance Update — 2026-07-12

- 用户确认 MiMo 在线识别可正常使用，并在 MiMo 后台看到了对应消耗，真实鉴权、音频上传、SSE 响应与账号计费链路据此验收通过。
- 用户决定不继续执行豆包真实 Key 验证；豆包代码和 fixture 保留，但真实网络连接不再是本阶段交付门禁，也不得被表述为用户已验证可用。
- 当前获准使用的在线旁路是 MiMo“完整音频快照输入 + 流式文本响应”。该验收不把 MiMo 描述为持续麦克风 PCM 双向流，也不改变旧本地预览、完整录音 final 与粘贴的生产权威。
- MiMo 的 2 秒首快照、后续约 4 秒一批是已知体验边界；不通过假逐字动画或无成本评估的高频重复上传伪装成持续音频流。

### Candidate Stability Update — Build 711

- MiMo仍是“完整音频快照输入 + SSE文本响应”，没有改成持续PCM上行，也没有提高快照频率。
- 请求级SSE从头重放由MiMo Provider内部的request projection处理；snapshot ID、基线和重放判断不进入通用Reducer、Projector或Candidate View。
- 自动化fixture证明后续请求的短前缀不会再形成统一partial回退，真实扩展与非前缀修订仍会输出。
- 本地SenseVoice快照、本地流式fixture和MiMo继续共享同一候选presentation model；Candidate生产源码厂商/Provider边界扫描通过。
- 该更新只提升旁路候选体验与诊断，不改变生产就绪判断：MiMo真实连接保持已验收的snapshot shadow，Stage 9B正式预览切换仍未批准。

### Cross-Snapshot Rollback Update — Build 712

- Build 711真实MiMo日志暴露`target_chars 11→22→11`，证明旧过滤只处理前缀重放，未处理非前缀严格缩短；Build 712在MiMo请求partial和完成快照两处阻止回退覆盖已投影全文。
- 本地`legacy_adapter`与用户视频同时证明候选整句重播是通用展示过渡问题。Candidate现在保留最长公共前缀、只动画变化后缀；无公共前缀立即替换，仍不包含厂商判断。
- 该修复不把MiMo升级为连续PCM在线流，也不改变snapshot shadow的生产就绪结论；Stage 9B继续未批准。

### Append-Only Candidate Motion — Build 713

- Build 712安装日志证明最长公共前缀可能只有1字，随后动画剩余10字仍会被用户正确感知为“从头来”；因此公共前缀不是可靠的候选动效边界。
- 通用Candidate现在只动画严格追加的新尾部。MiMo、本地快照或未来Provider只要产生非前缀/同长度修订，候选就首帧完整替换，不在UI重放修订内容。
- 该规则不伪造MiMo的持续音频流能力，也不改变Provider输出、Reducer真相或snapshot shadow就绪结论；Stage 9B继续未批准。

### Candidate Content/Motion Separation — Build 714

- Build 713真实日志证明MiMo和本地快照即使总体变长也常带非前缀修订，单纯把修订设为即时替换会让候选几乎没有动画；这不是MiMo未返回数据，而是候选Presentation职责耦合。
- Build 714完整内容始终由ContentProjection立即接受；TextMotion只维护字符可见进度。Provider修订不会重置进度，Motion也不能过滤、改写或推断Provider内容。
- 候选尾部推进仍是客户端产品展示，不代表MiMo持续PCM上传或服务器逐字产出；MiMo保持snapshot shadow结论，Stage 9B未批准。
