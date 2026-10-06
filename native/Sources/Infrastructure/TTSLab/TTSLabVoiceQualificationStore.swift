import Foundation

struct TTSLabVoiceQualificationStore {
    private struct Evidence: Decodable {
        let modelID: String
        let fingerprint: String
        let suite: [String]
        let voices: [String: String]
    }

    static var defaultRoot: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TypeWhale Pro/TTSLab/VoiceQualifications", isDirectory: true)
    }

    let root: URL

    init(root: URL = defaultRoot) {
        self.root = root
    }

    func qualifiedVoiceIDs(modelID: String, fingerprint: String) -> Set<String> {
        guard isSafeComponent(modelID) else { return [] }
        let resolvedRoot = root.resolvingSymlinksInPath().standardizedFileURL
        let evidenceURL = root.appendingPathComponent("\(modelID).json")
            .resolvingSymlinksInPath().standardizedFileURL
        guard isContained(evidenceURL, in: resolvedRoot),
              let data = try? Data(contentsOf: evidenceURL),
              let evidence = try? JSONDecoder().decode(Evidence.self, from: data),
              evidence.modelID == modelID,
              evidence.fingerprint == fingerprint,
              evidenceSuiteIsValid(
                  evidence.suite,
                  modelID: modelID
              ) else {
            return []
        }
        return Set(evidence.voices.compactMap { id, status in
            status == "passed" ? id : nil
        })
    }

    private func evidenceSuiteIsValid(_ suite: [String], modelID: String) -> Bool {
        let expected = modelID == "zipvoice-distill-int8-zh-en-emilia"
            ? Set(["zh-short-v1", "en-short-v1", "mixed-v1", "zh-long-v1"])
            : Set(["zh-short-v1", "en-short-v1", "mixed-v1"])
        return Set(suite) == expected
    }

    private func isSafeComponent(_ value: String) -> Bool {
        !value.isEmpty && value.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics
                .union(CharacterSet(charactersIn: "._-"))
                .contains($0)
        }
    }

    private func isContained(_ child: URL, in root: URL) -> Bool {
        let rootComponents = root.pathComponents
        let childComponents = child.pathComponents
        return childComponents.count > rootComponents.count
            && Array(childComponents.prefix(rootComponents.count)) == rootComponents
    }
}
