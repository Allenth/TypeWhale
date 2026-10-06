# ASR Model Flow Layout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the common-page ASR model selector's horizontal scrolling strip with a natural-width, width-aware wrapping layout that keeps every model visible.

**Architecture:** Add a small pure layout calculator that turns available width and button widths into row frames and total height. `ASRBackendSegmentedSelector` remains the selection/control boundary, but owns buttons directly, applies the calculated frames, and exposes a width-dependent intrinsic height to AppKit; the common-page stack no longer forces a 40-point selector height.

**Tech Stack:** Swift 5, AppKit, Auto Layout, shell boundary checks, standalone Swift regression checks, native TypeWhale build scripts.

## Global Constraints

- Preserve `ASRBackend.allCases` ordering, selection, disabled state, tooltip, accessibility label, switching progress, failure rollback, and next-recording semantics.
- Do not modify ASR discovery, validation, runtimes, hotword formats, backend capabilities, or model-detail pages.
- Do not introduce horizontal or vertical scrolling.
- Buttons keep natural title widths and wrap as complete units when the remaining row width is insufficient.
- Build and verify the installed app at `/Applications/TypeWhale Pro.app` after source changes.

---

### Task 1: Pure wrapping layout calculator

**Files:**
- Create: `native/Sources/Presentation/Main/ASRButtonFlowLayout.swift`
- Create: `native/Tests/ASRButtonFlowLayoutCheck.swift`

**Interfaces:**
- Consumes: available container width and an ordered `[CGFloat]` of button widths.
- Produces: `ASRButtonFlowLayout.Result`, containing ordered `[CGRect]` frames and total `height`.

- [ ] **Step 1: Write the failing regression check**

Create a standalone Swift check which asserts that widths `[120, 180, 130]` use two rows in a 320-point container, preserve order, never overlap, and fit in the container; also assert that a wider container puts all three items on one row.

- [ ] **Step 2: Run the check and confirm the red state**

Run:

```bash
mkdir -p /tmp/typewhale-tests
swiftc native/Sources/Presentation/Main/ASRButtonFlowLayout.swift native/Tests/ASRButtonFlowLayoutCheck.swift -o /tmp/typewhale-tests/asr-button-flow-layout-check
```

Expected: compilation fails because `ASRButtonFlowLayout.swift` does not exist.

- [ ] **Step 3: Implement the minimal layout calculator**

Implement `ASRButtonFlowLayout` with constants `horizontalSpacing = 6`, `verticalSpacing = 6`, `rowHeight = 28`, and `insets = NSEdgeInsets(top: 2, left: 2, bottom: 2, right: 2)`. Its `layout(containerWidth:itemWidths:)` method must place items left-to-right, wrap before an item that would exceed the right inset, clamp a single oversized item to available width, and return the final content height.

- [ ] **Step 4: Run the standalone check**

Run:

```bash
swiftc native/Sources/Presentation/Main/ASRButtonFlowLayout.swift native/Tests/ASRButtonFlowLayoutCheck.swift -o /tmp/typewhale-tests/asr-button-flow-layout-check
/tmp/typewhale-tests/asr-button-flow-layout-check
```

Expected: `ASRButtonFlowLayoutCheck passed`.

### Task 2: Replace scroll selector with adaptive flow control

**Files:**
- Modify: `native/Sources/Presentation/Main/ASRBackendSegmentedSelector.swift`
- Modify: `native/Sources/Presentation/Main/MainViewController+Layout.swift`
- Modify: `native/Sources/Presentation/Main/MainViewController+Configuration.swift`
- Modify: `native/Tests/ExpandedASRBackendUIBoundaryCheck.sh`
- Modify: `native/Tests/CommonASRSwitchProgressCheck.sh`

**Interfaces:**
- Consumes: `ASRButtonFlowLayout.layout(containerWidth:itemWidths:)` and the existing `[ASRBackendSegmentedSelector.Item]`.
- Produces: the unchanged `selectedTag`, `select(tag:)`, target/action, and accessibility behavior, plus width-dependent intrinsic height.

- [ ] **Step 1: Change boundary checks to require flow layout**

Require the selector source to reference `ASRButtonFlowLayout`, override `layout` and `intrinsicContentSize`, and invalidate intrinsic size when width changes. Reject `NSScrollView`, `hasHorizontalScroller`, `scrollToVisible`, and the fixed 40-point height constraint. Require the configuration tooltip to describe direct wrapped selection instead of horizontal scrolling.

- [ ] **Step 2: Run boundary checks and confirm they fail**

Run:

```bash
bash native/Tests/ExpandedASRBackendUIBoundaryCheck.sh
bash native/Tests/CommonASRSwitchProgressCheck.sh
```

Expected: both fail against the current scrolling implementation.

- [ ] **Step 3: Implement the flow control**

Remove the scroll view, document view, and horizontal stack. Add buttons directly to the control; preserve their configuration and natural fitting widths with a 110-point minimum. Override `isFlipped`, `layout`, and `intrinsicContentSize`; use the pure calculator to set button frames, invalidate intrinsic height after width changes, and keep `select(tag:)` free of scrolling behavior.

- [ ] **Step 4: Remove fixed height and update copy**

Delete `asrBackendMode.heightAnchor.constraint(equalToConstant: 40)` from `buildModelEntry()`. Update the tooltip to say that all models are directly available in the wrapped button area while the current recording remains unaffected.

- [ ] **Step 5: Run focused regression checks**

Run:

```bash
/tmp/typewhale-tests/asr-button-flow-layout-check
bash native/Tests/ExpandedASRBackendUIBoundaryCheck.sh
bash native/Tests/CommonASRSwitchProgressCheck.sh
bash native/Tests/LocalASRModelSelectionBoundaryCheck.sh
```

Expected: all checks pass.

### Task 3: Documentation, full verification, installation, and UI review

**Files:**
- Modify: `docs/开发日志.md`
- Modify: `native/Sources/Presentation/VersionHistory/VersionHistoryViewController.swift`
- Build-generated version files as selected by `native/build_and_log.sh`.

**Interfaces:**
- Consumes: completed wrapping selector and existing release workflow.
- Produces: installed, signed TypeWhale Pro build and recorded release history.

- [ ] **Step 1: Record the user-visible layout change**

Add the next version/build entry to the development log and in-app version history, stating that all ASR buttons are natural-width, automatically wrapped, and visible without horizontal scrolling.

- [ ] **Step 2: Run source verification**

Run the flow-layout check, existing ASR UI boundary checks, local model admission check, project Swift typecheck, `git diff --check`, and conflict-marker scan. Expected: every command exits zero.

- [ ] **Step 3: Recheck concurrency and build through the only supported entry point**

Run `git branch --show-current`, `git status --short`, process checks for build tools, and recent source mtimes. If clear, run:

```bash
./native/build_and_log.sh
```

Expected: build succeeds, overwrites `/Applications/TypeWhale Pro.app`, opens it, and records the resulting build.

- [ ] **Step 4: Review the real installed UI**

Open the Common page, capture the default window, confirm every model button is visible with no scroller, resize the window narrower and wider, and confirm rows reflow without overlap, clipping, or card overflow. Click one non-current ready model and verify switching progress/status, then restore the prior model.

- [ ] **Step 5: Verify installation and commit**

Verify installed plist version/build, running process, and strict code signature. Stage only this task's files, run `git diff --cached --check`, commit the implementation and release outputs, and require a clean `git status --short`.
