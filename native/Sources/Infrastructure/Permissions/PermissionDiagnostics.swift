import ApplicationServices
import AVFAudio
import Foundation

struct PermissionDiagnostics {
    let microphoneAuthorized: Bool
    let accessibilityTrusted: Bool
    let screenRecordingAuthorized: Bool
}

enum PermissionDiagnosticsProvider {
    enum MicrophoneAccessState {
        case authorized
        case notDetermined
        case denied
    }

    static func current(checkMicrophone: Bool = false) -> PermissionDiagnostics {
        PermissionDiagnostics(
            microphoneAuthorized: checkMicrophone && microphoneAccessState() == .authorized,
            accessibilityTrusted: AXIsProcessTrusted(),
            screenRecordingAuthorized: CGPreflightScreenCaptureAccess()
        )
    }

    static func microphoneAccessState() -> MicrophoneAccessState {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return .authorized
        case .undetermined:
            return .notDetermined
        case .denied:
            return .denied
        @unknown default:
            return .denied
        }
    }

    static func requestAccessibilityIfNeeded() {
        guard !AXIsProcessTrusted() else { return }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    static func requestMicrophone(completion: @escaping (Bool) -> Void) {
        guard AVAudioApplication.shared.recordPermission == .undetermined else {
            DispatchQueue.main.async { completion(AVAudioApplication.shared.recordPermission == .granted) }
            return
        }
        AVAudioApplication.requestRecordPermission { granted in
            DispatchQueue.main.async {
                completion(granted)
            }
        }
    }
}
