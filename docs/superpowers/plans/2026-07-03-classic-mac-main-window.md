# Classic Mac Main Window Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace TypeWhale Pro's horizontally scrolling main settings surface with a stable Classic Mac inspired two-zone control panel while preserving existing speech, hotkey, model, permission, and settings behavior.

**Architecture:** Keep `MainViewController` as the integration point, but move layout state and inspector navigation into focused presentation helpers. Reuse existing controls and action wiring; the experiment changes hierarchy, surfaces, and row composition rather than domain logic.

**Tech Stack:** Swift, AppKit, existing TypeWhale native build scripts, shell guard tests.

## Global Constraints

- Worktree: `$HOME/Pictures/macOSwinOSCoding/TypeSpeaker-classic-mac-design-lab`
- Branch: `codex/typewhale-classic-mac-design-lab`
- Do not change ASR recognition behavior.
- Do not change paste, clipboard restore, screenshot, OCR, translation, or smart rewrite semantics.
- Do not add third-party fonts, bitmap assets, or unlicensed visual material.
- Preserve existing settings storage, actions, popovers, permissions, model install flow, hotkey capture flow, and recent transcription behavior.
- Replace the right-side horizontal panel scroller with a stable inspector area; do not reintroduce horizontally clipped panels.
- Current session and recent transcriptions must remain visible while changing settings.
- After code changes, run `./native/build_and_log.sh` to build, install, open, and log the installed app.

---

## File Structure

- Modify `native/Sources/Presentation/Main/MainViewController.swift`
  - Add inspector tab state and reduce assumptions tied to horizontal scrolling.
- Modify `native/Sources/Presentation/Main/MainViewController+PanelLayout.swift`
  - Replace horizontal scroller assembly with two-zone layout and inspector pages.
- Modify `native/Sources/Presentation/Main/MainViewController+Preferences.swift`
  - Route Preferences to the settings inspector tab instead of horizontal scroll.
- Modify `native/Sources/Presentation/Shared/UIComponents.swift`
  - Tune existing visual tokens; add no new helper unless two changed call sites use the same view construction.
- Create `native/Tests/MainWindowLayoutBoundaryCheck.sh`
  - Static guard that prevents the main surface from reintroducing horizontal panel scrolling.
- Modify `docs/开发日志.md`
  - Record the design experiment and verification.
- Modify `native/Sources/Presentation/VersionHistory/VersionHistoryViewController.swift`
  - Add the build history entry required before `build_and_log.sh` changes version/build.

---

### Task 1: Add Layout Boundary Guard

**Files:**
- Create: `native/Tests/MainWindowLayoutBoundaryCheck.sh`

**Interfaces:**
- Consumes: existing source files under `native/Sources/Presentation/Main`.
- Produces: a shell guard runnable by `native/Tests/MainWindowLayoutBoundaryCheck.sh`.

- [ ] **Step 1: Write the failing guard**

Create `native/Tests/MainWindowLayoutBoundaryCheck.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PANEL_LAYOUT="$ROOT/native/Sources/Presentation/Main/MainViewController+PanelLayout.swift"
PREFERENCES="$ROOT/native/Sources/Presentation/Main/MainViewController+Preferences.swift"

if grep -q "hasHorizontalScroller = true" "$PANEL_LAYOUT"; then
  echo "Main window settings must not use a horizontal panel scroller." >&2
  exit 1
fi

if grep -q "panelScrollView" "$PANEL_LAYOUT"; then
  echo "Main panel layout must not depend on panelScrollView." >&2
  exit 1
fi

if grep -q "scrollToConfigPanels" "$PREFERENCES"; then
  echo "Preferences must select a stable inspector tab, not scroll horizontally." >&2
  exit 1
fi

grep -q "buildInspectorTabs" "$PANEL_LAYOUT" || {
  echo "Main panel layout must expose stable inspector tabs." >&2
  exit 1
}

echo "MainWindowLayoutBoundaryCheck passed"
```

- [ ] **Step 2: Run guard to verify it fails**

Run: `native/Tests/MainWindowLayoutBoundaryCheck.sh`

Expected: FAIL with `Main window settings must not use a horizontal panel scroller.`

- [ ] **Step 3: Make the guard executable**

Run:

```bash
chmod +x native/Tests/MainWindowLayoutBoundaryCheck.sh
```

- [ ] **Step 4: Commit the red guard**

```bash
git add native/Tests/MainWindowLayoutBoundaryCheck.sh
git commit -m "test: guard main window inspector layout"
```

---

### Task 2: Replace Horizontal Scroller With Stable Inspector

**Files:**
- Modify: `native/Sources/Presentation/Main/MainViewController.swift`
- Modify: `native/Sources/Presentation/Main/MainViewController+PanelLayout.swift`
- Modify: `native/Sources/Presentation/Main/MainViewController+Preferences.swift`

**Interfaces:**
- Consumes: existing `buildSessionAndRecentContent()`, `buildPreviewThemeContent()`, `buildComboQuickSmartContent()`, `buildHotkeysPanelContent()`, `buildMiscSettingsContent()`, `buildStatusPanelContent()`, and `wireHotkeyButtons()`.
- Produces: `buildInspectorTabs() -> NSView`, `selectInspectorTab(_:)`, and a `MainInspectorTab` enum.

- [ ] **Step 1: Add inspector tab state**

In `MainViewController.swift`, add this enum and property near `HotkeySlot`:

```swift
enum MainInspectorTab: CaseIterable {
    case common
    case intelligence
    case hotkeys
    case status

    var title: String {
        switch self {
        case .common: return "常用"
        case .intelligence: return "智能"
        case .hotkeys: return "快捷键"
        case .status: return "状态"
        }
    }
}

var selectedInspectorTab: MainInspectorTab = .common
var inspectorTabButtons: [MainInspectorTab: NSButton] = [:]
let inspectorContent = NSView()
```

Remove the stored `panelScrollView` property if it is no longer referenced after the layout rewrite.

- [ ] **Step 2: Rewrite `buildMainSurface()`**

In `MainViewController+PanelLayout.swift`, replace the current `buildMainSurface()` implementation with a two-zone layout:

```swift
func buildMainSurface() -> NSView {
    let container = NSView()
    container.translatesAutoresizingMaskIntoConstraints = false

    let topBar = buildTopBar()
    container.addSubview(topBar)

    wireHotkeyButtons()

    let session = panel("当前会话", width: 300, fillsHeight: true, buildSessionAndRecentContent())
    let inspector = panel("控制面板", width: 620, fillsHeight: true, buildInspectorTabs())
    container.addSubview(session)
    container.addSubview(inspector)

    NSLayoutConstraint.activate([
        topBar.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 18),
        topBar.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -18),
        topBar.topAnchor.constraint(equalTo: container.topAnchor, constant: 14),
        topBar.heightAnchor.constraint(equalToConstant: 38),

        session.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 18),
        session.topAnchor.constraint(equalTo: topBar.bottomAnchor, constant: 12),
        session.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16),

        inspector.leadingAnchor.constraint(equalTo: session.trailingAnchor, constant: 14),
        inspector.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -18),
        inspector.topAnchor.constraint(equalTo: topBar.bottomAnchor, constant: 12),
        inspector.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16),
    ])

    return container
}
```

- [ ] **Step 3: Add inspector tab builders**

In `MainViewController+PanelLayout.swift`, add:

```swift
func buildInspectorTabs() -> NSView {
    inspectorContent.translatesAutoresizingMaskIntoConstraints = false
    inspectorContent.wantsLayer = true
    inspectorContent.layer?.backgroundColor = NSColor(calibratedWhite: 0, alpha: 0.10).cgColor
    inspectorContent.layer?.borderWidth = 1
    inspectorContent.layer?.borderColor = UITheme.cardBorder.cgColor
    inspectorContent.layer?.cornerRadius = 8

    let tabs = MainInspectorTab.allCases.map { tab -> NSButton in
        let button = NSButton(title: tab.title, target: self, action: #selector(handleInspectorTab(_:)))
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.font = .systemFont(ofSize: 12, weight: .semibold)
        button.tag = MainInspectorTab.allCases.firstIndex(of: tab) ?? 0
        button.setAccessibilityLabel("\(tab.title)设置")
        inspectorTabButtons[tab] = button
        return button
    }

    let tabRow = NSStackView(views: tabs)
    tabRow.orientation = .horizontal
    tabRow.alignment = .centerY
    tabRow.spacing = 6
    tabRow.translatesAutoresizingMaskIntoConstraints = false

    let stack = NSStackView(views: [tabRow, inspectorContent])
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 10
    stack.translatesAutoresizingMaskIntoConstraints = false
    tabRow.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    inspectorContent.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    inspectorContent.setContentHuggingPriority(.defaultLow, for: .vertical)

    selectInspectorTab(.common)
    return stack
}

@objc func handleInspectorTab(_ sender: NSButton) {
    let tabs = MainInspectorTab.allCases
    guard sender.tag >= 0, sender.tag < tabs.count else { return }
    selectInspectorTab(tabs[sender.tag])
}

func selectInspectorTab(_ tab: MainInspectorTab) {
    selectedInspectorTab = tab
    inspectorTabButtons.forEach { key, button in
        button.state = key == tab ? .on : .off
        button.contentTintColor = key == tab ? UITheme.brandYellow : .secondaryLabelColor
    }
    inspectorContent.subviews.forEach { $0.removeFromSuperview() }
    let page = buildInspectorPage(tab)
    page.translatesAutoresizingMaskIntoConstraints = false
    inspectorContent.addSubview(page)
    NSLayoutConstraint.activate([
        page.leadingAnchor.constraint(equalTo: inspectorContent.leadingAnchor, constant: 14),
        page.trailingAnchor.constraint(equalTo: inspectorContent.trailingAnchor, constant: -14),
        page.topAnchor.constraint(equalTo: inspectorContent.topAnchor, constant: 14),
        page.bottomAnchor.constraint(lessThanOrEqualTo: inspectorContent.bottomAnchor, constant: -14),
    ])
}

func buildInspectorPage(_ tab: MainInspectorTab) -> NSView {
    switch tab {
    case .common:
        return inspectorPage([
            inspectorGroup("预览主题", buildPreviewThemeContent()),
            inspectorGroup("快捷设置", buildQuickSettingsCardContent()),
            inspectorGroup("系统", buildMiscSettingsContent()),
        ])
    case .intelligence:
        return inspectorPage([
            inspectorGroup("智能整理", buildSmartRewritePanelContent()),
        ])
    case .hotkeys:
        return inspectorPage([
            inspectorGroup("快捷键", buildHotkeysPanelContent()),
        ])
    case .status:
        return inspectorPage([
            inspectorGroup("状态", buildStatusPanelContent()),
        ])
    }
}
```

- [ ] **Step 4: Add group/page helpers**

In `MainViewController+PanelLayout.swift`, add:

```swift
private func inspectorPage(_ groups: [NSView]) -> NSView {
    let stack = NSStackView(views: groups)
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 12
    stack.translatesAutoresizingMaskIntoConstraints = false
    groups.forEach { $0.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
    return stack
}

private func inspectorGroup(_ title: String, _ body: NSView) -> NSView {
    let header = label(title, size: 11, weight: .semibold)
    header.textColor = UITheme.sectionTitle
    let stack = NSStackView(views: [header, body])
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 7
    stack.translatesAutoresizingMaskIntoConstraints = false
    body.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    return roundedBox(stack, hPad: 12, vPad: 10)
}
```

- [ ] **Step 5: Replace preferences routing**

In `MainViewController+Preferences.swift`, change `openPreferences()` to:

```swift
@objc func openPreferences() {
    selectInspectorTab(.common)
}
```

Remove `scrollToConfigPanels()` from `MainViewController+PanelLayout.swift`.

- [ ] **Step 6: Run guard**

Run: `native/Tests/MainWindowLayoutBoundaryCheck.sh`

Expected: PASS with `MainWindowLayoutBoundaryCheck passed`.

- [ ] **Step 7: Run existing guard tests**

Run:

```bash
native/Tests/ReleaseVersionRuleCheck.sh
native/Tests/ScreenshotArchitectureBoundaryCheck.sh
native/Tests/SmartRewriteSystemPromptBoundaryCheck.sh
```

Expected: all pass.

- [ ] **Step 8: Commit**

```bash
git add native/Sources/Presentation/Main/MainViewController.swift native/Sources/Presentation/Main/MainViewController+PanelLayout.swift native/Sources/Presentation/Main/MainViewController+Preferences.swift
git commit -m "feat: stabilize main window inspector layout"
```

---

### Task 3: Tighten Classic Desktop Visual Hierarchy

**Files:**
- Modify: `native/Sources/Presentation/Shared/UIComponents.swift`
- Modify: `native/Sources/Presentation/Main/MainViewController+Layout.swift`
- Modify: `native/Sources/Presentation/Main/MainViewController+PanelLayout.swift`

**Interfaces:**
- Consumes: `UITheme`, `UILayout`, `roundedBox`, `listCard`, `BrandSwitch`, existing AppKit controls.
- Produces: clearer contrast, panel borders, row rhythm, and selected/pressed states without new assets.

- [ ] **Step 1: Strengthen shared visual tokens**

In `UIComponents.swift`, tune existing tokens:

```swift
static let cardFill = NSColor(calibratedWhite: 1, alpha: 0.075)
static let cardBorder = NSColor(calibratedWhite: 1, alpha: 0.20)
static let hairline = NSColor(calibratedWhite: 1, alpha: 0.14)
static let sectionTitle = NSColor(calibratedWhite: 1, alpha: 0.56)
static let keycapFill = NSColor(calibratedWhite: 1, alpha: 0.13)
static let keycapBorder = NSColor(calibratedWhite: 1, alpha: 0.24)
```

Change `UILayout.cornerRadius` to `8`.

- [ ] **Step 2: Make inspector surface read as a desktop panel**

In `buildInspectorTabs()`, set the tab row and content so the selected tab is obvious and the content area has a stable minimum height:

```swift
inspectorContent.heightAnchor.constraint(greaterThanOrEqualToConstant: 460).isActive = true
```

Keep `button.state` and `contentTintColor` updates in `selectInspectorTab(_:)`.

- [ ] **Step 3: Improve hotkey rows**

In `shortcutRow(...)`, set the title label width and use table-like spacing:

```swift
titleLabel.widthAnchor.constraint(equalToConstant: 96).isActive = true
captureButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 128).isActive = true
fallbackButton.widthAnchor.constraint(equalToConstant: 70).isActive = true
```

Expected behavior: long hotkey titles truncate inside the capture button, but command labels remain aligned.

- [ ] **Step 4: Run guard tests**

Run:

```bash
native/Tests/MainWindowLayoutBoundaryCheck.sh
native/Tests/ReleaseVersionRuleCheck.sh
native/Tests/ScreenshotArchitectureBoundaryCheck.sh
native/Tests/SmartRewriteSystemPromptBoundaryCheck.sh
```

Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add native/Sources/Presentation/Shared/UIComponents.swift native/Sources/Presentation/Main/MainViewController+Layout.swift native/Sources/Presentation/Main/MainViewController+PanelLayout.swift
git commit -m "style: tune classic desktop main window hierarchy"
```

---

### Task 4: Document, Build, Install, And Review

**Files:**
- Modify: `docs/开发日志.md`
- Modify: `native/Sources/Presentation/VersionHistory/VersionHistoryViewController.swift`
- Generated/modified by build scripts: version/build documentation and build log files as required by `./native/build_and_log.sh`

**Interfaces:**
- Consumes: completed UI implementation.
- Produces: installed `/Applications/TypeWhale.app`, build log, product/dev history entries, and verification notes.

- [ ] **Step 1: Inspect current version-history format**

Run:

```bash
rg -n "1\\.8\\.3|510|Version" native/Sources/Presentation/VersionHistory/VersionHistoryViewController.swift docs/开发日志.md README.md macos/README.md
```

Expected: locate the current top entry and document style.

- [ ] **Step 2: Add development log entry**

In `docs/开发日志.md`, add an entry for the Classic Mac main window design experiment with:

- worktree branch
- reason: horizontal panel scroller weakened hierarchy
- change: stable two-zone control panel and inspector tabs
- preserved behavior: ASR, paste, screenshots, translation, hotkeys, settings persistence
- verification plan: guard tests, build/install, visual review

- [ ] **Step 3: Add version history entry before build**

In `VersionHistoryViewController.swift`, add the new version/build entry required by `release_local_build.sh`. Use the version/build that the build script expects after its bump. If `./native/build_and_log.sh` refuses because another process bumped the build first, update the entry to the required version/build and rerun.

- [ ] **Step 4: Check build concurrency**

Run:

```bash
pgrep -fl "build_and_log|release_local_build|build_native_app|swiftc|xcodebuild" || true
git status --short
```

Expected: no active conflicting build. If a build is active, wait and re-check before building.

- [ ] **Step 5: Build, install, and open**

Run:

```bash
./native/build_and_log.sh
```

Expected: script completes, installs `/Applications/TypeWhale.app`, opens it, and appends `docs/构建日志.md`.

- [ ] **Step 6: Manual visual verification**

Verify installed app:

- current session and recent transcriptions are visible
- right inspector has stable tabs and no horizontal clipping
- `常用`, `智能`, `快捷键`, `状态` tabs switch without moving the left work zone
- preview theme click changes selected state
- hotkey capture start/cancel remains readable
- status model card and permission buttons remain clickable

- [ ] **Step 7: Design review**

Run a design quality review. If automated visual review is practical in this environment, use `design-review`; otherwise perform a manual screenshot review of the installed app and record limitations.

- [ ] **Step 8: Final guard tests**

Run:

```bash
native/Tests/MainWindowLayoutBoundaryCheck.sh
native/Tests/ReleaseVersionRuleCheck.sh
native/Tests/ScreenshotArchitectureBoundaryCheck.sh
native/Tests/SmartRewriteSystemPromptBoundaryCheck.sh
```

Expected: all pass.

- [ ] **Step 9: Commit documentation/build artifacts**

```bash
git add docs native README.md macos/README.md
git commit -m "docs: record classic mac main window experiment"
```
