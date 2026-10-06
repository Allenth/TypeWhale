import Foundation

struct CapsuleVisibleTextCache {
    private let maxCharacters: Int
    private var cachedSource = ""
    private var cachedWidth = Double.nan
    private var cachedVisible = ""

    init(maxCharacters: Int) {
        self.maxCharacters = max(1, maxCharacters)
    }

    mutating func resolve(
        source: String,
        width: Double,
        measure: (String) -> Double
    ) -> String {
        guard source != cachedSource || width != cachedWidth else {
            return cachedVisible
        }

        let characters = Array(source)
        guard !characters.isEmpty else {
            cachedSource = source
            cachedWidth = width
            cachedVisible = ""
            return cachedVisible
        }

        var low = 1
        var high = min(characters.count, maxCharacters)
        var best = String(characters.suffix(1))
        while low <= high {
            let mid = (low + high) / 2
            let candidate = String(characters.suffix(mid))
            if measure(candidate) <= width {
                best = candidate
                low = mid + 1
            } else {
                high = mid - 1
            }
        }

        cachedSource = source
        cachedWidth = width
        cachedVisible = best
        return best
    }
}
