import AppKit

/// 标准装配：原胶囊（生产 RecordingPanel）+ 墨滴 / 雾线 / 玉弧。
///
/// 与核心类分文件，避免核心分发/布局逻辑耦合生产 RecordingPanel，便于独立预览编译。
/// 正式接入时把 SpeechInputCoordinator 的
/// `private var popup: PreviewPresenting = RecordingPanel()`
/// 改成 `private var popup: PreviewPresenting = MultiCapsulePreviewPresenter.standard()` 即可。
extension MultiCapsulePreviewPresenter {
    static func standard(anchor: PreviewPresenting = RecordingPanel()) -> MultiCapsulePreviewPresenter {
        MultiCapsulePreviewPresenter(anchor: anchor, variants: [
            ConceptCapsulePanel(view: InkwellCapsuleView()),
            ConceptCapsulePanel(view: MistlineCapsuleView()),
            ConceptCapsulePanel(view: JadeArcCapsuleView()),
        ])
    }
}
