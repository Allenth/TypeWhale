# 豆包与 MiMo 在线 ASR 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在不改变 TypeWhale 旧本地预览、完整录音 final ASR 与粘贴权威的前提下，为影子胶囊增加可二选一的豆包流式 ASR 和 Xiaomi MiMo-V2.5-ASR 快照 Provider，并在无真实 Key 阶段完成可验证的协议、密钥和失败隔离接线。

**Architecture:** 延续现有 Strangler Migration。录音开始时，`OnlineASRProviderFactory` 根据持久化选择与 Keychain 状态创建至多一个 Provider；豆包使用会话级 WebSocket 连续发送 PCM，MiMo 使用有界 WAV/Base64 HTTP-SSE 请求。两者只产生统一 `TranscriptionEvent`，继续复用 `RealtimeTranscriptionSession → TranscriptReducer → PreviewStateProjector → ShadowPreviewCoordinator`，任何在线错误只结束旁路。

**Tech Stack:** Swift 6.2、Foundation `URLSession` / `URLSessionWebSocketTask`、Security.framework Keychain、AVFoundation WAV、现有 actor/AsyncStream Core、可注入内存 Transport fixture、`native/build_and_log.sh`。

## Global Constraints

- 在线旁路选项固定为 `off`、`doubao`、`mimoV25`；单个录音会话只允许一个 active Provider。
- 默认值必须是 `off`；保存 Key 不等于允许发送音频，只有用户明确选择厂商且下一轮录音开始才联网。
- 豆包本计划只支持新版控制台 `X-Api-Key` 鉴权，固定小时版资源 `volc.bigasr.sauc.duration` 与 `wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_async`；旧版 App ID + Access Token 不在本计划伪兼容，若用户拿到旧凭证需先更新规格。
- MiMo 固定使用 `mimo-v2.5-asr`、`POST https://api.xiaomimimo.com/v1/chat/completions`、`api-key` Header、WAV Base64 和 `stream: true`；SSE 是响应流，不得描述为持续音频上传。
- Key 只存 macOS Keychain；禁止进入 UserDefaults、plist、日志、崩溃上下文、fixture、git 或错误描述。
- MiMo 单请求 Base64 必须严格小于或等于 10MB；本计划使用更严的 9MB 客户端上限保留 JSON/data URL 余量。
- 在线 Transport 不得读写 `SpeechSession.committedPreviewText/latestPreviewText`，不得调用 `finishRecording`、VAD、final、整理、历史、OpenClaw 或 PasteCoordinator。
- 当前会话失败后不自动切换 Provider；旁路发出可恢复 failure 后结束，旧胶囊与完整 final 继续。
- 豆包音频队列必须有界并在溢出时 fail-open；MiMo 只允许一个 active request 和一个 latest pending snapshot。
- 所有临时 WAV 在成功、失败、取消和进程恢复路径删除；URL、Base64 和厂商协议对象不得越过 Provider/Transport 边界。
- 无真实 Key 阶段禁止访问真实厂商 endpoint、产生费用或声称在线已接通；只允许本地 fixture 和安装版无 Key/fail-open QA。
- 每个任务先 RED、再 GREEN；每次任务完成后更新本计划 Execution Progress，代码变更必须构建、覆盖安装并验证签名。
- UI/设置改动完成后必须执行 `design-review` 与真实安装版截图/交互复核。
- 每次写入、构建、安装、stage 或 commit 前执行分支、dirty、构建进程和 mtime 并发保护。

## Approved Source Evidence

- 豆包双向流式地址与能力：[火山引擎官方产品动态](https://www.volcengine.com/docs/6561/162929?lang=zh)。
- 豆包小时版资源 ID：[火山引擎 ResourceID 说明](https://www.volcengine.com/docs/6561/1476626?lang=zh)。
- MiMo 请求、鉴权和响应：[MiMo 官方 API](https://mimo.mi.com/docs/zh-CN/api/audio/Speech-Recognition)。
- MiMo WAV/MP3、Base64 10MB 和 SSE 示例：[MiMo 官方使用指南](https://mimo.mi.com/docs/zh-CN/quick-start/usage-guide/audio/Speech-Recognition)。

## Execution Progress

| Task | Status | Commit | Verification | Next action |
| --- | --- | --- | --- | --- |
| 0 / Readiness baseline | COMPLETE | `7beabc1` | Build 692 签名有效；3 项关键回归通过；当前无厂商 endpoint/Transport，出站请求为 0；readiness 为 CONDITIONAL | Task 0 Gate 达成；重读计划后进入 Task 1 选择/Keychain |
| 1 / Selection + Keychain | COMPLETE | `c8e65e5` | 3 项 RED/GREEN 检查通过且无 warning；Build 693 完整构建、安装、签名有效；无 endpoint/网络/UI | Task 1 Gate 达成；重读计划后进入 Task 2 通用 Provider |
| 2 / Generic Provider | COMPLETE | `dca4260` | Provider/Factory RED→GREEN；Session/Fake/Keychain/Isolation 回归通过；Build 694 覆盖安装、签名与版本核对通过；通用层无厂商/网络细节 | Task 2 Gate 达成；重读计划后进入 Task 3 豆包协议 |
| 3 / Doubao protocol | COMPLETE | `f1498e6` | 官方 ASR 协议假设已纠正；codec RED→GREEN，全部截断前缀返回类型化错误；Build 695 覆盖安装、签名与版本核对通过；无 endpoint/凭证/网络 | Task 3 Gate 达成；重读计划后进入 Task 4 有界 WebSocket Transport |
| 4 / Bounded Doubao Transport | COMPLETE | `4457d15` | fake socket RED→GREEN；容量 16、串行发送、超时、失败脱敏与一次关闭矩阵通过；完整版本 Build 696 覆盖安装、签名与版本核对通过；无真实网络 | Task 4 Gate 达成；重读计划后进入 Task 5 MiMo 协议 |
| 5 / MiMo request + SSE | COMPLETE | `9d27566` | 官方 V2.5 规格复核；请求/SSE RED→GREEN；完整 Data URL/HTTP body ≤9MB，SSE 缓冲/事件 ≤1MB；Build 697 覆盖安装、签名与版本核对通过；无网络 | Task 5 Gate 达成；重读计划后进入 Task 6 latest-only MiMo Provider |
| 6 / Latest-only MiMo Provider | COMPLETE | `892492d` | 2s/4s 调度、12s/192k 音频、单 active/单 pending、10 分钟容量、失败/取消/finish/恢复清理 RED→GREEN；Build 698 覆盖安装、签名与版本核对通过；无真实网络 | Task 6 Gate 达成；重读计划后进入 Task 7 设置 UI/会话接线 |
| 7 / Settings UI + session wiring | COMPLETE | `9c13558` | UI/隔离 RED→GREEN；生命周期、Session、Fan-out、凭证泄漏通过；Build 701 安装、打开、签名和版本核对通过 | Task 7 Gate 达成；重读计划后进入 Task 8 design-review 与真实安装版截图 |
| 8 / Design + installed QA | COMPLETE | `32c5e75` | 全量 suite、Build 702 签名、两家 fail-open、Key 表单、取消/连续录音、切回关闭及 dark/light design-review 全部通过；零在线 activity | Task 8 Gate 达成；Task 9 真实连接仍被 Key/条款/计费证据阻塞 |
| 9 / Real Key | COMPLETE — MIMO ACCEPTED | `04ace37`, `08e7d98` | MiMo 真实鉴权、请求、SSE 响应和后台计费消耗均获用户确认；豆包 48k→16k fixture 通过但产品决定不做真实 Key 验证；Build 704 安装/签名与双 Provider fixture 通过 | 本阶段以 MiMo“完整快照输入 + 流式响应”作为已验收在线旁路；豆包真实网络验证退出当前交付门禁 |

## File Map

### New domain and settings

- `native/Sources/Domain/RealtimeTranscription/OnlineASRSelection.swift`: 厂商选择、可显示名称和 session-frozen 配置值；不含凭证。
- `native/Sources/Infrastructure/Settings/OnlineASRSettings.swift`: 只持久化选择，不持久化 Key。
- `native/Sources/Infrastructure/Security/OnlineASRCredentialStore.swift`: 豆包与 MiMo 分离 Keychain service 的 load/has/save/delete。
- `native/Sources/Application/RealtimeTranscription/OnlineASRProviderFactory.swift`: 根据选择和凭证存在性创建恰好一个 Provider，返回结构化 unavailable 原因。

### New provider files

- `native/Sources/Infrastructure/RealtimeTranscription/OnlineTranscriptionProvider.swift`: 把 `OnlineProviderMessage` 映射为统一事件、执行 session/epoch/sequence gate 和终态清理。
- `native/Sources/Infrastructure/RealtimeTranscription/DoubaoASRProtocol.swift`: 请求 Header、二进制帧编码/解码和结果 DTO；无网络 I/O。
- `native/Sources/Infrastructure/RealtimeTranscription/DoubaoStreamingTransport.swift`: WebSocket 生命周期、有界发送、接收与取消。
- `native/Sources/Infrastructure/RealtimeTranscription/MiMoASRProtocol.swift`: WAV/Base64 JSON 请求、9MB 限制、任意分片 SSE parser 和响应 DTO；无 URLSession 生命周期。
- `native/Sources/Infrastructure/RealtimeTranscription/MiMoSnapshotProvider.swift`: 有界 PCM、latest-only 快照、私有 WAV、单请求和边界协调。
- `native/Sources/Infrastructure/RealtimeTranscription/MiMoHTTPTransport.swift`: URLSession request/stream/cancel；通过协议注入 fixture。

### Modified integration and UI

- `native/Sources/Infrastructure/RealtimeTranscription/OnlineStreamingProviderPort.swift`: 补充 Transport metadata、finish/cancel 终态与脱敏错误契约。
- `native/Sources/Application/SpeechInputCoordinator.swift`: 在现有 `beginShadowPreview` 中增加窄 factory 分支和在线 diagnostics；旧 debug 与 Legacy Adapter 保留。
- `native/Sources/Presentation/Main/MainViewController.swift`: 增加 Provider 下拉框和两个 Key 按钮。
- `native/Sources/Presentation/Main/MainViewController+Configuration.swift`: 配置、刷新、accessibility 和凭证状态。
- `native/Sources/Presentation/Main/MainViewController+PanelLayout.swift`: 在系统设置旁路区域放置选择/Key 控件。
- `native/Sources/Presentation/Main/MainViewController+Actions.swift`: 保存选择、Keychain 表单、删除与下一轮生效提示。
- `docs/ONLINE_STREAMING_PROVIDER_READINESS.md`: Stage 8 条件接受结论、官方证据、无 Key 结果与真实 Key 门禁。
- `docs/ARCHITECTURE.md`, `docs/SHADOW_PREVIEW_QA.md`, `docs/开发日志.md`: 行为边界与验证证据。

### New focused checks

- `native/Tests/OnlineASRSettingsCheck.swift`
- `native/Tests/OnlineASRCredentialStoreCheck.swift`
- `native/Tests/OnlineASRCredentialLeakCheck.sh`
- `native/Tests/OnlineASRProviderFactoryCheck.swift`
- `native/Tests/OnlineTranscriptionProviderCheck.swift`
- `native/Tests/DoubaoASRProtocolCheck.swift`
- `native/Tests/DoubaoStreamingTransportCheck.swift`
- `native/Tests/MiMoASRProtocolCheck.swift`
- `native/Tests/MiMoSnapshotProviderCheck.swift`
- `native/Tests/OnlineASRShadowIsolationCheck.sh`
- `native/Tests/OnlineASRSettingsUIBoundaryCheck.sh`

---

### Task 0: Freeze Stage 8 Readiness And No-Key Baseline

**Files:**
- Create: `docs/ONLINE_STREAMING_PROVIDER_READINESS.md`
- Modify: `docs/SHADOW_PREVIEW_QA.md`
- Modify: `docs/superpowers/plans/2026-07-11-realtime-transcription-shadow-capsule.md`

**Interfaces:**
- Consumes: approved design `docs/superpowers/specs/2026-07-11-doubao-mimo-online-asr-design.md` and official links above.
- Produces: `CONDITIONAL / EXPERIMENT REQUIRED` readiness status and immutable no-Key baseline for later tasks.

- [x] **Step 1: Re-run concurrency protection and installed baseline**

Run:

```bash
git branch --show-current
git status --short
pgrep -af 'build_and_log\.sh|release_local_build\.sh|build_native_app\.sh|swiftc|xcodebuild' || true
codesign --verify --deep --strict --verbose=2 '/Applications/TypeWhale Pro.app'
```

Expected: isolated branch, no unexplained overlap or build, installed signature valid.

- [x] **Step 2: Write the readiness decision**

The document must contain these exact decision fields:

```markdown
Status: CONDITIONAL / EXPERIMENT REQUIRED
Selected vendors: Doubao ASR; Xiaomi MiMo-V2.5-ASR
Selection policy: exactly one provider per recording session
Credential model: user-owned Keychain credentials
Default network behavior: off
Production authority: local old preview + complete-recording final ASR
Blocked evidence: provider retention/training terms, account pricing, real auth, latency, cancellation, rate limits
```

- [x] **Step 3: Record no-Key installed behavior**

In `docs/SHADOW_PREVIEW_QA.md`, record normal recording, cancel and final/paste with current online functionality absent. Expected: PASS and zero outbound provider request.

- [x] **Step 4: Update the parent plan without claiming implementation**

Mark Task 12 Step 1 complete only for vendor, credential, fallback and regional default decisions. Keep the real spike and final readiness incomplete.

- [x] **Step 5: Commit Task 0**

```bash
git add docs/ONLINE_STREAMING_PROVIDER_READINESS.md docs/SHADOW_PREVIEW_QA.md docs/superpowers/plans/2026-07-11-realtime-transcription-shadow-capsule.md
git commit -m "docs: record online asr conditional readiness"
```

**Gate:** documentation says planned/conditional, not connected or production-ready.

---

### Task 1: Add Session-Frozen Selection And Keychain Credentials

**Files:**
- Create: `native/Sources/Domain/RealtimeTranscription/OnlineASRSelection.swift`
- Create: `native/Sources/Infrastructure/Settings/OnlineASRSettings.swift`
- Create: `native/Sources/Infrastructure/Security/OnlineASRCredentialStore.swift`
- Test: `native/Tests/OnlineASRSettingsCheck.swift`
- Test: `native/Tests/OnlineASRCredentialStoreCheck.swift`
- Test: `native/Tests/OnlineASRCredentialLeakCheck.sh`

**Interfaces:**
- Produces: `OnlineASRProviderSelection`, `OnlineASRSettingsStore`, `OnlineASRCredentialKind`, `OnlineASRCredentialStoring`.
- Consumes: `UserDefaults` only for non-secret selection and Security.framework only for credentials.

- [x] **Step 1: Write the failing selection check**

```swift
let suite = "OnlineASRSettingsCheck.\(UUID())"
let defaults = UserDefaults(suiteName: suite)!
defaults.removePersistentDomain(forName: suite)
let store = OnlineASRSettingsStore(defaults: defaults)
precondition(store.load().selection == .off)
store.save(OnlineASRSettings(selection: .doubao))
precondition(store.load().selection == .doubao)
store.save(OnlineASRSettings(selection: .mimoV25))
precondition(store.load().selection == .mimoV25)
precondition(defaults.string(forKey: "onlineASRProviderSelection") == "mimoV25")
```

- [x] **Step 2: Run RED**

```bash
swiftc -parse-as-library -o /tmp/typewhale-online-asr-settings-check \
  native/Tests/OnlineASRSettingsCheck.swift
```

Expected: FAIL because the selection/store types do not exist.

- [x] **Step 3: Implement selection and settings**

```swift
enum OnlineASRProviderSelection: String, CaseIterable, Equatable, Sendable {
    case off
    case doubao
    case mimoV25
}

struct OnlineASRSettings: Equatable, Sendable {
    let selection: OnlineASRProviderSelection
    static let defaultValue = OnlineASRSettings(selection: .off)
}
```

`OnlineASRSettingsStore.load()` must fall back to `.off` for missing or unknown raw values.

- [x] **Step 4: Write the credential RED with an injected backend**

Define the public boundary before Security.framework:

```swift
enum OnlineASRCredentialKind: String, CaseIterable, Sendable { case doubaoAPIKey, mimoAPIKey }

protocol OnlineASRCredentialStoring: Sendable {
    func load(_ kind: OnlineASRCredentialKind) -> String?
    func has(_ kind: OnlineASRCredentialKind) -> Bool
    func save(_ value: String, for kind: OnlineASRCredentialKind) throws
    func delete(_ kind: OnlineASRCredentialKind)
}
```

The check must save two different sentinel values in an in-memory backend, replace one, delete one, and prove whitespace input deletes instead of persisting an empty key.

- [x] **Step 5: Implement Keychain services**

Use distinct services:

```swift
case .doubaoAPIKey: "com.waykingah.typewhale.pro.online-asr.doubao"
case .mimoAPIKey: "com.waykingah.typewhale.pro.online-asr.mimo-v2.5"
```

Use account `api-key` and `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`. Return localized errors containing only OSStatus, never input values.

- [x] **Step 6: Add the leak source check**

`OnlineASRCredentialLeakCheck.sh` must fail if Online ASR sources contain:

```text
UserDefaults.*apiKey
defaults.set.*Key
LaunchDiagnostics.*credential
LaunchDiagnostics.*apiKey
Authorization: Bearer \(
```

It must also assert both Keychain service strings exist and that `MainViewController` never reads `load()` to display a key.

- [x] **Step 7: Run GREEN and adjacent settings regression**

```bash
swiftc -parse-as-library -o /tmp/typewhale-online-asr-settings-check \
  native/Sources/Domain/RealtimeTranscription/OnlineASRSelection.swift \
  native/Sources/Infrastructure/Settings/OnlineASRSettings.swift \
  native/Tests/OnlineASRSettingsCheck.swift
/tmp/typewhale-online-asr-settings-check
bash native/Tests/OnlineASRCredentialLeakCheck.sh
```

Expected: both print matching `passed` lines.

- [x] **Step 8: Commit Task 1**

```bash
git add native/Sources/Domain/RealtimeTranscription/OnlineASRSelection.swift \
  native/Sources/Infrastructure/Settings/OnlineASRSettings.swift \
  native/Sources/Infrastructure/Security/OnlineASRCredentialStore.swift \
  native/Tests/OnlineASRSettingsCheck.swift \
  native/Tests/OnlineASRCredentialStoreCheck.swift \
  native/Tests/OnlineASRCredentialLeakCheck.sh
git commit -m "feat: add online asr selection and keychain credentials"
```

**Gate:** UserDefaults contains only enum selection; keys are independently replaceable/deletable and never logged.

---

### Task 2: Build A Vendor-Neutral Online Provider Runtime

**Files:**
- Create: `native/Sources/Infrastructure/RealtimeTranscription/OnlineTranscriptionProvider.swift`
- Create: `native/Sources/Application/RealtimeTranscription/OnlineASRProviderFactory.swift`
- Modify: `native/Sources/Infrastructure/RealtimeTranscription/OnlineStreamingProviderPort.swift`
- Test: `native/Tests/OnlineTranscriptionProviderCheck.swift`
- Test: `native/Tests/OnlineASRProviderFactoryCheck.swift`

**Interfaces:**
- Consumes: `OnlineStreamingTransport`, `OnlineASRProviderSelection`, `OnlineASRCredentialStoring`.
- Produces: `OnlineTranscriptionProvider`, `OnlineASRProviderFactory.make(...) -> OnlineASRProviderBuildResult`.

- [x] **Step 1: Write Provider RED**

Use an actor fixture Transport. Prove this script:

```swift
.connectionChanged(.connected)
.partial(text: "今", providerSequence: 1)
.partial(text: "今天", providerSequence: 2)
.finalized(text: "今天", providerSequence: 3)
.failed(code: "network", message: "offline", isRecoverable: true)
```

maps to connected, partial revision 1/2, finalized immutable segment and recoverable failure; `cancel()` calls `disconnect()` once and late sequence 4 is not emitted.

- [x] **Step 2: Run RED**

Compile with existing Domain/Session files. Expected: FAIL because `OnlineTranscriptionProvider` does not exist.

- [x] **Step 3: Implement Provider mapping**

Required state:

```swift
private var sessionID: TranscriptionSessionID?
private var providerEpoch = 0
private var sequence: UInt64 = 0
private var partialRevision = 0
private var finalizedIndex = 0
private var terminal = false
private var messageTask: Task<Void, Never>?
```

`start` connects before consuming messages; `append` delegates continuous PCM; `finish` calls `finishInput`; `cancel` cancels the task, disconnects and emits `.cancelled`. Provider sequence must be monotonic; duplicate/out-of-order vendor messages are ignored.

- [x] **Step 4: Write Factory RED**

Assert:

```swift
precondition(factory.make(selection: .off) == .disabled)
precondition(factory.make(selection: .doubao) == .unavailable(.missingCredential(.doubaoAPIKey)))
precondition(factory.make(selection: .mimoV25) == .unavailable(.missingCredential(.mimoAPIKey)))
```

With injected credentials and constructor closures, each selection creates only its own provider and reads only its own credential.

- [x] **Step 5: Implement factory without networking**

```swift
enum OnlineASRProviderBuildResult {
    case disabled
    case unavailable(OnlineASRProviderUnavailableReason)
    case ready(any TranscriptionProvider)
}
```

The factory accepts injected Doubao/MiMo builders. It must not embed endpoint or URLSession logic.

- [x] **Step 6: Run GREEN and Session regression**

Run the two new checks plus `TranscriptionSessionCheck`. Expected: all pass without network access.

- [x] **Step 7: Commit Task 2**

```bash
git add native/Sources/Infrastructure/RealtimeTranscription/OnlineStreamingProviderPort.swift \
  native/Sources/Infrastructure/RealtimeTranscription/OnlineTranscriptionProvider.swift \
  native/Sources/Application/RealtimeTranscription/OnlineASRProviderFactory.swift \
  native/Tests/OnlineTranscriptionProviderCheck.swift \
  native/Tests/OnlineASRProviderFactoryCheck.swift
git commit -m "feat: add vendor-neutral online transcription provider"
```

**Gate:** the generic runtime knows no endpoint, Keychain service, WAV, Base64 or vendor JSON.

---

### Task 3: Implement And Fixture-Test The Doubao Binary Protocol

**Files:**
- Create: `native/Sources/Infrastructure/RealtimeTranscription/DoubaoASRProtocol.swift`
- Test: `native/Tests/DoubaoASRProtocolCheck.swift`

**Interfaces:**
- Produces: `DoubaoASRProtocolEncoder`, `DoubaoASRProtocolDecoder`, `DoubaoASRRequestConfiguration`, `DoubaoDecodedMessage`.
- Consumes: mono Float PCM frames and official v3 binary protocol constants verified at task start.

- [x] **Step 1: Re-open official API and freeze a protocol vector**

Before editing, record in the test fixture the official header nibbles, serialization/compression flags, sequence semantics and one sanitized server response. If current official values differ from the design evidence, update this plan before code.

- [x] **Step 2: Write binary codec RED**

The test must prove:

```swift
let pcm = [Float(-1), -0.5, 0, 0.5, 1]
precondition(encoder.pcm16LE(pcm) == Data([0x00,0x80, 0x00,0xC0, 0x00,0x00, 0x00,0x40, 0xFF,0x7F]))
```

Also assert the initial configuration JSON declares mono, 16kHz, 16-bit PCM, logical request `sequence: 1` and `show_utterances`. For the optimized `bigmodel_async` SAUC endpoint, client audio frames do **not** carry an incrementing wire sequence: ordinary audio uses flag `0`, and the terminal audio frame uses documented final-without-sequence flag `2`. Server result frames may carry positive/negative sequence using flags `1`/`3`. Malformed/truncated frames return a typed error without crash.

> 2026-07-11 protocol recheck: the earlier “audio frames increment sequence / final negative sequence” wording described the server response convention, not optimized client audio framing. Current ASR reference `https://www.volcengine.com/docs/6561/1354869` and two independently maintained implementations targeting that exact endpoint agree on `0x11` protocol/header, message types `1/2/9/F`, JSON/raw serialization, optional none/gzip compression, client audio flags `0/2`, and server sequence flags `1/3`. Task 3 freezes those values in a local fixture and never contacts the endpoint.

- [x] **Step 3: Run RED**

Expected: FAIL because protocol types do not exist.

- [x] **Step 4: Implement pure codec**

No URLSession import. Use explicit byte reads/writes and `JSONSerialization`/`Codable`. Decode only documented success/error/result forms; preserve `X-Tt-Logid` separately in Transport metadata, not text events.

- [x] **Step 5: Run GREEN and fuzz truncation loop**

Test every prefix length of the valid response as invalid input; expected: no crash and typed `.truncatedFrame` or `.invalidPayload`.

- [x] **Step 6: Commit Task 3**

```bash
git add native/Sources/Infrastructure/RealtimeTranscription/DoubaoASRProtocol.swift native/Tests/DoubaoASRProtocolCheck.swift
git commit -m "feat: add doubao streaming asr protocol codec"
```

**Gate:** binary correctness is proven without credentials or real endpoint.

---

### Task 4: Add Bounded Doubao WebSocket Transport

**Files:**
- Create: `native/Sources/Infrastructure/RealtimeTranscription/DoubaoStreamingTransport.swift`
- Test: `native/Tests/DoubaoStreamingTransportCheck.swift`

**Interfaces:**
- Consumes: `DoubaoASRProtocolEncoder/Decoder`, API key supplied in memory, `AudioFrame`.
- Produces: `OnlineStreamingTransport` messages and `DoubaoTransportDiagnostics`.

- [x] **Step 1: Write a fake socket boundary**

```swift
protocol DoubaoWebSocketSession: Sendable {
    func connect(request: URLRequest) async throws
    func send(_ data: Data) async throws
    func receive() async throws -> Data
    func close() async
}
```

The production adapter wraps `URLSessionWebSocketTask`; tests use an actor storing requests and frames.

- [x] **Step 2: Write Transport RED**

Assert the request uses the fixed WSS endpoint, `X-Api-Key`, `X-Api-Resource-Id: volc.bigasr.sauc.duration`, random `X-Api-Connect-Id`, and never exposes the key in diagnostics/errors. Feed fixture partial/final/error frames and verify mapped `OnlineProviderMessage` order.

Simulate a blocked socket with more than the configured send capacity. Expected: Transport emits `.failed(code: "audio_queue_overflow", ...)`, closes once and does not await from the recorder-facing `send` indefinitely.

- [x] **Step 3: Run RED**

Expected: FAIL because Transport/socket boundary does not exist.

- [x] **Step 4: Implement actor Transport**

Use capacity 16 audio frames, one serial sender task and one receiver task. `connect` sends configuration before accepting PCM. `finishInput` enqueues the final frame and waits for documented final response up to 5 seconds. Connection timeout is 5 seconds, first-result timeout 8 seconds, idle receive timeout 10 seconds.

- [x] **Step 5: Verify failure matrix**

Fixture cases: missing credential (factory only), TLS/connect failure, malformed frame, server auth status, 429/quota status, overflow, finish timeout, user cancel and late result after disconnect.

- [x] **Step 6: Run GREEN**

Expected: request/header assertions and every failure case pass; fixture confirms no real DNS/network call.

- [x] **Step 7: Commit Task 4**

```bash
git add native/Sources/Infrastructure/RealtimeTranscription/DoubaoStreamingTransport.swift native/Tests/DoubaoStreamingTransportCheck.swift
git commit -m "feat: add bounded doubao websocket transport"
```

**Gate:** continuous PCM is bounded, cancellable and isolated; credentials are not observable.

---

### Task 5: Implement MiMo Request And SSE Protocol

**Files:**
- Create: `native/Sources/Infrastructure/RealtimeTranscription/MiMoASRProtocol.swift`
- Test: `native/Tests/MiMoASRProtocolCheck.swift`

**Interfaces:**
- Produces: `MiMoASRRequestBuilder`, `MiMoSSEParser`, `MiMoASRDelta`, `MiMoASRProtocolError`.
- Consumes: provider-local WAV `Data`, language `auto|zh|en` and API key supplied only to the HTTP request builder.

- [x] **Step 1: Write request RED**

Given a 44-byte minimal WAV fixture, assert:

```swift
request.url == URL(string: "https://api.xiaomimimo.com/v1/chat/completions")
request.httpMethod == "POST"
request.value(forHTTPHeaderField: "api-key") == sentinelKey
json["model"] == "mimo-v2.5-asr"
json["stream"] == true
inputAudio["data"].hasPrefix("data:audio/wav;base64,")
asrOptions["language"] == "auto"
```

Assert a request whose complete WAV Data URL or encoded HTTP body exceeds 9,000,000 bytes fails locally before request creation and the error contains no Base64/key. This is intentionally stricter than the official 10MB Base64-string limit; do not interpret the cap as 9MB of raw WAV because Base64 expansion would exceed the provider limit.

- [x] **Step 2: Write arbitrary SSE split RED**

Feed the same stream byte-by-byte, in CR/LF splits and as one buffer:

```text
data: {"choices":[{"delta":{"content":"今天"}}]}

data: {"choices":[{"delta":{"content":"讨论"}}]}

data: [DONE]

```

All chunkings must produce deltas `今天`, `讨论`, then completed exactly once. Malformed JSON produces a typed protocol failure.

- [x] **Step 3: Run RED**

Expected: FAIL because MiMo protocol types do not exist.

- [x] **Step 4: Implement pure request/SSE code**

The parser owns a byte buffer capped at 1MB and recognizes blank-line event boundaries. It ignores comment lines, joins multiple `data:` lines per SSE rules, and treats `[DONE]` as terminal. It must not assume one URLSession callback equals one SSE event.

- [x] **Step 5: Run GREEN**

Expected: request, size rejection, every fragmentation pattern, malformed response and `[DONE]` idempotency pass.

- [x] **Step 6: Commit Task 5**

```bash
git add native/Sources/Infrastructure/RealtimeTranscription/MiMoASRProtocol.swift native/Tests/MiMoASRProtocolCheck.swift
git commit -m "feat: add mimo asr request and sse protocol"
```

**Gate:** MiMo is correctly modeled as complete bounded audio plus streamed response, not streaming audio input.

---

### Task 6: Add Latest-Only MiMo Snapshot Provider

**Files:**
- Create: `native/Sources/Infrastructure/RealtimeTranscription/MiMoHTTPTransport.swift`
- Create: `native/Sources/Infrastructure/RealtimeTranscription/MiMoSnapshotProvider.swift`
- Test: `native/Tests/MiMoSnapshotProviderCheck.swift`

**Interfaces:**
- Consumes: continuous PCM, `MiMoASRRequestBuilder`, injectable `MiMoHTTPStreaming`.
- Produces: unified partial/finalized/failure/completed events and bounded diagnostics.

- [x] **Step 1: Define an injectable HTTP stream**

```swift
protocol MiMoHTTPStreaming: Sendable {
    func stream(_ request: URLRequest) async throws -> AsyncThrowingStream<Data, Error>
    func cancel() async
}
```

Production uses URLSession delegate bytes; fixture returns arbitrary chunks/status failures.

- [x] **Step 2: Write Provider RED**

Use 16kHz mono frames. Required schedule: first snapshot at 2 seconds, then every 4 seconds; rolling audio max 12 seconds; request max one active plus one latest pending. A slow fixture over 2 minutes must prove:

```swift
diagnostics.maximumConcurrentRequests == 1
diagnostics.maximumPendingSnapshots == 1
diagnostics.maximumBufferedSamples <= 192_000
diagnostics.maximumRequestBytes <= 9_000_000
```

After finish/cancel: current buffer, pending snapshot, active request and temp-file count are zero.

- [x] **Step 3: Verify RED**

Expected: FAIL because HTTP/Provider types do not exist.

- [x] **Step 4: Implement Provider-local WAV ownership**

Reuse the proven WAV writing mechanics from `SenseVoiceSnapshotNativeRecognizer` but do not share URLs. Each request owns a UUID temp URL; `defer` deletes it after SSE completion/error. PCM snapshot creation occurs off the audio tap and never blocks fan-out.

- [x] **Step 5: Implement revision/reconciliation**

SSE deltas accumulate one volatile string for the active snapshot. At `[DONE]`, feed complete text and snapshot audio range into `SenseVoiceBoundaryReconciler` only as an internal reusable boundary algorithm; no MiMo/WAV terminology enters public events. Confirmed text only advances; pending latest snapshot replaces older pending work.

- [x] **Step 6: Verify failure cleanup**

Fixture cases: HTTP 401, 429, 500, timeout, malformed SSE, 9MB rejection, cancel during stream, finish during active request and late completion. Every case must leave zero temp files and never call production interfaces.

- [x] **Step 7: Run GREEN and 10-minute synthetic capacity**

Feed 6000 × 100ms frames with a deterministic fast fixture. Expected: buffers/request queue remain at limits and terminal resources are zero.

- [x] **Step 8: Commit Task 6**

```bash
git add native/Sources/Infrastructure/RealtimeTranscription/MiMoHTTPTransport.swift \
  native/Sources/Infrastructure/RealtimeTranscription/MiMoSnapshotProvider.swift \
  native/Tests/MiMoSnapshotProviderCheck.swift
git commit -m "feat: add bounded mimo snapshot asr provider"
```

**Gate:** repeated complete-audio requests cannot grow unbounded or masquerade as continuous streaming.

---

### Task 7: Add Settings UI And Session-Start Factory Wiring

**Files:**
- Modify: `native/Sources/Presentation/Main/MainViewController.swift`
- Modify: `native/Sources/Presentation/Main/MainViewController+Configuration.swift`
- Modify: `native/Sources/Presentation/Main/MainViewController+PanelLayout.swift`
- Modify: `native/Sources/Presentation/Main/MainViewController+Actions.swift`
- Modify: `native/Sources/Application/SpeechInputCoordinator.swift`
- Test: `native/Tests/OnlineASRSettingsUIBoundaryCheck.sh`
- Test: `native/Tests/OnlineASRShadowIsolationCheck.sh`

**Interfaces:**
- Consumes: `OnlineASRSettingsStore`, credential store, Provider factory and current shadow runtime.
- Produces: user-visible selection/credential state and exactly-one session-frozen runtime.

- [x] **Step 1: Write UI/source RED**

Require these controls and copy:

```text
在线旁路：关闭 / 豆包 ASR / MiMo‑V2.5-ASR
豆包 Key：未配置 / 已配置
MiMo Key：未配置 / 已配置
在线音频仅在选择对应服务并开始下一轮录音后发送；不参与最终识别和粘贴。
```

The source check must assert secure fields, save/clear/cancel actions, accessibility labels and that no label/title receives `credentialStore.load`.

- [x] **Step 2: Write isolation RED**

Assert online-owned source blocks contain none of:

```text
finishRecording(
PasteCoordinator
committedPreviewText =
latestPreviewText =
startFinalRecognition(
onVoiceProbe =
```

Factory creation must appear only inside `beginShadowPreview(taskID:)` after `controller.shadowPreviewEnabled`, and the chosen `OnlineASRSettings` value must be loaded once per session.

- [x] **Step 3: Implement settings controls**

Use an `NSPopUpButton` for selection and two existing-style Key buttons. The Key form uses `NSSecureTextField`, “保存/清除/取消”, Keychain store methods and status-only refresh. Changing selection posts `.shadowPreviewSettingDidChange` but does not hot-switch an active recording.

- [x] **Step 4: Wire factory with explicit precedence**

Preserve internal debug modes first:

```text
--debug-shadow-sensevoice
--debug-shadow-fake-stream
selected online Provider
LegacyPreviewShadowAdapter
```

Online selection `.off` retains Legacy Adapter behavior. Missing credential returns unavailable, shows a short diagnostic state and does not subscribe to PCM. Ready Provider uses the existing capacity-8 fan-out and `ShadowTranscriptionRuntime`.

- [x] **Step 5: Add online summary diagnostics**

Log only:

```text
provider, session short ID, connect_ms, first_text_ms, completed_requests,
max_pending, sent_audio_ms, status_code, sanitized_request_id, terminal_reason
```

No text/key/header/Base64/path fields.

- [x] **Step 6: Run UI/isolation/lifecycle checks**

Run the two new source checks plus `ShadowPreviewLifecycleCheck`, `AudioFrameFanOutCheck` and `TranscriptionSessionCheck`. Expected: all pass.

- [x] **Step 7: Commit Task 7**

```bash
git add native/Sources/Presentation/Main/MainViewController.swift \
  native/Sources/Presentation/Main/MainViewController+Configuration.swift \
  native/Sources/Presentation/Main/MainViewController+PanelLayout.swift \
  native/Sources/Presentation/Main/MainViewController+Actions.swift \
  native/Sources/Application/SpeechInputCoordinator.swift \
  native/Tests/OnlineASRSettingsUIBoundaryCheck.sh \
  native/Tests/OnlineASRShadowIsolationCheck.sh
git commit -m "feat: add selectable online asr shadow settings"
```

**Gate:** one visible choice controls the next session only; keys remain opaque; old path is unchanged when off/missing.

---

### Task 8: Build, Install, Design-Review And Close The No-Key Gate

**Files:**
- Modify: `native/Sources/Presentation/VersionHistory/VersionHistoryViewController.swift`
- Modify: `docs/开发日志.md`
- Modify: `docs/SHADOW_PREVIEW_QA.md`
- Modify: `docs/ONLINE_STREAMING_PROVIDER_READINESS.md`
- Modify: `docs/ARCHITECTURE.md`
- Modify: this plan

**Interfaces:**
- Consumes: Tasks 1–7 and all focused checks.
- Produces: signed installed app with default-off UI and fixture-proven providers; does not claim real connectivity.

- [x] **Step 1: Run complete focused suite**

Run every new check plus existing Reducer, Session, Broadcaster, Projector, FanOut, Shadow Lifecycle/Isolation, SenseVoice Provider and final-chunk checks. Expected: all pass and `git diff --check` exits 0.

- [x] **Step 2: Update version narrative before build**

Record exact boundaries: providers configured but unverified without keys; no real audio sent; normal mode default off; old final unchanged. Add the next build/version expected by `build_and_log.sh` to version history.

- [x] **Step 3: Re-run concurrency protection and build**

```bash
git branch --show-current
git status --short
pgrep -af 'build_and_log\.sh|release_local_build\.sh|build_native_app\.sh|swiftc|xcodebuild' || true
./native/build_and_log.sh
codesign --verify --deep --strict --verbose=2 '/Applications/TypeWhale Pro.app'
```

Expected: build/install/open/signature succeeds.

- [x] **Step 4: Run installed no-Key QA**

Verify:

1. default/关闭 shows no online request and normal old capsule/final/paste;
2. select 豆包 without Key: clear guidance, no PCM subscription/network, old path normal;
3. select MiMo without Key: same behavior;
4. save/replace/delete dummy Key in Keychain UI, restart app, status persists but value never displays;
5. cancel and consecutive recordings leave no shadow task/window;
6. set selection back to 关闭 and confirm Legacy Adapter shadow behavior returns.

- [x] **Step 5: Run design-review**

Capture real installed settings screenshots and review hierarchy, provider names, status clarity, secure input, button affordance, spacing, dark/light contrast and whether privacy copy is readable without dominating the panel. Fix each finding with an atomic commit and re-build if code changes.

2026-07-12 evidence: Build 701/702 真实 dark-state 截图无布局问题；用户随后确认 secure sheet、状态反馈和 light theme 全部正常。缺 Key 即时反馈修正通过独立设计回归，无新增视觉问题。报告位于 `~/.gstack/projects/Allenth-TypeWhale/designs/design-audit-20260712-online-asr-settings/`。

- [x] **Step 6: Update readiness honestly**

Set:

```text
Protocol fixture readiness: PASS
Keychain/UI readiness: PASS
Installed fail-open readiness: PASS
Real Doubao connectivity: BLOCKED BY KEY
Real MiMo connectivity: BLOCKED BY KEY
Production readiness: NOT APPROVED
```

- [x] **Step 7: Commit Task 8**

Stage only task-owned code/docs/build synchronization and commit:

```bash
git commit -m "feat: prepare doubao and mimo asr shadow providers"
```

**Gate:** the app is safe and useful with no key, but Stage 8 remains conditional until Task 9.

---

### Task 9: Run Real-Key Vendor Spikes And Final Readiness Decision

**Blocked until:** the user supplies a current-console Doubao API Key with access to `volc.bigasr.sauc.duration`, and a Xiaomi `MIMO_API_KEY`. Never request keys in chat or commit them; the user enters them only through the installed secure forms.

**Files:**
- Modify: `docs/ONLINE_STREAMING_PROVIDER_READINESS.md`
- Modify: `docs/SHADOW_PREVIEW_QA.md`
- Modify: `docs/ARCHITECTURE.md` only if a vendor is accepted
- Modify: this plan

### 2026-07-12 MiMo Real-Frame Incident Amendment

- Installed Build 702 received real mono PCM at the device-native 48kHz rate. `MiMoSnapshotProvider` rejected the first frame because its fixture-only boundary required exactly 16kHz, so the shadow session ended before any HTTP request (`completed_requests=0`).
- The app process, old capsule, local final ASR and paste remained healthy; this is a shadow-only input-normalization defect, not a Key/authentication result.
- Before continuing Step 4, add a stateful bounded mono resampler inside the MiMo Provider boundary. Scheduling, rolling-window and WAV limits remain on the normalized 16kHz timeline; do not relabel 48kHz samples as 16kHz.
- Add a 48kHz real-device-shaped RED fixture that proves first snapshot timing, bounded buffers, request cleanup and no immediate terminal failure. Build/install and owner re-test are required before any MiMo readiness claim.
- Doubao fixtures also currently use 16kHz. Its native-device input boundary must receive a separate RED audit before the first real Doubao audio test; this amendment does not claim Doubao is safe yet.

- [ ] **Step 1: Record current account terms before sending audio**

For each vendor record official pricing unit, free quota, retention duration, training usage/opt-out, processing region, rate/concurrency limits and account resource ID. If any cannot be confirmed, status remains conditional and audio testing requires explicit owner acceptance of that uncertainty.

- [ ] **Step 2: Enter credentials through installed UI**

User pastes each key into `NSSecureTextField`; verify only “已配置” appears. Search current logs and defaults export for a unique non-secret marker, never the key itself.

- [ ] **Step 3: Test Doubao independently**

Cases: 20s continuous, 2m mixed pauses, cancel at 5s, network disabled mid-session, consecutive recordings. Record connect, first partial, finalized, revisions, max queue, sent audio, CPU/RSS, request/log IDs and estimated cost. Confirm old preview/final/paste every time.

- [ ] **Step 4: Test MiMo independently**

Same cases and metrics, plus request count, WAV/Base64 maximum, SSE first delta, snapshot completion and temp-file cleanup. Explicitly label first text as snapshot latency, not streaming-audio latency.

Partial evidence (Build 703): real auth/request path, 12–56s sessions, bounded request/pending counts, temporary-file cleanup and old final/paste passed. User confirmed recognition is good but snapshot jumps are not true streaming. Cancel/network-off/2m, exact latency instrumentation, price and retention evidence remain incomplete; Step 4 stays unchecked.

- [ ] **Step 5: Decide each vendor**

Allowed statuses: `ACCEPTED FOR SHADOW`, `CONDITIONAL`, `REJECTED`. A vendor cannot be accepted if it leaks credentials/audio, blocks old final, violates queue/file bounds, lacks confirmed retention/price, or produces stale cross-session text.

- [ ] **Step 6: Commit readiness evidence**

```bash
git add docs/ONLINE_STREAMING_PROVIDER_READINESS.md docs/SHADOW_PREVIEW_QA.md docs/ARCHITECTURE.md docs/superpowers/plans/2026-07-11-doubao-mimo-online-asr.md
git commit -m "docs: record real online asr readiness evidence"
```

**Stage 8 Exit Gate:** both selected vendors have an explicit evidence-backed status; accepted vendors remain shadow-only. Stage 9 production cutover still requires a new owner approval.

## Plan Completion Definition

The no-Key implementation phase is complete only when Tasks 0–8 pass, the signed installed app defaults off, credentials are Keychain-only, fixture protocols are bounded/cancellable, and old recording/final/paste regressions pass. The full online readiness phase is complete only after Task 9 records current terms and real-Key evidence for both vendors. No step in this plan authorizes production preview or final cutover.
