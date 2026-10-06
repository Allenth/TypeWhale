# 方案 C · 侧边导航工作台 — UI 设计稿

配色统一采用「晨雾微光」（`UITheme.waterInk*` 的浅色版）。逐页高保真设计，作为开发时的像素级参考。

在浏览器中直接打开 `.html` 文件预览。

## 页面进度

| # | 页面 | 文件 | 状态 |
|---|------|------|------|
| 1 | 当前会话 | [session.html](session.html) | ✅ 高保真稿 |
| 2 | 智能整理 | [smart.html](smart.html) | ✅ 高保真稿 |
| 3 | 翻译 | [translate.html](translate.html) | ✅ 高保真稿 |
| 4 | 截图 | [screenshot.html](screenshot.html) | ✅ 高保真稿 |
| 5 | 闪念 | [idea.html](idea.html) | ✅ 高保真稿 |
| 6 | OpenClaw | [openclaw.html](openclaw.html) | ✅ 高保真稿 |
| 7 | 快捷键 | [hotkeys.html](hotkeys.html) | ✅ 高保真稿 |
| 8 | 状态 · 模型 | [status.html](status.html) | ✅ 高保真稿 |

**8/8 页高保真稿全部完成。** 落码计划见 [IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md)(开关驱动、新旧并存、逐页迁移)。

## 布局骨架

窗口 = 顶栏 + 左导航（172pt）+ 右内容区。左导航把八大功能显式成行，标签栏永不溢出；右侧内容区专注单一任务。

导航结构（八项 + 「系统」分组）：

```
当前会话 · 智能整理 · 翻译 · 截图 · 闪念 · OpenClaw
── 系统 ──
快捷键 · 状态·模型
```

## 信息架构重组（相比现状）

现状「智能」标签把整理 + 翻译 + 闪念 + 归档挤成 13 行；方案 C 按归属拆分：

| 原位置 | 设置项 | 新归属 |
|--------|--------|--------|
| 智能 | 自动翻译 / 翻译方向 / 翻译提示词 | → 翻译 |
| 智能 | 社交清单（驱动中译英语气） | → 翻译 |
| 智能 | 闪念整理 | → 闪念 |
| 智能 | 归档整理 | → 截图 |
| 常用 › 截图 | 保存位置 | → 截图 |
| 常用 › 系统 | 输入设备 / 实时预览 / 停顿完成 / 降音量 / 降噪 / 开机自启 | → 状态·模型 |
| 状态 | 语音模型 / 麦克风·辅助功能权限 | → 状态·模型 |
| 各处快捷键 | 9 个全局热键 | → 快捷键 |

- 翻译方向由下拉改**分段控件**（仅 3 档）；整理模式保留下拉（7 档）。

## 配色 token 映射

现有 `Presentation/Shared/UIComponents.swift` 里的 `UITheme.waterInk*` 是深色版，晨雾微光是同族浅色版——只改 token 取值，组件代码不动。

| Token | 晨雾取值 | 用途 |
|-------|----------|------|
| `waterInkBackground` | `#EBEFF3` | 窗口底 |
| `waterInkSurface` | `#FFFFFF` | 卡片面 |
| `waterInkPanel` / `panelFill` | `#F5F8FA` | 导航栏 / 次级面 |
| `waterInkLine` / `cardBorder` | `rgba(64,94,116,.15)` | 描边 |
| `waterInkText` | `#2C3E4B` | 主文字 |
| `waterInkMuted` | `#6E8290` | 次要文字 |
| `waterInkFaint` | `#94A6B2` | 弱化 / 占位 |
| `waterInkMistBlue` / `capsuleAccent` | `#5B84A6` | 强调 / 选中 / 波形 |
| `waterInkSuccess` | `#5AA588` | 完成态 LED |
| `waterInkWarning` | `#C0975B` | 识别中态 |
| 新增 `waterInkRecording` | `#D08A72` | 录音态 LED |

## 代码对接点

- 配色 token：`Presentation/Shared/UIComponents.swift · UITheme`
- 会话卡 / 状态区：`MainViewController+PanelLayout.swift · buildSessionPanel`
- 最近转录：`MainViewController+RecentTranscriptions.swift`
- 左导航壳（新增）：替换 `buildInspectorTabs` 的标签栏为侧导航
