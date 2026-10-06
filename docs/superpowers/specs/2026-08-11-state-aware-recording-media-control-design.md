# State-Aware Recording Media Control Design

Date: 2026-08-11
Status: Product design approved in conversation; awaiting written-spec review
Milestone: Recording media control becomes state-aware and safe by default

## Product intent

The existing “录音时暂停媒体” option sends an unconditional system play/pause toggle when recording begins. If the current video or music is already paused, that toggle starts playback—the opposite of the user's intent.

This milestone changes the feature from a blind paired toggle into state-aware media control. TypeWhale must pause media only when the system explicitly reports that media is playing, and must resume only media that TypeWhale actually paused. When playback state cannot be determined reliably, TypeWhale must leave media unchanged.

## Product priorities

- P0: Starting a recording must never start media that was already paused.
- P0: Ending a recording must not pause media that the user manually resumed during recording.
- P1: Media that was playing before recording should pause at recording start and resume after the final recording ends.
- P1: Rapid consecutive recordings must not produce a playback blip between recordings.
- P1: TypeWhale-generated media events must remain isolated from OpenClaw and all configurable media-key shortcuts.

## Scope

### In scope

- Add an asynchronous playback-state provider backed by the macOS `MediaRemote` private framework.
- Load private symbols dynamically at runtime so the framework is not a hard launch dependency.
- Represent playback as a state plus a stable, nonzero now-playing process identity.
- Query state before pause and again before resume.
- Treat `paused` and `unknown` as safe no-ops at recording start.
- Resume only when TypeWhale successfully emitted the original pause toggle, the current state is still `paused`, and the now-playing process is unchanged.
- Invalidate late asynchronous callbacks when recording ends, a replacement recording starts, or a newer generation supersedes the request.
- Preserve delayed resume coalescing for consecutive recordings.
- Keep the existing synthetic-event marker and hotkey-capture isolation.
- Add diagnostics for state-query availability and decisions without logging media titles, artists, URLs, or other content.
- Record the completed behavior as a small milestone in `docs/开发日志.md` and the in-app version history.

### Out of scope

- Per-player AppleScript, browser JavaScript, or Accessibility-based player adapters.
- Reading or storing now-playing metadata.
- Supporting the Mac App Store with the private implementation. A public-only replacement or feature removal must be decided before an App Store submission.
- Changing the “录音时降低系统音量” behavior.
- Persisting media ownership across an app crash or forced termination.

### Do not touch

- Existing Smart Rewrite and capsule concept files that are dirty from unrelated sessions.
- Physical media-key and OpenClaw shortcut semantics.
- Recording, ASR, paste, screenshot, translation, and model lifecycle behavior outside the shared media-control hooks.

## Platform decision and risk boundary

Apple's public `MPNowPlayingInfoCenter` exposes playback state for the current application, not arbitrary media controlled by the system media key. A local CoreAudio probe also showed that a paused Douyin helper can remain marked as running output, so audio-process activity is not a reliable paused/playing signal.

TypeWhale will dynamically load `MRMediaRemoteGetNowPlayingApplicationIsPlaying` and `MRMediaRemoteGetNowPlayingApplicationPID` from `MediaRemote.framework`. These are private APIs and can change or disappear on a future macOS release. The provider therefore must fail closed:

- missing framework or symbol -> `unknown`;
- callback timeout or malformed response -> `unknown`;
- `unknown` -> no media-key event;
- private API failure must never delay or prevent recording.

This is acceptable for the current direct-distribution Beta milestone. It is not an approved Mac App Store implementation because App Review Guideline 2.5.1 requires public APIs.

## Architecture

### 1. Playback-state provider

Introduce a small protocol or injected closure with one responsibility:

```swift
enum SystemMediaPlaybackState {
    case playing
    case paused
    case unknown
}

struct SystemMediaPlaybackSnapshot {
    let state: SystemMediaPlaybackState
    let processID: pid_t?
}

protocol SystemMediaPlaybackStateProviding {
    func fetchSnapshot(completion: @escaping (SystemMediaPlaybackSnapshot) -> Void)
}
```

The production provider dynamically loads the framework and symbols once, performs callbacks on a controlled queue, and returns the result to the main queue. Tests inject a manual provider and never load `MediaRemote` or affect real playback.

To avoid combining state from two different players during a rapid system transition, one logical snapshot reads process ID, playback state, then process ID again. The snapshot is usable only when both process IDs are equal and nonzero. Any missing, changing, or invalid identity produces `unknown`.

No now-playing metadata is requested or retained.

### 2. Start decision

`pauseIfNeeded(enabled:)` increments a generation, cancels any pending resume, and marks the recording interval active.

- If TypeWhale already owns a paused interval from a preceding recording, keep ownership and issue no new query or toggle.
- Otherwise query a playback snapshot asynchronously.
- Apply the callback only when its generation is current and the recording interval is still active.
- `playing` with a stable process ID: emit one tagged play/pause event; mark ownership with that process ID only if emission succeeds.
- `paused` or `unknown`: do nothing and hold no ownership.

If recording cleanup happens before the asynchronous start query returns, cleanup invalidates the query. A late `playing` callback must not pause media after recording has already ended.

### 3. Resume decision

Cleanup marks the recording interval inactive. If TypeWhale does not own the pause, cleanup is a no-op.

If TypeWhale owns the pause, schedule the existing delayed resume. A replacement recording cancels that work and keeps ownership so media remains paused between recordings.

At the valid delayed callback, query a playback snapshot again:

- `paused` with the same process ID TypeWhale paused: emit one tagged play/pause event and clear ownership.
- `playing` with the same process ID: the user or another actor already resumed playback; clear ownership without emitting.
- a changed or missing process ID: clear ownership without emitting because the media target is no longer provably the same.
- `unknown`: clear ownership without emitting. This may leave media paused, but it cannot accidentally start an unrelated or already-paused item.

The safe fallback deliberately prefers a missed resume over unwanted playback.

### 4. Event and shortcut isolation

Keep `SyntheticMediaKeyEvent.eventSourceUserData` on generated key-down and key-up events. `HotkeyMonitor` and shortcut capture continue rejecting marked events before shortcut matching. Unmarked physical media keys follow the existing path unchanged.

### 5. Diagnostics

Diagnostics may record only operational values such as:

- provider available/unavailable;
- query result (`playing`, `paused`, `unknown`);
- pause/resume emitted, skipped, coalesced, or invalidated;
- generation or timeout decisions if needed for debugging.

Logs must not contain player names, song names, video titles, URLs, or other user content.

## Failure handling

- Framework or symbol missing: return `unknown`; recording continues immediately.
- Asynchronous query arrives after cleanup or replacement: ignore it through a generation guard.
- Event creation/posting fails: do not claim ownership; never attempt a paired resume.
- User resumes playback during recording: end query sees `playing`, clears ownership, and sends no toggle.
- The current media process exits or changes during recording: end query sees a different or missing process ID, clears ownership, and sends no toggle.
- User starts another recording before delayed resume: cancel resume and preserve owned pause.
- State is unknown at resume: send nothing and clear ownership to avoid a later unrelated toggle.

## Automated verification

Required state-machine regression cases use injected state and event providers:

1. Paused before start -> zero events at start and finish.
2. Unknown before start -> zero events at start and finish.
3. Playing before start -> one pause event; paused before finish -> one resume event.
4. Playing before start -> one pause event; playing before finish -> no resume event.
5. Playing before start -> one pause event; a different or missing process before finish -> no resume event.
6. Process ID changes while a snapshot is being assembled -> snapshot becomes unknown and emits nothing.
7. Start query returns after cleanup -> zero events.
8. Start query from an older recording returns after replacement -> ignored.
9. Consecutive recording cancels pending resume -> no intermediate event; final paused state resumes once.
10. Duplicate cleanup remains idempotent.
11. Provider unavailable or timed out -> safe no-op.
12. Tagged synthetic events do not trigger OpenClaw or hotkey capture; physical events still work.
13. Existing output-volume restore tests remain green.

## Installed-app acceptance

Using `/Applications/TypeWhale Pro.app` with “录音时暂停媒体” enabled:

1. Pause a browser video, Douyin video, or Music track. Start and finish recording. The media remains paused throughout.
2. Play the same media. Start recording. Playback pauses; after the final recording finishes, playback resumes.
3. While TypeWhale has paused media, manually resume it. Finish recording. TypeWhale does not pause it again.
4. While TypeWhale has paused media, close that player or switch the system now-playing target. Finish recording. TypeWhale does not start the replacement target.
5. Start a second recording before the delayed resume. Playback does not blip between recordings and resumes once after the final finish.
6. Bind OpenClaw to the headset play key. TypeWhale's automatic controls never activate OpenClaw; a physical key press still does.
7. Disable the setting. Recording never changes media playback.
8. Test with a player that does not report reliable system state. TypeWhale leaves it unchanged instead of guessing.

Any start of previously paused media, any final toggle that pauses user-resumed playback, any generated-event activation of OpenClaw, or any late toggle after recording cleanup is a release blocker.

## Milestone record

The implementation release note will describe this as the point where recording media control changes from blind toggle pairing to state-aware ownership:

- only confirmed playing media is paused;
- only a pause owned by TypeWhale and still targeting the same media process can be resumed;
- unknown state fails safely without changing playback;
- user playback decisions and physical media shortcuts remain authoritative.
