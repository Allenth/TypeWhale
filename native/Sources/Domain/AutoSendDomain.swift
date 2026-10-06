import Foundation

enum PostPasteAction: String, Codable, CaseIterable, Equatable {
    case none
    case returnKey
    case commandReturn
}

struct AutoSendConfiguration: Codable, Equatable {
    static let countdownSecondsRange = 1...10
    static let defaultCountdownSeconds = 2

    var isEnabled: Bool
    var actionsByBundleID: [String: PostPasteAction]
    var countdownSeconds: Int

    init(
        isEnabled: Bool,
        actionsByBundleID: [String: PostPasteAction],
        countdownSeconds: Int = Self.defaultCountdownSeconds
    ) {
        self.isEnabled = isEnabled
        self.actionsByBundleID = actionsByBundleID
        self.countdownSeconds = Self.normalizedCountdownSeconds(
            countdownSeconds
        )
    }

    static func normalizedCountdownSeconds(_ value: Int) -> Int {
        min(
            countdownSecondsRange.upperBound,
            max(countdownSecondsRange.lowerBound, value)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case isEnabled
        case actionsByBundleID
        case countdownSeconds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
        let rawActions = try container.decodeIfPresent(
            [String: String].self,
            forKey: .actionsByBundleID
        ) ?? [:]
        actionsByBundleID = rawActions.reduce(into: [:]) { result, pair in
            guard let action = PostPasteAction(rawValue: pair.value),
                  action != .none else {
                return
            }
            result[pair.key] = action
        }
        countdownSeconds = Self.normalizedCountdownSeconds(
            try container.decodeIfPresent(
                Int.self,
                forKey: .countdownSeconds
            ) ?? Self.defaultCountdownSeconds
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(
            actionsByBundleID.mapValues(\.rawValue),
            forKey: .actionsByBundleID
        )
        try container.encode(
            Self.normalizedCountdownSeconds(countdownSeconds),
            forKey: .countdownSeconds
        )
    }
}
