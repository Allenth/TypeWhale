# TypeWhale Content Reader Design

Date: 2026-07-24
Status: Web-article and OCR sources added; pending written-spec review
Owner: TypeWhale product and engineering

## Summary

TypeWhale adds a first-party **Content Reader** under the existing **Voice** tab. It accepts text from authorized clipboard changes, a Chrome extension that extracts the current web article, and user-initiated local OCR. All sources become Reader Items that share text preparation, history, playback, and the draggable floating toolbar.

The default authorized source is Codex. Users may authorize additional applications.

The feature uses a new Reader Core and a native, isolated TTS helper. It must not depend on Python in the shipped product.

## Product Goal

Help users with reading difficulty consume Codex answers and other copied text through a predictable, low-friction listening flow:

1. Copy text in Codex, click **Read Webpage**, or click **OCR**.
2. See it appear in TypeWhale’s floating reader.
3. Play it manually, or enable automatic playback.
4. Pause, stop, change voice and speed, or choose another recent copied item.

## Non-goals

- No generic third-party plugin platform.
- No cloud TTS fallback.
- No Python, `pip`, or user-managed runtime in the shipped feature.
- No automatic reading from unapproved applications.
- No continuous playback queue for every copied item.
- No automatic persistence of copied content.
- No promise of emotion controls when the selected model does not support them.
- No code reading by default.
- No modification of authoritative clipboard contents.
- No bypass of login, paywalls, CAPTCHA, site permissions, or other access controls.
- No background extraction of webpages that the user did not explicitly request.
- No general-purpose browser automation platform in the first Chrome-extension release.

## Entry Points

### Voice Tab

Add a new **Content Reader** group under the existing Voice tab.

It contains:

- master enable switch;
- **Show Reader Toolbar** action;
- Chrome-extension installation, connection status, and repair entry;
- authorized application list;
- toolbar visibility mode;
- default voice;
- default emotion;
- default speech rate;
- default volume;
- read-code toggle;
- history capacity;
- persist-history toggle;
- clear-history action;
- model status and installation/repair entry.

### Menu Bar

Add **Show Reader Toolbar** to the TypeWhale menu-bar menu.

The Voice tab and menu-bar entry remain available when the floating toolbar is hidden.

### Floating-Toolbar Source Actions

The expanded toolbar adds:

- **Read Webpage**;
- **OCR**;
- OCR mode: rectangular region or whole window, defaulting to rectangular region.

Read Webpage and OCR are explicit play actions and are independent of the clipboard autoplay setting.

## Source Authorization

- Codex is authorized by default using its bundle identifier.
- Users can add or remove other applications.
- Clipboard changes are accepted only when the frontmost source application is authorized.
- The reader does not ingest clipboard contents that existed before the feature started.
- Unapproved sources do not create history entries or speech work.
- The preview shows the detected source application.

## Web Article And OCR Acquisition

### Chrome Extension

The first release provides a TypeWhale Chrome extension. When the user clicks **Read Webpage**:

1. TypeWhale requests content from the active tab.
2. A content script reads the currently accessible, rendered DOM.
3. Mozilla Readability runs on a document clone and extracts title, byline, language, and article body.
4. Chrome Native Messaging transfers the structured result to TypeWhale.
5. TypeWhale creates a web Reader Item, shows preview, and starts playback.

Rules:

- extraction occurs only after the explicit user action;
- the extension uses minimal permissions, with site access managed by Chrome and the user;
- it does not read browsing history, inactive tabs, or background pages;
- it does not bypass login, paywalls, CAPTCHA, or site permissions;
- it may process dynamic pages that the user is logged into and can currently view;
- untrustworthy or empty Readability output is not played as navigation noise;
- failure offers **Read Visible Text** and **OCR** fallbacks;
- the extension does not persist article text; TypeWhale applies the selected history policy;
- Safari support is deferred and may reuse the same protocol later.

### macOS Accessibility Fallback

When the Chrome extension is absent, disconnected, or cannot extract an article, **Read Visible Text** may:

- use macOS Accessibility APIs to read text exposed by the frontmost browser;
- require Accessibility permission;
- return navigation, controls, or only the visible portion;
- show preview and source limitations before playback;
- remain a fallback rather than the full-article primary path.

### Local OCR

When the user clicks **OCR**:

1. choose a rectangular region or whole window;
2. capture only the explicitly selected screen area;
3. run OCR locally;
4. show recognized-text preview;
5. start playback when recognition succeeds.

Rules:

- rectangular region is the default;
- temporary screenshots are deleted after OCR;
- history stores recognized text, not the image;
- empty or low-confidence results do not autoplay and offer recapture;
- OCR supports visible non-copyable text, canvas, images, and scanned documents;
- OCR does not attempt to circumvent site access controls.

### Acquisition Priority

1. Chrome extension plus Readability for full articles.
2. macOS Accessibility for currently exposed text.
3. OCR as the universal visible-content fallback.

## Clipboard And Playback Behavior

### Automatic Playback

The floating toolbar contains a persisted checkbox:

> Play automatically after copy

- Checked: a new copied item starts automatically only when the reader is idle.
- Unchecked: a new item updates preview and history but does not start playback.
- A newly copied item never interrupts speech already in progress.
- First-enable default: checked. Enabling the feature is the user's explicit decision to use the copy-to-listen flow.
- Read Webpage and OCR are explicit play commands and start playback after successful acquisition regardless of this checkbox.

### Switching Items

- New copied items are inserted into recent history.
- Recent items are not a continuous playback queue.
- Clicking another item explicitly stops the current item and starts the selected item.
- Users may also stop first and then choose another item.

### Playback Controls

The toolbar provides:

- play;
- pause;
- resume;
- stop;
- collapse;
- expand;
- hide.

Stopping preserves the selected history item and current preview.

## Recent Content History

- Default capacity: 10 items.
- Default storage: memory only.
- Memory-only history clears when TypeWhale quits.
- Optional persistent history is explicitly opt-in.
- Persistent history is stored locally in TypeWhale Application Support with user-only file permissions.
- The user can clear history at any time.
- Duplicate consecutive clipboard values update selection without creating duplicate rows.
- History records original text and prepared speech text separately, plus source type: clipboard, webpage, Accessibility, or OCR.
- Logs never record full copied text.

## Floating Toolbar

### Selected Layout

Use the approved **horizontal capsule** design.

### Collapsed State

Show:

- drag handle;
- source application;
- truncated current-content summary;
- current play/pause state;
- expand control.

### Expanded State

Show:

- current copied-content preview;
- recent-content list;
- Read Webpage;
- OCR;
- voice selector;
- emotion selector;
- speech-rate control;
- volume control;
- automatic-play checkbox;
- play, pause/resume, and stop;
- clear-history action;
- collapse control;
- hide control.

### Position And Visibility

- The toolbar is draggable from a dedicated handle.
- Dragging controls must not trigger playback actions.
- Position is remembered separately for each display.
- Display removal, resolution changes, and usable-frame changes recover the panel into a visible area.
- Visibility modes:
  - always visible while the feature is enabled;
  - appear on new content and hide after playback.
- Default visibility mode: always visible.
- In auto-hide mode, the collapsed toolbar hides five seconds after playback stops. Hovering, expanding, pausing, or receiving new content cancels the pending hide.
- Collapse changes presentation only.
- Hide removes the toolbar from screen but leaves clipboard monitoring enabled.
- The Voice-tab master switch disables monitoring, stops playback, and shuts down Reader TTS activity.

## Text Preview And Speech Preparation

Original preview text and speech-prepared text are separate values.

Default preparation rules:

- remove Markdown presentation markers;
- preserve meaningful prose and list order;
- speak link labels but not full URLs;
- skip fenced and indented code blocks;
- expose an opt-in **Read code** setting;
- convert numbers, percentages, currency, arithmetic operators, and common formulas into natural spoken language;
- preserve Chinese-English terms;
- normalize headings, parentheses, tables, bullets, and repeated punctuation into natural pauses;
- avoid splitting inside English tokens, numbers, formulas, or parenthetical clauses;
- segment at natural sentence and paragraph boundaries;
- never silently truncate long content.

Example:

```text
20,000 × 15% = 3,000
```

is prepared as:

```text
两万乘以百分之十五，等于三千。
```

Skipped code is indicated in preview without deleting the original text.

## Voice, Emotion, Rate, And Volume

Reader Core consumes engine capabilities rather than assuming every engine exposes the same controls.

Each voice profile reports:

- display name;
- language support;
- speaker identifier;
- supported rate range;
- whether native emotion control is supported;
- supported emotion values;
- model readiness.

First-enable defaults:

- speech rate: `1.0x`;
- volume: `80%`;
- voice: the native voice selected by the audition and release gate;
- emotion: `Natural` when supported, otherwise disabled.

When the active voice does not support emotion:

- the emotion control remains visible;
- the control is disabled;
- it displays **Current voice does not support emotion**;
- TypeWhale does not imitate emotion by secretly rewriting punctuation.

## Model Strategy

The production feature must use a native runtime.

Initial candidates:

1. Kokoro multilingual int8 through Sherpa C API.
2. Existing VITS Melo Chinese-English through Sherpa C API.
3. ZipVoice distilled int8 as a higher-complexity comparison candidate.

The separate native audition script compares naturalness, Chinese-English clarity, pause quality, first-audible latency, real-time factor, and memory.

No model becomes the production default until:

- native playback works without Python;
- commercial distribution rights are verified;
- installed-app latency and listening QA pass;
- failure remains isolated from TypeWhale’s input features.

## Architecture

Adopt a new shared Reader Core rather than coupling clipboard reading to OpenClaw.

### Components

#### `ClipboardReaderCoordinator`

- observes pasteboard change count;
- resolves the frontmost source application;
- applies the authorization list;
- rejects startup-existing and duplicate content;
- creates reader items.

#### `ReaderSourceCoordinator`

- normalizes all acquisition results into Reader Items;
- coordinates `ClipboardTextSource`;
- coordinates `ChromeWebArticleSource` through Native Messaging;
- coordinates `AccessibilityTextSource`;
- coordinates `OCRCaptureSource`;
- records necessary source metadata such as application, page title, and URL;
- contains no text-preparation or TTS logic.

#### `ReaderHistoryStore`

- owns recent reader items;
- enforces capacity;
- separates memory-only and opt-in persistent storage;
- clears entries on request.

#### `ReaderTextPreparer`

- transforms original copied text into speech-safe text;
- applies code, Markdown, URL, number, formula, and segmentation policies;
- returns preparation metadata for preview annotations.

#### `ReaderPlaybackCoordinator`

- owns selection and playback state;
- enforces the no-interrupt-on-new-copy rule;
- handles explicit item switching;
- prefetches the next speech segment of the active item;
- exposes play, pause, resume, stop, and progress state.

#### `ReaderTTSService`

- exposes available native engines and voice capabilities;
- owns the helper lifecycle;
- synthesizes segments;
- reports model readiness and failures;
- contains no clipboard or UI logic.

#### Native TTS Helper

- runs outside TypeWhale’s main process;
- uses Sherpa C API or another approved native API;
- keeps the selected model warm while actively used;
- supports cancellation and clean restart;
- never requires Python.

#### `ReaderFloatingPanelController`

- owns compact and expanded layouts;
- manages drag, per-display position, visibility, recovery, and accessibility;
- binds only to Reader Core presentation state.

#### Voice-Tab Reader Settings

- owns persisted product settings;
- shows model readiness;
- controls feature enablement and panel visibility;
- does not directly synthesize or inspect clipboard contents.

## Data Flow

1. An authorized foreground application writes new plain text to the pasteboard.
2. `ClipboardReaderCoordinator` accepts it and creates an item containing the original text and source metadata.
3. `ReaderTextPreparer` creates speech-safe text and preparation annotations.
4. `ReaderHistoryStore` inserts the item.
5. UI preview updates.
6. If automatic playback is enabled and playback is idle, `ReaderPlaybackCoordinator` selects and starts it.
7. If playback is active, the new item waits in history without interrupting.
8. Explicit selection of another item cancels current speech and starts the selected item.

Web article:

1. User clicks Read Webpage.
2. `ChromeWebArticleSource` requests extraction from the extension.
3. The extension runs Readability and returns structured text through Native Messaging.
4. `ReaderSourceCoordinator` creates a web Reader Item.
5. `ReaderTextPreparer` produces speech text.
6. Preview appears and `ReaderPlaybackCoordinator` starts playback.

OCR:

1. User clicks OCR and selects a region or window.
2. `OCRCaptureSource` captures and recognizes locally.
3. The screenshot is deleted and an OCR Reader Item is created.
4. Successful recognition previews and plays; low confidence waits for recapture.

## State Model

Reader playback states:

- idle;
- preparing;
- playing;
- paused;
- stopping;
- failed.

Panel states:

- visible-collapsed;
- visible-expanded;
- hidden.

Feature states:

- disabled;
- enabled-unready;
- enabled-ready.

Web-source states:

- extension-not-installed;
- extension-disconnected;
- extension-connected;
- extracting;
- extraction-failed;
- extraction-complete.

Panel visibility and playback state are independent. Hiding the panel does not stop playback or monitoring.

## Long Content

- Content is segmented without a fixed silent truncation limit.
- The first segment is synthesized first.
- Later segments are prefetched while the current segment plays.
- UI shows segment progress.
- Stop and explicit item switching cancel pending synthesis.
- Content above 50,000 characters requires explicit confirmation before preparation.
- Content above 500,000 characters is rejected with an instruction to copy a smaller section.

## Failure Handling

- Clipboard observation failure: show feature status without affecting other TypeWhale functions.
- Missing model: disable playback, preserve preview, and offer model installation/repair.
- Helper startup failure: preserve text and present an actionable error.
- Helper crash: restart once for the current request.
- Repeated helper failure: stop Reader playback and keep the feature in a recoverable failed state.
- Segment synthesis failure: stop the active item and retain it for retry.
- Temporary-audio failure: stop only Reader playback.
- No failure may block ASR, paste, screenshots, OpenClaw text, hotkeys, or the main settings window.
- No automatic Python fallback is permitted.
- Missing or disconnected extension preserves Reader playback and offers install, reconnect, Accessibility, or OCR.
- Untrustworthy Readability output is not autoplayed as page noise.
- Native Messaging failure affects only the current acquisition.
- OCR failure deletes the temporary screenshot and creates no empty item.

## Privacy And Security

- Processing is local.
- No copied text is sent to a server.
- Full text is excluded from diagnostics.
- Source authorization is explicit.
- Persistent history is off by default.
- Temporary audio is removed after playback or cancellation.
- Model packages require integrity checks and license records before distribution.
- The helper receives only the currently selected prepared text and voice configuration.
- Web extraction runs only after an explicit user action.
- The extension does not persist article text or inspect other tabs or browsing history.
- Native Messaging accepts only the controlled TypeWhale extension/host pairing.
- Diagnostic URLs are redacted by default; query strings and fragments are excluded.
- OCR screenshots are deleted after success, cancellation, or failure.

## Accessibility

- All controls have accessible names and values.
- Keyboard focus order follows preview, history, voice/emotion, rate/volume, autoplay, and transport controls.
- Play, pause, stop, collapse, expand, hide, and clear are keyboard operable.
- Disabled emotion control explains why it is unavailable.
- Status is not conveyed by color alone.
- Compact summaries use readable truncation and expose the full text as accessibility help.
- Motion remains minimal and respects reduced-motion settings.
- Read Webpage and OCR expose clear accessible names, state, and errors.
- OCR selection supports keyboard cancellation and explains region/window modes.

## Verification Strategy

### Unit And Contract Tests

- authorized-source filtering;
- startup-existing clipboard rejection;
- duplicate suppression;
- history capacity and persistence;
- automatic-play idle behavior;
- no interruption on new copy;
- explicit item switching;
- Markdown and URL cleanup;
- default code skipping;
- number, currency, percentage, and formula normalization;
- safe segmentation;
- engine capability mapping;
- emotion-disabled behavior;
- per-display position recovery;
- helper cancellation and restart.
- web-source message protocol and sender validation;
- successful, empty, and malformed Readability results;
- temporary OCR screenshot deletion;
- unified Reader Item creation across all source types.

### Integration Tests

- real Codex Copy button to Reader item;
- Voice-tab enable/disable;
- menu-bar and Voice-tab panel restoration;
- copy while idle;
- copy while playing;
- direct selection of another item;
- pause/resume/stop;
- helper crash degradation;
- missing-model behavior;
- restart with memory-only and persistent-history modes.
- Chrome-extension install, connect, disconnect, and reconnect;
- public articles, logged-in rendered articles, and pages without article content;
- fallback from extension failure to Accessibility or OCR;
- OCR rectangular region and whole window;
- explicit webpage/OCR playback independent of clipboard autoplay.

### Installed-App QA

- drag and recover the panel on multiple displays;
- collapse, expand, hide, and restore;
- listen to short, long, mixed Chinese-English, numeric, formula, Markdown, and code-containing replies;
- verify no Python process is launched;
- record cold and warm first-audible latency, memory, CPU, and uninterrupted multi-segment playback;
- verify TypeWhale ASR, paste, screenshots, OpenClaw, and hotkeys remain unaffected.
- verify the extension does not inspect inactive tabs, browsing history, or unrequested pages;
- verify article text, full URLs, and OCR screenshots do not enter diagnostics;
- verify blocked access, CAPTCHA, and paywalls are not bypassed.

## Acceptance Criteria

1. Enabling Clipboard Reader from the Voice tab shows the toolbar.
2. Copying from Codex creates a preview item; copying from an unapproved application does not.
3. The automatic-play checkbox controls idle automatic playback.
4. A copy made during playback never interrupts current speech.
5. Clicking another history item stops current speech and plays the selected item.
6. Default history contains at most 10 memory-only items and clears at app exit.
7. The horizontal capsule can collapse, expand, hide, restore, drag, and recover on every display.
8. Voice and rate controls work; unsupported emotion remains visible and disabled.
9. Markdown, URLs, numbers, formulas, and default code skipping follow the approved preparation rules.
10. Long content is streamed by segment without silent truncation.
11. The shipped path launches no Python process.
12. Reader failures do not regress any existing TypeWhale workflow.
13. Read Webpage extracts the current article through the Chrome extension, previews it, and starts playback.
14. The extension does not inspect unrequested pages or bypass site access controls.
15. Extension absence or extraction failure clearly offers Accessibility and OCR fallbacks.
16. OCR supports rectangular region and whole window, defaults to region, and plays after successful recognition.
17. OCR screenshots are deleted locally; history stores recognized text only by default.
18. Clipboard, webpage, Accessibility, and OCR share one history, preparation, and playback system.

## Rollout

1. Finish the native audition script and select a native model candidate.
2. Implement Reader Core and the unified Reader Item behind an internal feature flag.
3. Integrate the floating panel, Voice-tab controls, clipboard source, and OCR.
4. Implement the Chrome extension, Readability protocol, and Native Messaging host.
5. Add the macOS Accessibility fallback.
6. Run installed-app listening, extension-permission, performance, privacy, and regression QA.
7. Expose the feature only after model license and packaging review.
