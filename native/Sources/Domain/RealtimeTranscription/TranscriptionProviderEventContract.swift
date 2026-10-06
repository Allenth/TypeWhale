import Foundation

enum TranscriptionProviderEventKind: String, Equatable, Sendable {
    case textOutput = "text_output"
    case terminal = "terminal"
    case diagnostic = "diagnostic"
}

enum TranscriptionProviderEventContract {
    static func classify(_ event: TranscriptionEvent) -> TranscriptionProviderEventKind {
        switch event {
        case .partial, .finalized, .reconciled:
            return .textOutput
        case .completed, .failed, .cancelled:
            return .terminal
        case .connectionChanged:
            return .diagnostic
        }
    }
}
