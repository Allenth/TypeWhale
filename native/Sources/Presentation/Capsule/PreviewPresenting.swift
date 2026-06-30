import AppKit

/// 实时预览窗的能力抽象。
///
/// 把预览窗的全部功能从具体 UI（默认胶囊 / 刘海主题）中剥离：协调器只依赖本协议，
/// UI 只是可替换的实现，主题切换 = 替换实现而不改任何业务调用点。
protocol PreviewPresenting: AnyObject {
    /// 点击预览上的模式标签回调，用于手动切换整理模式。
    var onCycleMode: (() -> Void)? { get set }

    /// 录音开始时设置目标应用上下文（图标、名称、整理模式、是否自动翻译）。
    func setContext(appIcon: NSImage?, appName: String?, modeName: String, autoTranslateEnabled: Bool)
    /// 目标应用变化时更新图标与名称。
    func updateTargetApp(appIcon: NSImage?, appName: String?)
    /// 更新整理模式名称。
    func updateModeName(_ modeName: String)
    /// 更新是否启用自动翻译。
    func updateAutoTranslateEnabled(_ enabled: Bool)
    /// 更新录音状态（剩余秒数、内存高压提示）。
    func updateRecordingStatus(remainingSeconds: Int?, memoryHigh: Bool)
    /// 显示某个状态文案与可选草稿，并让预览可见。
    func show(state: String, draft: String?)
    /// 更新实时预览草稿文本。
    func updateDraft(_ draft: String)
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
}
