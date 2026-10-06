# Yellow Whale Pro App Icon Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the confirmed second-generation yellow whale as the TypeWhale Pro application icon with a permanent deep-brown/warm-yellow `PRO` badge.

**Architecture:** Preserve `TypeWhaleMinimalLogo.svg` and `.png` as immutable brand masters. Add a dedicated Pro SVG and raster production source, point the existing native `.icns` pipeline to that source, and lock the path with the existing icon/theme regression check. Use the repository release wrapper for versioning, installation, launch, signature verification, and logging.

**Tech Stack:** SVG, macOS `sips`/`iconutil`, Brand Icon Production Swift validators, zsh build scripts, AppKit application bundle.

## Global Constraints

- Change only the TypeWhale Pro application icon; do not change menu-bar, main-window, regular TypeWhale, capsule, ASR, translation, OCR, hotkey, or paste behavior.
- Preserve the existing yellow whale master geometry, gradient, colors, and whale-mark position.
- Use a deep-brown rounded badge with warm-yellow uppercase `PRO` text in the lower-right safe area.
- Keep the protected `assets/TypeWhaleMinimalLogo.svg` and `assets/TypeWhaleMinimalLogo.png` byte-for-byte unchanged.
- Keep the outer canvas transparent and avoid white corners, a second outer tile, or display-only shadows beyond the preserved master artwork.
- Use `./native/build_and_log.sh` as the sole build/install entry point.
- Protect unrelated untracked capsule concept directories from staging or modification.

---

### Task 1: Lock the new Pro icon source contract

**Files:**
- Modify: `native/Tests/WaterInkThemeCheck.sh`
- Modify: `native/build_native_app.sh:99`

**Interfaces:**
- Consumes: repository-relative asset path `assets/TypeWhaleAppIcon-yellow-pro.png`
- Produces: a regression gate requiring the Pro-specific production icon source

- [ ] **Step 1: Change the regression check first**

Replace the current icon assertion with:

```bash
grep -q 'TypeWhaleAppIcon-yellow-pro.png' "$BUILD_NATIVE" || {
  echo "Native Pro build must use the approved yellow-whale Pro app icon source." >&2
  exit 1
}
```

- [ ] **Step 2: Run the check and verify it fails**

Run: `bash native/Tests/WaterInkThemeCheck.sh`

Expected: exit 1 with `Native Pro build must use the approved yellow-whale Pro app icon source.`

- [ ] **Step 3: Point the build pipeline to the dedicated source**

Change the declaration to:

```bash
ICON_SOURCE="$ROOT/assets/TypeWhaleAppIcon-yellow-pro.png"
```

- [ ] **Step 4: Run the check and verify it passes**

Run: `bash native/Tests/WaterInkThemeCheck.sh`

Expected: `WaterInkThemeCheck passed`

### Task 2: Produce the yellow whale Pro master and raster assets

**Files:**
- Create: `assets/TypeWhaleAppIcon-yellow-pro.svg`
- Create: `assets/TypeWhaleAppIcon-yellow-pro.png`
- Preserve: `assets/TypeWhaleMinimalLogo.svg`
- Preserve: `assets/TypeWhaleMinimalLogo.png`

**Interfaces:**
- Consumes: the exact geometry and paint definitions from `TypeWhaleMinimalLogo.svg`
- Produces: a 1024×1024 RGBA PNG consumed by `native/build_native_app.sh`

- [ ] **Step 1: Record protected-master and old production hashes**

Run:

```bash
shasum -a 256 assets/TypeWhaleMinimalLogo.svg assets/TypeWhaleMinimalLogo.png assets/TypeWhaleAppIcon-ink.png
```

Expected protected PNG hash: `9e5e02a2817def106c5d31571a49a0f8760b0800f89472cf7a95b4c4298dbcba`.

- [ ] **Step 2: Add the dedicated SVG master**

Copy the protected SVG geometry exactly, then add this badge after the whale eye and before `</svg>`:

```svg
  <g aria-label="TypeWhale Pro badge">
    <rect x="570" y="674" width="252" height="126" rx="52" fill="#6F4E08"/>
    <rect x="572" y="676" width="248" height="122" rx="50" stroke="#FFE36A" stroke-opacity="0.34" stroke-width="4"/>
    <text x="696" y="758"
          fill="#FFD84D"
          font-family="-apple-system, BlinkMacSystemFont, 'Helvetica Neue', Arial, sans-serif"
          font-size="62"
          font-weight="800"
          letter-spacing="2"
          text-anchor="middle">PRO</text>
  </g>
```

- [ ] **Step 3: Render the production PNG**

Run:

```bash
sips -s format png assets/TypeWhaleAppIcon-yellow-pro.svg --out assets/TypeWhaleAppIcon-yellow-pro.png
```

Expected: a 1024×1024 RGBA PNG.

- [ ] **Step 4: Generate and validate all production sizes**

Run:

```bash
icon_check_dir="$(mktemp -d /tmp/typewhale-yellow-pro-appicon.XXXXXX)"
$HOME/.codex/skills/brand-icon-production/scripts/produce-appiconset.sh \
  assets/TypeWhaleAppIcon-yellow-pro.png "$icon_check_dir" 1.0
```

Expected: `Validated 7 AppIcon PNGs` for 16, 32, 64, 128, 256, 512, and 1024 px. Safe scale is `1.0` because the protected master already contains its established transparent visual safe area.

- [ ] **Step 5: Verify protected masters and image metadata**

Run:

```bash
shasum -a 256 assets/TypeWhaleMinimalLogo.svg assets/TypeWhaleMinimalLogo.png
sips -g pixelWidth -g pixelHeight -g hasAlpha -g format assets/TypeWhaleAppIcon-yellow-pro.png
```

Expected: protected hashes unchanged; new PNG reports 1024×1024, alpha `yes`, format `png`.

### Task 3: Record the release and build prerequisites

**Files:**
- Modify: `docs/开发日志.md`
- Modify: `native/Sources/Presentation/VersionHistory/VersionHistoryViewController.swift`

**Interfaces:**
- Consumes: current repository version `2.0.29 (Build 745)` and build counter `276`
- Produces: required entry for the next normal build `2.0.29 (Build 746)`

- [ ] **Step 1: Add the in-app version entry at the top**

Add:

```swift
VersionEntry(
    version: "版本 2.0.29 (Build 746)",
    date: "2026-07-18",
    changes: [
        "TypeWhale Pro 应用图标恢复为黄色鲸鱼第二版，并增加深棕底、暖黄色字的 PRO 角标。",
        "本次只调整 Pro App 图标资源；菜单栏图标、主界面品牌、语音输入、识别、翻译、OCR 与粘贴行为保持不变。"
    ]
),
```

- [ ] **Step 2: Add the development-log entry at the top**

Record the product goal, protected master, badge palette and position, build-source change, scope boundary, and planned 16–1024 px/install/signature verification under `2.0.29 (Build 746)`.

- [ ] **Step 3: Verify the release guard sees the entry**

Run:

```bash
grep -F '版本 2.0.29 (Build 746)' native/Sources/Presentation/VersionHistory/VersionHistoryViewController.swift
```

Expected: exactly one match.

### Task 4: Perform independent visual review and corrective pass

**Files:**
- Review: `assets/TypeWhaleAppIcon-yellow-pro.svg`
- Review: `assets/TypeWhaleAppIcon-yellow-pro.png`

**Interfaces:**
- Consumes: source and 16/32/64/128/1024 px renders
- Produces: design-review verdict covering hierarchy, readability, safe area, visual balance, and production defects

- [ ] **Step 1: Inspect the 1024 px source and 32/64 px renders**

Use `view_image` on the source PNG and the generated small-size outputs. Confirm the whale mark remains unchanged, the badge does not collide with it, and the badge reads as Pro identity rather than a promotional sticker.

- [ ] **Step 2: Run an independent design review**

Apply the repository-required `design-review` skill in an independent subagent. Require explicit checks for light/dark backdrop, transparent corners, double rounding, text legibility, visual centering, and clipping risk.

- [ ] **Step 3: Apply only bounded visual corrections if required**

Corrections may change only badge position, size, corner radius, border opacity, or typography. The protected yellow tile and whale mark must remain unchanged. Re-render and revalidate all sizes after any correction.

### Task 5: Build, install, and verify the real application

**Files:**
- Automatically modified: `native/build_native_app.sh` version/build values
- Automatically modified: `README.md`
- Automatically modified: `macos/README.md`
- Automatically appended: `docs/构建日志.md`
- Generated/installed: `macos/TypeWhale Pro.app`, `/Applications/TypeWhale Pro.app`

**Interfaces:**
- Consumes: approved production PNG and version-history entry
- Produces: signed, installed, launched TypeWhale Pro build with the new `.icns`

- [ ] **Step 1: Re-run concurrency protection checks**

Run branch/status, active build-process, target mtime, and current-version checks. Stop if another session is writing overlapping files or building.

- [ ] **Step 2: Run the sole build entry point**

Run: `./native/build_and_log.sh`

Expected: build-only cadence advances to `2.0.29 (746)`, installs to `/Applications/TypeWhale Pro.app`, launches it, verifies signing, and appends the build log.

- [ ] **Step 3: Verify installed metadata, icon and signature**

Run:

```bash
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' '/Applications/TypeWhale Pro.app/Contents/Info.plist'
/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' '/Applications/TypeWhale Pro.app/Contents/Info.plist'
shasum -a 256 'macos/TypeWhale Pro.app/Contents/Resources/TypeWhale.icns' '/Applications/TypeWhale Pro.app/Contents/Resources/TypeWhale.icns'
codesign --verify --deep --strict --verbose=2 '/Applications/TypeWhale Pro.app'
```

Expected: `2.0.29`, `746`, matching `.icns` hashes, and valid signature.

- [ ] **Step 4: Refresh registration and visually inspect the installed app**

Check `lsregister -dump` for duplicate TypeWhale Pro registrations, unregister non-install copies if needed, refresh Finder/Dock caches, reopen the installed app, and inspect Finder/Dock/Application-folder presentation. Confirm the yellow whale and `PRO` badge are visible and unclipped.

- [ ] **Step 5: Run final regression checks**

Run:

```bash
bash native/Tests/WaterInkThemeCheck.sh
git diff --check
git status --short
```

Expected: test pass, no whitespace errors, and only this icon delivery's files plus the two pre-existing protected capsule concept directories appear.
