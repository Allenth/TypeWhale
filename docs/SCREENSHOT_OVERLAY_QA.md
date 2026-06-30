# Screenshot Overlay QA Checklist

This checklist is the Version B real-overlay verification gate. Run it against the installed app in `/Applications/TypeWhale.app`, not only against source code.

## Scope

- Region screenshot.
- Window hover and click selection.
- Toolbar command availability after selection.
- Translation and window-recapture pending states.
- Copy, save, OCR, annotation, undo, done, Esc, right-click cancel.

## Preconditions

- Installed app is the current build recorded in `README.md`.
- Screen Recording permission is granted.
- DeepSeek API Key is configured only for translation-path checks that need a successful translation.
- A simple English UI/text sample is visible on screen for OCR/translation tests.
- A normal target app with an editable text field is open for OCR pasteboard checks if needed.

## Region Selection

1. Trigger ordinary screenshot mode.
2. Drag a region with visible text.
3. Expected:
   - Selection border and size label are visible.
   - Handles are visible when not annotating.
   - Toolbar buttons are not black/disabled except when a pending state explicitly requires it.
   - Dragging inside the selection moves it.
   - Dragging handles resizes it.

## Toolbar Availability

After a normal selected region:

- Copy is enabled.
- Save is enabled.
- OCR is enabled.
- Translate is enabled.
- Rectangle, arrow, pen, and text are enabled.
- Undo is enabled, even when it may no-op because no markup exists.
- Cancel is enabled.

If any ordinary selected-region button is visually disabled or unclickable, treat it as a regression.

## Copy And Save

1. Click copy or press Enter.
2. Expected:
   - Overlay closes.
   - Clipboard receives an image containing the selection and any markups.
   - TypeWhale main window is not unexpectedly shown.
3. Repeat with save.
4. Expected:
   - Overlay closes.
   - PNG is written to the configured screenshot directory.
   - Saved image contains the selection and any markups.

## Annotation

1. Select rectangle, arrow, pen, and text tools one by one.
2. Draw or place one markup for each tool.
3. Expected:
   - Active tool highlight follows the selected tool.
   - Markups are clipped to the selected region.
   - Undo removes the latest markup.
   - Delete removes the selected markup while annotating.
   - Copy/save output includes the remaining markups.

## OCR

1. Select a region with readable text.
2. Click OCR.
3. Expected:
   - Overlay closes.
   - Main status shows OCR processing, then success or a useful failure.
   - Clipboard receives recognized text on success.
   - If OCR fails or returns empty, stale callbacks do not reopen or mutate a later screenshot overlay.

## Screenshot Translation

1. Select a region with multiple English words or labels on the same visual row.
2. Click Translate.
3. During pending:
   - Only Cancel should be available.
   - Copy, save, OCR, annotation tools, undo, and done must not export or mutate unstable output.
4. On success:
   - Chinese translation blocks appear inside the selected region.
   - Each translation block is left-aligned to the corresponding OCR source line start.
   - Right-edge text may shift left only enough to stay inside the selection.
   - Copy/save output includes the translation layer.
5. On empty OCR, missing API key, cost limit, or network failure:
   - Selection remains usable.
   - User can retry, copy, save, or cancel.

## Cancel And Stale Callback Safety

Run these checks slowly enough that pending work has time to complete after cancel:

1. Start screenshot translation, then immediately press Esc.
2. Expected:
   - Overlay closes.
   - Clipboard and saved files are not modified by the cancelled translation.
   - No old "translation completed" overlay appears later.
3. Start screenshot translation, then right-click cancel.
4. Expected: same as Esc.
5. Start OCR, then immediately start a new screenshot after the overlay closes.
6. Expected:
   - Old OCR result does not overwrite the new screenshot session status after a newer operation begins.

## Window Selection And Recapture

1. Trigger ordinary screenshot mode.
2. Hover a visible app window.
3. Expected:
   - Candidate window outline appears.
   - Instruction text changes to window-selection mode.
4. Click the candidate window.
5. During recapture pending:
   - Overlay should not allow ordinary selection edits.
   - Cancel remains possible.
6. After recapture:
   - Window-aligned selection appears.
   - Toolbar commands are usable.
7. Repeat and cancel while recapture is pending.
8. Expected:
   - Overlay closes cleanly.
   - Old recapture does not refresh a closed overlay.

## Main Window Visibility

Run region and window screenshot checks with TypeWhale main window in three states:

- Closed/hidden.
- Behind another app.
- Visible in front.

Expected:

- Entering screenshot mode does not unexpectedly show, hide, or restore the TypeWhale main window.
- Copy/save/cancel do not unexpectedly open the main window.

## Pass Criteria

Version B cannot be declared complete until:

- Ordinary selected-region toolbar availability is verified in the installed app.
- Pending translation and window recapture are verified cancel-only in the installed app.
- Stale OCR/translation/window recapture callbacks are verified not to mutate later state.
- Copy, save, OCR, translation, annotation, undo, Esc, and right-click cancel all pass.
