# TypeWhale 遥控器设备图示与完整按键目录设计

日期：2026-09-13
状态：视觉方向已获项目所有者批准；架构状态为 `Conditional`，满足 G0/G1 后可实施
关联 AWF 任务：`task_b38e01187066d0fe778e562c`
基线：TypeWhale Pro 2.0.58 (Build 906)，提交 `4d2d22c`

## 1. 产品目标

在 TypeWhale 的“遥控器”页面最下方增加一个完整、原生的设备功能图解。用户滚动到底后，应能直接从小米蓝牙遥控器 2 Pro 的真实按键位置找到按钮名称和当前功能，不需要对照说明书或理解 HID/F5 等技术信息。

本轮同时修复当前页面的按键清单不完整问题：领域模型已有 13 个按键，页面只展示 5 个，硬件 profile 只识别 12 个。完成后，默认动作、硬件识别、映射编辑、动作分发与图示必须通过稳定 `RemoteButton` ID 对齐，不再各自维护互相漂移的清单。

长期目标是全部功能键可配置，但本轮只完整呈现并执行已经存在的动作类型。新动作、替换系统行为、语音键重映射、长短按或组合键语义留待后续产品讨论。

## 2. 用户场景与成功结果

### 主要场景

1. 用户进入遥控器页，先看到连接、设备、语音链路、映射、权限和排障信息。
2. 用户滚动到页面最下方，看到居中的遥控器示意图。
3. 左右两侧标签通过折线准确连接到物理按钮，并显示“按钮名称 + 当前功能”。
4. 用户在上方映射区修改一个已有动作后，底部图示的功能标签立即同步。
5. 用户点击“恢复默认”后，映射控件和图示一起恢复默认值。

### 可观察的成功标准

- 当前产品目录中的 13 个物理按键位置各出现一次，不重复、不遗漏、不以一个笼统“方向键”隐藏四向语义；其中未核证 HID usage 的位置必须明确标记，不能伪装成已可配置。
- 每条连线终点明确落在对应按钮，左右标签按物理高度排序，不交叉。
- 最长现有动作文案不截断；页面不产生横向滚动。
- 深色和晨雾浅色主题均保持足够对比，颜色不是唯一识别方式。
- VoiceOver 能读到每个按钮名称和当前功能；绘制的装饰线不进入焦点顺序。
- 原有页面上半部、语音录入、F5 隔离、电脑麦克风和系统按键行为不退化。

## 3. 范围边界

### In scope

- 行为保持型 Remote 展示层拆分。
- 规范化 RC003 按键 profile，并核对领域按键、HID usage、映射 UI、动作分发与图示覆盖。
- 完整展示当前产品目录中的 13 个物理按钮位置及其默认/当前状态；对尚未核证 HID usage 的按钮显示真实限制。
- 将现有安全动作编辑能力扩展到所有当前允许编辑且能被核证的按键。
- 原创 AppKit/Core Graphics 设备轮廓、按钮、折线和系统符号。
- 默认、持久化、修改、恢复、禁用、未配对、长文案、深浅主题和受约束布局验证。

### Out of scope

- 新动作类型、动作搜索、快捷键录制、URL/脚本/App 启动、组合键、按压时长、导入导出和云同步。
- 决定自定义动作“附加执行”还是“替换系统动作”。
- 允许语音键改作其他功能，或改变语音键与 ATVV 的关系。
- 改写蓝牙、音频、ASR、录音收尾、Fn 或 F5 抑制主链路。
- 将第三方产品图片、Logo、字体或网络资源打包进 App。

### Protected invariants

- `RemoteButtonMapping` 继续是当前功能的唯一真源，持久化 key/schema v1 不变。
- IOHID 保持非独占；普通物理 F5 和遥控器系统按键继续放行。
- voice F5 的 120ms 来源关联、310 秒最长保持保险不变。
- `AUDIO_STOP` 继续是遥控器录音收尾权威。
- 电脑 Fn、电脑麦克风与遥控器输入继续独立启动并共享后半程。
- 页面上半部信息顺序和真实状态含义不变。

## 4. 现状证据与架构判断

### 已确认事实

- `MainViewController+Remote.swift` 约 436 行，一个 `RemoteInspectorView` 同时承担页面装配、状态文案、设备信息、语音管线、映射控件、权限、排障、事件绑定和主控制器接线。
- `RemoteButton` 定义 13 个按键：voice、四向、center、back、home、menu、volumeUp、volumeDown、tv、power。
- `RemoteButtonMapping.defaults` 覆盖 13 个按键，但页面只展示 voice、center、back、home、menu。
- `XiaomiRemote2ProButtons` 当前映射 12 个 usage，没有 `.menu`。
- 语音键当前固定为 `.pushToTalk`，不能编辑；这是因为 voice HID 同时参与 ATVV 直接 `AUDIO_START` 的来源关联。
- 当前自定义动作是附加 App 行为，`.system` 与 `.none` 在 App 分发层不执行额外动作；非独占 HID 仍允许系统收到按键。

### 架构意义

状态为 `Conditional`。问题不是蓝牙或录音架构失效，而是按键这条垂直切片缺少一致性边界，且展示层单文件职责过多。必须先做有界拆分和 characterization，再添加图示；不允许借机重写稳定语音主链路。

## 5. 候选方案

### A. 静态产品图 + 固定文字

优点：实现快，视觉接近产品照片。
缺点：存在素材与 Logo 许可风险；深浅主题适配差；文字无法跟随当前 mapping；按钮清单继续重复。
结论：Rejected。

### B. 在现有 Remote 文件里增加单个绘制 View

优点：变更文件少，回滚简单。
缺点：继续扩大维护热点；图示、坐标、文案和页面状态耦合；无法解决 13/12/5 清单不一致；违反明确的分层约束。
结论：Rejected。

### C. 规范化按键目录 + 模块化原生图示

优点：每层只拥有本层事实；图示和编辑区共享当前 mapping；原创绘制规避外部资产许可；未来新增动作只需扩展动作与格式化，不改设备几何。
代价：需要先完成一次行为保持型拆分，并增加跨层覆盖测试。
结论：Accepted under G0/G1 conditions。

## 6. 选定架构

```text
RC003 HID event
    → XiaomiRemote2ProHIDProfile（usage → RemoteButton）
    → RemoteHIDEventReducer（down/up）
    → RemoteInputCoordinator
        → voice 来源关联（保持现状）
        → RemoteButtonActionDispatcher（已有动作）
        → RemoteInputSnapshot.mappings
            ├─ RemoteButtonMappingView（编辑）
            └─ RemoteButtonGuideView（当前功能图解）
                   → XiaomiRemote2ProDiagramSpec（几何/排序）
                   → RemoteControlIllustrationView（纯绘制）
```

### Domain

`RemoteButtonMapping.swift`

- 只拥有稳定按钮 ID、动作 ID、默认映射、可编辑规则和缺键回退。
- 不包含 AppKit、HID usage、坐标或主题颜色。
- 现有中文展示文案迁至 Presentation formatter，避免 Domain 承担页面语言。

### Infrastructure

`XiaomiRemote2ProHIDProfile.swift`

- 独占设备 VID/PID 与 `RemoteHIDUsage → RemoteButton`。
- 每个已核证物理键只有一个条目；未核证键不得猜值。

`RemoteHIDEventReducer.swift`

- 保持设备无关，只把 profile 提供的 usage 转为确定性 down/up。

`RemoteInputSettingsStore.swift`

- 从 Application coordinator 移出 UserDefaults 读写。
- 保持现有 key 与 Codable 结构；旧数据缺键时通过 defaults 回退。

### Application

`RemoteButtonActionDispatcher.swift`

- 只执行已有 `.send`、`.cancel`、`.toggleMainWindow`、`.system`、`.none`。
- `.system` 与 `.none` 本轮继续不产生 App 侧附加动作。
- 不拥有 HID、布局、持久化或语音会话。

`RemoteInputCoordinator.swift`

- 继续拥有 lifecycle、snapshot、voice 来源关联与组件协调。
- 先把 voice HID 交给 Bluetooth controller 维持直接 `AUDIO_START` 关联，再把非语音动作交给 dispatcher。

### Presentation

`MainViewController+Remote.swift`

- 最终只负责创建 Remote 页面并绑定 MainViewController callbacks。

`RemoteInspectorView.swift`

- 只负责编排区块、接收 snapshot 并把状态分发给子视图。

`RemoteConnectionOverviewView.swift`

- 连接开关、设备、主要动作和状态说明。

`RemoteVoicePipelineView.swift`

- 蓝牙、控制、音频包、PCM 与 TypeWhale 会话阶段。

`RemoteButtonMappingView.swift`

- 现有动作下拉、恢复默认与 mapping callback。
- 展示全部当前允许编辑的按键，不负责画设备。

`RemoteSupportView.swift`

- 权限、隐私、使用与排障。

`RemoteButtonGuideView.swift`

- 使用原生 `NSTextField` 组成左右标签，保证可访问性。
- 根据 snapshot mapping 更新“当前功能”，不执行动作、不持久化。

`XiaomiRemote2ProDiagramSpec.swift`

- 只拥有归一化按钮锚点、左右列、排序和图标语义。
- 对 13 个 `RemoteButton` 保持一对一覆盖。

`RemoteControlIllustrationView.swift`

- 只绘制原创设备轮廓、按钮、连接线和 SF Symbols。
- 不绘制文字、不读取 mapping、不响应业务动作。

## 7. 视觉与交互规格

### 页面位置

- 新区块标题：“设备与按键说明”。
- 放在“使用与排障”之后，严格位于页面最下方。
- 原有连接状态、语音链路和恢复入口保持在滚动首屏，不被图示推到上方之外。

### 设备图形

- 银灰色竖向圆角轮廓，中间深色按键，比例参考真实 RC003，但不追求产品照片级复制。
- 不使用 Xiaomi 字样、商标、NFC Logo 或外部位图。
- 按钮采用 Core Graphics 路径和 SF Symbols；系统符号不可用时使用简单几何图标。
- 图形只承担位置认知，不模拟金属纹理或手持场景。

### 13 个标注

左侧按物理高度排序：

1. 电源键
2. 方向上
3. 方向左
4. 返回键
5. 主页键
6. 自定义/菜单键

右侧按物理高度排序：

1. 语音键
2. 方向右
3. 确定键
4. 方向下
5. 音量加
6. 音量减
7. 电视键

每个标签包含：

```text
按钮名称
当前：格式化后的实际动作
```

`.system` 根据按钮显示更具体的当前含义，例如“系统导航”“系统确认”“系统音量”；`.none` 显示“无附加操作”；其他动作显示既有动作名称。若某键尚未取得可证明的 HID 事件，第二行显示“当前：系统接管／待核证”，不能写成 TypeWhale 已可配置。

### 映射区域

- 语音键继续显示为固定“按住说话”。
- 其他已核证按键使用现有动作下拉，不新增动作。
- 使用双列紧凑布局控制页面长度；每一行仍有完整 accessibility label。
- 自定义/菜单键只有在 G0 确认真实 usage 后才进入可编辑状态；否则诚实显示为待核证。
- “恢复默认”对完整 mapping 生效，随后刷新映射区与图示。

### 布局与可访问性

- 在当前约 592pt 内容宽度下，设备居中，标签列位于两侧；引线使用短水平段 + 折线段，终点有小圆点。
- 标签列与设备之间保留固定安全间距；引线只在中间绘制层出现，不穿过文字。
- 受约束宽度下改为“图示在上、左右标签转为两列在下”的无连线碰撞布局；不缩小文字到不可读。
- 标题使用现有 group 样式；按钮名称 11pt medium，功能 10pt muted；使用系统字体。
- accessibility 顺序按物理从上到下排列；装饰轮廓和引线 `accessibilityElement = false`。

## 8. 状态与错误处理

- 图示是使用说明，不依赖当前连接；disabled/unpaired 状态仍显示默认或已保存 mapping。
- 当前 mapping 缺键时使用 defaults，不显示空白或崩溃。
- 未核证按键使用明确状态文案，不以灰色 alone 表达不可用。
- 长动作文字优先换行，不截断；布局高度随内容增长。
- 切换 tab 后由最新 snapshot 恢复映射与图示，不保留子视图自己的业务状态。
- 绘制失败或 symbol 缺失时回退到几何按钮，不影响上半页或映射编辑。

## 9. 实施顺序与门禁

### G0：物理按键核证

- 核对 13 个物理按钮与当前 enum。
- 从真实 RC003 事件或受信硬件证据确认自定义/菜单键 usage；禁止用猜测填入 profile。
- 记录只说明 usage 和按钮身份，不记录设备地址或用户内容。

### G1：Characterization / RED

先增加失败测试，证明当前 13/12/5 不一致：

- `RemoteButton.allCases` 均有默认 mapping。
- HID profile、mapping presentation 与 diagram spec 对所有支持键一一覆盖且无孤儿。
- 已有动作 dispatch 每种执行一次；`.system/.none` 不执行 App callback。
- voice 仍不可被改写，且 HID→ATVV 关联不变。
- v1 mapping round-trip 与缺键回默认。
- 新图示 feature check 在视图/规格尚不存在时失败。

### G2：行为保持型重构

- 按第 6 节边界拆分文件，不改变用户可见布局和行为。
- 完成 remote aggregate、Fn/F5 与 recording finalization 回归。
- 构建唯一架构检查点（原计划 Build 907；该号编译失败后实际候选顺延为 Build 908），覆盖安装并截图证明上半页等价。
- 单独提交；任何行为差异均回滚该阶段，不进入 G3。

### G3：图示与完整已有按键

- 先为 diagram spec、动态标签、完整 mapping rows 写 RED。
- 实现原创图示、左右标签、同步刷新和受约束布局。
- 构建唯一功能候选（因 Build 907 编译失败，原计划 Build 908 顺延为 Build 909），覆盖安装、验签、打开并进行真实视觉/可访问性检查。
- 单独提交。

### G4：交付

- 运行 AWF 契约全部检查并取得 deliver `ready`。
- 更新现行 PRODUCT/ARCHITECTURE/DESIGN/RELEASE_QA/DEVELOPMENT_LOG、应用内版本历史与构建日志。
- 记录真实 RC003 按键证据、截图、视口、主题、状态、交互、残余风险和回滚点。

## 10. 验收矩阵

| Gate | 必须通过 |
| --- | --- |
| 架构 | MainVC wiring、页面装配、映射编辑、图示布局、纯绘制、HID profile、动作执行分别有单一职责 |
| 按键覆盖 | 当前产品目录中的 13 个物理位置与 diagram spec 一一对应；已核证支持键在 profile/UI/action tests 无孤儿；未核证位置有明确状态且不可编辑 |
| 视觉 | 页面底部；连线无交叉；按钮终点准确；深/浅主题、Retina、受约束高度无裁切或横向滚动 |
| 状态 | 默认、旧设置缺键、修改、恢复、禁用、未配对、连接、长文案稳定 |
| 可访问性 | 每键可读“名称 + 当前功能”；装饰不抢焦点；控件标签完整 |
| 集成 | voice/F5/ATVV/五分钟收尾、电脑 Fn/麦克风、方向/确认/返回/音量等系统行为无回归 |
| 许可/隐私 | 无外部图片、Logo、字体、新权限、网络、依赖或敏感日志 |
| 交付 | Build 907 保留失败记录；实际架构候选 Build 908 与功能候选 Build 909 各有唯一代码、记录、签名、安装、运行、截图和 Git 提交 |

## 11. 回滚与评审触发

- G2 回滚到 `4d2d22c` / Build 906；G3 可独立回滚到 G2 提交。
- 如果按键核证显示当前 enum 与真实硬件不同，先修改目录决策和测试，再进入实现。
- 如果实现要求修改 `RemoteBluetoothController`、`SpeechInputCoordinator`、F5 关联或持久化 schema，重新进入架构评审。
- 如果 13 条连线在当前固定面板宽度无法达到可读性，保留居中设备图，改为设备下方两列索引；不得缩字、裁切或删除按钮。
- 如果未来批准替换系统事件或语音键重映射，创建新的产品/架构决策，不在本设计上静默扩展。

## 12. 后续明确延期的产品决定

- 自定义动作是附加还是替换系统行为。
- `.none` 是否只取消 App 附加动作，还是吞掉系统事件。
- 语音键能否重映射，以及重映射后是否仍启动 ATVV。
- 新动作目录、应用/URL/脚本、快捷键录制、长按、短按、双击和组合键。
- 配置搜索、导入导出、设备 profile 版本与多遥控器支持。

这些延期项不影响本轮图示和已有动作完整性，但实施代码不得为它们预先增加未经验证的生产路径。
