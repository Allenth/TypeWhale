# 胶囊主题截图预览 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将“预览主题”区域升级为三张截图式主题卡，并让默认胶囊卡同时展示普通、闪念、OpenClaw 三种类型。

**Architecture:** 运行时直接实例化生产 `RecordingPanel`、`NotchPreviewPresenter`、`MinimalBlackPreviewPresenter`，设置固定演示状态后把真实视图离屏渲染为 `NSImage`；`ThemePreviewTile` 只显示快照、绘制卡片和处理选择。禁止重新手绘或维护第二套胶囊视觉，主题枚举、主题切换和生产业务链路保持不变。

**Tech Stack:** Swift 5、AppKit、NSBitmapImageRep、现有原生构建脚本与 shell 边界检查。

## Global Constraints

- 继续保留 `.classic`、`.notch`、`.minimalBlack` 三种 `PreviewTheme`。
- 默认胶囊截图必须同时包含普通录音、闪念、OpenClaw 三种类型。
- 预览卡不参与录音、ASR、缓存、粘贴或 OpenClaw 发送。
- 不修改生产胶囊、闪念胶囊、OpenClaw 胶囊的布局、动画和数据入口。
- 日常构建递增 build 号，覆盖安装 `/Applications/TypeWhale Pro.app` 并提交。
- 只在主目录工作，不创建 worktree。

## 2026-07-24 用户验收修正

Build 816 的固定 PNG 是独立绘制的“仿截图”，与生产胶囊并非同一渲染来源，用户验收未通过。Task 1/2 的产物只作为被否决实验记录；以下 Task 4/5 完整替换该实现。

---

### Task 4: 用生产组件生成真实快照

**Files:**
- Create: `native/Sources/Presentation/Main/CapsuleThemeSnapshotFactory.swift`
- Modify: `native/Sources/Presentation/Capsule/RecordingPanel.swift`
- Modify: `native/Sources/Presentation/Notch/NotchPreviewPresenter.swift`
- Modify: `native/Sources/Presentation/MinimalBlackPreview/MinimalBlackPreviewPresenter.swift`
- Modify: `native/Sources/Presentation/Main/ThemePreviewTile.swift`
- Delete: `native/Helpers/CapsuleThemePreviewCapture.swift`
- Delete: `native/Resources/ThemePreviews/classic-normal-idea-openclaw.png`
- Delete: `native/Resources/ThemePreviews/notch-recording.png`
- Delete: `native/Resources/ThemePreviews/minimal-black-text.png`
- Create: `native/Tests/CapsuleThemeProductionSnapshotBoundaryCheck.sh`
- Delete: `native/Tests/CapsuleThemeScreenshotAssetsCheck.sh`

**Interfaces:**
- `NSView.typeWhaleSnapshotImage() -> NSImage?`：离屏缓存当前真实视图。
- `RecordingPanel.makeThemePreviewSnapshot(...) -> NSImage?`：返回普通、闪念或 OpenClaw 的真实生产胶囊快照。
- `NotchPreviewPresenter.makeThemePreviewSnapshot(...) -> NSImage?`：返回真实刘海主题快照。
- `MinimalBlackPreviewPresenter.makeThemePreviewSnapshot(...) -> NSImage?`：返回真实简洁黑色快照。
- `CapsuleThemeSnapshotFactory.makeSnapshot(for:) -> NSImage?`：按主题组合供卡片显示的最终快照。

- [x] **Step 1: 写生产快照边界 RED**

检查必须锁定：

```bash
grep -Fq 'RecordingPanel()' native/Sources/Presentation/Main/CapsuleThemeSnapshotFactory.swift
grep -Fq 'NotchPreviewPresenter()' native/Sources/Presentation/Main/CapsuleThemeSnapshotFactory.swift
grep -Fq 'MinimalBlackPreviewPresenter()' native/Sources/Presentation/Main/CapsuleThemeSnapshotFactory.swift
grep -Fq 'CapsuleThemeSnapshotFactory.makeSnapshot' native/Sources/Presentation/Main/ThemePreviewTile.swift
test ! -e native/Helpers/CapsuleThemePreviewCapture.swift
test ! -d native/Resources/ThemePreviews
```

- [x] **Step 2: 运行 RED**

Run:

```bash
bash native/Tests/CapsuleThemeProductionSnapshotBoundaryCheck.sh
```

Expected: FAIL，生产快照工厂尚不存在。

- [x] **Step 3: 实现通用离屏快照**

```swift
extension NSView {
    func typeWhaleSnapshotImage() -> NSImage? {
        layoutSubtreeIfNeeded()
        guard bounds.width > 0, bounds.height > 0,
              let bitmap = bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        cacheDisplay(in: bounds, to: bitmap)
        let image = NSImage(size: bounds.size)
        image.addRepresentation(bitmap)
        return image
    }
}
```

- [x] **Step 4: 为三个生产 Presenter 增加只读快照入口**

三个入口只设置固定演示状态、执行现有布局并缓存各自 `contentView`，不 `orderFront`、不启动录音、不写设置。

- [x] **Step 5: 工厂组合三主题**

- `.classic`：依次获取普通、闪念、OpenClaw 三张真实 `RecordingPanel` 快照并纵向组合。
- `.notch`：获取真实刘海主题快照。
- `.minimalBlack`：获取真实简洁黑色主题快照。

- [x] **Step 6: 主题卡改为调用生产快照工厂**

删除 `Bundle.main.url` 和固定 PNG 加载；保留主题标题、点击切换和选中描边。

- [x] **Step 7: 删除被否决的绘图工具和 PNG**

删除 Build 816 的独立绘图代码、三张仿制 PNG 和旧资源尺寸检查。

- [x] **Step 8: 运行 GREEN 与相关回归**

```bash
bash native/Tests/CapsuleThemeProductionSnapshotBoundaryCheck.sh
bash native/Tests/PreviewThemeRoutingBoundaryCheck.sh
bash native/Tests/WaveformVisibilityCheck.sh
```

Expected: 全部 PASS。

- [x] **Step 9: 提交真实快照实现**

已提交：`1c66dae1 fix: render theme previews from production capsules`

```bash
git add -u
git add native/Sources/Presentation/Main/CapsuleThemeSnapshotFactory.swift \
  native/Tests/CapsuleThemeProductionSnapshotBoundaryCheck.sh \
  docs/superpowers/specs/2026-07-24-capsule-theme-screenshot-preview-design.md \
  docs/superpowers/plans/2026-07-24-capsule-theme-screenshot-preview.md
git commit -m "fix: render theme previews from production capsules"
```

---

### Task 5: Build 817 安装版验收

- [x] **Step 1: 更新开发日志与 Build 817 版本历史**
- [x] **Step 2: 构建前检查并发**
- [x] **Step 3: 执行 `./native/build_and_log.sh`**
- [x] **Step 4: 解锁状态下截取安装版“预览主题”区域**
- [x] **Step 5: 确认三主题、默认三类型、选中态、裁切和清晰度**
- [x] **Step 6: 运行最终测试、签名校验并提交 build 记录**

验证结果：三个主题边界测试全部通过；源码与安装版均为 `2.0.58 (817)`；安装包签名有效；真实安装版截图确认默认主题包含三个生产胶囊类型，另外两个主题没有裁切。

---

### Task 1: 生成三张截图资源

**Files:**
- Create: `native/Helpers/CapsuleThemePreviewCapture.swift`
- Create: `native/Resources/ThemePreviews/classic-normal-idea-openclaw.png`
- Create: `native/Resources/ThemePreviews/notch-recording.png`
- Create: `native/Resources/ThemePreviews/minimal-black-text.png`
- Create: `native/Tests/CapsuleThemeScreenshotAssetsCheck.sh`

**Interfaces:**
- Consumes: AppKit 绘图 API，以及生产胶囊当前颜色、圆角和类型语义。
- Produces: `640 x 360`、2x 像素密度的三张 PNG；运行时按固定资源名读取。

- [x] **Step 1: 写失败的资源边界检查**

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ASSETS="$ROOT/native/Resources/ThemePreviews"

for file in \
  classic-normal-idea-openclaw.png \
  notch-recording.png \
  minimal-black-text.png; do
  test -f "$ASSETS/$file" || {
    echo "Missing theme screenshot: $file" >&2
    exit 1
  }
  width="$(sips -g pixelWidth "$ASSETS/$file" | awk '/pixelWidth/ {print $2}')"
  height="$(sips -g pixelHeight "$ASSETS/$file" | awk '/pixelHeight/ {print $2}')"
  test "$width" = "640" && test "$height" = "360" || {
    echo "$file must be 640x360" >&2
    exit 1
  }
done

echo "CapsuleThemeScreenshotAssetsCheck passed"
```

- [x] **Step 2: 运行 RED**

Run:

```bash
bash native/Tests/CapsuleThemeScreenshotAssetsCheck.sh
```

Expected: FAIL，首个 PNG 不存在。

- [x] **Step 3: 创建独立截图生成器**

`CapsuleThemePreviewCapture.swift` 使用 `NSBitmapImageRep` 创建 `640 x 360` 画布，并输出三种场景：

```swift
import AppKit

enum PreviewScene: String, CaseIterable {
    case classic = "classic-normal-idea-openclaw"
    case notch = "notch-recording"
    case minimalBlack = "minimal-black-text"
}

@main
struct CapsuleThemePreviewCapture {
    static func main() throws {
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for scene in PreviewScene.allCases {
            let bitmap = render(scene)
            guard let png = bitmap.representation(using: .png, properties: [:]) else {
                throw CaptureError.encoding(scene.rawValue)
            }
            try png.write(to: output.appendingPathComponent("\(scene.rawValue).png"))
        }
    }

    static func render(_ scene: PreviewScene) -> NSBitmapImageRep {
        let pointSize = NSSize(width: 320, height: 180)
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 640,
            pixelsHigh: 360,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        bitmap.size = pointSize
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        drawBackground(in: NSRect(origin: .zero, size: pointSize))
        switch scene {
        case .classic:
            drawClassicStates(in: NSRect(origin: .zero, size: pointSize))
        case .notch:
            drawNotchState(in: NSRect(origin: .zero, size: pointSize))
        case .minimalBlack:
            drawMinimalBlackState(in: NSRect(origin: .zero, size: pointSize))
        }
        NSGraphicsContext.restoreGraphicsState()
        return bitmap
    }
}
```

生成器中的三个绘制方法必须使用当前生产视觉的可观察参数：

- 默认胶囊：42pt 高、20pt 圆角；普通为雾蓝细边，闪念为雾蓝强化边和“闪念”标签，OpenClaw 为红色边和右上小龙虾徽章。
- 刘海主题：黑色圆角岛、左侧目标 App 图标、居中文字、右侧脉冲。
- 简洁黑色：黑色胶囊、低饱和绿色细边、白色正文。

画布使用 `NSBitmapImageRep` 的 `pixelsWide = 640`、`pixelsHigh = 360`，确保资源实际输出 2x 像素。

- [x] **Step 4: 编译生成资源**

Run:

```bash
mkdir -p native/Resources/ThemePreviews
xcrun swiftc \
  -parse-as-library \
  -framework AppKit \
  native/Helpers/CapsuleThemePreviewCapture.swift \
  -o /tmp/CapsuleThemePreviewCapture
/tmp/CapsuleThemePreviewCapture native/Resources/ThemePreviews
```

Expected: 三张 PNG 均生成，尺寸为 `640 x 360`。

- [x] **Step 5: 运行 GREEN**

Run:

```bash
bash native/Tests/CapsuleThemeScreenshotAssetsCheck.sh
```

Expected: `CapsuleThemeScreenshotAssetsCheck passed`

- [x] **Step 6: 提交截图资源**

```bash
git add \
  native/Helpers/CapsuleThemePreviewCapture.swift \
  native/Resources/ThemePreviews \
  native/Tests/CapsuleThemeScreenshotAssetsCheck.sh
git commit -m "feat: add capsule theme screenshot assets"
```

---

### Task 2: 主题卡改为加载截图

**Files:**
- Modify: `native/Sources/Presentation/Main/ThemePreviewTile.swift`
- Modify: `native/Sources/Presentation/Main/MainViewController+PanelLayout.swift`
- Modify: `native/Tests/PreviewThemeRoutingBoundaryCheck.sh`
- Test: `native/Tests/CapsuleThemeScreenshotAssetsCheck.sh`

**Interfaces:**
- Consumes: `Bundle.main/Contents/Resources/ThemePreviews/*.png`。
- Produces: `ThemePreviewTile(kind:title:)` 外部接口保持不变；三种 `Kind` 分别解析固定资源名。

- [x] **Step 1: 扩展现有路由检查形成 RED**

在 `PreviewThemeRoutingBoundaryCheck.sh` 增加：

```bash
grep -Fq 'classic-normal-idea-openclaw' "$TILE"
grep -Fq 'notch-recording' "$TILE"
grep -Fq 'minimal-black-text' "$TILE"
grep -Fq 'Bundle.main.url' "$TILE"
if grep -Fq 'drawClassic(in:' "$TILE"; then
  echo "Theme tiles must use screenshot assets instead of abstract drawings" >&2
  exit 1
fi
```

- [x] **Step 2: 运行 RED**

Run:

```bash
bash native/Tests/PreviewThemeRoutingBoundaryCheck.sh
```

Expected: FAIL，`ThemePreviewTile` 尚未引用截图资源。

- [x] **Step 3: 用图片加载替换抽象绘制**

`ThemePreviewTile.Kind` 提供资源名：

```swift
enum Kind {
    case classic
    case notch
    case minimalBlack

    var resourceName: String {
        switch self {
        case .classic: return "classic-normal-idea-openclaw"
        case .notch: return "notch-recording"
        case .minimalBlack: return "minimal-black-text"
        }
    }
}
```

初始化时加载图片，失败时保留明确的空态而不是崩溃：

```swift
private let previewImage: NSImage?

private static func loadPreviewImage(named name: String) -> NSImage? {
    guard let url = Bundle.main.url(
        forResource: name,
        withExtension: "png",
        subdirectory: "ThemePreviews"
    ) else { return nil }
    return NSImage(contentsOf: url)
}
```

`draw(_:)` 中把图片按比例完整放进场景区域：

```swift
if let previewImage {
    previewImage.draw(
        in: screen,
        from: .zero,
        operation: .sourceOver,
        fraction: 1,
        respectFlipped: true,
        hints: [.interpolation: NSImageInterpolation.high]
    )
} else {
    drawMissingPreview(in: screen)
}
```

删除 `drawClassic`、`drawNotch`、`drawMinimalBlack` 三套抽象示意图。保持点击、标题和选中描边逻辑不变。

- [x] **Step 4: 增加卡片高度而不改变三列结构**

在 `ThemePreviewTile.init` 中把固定高度从 `78` 调整为 `116`；`buildPreviewThemeContent()` 仍使用：

```swift
let stack = NSStackView(views: [classicTile, notchTile, minimalBlackTile])
stack.orientation = .horizontal
stack.alignment = .top
stack.distribution = .fillEqually
stack.spacing = 12
```

- [x] **Step 5: 运行主题相关测试**

Run:

```bash
bash native/Tests/CapsuleThemeScreenshotAssetsCheck.sh
bash native/Tests/PreviewThemeRoutingBoundaryCheck.sh
bash native/Tests/WaveformVisibilityCheck.sh
```

Expected: 全部 PASS。

- [x] **Step 6: 提交运行时改动**

```bash
git add \
  native/Sources/Presentation/Main/ThemePreviewTile.swift \
  native/Sources/Presentation/Main/MainViewController+PanelLayout.swift \
  native/Tests/PreviewThemeRoutingBoundaryCheck.sh
git commit -m "feat: show screenshot-backed capsule themes"
```

---

### Task 3: 安装版视觉验收与记录

**Files:**
- Modify: `docs/开发日志.md`
- Modify: `native/Sources/Presentation/VersionHistory/VersionHistoryViewController.swift`
- Auto-modified by build: `README.md`
- Auto-modified by build: `macos/README.md`
- Auto-modified by build: `docs/构建日志.md`
- Auto-modified by build: `native/build_native_app.sh`

**Interfaces:**
- Consumes: Task 1 PNG 与 Task 2 图片主题卡。
- Produces: 新 build 的安装版、版本记录和真实界面截图验收。

- [x] **Step 1: 更新版本叙事**

开发日志和版本历史写明：

- 预览主题改为三张截图式主题卡。
- 默认胶囊卡同时展示普通、闪念、OpenClaw。
- 主题选择和生产语音链路没有改变。

- [x] **Step 2: 构建前并发检查**

Run:

```bash
git branch --show-current
git status --short
pgrep -fal 'build_and_log|release_local_build|build_native_app|swiftc|xcodebuild' || true
```

Expected: 当前分支为 `codex/typewhale-pro-asr-hotwords`，无重叠构建进程；只保留本任务改动和受保护的既有未跟踪目录。

- [x] **Step 3: 构建、递增 build、覆盖安装**

Run:

```bash
./native/build_and_log.sh
```

Expected: 编译成功、build 号递增、覆盖安装并打开 `/Applications/TypeWhale Pro.app`、签名校验通过。

- [ ] **Step 4: 真实安装版视觉复核**

在“常用 → 预览主题”检查：

- 三张主题卡完整显示且没有裁切。
- 默认胶囊卡能辨认普通、闪念、OpenClaw 三种状态。
- 选中描边明显但不压过截图内容。
- 主窗口宽度不变、主题区无横向溢出。
- 逐一点击三张卡，选中态正确切换。

- [x] **Step 5: 最终验证**

Run:

```bash
bash native/Tests/CapsuleThemeScreenshotAssetsCheck.sh
bash native/Tests/PreviewThemeRoutingBoundaryCheck.sh
bash native/Tests/WaveformVisibilityCheck.sh
git diff --check
/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' \
  '/Applications/TypeWhale Pro.app/Contents/Info.plist'
codesign --verify --deep --strict --verbose=2 \
  '/Applications/TypeWhale Pro.app'
```

Expected: 所有测试 PASS，diff 无格式错误，安装版 build 与源码一致，签名有效。

- [x] **Step 6: 提交 build 对应记录**

```bash
git add \
  README.md \
  macos/README.md \
  docs/开发日志.md \
  docs/构建日志.md \
  native/Sources/Presentation/VersionHistory/VersionHistoryViewController.swift \
  native/build_native_app.sh
git commit -m "release: install capsule theme screenshot previews"
```
