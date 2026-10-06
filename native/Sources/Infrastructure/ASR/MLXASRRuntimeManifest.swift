import Foundation

enum MLXASRRuntimeManifest {
    static let version = "v1"
    static let pythonVersion = "3.10"
    static let requirementsResourceName = "mlx_asr_runtime_requirements"
    static let requirementsSHA256 = "3e53de81eceab7f4c5223ea2bd7915b627b98a24f4c06310039affa339c36ccb"
    static let pythonArchiveURL = FunASRRuntimeManifest.pythonArchiveURL
    static let pythonArchiveSHA256 = FunASRRuntimeManifest.pythonArchiveSHA256
    static let requiredModules = ["mlx", "mlx_audio", "mlx_whisper", "numpy"]
    static let requiredVersions: [String: String] = [
        "mlx": "0.30.6", "mlx_audio": "0.3.1", "mlx_whisper": "0.4.3", "numpy": "1.26.4",
    ]
}
