# Visual brief — TypeWhale 遥控器 Tab

## Objective

Make the remote feel like a first-party TypeWhale input source. The page must answer three questions at a glance: “连上了吗？语音到哪一步？下一步怎么做？” while keeping mappings, permissions, and recovery on the same scroll surface.

## Product context

- Platform: macOS AppKit, existing 1000 × 620 pt TypeWhale main window.
- Surface: right inspector panel with segmented navigation and existing scroll behavior.
- Theme: reuse `UITheme` water-ink dark/light tokens and `inspectorGroupBox`; no Xiaomi/SayAll visual assets.
- Primary hardware: Xiaomi Bluetooth Remote 2 Pro / RC003-compatible firmware.
- Primary interaction: hold voice key to speak; release to finish TypeWhale recognition.

## Hierarchy

1. Lead status card with enable switch and one context-sensitive primary action.
2. Device truth and pairing recovery.
3. Five-stage voice path that makes failures diagnosable without logs.
4. Button mapping and reset.
5. Permissions/privacy and embedded three-step use/help.

## Content rules

- Use concrete customer language; never expose AWF, GPL analysis, source internals, or development status in the product UI.
- Never display “已连接” unless the peripheral, ATVV characteristics, and notification setup are real.
- Never display “语音可用” before capability negotiation succeeds.
- Device identifiers and Bluetooth addresses are absent.
- Keep a single primary action per state: 扫描遥控器 / 连接 / 重试 / 停止扫描.

## Accessibility and responsiveness

- All status chips and buttons need explicit accessibility labels and help.
- Status is never color-only; text and icon accompany tone.
- Keyboard navigation reaches enable, main action, mapping popups, reset, and system settings.
- Inspector width may compress to the current minimum; cards reflow vertically and labels truncate only secondary metadata.
- Full content scrolls; no bottom control may be clipped or unreachable.

## Required states

`disabled`, `bluetooth-unavailable`, `unpaired`, `scanning`, `connecting`, `negotiating`, `ready`, `listening`, `processing`, `busy`, `disconnected-retrying`, `protocol-failure`.
