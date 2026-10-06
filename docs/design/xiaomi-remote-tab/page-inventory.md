# Page inventory — 小米遥控器 2 Pro

| ID | Surface | Current | Target | States | Evidence |
| --- | --- | --- | --- | --- | --- |
| P01 | TypeWhale main inspector navigation | 6 tabs | Add seventh `遥控器` tab | default, selected, keyboard focus | installed screenshot + AX tree |
| P02 | Remote tab / connection | Missing | Native status, enable, scan/connect, paired-device guidance | disabled, Bluetooth unavailable, unpaired, scanning, connecting, ready, failure | screenshot + state reducer tests |
| P03 | Remote tab / voice path | Missing | BLE → control → packet → PCM → TypeWhale session diagnostics | idle, listening, processing, protocol failure | screenshot + protocol/audio tests |
| P04 | Remote tab / button mapping | Missing | Configurable remote actions with safe defaults | available, permission-limited, disabled | screenshot + mapping tests |
| P05 | Remote tab / permissions and help | Missing | Real permission status, recovery entry, local-privacy copy, pairing/use steps | granted, denied, restricted, unknown | screenshot + boundary test |

The five regions are one inseparable scroll page because the user must understand connection, input behavior, health, and recovery without leaving TypeWhale. No new window, WebView, or modal setup wizard is introduced.
