import Foundation

@main
struct MainCapsuleOpenClawProjectionCheck {
    static func main() {
        verifiesOpenClawConnectionProjection()
        verifiesNonOpenClawAccentProjection()
        print("MainCapsuleOpenClawProjectionCheck passed")
    }

    private static func verifiesOpenClawConnectionProjection() {
        let connected = MainCapsuleOpenClawProjection(
            accent: .openClaw,
            connectionStatus: .connected
        )
        precondition(connected.purpose == .openClaw(connection: .connected))

        let checking = MainCapsuleOpenClawProjection(
            accent: .openClaw,
            connectionStatus: .checking
        )
        precondition(checking.purpose == .openClaw(connection: .checking))

        let unavailable = MainCapsuleOpenClawProjection(
            accent: .openClaw,
            connectionStatus: .unavailable
        )
        precondition(unavailable.purpose == .openClaw(connection: .unavailable))
    }

    private static func verifiesNonOpenClawAccentProjection() {
        let normal = MainCapsuleOpenClawProjection(
            accent: .normal,
            connectionStatus: .connected
        )
        precondition(normal.purpose == .dictation)

        let ideaPill = MainCapsuleOpenClawProjection(
            accent: .ideaPill,
            connectionStatus: .connected
        )
        precondition(ideaPill.purpose == .ideaPill)
    }
}
