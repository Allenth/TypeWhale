# 方案 C 落地 · 逐步开启实施计划

目标：把「侧边导航工作台 + 晨雾微光」从设计稿落成代码，**不做一次性大改**。核心策略：

- **开关驱动、新旧并存**：每个高风险改动都藏在开关（`UserDefaults` flag）后，默认关闭。主分支任何时候都能编译、能跑、能回退。
- **每步一提交、每步一验证**：改完即 `./native/build_native_app.sh` 并在真机核对该步效果，通过再进下一步。
- **利好前提**：内容构建器已模块化（`buildInspectorPage(tab)` + `build*Content()`），侧导航主要是"外壳替换 + 内容重新分配"，不是推倒重来。

> 构建为手动、并发感知：动手前确认无其他构建在跑；跑构建前看一眼 `git status`。

---

## Phase 0 · 基线与闸门（零视觉变化）

- 确认当前 `1.9.27 (610)` 能正常构建、运行。截图留存旧界面基线。
- 在 `MainViewSettings` 增开关（默认关，保证不变现状）：
  - `useSidebarLayout: Bool`（侧导航 vs 旧标签栏）
  - `useMistLightTheme: Bool`（晨雾浅色 vs 现有深色）
- **文件**：`Infrastructure/Settings/AppSettings.swift`
- **验证**：构建通过，界面与现在完全一致（开关未启用）。
- **可回退**：本阶段不改任何 UI。

---

## Phase 1 · 晨雾浅色主题（配色，隔离且可逆）

只动颜色，不动布局。做成**深/浅双主题**，用 `useMistLightTheme` 切换，默认仍深色。

- 在 `UITheme` 把 `waterInk*` 从"固定深色"改为"随开关取深/浅两套值"；新增 `waterInkRecording`（`#D08A72`）。
- 浅色取值见 [README 的 token 映射表](README.md#配色-token-映射)。
- **文件**：`Presentation/Shared/UIComponents.swift`
- **风险**：全局配色一次性变 → 用开关隔离；自己切到浅色**逐屏核对对比度/可读性**（尤其次要文字、描边、禁用态）。
- **验证**：开关关=旧深色；开关开=晨雾浅色，逐页扫一遍无阅读障碍。
- **可回退**：关开关即恢复深色。稳定后再考虑改默认。

---

## Phase 2 · 侧导航外壳（结构，flag 后并存，先 1:1）

搭出"导航栏 + 内容区"外壳，**先不做功能重组**——仍是现有 5 个分区，只把标签栏换成左侧导航。

- 新建侧导航容器：左 172pt nav rail + 右 content area，复用现有 `buildInspectorPage(tab)` 的内容。
- `buildMainSurface()` 里按 `useSidebarLayout` 二选一：开→侧导航壳；关→现有 `session + inspector` 双列。
- "当前会话"从常驻左列变为导航第一项（内容复用 `buildSessionAndRecentContent()`）。
- **文件**：`MainViewController+PanelLayout.swift`（新增 `buildSidebarSurface()`，不动 `buildInspectorTabs`）
- **风险**：左列 session 迁入内容区 → 复用现成 content builder，降低风险；旧路径原样保留。
- **验证**：开关开→导航切换/选中态/滚动/布局稳定，五页内容都在；开关关→旧界面不受影响。
- **可回退**：关开关回到旧标签栏布局。

---

## Phase 3 · 逐页信息架构重组（一次一页，各自提交）

在侧导航壳内，按设计稿把功能重新切分。**每页一个独立提交，改完即验证**。建议顺序（先易后难、先被依赖者）：

| 步 | 页面 | 主要动作 | 主要文件 |
|----|------|----------|----------|
| 3a | 当前会话 | 会话卡 + 波形 + 最近转录成为导航首页；四状态色 | `buildSessionAndRecentContent` / `buildSessionPanel` |
| 3b | 翻译 | 从智能抽出 自动翻译/方向/提示词/社交清单；方向改**分段** | 新 `buildTranslationPageContent`；`SmartTranslation*` |
| 3c | 智能整理 | 去掉已迁走项，重排 整理引擎/规则/服务 三组卡 | `buildSmartRewritePanelContent` 拆分 |
| 3d | 截图 | 保存位置 + 归档整理 合成一页（标注仍在独立浮层） | `buildScreenshotSettingsContent` + `screenshotArchiveMode` |
| 3e | 闪念 | 抽出 闪念整理 + 闪念键 | `ideaPillRewriteMode` + `HotkeyDomain` |
| 3f | 快捷键 | 9 热键按 录音/截图/其他 分组 + keycap 可视化 | `buildHotkeysPanelContent` |
| 3g | 状态·模型 | 合并 系统 6 开关 + 模型列表 + 权限 | `buildSystemSettingsContent` + `buildStatusPanelContent` + `ManagedASRModelListView` |

- **风险**：每页只碰自己的 content builder，互不影响；导航项数据驱动，加/改一页不牵动别页。
- **验证**：每页做完能编译、能切到该页、内容与稿一致。
- **可回退**：单页提交，回退粒度到页。

> 迁移完成前，旧 `buildInspectorPage` 可暂留作对照；全部页迁完再删。

---

## Phase 4 · 组件精修 + 胶囊配色

- 分段控件（翻译方向）、keycap、语义色状态芯片、卡片圆角/间距按稿对齐。
- 胶囊（默认 / 刘海）配色同步晨雾：`ThemePreviewTile` 已用 `waterInk*`，随 Phase 1 自动跟进，此处仅微调。
- **文件**：`Presentation/Capsule/*`、`ThemePreviewTile.swift`
- **验证**：胶囊在浅色下对比度足够；预览瓦片与实际胶囊一致。

---

## Phase 5 · 切默认 + 清理

- 八页全部验证通过后，把 `useSidebarLayout` / `useMistLightTheme` 默认打开。
- 移除旧标签栏路径（`buildInspectorTabs` 及仅其使用的辅助），或将深色保留为可选主题。
- **验证**：全流程回归（录音→识别→整理→翻译→截图→闪念→OpenClaw）。
- **可回退**：切默认是最后一步；此前每阶段都可独立回退。

---

## 依赖与顺序小结

```
Phase 0 闸门 ── Phase 1 配色 ─┐
                              ├─ Phase 2 外壳 ── Phase 3 逐页(3a→3g) ── Phase 4 精修 ── Phase 5 切默认
（配色与外壳互不依赖，可并行准备，但建议先配色后外壳，避免同时排查两类问题）
```

最小可演示里程碑：**Phase 1 + Phase 2 完成**即可在真机看到"晨雾浅色 + 侧导航"的整体骨架（内容还是旧分区），先验证方向对不对，再进 Phase 3 精修内容。
