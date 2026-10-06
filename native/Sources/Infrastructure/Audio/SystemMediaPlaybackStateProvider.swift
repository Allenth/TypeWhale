import Foundation

enum SystemMediaPlaybackState: Equatable {
    case playing
    case paused
    case unknown
}

struct SystemMediaPlaybackSnapshot: Equatable {
    let state: SystemMediaPlaybackState
    let processID: pid_t?

    static let unknown = SystemMediaPlaybackSnapshot(
        state: .unknown,
        processID: nil
    )
}

protocol SystemMediaPlaybackStateProviding {
    func fetchSnapshot(
        completion: @escaping (SystemMediaPlaybackSnapshot) -> Void
    )
}

final class MediaRemoteSystemPlaybackStateProvider: SystemMediaPlaybackStateProviding {
    typealias RawFetch = (@escaping (Int32, pid_t) -> Void) -> Void

    private let rawFetch: RawFetch

    init(rawFetch: @escaping RawFetch = MediaRemoteSystemPlaybackStateProvider.fetchRawSnapshot) {
        self.rawFetch = rawFetch
    }

    func fetchSnapshot(
        completion: @escaping (SystemMediaPlaybackSnapshot) -> Void
    ) {
        rawFetch { rawState, processID in
            guard processID > 0 else {
                completion(.unknown)
                return
            }

            switch rawState {
            case 1:
                completion(SystemMediaPlaybackSnapshot(
                    state: .paused,
                    processID: processID
                ))
            case 2:
                completion(SystemMediaPlaybackSnapshot(
                    state: .playing,
                    processID: processID
                ))
            default:
                completion(.unknown)
            }
        }
    }

    private static func fetchRawSnapshot(
        completion: @escaping (Int32, pid_t) -> Void
    ) {
        TWSystemMediaFetchPlaybackSnapshot { state, processID in
            completion(state.rawValue, processID)
        }
    }
}
