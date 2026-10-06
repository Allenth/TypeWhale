# TypeWhale Remote Button Guide Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a deeply integrated Xiaomi Bluetooth Remote 2 Pro button guide and complete the existing button-mapping surface without regressing TypeWhale's voice, Fn, recording-finalization, or native system-key behavior.

**Architecture:** First turn the Remote vertical slice into focused Domain, Infrastructure, Application, and Presentation components while preserving behavior. Then render an original AppKit/Core Graphics remote diagram from a typed 13-button geometry specification and bind both the guide and mapping controls to the same `RemoteButtonMapping` snapshot. The GPLv3 upstream is evidence only; no upstream source, image, logo, or layout asset is copied into TypeWhale.

**Tech Stack:** Swift 6, AppKit, Core Graphics, IOHID/IOKit, Foundation/UserDefaults, shell feature checks, existing native build/install scripts.

## Global Constraints

- Production classification; no MVP, placeholder, temporary main path, or knowingly incomplete product behavior.
- Keep IOHID non-exclusive and preserve ordinary macOS behavior for directional, confirm, back, volume, TV, power, and other system keys.
- Preserve remote voice ownership timing: 120 ms HID/`AUDIO_START` association, 310-second held-key safety, and ATVV `AUDIO_STOP` as the only authoritative voice finalization event.
- Preserve computer Fn, computer microphone, remote microphone, existing recording finalization, and current upper-page section order and meaning.
- Keep persistence keys `typewhale.remote.enabled` and `typewhale.remote.button-mapping.v1`; old mappings missing new keys must fall back to defaults.
- Voice remains fixed to `pushToTalk`; the other twelve verified physical buttons use the existing action catalog only.
- No third-party image, logo, font, source code, runtime dependency, permission, network request, or sensitive device-address logging.
- Build 907 was reserved for the behavior-preserving architecture checkpoint but failed Swift actor-isolation compilation before producing an app; Build 908 is the replacement architecture checkpoint and Build 909 is the visual feature checkpoint. Every produced build must use its own source state, installation, signature check, launch evidence, documentation, and commit.
- Only exact task files may be staged; preserve `.artifacts/`, `.claude/`, `.superpowers/`, `docs/stories/`, and `docs/talks/` as user-owned untracked state.

---

## File Structure

### Domain

- Modify `native/Sources/Domain/Remote/RemoteButtonMapping.swift`: stable button/action IDs, defaults, editability, mapping fallback only.

### Infrastructure

- Create `native/Sources/Infrastructure/Remote/XiaomiRemote2ProHIDProfile.swift`: RC003 VID/PID and verified HID usage-to-button facts.
- Create `native/Sources/Infrastructure/Remote/RemoteInputSettingsStore.swift`: injected `UserDefaults` persistence using the existing schema.
- Modify `native/Sources/Infrastructure/Remote/RemoteHIDEventReducer.swift`: keep only device-neutral edge reduction.
- Modify `native/Sources/Infrastructure/Remote/RemoteHIDMonitor.swift`: consume `XiaomiRemote2ProHIDProfile` and preserve voice suppression observation.

### Application

- Create `native/Sources/Application/RemoteButtonActionDispatcher.swift`: execute existing App-side actions only.
- Modify `native/Sources/Application/RemoteInputCoordinator.swift`: coordinate lifecycle and voice ownership, delegating persistence and action dispatch.

### Presentation

- Create `native/Sources/Presentation/Remote/RemoteButtonPresentation.swift`: pure Chinese button/action formatting and editable catalog selection.
- Create `native/Sources/Presentation/Remote/RemoteInspectorPresentation.swift`: connection/status formatting with no HID or persistence knowledge.
- Create `native/Sources/Presentation/Remote/RemoteInspectorSectionFactory.swift`: shared group and vertical-stack construction.
- Create `native/Sources/Presentation/Remote/RemoteConnectionOverviewView.swift`: hero and device status sections.
- Create `native/Sources/Presentation/Remote/RemoteVoicePipelineView.swift`: Bluetooth-to-TypeWhale pipeline section.
- Create `native/Sources/Presentation/Remote/RemoteButtonMappingView.swift`: voice invariant, twelve editable verified rows, reset callback.
- Create `native/Sources/Presentation/Remote/RemoteSupportView.swift`: permissions, privacy, usage, and recovery sections.
- Create `native/Sources/Presentation/Remote/XiaomiRemote2ProDiagramSpec.swift`: normalized 13-button geometry, side, order, and symbol semantics.
- Create `native/Sources/Presentation/Remote/RemoteControlIllustrationView.swift`: original remote body, buttons, symbols, and connector drawing only.
- Create `native/Sources/Presentation/Remote/RemoteButtonGuideView.swift`: native text labels, current action binding, adaptive layout, and accessibility.
- Create `native/Sources/Presentation/Remote/RemoteInspectorView.swift`: page assembly and snapshot fan-out only.
- Reduce `native/Sources/Presentation/Main/MainViewController+Remote.swift`: MainViewController callback wiring only.

### Tests and evidence

- Modify `native/Tests/RemoteButtonMappingCheck.swift`.
- Modify `native/Tests/RemoteHIDEventReducerCheck.swift`.
- Create `native/Tests/RemoteInputSettingsStoreCheck.swift`.
- Create `native/Tests/RemoteButtonActionDispatcherCheck.swift`.
- Create `native/Tests/RemoteButtonGuideSpecCheck.swift`.
- Create `native/Tests/TypeWhaleRemoteButtonGuideFeatureCheck.sh`.
- Modify `native/Tests/TypeWhaleRemoteFeatureCheck.sh` and `native/Tests/RemoteTabBoundaryCheck.sh`.
- Modify `docs/design/xiaomi-remote-tab/spec.json`.
- Update `docs/current/PRODUCT.md`, `docs/current/ARCHITECTURE.md`, `docs/current/DESIGN.md`, `docs/current/RELEASE_QA.md`, `docs/current/DEVELOPMENT_LOG.md`, `docs/current/README.md`, `native/Sources/Presentation/VersionHistory/VersionHistoryViewController.swift`, and build/log files changed by the approved build scripts.

---

### Task 1: Lock the 13-button hardware and mapping contract

**Files:**
- Create: `native/Sources/Infrastructure/Remote/XiaomiRemote2ProHIDProfile.swift`
- Modify: `native/Sources/Infrastructure/Remote/RemoteHIDEventReducer.swift`
- Modify: `native/Sources/Infrastructure/Remote/RemoteHIDMonitor.swift`
- Modify: `native/Tests/RemoteButtonMappingCheck.swift`
- Modify: `native/Tests/RemoteHIDEventReducerCheck.swift`
- Modify: `native/Tests/TypeWhaleRemoteFeatureCheck.sh`

**Interfaces:**
- Consumes: `RemoteButton`, `RemoteHIDUsage`, `RemoteHIDEventReducer.reduce(page:usage:value:buttons:)`.
- Produces: `XiaomiRemote2ProHIDProfile.vendorID: Int`, `productID: Int`, `buttons: [RemoteHIDUsage: RemoteButton]`, and `supportedButtons: Set<RemoteButton>`.

- [ ] **Step 1: Extend the mapping test before production changes**

Add checks that every `RemoteButton` has a default, voice is the only non-editable button, every non-voice button accepts all non-voice existing actions, and missing decoded keys use defaults:

```swift
for button in RemoteButton.allCases {
    _ = RemoteButtonMapping.defaults.action(for: button)
    precondition(RemoteButtonMapping.defaults.canEdit(button) == (button != .voice))
}

var allEdited = RemoteButtonMapping.defaults
for button in RemoteButton.allCases where button != .voice {
    allEdited.set(.send, for: button)
    precondition(allEdited.action(for: button) == .send)
}
```

- [ ] **Step 2: Make the HID test require the profile and menu usage**

Replace direct access to `RemoteHIDUsage.xiaomiRemote2ProButtons` with `XiaomiRemote2ProHIDProfile.buttons`, then require exact coverage and `0x65` for menu:

```swift
let map = XiaomiRemote2ProHIDProfile.buttons
precondition(map.count == RemoteButton.allCases.count)
precondition(Set(map.values) == Set(RemoteButton.allCases))
precondition(map[RemoteHIDUsage(page: 7, usage: 0x65)] == .menu)
precondition(XiaomiRemote2ProHIDProfile.supportedButtons == Set(RemoteButton.allCases))
```

- [ ] **Step 3: Run RED and verify the failure reason**

Run:

```bash
/bin/zsh native/Tests/TypeWhaleRemoteFeatureCheck.sh
```

Expected: compilation fails because `XiaomiRemote2ProHIDProfile` does not exist; no production code has changed.

- [ ] **Step 4: Add the isolated profile and make the reducer device-neutral**

Create the profile with the current twelve verified usages plus menu `0x65`:

```swift
import Foundation

enum XiaomiRemote2ProHIDProfile {
    static let vendorID = 0x2717
    static let productID = 0x32B8
    static let buttons: [RemoteHIDUsage: RemoteButton] = [
        .init(page: 7, usage: 0x66): .power,
        .init(page: 7, usage: 0x52): .dpadUp,
        .init(page: 7, usage: 0x50): .dpadLeft,
        .init(page: 7, usage: 0x28): .center,
        .init(page: 7, usage: 0x4F): .dpadRight,
        .init(page: 7, usage: 0x51): .dpadDown,
        .init(page: 7, usage: 0xF1): .back,
        .init(page: 7, usage: 0x80): .volumeUp,
        .init(page: 7, usage: 0x4A): .home,
        .init(page: 7, usage: 0x81): .volumeDown,
        .init(page: 7, usage: 0x65): .menu,
        .init(page: 7, usage: 0x35): .tv,
        .init(page: 7, usage: 0x3E): .voice,
    ]
    static let supportedButtons = Set(buttons.values)
}
```

Remove the device map from `RemoteHIDUsage`, update monitor matching and reducer input to consume the profile, and keep `page == 7 && usage == 0x3E` as the voice-suppression observation boundary.

- [ ] **Step 5: Include the profile in direct Swift checks and run GREEN**

Update the `swiftc` command in `TypeWhaleRemoteFeatureCheck.sh` to compile `XiaomiRemote2ProHIDProfile.swift` before the reducer, then run:

```bash
/bin/zsh native/Tests/TypeWhaleRemoteFeatureCheck.sh
```

Expected: all current Remote checks pass, including the new exact 13-button profile assertions.

---

### Task 2: Extract persistence and action dispatch from the coordinator

**Files:**
- Create: `native/Sources/Infrastructure/Remote/RemoteInputSettingsStore.swift`
- Create: `native/Sources/Application/RemoteButtonActionDispatcher.swift`
- Create: `native/Tests/RemoteInputSettingsStoreCheck.swift`
- Create: `native/Tests/RemoteButtonActionDispatcherCheck.swift`
- Modify: `native/Sources/Application/RemoteInputCoordinator.swift`
- Modify: `native/Tests/TypeWhaleRemoteFeatureCheck.sh`

**Interfaces:**
- Consumes: existing UserDefaults keys and `RemoteButtonAction`.
- Produces: `RemoteInputSettingsStore(defaults:)`, `loadEnabled()`, `saveEnabled(_:)`, `loadMappings()`, `saveMappings(_:)`; `RemoteButtonActionDispatcher.init(showMainWindow:send:cancelCurrentOperation:)` and `dispatch(_:)`.

- [ ] **Step 1: Write the store RED test**

Use a unique suite, assert the default enabled state is `true`, round-trip `false`, round-trip a changed mapping, decode a partial v1 mapping, and recover from corrupt JSON:

```swift
let suite = "TypeWhale.RemoteInputSettingsStoreCheck.\(UUID().uuidString)"
let defaults = UserDefaults(suiteName: suite)!
defer { defaults.removePersistentDomain(forName: suite) }
let store = RemoteInputSettingsStore(defaults: defaults)
precondition(store.loadEnabled())
store.saveEnabled(false)
precondition(!store.loadEnabled())
```

- [ ] **Step 2: Write the dispatcher RED test**

Count callback invocations and require one callback for `.send`, `.cancel`, and `.toggleMainWindow`, while `.pushToTalk`, `.none`, and `.system` produce none:

```swift
var sent = 0
var cancelled = 0
var shown = 0
let dispatcher = RemoteButtonActionDispatcher(
    showMainWindow: { shown += 1 },
    send: { sent += 1; return true },
    cancelCurrentOperation: { cancelled += 1 }
)
RemoteButtonAction.allCases.forEach(dispatcher.dispatch)
precondition(sent == 1 && cancelled == 1 && shown == 1)
```

- [ ] **Step 3: Run both RED compilations**

Run direct `xcrun swiftc` commands from `TypeWhaleRemoteFeatureCheck.sh`.

Expected: compilation fails separately for missing `RemoteInputSettingsStore` and missing `RemoteButtonActionDispatcher`.

- [ ] **Step 4: Implement the minimal store and dispatcher**

The store owns exactly the two existing keys and allows injected `UserDefaults`; the dispatcher owns exactly the three App callbacks:

```swift
struct RemoteButtonActionDispatcher {
    let showMainWindow: () -> Void
    let send: () -> Bool
    let cancelCurrentOperation: () -> Void

    func dispatch(_ action: RemoteButtonAction) {
        switch action {
        case .send: _ = send()
        case .cancel: cancelCurrentOperation()
        case .toggleMainWindow: showMainWindow()
        case .pushToTalk, .none, .system: break
        }
    }
}
```

- [ ] **Step 5: Inject both components into `RemoteInputCoordinator`**

Delete the file-private store, add defaulted initializer parameters, and replace the action switch with:

```swift
private let settingsStore: RemoteInputSettingsStore
private let actionDispatcher: RemoteButtonActionDispatcher

// In buttonDown handling, after the voice ownership observation:
actionDispatcher.dispatch(snapshot.mappings.action(for: button))
```

Do not change the `buttonUp(.voice)` call to `bluetooth.observeVoiceButton(isDown: false)` and do not make HID-up finalize speech.

- [ ] **Step 6: Run GREEN and the recording/Fn regression set**

Run:

```bash
/bin/zsh native/Tests/TypeWhaleRemoteFeatureCheck.sh
/bin/zsh native/Tests/TypeWhaleRecordingFinalizationFeatureCheck.sh
/bin/zsh native/Tests/TypeWhaleInputGestureFeatureCheck.sh
```

Expected: all scripts exit 0 with their `passed` messages.

---

### Task 3: Establish presentation contracts before splitting the UI

**Files:**
- Create: `native/Tests/RemoteButtonGuideSpecCheck.swift`
- Create: `native/Tests/TypeWhaleRemoteButtonGuideFeatureCheck.sh`
- Modify: `native/Tests/RemoteTabBoundaryCheck.sh`
- Modify: `native/Tests/TypeWhaleRemoteFeatureCheck.sh`

**Interfaces:**
- Consumes: `RemoteButton.allCases`, `RemoteButtonMapping`, future diagram and formatter types.
- Produces: an executable test contract for complete catalog coverage, readable action text, source-file boundaries, accessibility labels, native implementation, and no third-party assets.

- [ ] **Step 1: Write the diagram/formatter RED test**

Require thirteen unique entries, complete button coverage, six left labels, seven right labels, strict side ordering, and non-empty current-action text:

```swift
let items = XiaomiRemote2ProDiagramSpec.items
precondition(items.count == 13)
precondition(Set(items.map(\.button)) == Set(RemoteButton.allCases))
precondition(items.filter { $0.side == .left }.count == 6)
precondition(items.filter { $0.side == .right }.count == 7)
for button in RemoteButton.allCases {
    let text = RemoteInspectorPresentation.actionDetail(
        for: RemoteButtonMapping.defaults.action(for: button),
        button: button
    )
    precondition(!text.isEmpty)
}
```

- [ ] **Step 2: Write the architecture/UI boundary RED script**

`TypeWhaleRemoteButtonGuideFeatureCheck.sh` must require each focused Presentation file, require `设备与按键说明`, require all thirteen enum cases in the diagram spec, reject `NSImage(contentsOf:)`, remote URLs, Xiaomi logos, `WKWebView`, and `WebView`, and require `MainViewController+Remote.swift` to remain wiring-only and under 70 lines.

- [ ] **Step 3: Run RED**

Run:

```bash
/bin/zsh native/Tests/TypeWhaleRemoteButtonGuideFeatureCheck.sh
```

Expected: the script fails because the focused Presentation files and diagram spec do not exist.

---

### Task 4: Perform the behavior-preserving Presentation split (Build 908 checkpoint after failed Build 907)

**Files:**
- Create: `native/Sources/Presentation/Remote/RemoteButtonPresentation.swift`
- Create: `native/Sources/Presentation/Remote/RemoteInspectorPresentation.swift`
- Create: `native/Sources/Presentation/Remote/RemoteInspectorSectionFactory.swift`
- Create: `native/Sources/Presentation/Remote/RemoteConnectionOverviewView.swift`
- Create: `native/Sources/Presentation/Remote/RemoteVoicePipelineView.swift`
- Create: `native/Sources/Presentation/Remote/RemoteButtonMappingView.swift`
- Create: `native/Sources/Presentation/Remote/RemoteSupportView.swift`
- Create: `native/Sources/Presentation/Remote/RemoteInspectorView.swift`
- Modify: `native/Sources/Presentation/Main/MainViewController+Remote.swift`
- Modify: `native/Tests/RemoteTabBoundaryCheck.sh`
- Modify: `docs/current/ARCHITECTURE.md`
- Modify: `docs/current/DEVELOPMENT_LOG.md`
- Modify: `native/Sources/Presentation/VersionHistory/VersionHistoryViewController.swift`

**Interfaces:**
- Consumes: `RemoteInputSnapshot` and the four existing page callbacks.
- Produces: `RemoteInspectorView.apply(snapshot:)` with the same external interface; focused child views each expose only the callbacks/state they own.

- [ ] **Step 1: Implement the formatter and shared section factory**

Move `RemoteButton.displayName` and `RemoteButtonAction.displayName` presentation text into the pure `RemoteButtonPresentation`; keep status, permission, and pipeline strings in `RemoteInspectorPresentation`. The factory exposes:

```swift
enum RemoteInspectorSectionFactory {
    static func group(title: String, body: NSView, prominence: InspectorGroupProminence = .standard) -> NSView
    static func vertical(_ views: [NSView], spacing: CGFloat) -> NSStackView
}
```

- [ ] **Step 2: Extract the current six visible groups without visual changes**

Move hero/device, pipeline, mappings, and permission/help code into their named views. `RemoteButtonMappingView` temporarily preserves the current voice + center/back/home/menu rows for this checkpoint; feature expansion happens only after the replacement architecture checkpoint Build 908.

- [ ] **Step 3: Reduce the page container and MainVC extension**

`RemoteInspectorView` owns only children, stack order, callback forwarding, and snapshot fan-out. `MainViewController+Remote.swift` contains only `buildRemoteInspectorPage()` and `updateRemoteInputSnapshot(_:)`.

- [ ] **Step 4: Turn the refactor boundary checks GREEN**

Keep the guide feature check outside the aggregate until Task 5; run the behavior-preserving refactor checks:

```bash
/bin/zsh native/Tests/RemoteTabBoundaryCheck.sh
/bin/zsh native/Tests/TypeWhaleRemoteFeatureCheck.sh
/bin/zsh native/Tests/TypeWhaleRecordingFinalizationFeatureCheck.sh
/bin/zsh native/Tests/TypeWhaleInputGestureFeatureCheck.sh
```

Expected: all behavior and source-boundary checks pass; the guide spec RED test remains the only intentional failure and is not included in the aggregate until Task 5.

- [ ] **Step 5: Document the architecture checkpoint before building**

Record that Build 907 failed compiler isolation before producing an app, add a Build 908 version-history entry stating “internal Remote page layering; no button or voice behavior change,” and record G2 evidence in `docs/current/ARCHITECTURE.md` and `docs/current/DEVELOPMENT_LOG.md` without claiming visual completion.

- [ ] **Step 6: Recheck concurrency, build, install, sign, and launch Build 908**

Run the branch/status/process/mtime checks from `AGENTS.md`, then:

```bash
./native/build_and_log.sh
```

Expected: version stays `2.0.58`, build becomes `908`, `/Applications/TypeWhale Pro.app` is replaced and running, signature checks pass, and `docs/构建日志.md` receives one Build 908 row.

- [ ] **Step 7: Capture the installed upper-page checkpoint and commit exactly G2**

Open the installed Remote tab, capture a screenshot proving the original upper groups are present and readable, then stage only Task 1–4 files plus generated version/build logs and commit:

```bash
git commit -m "refactor: separate remote input responsibilities"
```

---

### Task 5: Add the complete mapping UI and 13-button device guide (Build 909 feature)

**Files:**
- Create: `native/Sources/Presentation/Remote/XiaomiRemote2ProDiagramSpec.swift`
- Create: `native/Sources/Presentation/Remote/RemoteControlIllustrationView.swift`
- Create: `native/Sources/Presentation/Remote/RemoteButtonGuideView.swift`
- Modify: `native/Sources/Presentation/Remote/RemoteButtonMappingView.swift`
- Modify: `native/Sources/Presentation/Remote/RemoteInspectorView.swift`
- Modify: `native/Sources/Presentation/Remote/RemoteButtonPresentation.swift`
- Modify: `native/Tests/RemoteButtonGuideSpecCheck.swift`
- Modify: `native/Tests/TypeWhaleRemoteButtonGuideFeatureCheck.sh`
- Modify: `native/Tests/RemoteTabBoundaryCheck.sh`
- Modify: `native/Tests/TypeWhaleRemoteFeatureCheck.sh`

**Interfaces:**
- Consumes: `RemoteInputSnapshot.mappings`, `RemoteButtonMapping.canEdit(_:)`, `RemoteInspectorPresentation`.
- Produces: `XiaomiRemote2ProDiagramSpec.items`, `RemoteButtonGuideView.apply(mapping:)`, and complete mapping callbacks for all twelve non-voice buttons.

- [ ] **Step 1: Run the existing guide RED test again**

Run:

```bash
/bin/zsh native/Tests/TypeWhaleRemoteButtonGuideFeatureCheck.sh
```

Expected: failure names the missing diagram/guide/illustration production types, proving the test guards the feature rather than the old UI.

- [ ] **Step 2: Implement the pure diagram specification**

Define:

```swift
enum RemoteCalloutSide { case left, right }

struct RemoteButtonDiagramItem: Equatable {
    let button: RemoteButton
    let side: RemoteCalloutSide
    let order: Int
    let anchor: CGPoint
    let calloutY: CGFloat
    let symbolName: String
}
```

Use normalized coordinates in a portrait remote body. To keep connector routes short and avoid crossing adjacent controls, left order is power, up, left, back, volumeUp, volumeDown; right order is voice, right, center, down, home, menu, TV. Every button appears exactly once.

- [ ] **Step 3: Implement action-specific label formatting**

`RemoteButtonPresentation.actionDetail(for:button:)` returns `按住说话`, `附加发送`, `附加取消当前操作`, `显示 / 隐藏主窗口`, `无附加操作`, or a button-specific system description such as `系统导航`, `系统确认`, `系统音量`, `系统电视功能`, or `系统电源功能`.

- [ ] **Step 4: Implement original vector drawing**

`RemoteControlIllustrationView.draw(_:)` draws the silver rounded body, dark physical controls, SF Symbols/geometric fallbacks, connector polylines, and endpoint dots. It receives immutable diagram items and geometry only; it does not read `UserDefaults`, snapshots, actions, or callbacks.

- [ ] **Step 5: Implement native guide labels and adaptive layout**

`RemoteButtonGuideView` creates thirteen label pairs once, updates the second line from `RemoteButtonMapping`, sets each container accessibility label to `按钮名称，当前功能`, and marks the drawing view non-accessible. At normal inspector width it positions six left and seven right labels beside a centered remote with non-crossing connectors; below the compact threshold it places the remote above two label columns and suppresses connectors that would collide.

- [ ] **Step 6: Expand the mapping editor to all verified non-voice buttons**

Use one catalog-derived collection instead of a hard-coded five-item list:

```swift
let editableButtons = RemoteButtonPresentation.editableButtons(
    supportedButtons: XiaomiRemote2ProHIDProfile.supportedButtons
)
```

Keep voice as a fixed row. Use two columns, preserve the current action list, keep “恢复默认,” and update both editor selections and guide labels from each new snapshot.

- [ ] **Step 7: Add the guide as the final Remote page group**

Append `设备与按键说明` after `使用与排障`, forward the same mapping snapshot to editor and guide, and do not reorder or reinterpret the six original groups.

- [ ] **Step 8: Run GREEN and aggregate regressions**

Run:

```bash
/bin/zsh native/Tests/TypeWhaleRemoteButtonGuideFeatureCheck.sh
/bin/zsh native/Tests/TypeWhaleRemoteFeatureCheck.sh
/bin/zsh native/Tests/TypeWhaleRecordingFinalizationFeatureCheck.sh
/bin/zsh native/Tests/TypeWhaleInputGestureFeatureCheck.sh
git diff --check
```

Expected: all commands exit 0; guide coverage is 13/13, profile coverage is 13/13, editable coverage is 12/12, voice stays fixed, and existing regression scripts remain green.

---

### Task 6: Document, visually review, and deliver Build 909 → Build 910

**Files:**
- Modify: `docs/design/xiaomi-remote-tab/spec.json`
- Modify: `docs/current/PRODUCT.md`
- Modify: `docs/current/ARCHITECTURE.md`
- Modify: `docs/current/DESIGN.md`
- Modify: `docs/current/RELEASE_QA.md`
- Modify: `docs/current/DEVELOPMENT_LOG.md`
- Modify: `docs/current/README.md`
- Modify: `native/Sources/Presentation/VersionHistory/VersionHistoryViewController.swift`
- Modify: `native/build_native_app.sh` and `docs/构建日志.md` only through `build_and_log.sh`.

**Interfaces:**
- Consumes: verified Task 5 behavior and installed-app screenshots.
- Produces: Build 909 feature evidence, final Build 910 visual-fix evidence, current documentation, AWF delivery readiness, and rollback-safe commits.

- [x] **Step 1: Update the UI specification and validate it**

Record the bottom placement, 13-button callout matrix, current-action synchronization, wide/compact layout, light/dark contrast, no external assets, and accessibility focus behavior in `spec.json`, then run:

```bash
/usr/bin/python3 $HOME/.codex/skills/ui-design-spec/scripts/validate_ui_spec.py docs/design/xiaomi-remote-tab/spec.json --final
```

Expected: validator exits 0.

- [x] **Step 2: Update current documents before the build**

Record the actual product behavior in PRODUCT, component ownership/data flow in ARCHITECTURE, layout/accessibility rules in DESIGN, installed validation matrix and rollback in RELEASE_QA, implementation evidence/known limits in DEVELOPMENT_LOG, and planned Build 909 in the application version history. Keep GPLv3 upstream described as research evidence only and state that TypeWhale ships an original vector rendering.

- [x] **Step 3: Recheck concurrency, then build and install Build 909**

Run the mandated branch/status/process/mtime checks, then:

```bash
./native/build_and_log.sh
```

Expected: version remains `2.0.58`, build becomes `909`, app is installed at `/Applications/TypeWhale Pro.app`, signature checks pass, app launches, and exactly one Build 909 row is appended.

- [x] **Step 4: Perform the required installed-app design-quality review**

Invoke the `design-review` skill against the installed Remote tab and verify hierarchy, spacing, line crossings, label truncation, button-to-callout accuracy, theme contrast, compact behavior, accessibility text, and upper-page regression. Fix findings with a RED test when behavior changes and produce a new uniquely numbered build; never overwrite Build 909 with different code.

Build 909 review found low-contrast dark symbols, endpoint overlays, a home/menu route crossing, and insufficient compact bottom spacing. Build 910 contains the verified fixes; production-component snapshots cover dark/light and regular/compact layouts.

- [ ] **Step 5: Capture real installed-app evidence**

In both dark and Morning Mist/light appearances, verify the Remote tab at the normal inspector width and a constrained window width. Capture the full bottom guide and the upper groups. Change at least home, menu, direction, volume, TV, and power mappings, confirm labels update immediately, restore defaults, disconnect/reconnect, and confirm no autocomplete popup appears when pressing the remote voice key in a normal text field.

Partial evidence: the installed Build 910 window/version, four production-component guide states, two mapping states, and six representative mapping callback/synchronization/reset paths are verified. macOS lock screen blocked real Remote-tab navigation, disconnect/reconnect, and physical RC003 presses; these remain explicit field checks.

- [x] **Step 6: Run the full delivery command set fresh**

Run:

```bash
/bin/zsh native/Tests/TypeWhaleRemoteButtonGuideFeatureCheck.sh
/bin/zsh native/Tests/TypeWhaleRemoteFeatureCheck.sh
/bin/zsh native/Tests/TypeWhaleRecordingFinalizationFeatureCheck.sh
/bin/zsh native/Tests/TypeWhaleInputGestureFeatureCheck.sh
git diff --check
codesign --verify --deep --strict '/Applications/TypeWhale Pro.app'
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' '/Applications/TypeWhale Pro.app/Contents/Info.plist'
/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' '/Applications/TypeWhale Pro.app/Contents/Info.plist'
pgrep -fl 'TypeWhale Pro'
```

Expected: all tests and signature verification exit 0, installed version is `2.0.58`, installed build is `910`, and a TypeWhale Pro process is listed.

- [x] **Step 7: Commit exact feature and visual-fix scopes**

Review `git status --short` and `git diff --stat`, stage only this plan's source, tests, current docs, UI spec, version history, build version field, and generated build log, then commit:

```bash
git commit -m "feat: add complete remote button guide"
git commit -m "style(design): FINDING-001 — improve remote symbol contrast"
git commit -m "style(design): FINDING-002 — clarify remote connector routes"
```

- [x] **Step 8: Run AWF delivery gates**

From the AutoWebFactory workspace, run the prepared task checks using task `task_b38e01187066d0fe778e562c` and preparation `prep_66aab1d8-9b11-46be-b2de-794d263cfe17`, then run `task:check --phase deliver --json`.

Expected: all registered checks have inspectable receipts and deliver phase returns `ready`; otherwise report the exact remaining gate without claiming completion.

Completed with five passing run receipts (`run_44d62dde-0bc3-46e7-964b-e2f3018a0f83`, `run_42c4d355-b15f-45f9-83ce-36210c5699a9`, `run_7bc038af-e9db-436c-9073-784df3e6eca5`, `run_2cdc3755-fe41-447a-bd6a-0a2b9b7bbda1`, `run_a32f6665-2abf-4db2-9e7f-97aca56068bd`). Deliver status is `ready` with no blockers and source digest `83f628990e97cba0dcd94cd9e3b2090f4d5f45dc8b6c11f5ad1adcac26c6a5ec`.
