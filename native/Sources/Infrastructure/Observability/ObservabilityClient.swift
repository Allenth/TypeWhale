import Foundation

/// 可观测性统一门面：业务层只依赖它。
///
/// 设计（见 docs/埋点方案.md §3）：
/// - 同意关闭时整体 no-op，不构造也不发送任何数据。
/// - 上报在 utility 队列异步执行，永不阻塞录音/ASR/粘贴等热路径。
/// - 真实平台 SDK（Sentry / TelemetryDeck / Aptabase）通过替换 transport 注入，埋点点不变。
/// - 所有参数经 Redactor 脱敏，匿名标识为随机 UUID（不绑定任何身份信息）。
final class ObservabilityClient {
    static let shared = ObservabilityClient()

    private let analytics: AnalyticsTransport
    private let quality: QualityTransport
    private let queue = DispatchQueue(label: "com.waykingah.typewhale.observability", qos: .utility)
    private let anonymousID: String

    init(
        analytics: AnalyticsTransport = NoopObservabilityTransport(),
        quality: QualityTransport = NoopObservabilityTransport()
    ) {
        self.analytics = analytics
        self.quality = quality
        self.anonymousID = ObservabilityClient.loadOrCreateAnonymousID()
    }

    /// 产品分析事件（送 Analytics transport），需「匿名使用统计」开启。
    func track(_ event: AnalyticsEventName, _ params: [String: ObservabilityValue] = [:]) {
        guard ObservabilityConsentStore.productAnalyticsEnabled else { return }
        let flat = mergeCommon(ObservabilityRedactor.flatten(params))
        let analytics = self.analytics
        queue.async { analytics.send(event: event.rawValue, parameters: flat) }
    }

    /// 关键动作面包屑（送 Quality transport），需「崩溃与错误报告」开启。
    func breadcrumb(_ event: AnalyticsEventName, _ params: [String: ObservabilityValue] = [:]) {
        guard ObservabilityConsentStore.crashReportsEnabled else { return }
        let flat = ObservabilityRedactor.flatten(params)
        let quality = self.quality
        queue.async { quality.breadcrumb(event.rawValue, data: flat) }
    }

    /// 关键任务错误（送 Quality transport），需「崩溃与错误报告」开启。
    func captureError(
        module: String,
        code: String,
        task: String? = nil,
        params: [String: ObservabilityValue] = [:]
    ) {
        guard ObservabilityConsentStore.crashReportsEnabled else { return }
        var ctx = ObservabilityRedactor.flatten(params)
        ctx["module"] = ObservabilityRedactor.sanitizeToken(module)
        ctx["code"] = ObservabilityRedactor.sanitizeToken(code)
        if let task { ctx["task"] = ObservabilityRedactor.sanitizeToken(task) }
        let merged = mergeCommon(ctx)
        let quality = self.quality
        queue.async { quality.capture(error: code, context: merged) }
    }

    /// 合并所有事件隐式携带的公共字段（见 docs/埋点方案.md §4）。
    private func mergeCommon(_ params: [String: String]) -> [String: String] {
        var out = params
        let info = Bundle.main.infoDictionary
        out["app_version"] = info?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        out["build"] = info?["CFBundleVersion"] as? String ?? "0"
        out["os_version"] = ProcessInfo.processInfo.operatingSystemVersionString
        out["locale"] = Locale.current.identifier
        out["release_channel"] = ReleaseChannel.current.rawValue
        out["anonymous_user_id"] = anonymousID
        return out
    }

    /// 匿名标识：随机 UUID，首次生成后持久化。绝不使用设备指纹/邮箱/序列号。
    private static func loadOrCreateAnonymousID() -> String {
        let key = "observability.anonymousUserID"
        if let existing = UserDefaults.standard.string(forKey: key), !existing.isEmpty {
            return existing
        }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: key)
        return id
    }
}
