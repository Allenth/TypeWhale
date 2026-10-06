# TypeWhale 遥控器首批自定义与倒计时取消 Implementation Plan

> **执行要求：** 按任务顺序在当前分支串行执行；每个任务先运行可观察失败的测试，再写最少生产实现并做相关回归。不得触碰用户未授权的 42 项扩展路线图。

**Goal:** 完成已批准的上一批功能：倒计时可由 Esc 或右键取消；13 个 RC003 按钮可从首批安全动作中配置并记忆；自定义动作替换原系统动作；实体遥控器 down/up 及页面映射控件点击都驱动产品原图对应按压反馈。

**Architecture:** Domain 定义稳定动作、映射约束、取消与替换门禁；Application 读取一次映射快照并路由动作／按压状态；Infrastructure 负责 CGEvent 发送、RC003 系统事件关联和持久化；Presentation 负责分组动作选择与原图高亮。保留非独占 HID、ATVV `AUDIO_STOP`、Fn 450ms 和既有 voice F5 关联。

**Tech Stack:** Swift 6、AppKit、ApplicationServices/CoreGraphics、IOKit HID、UserDefaults、现有 shell 驱动 Swift checks、TypeWhale 唯一构建入口。

**Requirements summary:**

- In scope：右键取消倒计时；Esc 回归；首批 10 类动作；13 键可编辑和持久化；替换语义；实体按钮及页面映射控件高亮；安装版验证。
- Out of scope：42 项扩展目录、App 启动、宏、单双击／长按、关机／重启／注销、Fn 或 ASR 改造。
- Do not touch：电脑麦克风、Fn 分类、ATVV 音频格式和 `AUDIO_STOP` 收尾、ASR、粘贴正文、现有 voice F5 120ms/310s 策略。

---

## Task 1: 右键取消自动发送倒计时

**Files:**

- Modify: `native/Sources/Domain/AutoSendCountdownDomain.swift`
- Modify: `native/Sources/Infrastructure/Hotkey/HotkeyMonitor.swift`
- Modify: `native/Sources/Application/SpeechInputCoordinator.swift`
- Create: `native/Tests/RightMouseCountdownCancellationCheck.swift`
- Modify: `native/Tests/TypeWhaleAutoSendCancellationFeatureCheck.sh`

**Step 1 — RED:** 新增纯 `RightMouseCancellationGate` 测试：只有按钮号 1 的 down 在 `cancel()` 返回 true 时消费；只消费匹配的 up；无倒计时、左键、侧键、重复 down 均透传。

Run: `/bin/zsh native/Tests/TypeWhaleAutoSendCancellationFeatureCheck.sh`

Expected: FAIL，因为右键门禁与回调尚不存在。

**Step 2 — GREEN:** 在 Domain 添加门禁和 `.rightMouseButton` 取消原因；HotkeyMonitor 在鼠标快捷键分发前调用独立右键取消回调；SpeechInputCoordinator 将其接到唯一倒计时 coordinator。

**Step 3 — VERIFY:** 重跑自动发送聚合、Escape 门禁和鼠标快捷键边界，确认无倒计时时右键菜单与侧键保持原行为。

**Step 4 — COMMIT:** `fix: cancel auto-send countdown with right click`

## Task 2: 首批动作目录、13 键约束与持久化

**Files:**

- Create: `native/Sources/Domain/Remote/RemoteButtonAction.swift`
- Modify: `native/Sources/Domain/Remote/RemoteButtonMapping.swift`
- Modify: `native/Sources/Infrastructure/Remote/RemoteInputSettingsStore.swift`
- Modify: `native/Tests/RemoteButtonMappingCheck.swift`
- Modify: `native/Tests/RemoteInputSettingsStoreCheck.swift`
- Modify: `native/Tests/run_remote_domain_checks.sh`

**Step 1 — RED:** 覆盖稳定 ID、13 键均可编辑、voice 独有 PTT、返回键包含 Esc、全部按钮包含 system/none/Delete、非法 PTT 回退该键默认、旧 v1 缺键与未知动作只逐键回退。

Run: `/bin/zsh native/Tests/run_remote_domain_checks.sh`

Expected: FAIL，因为新动作与语音键编辑约束尚未实现。

**Step 2 — GREEN:** 将动作枚举／可用性移出 mapping；新增 Esc、Delete、Return、lockMac；mapping 的 Codable 采用逐键容错解码，旧 key 继续可读，不清空其他合法项。

**Step 3 — VERIFY:** 运行 remote domain 和 settings checks。

**Step 4 — COMMIT:** `feat: define safe remote action catalog`

## Task 3: 分层动作执行与合成事件标记

**Files:**

- Create: `native/Sources/Infrastructure/Remote/RemoteKeyboardActionEmitter.swift`
- Modify: `native/Sources/Application/RemoteButtonActionDispatcher.swift`
- Modify: `native/Tests/RemoteButtonActionDispatcherCheck.swift`
- Create: `native/Tests/RemoteKeyboardActionEmitterCheck.swift`
- Modify: `native/Tests/TypeWhaleRemoteFeatureCheck.sh`

**Step 1 — RED:** 测试 Esc、Delete、Return、Control-Command-Q 的 key-down/up、flags、顺序与 synthetic marker；Dispatcher 每次只路由到一个执行器，失败不重试。

Run: `/bin/zsh native/Tests/TypeWhaleRemoteFeatureCheck.sh`

Expected: FAIL，因为键盘 emitter 与执行结果尚不存在。

**Step 2 — GREEN:** 新增协议化键盘 emitter 和结构化结果；Dispatcher 只路由键盘／TypeWhale 动作，system、none、PTT 不执行；CGEvent 创建和 post 失败返回失败，不执行 shell。

**Step 3 — VERIFY:** 重跑 remote 聚合和普通键盘热键回归。

**Step 4 — COMMIT:** `feat: execute safe remote keyboard actions`

## Task 4: RC003 自定义动作替换原系统事件

**Files:**

- Create: `native/Sources/Infrastructure/Remote/RemoteSystemEventProfile.swift`
- Create: `native/Sources/Infrastructure/Remote/RemoteMappedEventSuppressionGate.swift`
- Modify: `native/Sources/Infrastructure/Remote/RemoteHIDMonitor.swift`
- Modify: `native/Sources/Infrastructure/Hotkey/HotkeyMonitor.swift`
- Modify: `native/Sources/Application/RemoteInputCoordinator.swift`
- Create: `native/Tests/RemoteMappedEventSuppressionGateCheck.swift`
- Modify: `native/Tests/TypeWhaleRemoteFeatureCheck.sh`

**Step 1 — RED:** 覆盖同按钮／同事件／双时间戳短窗消费，失配键码、普通电脑输入、TypeWhale synthetic 事件、超时、丢 up、断连与 tap 重启透传；无法核证系统事件身份的按钮不得使用宽泛“吞下一键”。

Run: `/bin/zsh native/Tests/TypeWhaleRemoteFeatureCheck.sh`

Expected: FAIL，因为通用关联门禁尚不存在。

**Step 2 — GREEN:** 以 RC003 profile 中已核证的 keyboard/system-defined 身份武装门禁；`system` 不武装；自定义／none 只在匹配成功时消费原事件；保留 voice 专用 F5 门禁并放行 synthetic 新动作。

**Step 3 — VERIFY:** Remote 聚合、F5 隔离、Fn／输入手势和普通电脑按键回归全绿。若某实体按钮没有核证事件身份，记录为安装版现场校准项，不用猜测扩大吞键。

**Step 4 — COMMIT:** `feat: replace correlated remote system events`

## Task 5: 语音键改映射不启动孤儿录音

**Files:**

- Modify: `native/Sources/Application/RemoteInputCoordinator.swift`
- Modify: `native/Tests/RemoteSpeechCoordinatorBoundaryCheck.sh`
- Create or modify: `native/Tests/RemoteInputCoordinatorMappingCheck.swift`
- Modify: `native/Tests/TypeWhaleRemoteFeatureCheck.sh`

**Step 1 — RED:** 默认 PTT 可启动；voice 改 Esc／none 后 HID 仍完成 F5 隔离但 Bluetooth `onVoiceStart` 在创建任务前拒绝；PCM/stop 不形成孤儿会话；恢复默认后下一个完整周期可录音。

**Step 2 — GREEN:** Coordinator 以当前 mapping 作为 voice eligibility 真源；HID down 只在 PTT 时通知语音启动策略并执行现有录音语义，其他动作只分发一次。

**Step 3 — VERIFY:** Remote、录音收尾和 F5 聚合全绿。

**Step 4 — COMMIT:** `fix: honor remapped remote voice button`

## Task 6: 实体／页面按键状态与产品原图按压反馈

**Files:**

- Modify: `native/Sources/Domain/Remote/RemoteInputModels.swift`
- Modify: `native/Sources/Application/RemoteInputCoordinator.swift`
- Create: `native/Sources/Presentation/Remote/RemoteButtonPressVisualSpec.swift`
- Modify: `native/Sources/Presentation/Remote/RemoteControlIllustrationView.swift`
- Modify: `native/Sources/Presentation/Remote/RemoteButtonGuideView.swift`
- Modify: `native/Sources/Presentation/Remote/RemoteInspectorView.swift`
- Create: `native/Sources/Presentation/Remote/RemoteButtonPreviewPopUpButton.swift`
- Modify: `native/Sources/Presentation/Remote/RemoteButtonMappingView.swift`
- Modify: `native/Tests/RemoteButtonGuideSnapshotCheck.swift`
- Modify: `native/Tests/RemoteButtonGuideSpecCheck.swift`
- Modify: `native/Tests/TypeWhaleRemoteButtonGuideFeatureCheck.sh`

**Step 1 — RED:** 13 个 region 一一对应；实体 down 或映射控件点击只激活一个 region；up 后至少保留约 180ms 可见反馈；断连／关闭清空；页面预览不执行真实动作；缺图不绘制伪高亮；减少动态效果无缩放动画。

Run: `/bin/zsh native/Tests/TypeWhaleRemoteButtonGuideFeatureCheck.sh`

Expected: FAIL，因为 snapshot 与图示目前没有按压状态。

**Step 2 — GREEN:** snapshot 增加当前物理按键；Coordinator 在 down/up 发布；独立 popup 子类只投影界面点击；Guide 统一维护最近识别文案；Illustration 依据独立视觉几何覆盖高对比亮层。

**Step 3 — VERIFY:** 深／浅、常规／窄宽、默认／自定义、按下／释放／缺图快照与可访问性检查通过。

**Step 4 — COMMIT:** `feat: show physical remote button feedback`

## Task 7: 映射 UI 完成 13 键编辑与正确语义

**Files:**

- Create: `native/Sources/Presentation/Remote/RemoteButtonActionPresentation.swift`
- Modify: `native/Sources/Presentation/Remote/RemoteButtonPresentation.swift`
- Modify: `native/Sources/Presentation/Remote/RemoteButtonMappingView.swift`
- Modify: `native/Tests/RemoteButtonGuideSpecCheck.swift`
- Modify: `native/Tests/RemoteButtonGuideSnapshotCheck.swift`

**Step 1 — RED:** 语音键可编辑但非 voice 不显示 PTT；动作标题按默认／键盘／TypeWhale／Mac／关闭分组；说明明确“替换”而不是“附加”；13 个控件都有可访问标签。

**Step 2 — GREEN:** UI 只消费 action presentation，不自行维护动作数组；默认与常用动作靠前；恢复默认同步 mapping 和图示标签。

**Step 3 — VERIFY:** 组件快照与 Remote UI 边界测试通过。

**Step 4 — COMMIT:** `feat: finish remote mapping controls`

## Task 8: 全量回归、Build、安装与维护记录

**Files:**

- Modify: `native/Tests/TypeWhaleRemoteCustomizationFeatureCheck.sh`
- Modify: `docs/current/PRODUCT.md`
- Modify: `docs/current/ARCHITECTURE.md`
- Modify: `docs/current/DESIGN.md`
- Modify: `docs/current/RELEASE_QA.md`
- Modify: `docs/current/DEVELOPMENT_LOG.md`
- Modify: `docs/开发日志.md`
- Modify: `native/Sources/Presentation/VersionHistory/VersionHistoryViewController.swift`
- Generated by build: `docs/构建日志.md`

**Step 1 — TEST:** 通过 AWF `task:run` 执行取消、Remote、录音收尾、Fn／输入手势、diff 和 runtime checks。

**Step 2 — UI EVIDENCE:** 运行生产组件快照；打开安装版 Remote tab，验证常规／窄宽、深／浅、未连接／已连接、默认／自定义、按压状态。物理设备未执行的项必须明确标记，不能用程序化事件冒充。

**Step 3 — DOCUMENT:** 更新现行文档、版本历史和开发日志，记录替换语义、权限、回滚与剩余现场项。

**Step 4 — BUILD:** 只运行 `./native/build_and_log.sh`；检查版本、深度签名、资源、进程和新诊断标记。

**Step 5 — DELIVER GATE:** 运行 AWF `task:check --phase deliver`，写独立 ACCEPTANCE 记录。

**Step 6 — COMMIT:** `build: install remote customization build`
