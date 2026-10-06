import Foundation

enum FunASRRuntimeManifest {
    static let version = "2"
    static let pythonVersion = "3.10"
    static let requirementsResourceName = "funasr_runtime_requirements"
    static let pythonArchiveURL = URL(string: "https://github.com/astral-sh/python-build-standalone/releases/download/20260510/cpython-3.10.20%2B20260510-aarch64-apple-darwin-install_only.tar.gz")!
    static let pythonArchiveSHA256 = "22f02aa2458efa28029f91800c3d85a270ae308a2d8450f3f6cef49f56abfa48"
    static let requiredModules = ["funasr", "funasr_onnx", "modelscope", "numpy", "onnxruntime", "torch", "torchaudio"]
    static let requiredVersions: [String: String] = [
        "funasr": "1.3.14",
        "modelscope": "1.38.1",
        "numpy": "1.26.4",
        "onnxruntime": "1.23.2",
        "torch": "2.11.0",
        "torchaudio": "2.11.0",
    ]
}
