import Foundation
@main struct MLXASRRuntimeInstallerCheck {
    static func main() {
        precondition(MLXASRRuntimeInstaller.sha256(Data("abc".utf8)) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let data = try! Data(contentsOf: root.appendingPathComponent("native/Resources/mlx_asr_runtime_requirements.txt"))
        precondition(MLXASRRuntimeInstaller.requirementsAreValid(data))
        let args = MLXASRRuntimeInstaller.pipInstallArguments(requirementsURL: URL(fileURLWithPath:"/tmp/r"), cacheURL: URL(fileURLWithPath:"/tmp/c"))
        precondition(args.contains("--no-user") && args.contains("--cache-dir") && args.contains("--require-hashes"))
        print("MLXASRRuntimeInstallerCheck passed")
    }
}
