import Foundation

/// 产品分析上报后端（TelemetryDeck / Aptabase 实现此协议）。
protocol AnalyticsTransport: AnyObject {
    func send(event name: String, parameters: [String: String])
}

/// 质量上报后端（Sentry 实现此协议）。
protocol QualityTransport: AnyObject {
    func capture(error code: String, context: [String: String])
    func breadcrumb(_ name: String, data: [String: String])
}

/// 默认空实现：在接入真实平台 SDK 之前，所有上报为 no-op。
/// 接入真实平台时只需替换注入 `ObservabilityClient` 的 transport，业务埋点点不变。
final class NoopObservabilityTransport: AnalyticsTransport, QualityTransport {
    func send(event name: String, parameters: [String: String]) {}
    func capture(error code: String, context: [String: String]) {}
    func breadcrumb(_ name: String, data: [String: String]) {}
}
