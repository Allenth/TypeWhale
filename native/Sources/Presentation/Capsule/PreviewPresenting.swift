import AppKit

enum PreviewAccent {
    case normal
    case ideaPill
    case openClaw
}

enum OpenClawConnectionStatus {
    case checking
    case connected
    case unavailable
}

enum PreviewModeEmphasis {
    case normal
    case automaticResolved
}

/// 实时预览窗的能力抽象。
///
/// 把预览窗的全部功能从具体 UI（默认胶囊 / 刘海主题）中剥离：协调器只依赖本协议，
/// UI 只是可替换的实现，主题切换 = 替换实现而不改任何业务调用点。
///
/// 继承 `ProductionPreviewTextSink`：统一转录核心把生产胶囊当作文字进料口消费，
/// 任何 `PreviewPresenting` 实现天然满足（`updateDraft(_ snapshot:)` 已是既有能力）。
protocol PreviewPresenting: AnyObject, ProductionPreviewTextSink {
    /// 点击预览上的模式标签回调，用于手动切换整理模式。
    var onCycleMode: (() -> Void)? { get set }
    /// 当前生产胶囊的屏幕 frame；仅供只读旁路窗口计算相邻位置。
    var presentationFrame: CGRect? { get }

    /// 录音开始时设置目标应用上下文（图标、名称、整理模式、是否自动翻译）。
    func setContext(appIcon: NSImage?, appName: String?, modeName: String, autoTranslateEnabled: Bool)
    /// 目标应用变化时更新图标与名称。
    func updateTargetApp(appIcon: NSImage?, appName: String?)
    /// 更新整理模式名称。
    func updateModeName(_ modeName: String)
    /// 更新整理模式的视觉强调；自动模式解析出的真实模式使用高亮提示。
    func updateModeEmphasis(_ emphasis: PreviewModeEmphasis)
    /// 更新是否启用自动翻译。
    func updateAutoTranslateEnabled(_ enabled: Bool)
    /// 更新录音状态（剩余秒数、内存高压提示）。
    func updateRecordingStatus(remainingSeconds: Int?, memoryHigh: Bool)
    /// 更新当前预览的产品语义强调色。
    func updateAccent(_ accent: PreviewAccent)
    /// 更新 OpenClaw 胶囊右上角徽章的连接状态颜色。
    func updateOpenClawConnectionStatus(_ status: OpenClawConnectionStatus)
    /// 显示某个状态文案与可选草稿，并让预览可见。
    func show(state: String, draft: String?)
    /// 更新实时预览草稿文本。
    func updateDraft(_ draft: String)
    /// 更新实时预览草稿（结构化展示快照：稳定前缀只追加 + 可变尾部原位修订）。
    /// 实现方应优先消费快照以获得稳定区/可变区分离；默认实现退化为整串文本。
    /// （`updateDraft(_ snapshot:)` 已由 `ProductionPreviewTextSink` 声明，此处不重复要求。）
    /// 动画隐藏预览。
    func hideAnimated()
    /// 更新波形频段（驱动波形 / 脉冲）。
    func updateBands(_ bands: [Float])
    /// 更新实时输入电平（dBFS）。
    func updateInputLevel(db: Float?)
}

extension PreviewPresenting {
    /// 便捷重载：等价于 show(state:draft:nil)，供协议类型调用方省略 draft。
    func show(state: String) { show(state: state, draft: nil) }

    /// 默认实现：不区分稳定/可变区的实现（如刘海主题）继续消费整串文本。
    func updateDraft(_ snapshot: PreviewDisplaySnapshot) {
        updateDraft(snapshot.displayText)
    }

    func updateAccent(_ accent: PreviewAccent) {}

    func updateOpenClawConnectionStatus(_ status: OpenClawConnectionStatus) {}

    func updateModeEmphasis(_ emphasis: PreviewModeEmphasis) {}

    /// 仅兼容尚未纳入生产目标的胶囊概念预览；生产协调器不再调用或维护此状态。
    func updateOllamaHealth(isHealthy: Bool) {
        _ = isHealthy
    }
}
