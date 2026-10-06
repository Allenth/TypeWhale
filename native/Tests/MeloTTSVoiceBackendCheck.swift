import Foundation

@main
struct MeloTTSVoiceBackendCheck {
    static func main() {
        let lease = MeloTTSWarmLease(idleTimeoutSeconds: 180)
        let start = Date(timeIntervalSince1970: 100)
        lease.renew(at: start)
        precondition(!lease.hasExpired(at: start.addingTimeInterval(179)))
        precondition(lease.hasExpired(at: start.addingTimeInterval(180)))
        print("MeloTTSVoiceBackendCheck passed")
    }
}
