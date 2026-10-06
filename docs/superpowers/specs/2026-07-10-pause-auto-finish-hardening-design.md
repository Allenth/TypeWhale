# Pause Auto-Finish Hardening Design

## Product intent

“停顿自动完成”应在切换式录音中可靠判断用户已经说完，自动结束录音并进入最终识别；它不能因为用户开始前思考、句中自然停顿、VAD 推理尚未返回，或上一轮录音的异步回调而截断当前输入。

产品承诺是：

- 长按录音始终由松键结束，不参与停顿自动完成。
- 切换式录音在确认人声后的持续静音中自动完成。
- 开场无人声保护是独立的空录音清理策略，不冒充“用户已经说完”。
- VAD 不可用时继续安全录音，由用户手动结束或硬上限收尾。
- 实时预览与停顿自动完成可以独立开关。

## Chosen architecture

新增纯领域对象 `RecordingAutoFinishPolicy`，只接收录音激活方式、开关状态、录音起始时间、带时间戳的 VAD 结果和实时预览证据，输出明确决策：继续录音、停顿完成、开场无人取消。协调器负责把决策转换成录音停止、取消、界面反馈和诊断日志。

每次实时 VAD 请求必须携带 `taskID`。回调回到主线程后，只有 `taskID` 仍等于当前活动录音时才允许更新状态或触发结束；旧录音回调只记录并丢弃。

自动完成只在一个权威 VAD 回调返回 `no_speech` 时评估，不再由每个音频缓冲基于过期的 `lastVoiceAt` 抢先结束。这样可以避免“用户已经重新开口，但最新 VAD 仍在途”时被旧状态截断。

## Timing policy

- 说话后停顿阈值保持内部基线 `1.5s`，但验收以用户感知时间为准：确认人声结束后，不得在 2 秒内误结束；连续静音时应稳定在约 2–3 秒内完成。0.7 秒滚动窗口和 0.4 秒探测节奏属于实现延迟的一部分。
- 开场无人声保护从 `3s` 调整为 `8s`。
- 开场取消必须由录音开始 8 秒后的 `no_speech` VAD 样本触发，并且当前没有有效实时预览文本。阈值前采集的旧结果不能在阈值到达后触发取消。
- 开场无人取消直接取消空录音，不写入最终识别任务。

## State and decisions

`RecordingAutoFinishPolicy` 持有本轮录音的：

- `recordingStartedAt`
- `lastVoiceAt`
- `voiceEverDetected`
- `hasFinished`

它提供：

- `reset(startedAt:)`
- `evaluateProbe(hasSpeech:capturedAt:autoFinishEnabled:isHoldActivation:hasMeaningfulPreview:)`

返回值：

- `.continueRecording`
- `.finishAfterPause(silenceDuration:)`
- `.cancelInitialSilence(elapsed:)`

决策一旦产生，`hasFinished` 阻止同一轮重复触发。

## Coordinator integration

- `AudioRecorder.onVoiceProbe` 增加 `taskID` 参数。
- `SpeechInputCoordinator.receiveVoiceProbe` 把 `taskID` 贯穿异步调用并在回调处校验当前 session。
- VAD 成功结果交给 policy；`speech` 继续录音，`no_speech` 可能产生结束决策。
- VAD 失败停用本轮自动完成，日志保留具体错误，不改变长按、手动停止和硬上限路径。
- 停顿完成记录 `reason=pause`、静音时长、录音时长、预览字符数和 task ID。
- 开场取消记录 `reason=initial_silence`、录音时长、预览字符数和 task ID，并显示短暂、明确的“无输入已停止”。
- 手动结束调用记录 `reason=manual_or_trigger`；硬上限和五分钟安全网继续使用现有专用原因。

## Settings behavior

删除设置层对“实时预览”和“停顿自动完成”的双向强制联动。两个开关独立持久化；关闭实时预览后，VAD 探测仍然运行，停顿自动完成仍可用。

本轮不新增滑杆或模式选择。先通过可归因日志验证默认时序，再决定是否需要“快速／标准／长口述”预设，避免没有证据就增加设置复杂度。

## Tests

纯策略测试必须覆盖：

- 关闭开关时永不自动结束。
- 长按录音永不自动结束。
- 首次确认人声后，短停顿不结束，达到阈值的 `no_speech` 探测才结束。
- 3 秒与 7.9 秒的开场静音不取消。
- 8 秒后的 `no_speech` 且无预览证据时取消。
- 8 秒后的有效预览证据阻止开场取消。
- 决策只触发一次。

协调器边界测试必须覆盖：

- VAD 回调携带并校验 task ID。
- 旧 task 回调不能更新当前录音。
- `reason=pause` 与 `reason=initial_silence` 诊断存在。
- 设置保存不再强制改变另一个开关。

## Manual acceptance

在覆盖安装后的真实 App 中验证：

1. 开启停顿自动完成、关闭实时预览，短按开始录音；正常说一句后停顿，应自动进入识别和粘贴。
2. 开始后分别等待 3 秒、5 秒、7 秒再开口，不得提前停止，也不得丢掉开头。
3. 完全不说话，约 8 秒后应显示“无输入已停止”，且不产生识别或粘贴。
4. 句中停顿约 1 秒后继续说，必须保留完整上下文；说完持续静音约 2–3 秒后应完成。
5. 长按快捷键并故意停顿超过 3 秒，必须持续录音直到松键。
6. 快速连续开始两轮录音，上一轮 VAD 回调不得改变第二轮状态。
7. 模拟 VAD 不可用时，不得自动结束；手动结束和最长录音保护仍可用。

## Documentation and release

同步 README、`docs/VAD_AND_WAVEFORM_DESIGN.md`、`docs/ARCHITECTURE.md`、`docs/开发日志.md` 与应用内版本历史。代码改动完成后按仓库唯一构建入口执行版本递增、覆盖安装、签名检查和真实安装版验证。
