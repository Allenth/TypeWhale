# 能量 VAD 与波形设计

> 录音胶囊的「静音 / 人离自动结束」判定，以及声纹折线波形的视觉响应设计。
> 相关代码：`native/Sources/Application/SpeechInputCoordinator.swift`、`native/Sources/Infrastructure/Audio/AudioRecorder.swift`、`native/Sources/Presentation/Capsule/RecordingCapsuleView.swift`。

> **⚠️ 现状更新（1.5.4–1.5.6，2026-06-29）：本文描述的「能量阈值 VAD 人声判定」已被删除。**
> 人声判定现唯一由 **Silero** 负责：录音中每约 0.4s 对最近 0.7s 单声道 PCM 跑一次 Silero（滚动窗口），作为权威信号驱动停顿/人离自动结束；所有 VAD 调用走独立队列 `vadBridge`。Silero 探测出错时停用停顿自动结束，仅保留手动停止与硬上限（不再回退能量 VAD）。
> 能量频带（`frequencyBands`）与峰值（`peakLevel`）现仅用于**波形显示**与**胶囊 dBFS 电平读数**，不再参与人声判定。
> 下文「能量 VAD 如何工作 / 判定逻辑 / 可调参数」保留为历史设计记录。

## 背景与问题

旧版的「静音 / 人离」自动结束**完全依赖实时 ASR 是否吐出文字**，而不是音频本身：

- 录音开始挂一个初始静音定时器，到点时若实时预览文字仍为空，就判「人离」结束；
- 一旦实时 ASR 识别出「有意义文字」，就改挂一个停顿定时器，超过停顿时长没有新文字即结束。

这条链路很长——要经过模型 VAD（`containsSpeech`）、「meaningful text」启发式、`realtimeBusy` 节流、音频快照节奏，于是带来三类不稳定：

1. **时延抖动大**：模型识别快慢不一，导致结束时机每次都不一样。
2. **噪声误识别会破坏判定**：环境噪声被误识成文字时，会取消「人离」定时器，于是该判人离时判不出。
3. **强耦合**：整套逻辑只在「停顿自动完成」开启、且实时预览正常工作时才成立。

明明 `AudioRecorder` 每个音频缓冲都已经算出了 7 段频率能量（`frequencyBands`）与峰值（`peakLevel`），这些能量却没有被用于静音判定。

## 设计原则

**把静音 / 人离判定从 ASR 文字解耦，改为直接基于音频能量（VAD = Voice Activity Detection）。**

能量是确定性的、逐缓冲连续可得的信号，不依赖模型输出，因此每次打开胶囊都能得到一致、可预期的判定。实时 ASR 文字回归它本来的职责——只负责**展示**预览，不再参与结束判定。

## 能量 VAD 如何工作

### 数据通路

```
AudioRecorder 音频 tap（每 1024 帧一个缓冲）
        │  frequencyBands() → [Float; 7]  // 7 段能量，已归一到约 0.12 ~ 1
        ▼
recorder.onBands  （主线程回调，逐缓冲）
        │
        ├─ popup.updateBands(bands)        // 胶囊波形
        ├─ controller.updateInputBands(...) // 主窗口波形
        └─ observeAudioEnergy(bands)        // ← 能量 VAD
```

### 判定逻辑

`observeAudioEnergy(_:)` 在每个音频缓冲到来时：

1. 取 7 段能量的**峰值** `level = bands.max()`，作为「当前有没有人声」的指标；
2. 若 `level ≥ VAD.speechBandThreshold`，标记 `voiceEverDetected = true` 并刷新 `lastVoiceAt = 现在`；
3. 调用 `evaluateVADAutoFinish()` 做结束判定。

`evaluateVADAutoFinish()` 在「停顿自动完成」开启、非长按模式、且正在录音时：

- **已说过话**（`voiceEverDetected == true`）：距上次有声 `lastVoiceAt` 超过 `autoFinishPauseSeconds` → 结束（说完停顿）。
- **从未有声**（开场即静音，「人离」）：距录音开始 `recordingStartedAt` 超过 `initialSilenceAutoFinishSeconds` → 结束。

因为是在每个缓冲里连续评估，静音一旦持续到阈值就会被立刻发现，无需额外定时器，也不会被 ASR 的快慢影响。

### 状态变量与重置

`recordingStartedAt / lastVoiceAt / voiceEverDetected` 三个状态在 `startRecording` 中、`recorder.start` 成功后重置。旧的文字版定时器（初始静音、停顿）已不再参与结束判定。

### 门控（与旧行为保持一致）

- 仅在「停顿自动完成」开关开启时生效；
- 长按（hold）录音模式不自动结束（由松手结束）；
- 仅在 `recorder.isRecording` 为真时评估。

## 波形（声纹折线）灵敏度设计

胶囊里的折线波形要做到「安静时是一条平直线，说话时灵敏地随响度起伏」。它和 VAD 共用同一份 7 段能量，但有自己的平滑与映射曲线（`RecordingCapsuleView`）。

- **平滑**（`update(bands:)`）：起音系数 0.6、落音系数 0.3。起音快让线条对人声反应迅速，落音也跟得紧，避免说话时线条拖沓。
- **噪声死区**（`drawWaveform`）：`activeBand = max(0, (band - 0.13) / 0.87)`。低于 0.13 的环境噪声落入死区输出 0，安静时保持平直、没有折痕；门限取 0.13 让人声一起就有反应。
- **映射曲线**：`emphasized = pow(activeBand, 0.9)`，接近线性。这样幅度真正随响度大小起伏、有动态层次，而不是像 `pow<1` 那样一过门限就顶满、之后大小声都长一个样。
- **形态**：7 个采样点按 `index % 2` 交替上下偏移形成折痕，圆角连接；各点权重接近一致（`centerWeight`），让说话时整条线一起波动而非只有中间动。

## 可调参数

真机调参时，集中改下面几个常量即可（多数在 `SpeechInputCoordinator.swift` 顶部常量区）。

| 参数 | 默认值 | 位置 | 作用 / 调法 |
| --- | --- | --- | --- |
| `VAD.speechBandThreshold` | `0.30` | `SpeechInputCoordinator.swift` | **核心阈值**。误判「人离」太频繁→调低（更易判有声）；环境吵、静音判不出→调高。 |
| `Timing.autoFinishPauseSeconds` | `1.5` | `SpeechInputCoordinator.swift` | 说完到自动结束的静音时长。 |
| `Timing.initialSilenceAutoFinishSeconds` | `3.0` | `SpeechInputCoordinator.swift` | 开场「人离」判定时长。 |
| 波形起音 / 落音 | `0.6 / 0.3` | `RecordingCapsuleView.update` | 越大越跟手、越小越平滑。 |
| 波形死区 | `0.13` | `RecordingCapsuleView.drawWaveform` | 越小越灵敏、越易受噪声影响。 |
| 波形映射幂次 | `0.9` | `RecordingCapsuleView.drawWaveform` | <1 更早顶满、动态层次少；接近 1 更线性、随响度起伏。 |

> 能量值的标定基准在 `AudioRecorder.frequencyBands`（`spectral` 除以 0.0058、`broadband` 除以 0.026，下限 0.12）。若整体灵敏度需要平移，可在这里调增益，但注意它会同时影响波形门限与 VAD 阈值的相对关系。

## 调参反馈对照

- **太早结束** → 调高 `speechBandThreshold` 或 `autoFinishPauseSeconds`。
- **该结束不结束 / 拖很久** → 调低 `speechBandThreshold` 或 `autoFinishPauseSeconds`。
- **开场总判人离** → 调高 `initialSilenceAutoFinishSeconds` 或调低 `speechBandThreshold`。
- **波形太钝（不跟人声）** → 调高起音系数 / 调低死区 / 幂次趋近 1。
- **波形太跳（噪声也抖）** → 调高死区 / 调高 `speechBandThreshold`。
