import Foundation

final class NativeSenseVoiceBridge {
    private enum Engine: Equatable {
        case senseVoice(URL)

        var label: String {
            switch self {
            case .senseVoice:
                return "sensevoice-small/sherpa-native"
            }
        }
    }

    private let queue: DispatchQueue
    private var recognizer: TypeSpeakerNativeRecognizer?
    private var loadedEngineLabel: String?
    private var loadedEngine: Engine?

    init(runtimeName: String) {
        queue = DispatchQueue(label: "com.waykingah.typespeaker.native-asr.\(runtimeName)", qos: .userInitiated)
    }

    var isAvailable: Bool {
        preferredEngine() != nil
    }

    var isVoiceActivityDetectionAvailable: Bool {
        VoiceActivityModelManifest.preferredModelURL != nil
    }

    func containsSpeech(
        audio: URL,
        completion: @escaping (Result<Bool, Error>) -> Void
    ) {
        queue.async { [weak self] in
            guard let self else { return }
            do {
                guard let vadModelURL = VoiceActivityModelManifest.preferredModelURL else {
                    throw self.nativeError("未找到 Silero VAD 人声检测模型")
                }
                var errorPointer: UnsafeMutablePointer<CChar>?
                let result = audio.path.withCString { audioCString in
                    vadModelURL.path.withCString { modelCString in
                        TypeSpeakerNativeVadHasSpeech(audioCString, modelCString, &errorPointer)
                    }
                }
                defer {
                    if let errorPointer { TypeSpeakerNativeStringFree(errorPointer) }
                }
                if let errorPointer {
                    throw self.nativeError(String(cString: errorPointer))
                }
                if result < 0 {
                    throw self.nativeError("Silero VAD 人声检测失败")
                }
                completion(.success(result == 1))
            } catch {
                completion(.failure(error))
            }
        }
    }

    func transcribe(
        audio: URL,
        configuration: ASRConfiguration,
        completion: @escaping (Result<[String: Any], Error>) -> Void
    ) {
        queue.async { [weak self] in
            guard let self else { return }
            let startedAt = Date()
            do {
                let recognizer = try self.loadRecognizer(for: configuration)
                var errorPointer: UnsafeMutablePointer<CChar>?
                let language = configuration.languageMode.senseVoiceLanguage
                let textPointer = audio.path.withCString { audioCString in
                    language.withCString { languageCString in
                        TypeSpeakerNativeRecognizerTranscribe(recognizer, audioCString, languageCString, &errorPointer)
                    }
                }
                defer {
                    if let textPointer { TypeSpeakerNativeStringFree(textPointer) }
                    if let errorPointer { TypeSpeakerNativeStringFree(errorPointer) }
                }
                if let errorPointer {
                    throw self.nativeError(String(cString: errorPointer))
                }
                guard let textPointer else {
                    throw self.nativeError("原生语音识别模型未返回识别结果")
                }
                completion(.success([
                    "text": String(cString: textPointer),
                    "duration_sec": Date().timeIntervalSince(startedAt),
                    "engine": self.loadedEngineLabel ?? "sherpa-native",
                    "language_mode": configuration.languageMode.rawValue,
                    "audio_path": audio.path,
                ]))
            } catch {
                completion(.failure(error))
            }
        }
    }

    func warmUp(configuration: ASRConfiguration = .current()) {
        queue.async { [weak self] in
            guard let self else { return }
            _ = try? self.loadRecognizer(for: configuration)
        }
    }

    func stop() {
        queue.sync {
            if let recognizer {
                TypeSpeakerNativeRecognizerDestroy(recognizer)
                self.recognizer = nil
                self.loadedEngine = nil
            }
        }
    }

    func reload() {
        stop()
    }

    private func loadRecognizer(for configuration: ASRConfiguration) throws -> TypeSpeakerNativeRecognizer {
        guard let engine = preferredEngine(for: configuration) else {
            throw nativeError("未找到已验证的原生语音识别模型")
        }
        if let recognizer, loadedEngine == engine {
            return recognizer
        }
        if let recognizer {
            TypeSpeakerNativeRecognizerDestroy(recognizer)
            self.recognizer = nil
            self.loadedEngine = nil
        }
        var errorPointer: UnsafeMutablePointer<CChar>?
        let created: TypeSpeakerNativeRecognizer?
        switch engine {
        case .senseVoice(let directory):
            let modelPath = directory.appendingPathComponent("model.onnx").path
            let tokensPath = directory.appendingPathComponent("tokens.txt").path
            created = modelPath.withCString { modelCString in
                tokensPath.withCString { tokensCString in
                    "".withCString { hotwordsCString in
                        TypeSpeakerNativeRecognizerCreate(modelCString, tokensCString, hotwordsCString, &errorPointer)
                    }
                }
            }
        }
        defer {
            if let errorPointer { TypeSpeakerNativeStringFree(errorPointer) }
        }
        if let errorPointer {
            throw nativeError(String(cString: errorPointer))
        }
        guard let created else {
            throw nativeError("无法初始化原生语音识别模型")
        }
        recognizer = created
        loadedEngine = engine
        loadedEngineLabel = engine.label
        return created
    }

    private func preferredEngine(for configuration: ASRConfiguration? = nil) -> Engine? {
        if let senseDirectory = SenseVoiceModelManifest.preferredModelDirectory {
            return .senseVoice(senseDirectory)
        }
        return nil
    }

    private func nativeError(_ message: String) -> NSError {
        NSError(domain: "com.waykingah.typespeaker.native-asr", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

final class SenseVoiceRouter {
    private let native: NativeSenseVoiceBridge

    init(runtimeName: String, native: NativeSenseVoiceBridge) {
        self.native = native
    }

    var startupError: String? {
        if native.isAvailable { return nil }
        return "尚未安装原生 SenseVoice 模型"
    }

    func start() {
        native.warmUp()
    }

    func transcribe(
        audio: URL,
        configuration: ASRConfiguration = .current(),
        completion: @escaping (Result<[String: Any], Error>) -> Void
    ) {
        if native.isAvailable {
            native.transcribe(audio: audio, configuration: configuration, completion: completion)
        } else {
            completion(.failure(NSError(
                domain: "com.waykingah.typespeaker.asr",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "请先安装原生 SenseVoice 模型"]
            )))
        }
    }

    func containsSpeech(
        audio: URL,
        completion: @escaping (Result<Bool, Error>) -> Void
    ) {
        guard native.isVoiceActivityDetectionAvailable else {
            completion(.failure(NSError(
                domain: "com.waykingah.typespeaker.asr",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "请先安装 Silero VAD 人声检测模型"]
            )))
            return
        }
        native.containsSpeech(audio: audio, completion: completion)
    }

    func stop() {
        native.stop()
    }
}
