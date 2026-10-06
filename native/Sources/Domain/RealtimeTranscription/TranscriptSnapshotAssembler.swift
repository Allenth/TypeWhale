import Foundation

enum TranscriptSnapshotAssembler {
    static func deliveryText(
        confirmed: String,
        volatile: String
    ) -> String {
        guard !confirmed.isEmpty else { return volatile }
        guard !volatile.isEmpty else { return confirmed }

        let confirmedCharacters = Array(confirmed)
        let volatileCharacters = Array(volatile)
        let maximumOverlap = min(confirmedCharacters.count, volatileCharacters.count)

        for length in stride(from: maximumOverlap, through: 1, by: -1) {
            let confirmedSuffix = confirmedCharacters.suffix(length)
            let volatilePrefix = volatileCharacters.prefix(length)
            guard Array(confirmedSuffix) == Array(volatilePrefix),
                  containsWordLikeCharacter(confirmedSuffix) else {
                continue
            }
            return confirmed + String(volatileCharacters.dropFirst(length))
        }

        return confirmed + volatile
    }

    private static func containsWordLikeCharacter<C: Collection>(_ characters: C) -> Bool where C.Element == Character {
        characters.contains { character in
            character.unicodeScalars.contains { scalar in
                CharacterSet.letters.contains(scalar)
                    || CharacterSet.decimalDigits.contains(scalar)
                    || CharacterSet(charactersIn: "\u{4E00}"..."\u{9FFF}").contains(scalar)
            }
        }
    }
}
