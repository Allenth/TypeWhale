# Recording Media Pause and Volume Restore Design

Date: 2026-08-10
Status: Product design approved in conversation; awaiting written-spec review

## Product intent

TypeWhale currently offers “录音时降低系统音量”. A delayed restore clears its saved baseline too early, so a second recording started before restoration can capture the already-ducked volume as the new baseline. The final restore then leaves the Mac at the ducked volume.

This change must fix that defect and add a separate, opt-in “录音时暂停媒体” setting. When media was playing before a recording, TypeWhale sends the system play/pause control at recording start and sends the paired control after the recording ends so playback continues. Consecutive recordings must remain quiet between sessions rather than briefly restoring audio.

## Scope

### In scope

- Preserve the first pre-recording system-volume baseline until a delayed/ramped restore truly completes or is abandoned because the user changed volume.
- Add an independent “录音时暂停媒体” switch beside the existing system-volume switch. It defaults to off.
- Send a paired system play/pause media-key event for recording start and final cleanup.
- Coalesce consecutive recordings: a new recording cancels pending media resume and volume restore while retaining their original ownership/baselines.
- Cover normal finish, cancellation, recording-start failure, replacement recording, and cleanup paths.
- Mark TypeWhale-generated media events so the app's own hotkey monitor ignores them.
- Preserve real headset play-button shortcuts for dictation, OpenClaw, screenshots, translation, and other configurable actions.
- Add diagnostics for media pause/resume requests and restore coalescing without logging user content.

### Out of scope

- Private `MediaRemote` framework use.
- Per-player AppleScript integrations.
- Detecting or controlling every independent audio source on the Mac.
- Persisting audio/media restoration across an app crash or force quit.
- Changing the existing fixed 5% ducked-volume target.

### Do not touch

- Smart Rewrite and capsule concept work currently present as unrelated dirty files.
- Existing OpenClaw activation semantics and user-selected shortcuts.
- Recording, ASR, paste, translation, and screenshot behavior except for the shared recording-start/cleanup hooks required here.

## Important platform boundary

macOS exposes the system play/pause control as a toggle, not as a public cross-app “pause this player” and “play this player” API. The option is therefore intended for the common case where media is already playing when recording starts. If no media is playing, or the user manually changes playback during recording, the system's toggle semantics can produce a different result. The switch remains off by default and its help text must describe it as controlling the current system media.

TypeWhale will not use private frameworks to infer Now Playing state because that would create commercial signing, notarization, and future macOS compatibility risk.

## Design

### 1. Volume restore ownership

`OutputAudioDucker` will retain its volume snapshots while restore is pending or ramping. `restore()` schedules work but does not immediately discard the original baseline.

When another recording begins before restore completes:

1. Cancel pending restore work.
2. Keep the first pre-recording baseline.
3. If the current volume still matches the last value TypeWhale applied, lower it back to the ducked target and continue using the first baseline.
4. If the current volume no longer matches the last TypeWhale-applied value, treat that as user intent. Replace the stale ownership with a new snapshot based on the user's current volume before ducking the new recording.

Each delayed/ramp callback carries a generation guard so a cancelled old callback cannot mutate volume or discard state after a newer recording starts. A snapshot is removed only after its final restore step, an explicit user-override decision, or an unreadable/unsupported output control.

### 2. Recording media controller

A focused media controller owns one Boolean/session state: whether TypeWhale currently owns a paired media toggle, plus any pending resume work item and generation.

On recording start with the setting enabled:

- Cancel pending resume.
- If TypeWhale already owns the paused interval from a preceding recording, keep it and do not send another toggle.
- Otherwise send one media-key down/up pair and record ownership.

On recording cleanup:

- If TypeWhale owns the paused interval, schedule the paired toggle after a short coalescing delay.
- If a new recording starts during that delay, cancel the resume and keep ownership.
- At the valid delayed callback, send one media-key down/up pair and clear ownership.

The cleanup operation is idempotent. Duplicate cleanup calls cannot send duplicate resume events.

### 3. Synthetic-event isolation

The media-key emitter assigns a TypeWhale-specific `eventSourceUserData` marker to both generated events. `HotkeyMonitor.handleSystemDefined` checks that marker before matching any user binding and returns without consuming or dispatching the event internally.

This prevents a generated pause/resume event from activating OpenClaw or any other TypeWhale action when that action is bound to “耳机播放键”. Physical headset events do not carry the marker and continue through the existing shortcut path unchanged.

The hotkey-capture UI must also ignore tagged synthetic events, so opening shortcut capture while media cleanup runs cannot accidentally save a media-key binding.

### 4. Settings and UI

Add `pauseSystemMediaWhileRecordingEnabled` to the existing `AppSettings` load/save boundary. The persisted key is independent of `duckSystemAudioWhileRecordingEnabled` and defaults to `false`.

Add one `BrandSwitch` row labeled “录音时暂停媒体” in the same recording/settings group as “录音时降低系统音量”. Both switches may be enabled together. Accessibility labels and help text must explain that the option toggles the current system media at recording start/end.

### 5. Coordinator integration

The speech coordinator calls both audio policies from the same lifecycle boundaries:

- immediately before recorder startup: request media pause and volume duck;
- unified recording cleanup: request delayed media resume and volume restore.

If recorder startup throws, existing cleanup must restore both owned resources. Purpose-specific flows, including OpenClaw recording, share the same lifecycle and do not add independent media logic.

## Failure handling

- Media-event creation failure is logged and must never block recording.
- An unreadable or software-volume-incompatible output device remains a silent no-op for volume ducking.
- User volume changes continue to outrank TypeWhale restoration.
- Cancelled generations do no work even if their dispatch block reaches the main queue.
- Turning either setting off affects future starts; cleanup still releases any state TypeWhale already owns.

## Automated verification

Behavioral tests use injected/fake volume and media-event backends so they never change the developer Mac's real volume or playback.

Required regression cases:

1. Volume 70% -> duck -> restore pending -> second duck -> final restore returns to 70%, never 5%.
2. A second recording during a partial ramp returns to the first 70% baseline.
3. User changes volume during recording; TypeWhale does not overwrite it on restore.
4. One media start/finish emits exactly one pause pair and one resume pair.
5. Consecutive recording cancels pending resume, emits no intermediate toggle, and resumes once after the final finish.
6. Duplicate cleanup is idempotent.
7. Disabled switches produce no volume or media event.
8. Tagged media events never trigger OpenClaw or other media-key bindings.
9. Untagged physical media events retain current shortcut behavior.
10. Setting persistence, layout boundary, accessibility label, startup failure, cancellation, and coordinator wiring checks pass.

## Installed-app acceptance

Using `/Applications/TypeWhale Pro.app`:

1. Enable only “录音时降低系统音量”, set system volume to a clearly audible level, perform several rapid consecutive recordings, then wait for cleanup. Volume returns to the first pre-recording level.
2. Change volume manually during recording. Cleanup preserves the user's new volume.
3. Enable only “录音时暂停媒体”, start playback in Apple Music and in a browser video, record once, and confirm pause at start and continuation after finish.
4. Start another recording before delayed media continuation. No audio blip occurs between recordings; media continues only after the final finish.
5. Bind OpenClaw to a normal key, then to “耳机播放键”. Generated pause/resume events never open or stop OpenClaw; a physical headset play-button press still activates the configured action.
6. Enable both switches and repeat normal finish, cancel, and forced recording-start failure paths.
7. Disable both switches and confirm recording never modifies volume or media playback.

Any OpenClaw activation caused by generated media events, a final volume left at 5%, duplicate media toggles, intermediate playback between consecutive sessions, or failure to restore after normal cleanup is a release blocker.
