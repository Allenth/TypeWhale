import Foundation

@main
enum TTSLabVoiceQualificationStoreCheck {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("TTSLabVoiceQualificationStoreCheck-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let evidence = """
        {
          "modelID": "qwen3-tts-06b-coreml",
          "fingerprint": "qwen3-tts-coreml-0.6b-v1",
          "suite": ["zh-short-v1", "en-short-v1", "mixed-v1"],
          "voices": {
            "uncle-fu": "passed",
            "serena": "passed",
            "ryan": "failed"
          }
        }
        """
        try Data(evidence.utf8).write(
            to: root.appendingPathComponent("qwen3-tts-06b-coreml.json")
        )
        let store = TTSLabVoiceQualificationStore(root: root)
        precondition(
            store.qualifiedVoiceIDs(
                modelID: "qwen3-tts-06b-coreml",
                fingerprint: "qwen3-tts-coreml-0.6b-v1"
            ) == Set(["uncle-fu", "serena"])
        )
        precondition(
            store.qualifiedVoiceIDs(
                modelID: "qwen3-tts-06b-coreml",
                fingerprint: "qwen3-tts-coreml-0.6b-v2"
            ).isEmpty
        )
        precondition(
            store.qualifiedVoiceIDs(
                modelID: "../escape",
                fingerprint: "anything"
            ).isEmpty
        )
        let zipEvidence = """
        {
          "modelID": "zipvoice-distill-int8-zh-en-emilia",
          "fingerprint": "zipvoice-distill-int8-reference-voices-v1",
          "suite": ["zh-short-v1", "en-short-v1", "mixed-v1", "zh-long-v1"],
          "voices": {
            "zipvoice-default": "passed",
            "zipvoice-video-reference": "passed"
          }
        }
        """
        try Data(zipEvidence.utf8).write(
            to: root.appendingPathComponent("zipvoice-distill-int8-zh-en-emilia.json")
        )
        precondition(
            store.qualifiedVoiceIDs(
                modelID: "zipvoice-distill-int8-zh-en-emilia",
                fingerprint: "zipvoice-distill-int8-reference-voices-v1"
            ) == Set(["zipvoice-default", "zipvoice-video-reference"])
        )
        print("TTSLabVoiceQualificationStoreCheck passed")
    }
}
