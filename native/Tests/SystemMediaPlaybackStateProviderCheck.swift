import Foundation

@main
struct SystemMediaPlaybackStateProviderCheck {
    static func main() {
        mapsKnownPlaybackStatesWithStableIdentity()
        rejectsUnknownStatesAndInvalidIdentity()
        completesExactlyOncePerRawSnapshot()
        print("SystemMediaPlaybackStateProviderCheck passed")
    }

    private static func mapsKnownPlaybackStatesWithStableIdentity() {
        precondition(
            snapshot(rawState: 2, processID: 451)
                == SystemMediaPlaybackSnapshot(state: .playing, processID: 451)
        )
        precondition(
            snapshot(rawState: 1, processID: 451)
                == SystemMediaPlaybackSnapshot(state: .paused, processID: 451)
        )
    }

    private static func rejectsUnknownStatesAndInvalidIdentity() {
        precondition(snapshot(rawState: 9, processID: 451) == .unknown)
        precondition(snapshot(rawState: 2, processID: 0) == .unknown)
        precondition(snapshot(rawState: 1, processID: -1) == .unknown)
        precondition(snapshot(rawState: 0, processID: 451) == .unknown)
    }

    private static func completesExactlyOncePerRawSnapshot() {
        var completions: [SystemMediaPlaybackSnapshot] = []
        let provider = MediaRemoteSystemPlaybackStateProvider { completion in
            completion(2, 902)
        }

        provider.fetchSnapshot { completions.append($0) }

        precondition(completions == [
            SystemMediaPlaybackSnapshot(state: .playing, processID: 902)
        ])
    }

    private static func snapshot(
        rawState: Int32,
        processID: pid_t
    ) -> SystemMediaPlaybackSnapshot {
        var snapshots: [SystemMediaPlaybackSnapshot] = []
        let provider = MediaRemoteSystemPlaybackStateProvider { completion in
            completion(rawState, processID)
        }
        provider.fetchSnapshot { snapshots.append($0) }
        precondition(snapshots.count == 1)
        return snapshots[0]
    }
}
