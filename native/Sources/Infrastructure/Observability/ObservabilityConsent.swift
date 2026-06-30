import Foundation

/// 用户对远程可观测性的同意状态。
///
/// 默认全部关闭：在用户明确开启前，不发送任何远程数据（local-first 隐私安全默认）。
/// 拆成两个独立逻辑开关，对应 docs/埋点方案.md §6：
/// - 匿名产品使用统计（TelemetryDeck/Aptabase）
/// - 崩溃与错误报告（Sentry）
enum ObservabilityConsentStore {
    private static let productAnalyticsKey = "observability.productAnalytics.enabled"
    private static let crashReportsKey = "observability.crashReports.enabled"
    private static let promptedKey = "observability.consentPrompted"

    /// 匿名产品使用统计是否开启（默认 false）。
    static var productAnalyticsEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: productAnalyticsKey) }
        set { UserDefaults.standard.set(newValue, forKey: productAnalyticsKey) }
    }

    /// 崩溃与错误报告是否开启（默认 false）。
    static var crashReportsEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: crashReportsKey) }
        set { UserDefaults.standard.set(newValue, forKey: crashReportsKey) }
    }

    /// 是否已向用户展示过首启同意说明（保证只展示一次）。
    static var hasBeenPrompted: Bool {
        get { UserDefaults.standard.bool(forKey: promptedKey) }
        set { UserDefaults.standard.set(newValue, forKey: promptedKey) }
    }

    /// 任一远程上报开启即视为需要初始化对应平台。
    static var anyEnabled: Bool { productAnalyticsEnabled || crashReportsEnabled }
}
