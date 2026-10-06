import Foundation

protocol OpenClawTTSBackend: AnyObject {
    var isRunning: Bool { get }
    func start(timeoutSeconds: TimeInterval) throws
    func synthesize(_ request: OpenClawVoiceSynthesisRequest, timeoutSeconds: TimeInterval) throws
    func cancelSynthesis()
    func stop()
}
