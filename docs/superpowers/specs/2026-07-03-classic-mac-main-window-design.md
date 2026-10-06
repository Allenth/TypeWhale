# TypeWhale Classic Mac Main Window Design

## Goal

Explore a Classic Mac inspired redesign of the TypeWhale Pro main window in the isolated worktree `codex/typewhale-classic-mac-design-lab`, producing a real runnable interface direction that can later be promoted to the stable product path if it proves stronger than the current horizontal control panel.

## Product Judgment

The current main window already contains the right product objects: current session, recent transcriptions, preview theme, smart rewrite settings, hotkeys, system settings, model status, and permissions. The design problem is hierarchy and spatial stability. The right side is currently a horizontal scroller of panels, which makes settings feel clipped and poster-like rather than like a stable desktop control panel.

This experiment should preserve TypeWhale's product identity as a local speech input workstation, while translating Classic Mac HIG principles into a modern macOS app:

- Current speech work stays primary.
- Settings become discoverable, stable, and grouped by purpose.
- Controls expose state and consequences without requiring memory.
- Visual nostalgia serves readability and control, not decoration.

## Scope

In scope:

- Redesign `MainViewController` layout and visual hierarchy.
- Replace the right-side horizontal panel scroller with a stable inspector area.
- Keep the left session/recent-transcription area visible as the main work surface.
- Group settings into clear pages or sections: General, Intelligence, Hotkeys, Status.
- Introduce a small Classic Mac inspired control surface vocabulary where it improves clarity: bordered panels, stronger hairlines, restrained palette, clearer button states, compact row rhythm.
- Preserve existing settings storage, actions, popovers, permissions, model install flow, hotkey capture flow, and recent transcription behavior.
- Update developer/product docs for the experiment.
- Build, install, open, and visually verify the installed app after code changes.

Out of scope:

- Changing ASR recognition behavior.
- Changing paste, clipboard restore, screenshot, OCR, translation, or smart rewrite semantics.
- Replacing the capsule/notch recording overlay.
- Adding third-party fonts, bitmap assets, or unlicensed visual material.
- Turning the UI into a strict historical System 7 replica.

## Required Hierarchy

The main window must read in this order:

1. App identity and live app health in the title bar area.
2. Current session state and live transcript.
3. Recent transcriptions.
4. Configurable settings.
5. Diagnostics and permissions.

The current session column is the user's workspace. It must remain visible while changing settings. Settings and status are supporting inspectors, not equal-weight workspaces.

## Layout Direction

Use a two-zone layout:

- Left fixed work zone: current session card and recent transcriptions.
- Right inspector zone: a tabbed or segmented content area with stable width and no horizontal scrolling.

Recommended tabs:

- `常用`: preview theme, quick rewrite mode, auto translation, translation direction, screenshot save location, microphone input, recording behavior toggles.
- `智能`: smart model, auto scope, rewrite prompt, developer terms, translation prompt, social scope, DeepSeek key/balance when relevant.
- `快捷键`: all hotkey bindings in a table-like list with command name, current binding, and reset/clear action.
- `状态`: current ASR model, permissions, hotkey listener, and memory state.

The experiment may combine `常用` and `智能` if implementation pressure is high, but it must not reintroduce a horizontally clipped list of panels.

## Visual Direction

Use Classic Mac HIG as a lens, not as cosplay:

- Increase contrast between background, panel fill, text, separators, and controls.
- Use color primarily for status and brand: green for healthy/ready, yellow for TypeWhale brand/accent, red/orange for problems.
- Keep controls consistent in height, border, pressed/selected/focused state, and label alignment.
- Prefer stable rectangular and subtle rounded panels over large soft cards.
- Preserve existing system font APIs. Do not add fonts.
- Do not use visible explanatory marketing copy inside the app.

## Interaction Requirements

- Hotkey capture must keep its existing behavior: disable sibling capture buttons while capturing, update titles, and restore labels after completion/cancel.
- Settings must keep existing `saveSettings` behavior.
- Theme selection must remain direct click-to-select.
- Status/permission rows must still open the appropriate system settings or detail popovers.
- The Preferences command may scroll no longer; it should bring the inspector to a sensible default settings tab.
- Keyboard/mouse interaction must remain visible: selected tab, selected theme, on/off switch, button press, disabled state.

## Testing Requirements

Automated / scripted:

- Run existing guard checks:
  - `native/Tests/ReleaseVersionRuleCheck.sh`
  - `native/Tests/ScreenshotArchitectureBoundaryCheck.sh`
  - `native/Tests/SmartRewriteSystemPromptBoundaryCheck.sh`
- Add a lightweight static guard if the layout change introduces a new invariant worth protecting, such as no horizontal main panel scroller.

Manual installed-app verification:

- Build via `./native/build_and_log.sh` after code changes.
- Confirm `/Applications/TypeWhale.app` opens to the redesigned main window.
- Verify current session area, recent transcriptions, settings tabs, hotkey table, status/permissions, and top bar fit without clipping at the shipped window size.
- Verify switching tabs does not move the current session area.
- Verify clicking preview theme changes selected state.
- Verify beginning and canceling a hotkey capture remains understandable.
- Verify permission buttons and model/status detail affordances remain clickable.

## Review Requirements

- Run a design quality review after implementation, using `design-review` if practical.
- If live visual review cannot be fully completed, record the remaining risk explicitly in the final response.
- Before promoting this experiment to the stable branch, compare screenshots against the current UI and judge whether hierarchy, readability, and control clarity improved.

## Success Criteria

The experiment is successful if the installed app feels more like a stable desktop control panel:

- No right-side clipped horizontal panel reading.
- Current speech work remains visually primary.
- Settings are easier to scan by purpose.
- Hotkeys read as a table of commands instead of stray buttons.
- Status and permissions are visible but not competing with the main task.
- The UI keeps TypeWhale's warm brand character while gaining classic desktop clarity.
