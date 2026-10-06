import Foundation

@main
struct FunASRSidecarProtocolCheck {
    static func main() throws {
        let request = FunASRSidecarRequest(
            id: "request-1",
            command: .transcribe,
            provider: "fun-asr-nano-2512",
            modelDirectory: "/tmp/model",
            audioPath: "/tmp/audio.wav",
            hotwords: ["Qwen3-ASR"],
            hotwordStrategy: "native_list"
        )
        let data = try JSONEncoder().encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        precondition(json?["id"] as? String == "request-1")
        precondition(json?["command"] as? String == "transcribe")
        precondition(json?["model_dir"] as? String == "/tmp/model")
        precondition(json?["audio_path"] as? String == "/tmp/audio.wav")
        precondition(json?["punctuation_dir"] == nil)
        precondition(json?["hotword_strategy"] as? String == "native_list")

        let responseData = Data(#"{"id":"request-1","ok":true,"text":"你好","engine":"fun-asr-nano-2512/funasr-python","load_sec":1.2,"duration_sec":0.42,"hotword_strategy":"native_list","hotword_count":1}"#.utf8)
        let response = try JSONDecoder().decode(FunASRSidecarResponse.self, from: responseData)
        precondition(response.id == "request-1")
        precondition(response.ok)
        precondition(response.text == "你好")
        precondition(response.durationSeconds == 0.42)
        precondition(response.loadSeconds == 1.2)
        precondition(response.hotwordStrategy == "native_list")
        precondition(response.hotwordCount == 1)

        print("FunASRSidecarProtocolCheck passed")
    }
}
