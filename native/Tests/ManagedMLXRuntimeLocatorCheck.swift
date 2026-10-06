import Foundation

@main
struct ManagedMLXRuntimeLocatorCheck {
    static func main() throws {
        let fileManager = FileManager.default
        let temporaryRoot = fileManager.temporaryDirectory
            .appendingPathComponent("ManagedMLXRuntimeLocatorCheck-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: temporaryRoot) }

        let candidates = ManagedMLXRuntimeLocator.candidateRoots(in: temporaryRoot)
        precondition(candidates.map(\.path) == [
            temporaryRoot.appendingPathComponent("mlx-llm/v1", isDirectory: true).path,
            temporaryRoot.appendingPathComponent("mlx-asr/v1", isDirectory: true).path,
        ])

        var verifiedPythonPaths: [String] = []
        var verification = ManagedMLXRuntimeProbeResult.failure(
            code: "runtime_import_failed",
            userMessage: "运行环境与当前 macOS 不兼容",
            technicalDetail: "ImportError: dlopen malformed __DATA/__thread_bss"
        )
        var dedicatedVerification: ManagedMLXRuntimeProbeResult?
        let locator = ManagedMLXRuntimeLocator(
            runtimesRootURL: temporaryRoot,
            fileManager: fileManager,
            moduleVerifier: { pythonURL in
                verifiedPythonPaths.append(pythonURL.path)
                if pythonURL.path.contains("/mlx-llm/v1/"),
                   let dedicatedVerification {
                    return dedicatedVerification
                }
                return verification
            }
        )

        precondition(locator.state == .missing)
        precondition(locator.probe().errorCode == "runtime_missing")

        let compatibleRuntime = candidates[1]
        try fileManager.createDirectory(at: compatibleRuntime, withIntermediateDirectories: true)
        precondition(locator.state == .invalid("运行环境 Python 缺失"))
        precondition(locator.probe().errorCode == "runtime_python_missing")

        let python310 = compatibleRuntime.appendingPathComponent("python/bin/python3.10")
        try makeExecutableScript("#!/bin/sh\nexit 0\n", at: python310, fileManager: fileManager)

        let failedProbe = locator.probe()
        precondition(failedProbe.errorCode == "runtime_import_failed")
        precondition(failedProbe.userMessage == "运行环境与当前 macOS 不兼容")
        precondition(failedProbe.technicalDetail?.contains("__thread_bss") == true)
        precondition(locator.state == .ready(python310))
        precondition(verifiedPythonPaths == [python310.path])

        verification = .success(pythonURL: python310)
        precondition(locator.state == .ready(python310))

        let dedicatedRuntime = candidates[0]
        let dedicatedPython = dedicatedRuntime.appendingPathComponent("python/bin/python3")
        try makeExecutableScript("#!/bin/sh\nexit 0\n", at: dedicatedPython, fileManager: fileManager)
        dedicatedVerification = .failure(
            code: "runtime_import_failed",
            userMessage: "专用运行时损坏"
        )
        verification = .success(pythonURL: python310)

        precondition(locator.state == .ready(dedicatedPython))
        let dedicatedFailure = locator.probe()
        precondition(dedicatedFailure.errorCode == "runtime_import_failed")
        precondition(dedicatedFailure.userMessage == "专用运行时损坏")

        dedicatedVerification = .success(pythonURL: dedicatedPython)
        precondition(locator.probe().pythonURL == dedicatedPython)
        precondition(ManagedMLXRuntimeLocator.requiredPackageVersions == [
            "mlx-lm": "0.30.5",
            "transformers": "5.0.0rc3",
        ])

        try verifyActualModuleProbe(fileManager: fileManager, root: temporaryRoot)

        print("ManagedMLXRuntimeLocatorCheck passed")
    }

    private static func verifyActualModuleProbe(fileManager: FileManager, root: URL) throws {
        let scripts = root.appendingPathComponent("probe-scripts", isDirectory: true)

        let successPython = scripts.appendingPathComponent("success-python")
        try makeExecutableScript(
            """
            #!/bin/sh
            case "$2" in
              *"import mlx_lm"*) exit 0 ;;
              *) echo "missing import mlx_lm" >&2; exit 9 ;;
            esac
            """,
            at: successPython,
            fileManager: fileManager
        )
        let success = ManagedMLXRuntimeLocator.verifyModules(pythonURL: successPython)
        precondition(success.isReady)
        precondition(success.pythonURL == successPython)

        let mismatchPython = scripts.appendingPathComponent("mismatch-python")
        try makeExecutableScript(
            "#!/bin/sh\necho 'mlx-lm expected 0.30.5, found 0.29.0' >&2\nexit 41\n",
            at: mismatchPython,
            fileManager: fileManager
        )
        let mismatch = ManagedMLXRuntimeLocator.verifyModules(pythonURL: mismatchPython)
        precondition(mismatch.errorCode == "runtime_version_mismatch")
        precondition(mismatch.userMessage == "运行环境依赖版本不匹配")

        let missingPython = scripts.appendingPathComponent("missing-python")
        try makeExecutableScript(
            "#!/bin/sh\necho 'mlx-lm metadata unavailable' >&2\nexit 42\n",
            at: missingPython,
            fileManager: fileManager
        )
        let missing = ManagedMLXRuntimeLocator.verifyModules(pythonURL: missingPython)
        precondition(missing.errorCode == "runtime_dependency_missing")
        precondition(missing.userMessage == "运行环境依赖缺失")

        let incompatiblePython = scripts.appendingPathComponent("incompatible-python")
        try makeExecutableScript(
            "#!/bin/sh\necho 'ImportError: dlopen failed: malformed __DATA/__thread_bss section' >&2\nexit 1\n",
            at: incompatiblePython,
            fileManager: fileManager
        )
        let incompatible = ManagedMLXRuntimeLocator.verifyModules(pythonURL: incompatiblePython)
        precondition(incompatible.errorCode == "runtime_import_failed")
        precondition(incompatible.userMessage == "运行环境与当前 macOS 不兼容")
        precondition(incompatible.technicalDetail?.contains("__thread_bss") == true)

        let noisyPython = scripts.appendingPathComponent("noisy-python")
        try makeExecutableScript(
            "#!/bin/sh\nprintf '\\001bad\\002 detail\\003' >&2\nexit 1\n",
            at: noisyPython,
            fileManager: fileManager
        )
        let noisy = ManagedMLXRuntimeLocator.verifyModules(pythonURL: noisyPython)
        precondition(noisy.technicalDetail?.contains("\u{1}") == false)
        precondition(noisy.technicalDetail?.contains("\u{2}") == false)

        let hangingPython = scripts.appendingPathComponent("hanging-python")
        try makeExecutableScript(
            "#!/bin/sh\nsleep 2\n",
            at: hangingPython,
            fileManager: fileManager
        )
        let startedAt = Date()
        let timeout = ManagedMLXRuntimeLocator.verifyModules(
            pythonURL: hangingPython,
            timeout: 0.05
        )
        precondition(timeout.errorCode == "runtime_probe_timeout")
        precondition(Date().timeIntervalSince(startedAt) < 1.5)
    }

    private static func makeExecutableScript(
        _ source: String,
        at url: URL,
        fileManager: FileManager
    ) throws {
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try source.write(to: url, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }
}
