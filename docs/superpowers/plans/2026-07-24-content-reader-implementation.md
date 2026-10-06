# TypeWhale Content Reader Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build TypeWhale’s production Content Reader so authorized clipboard text, user-selected OCR text, accessible browser text, and Chrome-extracted articles share one local preview, history, preparation, and native playback flow.

**Architecture:** A new Reader domain and application layer owns source-neutral `ReaderItem` values, history, text preparation, selection, and playback policy. Platform adapters acquire clipboard, Accessibility, OCR, and Chrome article text; presentation code binds a draggable floating panel and Voice-tab settings to the same coordinator. TTS uses a dedicated Reader service over the existing packaged native Sherpa runtime and never routes through OpenClaw or Python.

**Tech Stack:** Swift 5 / AppKit / AVFoundation / ApplicationServices / Vision, sherpa-onnx native CLI and C runtime, Chrome Manifest V3, JavaScript, Mozilla Readability, Chrome Native Messaging, repository Swift check executables and shell boundary checks.

## Global Constraints

- macOS deployment target remains `arm64-apple-macosx14.0`.
- Production Reader TTS must not launch Python, `pip`, or a virtual environment.
- Clipboard, webpage, Accessibility, and OCR content remain local.
- New clipboard content never interrupts active playback.
- Explicit item selection, Read Webpage, and successful OCR stop current playback and play the selected result.
- Clipboard autoplay applies only while the player is idle.
- History defaults to 10 memory-only items; persistence is opt-in.
- OCR screenshots are deleted after success, cancellation, or failure; history stores text only.
- Chrome extraction happens only after the user clicks Read Webpage and must not bypass login, paywalls, CAPTCHA, or site permissions.
- Safari extension and a general plugin platform remain out of scope.
- Existing ASR, screenshot translation, OpenClaw, paste, and hotkey behavior must not regress.

---

## Milestone 1 — Reader Core, Clipboard, Native Playback, And Floating Panel

### Task 1: Source-Neutral Reader Domain And Settings

**Files:**
- Create: `native/Sources/Domain/Reader/ReaderItem.swift`
- Create: `native/Sources/Domain/Reader/ReaderPlaybackState.swift`
- Create: `native/Sources/Infrastructure/Reader/ReaderSettings.swift`
- Test: `native/Tests/ReaderDomainCheck.swift`
- Test: `native/Tests/ReaderSettingsCheck.swift`

**Interfaces:**
- Produces: `ReaderSourceKind`, `ReaderSourceMetadata`, `ReaderItem`, `ReaderPlaybackState`, `ReaderSettings`, `ReaderSettingsStore`.
- `ReaderItem` stores `id`, `source`, `originalText`, `speechText`, `createdAt`, and preparation annotations.

- [ ] **Step 1: Write the failing domain check**

```swift
import Foundation

@main
struct ReaderDomainCheck {
    static func main() {
        let item = ReaderItem(
            source: .init(kind: .webpage, displayName: "Chrome", title: "课程", url: URL(string: "https://example.com/a?q=1")),
            originalText: "原文",
            speechText: "朗读文字",
            annotations: [.codeSkipped]
        )
        precondition(item.source.kind == .webpage)
        precondition(item.originalText == "原文")
        precondition(item.speechText == "朗读文字")
        precondition(item.annotations == [.codeSkipped])
        precondition(ReaderPlaybackState.idle.canAcceptAutomaticItem)
        precondition(!ReaderPlaybackState.playing(item.id).canAcceptAutomaticItem)
        print("ReaderDomainCheck passed")
    }
}
```

- [ ] **Step 2: Run the domain check and verify RED**

Run:

```bash
xcrun swiftc native/Tests/ReaderDomainCheck.swift -o /tmp/ReaderDomainCheck
```

Expected: compile failure because the Reader domain types do not exist.

- [ ] **Step 3: Implement the domain types**

```swift
enum ReaderSourceKind: String, Codable, CaseIterable {
    case clipboard, webpage, accessibility, ocr
}

struct ReaderSourceMetadata: Codable, Equatable {
    let kind: ReaderSourceKind
    let displayName: String
    let title: String?
    let url: URL?
}

struct ReaderPreparationAnnotation: OptionSet, Codable {
    let rawValue: Int
    static let codeSkipped = Self(rawValue: 1 << 0)
}

struct ReaderItem: Identifiable, Codable, Equatable {
    let id: UUID
    let source: ReaderSourceMetadata
    let originalText: String
    let speechText: String
    let annotations: ReaderPreparationAnnotation
    let createdAt: Date
}

enum ReaderPlaybackState: Equatable {
    case idle, preparing(UUID), playing(UUID), paused(UUID), stopping(UUID), failed(UUID?, String)
    var canAcceptAutomaticItem: Bool { self == .idle }
}
```

- [ ] **Step 4: Write the failing settings check**

```swift
let suite = "ReaderSettingsCheck.\(UUID())"
let defaults = UserDefaults(suiteName: suite)!
defer { defaults.removePersistentDomain(forName: suite) }
let store = ReaderSettingsStore(defaults: defaults)
precondition(store.load() == .default)
var settings = ReaderSettings.default
settings.isEnabled = true
settings.historyLimit = 25
settings.authorizedBundleIdentifiers = ["com.openai.codex"]
store.save(settings)
precondition(store.load() == settings)
```

- [ ] **Step 5: Run the settings check and verify RED**

Run:

```bash
xcrun swiftc native/Tests/ReaderSettingsCheck.swift -o /tmp/ReaderSettingsCheck
```

Expected: compile failure because `ReaderSettingsStore` is missing.

- [ ] **Step 6: Implement normalized settings and persistence**

```swift
struct ReaderSettings: Codable, Equatable {
    var isEnabled: Bool
    var autoplayClipboard: Bool
    var historyLimit: Int
    var persistsHistory: Bool
    var readsCode: Bool
    var speechRate: Double
    var volume: Double
    var authorizedBundleIdentifiers: Set<String>

    static let `default` = Self(
        isEnabled: false,
        autoplayClipboard: true,
        historyLimit: 10,
        persistsHistory: false,
        readsCode: false,
        speechRate: 1.0,
        volume: 0.8,
        authorizedBundleIdentifiers: ["com.openai.codex"]
    )
}
```

Persist one JSON value and normalize before saving:

```swift
private let key = "contentReader.settings.v1"

func save(_ value: ReaderSettings) {
    var normalized = value
    normalized.historyLimit = min(100, max(1, value.historyLimit))
    normalized.speechRate = min(1.75, max(0.75, value.speechRate))
    normalized.volume = min(1.5, max(0, value.volume))
    defaults.set(try? JSONEncoder().encode(normalized), forKey: key)
}
```

- [ ] **Step 7: Run both checks and verify GREEN**

Run:

```bash
xcrun swiftc native/Sources/Domain/Reader/ReaderItem.swift native/Sources/Domain/Reader/ReaderPlaybackState.swift native/Tests/ReaderDomainCheck.swift -o /tmp/ReaderDomainCheck && /tmp/ReaderDomainCheck
xcrun swiftc native/Sources/Infrastructure/Reader/ReaderSettings.swift native/Tests/ReaderSettingsCheck.swift -o /tmp/ReaderSettingsCheck && /tmp/ReaderSettingsCheck
```

Expected: both print `passed`.

- [ ] **Step 8: Commit**

```bash
git add native/Sources/Domain/Reader native/Sources/Infrastructure/Reader/ReaderSettings.swift native/Tests/ReaderDomainCheck.swift native/Tests/ReaderSettingsCheck.swift
git commit -m "feat: add content reader domain and settings"
```

### Task 2: Text Preparation And History

**Files:**
- Create: `native/Sources/Application/Reader/ReaderTextPreparer.swift`
- Create: `native/Sources/Application/Reader/ReaderHistoryStore.swift`
- Test: `native/Tests/ReaderTextPreparerCheck.swift`
- Test: `native/Tests/ReaderHistoryStoreCheck.swift`

**Interfaces:**
- Consumes: `ReaderItem`, `ReaderPreparationAnnotation`, `ReaderSettings`.
- Produces: `ReaderPreparedText`, `ReaderTextPreparer.prepare(_:readsCode:)`, `ReaderHistoryStore.insert(_:)`, `items`, `clear()`.

- [ ] **Step 1: Write failing text-preparation cases**

```swift
let preparer = ReaderTextPreparer()
let result = preparer.prepare("""
# 标题
价格是 20,000 × 15% = 3,000。
[官网](https://example.com)
```swift
print("skip")
```
""", readsCode: false)
precondition(result.speechText.contains("两万乘以百分之十五，等于三千"))
precondition(result.speechText.contains("官网"))
precondition(!result.speechText.contains("https://"))
precondition(!result.speechText.contains("print"))
precondition(result.annotations.contains(.codeSkipped))
```

- [ ] **Step 2: Verify RED**

Run:

```bash
xcrun swiftc native/Sources/Domain/Reader/ReaderItem.swift native/Tests/ReaderTextPreparerCheck.swift -o /tmp/ReaderTextPreparerCheck
```

Expected: compile failure for missing `ReaderTextPreparer`.

- [ ] **Step 3: Implement deterministic preparation**

Implement ordered transforms:

```swift
func prepare(_ original: String, readsCode: Bool) -> ReaderPreparedText {
    let normalized = normalizeNewlines(original)
    let withoutCode = readsCode ? normalized : removeFencedAndIndentedCode(normalized)
    let withoutMarkdown = replaceMarkdownLinksAndMarkers(withoutCode.text)
    let naturalMath = naturalizeCommonMath(withoutMarkdown)
    return .init(
        speechText: collapseForSpeech(naturalMath),
        annotations: withoutCode.didSkip ? [.codeSkipped] : []
    )
}
```

Keep each transform private and deterministic. Do not truncate.

- [ ] **Step 4: Run and verify GREEN**

Run:

```bash
xcrun swiftc native/Sources/Domain/Reader/ReaderItem.swift native/Sources/Application/Reader/ReaderTextPreparer.swift native/Tests/ReaderTextPreparerCheck.swift -o /tmp/ReaderTextPreparerCheck && /tmp/ReaderTextPreparerCheck
```

Expected: `ReaderTextPreparerCheck passed`.

- [ ] **Step 5: Write failing history cases**

```swift
let store = ReaderHistoryStore(limit: 2, persistenceURL: nil)
store.insert(item("A"))
store.insert(item("A"))
store.insert(item("B"))
store.insert(item("C"))
precondition(store.items.map(\.originalText) == ["C", "B"])
store.clear()
precondition(store.items.isEmpty)
```

- [ ] **Step 6: Verify RED**

Expected: compile failure for missing `ReaderHistoryStore`.

- [ ] **Step 7: Implement bounded memory and opt-in JSON persistence**

```swift
@MainActor
final class ReaderHistoryStore {
    private(set) var items: [ReaderItem] = []
    func insert(_ item: ReaderItem) {
        if items.first?.originalText == item.originalText && items.first?.source.kind == item.source.kind {
            items[0] = item
        } else {
            items.insert(item, at: 0)
        }
        items = Array(items.prefix(limit))
        persistIfEnabled()
    }
}
```

Use user-only file permissions for the opt-in JSON file and never log item text.

- [ ] **Step 8: Run both checks and commit**

```bash
xcrun swiftc native/Sources/Domain/Reader/ReaderItem.swift native/Sources/Application/Reader/ReaderHistoryStore.swift native/Tests/ReaderHistoryStoreCheck.swift -o /tmp/ReaderHistoryStoreCheck && /tmp/ReaderHistoryStoreCheck
git add native/Sources/Application/Reader native/Tests/ReaderTextPreparerCheck.swift native/Tests/ReaderHistoryStoreCheck.swift
git commit -m "feat: prepare and retain reader content"
```

### Task 3: Playback Policy And Native Reader TTS

**Files:**
- Create: `native/Sources/Application/Reader/ReaderPlaybackCoordinator.swift`
- Create: `native/Sources/Infrastructure/Reader/ReaderNativeTTSService.swift`
- Create: `native/Sources/Infrastructure/Reader/SherpaNativeSynthesisProcess.swift`
- Modify: `native/Sources/Infrastructure/OpenClaw/SherpaNativeTTSBackend.swift`
- Test: `native/Tests/ReaderPlaybackCoordinatorCheck.swift`
- Test: `native/Tests/ReaderNativeTTSServiceCheck.swift`
- Test: `native/Tests/ReaderNativeTTSBoundaryCheck.sh`

**Interfaces:**
- Produces: `ReaderSynthesizing`, `ReaderPlaybackCoordinator.play(_:intent:)`, `pause()`, `resume()`, `stop()`.
- `ReaderPlaybackIntent` is `.automaticClipboard` or `.explicitSelection`.
- Native synthesis consumes prepared segments and produces temporary WAV files.

- [ ] **Step 1: Write the failing playback-policy check**

```swift
let synth = RecordingReaderSynthesizer()
let coordinator = ReaderPlaybackCoordinator(synthesizer: synth)
coordinator.play(item("A"), intent: .automaticClipboard)
coordinator.play(item("B"), intent: .automaticClipboard)
precondition(synth.playedTexts == ["A"])
coordinator.play(item("B"), intent: .explicitSelection)
precondition(synth.cancelCount == 1)
precondition(synth.playedTexts == ["A", "B"])
```

- [ ] **Step 2: Verify RED**

Expected: compile failure for missing coordinator and protocol.

- [ ] **Step 3: Implement the policy state machine**

```swift
func play(_ item: ReaderItem, intent: ReaderPlaybackIntent) {
    if intent == .automaticClipboard, !state.canAcceptAutomaticItem { return }
    if intent == .explicitSelection, state != .idle { synthesizer.cancel() }
    activeItem = item
    state = .preparing(item.id)
    synthesizer.play(item: item, rate: settings.speechRate, volume: settings.volume, callbacks: callbacks)
}
```

Callbacks must transition preparing → playing → idle/failed and delete completed temporary audio.

- [ ] **Step 4: Run policy check and verify GREEN**

Expected: `ReaderPlaybackCoordinatorCheck passed`.

- [ ] **Step 5: Write the failing native-service check**

Create a fake executable that records arguments and writes `RIFFfakeWAVE`. Assert:

```swift
try service.synthesize(
    text: "本地朗读",
    rate: 1.25,
    outputURL: output
)
precondition(FileManager.default.fileExists(atPath: output.path))
precondition(arguments.contains("--vits-model="))
precondition(arguments.contains("--output-filename="))
precondition(arguments.contains("--speed=0.8"))
```

- [ ] **Step 6: Verify RED**

Expected: compile failure for missing `ReaderNativeTTSService`.

- [ ] **Step 7: Extract the shared Sherpa process runner**

`SherpaNativeSynthesisProcess` owns executable validation, process launch, cancellation, timeout, and output-file validation. `SherpaNativeTTSBackend` and `ReaderNativeTTSService` create their own argument lists but share the runner. Reader code must not import or mention OpenClaw types.

- [ ] **Step 8: Add the Python boundary check**

```bash
READER_DIR="$ROOT/native/Sources/Infrastructure/Reader"
! rg -n 'python|pip|venv|openclaw_tts_worker' "$READER_DIR"
rg -n 'sherpa-onnx-offline-tts|SherpaNativeSynthesisProcess' "$READER_DIR"
```

- [ ] **Step 9: Run native checks and commit**

```bash
bash native/Tests/ReaderNativeTTSBoundaryCheck.sh
xcrun swiftc -framework AVFoundation native/Sources/Domain/Reader/ReaderItem.swift native/Sources/Domain/Reader/ReaderPlaybackState.swift native/Sources/Application/Reader/ReaderPlaybackCoordinator.swift native/Tests/ReaderPlaybackCoordinatorCheck.swift -o /tmp/ReaderPlaybackCoordinatorCheck && /tmp/ReaderPlaybackCoordinatorCheck
xcrun swiftc native/Sources/Infrastructure/Reader/SherpaNativeSynthesisProcess.swift native/Sources/Infrastructure/Reader/ReaderNativeTTSService.swift native/Tests/ReaderNativeTTSServiceCheck.swift -o /tmp/ReaderNativeTTSServiceCheck && /tmp/ReaderNativeTTSServiceCheck
bash native/Tests/SherpaNativeTTSBackendSourceCheck.sh
git add native/Sources/Application/Reader/ReaderPlaybackCoordinator.swift native/Sources/Infrastructure/Reader native/Sources/Infrastructure/OpenClaw/SherpaNativeTTSBackend.swift native/Tests/ReaderPlaybackCoordinatorCheck.swift native/Tests/ReaderNativeTTSServiceCheck.swift native/Tests/ReaderNativeTTSBoundaryCheck.sh
git commit -m "feat: add native content reader playback"
```

### Task 4: Authorized Clipboard Acquisition And Reader Coordinator

**Files:**
- Create: `native/Sources/Application/Reader/ReaderSourceCoordinator.swift`
- Create: `native/Sources/Infrastructure/Reader/ClipboardTextSource.swift`
- Create: `native/Sources/Application/Reader/ContentReaderCoordinator.swift`
- Test: `native/Tests/ClipboardTextSourceCheck.swift`
- Test: `native/Tests/ContentReaderCoordinatorCheck.swift`

**Interfaces:**
- Produces: `ReaderAcquiredContent`, `ReaderContentSource`, `ClipboardTextSource.poll()`, `ContentReaderCoordinator.start()`, `stop()`, `accept(_:intent:)`.

- [ ] **Step 1: Write failing clipboard source cases**

Use injected pasteboard and frontmost-application closures. Verify startup content is ignored, unauthorized bundles are ignored, plain text from `com.openai.codex` is accepted, and a consecutive duplicate is ignored.

- [ ] **Step 2: Verify RED**

Expected: missing `ClipboardTextSource`.

- [ ] **Step 3: Implement polling without clipboard mutation**

```swift
func poll() -> ReaderAcquiredContent? {
    guard pasteboard.changeCount != baselineChangeCount else { return nil }
    baselineChangeCount = pasteboard.changeCount
    guard let app = frontmostApplication(),
          authorizedBundleIdentifiers().contains(app.bundleIdentifier),
          let text = pasteboard.string(forType: .string),
          !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          text != lastAcceptedText else { return nil }
    lastAcceptedText = text
    return .init(text: text, source: .clipboard(app.localizedName, app.bundleIdentifier))
}
```

- [ ] **Step 4: Run clipboard check and verify GREEN**

Expected: `ClipboardTextSourceCheck passed`.

- [ ] **Step 5: Write coordinator check**

Assert that accepted content is prepared, inserted into history, surfaced to observers, and autoplayed only when settings enable clipboard autoplay and playback is idle.

- [ ] **Step 6: Implement `ContentReaderCoordinator`**

It owns settings, source polling timer, history, preparer, and playback. Expose main-actor callbacks:

```swift
var onSnapshotChange: ((ReaderSnapshot) -> Void)?
var snapshot: ReaderSnapshot { get }
func selectAndPlay(_ id: UUID)
func playCurrent()
func pause()
func resume()
func stopPlayback()
func clearHistory()
```

- [ ] **Step 7: Run checks and commit**

```bash
xcrun swiftc -framework AppKit native/Sources/Domain/Reader/ReaderItem.swift native/Sources/Application/Reader/ReaderSourceCoordinator.swift native/Sources/Infrastructure/Reader/ClipboardTextSource.swift native/Tests/ClipboardTextSourceCheck.swift -o /tmp/ClipboardTextSourceCheck && /tmp/ClipboardTextSourceCheck
xcrun swiftc -framework AVFoundation native/Sources/Domain/Reader/ReaderItem.swift native/Sources/Domain/Reader/ReaderPlaybackState.swift native/Sources/Infrastructure/Reader/ReaderSettings.swift native/Sources/Application/Reader/ReaderTextPreparer.swift native/Sources/Application/Reader/ReaderHistoryStore.swift native/Sources/Application/Reader/ReaderPlaybackCoordinator.swift native/Sources/Application/Reader/ReaderSourceCoordinator.swift native/Sources/Application/Reader/ContentReaderCoordinator.swift native/Tests/ContentReaderCoordinatorCheck.swift -o /tmp/ContentReaderCoordinatorCheck && /tmp/ContentReaderCoordinatorCheck
git add native/Sources/Application/Reader native/Sources/Infrastructure/Reader/ClipboardTextSource.swift native/Tests/ClipboardTextSourceCheck.swift native/Tests/ContentReaderCoordinatorCheck.swift
git commit -m "feat: ingest authorized clipboard text"
```

### Task 5: Draggable Floating Reader Panel

**Files:**
- Create: `native/Sources/Presentation/Reader/ReaderFloatingPanelController.swift`
- Create: `native/Sources/Presentation/Reader/ReaderFloatingView.swift`
- Create: `native/Sources/Presentation/Reader/ReaderPanelLayout.swift`
- Test: `native/Tests/ReaderPanelLayoutCheck.swift`
- Test: `native/Tests/ReaderPanelBoundaryCheck.sh`

**Interfaces:**
- Consumes: `ContentReaderCoordinator`, `ReaderSnapshot`.
- Produces: compact/expanded horizontal capsule, source summary, preview/history, voice/rate/volume/autoplay controls, source action callbacks.

- [ ] **Step 1: Write failing pure layout check**

```swift
let compact = ReaderPanelLayout.frame(for: .collapsed, screenVisibleFrame: screen, preferredOrigin: farOutside)
precondition(screen.contains(compact))
let expanded = ReaderPanelLayout.frame(for: .expanded, screenVisibleFrame: screen, preferredOrigin: farOutside)
precondition(screen.contains(expanded))
precondition(expanded.width > compact.width)
```

- [ ] **Step 2: Verify RED**

Expected: missing layout type.

- [ ] **Step 3: Implement layout and per-display recovery**

Use a pure clamp function and store origins under `contentReader.panelOrigin.<displayID>`. Default to the lower-right safe area. Re-clamp on screen parameter changes.

- [ ] **Step 4: Run layout check and verify GREEN**

Expected: `ReaderPanelLayoutCheck passed`.

- [ ] **Step 5: Write panel boundary assertions**

Check for `.nonactivatingPanel`, `.canJoinAllSpaces`, dedicated drag handle, explicit `setAccessibilityLabel`, collapse/expand/hide controls, and absence of clipboard/TTS implementation code in Presentation.

- [ ] **Step 6: Build the panel**

`ReaderFloatingView` uses AppKit controls and exposes closures:

```swift
var onPlay: (() -> Void)?
var onPauseResume: (() -> Void)?
var onStop: (() -> Void)?
var onSelectItem: ((UUID) -> Void)?
var onAutoplayChange: ((Bool) -> Void)?
var onReadWebpage: (() -> Void)?
var onOCR: (() -> Void)?
```

Unsupported emotion stays visible and disabled with the approved explanation.

- [ ] **Step 7: Run boundary check and commit**

```bash
bash native/Tests/ReaderPanelBoundaryCheck.sh
git add native/Sources/Presentation/Reader native/Tests/ReaderPanelLayoutCheck.swift native/Tests/ReaderPanelBoundaryCheck.sh
git commit -m "feat: add floating content reader panel"
```

### Task 6: Voice Tab, Menu Bar, And App Lifecycle Wiring

**Files:**
- Modify: `native/TypeSpeakerApp.swift`
- Modify: `native/Sources/Application/AppLifecycleCoordinator.swift`
- Modify: `native/Sources/Presentation/Main/MainViewController.swift`
- Modify: `native/Sources/Presentation/Main/MainViewController+Configuration.swift`
- Modify: `native/Sources/Presentation/Main/MainViewController+PanelLayout.swift`
- Modify: `native/Sources/Presentation/Main/MainViewController+Actions.swift`
- Test: `native/Tests/ContentReaderWiringCheck.sh`

**Interfaces:**
- AppDelegate owns one `ContentReaderCoordinator` and one `ReaderFloatingPanelController`.
- Voice tab edits `ReaderSettingsStore`; the menu item calls `showReaderPanel()`.

- [ ] **Step 1: Write failing wiring assertions**

Require:

```bash
rg -n 'ContentReaderCoordinator' native/TypeSpeakerApp.swift
rg -n '显示朗读工具条' native/Sources/Application/AppLifecycleCoordinator.swift
rg -n '内容朗读' native/Sources/Presentation/Main/MainViewController+PanelLayout.swift
rg -n 'readerEnabledSwitch|readerAutoplaySwitch|readerShowPanelButton' native/Sources/Presentation/Main
```

- [ ] **Step 2: Verify RED**

Expected: boundary script exits non-zero.

- [ ] **Step 3: Wire lifecycle and settings**

Add explicit closures to `AppLifecycleCoordinator`:

```swift
var onShowReaderPanel: (() -> Void)?
```

Create the coordinator only after `AppPaths.prepare()`, start it when enabled, and stop playback/source polling at app termination.

- [ ] **Step 4: Add Voice-tab controls**

Add master enable, show toolbar, autoplay, read code, history limit, persist history, rate, volume, model state, and Chrome connection state. Changes save normalized settings and immediately refresh the coordinator.

- [ ] **Step 5: Run wiring and compile-only build**

```bash
bash native/Tests/ContentReaderWiringCheck.sh
./native/build_native_app.sh
```

Expected: all checks pass and the app compiles. Do not install yet; milestones 2 and 3 still change production code.

- [ ] **Step 6: Commit**

```bash
git add native/TypeSpeakerApp.swift native/Sources/Application/AppLifecycleCoordinator.swift native/Sources/Presentation/Main native/Tests/ContentReaderWiringCheck.sh
git commit -m "feat: integrate content reader controls"
```

---

## Milestone 2 — OCR And Accessibility Sources

### Task 7: Reader OCR From Existing Screenshot Selection

**Files:**
- Modify: `native/Sources/Presentation/Screenshot/ScreenshotCoordinator.swift`
- Modify: `native/Sources/Application/SpeechInputCoordinator.swift`
- Create: `native/Sources/Infrastructure/Reader/OCRCaptureSource.swift`
- Test: `native/Tests/ReaderOCRSourceCheck.swift`
- Test: `native/Tests/ReaderOCRWiringCheck.sh`

**Interfaces:**
- Produces: `ScreenshotCoordinator.beginReaderOCR(mode:onRecognized:)`.
- `OCRCaptureSource` converts successful recognized text to `ReaderAcquiredContent`.

- [ ] **Step 1: Write failing OCR source check**

```swift
let source = OCRCaptureSource()
let acquired = source.makeContent(recognizedText: "  网页文字  ")
precondition(acquired?.text == "网页文字")
precondition(acquired?.source.kind == .ocr)
precondition(source.makeContent(recognizedText: " \n ") == nil)
```

- [ ] **Step 2: Verify RED**

Expected: missing source type.

- [ ] **Step 3: Implement text-only OCR adapter**

The adapter must not accept, store, or persist image data.

- [ ] **Step 4: Add the reader-specific screenshot completion**

Refactor the existing OCR path to share recognition but keep current “copy OCR to clipboard” behavior unchanged. Reader mode calls the completion with recognized text and does not write the clipboard.

- [ ] **Step 5: Add region/window entry**

The Reader toolbar defaults to rectangular selection and exposes window selection through the existing visible-window candidate path. Cancel and low-confidence/empty results return a typed failure without creating a Reader Item.

- [ ] **Step 6: Run existing screenshot checks plus Reader checks**

```bash
bash native/Tests/ScreenshotArchitectureBoundaryCheck.sh
xcrun swiftc native/Sources/Domain/Reader/ReaderItem.swift native/Sources/Application/Reader/ReaderSourceCoordinator.swift native/Sources/Infrastructure/Reader/OCRCaptureSource.swift native/Tests/ReaderOCRSourceCheck.swift -o /tmp/ReaderOCRSourceCheck && /tmp/ReaderOCRSourceCheck
bash native/Tests/ReaderOCRWiringCheck.sh
```

- [ ] **Step 7: Commit**

```bash
git add native/Sources/Presentation/Screenshot/ScreenshotCoordinator.swift native/Sources/Application/SpeechInputCoordinator.swift native/Sources/Infrastructure/Reader/OCRCaptureSource.swift native/Tests/ReaderOCRSourceCheck.swift native/Tests/ReaderOCRWiringCheck.sh
git commit -m "feat: read selected screen text with OCR"
```

### Task 8: Accessibility Visible-Text Fallback

**Files:**
- Create: `native/Sources/Infrastructure/Reader/AccessibilityTextSource.swift`
- Test: `native/Tests/AccessibilityTextSourceCheck.swift`

**Interfaces:**
- Produces: `AccessibilityTreeReading`, `AccessibilityTextSource.acquireVisibleText()`.
- Returns a typed `ReaderSourceError.permissionRequired`, `.empty`, or content.

- [ ] **Step 1: Write failing tree-flattening tests**

Use a fake tree reader with roles and values. Assert static text is retained in visual order, duplicate parent/child values are removed, buttons with no meaningful text are skipped, and output is capped at 500,000 characters with an explicit error rather than silent truncation.

- [ ] **Step 2: Verify RED**

Expected: missing Accessibility source.

- [ ] **Step 3: Implement the AX adapter**

Use:

```swift
let appElement = AXUIElementCreateApplication(frontmost.processIdentifier)
AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &window)
```

Walk visible descendants with depth/node limits, read `kAXValueAttribute`, `kAXTitleAttribute`, and `kAXDescriptionAttribute`, and never synthesize clicks or modify the page.

- [ ] **Step 4: Run check and commit**

```bash
xcrun swiftc -framework ApplicationServices native/Sources/Domain/Reader/ReaderItem.swift native/Sources/Infrastructure/Reader/AccessibilityTextSource.swift native/Tests/AccessibilityTextSourceCheck.swift -o /tmp/AccessibilityTextSourceCheck && /tmp/AccessibilityTextSourceCheck
git add native/Sources/Infrastructure/Reader/AccessibilityTextSource.swift native/Tests/AccessibilityTextSourceCheck.swift
git commit -m "feat: read visible browser accessibility text"
```

---

## Milestone 3 — Chrome Article Extraction

### Task 9: Chrome Extension With Readability

**Files:**
- Create: `chrome-extension/content-reader/manifest.json`
- Create: `chrome-extension/content-reader/background.js`
- Create: `chrome-extension/content-reader/content.js`
- Create: `chrome-extension/content-reader/package.json`
- Create: `chrome-extension/content-reader/package-lock.json`
- Create: `chrome-extension/content-reader/scripts/build.sh`
- Generate: `chrome-extension/content-reader/dist/readability.js`
- Copy license: `chrome-extension/content-reader/THIRD_PARTY_READABILITY_LICENSE`
- Modify: `THIRD_PARTY_NOTICES.md`
- Test: `chrome-extension/content-reader/tests/extraction.test.mjs`

**Interfaces:**
- Native message request: `{"version":1,"id":"UUID","type":"extractArticle"}`.
- Response: `{"version":1,"id":"UUID","ok":true,"article":{"title":"...","byline":"...","language":"...","text":"...","url":"..."}}`.
- Failure: same envelope with `ok:false` and stable error code.

- [ ] **Step 1: Write failing extraction tests**

Use `jsdom` with a fixture containing navigation, article headings, paragraphs, and ads. Assert `extractArticle(document)` returns the article text and excludes navigation/ad text. Add empty-page and 500,000-character rejection cases.

- [ ] **Step 2: Run and verify RED**

Run:

```bash
cd chrome-extension/content-reader
npm test
```

Expected: module/function missing.

- [ ] **Step 3: Add pinned dependencies and build script**

Pin exact versions for `@mozilla/readability` and `jsdom`; `npm ci` must be reproducible. The build copies Readability’s distributable source and license into `dist/`; generated code is not manually edited.

- [ ] **Step 4: Implement content extraction**

```javascript
export function extractArticle(document) {
  const parsed = new Readability(document.cloneNode(true)).parse();
  const text = parsed?.textContent?.trim() ?? "";
  if (!text) return { ok: false, error: "no_article" };
  if (text.length > 500000) return { ok: false, error: "article_too_large" };
  return {
    ok: true,
    article: {
      title: parsed.title ?? document.title ?? "",
      byline: parsed.byline ?? "",
      language: parsed.lang ?? document.documentElement.lang ?? "",
      text,
      url: stripQueryAndFragment(document.location.href)
    }
  };
}
```

- [ ] **Step 5: Implement explicit active-tab messaging**

The service worker keeps a native port, accepts only `extractArticle`, queries the active tab after the native request, injects/contacts the content script, and returns the matching request ID. No history permission and no background tab enumeration.

- [ ] **Step 6: Run extension tests and permission audit**

```bash
npm ci
npm test
node tests/manifest-permissions.test.mjs
```

Expected: extraction tests pass; permissions are limited to `activeTab`, `scripting`, and `nativeMessaging`.

- [ ] **Step 7: Commit**

```bash
git add chrome-extension/content-reader THIRD_PARTY_NOTICES.md
git commit -m "feat: extract Chrome articles with Readability"
```

### Task 10: Native Messaging Host And Secure App Bridge

**Files:**
- Create: `native/Helpers/TypeWhaleReaderNativeHost.swift`
- Create: `native/Sources/Infrastructure/Reader/ReaderNativeMessageCodec.swift`
- Create: `native/Sources/Infrastructure/Reader/ChromeReaderBridge.swift`
- Create: `native/Sources/Infrastructure/Reader/ReaderUnixSocket.swift`
- Create: `native/Resources/NativeMessaging/com.waykingah.typewhale.reader.json.template`
- Modify: `native/build_native_app.sh`
- Test: `native/Tests/ReaderNativeMessageCodecCheck.swift`
- Test: `native/Tests/ChromeReaderBridgeCheck.swift`
- Test: `native/Tests/ChromeReaderPackagingCheck.sh`

**Interfaces:**
- Native Messaging uses 4-byte little-endian JSON framing.
- The helper bridges Chrome stdio to one user-only Unix socket at `Application Support/TypeWhale Pro/Reader/chrome-reader.sock`.
- `ChromeReaderBridge.extractCurrentArticle()` returns `ReaderAcquiredContent` or a typed connection/extraction error.

- [ ] **Step 1: Write failing codec tests**

```swift
let payload = Data(#"{"version":1,"type":"ping"}"#.utf8)
let framed = ReaderNativeMessageCodec.frame(payload)
precondition(framed.prefix(4) == Data([payload.count, 0, 0, 0].map(UInt8.init)))
precondition(try ReaderNativeMessageCodec.decode(framed) == payload)
```

Also reject frames above 1 MiB and malformed length prefixes.

- [ ] **Step 2: Verify RED**

Expected: missing codec.

- [ ] **Step 3: Implement the helper protocol**

The host continuously reads framed Chrome stdin, forwards JSON to the socket, reads the response, and writes framed stdout. It accepts no arbitrary filesystem path or shell command.

- [ ] **Step 4: Write the failing bridge check**

Use an injected fake socket transport. Verify request IDs match, successful article text becomes a `.webpage` acquisition, URLs lose query/fragment, mismatched IDs fail, and full text never enters diagnostic messages.

- [ ] **Step 5: Implement `ChromeReaderBridge`**

Maintain states: not installed, disconnected, connected, extracting, failed, complete. One in-flight extraction is allowed; a second explicit request cancels the first.

- [ ] **Step 6: Package and register the host**

Compile `TypeWhaleReaderNativeHost` into app Resources. At app startup, write the expanded host manifest atomically to:

```text
~/Library/Application Support/Google/Chrome/NativeMessagingHosts/com.waykingah.typewhale.reader.json
```

The manifest path points inside `/Applications/TypeWhale Pro.app`; `allowed_origins` contains only the fixed TypeWhale extension ID. File permissions are user-only.

- [ ] **Step 7: Run codec, bridge, and packaging checks**

```bash
xcrun swiftc native/Sources/Infrastructure/Reader/ReaderNativeMessageCodec.swift native/Tests/ReaderNativeMessageCodecCheck.swift -o /tmp/ReaderNativeMessageCodecCheck && /tmp/ReaderNativeMessageCodecCheck
xcrun swiftc native/Sources/Domain/Reader/ReaderItem.swift native/Sources/Application/Reader/ReaderSourceCoordinator.swift native/Sources/Infrastructure/Reader/ReaderUnixSocket.swift native/Sources/Infrastructure/Reader/ChromeReaderBridge.swift native/Tests/ChromeReaderBridgeCheck.swift -o /tmp/ChromeReaderBridgeCheck && /tmp/ChromeReaderBridgeCheck
bash native/Tests/ChromeReaderPackagingCheck.sh
```

- [ ] **Step 8: Commit**

```bash
git add native/Helpers/TypeWhaleReaderNativeHost.swift native/Sources/Infrastructure/Reader/ReaderNativeMessageCodec.swift native/Sources/Infrastructure/Reader/ChromeReaderBridge.swift native/Sources/Infrastructure/Reader/ReaderUnixSocket.swift native/Resources/NativeMessaging native/build_native_app.sh native/Tests/ReaderNativeMessageCodecCheck.swift native/Tests/ChromeReaderBridgeCheck.swift native/Tests/ChromeReaderPackagingCheck.sh
git commit -m "feat: bridge Chrome articles into TypeWhale"
```

### Task 11: Web Fallback Orchestration, Documentation, Release Build, And QA

**Files:**
- Modify: `native/Sources/Application/Reader/ContentReaderCoordinator.swift`
- Modify: `native/Sources/Presentation/Reader/ReaderFloatingView.swift`
- Modify: `native/Sources/Presentation/Main/MainViewController+Actions.swift`
- Modify: `docs/ARCHITECTURE.md`
- Modify: `docs/开发日志.md`
- Modify: `native/Sources/Presentation/VersionHistory/VersionHistoryViewController.swift`
- Test: `native/Tests/ContentReaderEndToEndCheck.swift`
- Test: `native/Tests/ContentReaderPrivacyBoundaryCheck.sh`

**Interfaces:**
- Read Webpage uses Chrome first, then offers Accessibility, then OCR.
- Explicit acquisition plays immediately after success.

- [ ] **Step 1: Write failing orchestration tests**

Use fake sources:

```swift
chrome.result = .failure(.disconnected)
accessibility.result = .success(content("可见文字", .accessibility))
coordinator.readWebpage()
precondition(snapshot.fallbackOffer == .accessibility)
coordinator.confirmFallback()
precondition(playback.lastIntent == .explicitSelection)
```

Add cases for Chrome success, no article, Accessibility permission denial, OCR cancel, and active playback replacement after explicit success.

- [ ] **Step 2: Verify RED**

Expected: orchestration behavior missing.

- [ ] **Step 3: Implement fallback UI and orchestration**

Show one actionable message at a time:

- extension missing → Install/Repair Chrome Extension, Read Visible Text, OCR;
- no article → Read Visible Text, OCR;
- Accessibility denied → Open System Settings, OCR;
- OCR empty → Capture Again.

- [ ] **Step 4: Add privacy boundary assertions**

The script rejects:

```bash
rg -n 'LaunchDiagnostics.*(originalText|speechText|article\\.text|ocrText)' native/Sources
rg -n 'httpBody.*(originalText|speechText|article)' native/Sources
find native -type f -iname '*ocr*' -path '*History*'
```

It positively checks screenshot deletion and URL query/fragment redaction.

- [ ] **Step 5: Run focused and regression tests**

Run all new Reader checks plus:

```bash
bash native/Tests/ScreenshotArchitectureBoundaryCheck.sh
bash native/Tests/SherpaNativeTTSBackendSourceCheck.sh
bash native/Tests/SpeechInputCoordinatorBoundaryCheck.sh
bash native/Tests/ApplicationScopeArchitectureBoundaryCheck.sh
```

Expected: all pass without warnings.

- [ ] **Step 6: Perform design review**

Use the required `design-review` skill against the installed Reader panel. Verify hierarchy, compact/expanded transition, drag handle, control spacing, keyboard focus, disabled emotion explanation, reduced motion, and no visual conflict with the existing recording capsule.

- [ ] **Step 7: Update architecture and release narrative**

Document source adapters, trust boundaries, native TTS isolation, Chrome permissions, temporary OCR handling, and fallback order. Add the exact upcoming build number to the version history before building.

- [ ] **Step 8: Recheck concurrency and run the required daily build**

```bash
git branch --show-current
git status --short
pgrep -af 'build_and_log|release_local_build|build_native_app|swiftc|xcodebuild' || true
./native/build_and_log.sh
```

Expected: build number increments once, `/Applications/TypeWhale Pro.app` is replaced and opened, signature verification passes, and the build log is appended.

- [ ] **Step 9: Installed-app manual QA**

1. Enable Content Reader in Voice.
2. Copy from Codex while idle: preview appears and autoplay follows the checkbox.
3. Copy during playback: current speech continues and the new item enters history.
4. Select another history item: current speech stops and selected text plays.
5. OCR a region and a whole window: recognized text previews and plays; the clipboard remains unchanged.
6. Read a public article and a logged-in rendered article from Chrome.
7. Disable/disconnect the extension and verify Accessibility/OCR fallback.
8. Collapse, expand, drag, hide, restore, change displays, and relaunch.
9. Verify ASR, paste, screenshot translation, OpenClaw, and hotkeys.
10. Confirm no Python process starts and no OCR screenshot remains.

- [ ] **Step 10: Commit the build**

Review `git status --short`, stage only Content Reader and build-generated version/log files, then:

```bash
git commit -m "release: ship TypeWhale content reader"
```

## Self-Review

- Spec coverage: clipboard authorization, no-interrupt autoplay, explicit switching, history, preparation, native TTS, floating panel, Voice tab, menu bar, OCR, Accessibility, Chrome/Readability, Native Messaging, privacy, failures, accessibility, tests, and rollout each map to a task.
- Intentional deferrals: Safari extension and general plugin platform remain outside this plan.
- Placeholder scan: no `TBD`, `TODO`, “similar to”, or unspecified error-handling step remains.
- Type consistency: all sources produce `ReaderAcquiredContent`; the coordinator converts it into `ReaderItem`; history and playback consume `ReaderItem`; explicit source actions use `ReaderPlaybackIntent.explicitSelection`.
