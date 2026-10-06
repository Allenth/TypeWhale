import Foundation

enum OnlineASRProviderUnavailableReason: Equatable, Sendable {
    case missingCredential(OnlineASRCredentialKind)
}

enum OnlineASRProviderBuildResult {
    case disabled
    case unavailable(OnlineASRProviderUnavailableReason)
    case ready(any TranscriptionProvider)
}

struct OnlineASRProviderFactory {
    typealias Builder = (String) -> any TranscriptionProvider

    private let credentials: any OnlineASRCredentialStoring
    private let doubaoBuilder: Builder
    private let mimoBuilder: Builder

    init(
        credentials: any OnlineASRCredentialStoring,
        doubaoBuilder: @escaping Builder,
        mimoBuilder: @escaping Builder
    ) {
        self.credentials = credentials
        self.doubaoBuilder = doubaoBuilder
        self.mimoBuilder = mimoBuilder
    }

    func make(selection: OnlineASRProviderSelection) -> OnlineASRProviderBuildResult {
        switch selection {
        case .off:
            return .disabled
        case .doubao:
            guard let key = credentials.load(.doubaoAPIKey) else {
                return .unavailable(.missingCredential(.doubaoAPIKey))
            }
            return .ready(doubaoBuilder(key))
        case .mimoV25:
            guard let key = credentials.load(.mimoAPIKey) else {
                return .unavailable(.missingCredential(.mimoAPIKey))
            }
            return .ready(mimoBuilder(key))
        }
    }
}
