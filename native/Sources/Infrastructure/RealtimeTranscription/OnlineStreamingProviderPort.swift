import Foundation

/// 真实在线 Provider 的供应商无关连接配置。
///
/// 本层不包含 endpoint、API Key、账号或持久化策略；这些必须经过 Stage 8 独立评审。
struct OnlineProviderConfiguration: Equatable, Sendable {
    let sampleRate: Int
    let channelCount: Int
    let languageHint: String?
    let connectionTimeoutSeconds: TimeInterval
}

enum OnlineProviderMessage: Equatable, Sendable {
    case partial(text: String, providerSequence: UInt64)
    case finalized(text: String, providerSequence: UInt64)
    case completed
    case connectionChanged(ProviderConnectionState)
    case failed(code: String, message: String, isRecoverable: Bool)
}

/// 在线流式传输端口定义；Task 8 只证明接口形状，不连接任何真实服务。
protocol OnlineStreamingTransport: Sendable {
    func connect(configuration: OnlineProviderConfiguration) async throws
    func send(_ frame: AudioFrame) async throws
    func finishInput() async throws
    func disconnect() async
    func messages() -> AsyncStream<OnlineProviderMessage>
}
