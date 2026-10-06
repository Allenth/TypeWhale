import Foundation

struct TTSLabRuntimeAvailability {
    let resolver: TTSLabRuntimeResolver
    let resourcesURL: URL
    let legacyPythonURL: URL
    let fileManager: FileManager

    init(
        resolver: TTSLabRuntimeResolver,
        resourcesURL: URL,
        legacyPythonURL: URL = URL(fileURLWithPath: "/usr/local/bin/python3"),
        fileManager: FileManager = .default
    ) {
        self.resolver = resolver
        self.resourcesURL = resourcesURL
        self.legacyPythonURL = legacyPythonURL
        self.fileManager = fileManager
    }

    func readiness(for model: TTSLabModel) -> TTSLabRuntimeReadiness {
        if let descriptor = try? resolver.resolve(model: model) {
            return fileManager.isExecutableFile(atPath: descriptor.executableURL.path)
                ? .ready
                : .unavailable
        }
        return .unavailable
    }
}
