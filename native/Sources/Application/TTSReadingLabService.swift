import AVFoundation
import Foundation

enum TTSReadingLabState: Equatable {
    case idle
    case preparing
    case generating
    case playing
    case completed(TTSLabMetrics, URL, String?)
    case stopped
    case failed(String)
}

protocol TTSLabAudioPlaying: AnyObject {
    func play(_ url: URL, completion: @escaping (Result<Void, Error>) -> Void)
    func stop()
}

final class TTSLabAudioPlayer: TTSLabAudioPlaying {
    private let lock = NSLock()
    private var player: AVAudioPlayer?

    func play(_ url: URL, completion: @escaping (Result<Void, Error>) -> Void) {
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.prepareToPlay()
            lock.lock()
            self.player = player
            lock.unlock()
            player.play()
            DispatchQueue.global(qos: .utility).async { [weak self, weak player] in
                while player?.isPlaying == true {
                    Thread.sleep(forTimeInterval: 0.05)
                }
                self?.lock.lock()
                if self?.player === player { self?.player = nil }
                self?.lock.unlock()
                completion(.success(()))
            }
        } catch {
            completion(.failure(error))
        }
    }

    func stop() {
        lock.lock()
        let player = self.player
        self.player = nil
        lock.unlock()
        player?.stop()
    }
}

final class TTSReadingLabService {
    typealias WorkerFactory = () -> TTSLabWorkerClient

    var onStateChange: ((TTSReadingLabState) -> Void)?

    private let outputRoot: URL
    private let player: TTSLabAudioPlaying
    private let waveValidator: TTSLabWaveValidator
    private let runtimeResolver: TTSLabRuntimeResolver
    private let workerFactory: WorkerFactory
    private let callbackQueue: DispatchQueue
    private let queue = DispatchQueue(label: "com.typewhale.tts-reading-lab", qos: .userInitiated)
    private let lock = NSLock()
    private var worker: TTSLabWorkerClient?
    private var generation: UInt64 = 0
    private(set) var lastOutputURL: URL?

    init(
        outputRoot: URL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
            .appendingPathComponent("TypeWhale Pro/TTSLab/Outputs", isDirectory: true),
        player: TTSLabAudioPlaying = TTSLabAudioPlayer(),
        waveValidator: TTSLabWaveValidator = TTSLabWaveValidator(),
        runtimeResolver: TTSLabRuntimeResolver = TTSLabRuntimeResolver(
            resourcesURL: Bundle.main.resourceURL!,
            managedRuntimeRoot: FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            )[0]
                .appendingPathComponent("TypeWhale Pro/Runtimes/tts", isDirectory: true)
        ),
        callbackQueue: DispatchQueue = .main,
        workerFactory: @escaping WorkerFactory = {
            TTSLabWorkerClient(
                pythonURL: URL(fileURLWithPath: "/usr/local/bin/python3"),
                workerURL: Bundle.main.url(
                    forResource: "tts_benchmark_worker",
                    withExtension: "py"
                )!
            )
        }
    ) {
        self.outputRoot = outputRoot
        self.player = player
        self.waveValidator = waveValidator
        self.runtimeResolver = runtimeResolver
        self.callbackQueue = callbackQueue
        self.workerFactory = workerFactory
    }

    func start(text: String, model: TTSLabModel, voice: TTSLabVoice? = nil) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            publish(.failed("请输入要朗读的文字"))
            return
        }
        stop(publishStopped: false)
        lock.lock()
        generation &+= 1
        let token = generation
        lock.unlock()
        queue.async { [weak self] in
            self?.run(text: trimmed, model: model, voice: voice, token: token)
        }
    }

    func stop() {
        stop(publishStopped: true)
    }

    func replayLastOutput() {
        guard let lastOutputURL else {
            publish(.failed("还没有可重播的音频"))
            return
        }
        publish(.playing)
        player.play(lastOutputURL) { [weak self] result in
            if case .failure(let error) = result {
                self?.publish(.failed(error.localizedDescription))
            }
        }
    }

    func generatePersonalVoicePreview(
        text: String,
        model: TTSLabModel,
        candidate: TTSLabPersonalVoiceCandidate,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        queue.async { [weak self] in
            guard let self else { return }
            let worker = self.workerFactory()
            do {
                try FileManager.default.createDirectory(
                    at: self.outputRoot,
                    withIntermediateDirectories: true
                )
                let outputURL = self.outputRoot.appendingPathComponent(
                    "personal-voice-preview-\(UUID().uuidString).wav"
                )
                if let descriptor = try? self.runtimeResolver.resolve(model: model) {
                    try worker.start(descriptor: descriptor)
                } else {
                    try worker.start(model: model)
                }
                _ = try worker.prepare()
                let voice = TTSLabVoice(
                    id: TTSLabPersonalVoiceStore.voiceID,
                    displayName: "我的声音",
                    detail: "临时试听",
                    group: .zipVoice,
                    speakerID: nil,
                    isDefault: false
                )
                _ = try worker.synthesize(
                    text: text,
                    outputURL: outputURL,
                    voice: voice,
                    referenceDirectoryName: candidate.directoryURL.lastPathComponent
                )
                _ = try self.waveValidator.validate(url: outputURL)
                worker.shutdown()
                self.callbackQueue.async { completion(.success(outputURL)) }
            } catch {
                worker.stop()
                self.callbackQueue.async { completion(.failure(error)) }
            }
        }
    }

    private func run(
        text: String,
        model: TTSLabModel,
        voice: TTSLabVoice?,
        token: UInt64
    ) {
        let worker = workerFactory()
        var pendingOutputURL: URL?
        lock.lock()
        self.worker = worker
        lock.unlock()
        do {
            try FileManager.default.createDirectory(
                at: outputRoot,
                withIntermediateDirectories: true
            )
            let outputURL = outputRoot.appendingPathComponent(
                "\(model.id)-\(UUID().uuidString).wav"
            )
            pendingOutputURL = outputURL
            publish(.preparing)
            if let descriptor = try? runtimeResolver.resolve(model: model) {
                try worker.start(descriptor: descriptor)
            } else {
                try worker.start(model: model)
            }
            _ = try worker.prepare()
            guard isCurrent(token) else { return }
            publish(.generating)
            let metrics: TTSLabMetrics
            let actualVoiceID: String?
            if let voice {
                let synthesis = try worker.synthesize(
                    text: text,
                    outputURL: outputURL,
                    voice: voice
                )
                metrics = synthesis.metrics
                actualVoiceID = synthesis.actualVoiceID
            } else {
                metrics = try worker.synthesize(
                    text: text,
                    outputURL: outputURL,
                    speakerID: model.defaultSpeakerID
                )
                actualVoiceID = nil
            }
            _ = try waveValidator.validate(url: outputURL)
            guard isCurrent(token) else { return }
            lastOutputURL = outputURL
            pendingOutputURL = nil
            publish(.playing)
            player.play(outputURL) { [weak self] result in
                guard let self, self.isCurrent(token) else { return }
                switch result {
                case .success:
                    self.publish(.completed(
                        metrics,
                        outputURL,
                        actualVoiceID
                    ))
                case .failure(let error):
                    self.publish(.failed(error.localizedDescription))
                }
            }
        } catch {
            if let pendingOutputURL {
                try? FileManager.default.removeItem(at: pendingOutputURL)
            }
            if isCurrent(token) {
                publish(.failed(error.localizedDescription))
            }
        }
    }

    private func stop(publishStopped: Bool) {
        lock.lock()
        generation &+= 1
        let worker = self.worker
        self.worker = nil
        lock.unlock()
        worker?.cancel()
        player.stop()
        if publishStopped { publish(.stopped) }
    }

    private func isCurrent(_ token: UInt64) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return generation == token
    }

    private func publish(_ state: TTSReadingLabState) {
        callbackQueue.async { [weak self] in
            self?.onStateChange?(state)
        }
    }
}
