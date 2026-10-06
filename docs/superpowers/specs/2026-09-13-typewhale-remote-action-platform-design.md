# TypeWhale 遥控器动作平台设计与分批路线图

日期：2026-09-13
状态：Approved；项目所有者已于 2026-09-13 回复“好，可以开始”，本轮只进入 R0
关联 AWF 任务：`task_7dadf7d7d67870da9b89b769`
基线：TypeWhale Pro 2.0.58 (Build 913)，提交 `d176bd59`
首个垂直切片规格：`2026-09-13-typewhale-remote-input-customization-design.md`

## 1. 需求结论

用户希望 TypeWhale 的 Remote tab 不只展示固定映射，而成为一套可扩展的遥控器动作平台：连接小米 RC003 后，可为每个实体按钮选择、保存和验证动作；后续可以持续增加动作，而不把键盘、系统、媒体、App 和 UI 逻辑堆进同一个文件。

用户提供的目标程序截图只作为能力盘点证据，不复制其代码、品牌、文案结构或页面布局。截图中可确认 42 个动作候选和 5 类配置机制；TypeWhale 保留自己的单页深度集成、产品原图、十三键示意和既有语音输入工作流。

许可边界：动作名称和 macOS 通用快捷操作只作为功能需求重新实现；不复制目标程序源码、图标、布局、动效或品牌资源，也不引入其许可证代码。RC003 产品图继续沿用已经由产品所有者确认授权并在第三方声明中记录的现有应用内资源。该路径把主要风险限定在我们自己的实现、系统权限和商标呈现，不以“功能相似”作为复制第三方产品的理由。

## 2. 当前状态与差距

- Build 913 已稳定识别并配置 13 个 RC003 物理按钮；物理 down/up 和页面映射点击都能在产品原图上反馈唯一对应位置。
- 当前 `RemoteButtonAction` 已交付 10 项：按住说话、Esc、Delete、Return、锁定 Mac、发送、取消、显示／隐藏 TypeWhale、禁用和保持系统原功能。
- 映射已有本机 JSON 持久化、逐键容错与恢复默认；自定义动作采用替代语义，并有一般系统事件相关抑制、语音 F5 专用抑制及电源键安全接管。
- 当前枚举仍没有版本化参数，因此不能安全承载自定义快捷键、App bundle identifier、单双击／长按或宏；这是扩展前必须先解决的架构缺口。
- Remote tab 已是单页深度集成，后续只在现有页面扩展动作选择器和状态，不改成目标程序的独立侧边栏式工具。
- Build 913 的倒计时取消、Fn 分类、RC003 F5 来源抑制、ATVV 录音收尾、电脑麦克风与 ASR 是稳定基线，扩展动作不得破坏。

## 3. 参考能力清单

### 3.1 基础按键：22 项

| ID | 用户可见动作 | 风险 | 计划批次 |
| --- | --- | --- | --- |
| `keyboard.escape` | Esc | 低 | 已交付（Build 913） |
| `keyboard.return` | Return | 低 | 已交付（Build 913） |
| `keyboard.commandReturn` | Command-Return | 低 | R2 |
| `keyboard.shiftReturn` | Shift-Return | 低 | R2 |
| `keyboard.copy` | 复制 | 低 | R2 |
| `keyboard.paste` | 粘贴 | 中；依赖前台输入状态 | R2 |
| `keyboard.closeWindow` | 关闭窗口 | 中；可能丢失未保存内容 | R2，需风险标记 |
| `keyboard.quitFrontApp` | 退出当前 App | 高；可能丢失未保存内容 | R5，需二次确认 |
| `keyboard.cut` | 剪切 | 中；修改内容 | R2 |
| `keyboard.selectAll` | 全选 | 低 | R2 |
| `keyboard.undo` | 撤销 | 低 | R2 |
| `keyboard.redo` | 重做 | 低 | R2 |
| `keyboard.find` | 查找 | 低 | R2 |
| `keyboard.save` | 保存 | 低 | R2 |
| `keyboard.commandDelete` | Command-Delete | 高；Finder 中可能移到废纸篓 | R5，需二次确认 |
| `keyboard.arrowUp` | 方向上 | 低 | R1 |
| `keyboard.arrowDown` | 方向下 | 低 | R1 |
| `keyboard.arrowLeft` | 方向左 | 低 | R1 |
| `keyboard.arrowRight` | 方向右 | 低 | R1 |
| `scroll.up` | 向上滚动 | 低 | R1 |
| `scroll.down` | 向下滚动 | 低 | R1 |
| `keyboard.deleteBackward` | Delete（退格） | 中；修改内容 | 已交付（Build 913） |

### 3.2 系统与媒体：9 项

| ID | 用户可见动作 | 风险 | 计划批次 |
| --- | --- | --- | --- |
| `system.showDesktop` | 显示桌面 | 低 | R3 |
| `system.contextMenu` | 打开上下文菜单 | 中；需可靠定位 | R3 |
| `system.switchApp` | 切换到上一 App | 低 | R3 |
| `media.volumeUp` | 系统音量 + | 低 | R3 |
| `media.volumeDown` | 系统音量 - | 低 | R3 |
| `media.mute` | 系统静音 | 低 | R3 |
| `media.playPause` | 播放／暂停 | 低 | R3 |
| `media.previousTrack` | 上一曲 | 低 | R3 |
| `media.nextTrack` | 下一曲 | 低 | R3 |

“上一曲／下一曲”按媒体动作实现，不照抄截图中 `Command-Left/Right` 的实现暗示；这能避免在文本编辑器里误移动光标。

### 3.3 自定义动作：3 项

| ID | 用户可见动作 | 规则 | 计划批次 |
| --- | --- | --- | --- |
| `custom.shortcut` | 自定义快捷键 | 记录键码和修饰键，不记录文本；阻止仅修饰键和递归触发 | R4 |
| `typewhale.focusInput` | 聚焦上次输入位置 | 只在权限和目标可验证时执行，失败不乱点屏幕 | R4 |
| `app.openCustom` | 打开自定义 App | 通过系统选择器保存 bundle identifier；不执行 shell | R4 |

### 3.4 打开具体 App：8 个参考入口

目标程序展示了无线麦、Codex、Claude、微信、Cursor、Xcode、Chrome、Safari。TypeWhale 不把竞争产品“无线麦”作为默认品牌入口，而用“显示／隐藏 TypeWhale”替代；其他已安装 App 可作为便捷预设，未安装时显示“未安装”且不可选择。任意 App 仍通过“打开自定义 App”支持。

| TypeWhale 入口 | 稳定语义 | 计划批次 |
| --- | --- | --- |
| 显示／隐藏 TypeWhale | `typewhale.toggleMainWindow` | 已交付（Build 913） |
| 打开 Codex | 已解析 bundle identifier | R4 |
| 打开 Claude | 已解析 bundle identifier | R4 |
| 打开微信 | 已解析 bundle identifier | R4 |
| 打开 Cursor | 已解析 bundle identifier | R4 |
| 打开 Xcode | 已解析 bundle identifier | R4 |
| 打开 Chrome | 已解析 bundle identifier | R4 |
| 打开 Safari | 已解析 bundle identifier | R4 |

### 3.5 TypeWhale 专属动作：6 项

这些动作不来自参考截图，但属于用户已批准的产品语义，必须保留：

| ID | 用户可见动作 | 规则 | 计划批次 |
| --- | --- | --- | --- |
| `remote.systemPassThrough` | 保持系统原功能 | 不执行附加动作，不抑制原事件 | 已交付（Build 913） |
| `remote.pushToTalk` | 按住说话 | 仅物理语音键可选 | 已交付（Build 913） |
| `typewhale.send` | 发送当前内容 | 复用现有发送流程 | 已交付（Build 913） |
| `typewhale.cancel` | 取消当前操作 | 复用现有取消边界 | 已交付（Build 913） |
| `remote.none` | 禁用此按键 | 抑制原事件，不执行新动作 | 已交付（Build 913） |
| `system.lockMac` | 锁定 Mac | 使用系统标准组合；不提供关机、重启或注销 | 已交付（Build 913） |

最终目录为 42 个截图等价槽位（“无线麦”替换为 TypeWhale）加 6 个 TypeWhale 专属语义，共 48 项；Build 913 已交付其中 10 项，后续待开发 38 项。动作 ID 一经进入正式版本只能追加或弃用，不能改写含义。

## 4. 配置机制清单

| 机制 | 产品决定 | 批次 |
| --- | --- | --- |
| 启用自定义按键 | 新增独立总开关；关闭时除语音 PTT 外回到系统默认但不删除配置，不复用“关闭整个遥控器输入”开关 | R1 |
| 禁用单个按键 | 数据层唯一真源为 `remote.none`，避免双重状态 | 已交付（Build 913） |
| 连接与电量 | 复用现有设备状态；没有可靠电量来源时不伪造百分比 | 已交付（Build 913） |
| 实体／页面按键验证 | 物理 down/up 或点击映射控件时高亮产品原图对应区域，并显示最近识别键与动作；页面预览不执行动作 | 已交付（Build 913） |
| 单击／双击／长按 | 独立 Trigger 模型；默认单击，双击会引入确认窗口，长按只触发一次 | R5 |
| 锁定当前按键 | 含义尚需结合真实交互确认，先进入产品待定项，不阻塞 R1–R4 | R5 |
| 语音触发键选择 | 属于电脑键盘输入设置，不并入遥控器动作目录；另案评估 | 不在本路线图 |
| 组合动作／宏 | 需要步骤、延迟、失败补偿和防递归模型 | R6 |

## 5. 用户流程与状态

### 主流程

1. 连接 RC003，进入 TypeWhale 的 Remote tab。
2. 点击页面中的某个按键映射控件，原图先反馈对应位置，再打开按类别分组的动作选择器；目录扩大后增加搜索。
3. 选择动作；高风险动作先展示风险确认，确认后保存。
4. 页面立即更新该按钮标签；按实体按钮时，对应产品图区域高亮并执行一次动作。
5. 重启 TypeWhale 后配置仍存在；恢复默认可以一次还原十三键。

### 关键状态

| 状态 | 页面行为 | 执行行为 |
| --- | --- | --- |
| 未连接 | 可预先配置，设备图显示未连接 | 不执行遥控器动作 |
| 已连接 | 展示当前配置和最近识别 | 按映射执行 |
| 自定义关闭 | 配置仍可查看 | 全部按系统默认放行 |
| 单键禁用 | 显示“已禁用” | 抑制该键原事件，不执行动作 |
| 缺少权限 | 标出具体缺失权限和修复入口 | 不伪装成功，不扩大事件拦截 |
| App 未安装 | 预设项显示未安装 | 不执行、不自动下载 |
| 动作失败 | 保留映射，显示一次明确失败原因 | 不自动重复，避免双执行 |
| 映射损坏 | 只回退损坏按钮 | 其他合法配置保持 |

## 6. 架构边界

```text
Domain
  RemoteActionDescriptor / RemoteActionID / RemoteTrigger / RemoteBinding
  RemoteActionCatalog / RemoteActionAvailability / RemoteMappingMigration

Application
  RemoteActionDispatcher / RemoteTriggerResolver / RemoteBindingService
  RemoteInteractionPublisher / RemoteActionResult

Infrastructure
  KeyboardActionExecutor / ScrollActionExecutor / MediaActionExecutor
  SystemActionExecutor / AppLaunchExecutor / RemoteEventSuppressionRegistry
  RemoteInputSettingsStore / PermissionProbe / InstalledAppResolver

Presentation
  RemoteButtonMappingView / RemoteActionPicker / RemoteActionRiskConfirmation
  RemoteButtonGuideView / RemoteControlIllustrationView / RemoteActionStatusView
```

硬规则：

- Catalog 只描述动作能力，不执行动作。
- Dispatcher 只路由，禁止膨胀成 48 分支的系统 API 文件。
- 每类系统能力由独立 Executor 承担并有协议级测试。
- UI 不持有 UserDefaults、HID usage 或 CGEvent 细节。
- 动作参数采用版本化 Codable payload；旧 v1 映射可逐键迁移，未知 ID 不清空整份配置。
- TypeWhale 合成事件写入固定 marker，永远不被自己的全局监听重复触发。

迁移顺序：先让现有 10 项动作通过 v2 descriptor/binding 运行并继续读取 v1 映射；行为、默认值和已保存配置完全不变后，才逐个追加其余 38 项。R0 不删除旧 key，Build 913 始终可作为回退基线。

R0 永久冻结以下兼容映射；左侧 v1 raw value 继续可读且不得复用，右侧才是 v2 canonical ID：

| v1 raw value | v2 canonical ID |
| --- | --- |
| `pushToTalk` | `remote.pushToTalk` |
| `keyboardEscape` | `keyboard.escape` |
| `keyboardDelete` | `keyboard.deleteBackward` |
| `keyboardReturn` | `keyboard.return` |
| `lockMac` | `system.lockMac` |
| `send` | `typewhale.send` |
| `cancel` | `typewhale.cancel` |
| `toggleMainWindow` | `typewhale.toggleMainWindow` |
| `none` | `remote.none` |
| `system` | `remote.systemPassThrough` |

R0 的一次实体 `buttonDown` 必须形成一个脱敏终态：系统透传、单键禁用、交给 PTT 生命周期、executor 成功或带稳定失败码的失败。日志只包含按钮 ID、canonical action ID、binding schema、executor family 与结果；不得记录正文、剪贴板、语音、蓝牙地址或未来 payload 原值。

## 7. 逐批实施顺序

| 批次 | 完整用户价值 | 交付动作／机制 | 进入条件 | 完成条件 |
| --- | --- | --- | --- | --- |
| 已交付基础（Build 913） | 遥控器已能进入日常使用 | Esc／右键取消倒计时；13 键配置／记忆／恢复；替代语义；页面／物理反馈；PTT、Esc、Return、Delete、锁屏、TypeWhale 显隐／发送／取消、禁用和系统原功能 | 已完成 | 自动回归、Build、签名、运行和安装版页面验收通过 |
| R0 架构骨架 | 后续 38 项可以安全追加 | Descriptor、Catalog、Binding、分类型 Executor 协议、v1→v2 迁移测试 | 本规格批准 | 现有 10 项和用户配置不变；架构与迁移测试通过 |
| R1 导航与滚动 | 任意按钮可承担常用浏览导航 | 方向上／下／左／右、向上／下滚动、独立“启用自定义按键”总开关 | R0 Go | 七项逐个红绿测试；关闭总开关时系统行为与 PTT 保持；安装版实测通过 |
| R2 编辑效率 | 完成常见文字与窗口操作 | Cmd-Return、Shift-Return、复制、粘贴、关闭窗口、剪切、全选、撤销、重做、查找、保存 | R1 Go | 每项一次执行、前台 App 回归和风险提示通过 |
| R3 系统媒体 | 遥控器可做可靠桌面和媒体控制 | 显示桌面、上下文菜单、App 切换、音量、静音、播放、上一曲、下一曲 | R2 Go | 系统版本、权限、播放源和事件回归通过 |
| R4 自定义与 App | 用户不受固定动作目录限制 | 自定义快捷键、聚焦输入、选择任意 App、已安装 App 预设 | R3 Go | 参数持久化、未安装／权限失败、防递归和迁移通过 |
| R5 高级触发与高风险动作 | 同一按钮可承载可控的单／双／长按语义 | Trigger 模型、Command-Q、Command-Delete、“锁定当前按键”交互 | R4 Go，交互语义完成单独复核 | 延迟、误触、丢 key-up、蓝牙抖动和二次确认通过 |
| R6 组合动作 | 多步动作可审计、可停止 | 组合动作编辑、步骤执行、延迟上限、失败停止、循环与递归保护 | R5 稳定使用 | 补偿、取消、超时、审计和安全验收通过 |

每个批次内部仍按“一个动作或一组不可分割动作 → 红灯测试 → 实现 → 绿灯 → 集成回归”串行推进。执行顺序固定为 R0，然后 R1 的方向键、滚动、总开关，再进入 R2；每批完成后生成可安装 Build 和独立验收证据，不等 48 项全部完成才让用户体验。

## 8. 关键决策表

| 条件 | 原系统事件 | 新动作 | 视觉反馈 | 结果 |
| --- | --- | --- | --- | --- |
| 自定义总开关关闭 | 放行 | 不执行 | 高亮对应实体键 | 保持 RC003 默认 |
| 动作为“系统原功能” | 放行 | 不执行 | 高亮 | 保持 RC003 默认 |
| 动作为“禁用” | 仅关联成功时抑制 | 不执行 | 高亮并显示已禁用 | 无副作用 |
| 动作为普通自定义动作 | 仅关联成功时抑制 | 执行一次 | 高亮并显示结果 | 替换默认动作 |
| 映射不合法／未知 | 按该按钮默认值处理 | 不猜测 | 显示已回退 | 不影响其他按钮 |
| 缺少动作所需权限 | 不扩大抑制范围 | 返回失败 | 显示修复入口 | 不伪装成功 |
| 高风险动作未确认 | 放弃保存 | 不执行 | 保持原映射 | 防止误配置 |

## 9. 验收与回归矩阵

每个 R0–R4 动作都必须具备：Catalog 可用性测试、Dispatcher 唯一路由测试、Executor 事件序列测试、持久化 round-trip、普通电脑输入不被吞、实体 down/up 视觉反馈和安装版手测。

发布阻断项：

1. 任一自定义动作与 RC003 原动作同时发生。
2. 普通电脑键盘、鼠标或 TypeWhale 合成事件被误吞。
3. 语音键改映射后仍启动 ATVV／ASR 会话，或恢复 PTT 后不能录音。
4. Esc／右键在无倒计时时被消费，或取消后仍自动发送。
5. 映射重启丢失、未知动作导致全部配置清空，或恢复默认不一致。
6. 页面显示成功但 Executor 实际失败。
7. App 预设通过名字猜测、shell 或未经验证路径启动。
8. R5 单双击／长按在蓝牙延迟、重复 HID 包或丢失 key-up 时产生双动作。

回归保护：Fn 450ms 分类、电脑麦克风、RC003 F5 隔离、ATVV `AUDIO_STOP` 收尾、ASR、粘贴正文、自动发送设置和既有 Remote 连接流程。

## 10. 安全、权限与回滚

- 不提供关机、重启、注销、任意 shell、任意脚本或隐藏下载。
- App 启动保存 bundle identifier；自定义快捷键保存键码与 flags，不保存用户输入内容。
- `Command-Q`、`Command-Delete` 和未来破坏性组合必须在配置时明确二次确认，并在 UI 中持续显示风险标记。
- 全局输入抑制只允许短时间、按钮身份与预期事件三者同时匹配；断连、超时、event tap 重启和丢失 up 都会清空。
- 每批使用独立提交和新 Build；旧映射 key 保留可读，R0–R4 任一失败均可回到 Build 913，不删除用户配置。

## 11. 非目标

- 不复制目标程序的界面、品牌、源代码或专有交互。
- 不把 Remote tab 变成独立外部 App；所有设置和验证留在 TypeWhale 单页内。
- 不把电脑 Fn／Command 语音触发选择混入 RC003 映射。
- R1–R4 不实现多击、长按、宏、任意 URL 或破坏性电源控制。
- 不以 UI 动画代替物理事件、执行结果或真实权限状态。

## 12. 规格自审

- 42 项截图能力已逐项归类，TypeWhale 专属能力和替换项已明确。
- 配置机制与动作语义分离，避免双重状态和单文件膨胀。
- R0–R6 每批都有可用闭环、进入条件、完成条件和回滚点。
- 高风险动作、蓝牙延迟、权限、未安装 App、迁移、误吞输入和录音回归均有边界。
- Build 913 已完成首批 10 项；剩余 38 项与 R0–R6 顺序清楚，不把已交付能力重复排入待办。
- 无影响 R0–R4 开工的占位符；“锁定当前按键”的具体语义明确延后至 R5 单独复核。
- 自评：9/10，可供架构、开发和 QA 在项目所有者批准后直接拆解实施计划。
