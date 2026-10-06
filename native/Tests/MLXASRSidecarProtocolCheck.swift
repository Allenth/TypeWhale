import Foundation

@main
struct MLXASRSidecarProtocolCheck {
    static func main() throws {
        let request = MLXASRSidecarRequest(
            id: "1", command: .transcribe, provider: "qwen3-asr-0.6b-mlx",
            modelDirectory: "/local/model", audioPath: "/tmp/a.wav", contextPrompt: nil
        )
        let data = try JSONEncoder().encode(request)
        let object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        precondition(object["model_dir"] as? String == "/local/model")
        precondition(object["context_prompt"] == nil)
        let response = try JSONDecoder().decode(MLXASRSidecarResponse.self, from: Data("""
        {"id":"1","ok":true,"text":"结果","engine":"qwen3-asr-0.6b-mlx/mlx","load_sec":1.2,"duration_sec":0.3}
        """.utf8))
        precondition(response.loadSeconds == 1.2 && response.durationSeconds == 0.3)
        print("MLXASRSidecarProtocolCheck passed")
    }
}
