> 文档迁移（2026-09-05）：[现行文档](current/RELEASE_QA.md)。下方为迁移阶段证据，旧生产保护边界不能当作当前架构；当前发布门槛见新入口。

# TypeWhale 旁路预览迁移 QA

本文记录新实时转录核心与影子胶囊迁移过程中每个 Stage 的生产保护、自动化证据、真实安装版体验和放行结论。计划来源：`docs/superpowers/plans/2026-07-11-realtime-transcription-shadow-capsule.md`。

## Production Protection

- 旧胶囊是迁移期间唯一生产显示权威。
- 默认语音输入继续以完整录音 final ASR 作为最终识别与粘贴来源。
- 影子链路不得修改录音、VAD、自动结束、final、整理、翻译、粘贴、历史或 OpenClaw。
- 影子失败不得阻塞旧链路；关闭实验后必须恢复单胶囊，且没有残留 Task、Timer、音频订阅或窗口。
- 未通过当前 Stage Exit Gate，不得进入下一 Stage。

## Stage 0 — 旧胶囊基线冻结

### 环境

- 日期：2026-07-11
- 开发分支：`codex/realtime-transcription-shadow`
- 基线提交：`5251d72a`
- 真实安装版：`/Applications/TypeWhale Pro.app`
- 安装版版本：`2.0.6 (Build 673)`
- 签名：`codesign --verify --deep --strict` 通过
- 运行状态：真实安装版进程正在运行

### 自动化基线

| 检查 | 结果 | 说明 |
| --- | --- | --- |
| `PreviewDisplaySnapshotCheck` | PASS | stable/volatile 展示快照与长录音投影规则通过 |
| `PreviewRequestSchedulerCheck` | PASS | 现有 fast/correction 调度顺序测试通过；不代表队列容量有界 |
| `PreviewTranscriptReducerCheck` | PASS | 现有校正、时间戳、重叠与恢复规则通过 |
| `CapsuleSnapshotBufferCheck` | PASS | 结构化快照进入胶囊动画缓冲的规则通过 |
| `CapsuleTextBufferCheck` | PASS | 旧字符串路径和动画欠账上限检查退出 0 |
| `git diff --check` | PASS | Stage 0 文档写入前工作区无格式错误 |

### 真实安装版旧胶囊体验

以下两项必须由本轮真实人声操作完成；历史日志只能提供机制证据，不能代替本轮体验验收。

| Case | First visible text | Natural pause | Stop transition | Final paste | Result |
| --- | --- | --- | --- | --- | --- |
| 20 秒连续口述 | 正常 | 正常，无清空、跳变或重复 | 正常进入完整识别 | 正常整理/粘贴 | PASS（用户真实安装版反馈） |
| 2 分钟混合停顿口述 | 正常 | 1–3 秒自然停顿正常，无清空、跳变或重复 | 达到上限后正常结束并进入完整识别 | 正常整理/粘贴，第二轮无上一轮残留 | PASS（用户真实安装版反馈） |

### 失败判定

- 开始录音后胶囊未出现或明显迟于历史正常体验。
- 自然停顿导致已显示文本被清空、跳回或跨块重复。
- 达到两分钟上限后没有自动结束，或结束后无法进入完整录音识别。
- final 文本没有进入既有整理/翻译/粘贴路径。
- 第二轮录音被上一轮晚到预览更新污染。

### Stage 0 Exit Gate

- [x] 分支与 worktree 隔离安全。
- [x] 五项预览自动化基线通过。
- [x] 真实安装版版本与签名确认。
- [x] 20 秒连续口述基线通过。
- [x] 2 分钟混合停顿口述基线通过。
- [x] Stage 0 文档与开发日志已准备提交。

当前状态：`PASS`。Stage 0 Exit Gate 全部通过，允许进入 Stage 1。

## Stage 3 — 默认关闭设置与生命周期门禁

- 日期：2026-07-11
- 真实安装版：`2.0.8 (Build 680)`
- 自动化：`ShadowPreviewIsolationCheck`、`ShadowPreviewLifecycleCheck`、`TranscriptionSessionCheck` 全部通过。
- 用户真实安装版验收：设置页存在“旁路预览（实验）”，默认关闭；提示文案正确；开关可切换；关闭并重启后仍保持关闭；录音、旧胶囊、最终识别与粘贴全部正常。
- 当前阶段尚未把实时预览状态接入旁路窗口，因此开启后不出现第二胶囊符合 Task 6 边界；实时双胶囊由 Stage 4 / Task 7 实现。

### Stage 3 Exit Gate

- [x] 独立设置默认关闭且持久化正确。
- [x] 关闭设置会终止旁路订阅并隐藏窗口。
- [x] 隔离测试禁止旁路触碰录音、VAD、final、粘贴与 OpenClaw。
- [x] 用户确认真实安装版旧录音和粘贴主路径无退化。

当前状态：`PASS`。允许进入 Stage 4 / Task 7。

## Stage 4 — 旧预览实时旁路对照

- 日期：2026-07-11
- 真实安装版：`2.0.8 (Build 681)`
- 实现边界：旁路只复制旧胶囊已经消费的 `PreviewDisplaySnapshot`，不增加第二次 ASR，不写回生产状态。
- 自动化：`LegacyPreviewShadowAdapterCheck`、`ShadowPreviewIsolationCheck`、`TranscriptionSessionCheck`、`ShadowPreviewLifecycleCheck` 全部通过；安装版签名有效并已启动。
- 自动视觉验证：`design-review` 已进入真实安装版检查阶段，但 Computer Use 原生管道启动失败，无法替代真实录音动态观察。

| Case | First visible text | Text parity / revisions | Lifecycle cleanup | Final paste | Result |
| --- | --- | --- | --- | --- | --- |
| 16.3 秒连续口述 | 3909ms（生产日志） | 同一快照，12 次可见字符数变化；用户确认双胶囊正常、无异常闪烁 | 停止后正常清理 | 用户确认旧 final 正常 | PASS |
| 44.0 秒混合口述 | 1849ms（生产日志） | 同一快照，44 次可见字符数变化；用户确认稳定/修订正常 | 停止、第二轮无残留 | 用户确认旧 final 正常 | PASS |
| 96.8 秒长口述 | 1339ms（生产日志） | 同一快照，73 次可见字符数变化；用户确认双胶囊全部正常 | 停止、取消、关闭均正常 | 用户确认旧 final 正常 | PASS |

### 已接受的实验生命周期边界

- 若录音开始时旁路开关为关闭，录音过程中才重新开启，不会热加入当前会话；下一轮录音开始时生效。
- 该行为符合 Task 7 的“录音开始时创建旁路对象”设计。用户明确表示可以接受，因此不在运行中切换 Session，避免当前会话出现身份和顺序竞态。

当前状态：`PASS`。Stage 4 Exit Gate 通过，允许进入 Stage 5 / Task 8。

## Stage 5 — Fake Streaming Provider 兼容性证明

- 真实安装版：`2.0.9 (Build 682)`，签名有效。
- 自动化：`FakeStreamingProviderCheck`、`FakeStreamingShadowInjectionCheck`、`ShadowPreviewIsolationCheck`、`TranscriptionSessionCheck` 全部通过。
- 网络边界：没有真实 endpoint、API Key、厂商 SDK 或网络连接；`OnlineStreamingProviderPort` 仅为供应商无关协议。
- 当前安装版以一次性 `--debug-shadow-fake-stream` 参数运行；参数不持久化，正常重启即恢复 Legacy Adapter。

### 安装版人工门禁

- [x] 开始一轮真实录音，旧胶囊继续显示真实口述文本。
- [x] 旁路胶囊独立显示固定流式测试句，与正常预览内容无关，证明 Provider 独立驱动。
- [x] 旧 epoch 文本“旧代次”不可见。
- [x] 停止后旧 final、整理和粘贴保持正常。

首次人工观察仍显示正常预览；进程证据显示当时启动命令缺少 `--debug-shadow-fake-stream`，根因是内部测试进程被普通启动替换，并非流式状态被 UI 合并。重新以参数启动后，用户确认旁路固定脚本与旧胶囊真实内容互不相关且全部正常。验收后已恢复无参数正常启动。

当前状态：`PASS`。Stage 5 Exit Gate 通过，允许进入 Stage 6 / Task 9。

## Stage 6 前置 — Task 10 有界 PCM Fan-Out

- 安装版：`2.0.9 (Build 684)`，签名有效并已正常启动。
- 自动化：`AudioFrameFanOutCheck`、`AudioRecorderFanOutSourceCheck`、`SenseVoiceShadowSchedulerCheck`、`SenseVoiceBoundaryReconcilerCheck`、`ShadowPreviewIsolationCheck` 全部通过。
- 生产保护：PCM 只在录音 WAV 写入成功后 offer；慢旁路溢出只结束自身；旧 realtime/correction/VAD 回调保持存在。

### 真实安装版门禁

- [x] 正常麦克风录音、停止、final 和粘贴正常。
- [x] 取消一轮录音后可立即重新录音，无残留旁路或麦克风占用。
- [x] 连续两轮录音正常，第二轮无上一轮音频或文本。
- [x] 切换输入设备或模拟路由变化时，只停止当前轮，重新录音可恢复。

用户真实安装版反馈：上述路径全部正常。

当前状态：`PASS`。Task 10 Gate 通过，返回 Task 9 Step 3。

## Stage 6 — 真实 SenseVoice Shadow Provider

- 安装版：`2.0.10 (Build 687)`，签名有效。
- 默认边界：正常启动仍使用 Legacy Adapter；只有旁路开关开启且显式 `--debug-shadow-sensevoice` 参数存在时运行真实新 Provider。
- 自动化：Scheduler、Boundary Reconciler、Snapshot Provider、Native adapter cleanup、FanOut、Lifecycle 和 Isolation 检查通过。
- 资源保护：单模型并发 1；fast pending 1；correction pending 2；单次服务超过 700ms 后本会话停止新旁路推理并降级。

### 容量证据

| Duration | old_first_text_ms | shadow_first_text_ms | max_fast_pending | max_correction_pending | correction/resource degraded | provider_service_ms | main_thread_draw_ms | CPU / RSS | Result |
| --- | ---: | ---: | ---: | ---: | --- | ---: | ---: | --- | --- |
| 18.0 秒真实录音（首轮） | 340ms | <1s（同秒首个非空 render） | 1 | 1 | 0 / 0 | 223 | 0 | CPU≈285%；RSS≈1.19→2.18GB | FAIL：用户观察旧胶囊偶发卡顿 |
| 46.3 秒真实复测 | 833ms | <1s（同秒首个非空 render） | 1 | 1 | 0 / 0 | 94 | 0 | CPU peak 154.8%；RSS peak 2.15GB | PASS：用户确认旧/旁路/final 全部正常 |
| 120.1 秒 + 94.5 秒真实录音 | 835ms / 346ms | <1s / <1s | 1 | 1 | 0 / 0 | 94 / 96 | 0 | CPU avg 46.2%、peak 267.9%；RSS 2.13→2.68GB | PASS：用户确认两轮均无卡顿、越久未变慢 |
| 10 分钟合成 PCM（6000×100ms） | N/A | N/A | 1 | ≤2 | 0 / 0 | stub | N/A | harness 2.31s；RSS peak 19.2MB | PASS：窗口≤128000 samples；终态 buffer/pending/active 全归零 |

注：产品单次录音硬上限为 2 分钟，不能为了容量测试解除生产保护；10 分钟项使用同一 Provider/FanOut 的合成连续 PCM harness 验证队列与内存上界，真实安装版负责 20 秒与 2 分钟体验/资源对照。

### 修复后容量结论

- Build 689 引入生产优先 admission、fast 3 秒短窗口/2 秒 cadence、correction 8 秒窗口/10 秒 cadence 后，真实安装版三轮复测均未再出现旧预览卡顿。
- 真实 2 分钟门禁中最大缓冲固定为 384000 samples（设备 48kHz 下 8 秒），fast/correction pending 均为 1，单模型并发为 1，没有容量或资源降级。
- 10 分钟检查不解除产品 2 分钟硬上限，使用同一 Provider 的连续 PCM harness；证明录音时长增长不会扩大滚动窗口或请求队列，结束后内存持有和调度状态清零。
- RSS 峰值 2.68GB 高于短录音，但队列与 PCM 均有明确上界；后续长时观察仍需区分 Native 模型工作集与 Swift Provider 持有，不把本次测试外推成“一小时稳定”承诺。

### Stage 6 Exit Gate

- [x] Build 690 全量编译、覆盖安装、打开与签名校验通过。
- [x] 真实安装版 20 秒级与 2 分钟级旧/旁路/final 体验通过。
- [x] 10 分钟连续 PCM 证明窗口、请求和终态资源有界。
- [x] `design-review` 复用真实 Retina 静态基线，并以三轮动态用户观察和 `draw_ms=0` 日志复核节奏、闪烁、跳变与上下文保持；无新增发现，不需要 UI 修正。

当前状态：`PASS`。Stage 6 Exit Gate 已关闭，允许进入 Task 11；RSS 峰值 2.68GB 继续作为 Native 模型工作集观察项，不把本次证据外推为一小时稳定承诺。

## Stage 7 — Final Chunk 两阶段提交

- 安装版：`2.0.11 (Build 692)`，全量编译、覆盖安装、打开与签名校验通过。
- RED：旧 Recorder 源码门禁证明 final snapshot 写盘前已推进 chunk index/start 并释放缓冲，失败后没有 pending ownership、retry、fallback 或诊断。
- GREEN：`ChunkCommitStateCheck`、`PreviewFinalChunkWriteFailureCheck`、`AudioRecorderFanOutSourceCheck`、`ShadowPreviewIsolationCheck` 全部通过。
- 失败语义：final snapshot 最多写两次；重复失败保留 frozen buffers 和 ticket，完整录音成功落盘后才允许标记 `recoveredFromFullRecording` 并释放。
- 用户真实安装版验收：正常录音、自然停顿、预览、停止、final、粘贴正常；取消后可立即重录；下一轮无残留文本或卡顿。
- 安装版日志：多轮 16.1–34.7 秒录音均完成 final，识别 174–398ms；`final_chunk_snapshot_write_failed`、prepare/commit/recovery failure 均为 0。

当前状态：`PASS`。Stage 7 Exit Gate 已关闭，允许进入 Stage 8 / Task 12。

## Stage 8 Task 0 — 在线 ASR 无 Key 基线

- 安装版：`2.0.11 (Build 692)`，签名有效。
- 当前代码没有豆包/MiMo endpoint、Transport 或凭证读取，因此在线 ASR 出站请求为 0。
- 自动化：`ChunkCommitStateCheck`、`ShadowPreviewIsolationCheck`、`AudioRecorderFanOutSourceCheck` 全部通过。
- 最近人工基线：正常录音、自然停顿、final/粘贴、取消后恢复、连续录音无残留全部通过。
- 决策：在线 Provider 默认关闭、二选一、用户自带 Keychain 凭证；真实 Key 之前只能运行本地协议 fixture。

当前状态：`PASS (NO-KEY BASELINE)`。允许开始在线选择/Keychain 的无网络实现，不代表真实厂商已接通。

## Stage 8 Task 8 — 在线 ASR 设置无 Key 安装门禁（进行中）

- 安装版：`2.0.14 (Build 701)`，全量编译、覆盖安装、打开与严格签名校验通过。
- 默认状态：`onlineASRProviderSelection` 未写入 UserDefaults，按实现回退 `off`；豆包与 MiMo 两个 Keychain service 均不存在。
- 真实日志：4 轮录音均记录 `provider=legacy_adapter`，没有 `shadow_online_summary` 或豆包/MiMo Provider 活动；其中 3 轮完成本地 `final_asr_result` 和 `paste_finish outcome=restored`。
- 自动化：在线设置/Keychain/Factory/Provider、豆包协议/Transport、MiMo 协议/Provider，以及 Reducer、Session、Broadcaster、Projector、FanOut、Shadow Lifecycle/Isolation、SenseVoice Provider、final-chunk 检查全部通过。
- 视觉证据：真实安装版 dark theme 截图中，在线旁路为“关闭”，豆包/MiMo 均显示“未配置”，隐私说明可读且不压过控件；`design-review` 未发现需要代码修复的问题。
- 自动 UI 控制管道连续启动失败；为避免在用户真实录音期间误点，本轮没有使用坐标脚本或直接修改用户设置代替验收。

### 待人工确认的状态变更路径

- [x] 选择豆包但不配置 Key，下一轮录音提示缺 Key且继续本地旁路。
- [x] 选择 MiMo 但不配置 Key，下一轮录音提示缺 Key且继续本地旁路。
- [x] dummy Key 在安全表单中保存、覆盖、重启持久化、清除；全过程不显示 Key 原文。
- [x] 取消及连续两轮录音后没有残留旁路窗口或 Task。
- [x] 切回“关闭”后下一轮恢复 Legacy Adapter；亮色主题下控件、状态和隐私文案仍清晰。

当前状态：`PASS (NO-KEY GATE)`。默认关闭、零在线活动、两家缺 Key fail-open、Keychain 表单、取消/连续录音、切回关闭、旧 final/粘贴及 dark/light 视觉全部通过；不代表真实厂商连接通过。

## Stage 9A Build 711 — MiMo候选稳定性

- RED 1：`MiMoRequestPartialProjectionCheck`准确失败于请求投影类型缺失；GREEN后请求基线重放静默，真实扩展/修订保留。
- RED 2：`CandidatePresentationModelCheck`与`CandidatePreviewRenderBoundaryCheck`分别证明render model缺失、View仍持有ViewState/buffer/Timer；GREEN后View只绘制`CandidateRenderState`。
- RED 3：`CandidateWindowUpdatePolicyCheck`准确失败于策略类型缺失；GREEN证明首次show、100次相同frame不动作、一次frame变化move、hide/new session幂等。
- 自动化通过：MiMo protocol/projection/provider，Candidate buffer/model/provider matrix/window/lifecycle，Reducer、Projector、Session、Broadcaster、AudioFrameFanOut、ChunkCommitState、final-chunk、三胶囊/Shadow布局、wiring、Candidate render boundary、Shadow/Online isolation。
- Build 711当前`CandidatePreviewView`等待/增长/完成三态AppKit渲染与独立design-review通过，A-，无P0/P1/P2；同frame不置前/移动和相同目标不render均有纯策略测试。
- 安装版`2.0.18 (711)`已覆盖运行，LaunchProbe、lifecycle、hotkey启动链和deep/strict签名通过。
- 仍待owner现场观察：MiMo 20秒/2分钟闪烁、取消、连续会话；本地SenseVoice；实验关闭；dark/light真实窗口。原胶囊、final和粘贴必须保持不变；此项不由无麦克风fixture冒充。

## Stage 9A Build 712 — 本地/MiMo候选整句重播

- 真实失败视频：`$HOME/Downloads/截图/iShot_2026-07-13_16.25.08.mp4`。候选完整显示后退回“对，现在”重新逐字播放；旁路1直接展示修订结果，未重复整句打字动画。
- 本地日志：会话`28CCBA9F`在`target_chars 3→6、6→6、10→10`时反复`displayed_chars→0`；动画tick伴随连续`action=move`。
- MiMo日志：会话`13B069B4`出现`target_chars 11→22→11`，严格缩短被旧request projection当作非前缀修订放行。
- RED→GREEN：MiMo严格缩短纯投影/Provider集成、Candidate公共前缀修订、无公共前缀即时替换、Timer不重复读取frame全部通过。
- 回归通过：MiMo protocol/provider，Candidate buffer/model/provider matrix/window/lifecycle，Reducer/Projector，Candidate纯View边界、三胶囊接线、Shadow/Online isolation及AppKit typecheck。
- Build 712安装版本地日志：sequence 1首次目标3字正常从0动画；sequence 2目标6字直接`displayed_chars=6`，没有回零；sequence 3目标10字从公共前缀`displayed_chars=5`继续，后续字符全部`action=none`。构建、覆盖安装、启动链和deep/strict签名通过。
- 待owner视觉：以同一段话复看本地与MiMo，候选不得退回开头重播；修订只允许从公共前缀继续或即时替换。自动与日志门禁已经通过，不把日志代替最终肉眼动效签收。

## Stage 9A Build 713 — 候选只动画严格追加

- Build 712复测结论：FAIL。真实会话`C96528BF`中9字目标完成后，11字修订只保留1字并从`displayed_chars=1→11`播放；没有回零仍然不满足“不得从头来”。
- 新RED使用同一9→11/common-prefix-1形状，要求修订首帧`displayedText==targetText==incoming`且`needsTimer=false`；再覆盖一次同长度非前缀修订。
- GREEN规则：首次目标和严格追加保留有界逐字动效；任何非前缀、同长度或改写修订完整替换并停止Timer。Candidate不识别Provider，View不处理数据。
- 自动回归通过：Candidate buffer/model/三Provider矩阵/window/lifecycle、MiMo projection/protocol/provider、Candidate纯View边界、三胶囊接线及Shadow/Online isolation。
- AppKit design-review四帧通过：修订前稳定帧、严格追加帧、非前缀修订完整帧、同长度修订完整帧均使用当前真实组件；没有空帧、单字中间帧或视觉样式变化。
- 安装版`2.0.18 (713)`已完成build-only构建、覆盖安装、启动链和deep/strict签名；运行进程来自`/Applications/TypeWhale Pro.app`。
- Owner验收：用本地或MiMo连续口述；严格追加应继续流动，识别改写只允许一次原位替换，失败标准是候选退回句首后再次增长。原胶囊、旁路1、final和粘贴必须不变。

## Stage 9A Build 748 — 剩余真实门槛验收口径

- 安装版：`2.0.29 (Build 748)`，已通过 build-only 覆盖安装、打开与 deep/strict 签名校验。
- 当前状态：Build 747 已由真实反馈确认麦克风启动恢复正常；Build 748 只补取消/清理诊断，不改变候选、旁路、final ASR 或粘贴行为。
- 自动化边界：
  - `Stage9AManualGateBoundaryCheck.sh`：验证关闭旁路、publish、cancel/clear、shadow teardown 的源码边界。
  - `Stage9AInstalledLogGateCheck.py`：只读解析安装版日志，确认真实单胶囊与取消恢复证据。
- 当前 748 日志状态：尚无录音/取消样本；`Stage9AInstalledLogGateCheck.py` report-only 输出 `MISSING single_capsule` 与 `MISSING cancel_recovery`，`--require-complete` 返回 1。此状态表示“缺真实证据”，不是产品失败。

### Case A：关闭候选/旁路后的单胶囊路径

操作：

1. 在安装版 `2.0.29 (748)` 中关闭“旁路预览（实验）”。
2. 开始一轮正常口述，建议 10–20 秒即可。
3. 观察屏幕：只允许出现原胶囊；不得出现“旁路”或“候选”胶囊。
4. 正常停止，让 final ASR、整理和粘贴完成。
5. 运行：

```bash
native/Tests/Stage9AInstalledLogGateCheck.py
```

PASS 日志条件：

- 同一 session 有 `recording_start`。
- 同一 session 有 `recording_finish_saved`。
- 同一 session 有 `final_asr_result`。
- 有 `paste_finish`。
- 同一 session 没有 `shadow_preview_mode`、`shadow_preview_render` 或 `candidate_preview_render`。

FAIL 条件：

- 屏幕出现第二/第三胶囊。
- final 或粘贴未完成。
- 日志中该 session 出现 shadow/candidate 相关行。
- `Stage9AInstalledLogGateCheck.py` 仍输出 `MISSING single_capsule`。

### Case B：录音中取消后的恢复路径

操作：

1. 开启或关闭旁路均可；若要更强证据，建议开启旁路后开始录音。
2. 录音开始后不要正常停止，执行一次取消/中断录音的真实操作。
3. 确认胶囊隐藏，没有继续粘贴、没有残留旁路/候选窗口。
4. 立即开始下一轮正常口述并正常停止，确认 final ASR 和粘贴完成。
5. 运行：

```bash
native/Tests/Stage9AInstalledLogGateCheck.py --require-complete
```

PASS 日志条件：

- 有 `recording_cancel_requested reason=...`。
- 取消后有 `shadow_preview_teardown cancelled=true`。
- 取消后存在后续成功录音：`recording_start`、`recording_finish_saved`、`final_asr_result`、`paste_finish`。

FAIL 条件：

- 取消后发生粘贴。
- 胶囊或候选窗口残留。
- 下一轮无法启动、无预览、无 final 或无粘贴。
- `Stage9AInstalledLogGateCheck.py --require-complete` 返回非 0。

### Stage 9A 收口规则

- 只有 Case A 与 Case B 都通过，并且 `Stage9AInstalledLogGateCheck.py --require-complete` 返回 0，才允许把 Stage 9A 标记为完成。
- Stage 9A 完成也只代表旁路迁移、候选展示、取消/关闭边界与 2 分钟内体验矩阵通过；不得据此宣称“一小时/多小时长录音已根治”。

## Stage 9A Build 714 — 候选内容/动效解耦

- Build 713 owner结论：FAIL。候选不再从头重播，但旁路1与候选体验一致、动画不可感知。
- 安装日志证据：会话`F4E80286`首次6字按0→6动画；随后多数带修订增长状态直接完整显示，只有严格前缀的`16→22、59→64、65→69`继续Timer。根因位于候选Presentation内容与动效共用buffer，不是Provider缺少数据。
- 双层RED/GREEN：`CandidateContentProjectionCheck`证明完整内容即时接受且没有动画API；`CandidateTextMotionCheck`证明只按字符数保持可见进度、推进和24字欠账；Model真实9→11修订首帧显示新内容前9字并只推进2字。
- 边界门禁：ContentProjection不得出现Timer/可见进度；TextMotion不得读取字符串、ViewState或Provider；View不得读取两个内部状态。三Provider仍通过同一Model契约。
- AppKit design-review四帧：旧9字完整、新11字修订首帧9字、第10字推进、第11字完成。无旧字、空帧或1→11重播，静态视觉和窗口布局未改。
- 安装版`2.0.19 (714)`已完成完整版本构建、覆盖安装、启动和deep/strict签名，进程来自`/Applications/TypeWhale Pro.app`。
- Owner验收：本地或MiMo连续口述；旁路1应保持真实硬跳，候选应重新出现尾部推进；候选不得退回句首。原胶囊、final和粘贴必须不变。

### 2026-07-14 证据重审结论

- 当前状态：`NO-GO / OWNER ACCEPTANCE NOT MET`。Build 714 构建、安装、签名与纯状态/组件验证成立，但不能替代真实安装版动态签收。
- Build 714 日志证明 Candidate 的 `displayed_chars` 曾按字追赶；同一日志也证明本地会话使用 `provider=legacy_adapter`，停止后对完整 WAV 执行 final ASR。正确语义是“候选 Presentation 层已分层”，不是“本地转录数据层已独立”或“长录音已解决”。
- 仍缺：本地与 MiMo 20s/2m、快速突发、非前缀修订、取消、连续两轮、关闭实验、dark/light，以及同一 Build 714 下原胶囊/final/paste 无退化的 owner PASS。
- 原 Stage 9A 不得关闭，Stage 9B 与 Task 14 继续保持未批准。

## Stage 8 Task 12A — 通用在线 Provider 终态修复

- RED：`OnlineTranscriptionProviderCheck` 与 `DoubaoStreamingTransportCheck` 因 vendor-neutral `.completed` 缺失精确编译失败。
- GREEN：连续在线 transport 在 stream-final 文本后发送一个通用 completion；Provider 按序输出 `finalized -> completed`，且只 disconnect 一次并结束事件流。
- 独立评审首轮发现测试没有真正把 duplicate/late 消息送进 Provider，且缺 cancel-wins 回归；返工后增加重复 completed、晚到 partial、取消先于 server-final 和有界超时检查，复审为 `Spec PASS / Quality APPROVED`。
- 已通过 Online Provider、Doubao protocol/transport、Fake Streaming、Session、Reducer、Broadcaster、三胶囊接线、Shadow/Online isolation 与凭证泄漏回归。
- 真实豆包 Key/网络仍不在已批准门禁内；本任务只修复通用终态，不改 Candidate、MiMo、生产 final/paste 或长录音。
- 构建/安装状态：Build 715 已通过唯一入口 `./native/build_and_log.sh` 完成 build-only、覆盖安装与启动；`/Applications/TypeWhale Pro.app` 为 `2.0.19 (715)`，deep/strict 签名有效，安装版进程从该路径运行。
- Build 715 新鲜回归：`OnlineTranscriptionProviderCheck`、`DoubaoStreamingTransportCheck`、Fake Streaming 注入、Shadow/Online isolation、三胶囊接线与凭证泄漏检查全部通过；这只关闭通用在线终态缺口，不替代 Stage 9A 的真实录音体验签收。

## Stage 9A — 正常本地旁路激活真实 SenseVoice Provider

- 证据纠偏：Build 715 在线关闭/缺 Key 时仍使用 `LegacyPreviewShadowAdapter`，所以候选虽已完成 Presentation 分层，本地数据仍来自旧生产预览；不能据此证明新本地架构效果。
- RED：新增 `LocalSenseVoiceShadowRoutingCheck`，准确失败于正常本地路线缺少 SenseVoice 组装边界；旧 `OnlineASRShadowIsolationCheck` 同时保持通过，证明 RED 不是旧门禁损坏。
- GREEN：`.disabled` 与 `.unavailable(.missingCredential)` 统一通过 `makeLocalSenseVoiceShadowRuntime` 创建已验收的 `SenseVoiceSnapshotProvider`、生产优先 admission 和 Provider runtime；活动配置意外缺失时才使用 Legacy fail-open 安全网。
- 聚焦回归：本地路由、Online/Shadow isolation、SenseVoice Native source/Provider/Scheduler/Reconciler、Audio FanOut、Candidate Model/Provider Matrix/Lifecycle/Render Boundary、三胶囊接线与凭证泄漏检查通过。
- 架构复核状态：`Conditional`。单 Provider 权威、Provider/Core/Presentation 边界和关闭旁路回滚成立；双模型 CPU/RSS 与旧胶囊无卡顿仍必须由 Build 716 安装版 20 秒/2 分钟动态矩阵证明。
- 构建状态：Build 716 已通过唯一入口完成 build-only、覆盖安装和启动；安装版为 `2.0.19 (716)`，deep/strict 签名有效，进程从 `/Applications/TypeWhale Pro.app` 运行。安装后本地路由、Online/Shadow isolation、Candidate render boundary 与三胶囊接线重新通过。
- Build 716动态验收失败：真实会话`A6DEE89D`确认`provider=sensevoice_snapshot source=local_fallback`且资源有界，但新核心正文从13字反复缩至1字；用户截图时原胶囊33字、旁路1和候选仅“我要。”。截图热键日志与`sequence=16 chars=3`完全对齐。
- 根因与源码RED：10秒correction cadence大于8秒rolling/correction window；30秒真实Provider/Session测试准确失败于相邻范围`2...9`与`12...19`存在缺口。Candidate未参与数据处理。
- Build 717源码GREEN：correction cadence调整为6秒，与8秒窗口保留约2秒重叠；累计测试证明confirmed正文出现并保持append-only，后续fast partial不抹除确认前缀，健康路径不产生候选清空failure。聚焦和相邻回归全部通过。
- 构建状态：自动第42次构建按规则生成完整版本`2.0.20 (717)`；唯一入口完成全量编译、覆盖安装、启动和deep/strict签名，安装后Provider累计、本地路由、Online isolation、Candidate render boundary与三胶囊接线重新通过。
- 动态状态：仍为`NO-GO / BUILD 717 VISUAL ACCEPTANCE PENDING`。必须重新执行本地20秒/2分钟、取消、连续会话、关闭实验、原胶囊/final/paste、CPU/RSS和候选节奏后才能关闭Task 2A/Stage 9A。

## Stage 9A Build 719 — 原子时间装配与零内容欠账

- RED 精确覆盖 Build 717 三个真实失败：Core 缺少原子事件；音频重叠但 token 文字完全改写时 Reconciler 要求 recovery；Candidate 首帧可见字数为0并启动Timer。
- GREEN 新增 `.reconciled`，本地 Provider 的 fast/correction 每次成功识别只发布一个转录事件；30秒 fixture 每次用 A/B 两套不同 token 改写相同音频区间，稳定前缀仍按时间单调增长，无 `.failed`。
- Candidate Motion/Model/三 Provider Matrix/Lifecycle 证明每个接受状态 `displayedText == targetText` 且 `needsTimer == false`；Coordinator 在180ms后仍只绘制1次。
- 相邻回归首次发现 MiMo 历史上共享该 Reconciler；现已显式隔离 `audioTime` 与 `lexicalOverlap` 策略，MiMo 全量容量、回滚、取消、终态清理回归重新通过。
- 编译/安装与20秒/2分钟真实动态验收尚未记录；在新鲜日志证明无整段缩短、无hide/show、final/paste正常前，Stage 9A仍不关闭。
- Build 719 已通过唯一入口全量编译、覆盖安装、启动与deep/strict签名；安装后 Reducer、Candidate三源矩阵、本地路由、Shadow/Online isolation、三胶囊接线、纯View边界和最终WAV生命周期重新通过。
- Build 720 追加确认段时间单调门禁：RED准确失败于重叠音频范围，GREEN后30秒fixture的每个确认段均`start <= end`且后段`start >= 前段end`。完整版本`2.0.21 (720)`已构建安装、启动和签名；安装后本地Provider、MiMo全矩阵、路由/隔离/纯View/最终WAV门禁通过。
- Build 720 AppKit design-review 复核等待、原子短修订和长文本三帧：短文本当帧完整，长文本保留原有头部省略/最新尾部可见规则，无空帧、旧字残留、中间单字帧或布局/配色退化，P0/P1/P2均为无。真实麦克风动态仍待owner现场验收。

## Stage 9A Build 721 — 本地候选慢识别不再自我熔断

- Build 720 真实日志证据：21.9秒录音的WAV完整非静音，final ASR 53字且粘贴成功；但候选/旁路只渲染空态后隐藏。`shadow_sensevoice_summary`显示`resource_degraded=1 provider_service_ms=630`。
- RED→GREEN：新增慢单次识别和慢首轮识别后续恢复回归，要求慢但成功的SenseVoice影子结果仍进入`reconciled`，且不得发布清空候选UI的recoverable failure。
- 修复边界：`resourceDegradedCount`保留为诊断；超过服务预算不再取消队列、不再永久停止本地候选请求。Candidate仍只消费统一ViewState，不参与数据处理。
- 自动化：SenseVoice Provider、Candidate三源矩阵、MiMo Provider、Online Provider、Projector/Broadcaster/Session、Candidate render boundary、LocalSenseVoice routing、OnlineASR isolation和ThreeCapsule wiring均通过。
- 构建状态：`2.0.21 (721)`已通过唯一入口build-only覆盖安装、启动与deep/strict签名，安装版进程来自`/Applications/TypeWhale Pro.app`。
- 真实26.24秒录音：候选连续显示`9→20→28→39→41→48`，每次`displayed_chars == target_chars`；`resource_degraded=0`、`provider_service_ms=133`；WAV平均音量-24.1dB；final ASR 84字并粘贴成功。
- 真实短录音观察：7.8秒与1.5秒短录音final/paste正常；另有6.7秒短录音final/paste正常但影子候选为空，日志显示`resource_degraded=1 provider_service_ms=803`。这不阻塞26秒门禁，但说明短录音冷启动候选仍需继续观察。
- 当前状态：`PARTIAL PASS / 2M OPEN`。2分钟真实录音、取消、连续会话、关闭实验和原胶囊无卡顿仍未关闭；Stage 9A不得进入Stage 9B。

## Stage 9A Build 739 — 合并主线十模型 ASR 并保留候选慢识别修复

- 背景纠偏：当前安装版已进入主线 `2.0.26 (738)`，而主线缺少 Build 721 的本地候选慢识别修复；继续用旧 `2.0.21 (721)` 证据会误判 Stage 9A。
- 合并策略：把 `codex/typewhale-pro-asr-hotwords` 合入 `codex/realtime-transcription-shadow` 隔离 worktree，保留 `SenseVoiceSnapshotProvider` 中“慢识别只记诊断、不清空 UI、不永久停止候选请求”的行为和慢识别回归测试。
- 自动化：SenseVoice Provider、Candidate 内容/动画/模型/窗口策略/生命周期/三源矩阵、MiMo Provider、Online Provider、Session、Broadcaster、Projector、Candidate render boundary、LocalSenseVoice routing、OnlineASR isolation、ThreeCapsule wiring、Sherpa candidate isolation/bridge、ASR UI boundary 与 `git diff --check` 全部通过。
- 构建状态：唯一入口 `./native/build_and_log.sh` 已完成 build-only，安装版为 `/Applications/TypeWhale Pro.app` `2.0.26 (739)`；`codesign --verify --deep --strict` 通过，构建日志新增 #47。
- 当前状态：`AUTOMATION PASS / REAL 20S+2M OPEN`。仍需真实 20 秒、2 分钟、取消、连续会话、关闭实验和原胶囊/final/paste 现场验收；通过前不得关闭 Stage 9A 或进入 Stage 9B。

## Stage 8 Task 9 — MiMo 首轮真实帧事故

- Build 702：用户安全配置 MiMo Key 后，旁路在录音首帧立即结束；旧录音/final/paste 正常。
- 日志：`provider=mimoV25` 后立即 `shadow_audio_delivery_failed`；`completed_requests=0`、`sent_audio_ms=-1`，没有真实 HTTP 音频请求或费用证据。
- 根因：设备 fan-out 为 48kHz，Provider 仅接受 fixture 使用的 16kHz。
- RED→GREEN：新增 48kHz 真实设备形状测试，并在 Provider 内连续重采样至 16kHz；完整 MiMo 容量/清理和隔离回归通过。
- Build 703 全量编译、覆盖安装、打开与签名校验通过；真实在线短录音待验证，本节当前状态为 `USER RETEST`。

### Build 703 MiMo 真实在线初测

- 用户确认修复后识别质量“确实还不错”，旁路不再退出；旧胶囊、本地 final 与粘贴持续正常。
- 真实会话证据：12.4 秒完成 4 个快照请求，16.1 秒完成 5 个，56.5 秒完成 15 个；`max_pending≤1`，终态 completed，MiMo 临时目录文件数为 0。
- 渲染证据：约 2 秒出现首批文本，之后以约 4 秒快照间隔突发多条 SSE delta；用户准确反馈视觉上“一卡一卡”，不是持续逐字流式。
- 协议解释：MiMo 上传完整 WAV 快照，SSE 只流式返回该快照的文本；它不是连续音频流。不得用逐字动画或提高完整音频重复请求频率伪装成真流式。
- 凭证仍只存在 Keychain，Build 703 日志未发现 `sk-`/`tp-`/明文 `api-key` 模式；临时 WAV 清理通过。
- 当前判断：MiMo 为 `CONDITIONAL / SNAPSHOT SHADOW`。识别链路可用，但不满足“真正逐字流式”体验；价格、保留/训练条款、限流、断网和完整 2 分钟矩阵未完成前不得接受为生产或流式 Provider。

### Build 704 豆包真实设备帧前置门禁

- 在真实豆包请求前主动复现 48kHz 麦克风帧与 16kHz 协议声明不一致：旧包体为 9600 字节，正确值应为 3200 字节。
- 抽取共用连续重采样器后，豆包 48kHz × 100ms fixture 生成 1600 个 16kHz PCM16 样本；豆包与 MiMo 全量 fixture 回归通过。
- 本项只证明本地输入编码正确；Build 704 构建、安装、打开与签名通过。未配置/使用豆包真实 Key，未连接 endpoint，真实 WebSocket 测试待执行。

### Build 702 缺 Key 即时反馈修复

- 用户复测发现选择豆包/MiMo 后没有缺 Key 提示，判定为 FAIL。
- 根因：选择动作只保存 Provider；Key 检查仅发生在下一轮录音开始，而且详情可能被录音状态覆盖。
- 修复：选择未配置服务时立即显示短 Toast，并在详情区明确“不发送在线音频，下一轮继续使用本地旁路”；会话开始仍由 Factory 二次校验。
- 自动化和 Build 702 安装/签名通过；等待用户从当前 Provider 切换到另一个未配置 Provider，确认即时提示可见。
- 用户真实安装版复测：豆包与 MiMo 切换后缺 Key 即时提示均正常，Build 702 修复验收通过。
- 用户真实安装版 Keychain 表单复测：dummy Key 保存、状态显示、重启持久化、不回显原文与清除全部正常；测试期间未录音、未触发在线请求。
- 用户确认豆包与 MiMo 无 Key 录音均正常；Build 702 日志累计 12 轮 `online_status=missing_credential` 全部使用 Legacy Adapter，未出现 online summary/activity，本地 final 与粘贴持续正常。这证明 fail-open，不证明真实在线连接。
- 用户确认取消、连续两轮录音、切回关闭和亮色主题全部正常，无残留窗口/文本/Task 或可见布局问题。Task 8 无 Key 安装门禁关闭。

### 首轮失败判断

- 用户明确反馈“原预览窗口偶尔有卡顿”，这是生产退化信号，优先级高于旁路结果可见。
- 单次 Provider service 低于 700ms，说明当前熔断只看单请求延迟，无法发现两套模型并发造成的总 CPU 争用。
- 修正要求：旁路 admission 必须在生产识别忙时跳过；fast 只看短窗口并降低频率；correction 独立使用有界窗口。修复前禁止 2 分钟测试。
