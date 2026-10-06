import Foundation

@main
struct RemoteConnectionPolicyCheck {
    static func main() {
        followsTheHappyPath()
        handlesUnavailableRetryAndBusyStates()
        disableAlwaysWins()
        print("RemoteConnectionPolicyCheck passed")
    }

    private static func followsTheHappyPath() {
        var policy = RemoteConnectionPolicy()
        precondition(policy.phase == .disabled)
        policy.handle(.setEnabled(true))
        precondition(policy.phase == .scanning)
        policy.handle(.peripheralFound)
        precondition(policy.phase == .connecting)
        policy.handle(.connected)
        precondition(policy.phase == .negotiating)
        policy.handle(.capabilitiesAccepted)
        precondition(policy.phase == .ready)
        policy.handle(.voiceStarted)
        precondition(policy.phase == .listening)
        policy.handle(.voiceStopped)
        precondition(policy.phase == .processing)
        policy.handle(.processingFinished)
        precondition(policy.phase == .ready)
    }

    private static func handlesUnavailableRetryAndBusyStates() {
        var policy = RemoteConnectionPolicy()
        policy.handle(.bluetoothUnavailable)
        precondition(policy.phase == .bluetoothUnavailable)
        policy.handle(.bluetoothAvailable(enabled: true))
        precondition(policy.phase == .scanning)
        policy.handle(.peripheralFound)
        policy.handle(.connectionFailed(reason: "timeout"))
        precondition(policy.phase == .retrying(attempt: 1))
        policy.handle(.retryTimerFired)
        precondition(policy.phase == .scanning)
        policy.handle(.speechBusy)
        precondition(policy.phase == .busy)
        policy.handle(.processingFinished)
        precondition(policy.phase == .scanning)
        policy.handle(.protocolFailed(reason: "unsupported codec"))
        precondition(policy.phase == .protocolFailure(reason: "unsupported codec"))
    }

    private static func disableAlwaysWins() {
        var policy = RemoteConnectionPolicy()
        policy.handle(.setEnabled(true))
        policy.handle(.peripheralFound)
        policy.handle(.connected)
        policy.handle(.setEnabled(false))
        precondition(policy.phase == .disabled)
        policy.handle(.connected)
        precondition(policy.phase == .disabled)
    }
}
