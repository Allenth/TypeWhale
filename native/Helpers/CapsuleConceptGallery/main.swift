import AppKit

/// 独立预览只需要生产协议的文字投递能力；Helper 不参与主 App 编译，
/// 因而在这里保留同形方法契约，避免把完整实时转录协调器及其依赖拖入预览工具。
/// 预览本身由 NSApplication 主线程运行；生产构建仍使用真实协议的 @MainActor 约束。
protocol ProductionPreviewTextSink: AnyObject {
    func updateDraft(_ snapshot: PreviewDisplaySnapshot)
}

// 独立预览：用真实的 MultiCapsulePreviewPresenter（fan-out）驱动三套概念胶囊悬浮面板，
// 喂一条模拟 SpeechInputCoordinator 的数据流（快照 + 频段 + 强调态 + 倒计时 + 健康），
// 验证「同屏不遮盖 + 都订阅同一数据源」。与主程序隔离——swiftc 单独编译，不接协调器。
// 运行：native/Helpers/CapsuleConceptGallery/run.sh

/// 固定中屏锚点：模拟「原胶囊」的位置，让三套概念胶囊堆叠其上，便于预览截图。
final class FakeAnchor: PreviewPresenting {
    var onCycleMode: (() -> Void)?
    let frame: CGRect
    init(frame: CGRect) { self.frame = frame }
    var presentationFrame: CGRect? { frame }
    func setContext(appIcon: NSImage?, appName: String?, modeName: String, autoTranslateEnabled: Bool) {}
    func updateTargetApp(appIcon: NSImage?, appName: String?) {}
    func updateModeName(_ modeName: String) {}
    func updateAutoTranslateEnabled(_ enabled: Bool) {}
    func updateRecordingStatus(remainingSeconds: Int?, memoryHigh: Bool) {}
    func updateOllamaHealth(isHealthy: Bool) {}
    func show(state: String, draft: String?) {}
    func updateDraft(_ draft: String) {}
    func hideAnimated() {}
    func updateBands(_ bands: [Float]) {}
    func updateInputLevel(db: Float?) {}
}

final class Harness: NSObject, NSApplicationDelegate {
    private let panels = [
        ConceptCapsulePanel(view: InkwellCapsuleView()),
        ConceptCapsulePanel(view: MistlineCapsuleView()),
        ConceptCapsulePanel(view: JadeArcCapsuleView()),
    ]
    private lazy var presenter: MultiCapsulePreviewPresenter = {
        // 固定到原点 (0,0) 的主笔记本屏，保证 screencapture 能抓到（多屏环境下 NSScreen.main 可能指向外接屏）。
        let target = NSScreen.screens.first(where: { $0.frame.origin == .zero }) ?? NSScreen.main
        let vis = target?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let anchor = FakeAnchor(frame: CGRect(x: vis.midX - 100, y: vis.midY - 140, width: 200, height: 44))
        return MultiCapsulePreviewPresenter(anchor: anchor, variants: panels)
    }()
    private var bandTimer: Timer?
    private var scriptTimer: Timer?
    private var t: CGFloat = 0
    private var scene = 0
    private let sentence = Array("把周三的产品评审挪到下午三点，并同步给设计和前端两位")
    private var revealed = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        presenter.setContext(appIcon: nil, appName: "飞书", modeName: "书面", autoTranslateEnabled: true)
        presenter.updateOllamaHealth(isHealthy: true)
        presenter.show(state: "录音中", draft: nil)

        let bt = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in self?.feedBands() }
        RunLoop.main.add(bt, forMode: .common); bandTimer = bt
        let st = Timer(timeInterval: 0.9, repeats: true) { [weak self] _ in self?.advance() }
        RunLoop.main.add(st, forMode: .common); scriptTimer = st

        NSApp.activate(ignoringOtherApps: true)
    }

    /// 合成「说话/停顿」交替的频段，驱动全部三套波形/墨珠。
    private func feedBands() {
        t += 1.0 / 30.0
        let speaking = sin(t * 0.7) > -0.2
        var bands = [Float](repeating: 0.08, count: 7)
        if speaking {
            for i in 0..<7 {
                let base = 0.35 + 0.5 * abs(sin(t * (2.0 + Double(i) * 0.6)))
                bands[i] = Float(min(1, max(0.1, base + Double.random(in: -0.12...0.12))))
            }
        }
        presenter.updateBands(bands)
    }

    /// 场景脚本：待说话 → 逐字转写 → 灵感丸 → OpenClaw → 倒计时告急，循环。
    private func advance() {
        // 逐字揭示转写。
        if scene >= 1 && scene <= 4 {
            revealed = min(sentence.count, revealed + 2)
            let text = String(sentence.prefix(revealed))
            let stableCount = max(0, text.count - 4)               // 末 4 字视为可变尾部
            let stable = String(Array(text).prefix(stableCount))
            let volatile = String(Array(text).suffix(text.count - stableCount))
            presenter.updateDraft(PreviewDisplaySnapshot(
                revision: revealed, stableCharacterCount: stableCount,
                stableWindowText: stable, volatileTailText: volatile))
        }

        // 每 ~3.6s（4 tick）切一次场景。
        guard Int(t * 30) % 4 == 0 else { return }
        scene = (scene + 1) % 6
        switch scene {
        case 0:
            revealed = 0
            presenter.updateAccent(.normal)
            presenter.updateRecordingStatus(remainingSeconds: nil, memoryHigh: false)
            presenter.updateOllamaHealth(isHealthy: true)
            presenter.show(state: "录音中", draft: nil)
        case 1:
            presenter.updateAccent(.normal)
        case 2:
            presenter.updateAccent(.ideaPill)
        case 3:
            presenter.updateOpenClawConnectionStatus(.connected)
            presenter.updateAccent(.openClaw)
        case 4:
            presenter.updateAccent(.normal)
            presenter.updateRecordingStatus(remainingSeconds: 8, memoryHigh: false)
        default:
            presenter.updateRecordingStatus(remainingSeconds: nil, memoryHigh: false)
        }
    }
}

let app = NSApplication.shared
let harness = Harness()
app.delegate = harness
app.setActivationPolicy(.regular)
app.run()
