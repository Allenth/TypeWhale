# 截图翻译功能规格

## 状态

- 日期：2026-06-25
- 状态：第一版已实现
- 本版范围：仅做英译中
- 目标入口：截图工具栏中的「翻译」按钮

## 背景

当前截图功能已经支持选区、窗口对齐、标注、OCR、复制和保存，但「翻译」按钮仍是占位状态。截图翻译的目标是让用户选中一块包含英文文字的区域后，TypeWhale 自动 OCR 识别英文内容，翻译成中文，并把中文译文直接贴入截图选区中。

本版本只做「英文识别 -> 中文翻译 -> 原文遮盖 -> 译文贴入截图」。不做中文转英文，不做双向自动判断。

## 当前代码状态

| 模块 | 当前状态 |
|---|---|
| `native/Sources/Presentation/Screenshot/ScreenshotCoordinator.swift` | 已有截图覆盖层、选区、复制、保存、标注、OCR 入口。 |
| `ScreenshotOverlayView.ToolAction.translate` | 「翻译」按钮已启用，点击后执行截图英译中。 |
| `ScreenshotOCRRecognizer` | 已基于 Vision `VNRecognizeTextRequest` 实现 OCR，返回纯文本和行级 bounding box。 |
| `renderedSelectionImage()` | 已能把截图选区和 `markups` 一起渲染成复制/保存图片。 |
| `DeepSeekRewriteEngine.translate` | 已有语音翻译链路，可复用英译中方向。 |
| `SmartTranslationDirection.englishToChinese` | 已有英译中方向和默认提示词。 |

## 目标行为

1. 用户进入截图模式并框选英文区域。
2. 用户点击工具栏「翻译」。
3. TypeWhale 对当前选区执行 OCR。
4. 如果 OCR 没有识别到文字，显示提示，不调用 DeepSeek。
5. 如果识别到文字，固定按英译中调用翻译。
6. 翻译完成后，根据 OCR 行级坐标遮盖英文原文，并将中文译文作为截图内的标注层插入当前选区。
7. 用户可以继续移动、删除、撤销译文层。
8. 用户双击选区复制时，剪贴板图片包含译文层。
9. 用户点击保存本地时，保存的 PNG 包含译文层。

## 非目标范围

- 不做中文转英文。
- 不做中英自动语言判断。
- 不做真正的图像修复或生成式背景重建；当前使用平均背景色近似遮盖。
- 不做完整仿原字体排版；当前是基于 OCR 区域的系统字体贴入。
- 不新增截图翻译提示词设置页。
- 不改变现有 OCR 按钮「识别并复制文本」行为。
- 不改变当前截图双击复制逻辑。

## 交互规格

### 工具栏

- 启用现有「翻译」按钮。
- 点击后进入处理中状态，避免重复点击。
- 处理中期间允许取消截图，但不应关闭整个 App 或阻塞电脑输入。

### 状态提示

| 场景 | 主状态 | 详情 |
|---|---|---|
| 开始 OCR | 截图翻译中 | 正在识别选区英文内容 |
| 开始翻译 | 截图翻译中 | 正在翻译为中文 |
| OCR 空结果 | 未识别到文字 | 可以调整截图范围后再试一次 |
| 翻译成功 | 翻译已添加 | 双击复制或保存时会包含中文译文 |
| 缺少 API Key | 截图翻译失败 | 请先设置 DeepSeek API Key |
| 网络或接口失败 | 截图翻译失败 | 保留截图选区，可重试或保存原图 |

## 技术方案

### OCR

第一版可复用现有 `ScreenshotOCRRecognizer.recognize(image:) -> String`。

后续如果要做逐行覆盖，再扩展为：

```swift
struct ScreenshotOCRResult {
    let text: String
    let lines: [ScreenshotOCRLine]
}

struct ScreenshotOCRLine {
    let text: String
    let normalizedBoundingBox: CGRect
}
```

本版不要求逐行坐标。

### 翻译

复用 `DeepSeekRewriteEngine.translate`，方向固定为：

```swift
.englishToChinese
```

建议扩展翻译方法的日志来源参数，便于成本审计区分语音翻译与截图翻译：

```swift
func translate(
    rawText: String,
    direction: SmartTranslationDirection,
    context: SmartInputContext,
    triggeredBy: String = "final_translation"
)
```

截图翻译调用时传入：

```swift
triggeredBy: "screenshot_translation"
```

截图翻译必须使用截图 OCR 专用提示词，不应沿用普通语音翻译语境：

- 明确输入是截图 OCR 行文本，不是语音转写。
- 每一行只要包含可读英文，就必须翻译成中文。
- 短词、按钮、菜单、标题、状态词和普通 UI label 也必须翻译。
- 专有名词、产品名、品牌名、代码、API、文件名、变量名和版本号可以保留英文，但周围普通英文仍需翻译。
- 无法确定上下文时，给出最可能的中文译法，不允许直接输出原英文作为逃避。

### 译文贴入截图

在 `ScreenshotOverlayView.Markup` 中新增译文类型：

```swift
case translation(String, NSRect, [TranslationPatch])
```

默认插入策略：

- 放在选区内底部。
- 左右边距 16pt。
- 宽度不超过选区宽度减去 32pt。
- 高度按中文译文自动换行计算。
- 背景使用半透明深色或浅色卡片，保证可读。
- 字号根据选区大小控制在 14-18pt。

当前行级贴回策略：

- 每个 OCR 行生成一个译文块，贴回该行附近。
- 译文背景按中文实际文字宽度和原 OCR 行宽温和扩展，不能设置大号固定最小宽。
- 短 label 的背景应保持紧凑，避免覆盖相邻按钮、菜单项或正文。
- 原英文行使用本地平均背景色做小范围遮盖，译文 label 只覆盖自身需要的区域。

译文层应参与：

- `drawMarkups()`
- `renderedSelectionImage()`
- 选中与拖动
- 删除
- 撤销

## 优先级

| 优先级 | 内容 | 验收 |
|---|---|---|
| P0 | 已完成：启用「翻译」按钮，完成 OCR -> 英译中 -> 译文插入截图 | 英文截图可生成中文译文层 |
| P0 | 已完成：复制/保存输出包含译文层 | 双击复制和保存 PNG 都包含译文 |
| P0 | 已完成：失败状态不关闭截图浮层 | OCR 空、API 失败后仍可继续操作 |
| P1 | 已完成：译文层可移动、撤销、删除 | 与现有标注操作一致 |
| P1 | 已完成：DeepSeek 日志区分 `screenshot_translation` | 成本审计能识别截图翻译来源 |
| P2 | 已完成：OCR 返回行级坐标，为后续逐行覆盖做准备 | 不影响本版交付 |
| P2 | 已完成第一版：原文遮盖、背景近似修复、区域贴入 | 后续可继续做生成式修复和更完整的仿原字体排版 |
| P3 / Backlog | 中英自动判断与中译英 | 最低优先级，后续开发再评估 |

## 验收标准

1. 英文截图区域点击「翻译」后，能在截图选区内看到中文译文。
2. OCR 未识别到文字时，不调用 DeepSeek。
3. DeepSeek 翻译失败时，截图浮层不关闭，用户仍可复制、保存或取消。
4. 双击选区复制出的图片包含中文译文。
5. 点击「保存本地」保存出的 PNG 包含中文译文。
6. 现有矩形、箭头、画笔、文字、OCR、复制、保存、取消功能不回退。
7. 本版本不出现中文转英文入口或自动双向翻译承诺。

## 测试计划

| 层级 | 测试内容 |
|---|---|
| 单元 | 英译中方向固定，不走自动判断。 |
| 单元 | 译文卡片 bounds 计算不越出选区。 |
| 集成 | OCR 成功后调用英译中翻译并插入 `translation` markup。 |
| 集成 | OCR 空文本时不调用翻译。 |
| 手动 | 英文网页截图 -> 翻译 -> 双击复制 -> 粘贴检查图片含中文译文。 |
| 手动 | 英文截图 -> 翻译 -> 保存本地 -> 打开 PNG 检查含中文译文。 |
| 回归 | 标注、撤销、复制、保存、取消继续可用。 |

## 风险与后续

- Vision OCR 对小字号、低对比度、倾斜文本的识别质量有限；本版失败时应保留用户可重试路径。
- 译文卡片可能遮挡原文；这是本版取舍，优先保证可读和可保存。
- DeepSeek 成本需要通过 `screenshot_translation` 单独审计，避免和语音翻译混在一起。
- 后续商业化增强应优先评估逐行 OCR 坐标、自动遮罩和背景修复。
