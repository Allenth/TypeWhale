import Foundation

private enum Command: String, Codable { case health, warmup, transcribe, shutdown }
private struct Request: Codable {
    let id: String; let command: Command; let provider: String?; let modelDirectory: String?; let audioPath: String?
    enum CodingKeys: String, CodingKey { case id, command, provider; case modelDirectory = "model_dir"; case audioPath = "audio_path" }
}
private struct Response: Codable {
    let id: String; let ok: Bool; let ready: Bool?; let text: String?; let engine: String?
    let loadSeconds: Double?; let durationSeconds: Double?; let error: String?; let shutdown: Bool?
    enum CodingKeys: String, CodingKey { case id, ok, ready, text, engine, error, shutdown; case loadSeconds = "load_sec"; case durationSeconds = "duration_sec" }
}

private final class Runtime {
    private var recognizer: TypeSpeakerNativeRecognizer?
    private var provider: String?

    deinit { close() }

    func warmUp(provider: String, modelDirectory: String) throws -> Double {
        if self.provider == provider, recognizer != nil { return 0 }
        close()
        let started = ProcessInfo.processInfo.systemUptime
        var errorPointer: UnsafeMutablePointer<CChar>?
        let created: TypeSpeakerNativeRecognizer?
        guard provider == "parakeet-tdt-0.6b-v2-sherpa-int8" else {
            throw failure("不支持的 Sherpa helper provider：\(provider)")
        }
        do {
            let root = URL(fileURLWithPath: modelDirectory, isDirectory: true)
            created = root.appendingPathComponent("encoder.int8.onnx").path.withCString { encoder in
                root.appendingPathComponent("decoder.int8.onnx").path.withCString { decoder in
                    root.appendingPathComponent("joiner.int8.onnx").path.withCString { joiner in
                        root.appendingPathComponent("tokens.txt").path.withCString { tokens in
                            "".withCString { empty in
                                TypeSpeakerNativeParakeetRecognizerCreate(encoder, decoder, joiner, tokens, empty, &errorPointer)
                            }
                        }
                    }
                }
            }
        }
        defer { if let errorPointer { TypeSpeakerNativeStringFree(errorPointer) } }
        if let errorPointer { throw failure(String(cString: errorPointer)) }
        guard let created else { throw failure("Sherpa helper 无法创建识别器") }
        recognizer = created; self.provider = provider
        return ProcessInfo.processInfo.systemUptime - started
    }

    func transcribe(provider: String, audioPath: String) throws -> (String, Double) {
        guard self.provider == provider, let recognizer else { throw failure("Sherpa helper 模型尚未预热") }
        let started = ProcessInfo.processInfo.systemUptime
        var errorPointer: UnsafeMutablePointer<CChar>?
        let pointer = audioPath.withCString { audio in
            "auto".withCString { language in TypeSpeakerNativeRecognizerTranscribe(recognizer, audio, language, &errorPointer) }
        }
        defer { if let pointer { TypeSpeakerNativeStringFree(pointer) }; if let errorPointer { TypeSpeakerNativeStringFree(errorPointer) } }
        if let errorPointer { throw failure(String(cString: errorPointer)) }
        guard let pointer else { throw failure("Sherpa helper 未返回结果") }
        return (String(cString: pointer), ProcessInfo.processInfo.systemUptime - started)
    }

    func close() {
        if let recognizer { TypeSpeakerNativeRecognizerDestroy(recognizer) }
        recognizer = nil; provider = nil
    }

    private func failure(_ message: String) -> NSError {
        NSError(domain: "com.waykingah.typewhale.sherpa-helper", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

@main
private struct TypeWhaleSherpaASR {
    static func main() {
        let runtime = Runtime(), encoder = JSONEncoder(), decoder = JSONDecoder()
        while let line = readLine() {
            guard let data = line.data(using: .utf8), let request = try? decoder.decode(Request.self, from: data) else { continue }
            let response: Response
            do {
                switch request.command {
                case .health:
                    response = Response(id: request.id, ok: true, ready: true, text: nil, engine: nil, loadSeconds: nil, durationSeconds: nil, error: nil, shutdown: nil)
                case .warmup:
                    guard let provider = request.provider, let directory = request.modelDirectory else { throw failure("warmup 缺少 provider/model_dir") }
                    let seconds = try runtime.warmUp(provider: provider, modelDirectory: directory)
                    response = Response(id: request.id, ok: true, ready: true, text: nil, engine: "\(provider)/sherpa-helper", loadSeconds: seconds, durationSeconds: nil, error: nil, shutdown: nil)
                case .transcribe:
                    guard let provider = request.provider, let audio = request.audioPath else { throw failure("transcribe 缺少 provider/audio_path") }
                    let (text, seconds) = try runtime.transcribe(provider: provider, audioPath: audio)
                    response = Response(id: request.id, ok: true, ready: true, text: text, engine: "\(provider)/sherpa-helper", loadSeconds: nil, durationSeconds: seconds, error: nil, shutdown: nil)
                case .shutdown:
                    runtime.close()
                    response = Response(id: request.id, ok: true, ready: nil, text: nil, engine: nil, loadSeconds: nil, durationSeconds: nil, error: nil, shutdown: true)
                }
            } catch {
                response = Response(id: request.id, ok: false, ready: false, text: nil, engine: nil, loadSeconds: nil, durationSeconds: nil, error: error.localizedDescription, shutdown: nil)
            }
            if let output = try? encoder.encode(response) { FileHandle.standardOutput.write(output); FileHandle.standardOutput.write(Data([0x0A])) }
            if request.command == .shutdown { break }
        }
    }

    static func failure(_ message: String) -> NSError {
        NSError(domain: "com.waykingah.typewhale.sherpa-helper", code: 2, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
