import Foundation

protocol SherpaNativeRecognizing: AnyObject {
    func transcribe(audioURL: URL) throws -> String
    func close()
}

final class SherpaBenchmarkAdapter: @unchecked Sendable {
    typealias RecognizerFactory = (ASRModelDescriptor, ASRHotwordPayload) throws -> SherpaNativeRecognizing

    private let queue = DispatchQueue(label: "com.waykingah.typewhale.asr-benchmark.sherpa", qos: .userInitiated)
    private let factory: RecognizerFactory
    private var recognizer: SherpaNativeRecognizing?
    private var loadedCandidate: ASRCandidateID?
    private var loadedHotwords: ASRHotwordPayload?
    private let cancellationLock = NSLock()
    private var cancelledRunIDs = Set<UUID>()

    init(factory: @escaping RecognizerFactory = SherpaBenchmarkAdapter.makeNativeRecognizer) {
        self.factory = factory
    }

    func run(
        request: ASREngineRequest,
        completion: @escaping (Result<ASREngineResult, Error>) -> Void
    ) {
        queue.async { [weak self] in
            guard let self else { return }
            do {
                guard !isCancelled(request.runID) else { throw error("测速已取消") }
                let loadStarted = ProcessInfo.processInfo.systemUptime
                if recognizer == nil
                    || loadedCandidate != request.descriptor.id
                    || loadedHotwords != request.hotwords {
                    recognizer?.close()
                    recognizer = try factory(request.descriptor, request.hotwords)
                    loadedCandidate = request.descriptor.id
                    loadedHotwords = request.hotwords
                }
                let loadSeconds = ProcessInfo.processInfo.systemUptime - loadStarted
                guard let recognizer else { throw error("Sherpa 识别器未加载") }
                guard !isCancelled(request.runID) else { throw error("测速已取消") }
                let inferenceStarted = ProcessInfo.processInfo.systemUptime
                let text = try recognizer.transcribe(audioURL: request.audioURL)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let inferenceSeconds = ProcessInfo.processInfo.systemUptime - inferenceStarted
                guard !text.isEmpty else { throw error("Sherpa 模型返回空文本") }
                guard !isCancelled(request.runID) else { throw error("测速已取消") }
                completion(.success(ASREngineResult(
                    text: text,
                    engine: "\(request.descriptor.id.rawValue)/sherpa-native",
                    loadSeconds: loadSeconds,
                    inferenceSeconds: inferenceSeconds,
                    peakRSSMB: 0
                )))
            } catch {
                completion(.failure(error))
            }
        }
    }

    func cancel(runID: UUID) {
        cancellationLock.lock()
        cancelledRunIDs.insert(runID)
        cancellationLock.unlock()
    }

    func unload(completion: @escaping () -> Void = {}) {
        queue.async { [weak self] in
            self?.recognizer?.close()
            self?.recognizer = nil
            self?.loadedCandidate = nil
            self?.loadedHotwords = nil
            self?.cancellationLock.lock()
            self?.cancelledRunIDs.removeAll()
            self?.cancellationLock.unlock()
            completion()
        }
    }

    private func isCancelled(_ runID: UUID) -> Bool {
        cancellationLock.lock()
        defer { cancellationLock.unlock() }
        return cancelledRunIDs.contains(runID)
    }

    private func error(_ message: String) -> NSError {
        NSError(
            domain: "com.waykingah.typewhale.asr-benchmark.sherpa",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }

#if ASR_BENCHMARK_TEST
    private static func makeNativeRecognizer(
        descriptor: ASRModelDescriptor,
        hotwords: ASRHotwordPayload
    ) throws -> SherpaNativeRecognizing {
        throw NSError(domain: "SherpaBenchmarkAdapterCheck", code: 1)
    }
#else
    private static func makeNativeRecognizer(
        descriptor: ASRModelDescriptor,
        hotwords: ASRHotwordPayload
    ) throws -> SherpaNativeRecognizing {
        try NativeSherpaCandidateRecognizer(descriptor: descriptor, hotwords: hotwords)
    }
#endif
}

#if !ASR_BENCHMARK_TEST
private final class NativeSherpaCandidateRecognizer: SherpaNativeRecognizing {
    private var recognizer: TypeSpeakerNativeRecognizer?

    init(descriptor: ASRModelDescriptor, hotwords: ASRHotwordPayload) throws {
        let hotwordText: String
        switch hotwords {
        case .none: hotwordText = ""
        case .text(let value): hotwordText = value
        case .list, .context:
            throw Self.error("Sherpa 模型收到不兼容的热词格式")
        }
        var errorPointer: UnsafeMutablePointer<CChar>?
        let created: TypeSpeakerNativeRecognizer?
        switch descriptor.id {
        case .senseVoiceInt8:
            guard hotwordText.isEmpty else { throw Self.error("SenseVoice 不支持热词") }
            let model = descriptor.modelDirectory.appendingPathComponent("model.onnx").path
            let tokens = descriptor.modelDirectory.appendingPathComponent("tokens.txt").path
            created = model.withCString { modelCString in
                tokens.withCString { tokensCString in
                    "".withCString { empty in
                        TypeSpeakerNativeRecognizerCreate(modelCString, tokensCString, empty, &errorPointer)
                    }
                }
            }
        case .parakeetTDT06B:
            guard hotwordText.isEmpty else { throw Self.error("Parakeet 当前未验证热词") }
            let encoder = descriptor.modelDirectory.appendingPathComponent("encoder.int8.onnx").path
            let decoder = descriptor.modelDirectory.appendingPathComponent("decoder.int8.onnx").path
            let joiner = descriptor.modelDirectory.appendingPathComponent("joiner.int8.onnx").path
            let tokens = descriptor.modelDirectory.appendingPathComponent("tokens.txt").path
            created = encoder.withCString { encoderCString in
                decoder.withCString { decoderCString in
                    joiner.withCString { joinerCString in
                        tokens.withCString { tokensCString in
                            "".withCString { empty in
                                TypeSpeakerNativeParakeetRecognizerCreate(
                                    encoderCString,
                                    decoderCString,
                                    joinerCString,
                                    tokensCString,
                                    empty,
                                    &errorPointer
                                )
                            }
                        }
                    }
                }
            }
        default:
            throw Self.error("候选不是 Sherpa 模型：\(descriptor.id.rawValue)")
        }
        defer {
            if let errorPointer { TypeSpeakerNativeStringFree(errorPointer) }
        }
        if let errorPointer { throw Self.error(String(cString: errorPointer)) }
        guard let created else { throw Self.error("无法初始化 Sherpa 候选模型") }
        recognizer = created
    }

    func transcribe(audioURL: URL) throws -> String {
        guard let recognizer else { throw Self.error("Sherpa 识别器已经释放") }
        var errorPointer: UnsafeMutablePointer<CChar>?
        let pointer = audioURL.path.withCString { audioCString in
            "auto".withCString { languageCString in
                TypeSpeakerNativeRecognizerTranscribe(recognizer, audioCString, languageCString, &errorPointer)
            }
        }
        defer {
            if let pointer { TypeSpeakerNativeStringFree(pointer) }
            if let errorPointer { TypeSpeakerNativeStringFree(errorPointer) }
        }
        if let errorPointer { throw Self.error(String(cString: errorPointer)) }
        guard let pointer else { throw Self.error("Sherpa 模型未返回结果") }
        return String(cString: pointer)
    }

    func close() {
        if let recognizer {
            TypeSpeakerNativeRecognizerDestroy(recognizer)
            self.recognizer = nil
        }
    }

    deinit {
        close()
    }

    private static func error(_ message: String) -> NSError {
        NSError(
            domain: "com.waykingah.typewhale.asr-benchmark.sherpa-native",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}
#endif
