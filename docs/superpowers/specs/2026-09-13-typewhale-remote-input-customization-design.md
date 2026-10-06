# TypeWhale 遥控器自定义、实体按键反馈与倒计时取消设计

日期：2026-09-13
状态：产品方向已获项目所有者批准，等待书面规格复核
关联 AWF 任务：`task_5dc482d02a264df0df282565`
准备记录：`prep_f7d2e233-e2a2-435e-8898-f81594fe38ca`
基线：TypeWhale Pro 2.0.58 (Build 911)，提交 `184eb471`

## 1. 产品目标

用户完成一段语音、文字已粘贴并进入自动发送倒计时后，可以按 `Esc` 或点击鼠标右键立即取消本次自动发送。取消只终止倒计时和后续模拟发送键，不撤回已经粘贴的文字。

连接小米 RC003 后，用户可以在遥控器页面为十三个物理按钮选择支持的动作并持久记忆。页面同时成为硬件自测工具：按下实体遥控器按钮时，产品原图中只有对应按钮产生清晰按压反馈，松开后平滑恢复；快速点击也保留短暂可见反馈。

## 2. 已批准语义

- 自动发送倒计时活跃时，`Esc` 或鼠标右键按下立即取消，配对的 key-up／mouse-up 一并消费，避免残留按键或右键菜单。
- 没有活跃倒计时时，普通 `Esc`、右键菜单和鼠标快捷键完全按原行为传递。
- 每个物理按钮保留现有默认值；用户选择的自定义动作在应用重启后仍保留，恢复默认可一次还原全部按键。
- 自定义动作采用替换语义：只执行新动作，不同时触发遥控器原系统动作；选择“保持系统原功能”时不抑制系统事件。
- 返回键的动作列表包含 `Esc`；首批键盘动作包含 `Delete`；电源键保留“系统电源功能”默认项并提供“锁定 Mac”。
- 语音键默认仍是“按住说话”，但允许选择其他动作；改作其他动作后，不启动 TypeWhale 遥控器语音会话。`按住说话` 只对物理语音键开放，其他按钮不能伪造远端音频。
- 一个物理按下周期最多执行一次动作。除语音键“按住说话”外，首批自定义动作不定义长按连发、多击或组合动作。

## 3. 首批动作目录

| 稳定 ID | 下拉文案 | 行为 | 可用按钮 |
| --- | --- | --- | --- |
| `system` | 保持系统原功能 | 放行 RC003 对应的 macOS 原始事件，不执行附加动作 | 全部 |
| `pushToTalk` | 按住说话 | 物理语音键按住期间使用 RC003 音频，抬起后沿现有 ATVV 收尾 | 仅语音键 |
| `keyboardEscape` | 按 Esc | 发送一对带 TypeWhale 标记的 Esc down/up | 全部 |
| `keyboardDelete` | 按 Delete | 发送一对带 TypeWhale 标记的向后删除 down/up | 全部 |
| `keyboardReturn` | 按 Return | 发送一对带 TypeWhale 标记的 Return down/up | 全部 |
| `lockMac` | 锁定 Mac | 发送 macOS 标准 `Control + Command + Q` 组合 | 全部 |
| `toggleMainWindow` | 显示／隐藏 TypeWhale | 切换现有主窗口，不改变前台输入内容 | 全部 |
| `send` | 发送当前内容 | 沿用现有 TypeWhale 手动发送动作 | 全部 |
| `cancel` | 取消当前操作 | 沿用现有录音／倒计时取消边界 | 全部 |
| `none` | 无操作 | 抑制对应系统事件且不执行其他动作 | 全部 |

本轮不加入关机、重启、注销、任意脚本、URL、App 启动、宏、组合动作或长按配置。后续新增动作只能追加稳定 ID，不能改写已有 raw value。

## 4. 候选方案与结论

### A. 扩大现有枚举并继续在单个 Dispatcher 里 switch

优点是文件少。缺点是键盘事件、锁屏、窗口控制、语音策略和展示文案继续耦合，动作增加后单文件会迅速成为维护热点，也难以独立测试失败路径。拒绝。

### B. 每个物理按钮维护一套独立下拉数组和执行逻辑

优点是每键文案直观。缺点是相同动作在十三处重复，默认值、迁移和后续新增动作容易漂移，无法保证“同一动作只有一个语义”。拒绝。

### C. 共享动作目录＋每键能力过滤＋分层执行器

Domain 维护稳定动作 ID 和每键可用性；Presentation 维护分组、文案与每键推荐顺序；Application 只协调；Infrastructure 负责系统事件发送与来源抑制。十三个下拉共用同一目录，但语音键额外开放按住说话，当前按钮的默认和常用动作排在前面。接受。

## 5. 架构与文件边界

```text
RC003 IOHID down/up
    → RemoteHIDEventReducer
    → RemoteInputCoordinator
        ├─ RemoteButtonInteraction callback → RemoteInspectorView
        │                                  → RemoteButtonGuideView
        │                                  → RemoteControlIllustrationView
        ├─ RemoteButtonMapping → RemoteButtonActionDispatcher
        │                       ├─ RemoteKeyboardActionEmitter
        │                       ├─ TypeWhale callbacks
        │                       └─ voice eligibility policy
        └─ RemoteMappedEventSuppressionRegistry
                                → HotkeyMonitor CGEvent tap

Esc/right mouse
    → HotkeyMonitor cancellation gates
    → AutoSendCountdownCoordinator.cancel(reason:)
```

### Domain

`RemoteButtonAction.swift`

- 定义稳定动作 ID、动作类别和是否需要替换系统事件。
- 定义 `allowedActions(for:)`，语音键可选择全部首批动作，其他键排除 `pushToTalk`。
- 不包含中文、AppKit、CGEvent、IOHID usage、UserDefaults 或布局。

`RemoteButtonMapping.swift`

- 继续拥有十三键默认值、查找、设置、Codable 与缺键回退。
- 所有十三键可编辑；不允许把 `pushToTalk` 写到非语音键，非法组合回退该按钮默认值。

`AutoSendCountdownDomain.swift`

- 新增取消原因 `rightMouseButton`。
- 新增通用的右键取消配对门禁：down 只有在 coordinator 真正取消时才被消费；只有被消费的 down 才消费对应 up；其他鼠标按钮永远放行。

`RemoteMappedEventSuppressionGate.swift`

- 保存一次 RC003 HID 周期的按钮、down/up 双时间戳和是否需要抑制。
- 仅消费与该按钮期望系统事件身份一致、且事件时间和观察时间均落在短关联窗口内的 CGEvent。
- TypeWhale 自己生成的事件带固定 `eventSourceUserData`，永远不作为 RC003 原事件消费。
- 丢失 up、超时、断连、关闭遥控器和 event tap 重启都会清空状态；不允许形成全局吞键。

### Application

`RemoteButtonActionDispatcher.swift`

- 只按动作类型把工作交给协议化执行器或现有 TypeWhale 回调。
- 返回结构化成功／失败结果供诊断；一个 HID down 只调用一次。
- 不读取 UserDefaults、不识别 HID、不生成展示文案。

`RemoteInputCoordinator.swift`

- down 时读取当前 mapping 的单一快照，先确定是否放行系统事件，再触发视觉事件和动作。
- 语音键只有映射为 `pushToTalk` 时才允许 RC003 音频开始；其他映射仍保留既有 F5 来源抑制，避免输入框弹补全。
- up 时发送视觉释放并清理本按钮周期；ATVV `AUDIO_STOP` 仍是实际遥控器录音的收尾权威。

### Infrastructure

`RemoteKeyboardActionEmitter.swift`

- 生成 Esc、Delete、Return 和 `Control + Command + Q` 的 CGEvent down/up。
- 每个事件写入 TypeWhale synthetic marker，创建或 post 失败返回明确结果。
- 不执行 shell，不依赖键盘布局文本，不操作剪贴板。

`RemoteSystemEventProfile.swift`

- 集中维护 RC003 按钮与 macOS 可观察系统事件身份的关系，包括箭头、Return、Home、F5、音量和电源类事件。
- 没有证据的按钮不使用“吞第一个相邻事件”这种宽泛规则；无系统 CGEvent 的按钮无需抑制。

`RemoteInputSettingsStore.swift`

- 保持现有 mapping key 与 JSON 结构可读；新增动作通过稳定 raw value 自然兼容。
- 损坏、未知或非法动作只回退对应按钮默认值，不清空其他合法用户配置。

### Presentation

`RemoteButtonActionPresentation.swift`

- 定义中文标题、类别顺序、每键推荐顺序和辅助说明。
- 下拉项按“默认／键盘／TypeWhale／Mac／关闭”组织，当前按钮默认动作始终容易找到。

`RemoteButtonMappingView.swift`

- 只渲染每键动作目录、当前选择、恢复默认和 callback。
- 十三个按钮均有原生可访问标签；语音键不再显示为不可编辑固定行。

`RemoteButtonPressVisualSpec.swift`

- 以 1024×1536 原图归一化坐标定义十三个可视区域；方向环四个扇区、中央键、圆键和音量胶囊上下半区分别建模。
- 几何只属于 Presentation，不复制到 Domain 或 HID profile。

`RemoteControlIllustrationView.swift`

- 原图仍是底层；按下时在对应区域覆盖高对比半透明亮层并产生轻微压下感。
- release 后保留约 180ms 淡出，确保快速点击可见；开启“减少动态效果”时取消缩放与渐变，只切换静态高亮。
- 图片缺失时不绘制虚假按钮反馈。

`RemoteButtonGuideView.swift`

- 接收硬件 down/up，驱动 Illustration；保留最近一次识别文案，例如“刚刚识别：返回键”，帮助用户在动画结束后核对。
- 映射变化继续即时更新十三个“当前功能”标签。

## 6. 事件顺序与竞态

### 倒计时右键取消

1. 全局 mouse tap 收到 rightMouseDown。
2. 右键门禁调用 `cancel(.rightMouseButton)`。
3. coordinator 有 pending 时原子完成：停止 timer、清空 pending、隐藏 Presenter、记录 terminal；down 被消费。
4. 同一门禁消费配对 rightMouseUp，避免目标 App 打开菜单。
5. 若 coordinator 没有 pending，down/up 都透传，普通右键行为不变。

Esc 沿用现有 `EscapeCancellationGate` 和 coordinator 路径，只补齐聚合回归，避免为同一行为再造监听器。

### 实体按键与自定义动作

1. IOHID down 被 reducer 去重并转换为稳定 `RemoteButton`。
2. coordinator 读取本次 down 的 mapping；不可在同一按压周期中途切换动作。
3. 若为 `system`，不武装抑制门禁、不执行附加动作，只发布图片按下。
4. 若为自定义或 `none`，按按钮身份武装短窗抑制，发布图片按下，并执行一次新动作。
5. CGEvent tap 只消费同一 RC003 周期的已知原系统事件；synthetic 新动作放行。
6. IOHID up 发布图片释放并结束周期。快速 down/up 的视觉淡出由 Presentation 独立完成。

### 语音键改映射

- `pushToTalk`：保持 Build 911 的 HID/F5 来源关联和 ATVV 录音链路。
- 其他动作：仍观察 voice HID 以抑制 RC003 产生的 F5，但 `onVoiceStart` 在创建 TypeWhale 录音任务前拒绝音频；PCM 和 stop 不生成孤儿会话。
- 从其他动作恢复 `pushToTalk` 后，下一个完整按压周期正常工作，不复用旧周期状态。

## 7. 错误、权限与恢复

- 缺少辅助功能或输入监控权限时，页面继续显示配置和实体 HID 识别能力，但动作失败必须留下可理解状态；不能显示“已执行”。
- CGEvent 发送失败不会重试成重复动作，也不会改变用户映射。
- 右键取消发生在倒计时终点竞态时，由 coordinator 的 pending token 决定唯一 terminal：要么取消，要么已发送，不能两者都发生。
- 断连、关闭遥控器或 App 停止时清空按压反馈和全部抑制门禁。
- 损坏的持久化数据按键级回退默认；用户其他合法映射保留。

## 8. 测试与验收

### TDD 红灯

- 右键门禁：活跃倒计时 down/up 被消费；无倒计时透传；重复 down 不重复取消；左键和侧键透传。
- 动作目录：十三键可编辑；voice 独有 push-to-talk；返回键包含 Esc；所有按键包含 Delete、系统原功能和无操作；非法组合回退。
- 持久化：每种新动作 round-trip；旧 v1 缺键数据迁移；一个未知动作不清空其他按键。
- Dispatcher/emitter：每个动作调用唯一执行器；Esc/Delete/Return/锁屏事件顺序、flags 和 synthetic marker 正确；失败只报告一次。
- 替换门禁：关联 RC003 事件消费；失配按钮、失配 keyCode、窗口外、普通电脑输入和 synthetic 新动作透传；丢失 up/断连恢复。
- 语音键：默认录音；改作 Esc 后不开始语音但仍抑制 F5；恢复默认后重新录音。
- 视觉反馈：十三个 region 一一覆盖；down 只激活对应 region；up 释放；快速点击可见；断连清空；减少动态效果无缩放动画。

### 回归

- Remote 完整聚合、真实使用 profile、F5 隔离、电脑 Fn 手势、电脑麦克风、录音收尾和自动发送倒计时现有测试全部通过。
- `git diff --check`、完整 Build、覆盖安装、深度签名和运行检查通过。

### 安装版体验

1. 在文本框完成一次语音并进入倒计时，分别用 Esc 和右键取消；文字保留，等待超过设置秒数也不发送。
2. 无倒计时时验证 Esc 和右键菜单仍正常。
3. Remote tab 逐键按 RC003，图中只有对应按钮亮起，“刚刚识别”一致；覆盖按住、快速点按和相邻键切换。
4. 将返回键设为 Esc，在目标应用打开可由 Esc 关闭的界面，按实体返回键只执行一次 Esc，不同时执行旧返回动作。
5. 将任一非语音键设为 Delete，在文本框删除一个字符且只删除一次。
6. 将电源键设为锁定 Mac，确认只锁屏一次；重新登录后映射仍在。
7. 把语音键改为无操作，确认不录音、不弹 F5 补全；恢复默认后按住说话恢复。
8. 恢复默认并重启 App，十三键默认行为和页面标签一致。

## 9. 非目标与保护边界

- 不改 Fn 450ms 分类、RemoteVoiceKeySuppressionGate 的 120ms 来源窗口和最长五分钟保险，除非新增测试证明扩展映射必须复用其公共机制且完全保持旧语义。
- 不改 ATVV `AUDIO_STOP` 收尾权威、音频格式、ASR、电脑麦克风、粘贴正文、自动发送设置范围或截图取消。
- 不独占整个 RC003 HID 设备，不用全局“吞下一键”近似替换，不用 UI 动画冒充动作成功。
- 不加入用户尚未定义的宏、脚本、App 启动或破坏性电源动作。

## 10. 规格自审

- 无占位符或未定义的首批动作。
- “替换系统行为”与“保持系统原功能”边界一致。
- 语音键可编辑与硬件音频限制都有明确行为。
- 每项需求均有对应状态、失败路径和自动／安装验收。
- 文件按 Domain/Application/Infrastructure/Presentation 职责拆分，没有把动作目录、事件发送、持久化和动画集中到一个文件。
