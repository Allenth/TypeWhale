# OpenClaw TTS Continuity and Voice Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 消除 OpenClaw 长回复朗读中的大量等待停顿，并让小龙虾音色列表自动同步声音页的四个预置音色和有效个人音色。

**Architecture:** 保留唯一 ZipVoice worker 和现有参考音色，不裁剪音频、不更换模型。将文本预处理改为“先规范化、过滤无声片段、再按自然句边界合并为可持续预取的块”，并让播放队列在单块失败时继续处理后续块。音色能力以 `TTSLabVoiceCatalog` 为唯一预置目录，统一组合资格证据和本机个人音色发现结果，Reader Demo 与 OpenClaw 使用同一份可用音色列表。

**Tech Stack:** Swift/AppKit、AVFAudio、ZipVoice sherpa-onnx worker、现有 Swift executable checks、shell source checks、Python worker tests。

## Global Constraints

- P0：OpenClaw 1.25× 播放 300–500 字中文回复时不得持续显示“等待下一段”，人为额外停顿总量目标小于 0.5 秒。
- P0：Markdown 分隔线、空行、独立引号、emoji-only 内容不得进入 ZipVoice 请求，也不得中断后续播放。
- P0：小龙虾必须显示声音页当前可用的全部 ZipVoice 音色；有效“我的声音”保存后可选择，损坏或不存在时不显示。
- P1：1.5× 播放允许短暂缓冲，但同一 300–500 字样本额外停顿目标小于 3 秒。
- 不改变四个预置音色的参考包、哈希、资格指纹或声线。
- 不使用固定裁头、裁尾或交叉淡化掩盖停顿。
- 不增加 Python、Conda 或 Homebrew 依赖；继续复用安装包已有 ZipVoice runtime。
- 不修改 ASR、VAD、OCR、翻译、剪贴板、Reader Demo 播放行为或 OpenClaw 回复生成逻辑。
- 实现后必须递增 build 号，更新版本历史与开发日志，安装到 `/Applications/TypeWhale Pro.app` 并完成真实安装版验证。

---

### Task 1: 统一 Reader Demo 与 OpenClaw 的可用音色目录

**Files:**
- Modify: `native/Sources/Infrastructure/TTSLab/TTSLabVoice.swift`
- Modify: `native/Sources/Infrastructure/Settings/OpenClawVoiceSettings.swift`
- Modify: `native/Sources/Presentation/Main/MainViewController+TTSReadingLab.swift`
- Modify: `native/Sources/Presentation/Main/MainViewController+PanelLayout.swift`
- Test: `native/Tests/TTSLabVoiceCatalogCheck.swift`
- Test: `native/Tests/OpenClawVoiceSettingsCheck.swift`

**Interfaces:**
- Produces: `TTSLabVoiceCatalog.availableVoices(qualificationStore:personalVoiceStore:) -> [TTSLabVoice]`
- Produces: `OpenClawVoiceSettings.normalized(availableVoiceIDs:) -> OpenClawVoiceSettings`
- Consumes: `TTSLabVoiceQualificationStore.qualifiedVoiceIDs(modelID:fingerprint:)`
- Consumes: `TTSLabPersonalVoiceStore.discoverVoice()`

- [ ] **Step 1: 写出失败测试，证明音色同步边界**

在 `TTSLabVoiceCatalogCheck.swift` 增加隔离目录测试，要求：

```swift
let voices = TTSLabVoiceCatalog.availableVoices(
    qualificationStore: qualificationStore,
    personalVoiceStore: personalStore
)
precondition(voices.map(\.id) == [
    "zipvoice-default",
    "zipvoice-serena",
    "zipvoice-cosy",
    "zipvoice-video-reference",
    "zipvoice-my-voice",
])
```

再删除或破坏个人音色 manifest，断言 `zipvoice-my-voice` 不再出现。更新 `OpenClawVoiceSettingsCheck.swift`，断言有效个人音色 ID 被保留，不可用 ID 回退到 `zipvoice-default`。

- [ ] **Step 2: 运行测试并确认当前实现失败**

Run:

```bash
swiftc native/Sources/Infrastructure/TTSLab/TTSLabVoice.swift \
  native/Sources/Infrastructure/TTSLab/TTSLabVoiceQualificationStore.swift \
  native/Sources/Infrastructure/TTSLab/TTSLabPersonalVoiceStore.swift \
  native/Tests/TTSLabVoiceCatalogCheck.swift -o /tmp/typewhale-voice-catalog-check
```

Expected: FAIL，因为 `availableVoices` 尚不存在，OpenClaw 仍只接受硬编码四音色。

- [ ] **Step 3: 将资格过滤和个人音色发现集中到唯一目录**

在 `TTSLabVoiceCatalog` 增加：

```swift
static func availableVoices(
    qualificationStore: TTSLabVoiceQualificationStore = .init(),
    personalVoiceStore: TTSLabPersonalVoiceStore = .init()
) -> [TTSLabVoice] {
    let qualified = qualificationStore.qualifiedVoiceIDs(
        modelID: retainedModelID,
        fingerprint: fingerprintValue
    )
    var voices = candidates(for: retainedModelID).filter { qualified.contains($0.id) }
    if let personal = personalVoiceStore.discoverVoice() {
        voices.append(personal)
    }
    return voices
}
```

Reader Demo 初始化和保存个人音色后的刷新都调用该接口，不再自行拼接列表。

- [ ] **Step 4: 让 OpenClaw 设置按动态可用列表校验**

移除 `OpenClawVoiceSettings.allowedVoiceIDs` 和重复的 `displayName(for:)` switch。菜单直接使用 `[TTSLabVoice]` 的 `menuTitle`/`displayName` 与 `id`；设置归一化显式接收 `Set<String>`，若已保存的个人音色被删除或损坏则回退默认音色。

- [ ] **Step 5: 运行音色目录与设置测试**

Run:

```bash
./native/Tests/OpenClawZipVoiceBoundaryCheck.sh
./native/Tests/OpenClawVoiceSettingsTabCheck.sh
```

Expected: PASS；四个预置音色顺序不变，有效个人音色作为第五项出现，不存在的音色不会残留。

- [ ] **Step 6: 提交独立音色同步改动**

```bash
git add native/Sources/Infrastructure/TTSLab/TTSLabVoice.swift \
  native/Sources/Infrastructure/Settings/OpenClawVoiceSettings.swift \
  native/Sources/Presentation/Main/MainViewController+TTSReadingLab.swift \
  native/Sources/Presentation/Main/MainViewController+PanelLayout.swift \
  native/Tests/TTSLabVoiceCatalogCheck.swift \
  native/Tests/OpenClawVoiceSettingsCheck.swift
git commit -m "fix(tts): synchronize OpenClaw voice catalog"
```

---

### Task 2: 用自然分块替换逐标点短句切分

**Files:**
- Modify: `native/Sources/Infrastructure/OpenClaw/OpenClawVoicePlayback.swift`
- Test: `native/Tests/OpenClawVoicePlaybackCheck.swift`

**Interfaces:**
- Produces: `OpenClawVoiceRuntime.speechSegments(from:targetCharacters:maximumCharacters:) -> [String]`
- Produces: `OpenClawVoiceRuntime.isSpeakable(_:) -> Bool`

- [ ] **Step 1: 用真实 OpenClaw 样本写失败测试**

测试必须覆盖本次提取的 327 字珍珠故事，并断言：

```swift
let segments = OpenClawVoiceRuntime.speechSegments(from: openClawSample)
precondition((4...6).contains(segments.count))
precondition(segments.allSatisfy { (40...100).contains($0.count) })
precondition(!segments.contains("\""))
precondition(segments.joined().contains("好，讲一个。海里有一只小蚌壳"))
precondition(segments.joined().contains("讲完了，效果怎么样？"))
```

另加仅包含 `---`、反引号、引号和 emoji 的输入，断言不会生成无声请求；有文字的 emoji 前缀内容仍保留可朗读文字。

- [ ] **Step 2: 运行测试并确认当前 21 段实现失败**

Run:

```bash
swiftc native/Sources/Infrastructure/Settings/OpenClawVoiceSettings.swift \
  native/Sources/Infrastructure/OpenClaw/OpenClawTTSBackend.swift \
  native/Sources/Infrastructure/OpenClaw/OpenClawVoicePlayback.swift \
  native/Tests/OpenClawVoicePlaybackCheck.swift \
  -o /tmp/typewhale-openclaw-playback-check
/tmp/typewhale-openclaw-playback-check
```

Expected: FAIL；当前样本产生 21 段，并包含五个独立引号段。

- [ ] **Step 3: 实现规范化后的自然分块**

切分流程固定为：

1. 运行现有 Markdown/URL 清理。
2. 删除 worker 也会清除的纯符号内容，确保 Swift 与 worker 的“可朗读”定义一致。
3. 先识别自然句子，但不立即创建请求。
4. 累积到目标 60 字后才在最近句末 flush。
5. 单块硬上限 100 字；超过时优先逗号边界，其次字符边界。
6. 末尾不足 40 字时合并到前一块，只要不超过 100 字。

短回复小于 100 字直接整段生成，避免“好。”这类 1 秒音频成为首块。

- [ ] **Step 4: 运行切分测试**

Expected: 珍珠故事形成 4–6 个自然块，不存在独立引号/分隔线请求，原有 Markdown 清理和 URL 文本保留测试继续通过。

- [ ] **Step 5: 提交独立切分改动**

```bash
git add native/Sources/Infrastructure/OpenClaw/OpenClawVoicePlayback.swift \
  native/Tests/OpenClawVoicePlaybackCheck.swift
git commit -m "fix(tts): group OpenClaw replies into natural speech chunks"
```

---

### Task 3: 修复预取失败后的队列连续性并加入缓冲指标

**Files:**
- Modify: `native/Sources/Infrastructure/OpenClaw/OpenClawVoicePlayback.swift`
- Test: `native/Tests/OpenClawVoicePlaybackCheck.swift`
- Test: `native/Tests/OpenClawVoicePlaybackIntegrationCheck.sh`

**Interfaces:**
- Produces: 队列 helper，在当前块播放期间持续跳过不可生成块并预取下一可生成块
- Produces: 日志字段 `buffer_wait_seconds`、`segment_index`、`segment_count`

- [ ] **Step 1: 写失败测试模拟中间块生成失败**

使用可注入 fake backend，输入三块 `A / invalid / C`：

```swift
backend.resultByText["invalid"] = .failure(TestError.expected)
player.speak(["A", "invalid", "C"])
precondition(backend.requestedTexts == ["A", "invalid", "C"])
precondition(audioProbe.playedTexts == ["A", "C"])
```

断言失败块被记录，但不会令内层播放链结束，也不会丢失 C。

- [ ] **Step 2: 运行测试并确认失败**

Expected: FAIL；当前 `prefetchError` 会令 `current = nil`，结束预取链。

- [ ] **Step 3: 改为“取下一可播放块”的循环**

将一次性 `nextRequest` 预取改为：

```swift
while let candidate = dequeueNextRequest() {
    do {
        return try synthesizeTimed(candidate)
    } catch {
        logPrefetchFailure(candidate, error: error)
        continue
    }
}
return nil
```

保持现有打断、取消和输出 WAV 清理语义；取消事件不得被当成普通失败吞掉。

- [ ] **Step 4: 记录真实缓冲等待而不是只记录合成耗时**

每个块记录从前一音频播放结束到下一音频开始的 `buffer_wait_seconds`。该指标仅写诊断日志，不记录朗读正文。

- [ ] **Step 5: 运行队列、取消和边界测试**

Run:

```bash
./native/Tests/OpenClawVoicePlaybackIntegrationCheck.sh
./native/Tests/OpenClawTTSBackendBoundaryCheck.sh
```

并运行现有 `SherpaNativeTTSBackendCancellationCheck.swift`。Expected: PASS；失败块可跳过，用户打断仍能立即停止 worker 和播放器。

- [ ] **Step 6: 提交队列连续性改动**

```bash
git add native/Sources/Infrastructure/OpenClaw/OpenClawVoicePlayback.swift \
  native/Tests/OpenClawVoicePlaybackCheck.swift \
  native/Tests/OpenClawVoicePlaybackIntegrationCheck.sh
git commit -m "fix(tts): keep OpenClaw prefetch queue alive after failures"
```

---

### Task 4: 实机性能、音质和 UI 验收

**Files:**
- Modify: `native/Sources/Presentation/VersionHistory/VersionHistoryViewController.swift`
- Modify: `docs/开发日志.md`
- Modify: `docs/构建日志.md`（由构建脚本追加）

**Interfaces:**
- Consumes: Tasks 1–3 的统一音色目录、自然分块和连续预取。

- [ ] **Step 1: 用固定样本建立性能门禁**

使用本次 327 字珍珠故事和一段 500 字 Markdown 回复，分别以视频音色、Serena、CosyVoice 和“我的声音”运行。记录首音时间、总生成时间、音频时长、实际 `buffer_wait_seconds`。

Expected:

- 1.25×：单样本额外等待总量 `< 0.5s`，无单次 `> 0.3s` 停顿。
- 1.5×：单样本额外等待总量 `< 3.0s`。
- 日志无 `text is empty after ZipVoice normalization`。

- [ ] **Step 2: 做真人听感回归**

重点听：

- “好，讲一个”不丢“好”字。
- 引号处没有 2–3 秒空档。
- 段落间保留自然停顿，但不按每个换行额外停顿。
- 四个预置音色声线、句首、音量稳定性不退化。
- 个人音色能够被小龙虾选择并完整读出短文与长文。

- [ ] **Step 3: 做 UI/交互 design review**

使用 `design-review` skill 检查真实安装版声音设置：

- 小龙虾音色下拉与 Reader Demo 项目一致。
- 新保存的“我的声音”在重新打开设置后出现。
- 个人音色损坏/删除后自动回退默认音色，不显示空白选中项。
- 切换音色、关闭朗读、打断当前播放均有正确反馈。

- [ ] **Step 4: 更新版本记录**

版本历史和开发日志需写明：

- 自然分块替代逐句切分。
- 修复独立引号导致的预取链中断。
- OpenClaw 与声音页共享音色目录，并支持有效个人音色。
- 未改变 ZipVoice 模型和四个参考音色。

- [ ] **Step 5: 执行完整日常构建和安装验证**

先重新检查分支、dirty 状态、构建进程和源码 mtime，然后运行：

```bash
./native/build_and_log.sh
```

Expected: build 号递增；`/Applications/TypeWhale Pro.app` 被覆盖安装并打开；签名检查通过；构建日志追加成功。

- [ ] **Step 6: 复核并提交最终 build**

```bash
git status --short
git diff --check
git add <仅本轮版本、文档和构建记录文件>
git commit -m "build: validate OpenClaw TTS continuity"
```

不得 stage `.artifacts/`、`.superpowers/`、`native/Helpers/CapsuleConceptGallery/` 或 `native/Sources/Presentation/Capsule/Concepts/`。

---

## Final Acceptance

- OpenClaw 的小龙虾音色下拉与声音页使用同一可用音色集合。
- 四个现有预置音色保持可用；有效个人音色成为第五项。
- 327 字真实样本由 21 个短任务下降为 4–6 个自然块。
- 不再产生独立引号或空规范化请求。
- 1.25× 播放不再出现可感知的“等待下一段”链式停顿。
- 任一合成块失败不会中止后续朗读。
- 打断、取消、音量、语速和最终回复朗读策略无回归。
- 自动测试、真人试听、真实安装版 UI review、签名、构建和提交全部完成。
