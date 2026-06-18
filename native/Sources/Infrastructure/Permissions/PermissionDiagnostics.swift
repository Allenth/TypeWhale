import ApplicationServices
import AVFoundation
import Foundation

struct PermissionDiagnostics {
    let microphoneAuthorized: Bool
    let accessibilityTrusted: Bool
}

enum PermissionDiagnosticsProvider {
    static func current() -> PermissionDiagnostics {
        PermissionDiagnostics(
            microphoneAuthorized: AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
            accessibilityTrusted: AXIsProcessTrusted()
        )
    }

    static func requestAccessibilityIfNeeded() {
        guard !AXIsProcessTrusted() else { return }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    static func requestMicrophone(completion: @escaping () -> Void) {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined else {
            DispatchQueue.main.async { completion() }
            return
        }
        AVCaptureDevice.requestAccess(for: .audio) { _ in
            DispatchQueue.main.async { completion() }
        }
    }
}
