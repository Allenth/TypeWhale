import Foundation

@main
struct SherpaMeloTTSVoicePackCheck {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let pack = SherpaMeloTTSVoicePack(modelsRoot: root)
        precondition(pack.directory.lastPathComponent == "sherpa-vits-melo-tts-zh_en")
        do {
            try pack.validate()
            preconditionFailure("missing pack must fail validation")
        } catch SherpaMeloTTSVoicePack.ValidationError.missingManifest { }

        try FileManager.default.createDirectory(at: pack.directory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: pack.dictDirectory, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: pack.manifestURL)
        try Data().write(to: pack.modelURL)
        try Data().write(to: pack.lexiconURL)
        try Data().write(to: pack.tokensURL)
        try Data().write(to: pack.dictDirectory.appendingPathComponent("README.md"))
        try Data().write(to: pack.directory.appendingPathComponent("number.fst"))
        try Data().write(to: pack.directory.appendingPathComponent("phone.fst"))
        do {
            try pack.validate()
            preconditionFailure("missing date.fst must fail validation")
        } catch SherpaMeloTTSVoicePack.ValidationError.missingModelFile("date.fst") { }
        try Data().write(to: pack.directory.appendingPathComponent("date.fst"))
        try pack.validate()
        print("SherpaMeloTTSVoicePackCheck passed")
    }
}
