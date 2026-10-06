import Foundation

protocol DoubaoWebSocketSession: Sendable {
    func connect(request: URLRequest) async throws
    func send(_ data: Data) async throws
    func receive() async throws -> Data
    func close() async
}

struct DoubaoTransportDiagnostics: Sendable, CustomStringConvertible {
    let requestID: String
    let connectID: String
    let endpointHost: String

    var description: String {
        "DoubaoTransportDiagnostics(requestID: \(requestID), connectID: \(connectID), endpointHost: \(endpointHost))"
    }
}

enum DoubaoStreamingTransportError: Error, Sendable, Equatable {
    case connectionFailed
    case notConnected
    case invalidAudioFrame
    case terminal
    case finishTimeout
}

actor DoubaoStreamingTransport: OnlineStreamingTransport {
    static let endpoint = URL(string: "wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_async")!
    static let resourceID = "volc.bigasr.sauc.duration"

    nonisolated let diagnostics: DoubaoTransportDiagnostics
    nonisolated let messageStream: AsyncStream<OnlineProviderMessage>

    private let apiKey: String
    private let socket: any DoubaoWebSocketSession
    private let maximumBufferedAudioFrames: Int
    private let requestID: String
    private let connectTimeoutSeconds: TimeInterval
    private let firstResultTimeoutSeconds: TimeInterval
    private let idleReceiveTimeoutSeconds: TimeInterval
    private let finishTimeoutSeconds: TimeInterval
    private let messageContinuation: AsyncStream<OnlineProviderMessage>.Continuation

    private var encoder: DoubaoASRProtocolEncoder?
    private var outbound: [Data] = []
    private var outboundWaiter: CheckedContinuation<Data?, Never>?
    private var senderTask: Task<Void, Never>?
    private var receiverTask: Task<Void, Never>?
    private var firstResultTask: Task<Void, Never>?
    private var connected = false
    private var terminal = false
    private var socketClosed = false
    private var receivedResult = false
    private var receivedFinal = false
    private var fallbackSequence: UInt64 = 0
    private var inputResampler: StreamingMonoPCMResampler?

    init(
        apiKey: String,
        socket: any DoubaoWebSocketSession = URLSessionDoubaoWebSocketSession(),
        maximumBufferedAudioFrames: Int = 16,
        connectTimeoutSeconds: TimeInterval = 5,
        firstResultTimeoutSeconds: TimeInterval = 8,
        idleReceiveTimeoutSeconds: TimeInterval = 10,
        finishTimeoutSeconds: TimeInterval = 5,
        requestID: @escaping @Sendable () -> String = { UUID().uuidString },
        connectID: @escaping @Sendable () -> String = { UUID().uuidString }
    ) {
        let resolvedRequestID = requestID()
        let resolvedConnectID = connectID()
        self.apiKey = apiKey
        self.socket = socket
        self.maximumBufferedAudioFrames = max(1, maximumBufferedAudioFrames)
        self.requestID = resolvedRequestID
        self.connectTimeoutSeconds = connectTimeoutSeconds
        self.firstResultTimeoutSeconds = firstResultTimeoutSeconds
        self.idleReceiveTimeoutSeconds = idleReceiveTimeoutSeconds
        self.finishTimeoutSeconds = finishTimeoutSeconds
        self.diagnostics = DoubaoTransportDiagnostics(
            requestID: resolvedRequestID,
            connectID: resolvedConnectID,
            endpointHost: Self.endpoint.host ?? "provider"
        )
        var captured: AsyncStream<OnlineProviderMessage>.Continuation!
        self.messageStream = AsyncStream { captured = $0 }
        self.messageContinuation = captured
    }

    nonisolated func messages() -> AsyncStream<OnlineProviderMessage> { messageStream }

    func connect(configuration: OnlineProviderConfiguration) async throws {
        guard !terminal else { throw DoubaoStreamingTransportError.terminal }
        guard !connected else { return }

        messageContinuation.yield(.connectionChanged(.connecting))
        var request = URLRequest(url: Self.endpoint)
        request.timeoutInterval = min(5, max(0.1, configuration.connectionTimeoutSeconds))
        request.setValue(apiKey, forHTTPHeaderField: "X-Api-Key")
        request.setValue(Self.resourceID, forHTTPHeaderField: "X-Api-Resource-Id")
        request.setValue(diagnostics.connectID, forHTTPHeaderField: "X-Api-Connect-Id")
        let connectionRequest = request

        let encoder = DoubaoASRProtocolEncoder(configuration: DoubaoASRRequestConfiguration(
            requestID: requestID,
            userID: requestID,
            sampleRate: configuration.sampleRate,
            channelCount: configuration.channelCount
        ))
        do {
            try await DoubaoOperationTimeout.run(seconds: connectTimeoutSeconds) {
                try await self.socket.connect(request: connectionRequest)
            }
            try await DoubaoOperationTimeout.run(seconds: connectTimeoutSeconds) {
                try await self.socket.send(try encoder.initialConfigurationFrame())
            }
        } catch {
            await fail(code: "connect_failed", message: "Online provider connection failed")
            throw DoubaoStreamingTransportError.connectionFailed
        }

        self.encoder = encoder
        inputResampler = StreamingMonoPCMResampler(outputSampleRate: configuration.sampleRate)
        connected = true
        messageContinuation.yield(.connectionChanged(.connected))
        senderTask = Task { [weak self] in await self?.runSender() }
        receiverTask = Task { [weak self] in await self?.runReceiver() }
    }

    func send(_ frame: AudioFrame) async throws {
        guard connected else { throw DoubaoStreamingTransportError.notConnected }
        guard !terminal, let encoder, var resampler = inputResampler else {
            throw DoubaoStreamingTransportError.terminal
        }
        let normalizedFrame: AudioFrame?
        do {
            normalizedFrame = try resampler.append(frame)
        } catch {
            throw DoubaoStreamingTransportError.invalidAudioFrame
        }
        inputResampler = resampler
        guard let normalizedFrame else { return }
        startFirstResultWatchdogIfNeeded()
        let packet = encoder.audioFrame(
            pcm16LE: encoder.pcm16LE(normalizedFrame.samples),
            isFinal: false
        )
        try await enqueue(packet)
    }

    func finishInput() async throws {
        guard connected else { throw DoubaoStreamingTransportError.notConnected }
        guard !terminal, let encoder else { throw DoubaoStreamingTransportError.terminal }
        startFirstResultWatchdogIfNeeded()
        try await enqueue(encoder.audioFrame(pcm16LE: Data(), isFinal: true))

        let deadline = ContinuousClock.now.advanced(by: .seconds(finishTimeoutSeconds))
        while !receivedFinal, !terminal, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        guard receivedFinal else {
            if !terminal {
                await fail(code: "finish_timeout", message: "Online provider final response timed out")
            }
            throw DoubaoStreamingTransportError.finishTimeout
        }
    }

    func disconnect() async {
        guard !socketClosed else { return }
        terminal = true
        connected = false
        senderTask?.cancel()
        receiverTask?.cancel()
        firstResultTask?.cancel()
        senderTask = nil
        receiverTask = nil
        firstResultTask = nil
        outbound.removeAll(keepingCapacity: false)
        inputResampler?.reset()
        inputResampler = nil
        outboundWaiter?.resume(returning: nil)
        outboundWaiter = nil
        socketClosed = true
        await socket.close()
        messageContinuation.finish()
    }

    private func enqueue(_ packet: Data) async throws {
        guard !terminal else { throw DoubaoStreamingTransportError.terminal }
        if let waiter = outboundWaiter {
            outboundWaiter = nil
            waiter.resume(returning: packet)
            return
        }
        guard outbound.count < maximumBufferedAudioFrames else {
            await fail(code: "audio_queue_overflow", message: "Online audio queue reached its safety limit")
            throw DoubaoStreamingTransportError.terminal
        }
        outbound.append(packet)
    }

    private func nextOutbound() async -> Data? {
        if !outbound.isEmpty { return outbound.removeFirst() }
        if terminal { return nil }
        return await withCheckedContinuation { outboundWaiter = $0 }
    }

    private func runSender() async {
        while !Task.isCancelled, let packet = await nextOutbound() {
            do {
                try await socket.send(packet)
            } catch is CancellationError {
                return
            } catch {
                if !terminal {
                    await fail(code: "send_failed", message: "Online provider send failed")
                }
                return
            }
        }
    }

    private func runReceiver() async {
        while !Task.isCancelled, !terminal {
            do {
                let data: Data
                if receivedResult {
                    data = try await DoubaoOperationTimeout.run(seconds: idleReceiveTimeoutSeconds) {
                        try await self.socket.receive()
                    }
                } else {
                    data = try await socket.receive()
                }
                try await handle(data)
                if receivedFinal { return }
            } catch is CancellationError {
                return
            } catch is DoubaoASRProtocolError {
                if !terminal {
                    await fail(code: "malformed_frame", message: "Online provider returned an invalid frame")
                }
                return
            } catch is DoubaoOperationTimeout.TimeoutError {
                if !terminal {
                    await fail(code: "receive_idle_timeout", message: "Online provider response timed out")
                }
                return
            } catch {
                if !terminal {
                    await fail(code: "receive_failed", message: "Online provider receive failed")
                }
                return
            }
        }
    }

    private func handle(_ data: Data) async throws {
        switch try DoubaoASRProtocolDecoder().decode(data) {
        case .result(let result):
            guard !receivedFinal else { return }
            receivedResult = true
            firstResultTask?.cancel()
            firstResultTask = nil
            fallbackSequence &+= 1
            let sequence = result.providerSequence > 0 ? UInt64(result.providerSequence) : fallbackSequence
            let definite = result.isFinalFrame || result.utterances.contains(where: \.isDefinite)
            if result.isFinalFrame { receivedFinal = true }
            if definite {
                messageContinuation.yield(.finalized(text: result.text, providerSequence: sequence))
            } else {
                messageContinuation.yield(.partial(text: result.text, providerSequence: sequence))
            }
            if result.isFinalFrame {
                messageContinuation.yield(.completed)
            }
        case .error(let providerError):
            let classification: (String, String)
            switch providerError.code {
            case 401, 403:
                classification = ("provider_auth", "Online provider rejected the credential")
            case 429:
                classification = ("provider_quota", "Online provider quota or rate limit was reached")
            default:
                classification = ("provider_error", "Online provider returned an error")
            }
            await fail(code: classification.0, message: classification.1)
        }
    }

    private func fail(code: String, message: String) async {
        guard !terminal else { return }
        terminal = true
        connected = false
        messageContinuation.yield(.failed(code: code, message: message, isRecoverable: true))
        senderTask?.cancel()
        receiverTask?.cancel()
        firstResultTask?.cancel()
        firstResultTask = nil
        outbound.removeAll(keepingCapacity: false)
        inputResampler?.reset()
        inputResampler = nil
        outboundWaiter?.resume(returning: nil)
        outboundWaiter = nil
        if !socketClosed {
            socketClosed = true
            await socket.close()
        }
        messageContinuation.finish()
    }

    private func startFirstResultWatchdogIfNeeded() {
        guard firstResultTask == nil, !receivedResult, !terminal else { return }
        let timeout = firstResultTimeoutSeconds
        firstResultTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(timeout))
                await self?.firstResultTimedOut()
            } catch {}
        }
    }

    private func firstResultTimedOut() async {
        guard !receivedResult, !terminal else { return }
        await fail(code: "first_result_timeout", message: "Online provider first result timed out")
    }
}

actor URLSessionDoubaoWebSocketSession: DoubaoWebSocketSession {
    private var session: URLSession?
    private var task: URLSessionWebSocketTask?

    func connect(request: URLRequest) async throws {
        let session = URLSession(configuration: .ephemeral)
        let task = session.webSocketTask(with: request)
        self.session = session
        self.task = task
        task.resume()
    }

    func send(_ data: Data) async throws {
        guard let task else { throw DoubaoStreamingTransportError.notConnected }
        try await task.send(.data(data))
    }

    func receive() async throws -> Data {
        guard let task else { throw DoubaoStreamingTransportError.notConnected }
        switch try await task.receive() {
        case .data(let data): return data
        case .string: throw DoubaoASRProtocolError.invalidPayload
        @unknown default: throw DoubaoASRProtocolError.invalidPayload
        }
    }

    func close() async {
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
        session?.invalidateAndCancel()
        session = nil
    }
}

private enum DoubaoOperationTimeout {
    struct TimeoutError: Error, Sendable {}

    static func run<T: Sendable>(
        seconds: TimeInterval,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                throw TimeoutError()
            }
            guard let result = try await group.next() else { throw TimeoutError() }
            group.cancelAll()
            return result
        }
    }
}
