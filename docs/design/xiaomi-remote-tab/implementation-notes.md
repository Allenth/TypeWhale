# Implementation notes — Remote tab

## Layout

- Add `remote` to `MainInspectorTab` after `voice` and before `hotkeys`.
- Use existing `inspectorPage` and `inspectorGroup` containers; the page is a vertical scroll document.
- Preserve the existing main window at 1000 × 620 pt. Segment widths must fit the right pane without clipping; `OpenClaw` may stay wider while Chinese labels use compact widths.
- Lead card contains the overall state, supporting sentence, enabled switch, and a context-sensitive primary button.
- Device and voice-path rows are real views driven by `RemoteInputCoordinator` snapshots, not static copy.

## Behavior

- Enabling starts retrieval/scan only when CoreBluetooth is powered on.
- The primary button changes by state: scan, stop scan, connect, retry. It never opens a second window.
- Hold-to-talk is driven by ATVV control events. Duplicate start/stop events are idempotent.
- If TypeWhale already has an active speech session, reject remote start as `busy` and leave that session untouched.
- Disconnect while listening ends/cancels the remote-owned session safely and schedules bounded backoff.
- Mappings persist locally. Reset restores safe defaults. Unmapped and unknown usages do nothing.

## Permission and privacy

- Bluetooth state comes from `CBCentralManager.authorization` and manager state.
- HID mapping reports Input Monitoring limitations honestly; the app may deep-link to the relevant System Settings pane but cannot grant itself access.
- The page explains that speech remains local unless the user's selected TypeWhale ASR provider itself is online.
- No raw packets, audio samples, Bluetooth addresses, peripheral UUIDs, or remote names are written to persistent diagnostics.

## Accessibility

- Overall state has label `遥控器状态：<state>`.
- Pipeline stages expose both name and status.
- Mapping popup labels name the physical button and selected action.
- Dynamic updates use a polite announcement only when state meaningfully changes (ready, listening, failure), not on every packet.

## Verification

- Compare installed UI against `clean.svg` at the current panel width.
- Verify top and bottom of the scroll document, keyboard focus, VoiceOver labels, dark theme, and light theme token use.
- Verify all required failure states through pure state tests or injected controller snapshots; hardware-ready/listening requires real-device evidence.
