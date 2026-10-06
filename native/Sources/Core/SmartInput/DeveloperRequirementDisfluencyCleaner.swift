import Foundation

enum DeveloperRequirementDisfluencyCleaner {
    static func clean(_ text: String) -> String {
        let characters = Array(text)
        guard characters.count >= 4 else { return text }

        var cleaned: [Character] = []
        cleaned.reserveCapacity(characters.count)
        var index = 0
        while index < characters.count {
            if index + 3 < characters.count,
               characters[index] == "不",
               characters[index + 2] == "不",
               characters[index + 1] == characters[index + 3],
               isCJK(characters[index + 1]) {
                index += 2
                continue
            }
            cleaned.append(characters[index])
            index += 1
        }
        return String(separateRepeatedActionClauses(in: cleaned))
    }

    private static func isCJK(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy {
            (0x4E00...0x9FFF).contains($0.value)
        }
    }

    private static func separateRepeatedActionClauses(
        in characters: [Character]
    ) -> [Character] {
        var separated = characters
        for commaIndex in separated.indices
        where separated[commaIndex] == "，" || separated[commaIndex] == "," {
            let searchEnd = min(commaIndex + 14, separated.count)
            guard commaIndex + 3 < searchEnd else { continue }
            for alsoIndex in (commaIndex + 1)..<searchEnd {
                if "，,。；;\n".contains(separated[alsoIndex]) {
                    break
                }
                guard separated[alsoIndex] == "也",
                      alsoIndex + 2 < separated.count else {
                    continue
                }
                let action = [
                    separated[alsoIndex + 1],
                    separated[alsoIndex + 2],
                ]
                if contains(
                    action,
                    in: separated,
                    before: commaIndex
                ) {
                    separated[commaIndex] = "。"
                }
                break
            }
        }
        return separated
    }

    private static func contains(
        _ pair: [Character],
        in characters: [Character],
        before endIndex: Int
    ) -> Bool {
        guard pair.count == 2, endIndex >= 2 else { return false }
        let startIndex = max(0, endIndex - 20)
        for index in startIndex..<(endIndex - 1)
        where characters[index] == pair[0]
            && characters[index + 1] == pair[1] {
            return true
        }
        return false
    }
}
