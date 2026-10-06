import Foundation

@main
struct MeloTTSVoicePackCheck {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let pack = MeloTTSVoicePack(modelsRoot: root)
        precondition(pack.directory.lastPathComponent == "melotts-zh")
        do {
            try pack.validate()
            preconditionFailure("missing pack must fail validation")
        } catch MeloTTSVoicePack.ValidationError.missingManifest { }

        for directory in [pack.runtimePythonURL.deletingLastPathComponent(), pack.modelDirectory, pack.bertDirectory] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try Data("{}".utf8).write(to: pack.manifestURL)
        try Data().write(to: pack.runtimePythonURL)
        try Data().write(to: pack.modelDirectory.appendingPathComponent("config.json"))
        try Data().write(to: pack.modelDirectory.appendingPathComponent("checkpoint.pth"))
        try Data().write(to: pack.bertDirectory.appendingPathComponent("config.json"))
        try Data().write(to: pack.bertDirectory.appendingPathComponent("pytorch_model.bin"))
        do {
            try pack.validate(requireExecutableRuntime: false)
            preconditionFailure("missing tokenizer must fail validation")
        } catch MeloTTSVoicePack.ValidationError.missingBERTFile("tokenizer.json") { }
        try Data().write(to: pack.bertDirectory.appendingPathComponent("tokenizer.json"))

        do {
            try pack.validate(requireExecutableRuntime: false)
            preconditionFailure("missing NLTK tagger must fail validation")
        } catch MeloTTSVoicePack.ValidationError.missingNLTKResource("taggers/averaged_perceptron_tagger_eng") { }

        let taggerDirectory = pack.nltkDataDirectory
            .appendingPathComponent("taggers", isDirectory: true)
            .appendingPathComponent("averaged_perceptron_tagger_eng", isDirectory: true)
        try FileManager.default.createDirectory(at: taggerDirectory, withIntermediateDirectories: true)
        try Data().write(to: taggerDirectory.appendingPathComponent("averaged_perceptron_tagger_eng.weights.json"))

        do {
            try pack.validate(requireExecutableRuntime: false)
            preconditionFailure("missing cmudict must fail validation")
        } catch MeloTTSVoicePack.ValidationError.missingNLTKResource("corpora/cmudict") { }

        let cmuDirectory = pack.nltkDataDirectory
            .appendingPathComponent("corpora", isDirectory: true)
            .appendingPathComponent("cmudict", isDirectory: true)
        try FileManager.default.createDirectory(at: cmuDirectory, withIntermediateDirectories: true)
        try Data().write(to: cmuDirectory.appendingPathComponent("cmudict"))
        try pack.validate(requireExecutableRuntime: false)
        print("MeloTTSVoicePackCheck passed")
    }
}
