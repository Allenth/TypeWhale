# Verification record — Remote tab

- Design status: approved
- Implementation status: TypeWhale Pro 2.0.58 (899) installed and running
- Installed screenshots:
  - `~/.gstack/projects/Allenth-TypeWhale/designs/design-audit-20260912/screenshots/remote-top-build899.png`
  - `~/.gstack/projects/Allenth-TypeWhale/designs/design-audit-20260912/screenshots/remote-bottom-build899.png`
- Accessibility tree: passed; native controls expose tab, switch, scan action, four mapping pop-ups, permissions, device and pipeline status
- Dark theme: passed at the installed 1000 × 620 pt window; Retina evidence is 2000 × 1240 px
- Light theme token review: implementation reuses the existing `UITheme` tokens; an installed light-theme screenshot was not required for this dark-theme user session
- Required state coverage: policy tests cover disabled, unavailable, unpaired, scanning, connecting, negotiating, ready, listening, processing, busy, retry and protocol failure; installed hardware covered ready and listening
- Real hardware: passed with Xiaomi Bluetooth Voice Remote Control model RC003, 61% battery, ATVV control ready, PCM level observed from -44 dB through -2 dB, and 260 packets in one visible session
- Dual-input compatibility: passed; a real remote ATVV session completed, then a controlled Fn session migrated the old `MiRemoteV 2ch` selection and opened `MacBook Pro麦克风` before completing normally
- User-visible result: remote sessions produced recent transcripts including “这个可以吗？” and “效果非常棒，我非常满意”
- Final design judgment: Go; no High or Medium design findings

## Unit acceptance record

```text
Unit: TypeWhale native remote input page
Path: Main window → 遥控器
Flow selected: production native-App integration
Status: Go with accepted risk
Design goal: make connection, voice-path health, mapping, permission and recovery understandable on one scrollable page
Public copy / SEO gate: not applicable; this is a private native control surface
In scope: RC003 connection, ATVV voice, external PCM, existing ASR/writeback, button observation, settings and diagnostics
Out of scope: SayAll code/assets, virtual microphone, driver/helper, Windows, public distribution
Completed scope: all in-scope paths implemented; legacy virtual-input migration added after live regression feedback
Screenshots/evidence: installed top and bottom screenshots above; Build 899 log and aggregate check
Verified viewports: 1000 × 620 pt native window, 2000 × 1240 px Retina captures
Verified states: ready, listening and idle on hardware; all declared failure states through state tests
Interactions checked: select tab, scroll to bottom, start/release remote speech, Fn start/finish, mapping values and disabled recording action
Issues found: normal Fn input was still bound to the old MiRemoteV 2ch device
Fixes completed: one-time system-microphone migration only for that legacy virtual input while the native remote feature is enabled
Remaining risk: long-duration disconnect/reconnect stress and unknown future remote firmware are not proven by this session
Allowed to proceed to next unit: yes
```
