import Foundation

@main
struct FunASRRuntimeInstallerCheck {
    static func main() {
        precondition(FunASRRuntimeInstaller.sha256(Data("abc".utf8)) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        precondition(FunASRRuntimeManifest.pythonArchiveURL.host == "github.com")
        precondition(FunASRRuntimeManifest.pythonArchiveSHA256.count == 64)
        precondition(FunASRRuntimeInstaller.archiveIsValid(Data("abc".utf8), expectedSHA256: "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"))
        precondition(!FunASRRuntimeInstaller.archiveIsValid(Data("abcd".utf8), expectedSHA256: "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"))
        let pipArguments = FunASRRuntimeInstaller.pipInstallArguments(
            requirementsURL: URL(fileURLWithPath: "/tmp/requirements.txt"),
            cacheURL: URL(fileURLWithPath: "/tmp/cache")
        )
        precondition(pipArguments.contains("--retries"))
        precondition(pipArguments.contains("--resume-retries"))
        precondition(pipArguments.contains("--timeout"))
        precondition(pipArguments.contains("--cache-dir"))
        let curlArguments = FunASRRuntimeInstaller.pythonDownloadArguments(
            destinationURL: URL(fileURLWithPath: "/tmp/python.tar.gz")
        )
        precondition(curlArguments.contains("--retry-all-errors"))
        precondition(curlArguments.contains("--continue-at"))
        print("FunASRRuntimeInstallerCheck passed")
    }
}
