import Foundation

@main
struct FunASRRuntimeManifestCheck {
    static func main() {
        precondition(FunASRRuntimeManifest.version == "2")
        precondition(FunASRRuntimeManifest.pythonVersion == "3.10")
        precondition(Set(FunASRRuntimeManifest.requiredModules) == Set(["funasr", "funasr_onnx", "modelscope", "numpy", "onnxruntime", "torch", "torchaudio"]))
        precondition(FunASRRuntimeManifest.requiredVersions["funasr"] == "1.3.14")
        precondition(FunASRRuntimeManifest.requiredVersions["numpy"] == "1.26.4")
        precondition(FunASRRuntimeManifest.requiredVersions["onnxruntime"] == "1.23.2")
        precondition(FunASRRuntimeManifest.requiredVersions["torch"] == "2.11.0")
        print("FunASRRuntimeManifestCheck passed")
    }
}
