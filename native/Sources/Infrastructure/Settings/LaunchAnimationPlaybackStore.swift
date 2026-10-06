import Foundation

enum LaunchAnimationPlaybackStore {
    static let hasPlayedKey = "typewhale.launchAnimation.hasPlayed.v1"

    static var shouldPlayFirstLaunch: Bool {
        !UserDefaults.standard.bool(forKey: hasPlayedKey)
    }

    static func markPlayed() {
        UserDefaults.standard.set(true, forKey: hasPlayedKey)
    }
}
