import Foundation

/// Installs process-wide handlers so that crashes which happen *after* `main`
/// begins (signals such as SIGSEGV/SIGABRT, or uncaught Objective-C exceptions)
/// leave a record in the launch log. Pre-`main` dyld failures are captured by
/// the native LaunchProbe constructor and, failing that, by the system crash
/// report under ~/Library/Logs/DiagnosticReports.
enum CrashReporter {
    /// Signals worth catching for a GUI app. We deliberately keep the handler
    /// tiny and route through the C logger, which only uses POSIX calls.
    private static let fatalSignals: [Int32] = [
        SIGILL, SIGTRAP, SIGABRT, SIGBUS, SIGSEGV, SIGFPE,
    ]

    static func install() {
        NSSetUncaughtExceptionHandler { exception in
            let reason = exception.reason ?? "(no reason)"
            typewhale_launch_probe_log("uncaught exception: \(exception.name.rawValue): \(reason)")
        }

        for signalNumber in fatalSignals {
            signal(signalNumber) { received in
                // Async-signal context: do the minimum, then re-raise with the
                // default disposition so the system still produces a crash report.
                typewhale_launch_probe_log("fatal signal \(received)")
                signal(received, SIG_DFL)
                raise(received)
            }
        }
    }
}
