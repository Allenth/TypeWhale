import Foundation

@main
struct RealtimeChunkBoundaryPolicyCheck {
    static func main() {
        let policy = RealtimeChunkBoundaryPolicy()

        precondition(!policy.shouldFinalize(
            chunkIndex: 0,
            chunkDuration: 5.9,
            voiceActive: false,
            hasObservedVoice: true
        ))
        precondition(!policy.shouldFinalize(
            chunkIndex: 0,
            chunkDuration: 6.0,
            voiceActive: false,
            hasObservedVoice: false
        ), "initial silence must not consume the first chunk")
        precondition(policy.shouldFinalize(
            chunkIndex: 0,
            chunkDuration: 6.0,
            voiceActive: false,
            hasObservedVoice: true
        ))
        precondition(!policy.shouldFinalize(
            chunkIndex: 0,
            chunkDuration: 6.0,
            voiceActive: true,
            hasObservedVoice: true
        ))
        precondition(policy.shouldFinalize(
            chunkIndex: 0,
            chunkDuration: 18.0,
            voiceActive: true,
            hasObservedVoice: true
        ))
        precondition(!policy.shouldFinalize(
            chunkIndex: 1,
            chunkDuration: 9.9,
            voiceActive: false,
            hasObservedVoice: true
        ))
        precondition(policy.shouldFinalize(
            chunkIndex: 1,
            chunkDuration: 10.0,
            voiceActive: false,
            hasObservedVoice: true
        ))
        precondition(policy.shouldFinalize(
            chunkIndex: 2,
            chunkDuration: 18.0,
            voiceActive: true,
            hasObservedVoice: true
        ))

        print("RealtimeChunkBoundaryPolicyCheck passed")
    }
}
