# 豆包与 MiMo 在线 ASR 旁路设计

## 状态与受众

- 状态：产品设计已批准，等待实现计划与无凭证协议测试。
- 日期：2026-07-11。
- 受众：TypeWhale 产品负责人、后续开发 Agent、架构评审与 QA。
- 维护责任：厂商协议、隐私条款、计费或产品边界变化时，由在线 ASR 集成负责人更新。

## 目标

在不改变旧本地预览、完整录音 final ASR、VAD、整理和粘贴权威的前提下，为影子胶囊增加两个可二选一的在线 Provider：火山引擎豆包 ASR 与 Xiaomi MiMo-V2.5-ASR。用户配置自己的凭证并明确选择厂商后，新录音会话才允许发送音频；任何在线失败都只终止旁路。

本阶段的产品价值是以同一胶囊、Session、Reducer 和测量口径对比本地、豆包与 MiMo 的首字延迟、修订稳定性、识别质量和资源成本，而不是立即替换生产路径。

## 官方协议证据

### 豆包 ASR

火山引擎官方资料确认大模型流式语音识别提供 WebSocket 双向流式模式，优化版地址为 `wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_async`；客户端可持续发送音频并接收中间/最终结果。该模式适合作为真正的连续 PCM Provider。

- [火山引擎语音识别产品动态与流式地址](https://www.volcengine.com/docs/6561/162929?lang=zh)
- [火山引擎豆包语音服务等级协议](https://www.volcengine.com/docs/6561/107349?lang=zh)

具体资源 ID、鉴权 Header、二进制帧结构和结果字段必须以实现时最新的官方 API 页面与开通控制台为准，不允许根据第三方示例猜测。

### Xiaomi MiMo-V2.5-ASR

Xiaomi MiMo 官方 API 使用 `POST https://api.xiaomimimo.com/v1/chat/completions`，支持 `api-key` 或 Bearer 鉴权。请求只接受单个 WAV/MP3 音频，以 Base64 或 data URL 传入；Base64 后上限 10MB。`stream: true` 表示服务端以 SSE 增量返回文本，并不表示客户端可以在同一请求中持续上传 PCM。

- [MiMo-V2.5-ASR OpenAI 兼容 API](https://mimo.mi.com/docs/zh-CN/api/audio/Speech-Recognition)
- [MiMo-V2.5-ASR 使用指南与音频限制](https://mimo.mi.com/docs/zh-CN/quick-start/usage-guide/audio/Speech-Recognition)

因此 MiMo 必须作为有界音频快照 Provider，不得被描述或实现成 WebSocket 连续音频流。

## 已批准的产品决策

- 在线旁路选项为：关闭、豆包 ASR、MiMo-V2.5-ASR；同一会话只能有一个 active Provider。
- 两个厂商使用用户自带凭证。凭证只存 macOS Keychain，设置和日志只暴露“已配置/未配置”。
- 在线旁路默认关闭。保存凭证不等于授权发送音频；只有明确选择厂商并开始下一轮录音才发送。
- 当前会话在线失败时不自动切换厂商或切回另一个影子 Provider，避免文本重复、回退和 epoch 竞态。
- 失败后旁路胶囊显示简短可诊断状态再隐藏；旧本地胶囊、完整录音 final、整理和粘贴继续运行。
- 下一轮录音重新尝试用户选择的 Provider；用户可在设置中关闭、换厂商、替换或删除凭证。
- 在真实 Key 验证完成前，在线 Provider 只能标记为“已配置/待验证”或“实验”，不能宣称生产可用。

## 方案比较与决定

### 采用：统一 Provider 契约，厂商独立 Transport

Core 只接收 `AudioFrame` 与统一 `TranscriptionEvent`。`DoubaoStreamingTransport` 负责豆包 WebSocket/二进制协议，`MiMoSnapshotTransport` 负责 WAV、Base64、HTTP 与 SSE。厂商协议不会进入 Session、Reducer、Projector 或胶囊。

这样既保留一套上层状态机，又允许两种本质不同的输入协议独立演进和测试。

### 拒绝：强制共用 OpenAI 兼容客户端

MiMo 可以使用 OpenAI 兼容请求，但豆包流式 ASR 不是同一协议。强行统一会把二进制 WebSocket、资源鉴权和流式音频细节泄漏到通用层，形成伪抽象。

### 暂不采用：TypeWhale 自建中转服务

中转服务可以隐藏终端凭证，但会增加服务器成本、音频数据责任、地区合规和新的单点故障。用户自带 Key 的本地直连更符合当前实验范围；未来若进入商业账号托管，再单独评审服务端代理。

## 架构与组件

### 设置与凭证

- `OnlineASRProviderSelection`：`off`、`doubao`、`mimoV25`。
- `OnlineASRCredentialStore`：Keychain 的保存、读取、替换、删除和存在性查询；不提供可被 UI/日志打印的描述。
- 设置页分别显示豆包、MiMo 的凭证状态和“验证连接”结果。选择未配置厂商时不启动网络请求，并明确提示先配置凭证。
- Provider 选择在录音开始时冻结到 session configuration；录音中修改设置只影响下一轮。

### 豆包 Provider

- 从现有有界 PCM fan-out 消费单声道音频，不写临时 WAV。
- Transport 建立一个会话级 WebSocket，发送配置帧后按官方 cadence 串行发送音频帧。
- 厂商中间结果映射为 `.partial`；确定句段映射为 `.finalized`；正常结束映射为 `.completed`。
- 连接、音频发送和接收各自有有界队列；音频积压或协议错误立即降级，不反压录音 tap。
- 取消必须停止发送、关闭 WebSocket 并拒绝晚到 epoch 事件。

### MiMo Provider

- 从连续 PCM 创建 Provider 私有的有界 WAV 快照，URL 不越过 Provider 边界，请求结束或失败后立即删除。
- 首个短快照用于尽早产生可见文本；后续使用有界、latest-only 快照，单请求音频与 Base64 必须低于官方 10MB 上限。
- 同一时刻最多一个 HTTP 请求。新快照到达时只保留最新待处理项，不建立无界 FIFO。
- SSE 文本增量只属于当前快照的 volatile revision；请求结束后通过边界协调器决定可确认前缀，稳定文本不得倒退。
- 取消必须取消 URLSession task、删除临时 WAV，并通过 session/epoch 拒绝晚到 SSE。

### 统一运行时

`OnlineASRProviderFactory` 根据录音开始时的选择和 Keychain 状态创建恰好一个 Provider。Provider 继续使用现有 `RealtimeTranscriptionSession → TranscriptReducer → PreviewStateProjector → ShadowPreviewCoordinator` 数据流。旧 `SpeechInputCoordinator` 只负责创建/销毁独立旁路 runtime，不消费在线文本作为生产真相。

## 数据流

### 豆包

`AudioRecorder tap → bounded PCM fan-out → Doubao Provider → WebSocket transport → vendor result decoder → TranscriptionEvent → shadow capsule`

### MiMo

`AudioRecorder tap → bounded PCM fan-out → MiMo bounded snapshot → private WAV/Base64 → HTTP/SSE transport → boundary reconciliation → TranscriptionEvent → shadow capsule`

两条路径都不得调用 `finishRecording`、修改生产 preview state、提交 final、写历史或触发粘贴。

## 密钥、隐私与费用边界

- Keychain item 以厂商和 TypeWhale bundle service 分离；删除应用配置时可单独删除每个厂商凭证。
- 禁止把 Key 放入 UserDefaults、plist、环境持久化文件、崩溃上下文、诊断日志、测试 fixture 或 git。
- 日志可记录厂商、session 短 ID、阶段、耗时、HTTP/协议状态、厂商 request/log ID、字数和音频毫秒数；禁止记录 Key、Authorization、原始音频、Base64 或完整转录文本。
- TypeWhale 不额外保存在线请求音频。Provider 私有临时文件必须在成功、失败、取消和进程恢复清理中删除。
- 厂商服务端的数据保留、训练使用、地域与计费以账号开通时条款为准。真实 Key 测试前必须记录当时条款和价格，未确认前不得默认开启。
- 产品录音上限仍为两分钟。MiMo 还必须遵守 10MB Base64 单请求上限；任何超过限制的快照在本地拒绝，不发送、不重试计费。
- 鉴权失败和 4xx 不自动重试。豆包仅允许在尚未发送音频前重连；MiMo 已提交音频后的自动重试默认关闭，避免重复计费。429/额度不足终止本会话旁路。

## 错误与状态语义

- 未配置凭证：不创建 Transport，旁路显示“请先配置在线识别”。
- 鉴权失败：标记该凭证待修复，本会话结束旁路；不删除用户凭证。
- 断网、DNS、TLS、WebSocket/SSE 中断：发出可恢复 failure，清理网络和临时资源，旧链路继续。
- 协议不兼容或未知响应：记录脱敏 request ID 和错误码，结束旁路，不猜测文本。
- 超时：连接、首字、空闲接收和总请求分别设上限；超时只取消旁路。
- 取消/录音结束：停止输入、完成或取消厂商请求、等待有界终态，随后销毁 runtime。
- 晚到结果：通过 sessionID、providerEpoch 和 sequence gate 丢弃。

## 可观察验收标准

### 无 Key 阶段

- 设置中可以二选一或关闭，默认关闭；选择状态持久化，凭证只进入 Keychain。
- 保存、替换、删除凭证均有自动化测试证明 UserDefaults 和日志不含明文。
- 豆包 fixture 能验证连接配置、二进制帧顺序、partial/final、取消、超时、429 和晚到事件隔离。
- MiMo fixture 能验证 WAV/Base64 请求、10MB 本地拒绝、SSE 任意分片、latest-only、取消、超时、429 和临时文件清理。
- 两个 fixture 都使用同一 Session/Reducer/Presenter；切换厂商不修改胶囊或通用事件。
- 无凭证、关闭在线或网络 fixture 失败时，正常录音、旧胶囊、final 和粘贴全部通过。

### 获得 Key 后

- 分别执行一次隔离连接测试，记录 endpoint、模型/资源 ID、鉴权状态和脱敏 request ID。
- 每个厂商完成 20 秒连续口述、2 分钟混合停顿、取消、断网和连续两轮测试。
- 记录连接耗时、首个非空文本、finalization、修订次数、积压、CPU/RSS、发送音频时长、响应状态和估算费用。
- 豆包必须证明是真正连续 PCM；MiMo 必须清楚标为快照响应流，不宣称实时音频上传。
- 未通过隐私、价格、地域、保留政策和实测延迟门禁前，不允许在线结果控制生产胶囊或 final。

## 测试策略

- 纯 Swift：Provider factory、选择冻结、Keychain facade、事件映射、epoch 隔离、队列容量与状态转换。
- 本地协议服务器：可编程 WebSocket/HTTP-SSE fixture，注入分片、延迟、断线、错误码和晚到消息；不访问真实厂商。
- 源码安全检查：禁止凭证进入 UserDefaults/日志，禁止 MiMo URL/Base64 越过 Provider，禁止在线 Provider 触碰 final/粘贴接口。
- 安装版：设置交互、默认关闭、无 Key 提示、在线失败 fail-open、取消和连续录音。
- 真实 Key：按厂商分开执行，不并行发送同一录音，不在验证之外产生费用。

## 风险与后续门禁

- 豆包 API 的具体资源 ID、二进制协议版本和开通权限可能变化，实现前必须再次读取最新官方 API 页面。
- MiMo 的 SSE 增量可能是 token 流而非稳定 ASR partial，必须用真实响应验证修订语义；在此之前只允许 volatile 展示。
- 两家服务的数据保留和训练条款尚未随具体账号确认，因此当前 readiness 状态为 `CONDITIONAL / EXPERIMENT REQUIRED`。
- 获得 Key 后若实测显示 MiMo 快照延迟或重复计费不适合实时旁路，应保留其离线质量对照角色，不为追求形式统一而伪装成实时 Provider。
- 本规格不授权 Stage 9 切换生产预览。任何切换仍需新的产品批准和完整对照证据。
