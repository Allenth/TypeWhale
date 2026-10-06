# MiMo 适配与候选预览稳定性设计

## 状态

- 日期：2026-07-13
- 状态：产品目标与分层已批准
- 所属阶段：Stage 9A / Task 13A 收尾修复
- 生产边界：不授权 Stage 9B，不修改原胶囊、final 或粘贴

## 问题与目标

Build 710 证明 MiMo 鉴权、快照请求、SSE 文本下行、新核心状态广播和旧 final/paste 可以共同运行，但候选预览仍会闪烁。代码审查确认两个不同层次的问题：MiMo 每个累计音频快照会从响应开头重新产生 partial；候选窗口又对每个状态重复重绘、重新置前。现有 `CandidateStreamTextBuffer` 在 Presentation 层猜测“短前缀是否属于快照重放”，越过了候选窗的产品职责。

本轮目标是一次性消除这类闪烁，同时巩固三种模型共享的架构：MiMo 的请求级特殊语义只在 MiMo 适配层处理；本地非流式、本地流式和在线 MiMo 继续输出同一 `TranscriptionEvent`；候选预览只把统一状态变成未来产品体验的可视证据。

## 候选预览窗的产品职责

三胶囊回答三个不同问题：

- 原胶囊：当前生产功能是否仍然可用，是预览、final 和粘贴的权威路径。
- 旁路1：Provider 与新核心实际产生了什么，保留批次、修订、失败和时间诊断。
- 旁路2候选胶囊：新核心成熟后接管正式预览时，用户可获得怎样稳定、连续且可信的产品体验。

候选预览允许对“已经到达的真实文字”执行有界显示节奏，但不能决定 transcript 真相。它不得识别 Provider、请求、WAV 或 SSE，不得去重厂商事件，不得把视觉状态写回 Reducer、final、历史或粘贴。

## 决策

采用“MiMo 请求投影 + 通用纯渲染”两层修复。

拒绝方案一：只在 `CandidatePreviewView` 增加更多字符串特判。该方案改动小，但让 UI 继续承担 MiMo 数据语义，无法证明三模型兼容。

拒绝方案二：在通用 Reducer 或 Projector 中识别 MiMo 重放。该方案会污染统一状态层，并可能改变 SenseVoice 快照与本地真流式 partial 的合法修订语义。

### MiMo 适配层

`MiMoSnapshotProvider` 必须拥有每次 snapshot request 的 partial 投影。一个新请求从空文本开始产生 SSE delta 时，适配层将请求内累计文本与上一轮已接受的快照文本比较：

- 请求内增长只更新该请求的候选文本；
- 新请求重放上一轮已接受文本的前缀时，不向统一事件流发出回退 partial；
- 超过上一轮已接受文本后，发出真实扩展；
- 请求完成后仍由现有 reconciler 决定 confirmed/volatile 语义；
- 真实非前缀修订必须发出，不能被当成重放吞掉；
- cancel、failure、session 结束必须清空请求投影。

MiMo 适配层可以理解 snapshot ID、SSE 和快照基线，但不能引用 AppKit、候选窗口或动画。

### 统一核心

`TranscriptionSession → TranscriptReducer → PreviewStateProjector` 的公共接口不改变。SenseVoice 快照、本地流式 fixture 和 MiMo 仍共享 `partial/finalized/completed/failed/cancelled` 事件与 `PreviewViewState`。通用核心不增加 Provider switch。

### 候选展示层

候选展示缓冲只处理通用展示行为：已到达前缀增长、最多 24 字的动画尾部、真实非前缀修订、跨 session 清理。删除其中关于“新 snapshot 从头重放”的厂商语义与对应猜测。

Presenter 和 View 必须遵守纯展示边界：

- 同一 session 第一次有效状态时显示窗口一次；
- frame 未变化时不重复 `setFrame(display:)`；
- 已经可见时不重复 `orderFrontRegardless()`；
- buffer 返回 `.unchanged` 时不替换绘制状态、不触发 `needsDisplay`；
- Timer 只在可见文字确实推进时重绘；
- Presenter/View 不包含 `MiMo`、`SenseVoice`、snapshot、SSE 或 Provider 判断。

## 数据流与证据边界

```text
MiMo audio snapshot → MiMo request projection → TranscriptionEvent
SenseVoice snapshot ───────────────────────────→ TranscriptionEvent
Local streaming partial ───────────────────────→ TranscriptionEvent
                                                    ↓
                              Session → Reducer → Projector
                                                    ├─→ 旁路1：真实核心状态证据
                                                    └─→ 候选通用显示缓冲
                                                              ↓
                                                        纯 Presenter/View
```

MiMo 原始请求诊断必须保留在 Provider 日志或 diagnostics 中；旁路1继续显示新核心实际收到的统一状态。候选窗的稳定不可以通过删除旁路1证据实现。

## In Scope

- 为 MiMo snapshot request 建立可测试的请求级 partial 投影。
- 移除候选缓冲中的 MiMo 快照猜测。
- 让候选窗口只在内容、样式、位置或可见性真正变化时更新。
- 增加实际 `displayedText/targetText` 与窗口动作诊断。
- 覆盖本地非流式、本地流式和 MiMo 三数据源回归。
- 更新架构、QA、readiness、开发计划、版本历史并构建安装。

## Out of Scope / Do Not Touch

- 不把 MiMo 改造成官方未证明的持续 PCM 上行连接。
- 不改变 MiMo API endpoint、Keychain、计费、语言参数或 snapshot 调度间隔。
- 不改变 SenseVoice Provider 或本地流式 Provider 的事件语义。
- 不改变原胶囊、旁路1绘制节奏、旧 preview、final ASR、VAD、整理、翻译、历史、OpenClaw 或粘贴。
- 不授权候选胶囊接管正式位置，不删除任何旁路。

## 可观察验收标准

1. MiMo 第二次及后续 snapshot request 从短前缀重新输出时，统一 partial 不回退，候选窗不闪烁；真实扩展继续到达。
2. MiMo 真实非前缀修订能够通过统一事件进入候选缓冲并干净替换。
3. SenseVoice 快照修订行为与本地流式 partial 行为不变，三者通过同一候选显示接口。
4. 相同 RenderState 不重绘；同一 session、frame 不变时只执行一次 order-front。
5. 取消、失败、完成、关闭实验和连续会话后无旧 Timer、窗口或文字复活。
6. 20 秒与 2 分钟安装版测试中，原胶囊、final 和粘贴无退化。
7. 实际诊断可区分 Provider 输入长度、candidate target 长度、displayed 长度和窗口 show/reposition 次数。
8. `CandidatePreview` 生产源码不包含厂商名、snapshot、SSE、WAV 或 Provider 类型依赖。

## 回滚

MiMo 请求投影和候选窗口去抖分别形成独立提交。任何一层出现回归时可以独立回滚；关闭旁路实验仍是即时产品回滚开关。原胶囊与旧 final/paste 始终保持权威。
