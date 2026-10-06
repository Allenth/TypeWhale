import Foundation

enum TTSLabModelCatalog {
    static let retainedModelID = "zipvoice-distill-int8-zh-en-emilia"

    private struct Manifest: Decodable {
        struct Qualification: Decodable {
            let status: TTSLabQualification
        }

        let id: String
        let displayName: String
        let tier: Int
        let runtime: TTSLabRuntime
        let licensePath: String
        let requiredPaths: [String]
        let capabilities: TTSLabCapabilities?
        let qualification: Qualification
        let defaultSpeakerID: Int?
    }

    static var defaultRoot: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TypeWhale Pro", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent("tts", isDirectory: true)
    }

    static func qualifiedModels(
        root: URL = defaultRoot,
        fileManager: FileManager = .default
    ) throws -> [TTSLabModel] {
        try installedModels(root: root, fileManager: fileManager)
            .filter { $0.qualification == .passed }
    }

    static func installedModels(
        root: URL = defaultRoot,
        fileManager: FileManager = .default
    ) throws -> [TTSLabModel] {
        let resolvedRoot = root.resolvingSymlinksInPath().standardizedFileURL
        let children = try fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        )
        let decoder = JSONDecoder()
        var models: [TTSLabModel] = []
        for child in children {
            let resolvedDirectory = child.resolvingSymlinksInPath().standardizedFileURL
            guard isContained(resolvedDirectory, in: resolvedRoot) else { continue }
            let manifestURL = resolvedDirectory.appendingPathComponent("typewhale-model.json")
            guard let data = try? Data(contentsOf: manifestURL),
                  let manifest = try? decoder.decode(Manifest.self, from: data),
                  manifest.id == retainedModelID,
                  manifest.requiredPaths.allSatisfy({
                      fileManager.fileExists(
                          atPath: resolvedDirectory.appendingPathComponent($0).path
                      )
                  }),
                  fileManager.fileExists(
                      atPath: resolvedDirectory.appendingPathComponent(manifest.licensePath).path
                  ) else {
                continue
            }
            models.append(
                TTSLabModel(
                    id: manifest.id,
                    displayName: manifest.displayName,
                    tier: manifest.tier,
                    runtime: manifest.runtime,
                    capabilities: manifest.capabilities ?? .basic,
                    directory: resolvedDirectory,
                    qualification: manifest.qualification.status,
                    defaultSpeakerID: manifest.defaultSpeakerID ?? 0
                )
            )
        }
        return models.sorted {
            if $0.tier != $1.tier { return $0.tier < $1.tier }
            return $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
    }

    private static func isContained(_ child: URL, in root: URL) -> Bool {
        let rootComponents = root.pathComponents
        let childComponents = child.pathComponents
        return childComponents.count > rootComponents.count
            && Array(childComponents.prefix(rootComponents.count)) == rootComponents
    }
}
