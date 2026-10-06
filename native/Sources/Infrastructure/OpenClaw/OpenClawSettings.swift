import Foundation

struct OpenClawSettings: Equatable {
    var gatewayURL: String
    var agentID: String
    var sessionKey: String
    var cliPath: String

    static let `default` = OpenClawSettings(
        gatewayURL: "ws://127.0.0.1:18789",
        agentID: "main",
        sessionKey: "agent:main:typewhale-voice",
        cliPath: "/opt/homebrew/bin/openclaw"
    )
}

enum OpenClawSettingsStore {
    private static let gatewayURLKey = "openClawGatewayURL"
    private static let agentIDKey = "openClawAgentID"
    private static let sessionKeyKey = "openClawSessionKey"
    private static let cliPathKey = "openClawCLIPath"

    static func load() -> OpenClawSettings {
        let fallback = OpenClawSettings.default
        return OpenClawSettings(
            gatewayURL: nonEmptyString(forKey: gatewayURLKey) ?? fallback.gatewayURL,
            agentID: nonEmptyString(forKey: agentIDKey) ?? fallback.agentID,
            sessionKey: nonEmptyString(forKey: sessionKeyKey) ?? fallback.sessionKey,
            cliPath: nonEmptyString(forKey: cliPathKey) ?? fallback.cliPath
        )
    }

    static func save(_ settings: OpenClawSettings) {
        set(settings.gatewayURL, forKey: gatewayURLKey, fallback: OpenClawSettings.default.gatewayURL)
        set(settings.agentID, forKey: agentIDKey, fallback: OpenClawSettings.default.agentID)
        set(settings.sessionKey, forKey: sessionKeyKey, fallback: OpenClawSettings.default.sessionKey)
        set(settings.cliPath, forKey: cliPathKey, fallback: OpenClawSettings.default.cliPath)
    }

    static func reset() {
        [gatewayURLKey, agentIDKey, sessionKeyKey, cliPathKey].forEach {
            UserDefaults.standard.removeObject(forKey: $0)
        }
    }

    private static func nonEmptyString(forKey key: String) -> String? {
        guard let value = UserDefaults.standard.string(forKey: key)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }

    private static func set(_ value: String, forKey key: String, fallback: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == fallback {
            UserDefaults.standard.removeObject(forKey: key)
        } else {
            UserDefaults.standard.set(trimmed, forKey: key)
        }
    }
}
