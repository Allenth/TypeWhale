import Foundation

enum TTSLabRuntimeResolverError: LocalizedError, Equatable {
    case unsupportedModel(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedModel(let id):
            return "尚未接通本地运行时：\(id)"
        }
    }
}

struct TTSLabRuntimeResolver {
    let resourcesURL: URL
    let managedRuntimeRoot: URL

    func resolve(model: TTSLabModel) throws -> TTSLabRuntimeDescriptor {
        switch model.id {
        case "zipvoice-distill-int8-zh-en-emilia":
            return zipVoiceDescriptor(model: model)
        default:
            throw TTSLabRuntimeResolverError.unsupportedModel(model.id)
        }
    }

    private func zipVoiceDescriptor(model: TTSLabModel) -> TTSLabRuntimeDescriptor {
        return TTSLabRuntimeDescriptor(
            adapterID: "sherpa-zipvoice",
            executableURL: URL(fileURLWithPath: "/usr/local/bin/python3"),
            arguments: [
                resourcesURL.appendingPathComponent("tts_benchmark_worker.py").path,
                "--engine", "sherpa-zipvoice",
                "--pack", model.directory.path,
            ],
            environment: offlineEnvironment,
            fingerprint: TTSLabVoiceCatalog.fingerprintValue
        )
    }

    private var offlineEnvironment: [String: String] {
        [
            "HF_HUB_OFFLINE": "1",
            "TRANSFORMERS_OFFLINE": "1",
            "NO_PROXY": "*",
        ]
    }
}
