import Foundation

struct MinimalBlackRenderState: Equatable, Sendable {
    static let empty = MinimalBlackRenderState(
        stableWindowText: "",
        volatileTailText: "",
        visibleCharacterCount: 0
    )

    private(set) var stableWindowText: String
    private(set) var volatileTailText: String
    var visibleCharacterCount: Int

    var displayText: String { stableWindowText + volatileTailText }
    var stableCharacterCount: Int { stableWindowText.count }
    var visibleText: String {
        String(displayText.prefix(max(0, min(visibleCharacterCount, displayText.count))))
    }
    var visibleStableCharacterCount: Int {
        min(stableCharacterCount, visibleText.count)
    }

    mutating func apply(stableWindowText: String, volatileTailText: String) {
        self.stableWindowText = stableWindowText
        self.volatileTailText = volatileTailText
        visibleCharacterCount = min(visibleCharacterCount, displayText.count)
    }
}
