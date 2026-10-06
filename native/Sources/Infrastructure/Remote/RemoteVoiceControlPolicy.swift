import Foundation

struct RemoteVoiceControlPolicy {
    enum Phase: String, Equatable {
        case idle
        case opening
        case streaming
    }

    enum Event: Equatable {
        case startSearch
        case audioStart
        case audioStop
    }

    enum Action: String, Equatable {
        case beginSessionAndOpenMicrophone
        case beginSessionFromAudioStart
        case awaitCorrelatedVoiceButton
        case ignoreUnexpectedAudioStart
        case ignoreDuplicateStartSearch
        case closeMicrophoneAndFinishSession
        case finishSession
        case none
    }

    private(set) var phase: Phase = .idle
    private(set) var usesExplicitAudioStop: Bool
    private let fallbackCorrelationWindowNanoseconds: UInt64
    private var voiceButtonDownObservedAt: UInt64?
    private var pendingAudioStartObservedAt: UInt64?

    init(
        usesExplicitAudioStop: Bool = true,
        fallbackCorrelationWindowNanoseconds: UInt64 = 120_000_000
    ) {
        self.usesExplicitAudioStop = usesExplicitAudioStop
        self.fallbackCorrelationWindowNanoseconds = fallbackCorrelationWindowNanoseconds
    }

    mutating func configure(usesExplicitAudioStop: Bool) {
        self.usesExplicitAudioStop = usesExplicitAudioStop
        reset()
    }

    mutating func observeVoiceButton(isDown: Bool, observedAt: UInt64) -> Action {
        guard isDown else {
            clearFallbackCorrelation()
            return .none
        }
        guard phase == .idle else { return .none }
        if let pendingAudioStartObservedAt,
           isCorrelated(pendingAudioStartObservedAt, observedAt) {
            self.pendingAudioStartObservedAt = nil
            voiceButtonDownObservedAt = nil
            phase = .streaming
            return .beginSessionFromAudioStart
        }
        pendingAudioStartObservedAt = nil
        voiceButtonDownObservedAt = observedAt
        return .none
    }

    mutating func handle(
        _ event: Event,
        observedAt: UInt64 = DispatchTime.now().uptimeNanoseconds
    ) -> Action {
        switch (phase, event) {
        case (.idle, .startSearch):
            clearFallbackCorrelation()
            phase = .opening
            return .beginSessionAndOpenMicrophone
        case (.opening, .startSearch):
            return .ignoreDuplicateStartSearch
        case (.streaming, .startSearch):
            guard !usesExplicitAudioStop else { return .ignoreDuplicateStartSearch }
            clearFallbackCorrelation()
            phase = .idle
            return .closeMicrophoneAndFinishSession
        case (.idle, .audioStart):
            if let voiceButtonDownObservedAt,
               isCorrelated(voiceButtonDownObservedAt, observedAt) {
                clearFallbackCorrelation()
                phase = .streaming
                return .beginSessionFromAudioStart
            }
            voiceButtonDownObservedAt = nil
            pendingAudioStartObservedAt = observedAt
            return .awaitCorrelatedVoiceButton
        case (.opening, .audioStart):
            clearFallbackCorrelation()
            phase = .streaming
            return .none
        case (.streaming, .audioStart):
            return .none
        case (.idle, .audioStop):
            clearFallbackCorrelation()
            return .none
        case (.opening, .audioStop), (.streaming, .audioStop):
            clearFallbackCorrelation()
            phase = .idle
            return .finishSession
        }
    }

    mutating func reset() {
        phase = .idle
        clearFallbackCorrelation()
    }

    private func isCorrelated(_ lhs: UInt64, _ rhs: UInt64) -> Bool {
        let difference = lhs >= rhs ? lhs - rhs : rhs - lhs
        return difference <= fallbackCorrelationWindowNanoseconds
    }

    private mutating func clearFallbackCorrelation() {
        voiceButtonDownObservedAt = nil
        pendingAudioStartObservedAt = nil
    }
}
