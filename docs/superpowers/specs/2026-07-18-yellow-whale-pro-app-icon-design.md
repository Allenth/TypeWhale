# Yellow Whale Pro App Icon Design

## Product goal

Restore the confirmed second-generation yellow TypeWhale whale mark as the TypeWhale Pro application icon, while making the Pro identity unmistakable at Finder and Dock sizes.

## Scope

- Replace only the TypeWhale Pro application icon production source.
- Preserve the existing yellow whale master geometry, gradient, colors, and whale-mark position.
- Add a permanent `PRO` badge in the lower-right corner.
- Generate and validate the macOS icon sizes used by the existing build pipeline.
- Build, install, launch, sign-check, and visually verify `/Applications/TypeWhale Pro.app`.

## Out of scope

- Menu-bar/status-item artwork.
- Main-window logo or brand colors.
- TypeWhale non-Pro identity.
- Capsule, ASR, translation, OCR, hotkey, or paste behavior.
- Redesigning the yellow whale symbol.

## Visual design

The base remains the existing `TypeWhaleMinimalLogo.svg`: a warm yellow rounded tile with the second-generation whale mark. A compact rounded badge sits inside the lower-right visual safe area. The badge uses the whale mark's deep brown as its fill and warm yellow uppercase `PRO` lettering, producing a single coherent palette rather than a promotional sticker effect.

The badge must remain visually separate from the whale mark, retain padding at 16 px output, and stay clear of macOS icon masking. It must not introduce a second outer icon tile, white canvas, or display-only shadow.

## Production assets and integration

- Keep the existing yellow whale SVG and PNG unchanged as protected masters.
- Add a dedicated Pro SVG master and a 1024 px RGBA production PNG.
- Point `native/build_native_app.sh` to the dedicated Pro production PNG.
- Preserve the current `.icns` generation contract and exact 16–1024 px entries.
- Update the icon-source regression check to require the new Pro asset.

## Verification

- Record old and new source SHA-256 hashes before replacement.
- Confirm the new 1024 px PNG is RGBA with transparent outer corners.
- Generate and validate 16, 32, 64, 128, 256, 512, and 1024 px outputs.
- Inspect the source, production preview, and small-size render visually.
- Run the relevant icon-source regression check.
- Use the repository's sole build entry point, allowing its normal build/full-version cadence.
- Verify the installed app's icon resource, code signature, launch state, Finder/Dock appearance, and absence of duplicate registered development copies where practical.

## Failure conditions

- The whale mark is redrawn, shifted, recolored, or obscured.
- `PRO` is unreadable at Dock/Finder scale or clipped by the icon mask.
- The output contains white corners, a double rounded rectangle, or a full-canvas background.
- The regular TypeWhale identity or status-item icon changes.
- Any unrelated product behavior changes.
