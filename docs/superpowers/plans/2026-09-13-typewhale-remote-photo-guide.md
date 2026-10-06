# TypeWhale RC003 原图按键说明 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 TypeWhale 遥控器页底部错误的自绘 RC003 设备图替换为已授权原图，并让 13 个既有标注准确连接真实按键，同时保持所有输入和映射行为不变。

**Architecture:** `RemoteButtonMapping` 继续提供当前功能，`RemoteButtonGuideView` 继续布局文字标签；`RemoteControlPhotoResource` 只负责从 bundle 单例加载图片，`RemoteControlIllustrationView` 只绘制图片、降级占位和折线，`XiaomiRemote2ProDiagramSpec` 只保存显示框与归一化热点。图片是编译期资源，运行时不联网。

**Tech Stack:** Swift 6 / AppKit / Core Graphics、zsh 回归脚本、TypeWhale 统一本地构建脚本。

## Global Constraints

- 基线为 TypeWhale Pro 2.0.58 (Build 910) / `3ddf882e`；设计提交为 `fc0a880`。
- 图片源提交固定为 `HD838A/remote-mic-app@2fa4067ebfe68b874683341efc62555a0b650a6a`，SHA-256 固定为 `658d9333853958c13ff721eb76e1a6816c1dbea16006a84e8577ad410812549f`。
- 只修改静态资源、Presentation 图片/几何、对应测试、版本和现行维护文档。
- 不修改蓝牙、HID、ATVV、Fn/F5、电脑麦克风、ASR、录音收尾、粘贴、权限、动作执行或持久化语义。
- `RemoteButtonMapping` 继续是当前功能唯一真源；语音键固定，其他 12 键可编辑范围不变。
- 运行时禁止联网取图；资源缺失必须有不崩溃的有界占位。
- 代码改动后必须使用 `./native/build_and_log.sh` 生成唯一 build、覆盖安装、验签、启动和提交。
- 不 stage 或提交现存 `.artifacts/`、`.claude/`、`.superpowers/`、`docs/stories/`、`docs/talks/` 用户内容。

---

## File Structure

- Create `native/Resources/Remote/RC003-remote-photo.png`: 原始授权图片字节。
- Create `native/Sources/Presentation/Remote/RemoteControlPhotoResource.swift`: bundle 名称、预期像素/摘要元数据和单例 `NSImage` 加载。
- Modify `native/Sources/Presentation/Remote/RemoteControlIllustrationView.swift`: 删除自绘机身/按钮/SF Symbols，改为图片、占位和折线。
- Modify `native/Sources/Presentation/Remote/XiaomiRemote2ProDiagramSpec.swift`: 真实图片显示框、热点、左右顺序和折线入口。
- Modify `native/Tests/RemoteButtonGuideSpecCheck.swift`: 锁定真实布局、图片规格和 13 键覆盖。
- Modify `native/Tests/TypeWhaleRemoteButtonGuideFeatureCheck.sh`: 校验资源摘要、Presentation 边界和构建脚本资源路径。
- Modify `native/Tests/TypeWhaleRemoteButtonGuideSnapshotCheck.sh`: 将图片资源 loader 加入快照编译，并传入测试 bundle fallback。
- Modify `native/Tests/RemoteButtonGuideSnapshotCheck.swift`: 验证原图模式和缺图占位的四态生产组件截图。
- Modify `THIRD_PARTY_NOTICES.md`: 记录图片来源、提交、摘要和所有者授权确认。
- Modify `docs/current/DESIGN.md`, `docs/current/DEVELOPMENT_LOG.md`, `docs/current/RELEASE_QA.md`, `docs/current/README.md`: 更新现行体验与证据。
- Modify `native/Sources/Presentation/VersionHistory/VersionHistoryViewController.swift`, `native/build_native_app.sh`: 写入下一个 build 的用户可见说明与版本号。

---

### Task 1: 锁定原图资源与架构边界

**Files:**
- Modify: `native/Tests/TypeWhaleRemoteButtonGuideFeatureCheck.sh`
- Modify: `native/Tests/RemoteButtonGuideSpecCheck.swift`
- Create: `native/Resources/Remote/RC003-remote-photo.png`
- Create: `native/Sources/Presentation/Remote/RemoteControlPhotoResource.swift`
- Modify: `THIRD_PARTY_NOTICES.md`

**Interfaces:**
- Consumes: source asset at `/tmp/typewhale-remote-source.7A8RPl/remote-mic-app/Resources/RC003-remote-photo.png`.
- Produces: `enum RemoteControlPhotoResource` with `static let resourceName = "RC003-remote-photo"`, `static let expectedPixelSize = CGSize(width: 1024, height: 1536)`, `static let image: NSImage?`, and `static func load(bundle: Bundle = .main) -> NSImage?`.

- [ ] **Step 1: Write the failing resource and boundary checks**

Add exact checks to `TypeWhaleRemoteButtonGuideFeatureCheck.sh`:

```zsh
PHOTO="$ROOT/native/Resources/Remote/RC003-remote-photo.png"
[[ -f "$PHOTO" ]] || { print -u2 "Missing bundled RC003 photo"; exit 1; }
[[ "$(shasum -a 256 "$PHOTO" | awk '{print $1}')" == "658d9333853958c13ff721eb76e1a6816c1dbea16006a84e8577ad410812549f" ]]
grep -Fq 'RemoteControlPhotoResource.swift' "$ROOT/native/Tests/TypeWhaleRemoteButtonGuideSnapshotCheck.sh"
grep -Fq 'RC003-remote-photo.png' "$ROOT/native/build_native_app.sh" || test -d "$ROOT/native/Resources"
if rg -n 'IOHID|UserDefaults|RemoteBluetooth|SpeechInputCoordinator|https?://' "$REMOTE_DIR/RemoteControlPhotoResource.swift" "$REMOTE_DIR/RemoteControlIllustrationView.swift"; then
  print -u2 "Remote photo presentation must not own runtime or network behavior"
  exit 1
fi
```

Extend `required_files` with `RemoteControlPhotoResource.swift` and replace the old third-party-visual rejection with the local-only boundary above.

- [ ] **Step 2: Run the check and verify RED**

Run: `./native/Tests/TypeWhaleRemoteButtonGuideFeatureCheck.sh`

Expected: FAIL with `Missing focused Remote presentation file: RemoteControlPhotoResource.swift` or `Missing bundled RC003 photo`.

- [ ] **Step 3: Add the exact image and loader**

Use `apply_patch` for source/text files and copy the already-inspected binary without transformation:

```zsh
mkdir -p native/Resources/Remote
cp /tmp/typewhale-remote-source.7A8RPl/remote-mic-app/Resources/RC003-remote-photo.png native/Resources/Remote/RC003-remote-photo.png
```

Create the loader:

```swift
import AppKit

enum RemoteControlPhotoResource {
    static let resourceName = "RC003-remote-photo"
    static let resourceExtension = "png"
    static let expectedPixelSize = CGSize(width: 1024, height: 1536)

    static let image: NSImage? = load()

    static func load(bundle: Bundle = .main) -> NSImage? {
        let nested = bundle.url(
            forResource: resourceName,
            withExtension: resourceExtension,
            subdirectory: "Remote"
        )
        let flat = bundle.url(forResource: resourceName, withExtension: resourceExtension)
        guard let url = nested ?? flat else { return nil }
        return NSImage(contentsOf: url)
    }
}
```

Append a `RC003 product photo` section to `THIRD_PARTY_NOTICES.md` with source URL, exact commit, SHA-256, bundled location, owner authorization statement and public-distribution recheck condition.

- [ ] **Step 4: Verify byte identity and focused compile inputs**

Run:

```bash
shasum -a 256 native/Resources/Remote/RC003-remote-photo.png
sips -g pixelWidth -g pixelHeight native/Resources/Remote/RC003-remote-photo.png
```

Expected: digest `658d...549f`; width `1024`; height `1536`.

- [ ] **Step 5: Commit the resource boundary**

```bash
git add native/Resources/Remote/RC003-remote-photo.png native/Sources/Presentation/Remote/RemoteControlPhotoResource.swift native/Tests/TypeWhaleRemoteButtonGuideFeatureCheck.sh THIRD_PARTY_NOTICES.md
git commit -m "feat: bundle authorized RC003 product photo"
```

---

### Task 2: Replace the vector device with the photo and correct hotspots

**Files:**
- Modify: `native/Sources/Presentation/Remote/RemoteControlIllustrationView.swift`
- Modify: `native/Sources/Presentation/Remote/XiaomiRemote2ProDiagramSpec.swift`
- Modify: `native/Tests/RemoteButtonGuideSpecCheck.swift`
- Modify: `native/Tests/TypeWhaleRemoteButtonGuideSnapshotCheck.sh`
- Modify: `native/Tests/RemoteButtonGuideSnapshotCheck.swift`

**Interfaces:**
- Consumes: `RemoteControlPhotoResource.image` and `XiaomiRemote2ProDiagramSpec.items`.
- Produces: `XiaomiRemote2ProDiagramSpec.photoRect(in:) -> CGRect`, `sourceCropRect` normalized to the 1024×1536 asset, corrected `RemoteButtonDiagramItem.anchor`, and `RemoteControlIllustrationView.imageProvider: () -> NSImage?` test seam.

- [ ] **Step 1: Write failing layout assertions**

In `RemoteButtonGuideSpecCheck.swift`, assert physical ordering and relative positions:

```swift
precondition(left.map(\.button) == [.power, .dpadUp, .dpadLeft, .back, .home, .menu])
precondition(right.map(\.button) == [.voice, .dpadRight, .center, .dpadDown, .volumeUp, .volumeDown, .tv])
precondition(anchor(.power).x < anchor(.voice).x)
precondition(anchor(.back).y < anchor(.home).y)
precondition(anchor(.home).y < anchor(.menu).y)
precondition(anchor(.volumeUp).x > anchor(.back).x)
precondition(anchor(.volumeUp).y < anchor(.volumeDown).y)
precondition(anchor(.menu).x < anchor(.tv).x)
```

Add a helper inside the test:

```swift
func anchor(_ button: RemoteButton) -> CGPoint {
    items.first { $0.button == button }!.anchor
}
```

- [ ] **Step 2: Run the spec check and verify RED**

Run: `./native/Tests/TypeWhaleRemoteButtonGuideFeatureCheck.sh`

Expected: FAIL because the Build 910 ordering places volume left and home/menu right, which contradicts the real photo.

- [ ] **Step 3: Update the pure geometry spec**

Keep `remoteWidth = 156`, `remoteHeight = 440`, and `bodyRect(in:)`. Rename the body meaning to photo display geometry in comments, move left/right lists to the real layout, and set normalized anchors by the image crop:

```swift
.power     CGPoint(x: 0.30, y: 0.073)
.voice     CGPoint(x: 0.70, y: 0.073)
.dpadUp    CGPoint(x: 0.50, y: 0.155)
.dpadLeft  CGPoint(x: 0.30, y: 0.235)
.center    CGPoint(x: 0.50, y: 0.235)
.dpadRight CGPoint(x: 0.70, y: 0.235)
.dpadDown  CGPoint(x: 0.50, y: 0.315)
.back      CGPoint(x: 0.34, y: 0.405)
.volumeUp  CGPoint(x: 0.69, y: 0.405)
.volumeDown CGPoint(x: 0.69, y: 0.525)
.home      CGPoint(x: 0.34, y: 0.515)
.menu      CGPoint(x: 0.34, y: 0.625)
.tv        CGPoint(x: 0.69, y: 0.625)
```

Tune only after deterministic snapshot inspection; update the spec values, never patch pixels in screenshot output.

- [ ] **Step 4: Replace custom drawing with image/placeholder drawing**

`RemoteControlIllustrationView.draw(_:)` becomes:

```swift
override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    let photoRect = XiaomiRemote2ProDiagramSpec.bodyRect(in: bounds)
    if let image = imageProvider() {
        drawPhoto(image, in: photoRect)
    } else {
        drawMissingPhotoPlaceholder(in: photoRect)
    }
    drawConnectors(in: photoRect)
}
```

The initializer defaults to `imageProvider = { RemoteControlPhotoResource.image }`. `drawPhoto` clips to a 24pt rounded rect and uses `.sourceOver` with full fraction. Remove `drawBody`, `drawControls`, `drawRoundButton`, symbol tinting and control colors so no TypeWhale-generated icon remains. The placeholder draws a neutral rounded rectangle plus centered `遥控器图片不可用`.

- [ ] **Step 5: Extend deterministic snapshot coverage**

Add `RemoteControlPhotoResource.swift` to the snapshot compile command. In the snapshot executable, instantiate one production guide using the real file-loaded image and one illustration with `{ nil }` to render `missing-photo.png`; keep dark/light × regular/compact snapshots and verify PNG dimensions/existence.

- [ ] **Step 6: Run focused tests and inspect images**

Run:

```bash
./native/Tests/TypeWhaleRemoteButtonGuideFeatureCheck.sh
open "$(find "${TMPDIR:-/tmp}" -path '*typewhale-remote-guide*' -name '*.png' | head -1)"
```

Expected: `RemoteButtonGuideSpecCheck passed`, snapshot check passed, photo unwarped, 13 lines land on intended areas, no line crosses a neighboring button.

- [ ] **Step 7: Commit the display replacement**

```bash
git add native/Sources/Presentation/Remote/RemoteControlIllustrationView.swift native/Sources/Presentation/Remote/XiaomiRemote2ProDiagramSpec.swift native/Tests/RemoteButtonGuideSpecCheck.swift native/Tests/TypeWhaleRemoteButtonGuideSnapshotCheck.sh native/Tests/RemoteButtonGuideSnapshotCheck.swift
git commit -m "fix: align remote guide with RC003 photo"
```

---

### Task 3: Run protected regressions and produce the unique installed build

**Files:**
- Modify: `native/Sources/Presentation/VersionHistory/VersionHistoryViewController.swift`
- Modify: `docs/current/DESIGN.md`
- Modify: `docs/current/DEVELOPMENT_LOG.md`
- Modify: `docs/current/RELEASE_QA.md`
- Modify: `docs/current/README.md`
- Modify automatically: `native/build_native_app.sh`, `docs/构建日志.md`

**Interfaces:**
- Consumes: Tasks 1–2 green source and snapshots.
- Produces: TypeWhale Pro 2.0.58 Build 911 installed at `/Applications/TypeWhale Pro.app`, signed and running, plus current documentation.

- [ ] **Step 1: Recheck concurrency and source ownership**

Run:

```bash
git branch --show-current
git status --short
pgrep -fal '[b]uild_and_log\.sh|[r]elease_local_build\.sh|[b]uild_native_app\.sh|[s]wiftc|[x]codebuild' || true
```

Expected: branch `codex/typewhale-pro-asr-hotwords`; only this task's tracked edits plus the known protected untracked paths; no other build.

- [ ] **Step 2: Run focused and protected regressions**

Run each and require exit 0:

```bash
./native/Tests/TypeWhaleRemoteButtonGuideFeatureCheck.sh
./native/Tests/TypeWhaleRemoteFeatureCheck.sh
./native/Tests/TypeWhaleRecordingFinalizationFeatureCheck.sh
./native/Tests/TypeWhaleInputGestureFeatureCheck.sh
./native/Tests/TypeWhaleRemoteHIDIsolationFeatureCheck.sh
git diff --check
```

- [ ] **Step 3: Update user-visible build history and current docs**

Prepend Build 911 with exactly these behavior boundaries:

```swift
VersionEntry(
    version: "版本 2.0.58 (Build 911)",
    date: "2026-09-13",
    changes: [
        "遥控器页改用准确的 RC003 原图，电源、语音、方向、返回、主页、菜单、音量和电视图标与真实设备一致。",
        "十三个按键标注和折线已按原图物理位置重新校准，修改或恢复映射后仍会即时显示当前功能。",
        "原图离线内置且具有缺图降级；蓝牙、Fn／F5、电脑麦克风、语音输入和录音收尾逻辑保持不变。"
    ]
)
```

In current docs, replace the old “原创矢量/不使用图片” current-state claim with the authorized-photo rule, while preserving Build 910 as historical evidence.

- [ ] **Step 4: Build, install, sign and launch**

Run: `./native/build_and_log.sh`

Expected: script increments 910 → 911, builds current source, installs `/Applications/TypeWhale Pro.app`, `codesign --verify --deep --strict` passes, app launches, and build log records 911.

- [ ] **Step 5: Verify bundle resource and runtime**

Run:

```bash
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' '/Applications/TypeWhale Pro.app/Contents/Info.plist'
/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' '/Applications/TypeWhale Pro.app/Contents/Info.plist'
shasum -a 256 '/Applications/TypeWhale Pro.app/Contents/Resources/Remote/RC003-remote-photo.png'
codesign --verify --deep --strict '/Applications/TypeWhale Pro.app'
pgrep -fal '/Applications/TypeWhale Pro.app/Contents/MacOS/TypeWhalePro'
./native/Tests/TypeWhaleInputGestureRuntimeCheck.sh
```

Expected: `2.0.58`, `911`, digest `658d...549f`, successful signature, running process, runtime check passed.

- [ ] **Step 6: Capture installed visual evidence**

Open the installed app, select `遥控器`, scroll to the bottom, and capture dark/light screenshots. Verify normal width and a constrained width. Record whether physical RC003 pressing was possible; do not convert a component screenshot into physical-device evidence.

- [ ] **Step 7: Commit the build and documentation**

```bash
git add native/Sources/Presentation/VersionHistory/VersionHistoryViewController.swift native/build_native_app.sh docs/构建日志.md docs/current/README.md docs/current/DESIGN.md docs/current/DEVELOPMENT_LOG.md docs/current/RELEASE_QA.md
git commit -m "build: install RC003 photo guide build 911"
```

---

### Task 4: AWF delivery evidence and final audit

**Files:**
- Modify outside TypeSpeaker: `docs/projects/typewhale-remote-photo-guide/PROJECT_PLAN.md`
- Create outside TypeSpeaker: `docs/projects/typewhale-remote-photo-guide/ACCEPTANCE.md`
- Generated outside TypeSpeaker: `registry/tasks/task_feecb57c7e27eee23c0774cf/*.json`

**Interfaces:**
- Consumes: committed TypeSpeaker Build 911 and all Task 3 checks.
- Produces: AWF task runs, `deliver: ready`, PM local-delivery judgment and exact residual risk.

- [ ] **Step 1: Run all prepared AWF checks**

Run the five prepared checks exactly:

```bash
npm run factory -- task:run --id task_feecb57c7e27eee23c0774cf --preparation prep_db5d67b9-e14e-4bf7-b5c8-8fdb1b5bbb5b --check remote-photo-guide --json
npm run factory -- task:run --id task_feecb57c7e27eee23c0774cf --preparation prep_db5d67b9-e14e-4bf7-b5c8-8fdb1b5bbb5b --check remote-full-regression --json
npm run factory -- task:run --id task_feecb57c7e27eee23c0774cf --preparation prep_db5d67b9-e14e-4bf7-b5c8-8fdb1b5bbb5b --check recording-finalization-regression --json
npm run factory -- task:run --id task_feecb57c7e27eee23c0774cf --preparation prep_db5d67b9-e14e-4bf7-b5c8-8fdb1b5bbb5b --check typewhale-diff-check --json
npm run factory -- task:run --id task_feecb57c7e27eee23c0774cf --preparation prep_db5d67b9-e14e-4bf7-b5c8-8fdb1b5bbb5b --check installed-runtime --json
```

Names: `remote-photo-guide`, `remote-full-regression`, `recording-finalization-regression`, `typewhale-diff-check`, `installed-runtime`. Expected: every result status is passed.

- [ ] **Step 2: Check deliver gate**

Run:

```bash
npm run factory -- task:check --id task_feecb57c7e27eee23c0774cf --preparation prep_db5d67b9-e14e-4bf7-b5c8-8fdb1b5bbb5b --phase deliver --json
```

Expected: `status: ready`, no blockers.

- [ ] **Step 3: Record acceptance without overstating field evidence**

Write the planned/actual scope, asset source and digest, test/build/signature/runtime results, screenshot paths, rollback commit, authorization boundary, any unperformed physical RC003 test, and PM `Go for local delivery` or `No-Go`.

- [ ] **Step 4: Commit only owned AWF files**

```bash
git add docs/projects/typewhale-remote-photo-guide registry/tasks/task_feecb57c7e27eee23c0774cf
git diff --cached --check
git commit -m "docs: record TypeWhale remote photo guide delivery"
```
