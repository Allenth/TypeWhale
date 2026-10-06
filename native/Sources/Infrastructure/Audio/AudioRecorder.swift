import AVFAudio
import AudioToolbox
import CoreAudio
import Darwin
import Foundation

struct ExperimentalPreviewAudioSnapshot: Sendable {
    let taskID: UUID
    let audioURL: URL
    let chunkIndex: Int
    let audioRange: PreviewAudioRange
    let boundary: PreviewBoundary
}

struct ExperimentalPreviewTailSnapshot: Sendable {
    let taskID: UUID
    let audioURL: URL
    let audioRange: PreviewAudioRange
}

final class LockedRecordingState: @unchecked Sendable {
    private var lock = os_unfair_lock_s()
    private var acceptingAudio = false
    private var frameCount: AVAudioFramePosition = 0
    private var peakLevel: Float = 0
    private var writeError: Error?

    func begin() {
        os_unfair_lock_lock(&lock)
        acceptingAudio = true
        frameCount = 0
        peakLevel = 0
        writeError = nil
        os_unfair_lock_unlock(&lock)
    }

    func stopAccepting() {
        os_unfair_lock_lock(&lock)
        acceptingAudio = false
        os_unfair_lock_unlock(&lock)
    }

    func resumeAccepting() {
        os_unfair_lock_lock(&lock)
        if writeError == nil {
            acceptingAudio = true
        }
        os_unfair_lock_unlock(&lock)
    }

    func shouldAcceptAudio() -> Bool {
        os_unfair_lock_lock(&lock)
        let value = acceptingAudio
        os_unfair_lock_unlock(&lock)
        return value
    }

    func addFrames(_ count: AVAudioFramePosition) {
        os_unfair_lock_lock(&lock)
        frameCount += count
        os_unfair_lock_unlock(&lock)
    }

    func observePeak(_ value: Float) {
        os_unfair_lock_lock(&lock)
        peakLevel = max(peakLevel, value)
        os_unfair_lock_unlock(&lock)
    }

    func record(error: Error) {
        os_unfair_lock_lock(&lock)
        writeError = writeError ?? error
        acceptingAudio = false
        os_unfair_lock_unlock(&lock)
    }

    func snapshot() -> (AVAudioFramePosition, Error?, Float) {
        os_unfair_lock_lock(&lock)
        let value = (frameCount, writeError, peakLevel)
        os_unfair_lock_unlock(&lock)
        return value
    }
}

enum AudioInputSwitchResult: Equatable {
    case switched(deviceName: String)
    case restoredPrevious(deviceName: String, error: String)
    case followedSystem(deviceName: String, error: String?)
    case unavailable(error: String)
    case superseded
}

enum AudioInputRouteEvent {
    case manualDeviceDisconnected(name: String)
    case systemDefaultChanged
}

final class AudioRecorder: @unchecked Sendable {
    private let outputURLProvider: @Sendable () -> URL
    private static let lowLevelSpeechFloor: Float = 0.08
    private static let lowLevelSpeechReference: Float = 0.0012
    private static let lowLevelSpectralReference: Float = 0.00042
    private enum CaptureLifecycle {
        case idle
        case recording
        case switching
        case stopping
    }

    private struct PendingRealtimeChunk {
        let ticket: ChunkCommitTicket
        let taskID: UUID
        let samples: [Float]
        let sampleRate: Int
        let audioDuration: TimeInterval
    }
    private enum RealtimeTiming {
        static let firstSnapshotSeconds: Double = 0.30
        static let snapshotIntervalSeconds: Double = 0.50
        /// 实时预览分块：到软目标后，等下一个停顿（Silero 判定当前无人声）再在停顿处冻结提交，
        /// 让块边界落在词/句间隙、不切词；若一直不停顿则到硬上限强制提交兜底。
        /// 既封住长录音的 O(n²) 重识别开销，也让已提交文本稳定不跳变。
    }
    /// 实时人声门控（A 方案）：每隔 intervalSeconds 把最近 windowSeconds 的单声道 PCM
    /// 交给 Silero 跑一次，作为"当前是否有人声"的权威信号。与实时预览开关无关，始终运行。
    private enum VoiceProbe {
        static let windowSeconds: Double = 0.7
        static let intervalSeconds: Double = 0.4
        static let firstSeconds: Double = 0.3
    }
    /// 胶囊实时电平读数：峰值保持（快升慢降）+ 约每 0.1s 上报一次 dBFS，避免数字抖动。
    private enum LevelReadout {
        static let intervalSeconds: Double = 0.1
        static let holdDecay: Float = 0.88
    }
    private enum Finalization {
        static let tailPaddingSeconds: Double = 0.25
    }
    private enum RouteStability {
        static let startupGraceSeconds: TimeInterval = 1.2
    }
    private struct InputRouteSnapshot {
        let manualDeviceID: AudioDeviceID?
        let defaultDeviceID: AudioDeviceID?
        let startedAt: Date

        var targetDescription: String {
            if let manualDeviceID {
                return "manual:\(manualDeviceID)"
            }
            return "default:\(defaultDeviceID.map(String.init) ?? "unknown")"
        }

        func stillTargetsSameInput() -> Bool {
            if let manualDeviceID {
                return AudioInputDeviceProvider.devices().contains { $0.id == manualDeviceID }
            }
            guard let defaultDeviceID else { return false }
            return AudioInputDeviceProvider.currentDefaultInputDeviceID() == defaultDeviceID
        }
    }

    private var engine: AVAudioEngine?
    private var manualCapture: ManualAudioInputCapture?
    private var currentFile: AVAudioFile?
    private var canonicalConverter: CanonicalAudioConverter?
    private var currentInputDeviceID: AudioDeviceID?
    private var currentInputDeviceName = "跟随系统"
    private var captureLifecycle: CaptureLifecycle = .idle
    private var switchGeneration = AudioInputSwitchGeneration()
    private var inputTapInstalled = false
    private var inputReleaseGeneration = 0
    private let processingQueue = DispatchQueue(label: "com.waykingah.typespeaker.audio-processing", qos: .userInteractive)
    private let routeControlQueue = DispatchQueue(label: "com.waykingah.typespeaker.audio-route-control", qos: .userInitiated)
    private let snapshotQueue = DispatchQueue(label: "com.waykingah.typespeaker.audio-snapshots", qos: .userInitiated)
    private let processingGroup = DispatchGroup()
    private let state = LockedRecordingState()
    private let audioFrameFanOut = AudioFrameFanOut()
    private var startedAt = Date()
    private var currentTaskID: UUID?
    private var currentPendingURL: URL?
    private var realtimeBuffers: [AVAudioPCMBuffer] = []
    private var experimentalContextBuffers: [AVAudioPCMBuffer] = []
    private var experimentalPreviewEnabled = false
    private var pendingExperimentalBoundary: (boundary: PreviewBoundary, frame: AVAudioFramePosition)?
    private var completedExperimentalSnapshots: [ExperimentalPreviewAudioSnapshot] = []
    private var nextRealtimeFrame: AVAudioFramePosition = 0
    private var realtimeChunkStartFrame: AVAudioFramePosition = 0
    private var realtimeChunkIndex = 0
    private let realtimeChunkBoundaryPolicy = RealtimeChunkBoundaryPolicy()
    private var finalChunkCommitMachine = ChunkCommitStateMachine(chunkIndex: 0, startFrame: 0)
    private var pendingRealtimeChunk: PendingRealtimeChunk?
    /// 由协调器按 Silero 探测结果实时推送：当前是否有人声。用于在停顿处对齐分块边界（不切词）。
    private var realtimeVoiceActive = true
    private var realtimeVoiceObserved = false
    private var realtimeEnabled = false
    private var vadWindowSamples: [Float] = []
    private var vadWindowCapacity = 0
    private var nextVoiceProbeFrame: AVAudioFramePosition = 0
    private var recentPeakHold: Float = 0
    private var nextLevelFrame: AVAudioFramePosition = 0
    private var snapshotRequestedWhileBusy = false
    private var inputRouteObserver: AudioInputRouteObserver?
    private var engineConfigurationObserver: NSObjectProtocol?
    private var inputRouteSnapshot: InputRouteSnapshot?
    private var inputFormatDescription = ""
    private var inputSourceDescription = "麦克风"
    private var latestEmptyRecordingReason: String?
    private(set) var isRecording = false
    var onBands: (([Float]) -> Void)?
    /// (taskID, 单声道 PCM samples, 采样率, 块序号, 是否为该块的最终快照, 音频时长, 整段录音绝对范围)。块最终快照用于冻结提交、不会被丢弃。
    var onRealtimeSnapshot: ((UUID, [Float], Int, Int, Bool, TimeInterval, PreviewAudioRange) -> Void)?
    var onInputRouteChanged: ((String) -> Void)?
    var onInputRouteEvent: ((AudioInputRouteEvent) -> Void)?
    var onInputRecoveryFailed: ((String) -> Void)?
    /// 实时人声门控信号：(最近窗口的单声道 PCM, 采样率)。约每 0.4s 触发一次，在后台队列回调。
    var onVoiceProbe: ((UUID, [Float], Int) -> Void)?
    /// 实时输入电平（dBFS，≤0）。约每 0.1s 在 main 回调一次，供胶囊显示。
    var onInputLevelDb: ((Float) -> Void)?
    var onExperimentalPreviewSnapshot: ((ExperimentalPreviewAudioSnapshot) -> Void)?

    init(outputURLProvider: @escaping @Sendable () -> URL = {
        AppPaths.recordings.appendingPathComponent("latest.wav")
    }) {
        self.outputURLProvider = outputURLProvider
    }

    func subscribeToAudioFrames(capacity: Int) -> AudioFrameFanOutSubscription {
        audioFrameFanOut.subscribe(capacity: capacity)
    }

    func unsubscribeFromAudioFrames(_ id: UUID) {
        audioFrameFanOut.unsubscribe(id)
    }

    var emptyRecordingReason: String? {
        latestEmptyRecordingReason
    }

    var latestURL: URL {
        outputURLProvider()
    }

    func start(
        taskID: UUID,
        realtimeEnabled: Bool,
        inputDeviceID: AudioDeviceID?,
        inputDeviceName: String = "跟随系统",
        experimentalPreviewEnabled: Bool = false
    ) throws {
        guard !isRecording else { return }
        inputReleaseGeneration += 1
        let directory = latestURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let pendingURL = directory.appendingPathComponent(".recording-\(taskID.uuidString).wav")
        try? FileManager.default.removeItem(at: pendingURL)

        let engine: AVAudioEngine?
        let input: AVAudioInputNode?
        let manualCapture: ManualAudioInputCapture?
        let format: AVAudioFormat
        if let inputDeviceID {
            let capture = try ManualAudioInputCapture(deviceID: inputDeviceID)
            engine = nil
            input = nil
            manualCapture = capture
            format = capture.format
        } else {
            let defaultEngine = AVAudioEngine()
            engine = defaultEngine
            input = defaultEngine.inputNode
            manualCapture = nil
            format = defaultEngine.inputNode.outputFormat(forBus: 0)
        }
        self.engine = engine
        self.manualCapture = manualCapture
        guard format.sampleRate > 0, format.channelCount > 0 else {
            self.engine = nil
            try? FileManager.default.removeItem(at: pendingURL)
            throw NSError(
                domain: "TypeWhale.AudioRecorder",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey: "当前麦克风输入不可用。若正在语音通话，请检查系统输入设备或关闭通话软件的独占/降噪处理。"
                ]
            )
        }
        try prepareRecordingSession(
            taskID: taskID,
            inputFormat: format,
            pendingURL: pendingURL,
            realtimeEnabled: realtimeEnabled,
            experimentalPreviewEnabled: experimentalPreviewEnabled,
            inputDeviceID: inputDeviceID,
            inputDeviceName: inputDeviceName,
            inputSourceDescription: "麦克风",
            monitorsInputRoute: true
        )
        if let input, let engine {
            installCaptureTap(on: input, format: format, taskID: taskID)
            engine.prepare()
        } else if let manualCapture {
            manualCapture.onBuffer = { [weak self] buffer in
                guard let self else { return }
                self.processingGroup.enter()
                guard self.state.shouldAcceptAudio(), let copy = self.copy(buffer: buffer) else {
                    self.processingGroup.leave()
                    return
                }
                self.processingQueue.async {
                    defer { self.processingGroup.leave() }
                    self.processCapturedBuffer(copy, taskID: taskID)
                }
            }
        }
        do {
            if let engine { try engine.start() } else { try manualCapture?.start() }
            startedAt = Date()
            startInputRouteMonitoring()
        } catch {
            state.stopAccepting()
            isRecording = false
            captureLifecycle = .idle
            currentTaskID = nil
            currentPendingURL = nil
            currentFile = nil
            canonicalConverter = nil
            releaseInputNode(reason: "start_failed")
            try? FileManager.default.removeItem(at: pendingURL)
            throw error
        }
    }

    func startExternal(
        taskID: UUID,
        sampleRate: Int,
        realtimeEnabled: Bool,
        sourceName: String,
        experimentalPreviewEnabled: Bool = false
    ) throws {
        guard !isRecording else { return }
        guard sampleRate > 0,
              let inputFormat = AVAudioFormat(
                  commonFormat: .pcmFormatInt16,
                  sampleRate: Double(sampleRate),
                  channels: 1,
                  interleaved: false
              ) else {
            throw RemotePCMBufferError.invalidSampleRate
        }
        inputReleaseGeneration += 1
        let directory = latestURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let pendingURL = directory.appendingPathComponent(".recording-\(taskID.uuidString).wav")
        try? FileManager.default.removeItem(at: pendingURL)

        engine = nil
        manualCapture = nil
        try prepareRecordingSession(
            taskID: taskID,
            inputFormat: inputFormat,
            pendingURL: pendingURL,
            realtimeEnabled: realtimeEnabled,
            experimentalPreviewEnabled: experimentalPreviewEnabled,
            inputDeviceID: nil,
            inputDeviceName: sourceName,
            inputSourceDescription: sourceName,
            monitorsInputRoute: false
        )
        startedAt = Date()
    }

    func appendExternalPCM16(_ samples: [Int16], taskID: UUID) {
        guard !samples.isEmpty,
              isRecording,
              currentTaskID == taskID,
              state.shouldAcceptAudio() else { return }
        do {
            let buffer = try RemotePCMBufferFactory.make(
                samples: samples,
                sampleRate: Int(canonicalConverterInputSampleRate)
            )
            let group = processingGroup
            group.enter()
            processingQueue.async { [weak self] in
                defer { group.leave() }
                self?.processCapturedBuffer(buffer, taskID: taskID)
            }
        } catch {
            state.record(error: error)
        }
    }

    private var canonicalConverterInputSampleRate: Double {
        externalInputSampleRate ?? CanonicalAudioConverter.format.sampleRate
    }

    private var externalInputSampleRate: Double?

    private func prepareRecordingSession(
        taskID: UUID,
        inputFormat: AVAudioFormat,
        pendingURL: URL,
        realtimeEnabled: Bool,
        experimentalPreviewEnabled: Bool,
        inputDeviceID: AudioDeviceID?,
        inputDeviceName: String,
        inputSourceDescription: String,
        monitorsInputRoute: Bool
    ) throws {
        let converter = try CanonicalAudioConverter(inputFormat: inputFormat)
        let canonicalFormat = CanonicalAudioConverter.format
        currentFile = try AVAudioFile(forWriting: pendingURL, settings: canonicalFormat.settings)
        canonicalConverter = converter
        currentInputDeviceID = inputDeviceID
        currentInputDeviceName = inputDeviceName
        currentTaskID = taskID
        currentPendingURL = pendingURL
        realtimeBuffers = []
        experimentalContextBuffers = []
        pendingExperimentalBoundary = nil
        self.experimentalPreviewEnabled = experimentalPreviewEnabled
        realtimeChunkStartFrame = 0
        realtimeChunkIndex = 0
        finalChunkCommitMachine = ChunkCommitStateMachine(chunkIndex: 0, startFrame: 0)
        pendingRealtimeChunk = nil
        realtimeVoiceActive = true
        realtimeVoiceObserved = false
        self.realtimeEnabled = realtimeEnabled
        snapshotRequestedWhileBusy = false
        inputFormatDescription = "\(Int(inputFormat.sampleRate)) Hz / \(inputFormat.channelCount) ch → 16000 Hz / 1 ch"
        self.inputSourceDescription = inputSourceDescription
        externalInputSampleRate = monitorsInputRoute ? nil : inputFormat.sampleRate
        latestEmptyRecordingReason = nil
        inputRouteSnapshot = monitorsInputRoute
            ? InputRouteSnapshot(
                manualDeviceID: inputDeviceID,
                defaultDeviceID: AudioInputDeviceProvider.currentDefaultInputDeviceID(),
                startedAt: Date()
            )
            : nil
        nextRealtimeFrame = AVAudioFramePosition(canonicalFormat.sampleRate * RealtimeTiming.firstSnapshotSeconds)
        vadWindowSamples = []
        vadWindowCapacity = max(1, Int(canonicalFormat.sampleRate * VoiceProbe.windowSeconds))
        nextVoiceProbeFrame = AVAudioFramePosition(canonicalFormat.sampleRate * VoiceProbe.firstSeconds)
        recentPeakHold = 0
        nextLevelFrame = AVAudioFramePosition(canonicalFormat.sampleRate * LevelReadout.intervalSeconds)
        state.begin()
        isRecording = true
        captureLifecycle = .recording
    }

    private func processCapturedBuffer(_ input: AVAudioPCMBuffer, taskID: UUID) {
        do {
            guard let converter = canonicalConverter else { return }
            let canonical = try converter.convert(input)
            try processCanonicalBuffer(canonical, taskID: taskID)
        } catch {
            state.record(error: error)
        }
    }

    private func processCanonicalBuffer(_ canonical: AVAudioPCMBuffer, taskID: UUID) throws {
        guard let file = currentFile else { return }
        let format = CanonicalAudioConverter.format
        try file.write(from: canonical)
        state.addFrames(AVAudioFramePosition(canonical.frameLength))
        let bufferPeak = peakLevel(from: canonical)
        state.observePeak(bufferPeak)
        recentPeakHold = max(bufferPeak, recentPeakHold * LevelReadout.holdDecay)
        let (frameCount, _, _) = state.snapshot()
        if audioFrameFanOut.subscriberCount > 0,
           let frame = makeAudioFrame(
               from: canonical,
               startFrame: Int64(frameCount) - Int64(canonical.frameLength)
           ) {
            audioFrameFanOut.offer(frame)
        }
        if realtimeEnabled {
            realtimeBuffers.append(canonical)
            if experimentalPreviewEnabled {
                experimentalContextBuffers.append(canonical)
                trimExperimentalContext(sampleRate: format.sampleRate)
            }
            if frameCount >= nextRealtimeFrame {
                nextRealtimeFrame = frameCount + AVAudioFramePosition(format.sampleRate * RealtimeTiming.snapshotIntervalSeconds)
                let chunkDuration = Double(frameCount - realtimeChunkStartFrame) / format.sampleRate
                let hardReached = realtimeChunkBoundaryPolicy.hasReachedHardBoundary(chunkDuration)
                let isChunkFinal = realtimeChunkBoundaryPolicy.shouldFinalize(
                    chunkIndex: realtimeChunkIndex,
                    chunkDuration: chunkDuration,
                    voiceActive: realtimeVoiceActive,
                    hasObservedVoice: realtimeVoiceObserved
                )
                let chunkIndex = realtimeChunkIndex
                let chunkBuffers = realtimeBuffers
                if isChunkFinal, pendingRealtimeChunk == nil {
                    if experimentalPreviewEnabled {
                        pendingExperimentalBoundary = (
                            PreviewBoundary(
                                sessionID: taskID,
                                chunkID: chunkIndex,
                                time: Double(frameCount) / format.sampleRate,
                                kind: hardReached ? .hardLimit : .voicePause
                            ),
                            frameCount
                        )
                    }
                    prepareFinalChunkCommit(
                        taskID: taskID,
                        format: format,
                        buffers: chunkBuffers,
                        endFrame: frameCount
                    )
                } else if !isChunkFinal, pendingRealtimeChunk == nil {
                    emitRealtimeSnapshot(
                        taskID: taskID,
                        format: format,
                        buffers: chunkBuffers,
                        chunkIndex: chunkIndex,
                        isChunkFinal: false
                    )
                }
                emitBoundaryCenteredSnapshotIfReady(taskID: taskID, format: format, frameCount: frameCount)
            }
        }
        appendVoiceWindow(from: canonical)
        if onVoiceProbe != nil, frameCount >= nextVoiceProbeFrame {
            let window = vadWindowSamples
            let rate = Int(format.sampleRate)
            nextVoiceProbeFrame = frameCount + AVAudioFramePosition(format.sampleRate * VoiceProbe.intervalSeconds)
            DispatchQueue.main.async { [weak self] in self?.onVoiceProbe?(taskID, window, rate) }
        }
        if onInputLevelDb != nil, frameCount >= nextLevelFrame {
            nextLevelFrame = frameCount + AVAudioFramePosition(format.sampleRate * LevelReadout.intervalSeconds)
            let db: Float = recentPeakHold > 1e-6 ? 20 * log10(recentPeakHold) : -100
            DispatchQueue.main.async { [weak self] in self?.onInputLevelDb?(db) }
        }
        let bands = frequencyBands(from: canonical)
        DispatchQueue.main.async { [weak self] in self?.onBands?(bands) }
    }

    private func installCaptureTap(
        on input: AVAudioInputNode,
        format: AVAudioFormat,
        taskID: UUID
    ) {
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            self.processingGroup.enter()
            guard self.state.shouldAcceptAudio(), let copy = self.copy(buffer: buffer) else {
                self.processingGroup.leave()
                return
            }
            self.processingQueue.async {
                defer { self.processingGroup.leave() }
                self.processCapturedBuffer(copy, taskID: taskID)
            }
        }
        inputTapInstalled = true
    }

    private func bind(input: AVAudioInputNode, to deviceID: AudioDeviceID) throws {
        guard let audioUnit = input.audioUnit else {
            throw NSError(
                domain: "TypeWhale.AudioRecorder",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "无法绑定指定麦克风，请改用系统默认输入设备。"]
            )
        }
        var enableInput: UInt32 = 1
        let enableStatus = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_EnableIO,
            kAudioUnitScope_Input,
            1,
            &enableInput,
            UInt32(MemoryLayout<UInt32>.size)
        )
        guard enableStatus == noErr else {
            throw audioInputBindingError(
                code: enableStatus,
                message: "无法启用选中麦克风的输入通道"
            )
        }
        var selectedDeviceID = deviceID
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &selectedDeviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        guard status == noErr else {
            throw NSError(
                domain: "TypeWhale.AudioRecorder",
                code: Int(status),
                userInfo: [NSLocalizedDescriptionKey: "无法使用选中的麦克风（CoreAudio \(status)），请尝试切回系统默认或选择通话正在使用的设备。"]
            )
        }
        try verifyBoundInputDevice(audioUnit, expected: deviceID)

        var hardwareFormat = AudioStreamBasicDescription()
        var formatSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let readFormatStatus = AudioUnitGetProperty(
            audioUnit,
            kAudioUnitProperty_StreamFormat,
            kAudioUnitScope_Input,
            1,
            &hardwareFormat,
            &formatSize
        )
        guard readFormatStatus == noErr,
              hardwareFormat.mSampleRate > 0,
              hardwareFormat.mChannelsPerFrame > 0 else {
            throw audioInputBindingError(
                code: readFormatStatus,
                message: "无法读取选中麦克风的真实硬件格式"
            )
        }
        var clientFormat = hardwareFormat
        let setFormatStatus = AudioUnitSetProperty(
            audioUnit,
            kAudioUnitProperty_StreamFormat,
            kAudioUnitScope_Output,
            1,
            &clientFormat,
            UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        )
        guard setFormatStatus == noErr else {
            throw audioInputBindingError(
                code: setFormatStatus,
                message: "无法同步选中麦克风的采集格式"
            )
        }
        LaunchDiagnostics.mark(
            "audio_input_device_bound device_id=\(deviceID) sample_rate=\(Int(hardwareFormat.mSampleRate)) channels=\(hardwareFormat.mChannelsPerFrame)"
        )
    }

    private func verifyBoundInputDevice(_ audioUnit: AudioUnit, expected deviceID: AudioDeviceID) throws {
        var actualDeviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioUnitGetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &actualDeviceID,
            &size
        )
        guard status == noErr, actualDeviceID == deviceID else {
            throw audioInputBindingError(
                code: status == noErr ? -1 : status,
                message: "系统没有真正切换到选中的麦克风"
            )
        }
    }

    private func audioInputBindingError(code: OSStatus, message: String) -> NSError {
        NSError(
            domain: "TypeWhale.AudioRecorder",
            code: Int(code),
            userInfo: [NSLocalizedDescriptionKey: "\(message)（CoreAudio \(code)）。"]
        )
    }

    func switchInput(
        to deviceID: AudioDeviceID?,
        deviceName: String,
        intent: AudioInputSwitchIntent,
        completion: @escaping (AudioInputSwitchResult) -> Void
    ) {
        let localIntent = switchGeneration.issue(targetUID: intent.targetUID)
        routeControlQueue.async { [weak self] in
            guard let self else { return }
            guard self.isRecording, self.captureLifecycle == .recording,
                  let taskID = self.currentTaskID else {
                DispatchQueue.main.async { completion(.superseded) }
                return
            }
            guard self.switchGeneration.accepts(localIntent) else {
                DispatchQueue.main.async { completion(.superseded) }
                return
            }

            let previousDeviceID = self.currentInputDeviceID
            let previousDeviceName = self.currentInputDeviceName
            self.captureLifecycle = .switching
            self.state.stopAccepting()
            self.processingGroup.wait()

            do {
                try self.configureInputEngine(deviceID: deviceID, taskID: taskID)
                guard self.switchGeneration.accepts(localIntent) else {
                    self.captureLifecycle = .recording
                    self.state.resumeAccepting()
                    DispatchQueue.main.async { completion(.superseded) }
                    return
                }
                self.currentInputDeviceID = deviceID
                self.currentInputDeviceName = deviceName
                self.captureLifecycle = .recording
                self.state.resumeAccepting()
                let result: AudioInputSwitchResult = deviceID == nil
                    ? .followedSystem(deviceName: deviceName, error: nil)
                    : .switched(deviceName: deviceName)
                DispatchQueue.main.async { completion(result) }
            } catch {
                let targetError = error.localizedDescription
                do {
                    try self.configureInputEngine(deviceID: previousDeviceID, taskID: taskID)
                    self.currentInputDeviceID = previousDeviceID
                    self.currentInputDeviceName = previousDeviceName
                    self.captureLifecycle = .recording
                    self.state.resumeAccepting()
                    DispatchQueue.main.async {
                        completion(.restoredPrevious(deviceName: previousDeviceName, error: targetError))
                    }
                } catch {
                    self.captureLifecycle = .stopping
                    self.state.stopAccepting()
                    DispatchQueue.main.async {
                        completion(.unavailable(error: "\(targetError)；恢复原麦克风也失败：\(error.localizedDescription)"))
                    }
                }
            }
        }
    }

    private func configureInputEngine(
        deviceID: AudioDeviceID?,
        taskID: UUID
    ) throws {
        stopInputRouteMonitoring()
        manualCapture?.stop()
        manualCapture = nil
        if let oldEngine = engine {
            let oldInput = oldEngine.inputNode
            if inputTapInstalled {
                oldInput.removeTap(onBus: 0)
                inputTapInstalled = false
            }
            oldEngine.stop()
            oldEngine.reset()
        }

        if let deviceID {
            let capture = try ManualAudioInputCapture(deviceID: deviceID)
            let hardwareFormat = capture.format
            canonicalConverter = try CanonicalAudioConverter(inputFormat: hardwareFormat)
            capture.onBuffer = { [weak self] buffer in
                guard let self else { return }
                self.processingGroup.enter()
                guard self.state.shouldAcceptAudio(), let copy = self.copy(buffer: buffer) else { self.processingGroup.leave(); return }
                self.processingQueue.async { defer { self.processingGroup.leave() }; self.processCapturedBuffer(copy, taskID: taskID) }
            }
            engine = nil
            manualCapture = capture
            inputTapInstalled = false
            inputFormatDescription = "\(Int(hardwareFormat.sampleRate)) Hz / \(hardwareFormat.channelCount) ch → 16000 Hz / 1 ch"
            inputRouteSnapshot = InputRouteSnapshot(manualDeviceID: deviceID, defaultDeviceID: AudioInputDeviceProvider.currentDefaultInputDeviceID(), startedAt: Date())
            try capture.start()
            startInputRouteMonitoring()
            return
        }

        let newEngine = AVAudioEngine()
        let input = newEngine.inputNode
        let hardwareFormat = input.outputFormat(forBus: 0)
        guard hardwareFormat.sampleRate > 0, hardwareFormat.channelCount > 0 else {
            throw NSError(
                domain: "TypeWhale.AudioRecorder",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: "切换后的麦克风没有可用输入格式。"]
            )
        }
        let converter = try CanonicalAudioConverter(inputFormat: hardwareFormat)
        installCaptureTap(on: input, format: hardwareFormat, taskID: taskID)
        canonicalConverter = converter
        engine = newEngine
        inputFormatDescription = "\(Int(hardwareFormat.sampleRate)) Hz / \(hardwareFormat.channelCount) ch → 16000 Hz / 1 ch"
        inputRouteSnapshot = InputRouteSnapshot(
            manualDeviceID: deviceID,
            defaultDeviceID: AudioInputDeviceProvider.currentDefaultInputDeviceID(),
            startedAt: Date()
        )
        newEngine.prepare()
        try newEngine.start()
        startInputRouteMonitoring()
    }

    func stop() throws -> (URL, TimeInterval)? {
        guard isRecording, let taskID = currentTaskID, let pendingURL = currentPendingURL else { return nil }
        captureLifecycle = .stopping
        state.stopAccepting()
        isRecording = false
        routeControlQueue.sync {}
        releaseInputNode(reason: "stop")
        scheduleIdleInputRelease(reason: "stop_delayed")
        let waitStart = Date()
        processingGroup.wait()
        // AVAudioFile finalizes the WAV header when its writer is released. Reopening the
        // pending URL while currentFile is still retained can expose a zero-length source,
        // leaving the final recording as tail padding only.
        currentFile = nil
        audioFrameFanOut.finish()
        snapshotQueue.sync {}
        defer { clearRecordingSessionState() }
        let waitMs = Int(Date().timeIntervalSince(waitStart) * 1000)
        if waitMs >= 80 {
            LaunchDiagnostics.mark("recorder_stop_wait_ms=\(waitMs)")
        }
        let (frameCount, writeError, peakLevel) = state.snapshot()
        LaunchDiagnostics.mark("recorder_stop_audio frames=\(frameCount) peak=\(String(format: "%.6f", peakLevel))")
        if let writeError {
            try? FileManager.default.removeItem(at: pendingURL)
            throw writeError
        }
        let recoveryHint = inputSourceDescription == "麦克风"
            ? "如果正在语音通话，请检查系统输入设备是否被通话软件切走或占用。"
            : "请确认遥控器仍已连接，并重新按住语音键讲话。"
        guard frameCount >= 800 else {
            latestEmptyRecordingReason = "没有收到\(inputSourceDescription)输入（\(inputFormatDescription)）。\(recoveryHint)"
            try? FileManager.default.removeItem(at: pendingURL)
            return nil
        }
        let duration = Date().timeIntervalSince(startedAt)
        latestEmptyRecordingReason = peakLevel < 0.002
            ? "\(inputSourceDescription)输入接近静音（\(inputFormatDescription)）。\(recoveryHint)"
            : nil
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let taskURL = latestURL.deletingLastPathComponent().appendingPathComponent(
            "recording_\(formatter.string(from: Date()))_\(taskID.uuidString.prefix(8)).wav"
        )
        try writeFinalRecording(from: pendingURL, to: taskURL)
        processingQueue.sync {
            recoverPendingFinalChunkFromFullRecording()
        }
        try? FileManager.default.removeItem(at: pendingURL)
        try? FileManager.default.removeItem(at: latestURL)
        try FileManager.default.copyItem(at: taskURL, to: latestURL)
        return (taskURL, duration)
    }

    func cancel() {
        guard isRecording else {
            releaseInputNode(reason: "cancel_idle")
            scheduleIdleInputRelease(reason: "cancel_idle_delayed")
            return
        }
        state.stopAccepting()
        isRecording = false
        captureLifecycle = .stopping
        routeControlQueue.sync {}
        releaseInputNode(reason: "cancel")
        scheduleIdleInputRelease(reason: "cancel_delayed")
        processingGroup.wait()
        audioFrameFanOut.finish()
        if let currentPendingURL {
            try? FileManager.default.removeItem(at: currentPendingURL)
        }
        clearRecordingSessionState()
    }

    private func clearRecordingSessionState() {
        currentTaskID = nil
        currentPendingURL = nil
        currentFile = nil
        canonicalConverter = nil
        captureLifecycle = .idle
        realtimeBuffers = []
        experimentalContextBuffers = []
        pendingExperimentalBoundary = nil
        pendingRealtimeChunk = nil
        finalChunkCommitMachine = ChunkCommitStateMachine(chunkIndex: 0, startFrame: 0)
        experimentalPreviewEnabled = false
        realtimeEnabled = false
        snapshotRequestedWhileBusy = false
        inputSourceDescription = "麦克风"
        externalInputSampleRate = nil
    }

    func makeExperimentalTailSnapshot(
        from sourceURL: URL,
        taskID: UUID,
        maxSeconds: TimeInterval = 22.5
    ) throws -> ExperimentalPreviewTailSnapshot {
        let source = try AVAudioFile(forReading: sourceURL)
        let sampleRate = source.processingFormat.sampleRate
        let maxFrames = AVAudioFramePosition(sampleRate * maxSeconds)
        let startFrame = max(0, source.length - maxFrames)
        source.framePosition = startFrame
        let destination = sourceURL.deletingLastPathComponent().appendingPathComponent(
            ".tail-reconcile-\(taskID.uuidString).wav"
        )
        try? FileManager.default.removeItem(at: destination)
        let output = try AVAudioFile(forWriting: destination, settings: source.fileFormat.settings)
        let chunkFrames: AVAudioFrameCount = 4096
        guard let buffer = AVAudioPCMBuffer(pcmFormat: source.processingFormat, frameCapacity: chunkFrames) else {
            throw CocoaError(.fileWriteUnknown)
        }
        while source.framePosition < source.length {
            let remaining = AVAudioFrameCount(min(Int64(chunkFrames), source.length - source.framePosition))
            try source.read(into: buffer, frameCount: remaining)
            if buffer.frameLength == 0 { break }
            try output.write(from: buffer)
        }
        return ExperimentalPreviewTailSnapshot(
            taskID: taskID,
            audioURL: destination,
            audioRange: PreviewAudioRange(
                start: Double(startFrame) / sampleRate,
                end: Double(source.length) / sampleRate
            )
        )
    }

    func releaseIdleInputSession(reason: String) {
        guard !isRecording else { return }
        releaseInputNode(reason: reason)
    }

    private func scheduleIdleInputRelease(reason: String) {
        inputReleaseGeneration += 1
        let generation = inputReleaseGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self, self.inputReleaseGeneration == generation, !self.isRecording else { return }
            self.releaseInputNode(reason: reason)
        }
    }

    private func releaseInputNode(reason: String) {
        stopInputRouteMonitoring()
        if let manualCapture {
            manualCapture.stop()
            self.manualCapture = nil
            LaunchDiagnostics.mark("recorder_manual_input_release reason=\(reason)")
        }
        guard let engine else {
            if reason.contains("delayed") {
                LaunchDiagnostics.mark("recorder_input_release reason=\(reason) had_engine=false")
            }
            return
        }
        let input = engine.inputNode
        if inputTapInstalled {
            input.removeTap(onBus: 0)
            inputTapInstalled = false
        }
        engine.stop()
        engine.reset()
        self.engine = nil
        inputRouteSnapshot = nil
        LaunchDiagnostics.mark("recorder_input_release reason=\(reason) had_engine=true")
        DispatchQueue.main.async { [weak self] in self?.onBands?(Array(repeating: 0.1, count: 7)) }
    }

    private func startInputRouteMonitoring() {
        stopInputRouteMonitoring()
        let routeObserver = AudioInputRouteObserver { [weak self] reason in
            self?.handleInputRouteChanged(reason.userMessage)
        }
        routeObserver.start()
        inputRouteObserver = routeObserver
        if let engine {
            engineConfigurationObserver = NotificationCenter.default.addObserver(
                forName: .AVAudioEngineConfigurationChange,
                object: engine,
                queue: .main
            ) { [weak self] _ in
                self?.handleEngineConfigurationChanged()
            }
        }
    }

    private func stopInputRouteMonitoring() {
        inputRouteObserver?.stop()
        inputRouteObserver = nil
        if let engineConfigurationObserver {
            NotificationCenter.default.removeObserver(engineConfigurationObserver)
        }
        engineConfigurationObserver = nil
    }

    private func handleInputRouteChanged(_ message: String) {
        guard isRecording else { return }
        if shouldIgnoreStartupRouteChange(message: message) {
            return
        }
        let event: AudioInputRouteEvent
        if currentInputDeviceID != nil,
           !AudioInputDeviceProvider.devices().contains(where: { $0.id == currentInputDeviceID }) {
            event = .manualDeviceDisconnected(name: currentInputDeviceName)
        } else {
            event = .systemDefaultChanged
        }
        onInputRouteEvent?(event)
        onInputRouteChanged?(message)
    }

    private func handleEngineConfigurationChanged() {
        guard isRecording else { return }
        if inputRouteSnapshot?.stillTargetsSameInput() == true {
            recoverInputAfterConfigurationChange()
            return
        }
        onInputRouteEvent?(.systemDefaultChanged)
    }

    private func shouldIgnoreStartupRouteChange(message: String) -> Bool {
        guard let inputRouteSnapshot else { return false }
        let elapsed = Date().timeIntervalSince(inputRouteSnapshot.startedAt)
        guard elapsed <= RouteStability.startupGraceSeconds else { return false }
        guard inputRouteSnapshot.stillTargetsSameInput() else { return false }
        LaunchDiagnostics.mark(
            "audio_route_startup_change_ignored elapsed_ms=\(Int(elapsed * 1000)) target=\(inputRouteSnapshot.targetDescription) message=\(message)"
        )
        return true
    }

    private func recoverInputAfterConfigurationChange() {
        routeControlQueue.async { [weak self] in
            guard let self,
                  self.isRecording,
                  self.captureLifecycle == .recording,
                  let engine = self.engine,
                  !engine.isRunning,
                  let taskID = self.currentTaskID else { return }

            self.captureLifecycle = .switching
            self.state.stopAccepting()
            self.processingGroup.wait()

            do {
                // AVAudioEngineConfigurationChange 会使旧 inputNode 的格式状态失效。
                // 在该节点上重新 installTap 会由 AVFAudio 抛出 Objective-C 异常并直接终止进程，
                // 因此沿用热切换的安全路径，完整创建并绑定一套新引擎。
                try self.configureInputEngine(deviceID: self.currentInputDeviceID, taskID: taskID)
                self.captureLifecycle = .recording
                self.state.resumeAccepting()
                LaunchDiagnostics.mark(
                    "audio_route_configuration_recovered target=\(self.inputRouteSnapshot?.targetDescription ?? "unknown")"
                )
            } catch {
                self.captureLifecycle = .stopping
                self.state.stopAccepting()
                let message = "麦克风配置恢复失败：\(error.localizedDescription)"
                LaunchDiagnostics.mark("audio_route_configuration_recovery_failed error=\(error.localizedDescription)")
                DispatchQueue.main.async { [weak self] in
                    self?.onInputRecoveryFailed?(message)
                }
            }
        }
    }

    /// 把「当前块」的音频缓冲转成内存 PCM 并回调；产品实时预览不再为每拍生成 .realtime wav。
    private func emitRealtimeSnapshot(
        taskID: UUID, format: AVAudioFormat, buffers: [AVAudioPCMBuffer],
        chunkIndex: Int, isChunkFinal: Bool
    ) {
        let audioDuration = Double(buffers.reduce(AVAudioFramePosition(0)) {
            $0 + AVAudioFramePosition($1.frameLength)
        }) / format.sampleRate
        let samples = monoSamples(from: buffers)
        guard !samples.isEmpty else { return }
        let sampleRate = Int(format.sampleRate)
        let audioStart = Double(realtimeChunkStartFrame) / format.sampleRate
        let audioRange = PreviewAudioRange(start: audioStart, end: audioStart + audioDuration)
        DispatchQueue.main.async { [weak self] in
            self?.onRealtimeSnapshot?(
                taskID, samples, sampleRate, chunkIndex, isChunkFinal, audioDuration, audioRange
            )
        }
    }

    private func monoSamples(from buffers: [AVAudioPCMBuffer]) -> [Float] {
        var result: [Float] = []
        result.reserveCapacity(buffers.reduce(0) { $0 + Int($1.frameLength) })
        for buffer in buffers {
            guard let frame = makeAudioFrame(from: buffer, startFrame: 0) else { continue }
            result.append(contentsOf: frame.samples)
        }
        return result
    }

    private func prepareFinalChunkCommit(
        taskID: UUID,
        format: AVAudioFormat,
        buffers: [AVAudioPCMBuffer],
        endFrame: AVAudioFramePosition
    ) {
        do {
            let ticket = try finalChunkCommitMachine.prepare(
                endFrame: Int64(endFrame),
                frozenBufferCount: buffers.count
            )
            let audioDuration = Double(buffers.reduce(AVAudioFramePosition(0)) {
                $0 + AVAudioFramePosition($1.frameLength)
            }) / format.sampleRate
            pendingRealtimeChunk = PendingRealtimeChunk(
                ticket: ticket,
                taskID: taskID,
                samples: monoSamples(from: buffers),
                sampleRate: Int(format.sampleRate),
                audioDuration: audioDuration
            )
            realtimeBuffers.removeAll(keepingCapacity: true)
            try finalChunkCommitMachine.beginWriting()
            emitFinalChunkSnapshot(ticketID: ticket.id)
        } catch {
            LaunchDiagnostics.mark("final_chunk_prepare_failed error=\(error.localizedDescription)")
        }
    }

    private func emitFinalChunkSnapshot(ticketID: UUID) {
        guard let pending = pendingRealtimeChunk,
              pending.ticket.id == ticketID else { return }
        guard !pending.samples.isEmpty else {
            LaunchDiagnostics.mark("final_chunk_snapshot_empty chunk=\(pending.ticket.chunkIndex)")
            return
        }
        commitPendingFinalChunk(ticketID: ticketID)
        let audioRange = PreviewAudioRange(
            start: Double(pending.ticket.startFrame) / Double(pending.sampleRate),
            end: Double(pending.ticket.endFrame) / Double(pending.sampleRate)
        )
        DispatchQueue.main.async { [weak self] in
            self?.onRealtimeSnapshot?(
                pending.taskID,
                pending.samples,
                pending.sampleRate,
                pending.ticket.chunkIndex,
                true,
                pending.audioDuration,
                audioRange
            )
        }
    }

    private func commitPendingFinalChunk(ticketID: UUID) {
        guard let pending = pendingRealtimeChunk,
              pending.ticket.id == ticketID else { return }
        do {
            try finalChunkCommitMachine.commit()
            realtimeChunkStartFrame = AVAudioFramePosition(pending.ticket.endFrame)
            realtimeChunkIndex = pending.ticket.chunkIndex + 1
            try finalChunkCommitMachine.collectNextChunk()
            pendingRealtimeChunk = nil
        } catch {
            LaunchDiagnostics.mark("final_chunk_commit_failed error=\(error.localizedDescription)")
        }
    }

    private func recoverPendingFinalChunkFromFullRecording() {
        guard let pending = pendingRealtimeChunk else { return }
        do {
            try finalChunkCommitMachine.recoverFromFullRecording()
            LaunchDiagnostics.mark(
                "final_chunk_recovered_from_full_recording chunk=\(pending.ticket.chunkIndex) start=\(pending.ticket.startFrame) end=\(pending.ticket.endFrame)"
            )
            try finalChunkCommitMachine.collectNextChunk()
            realtimeChunkStartFrame = AVAudioFramePosition(pending.ticket.endFrame)
            realtimeChunkIndex = pending.ticket.chunkIndex + 1
            pendingRealtimeChunk = nil
        } catch {
            LaunchDiagnostics.mark("final_chunk_recovery_failed error=\(error.localizedDescription)")
        }
    }

    private func trimExperimentalContext(sampleRate: Double) {
        let maxFrames = AVAudioFramePosition(sampleRate * 22.5)
        var totalFrames = experimentalContextBuffers.reduce(AVAudioFramePosition(0)) {
            $0 + AVAudioFramePosition($1.frameLength)
        }
        while experimentalContextBuffers.count > 1,
              let first = experimentalContextBuffers.first,
              totalFrames - AVAudioFramePosition(first.frameLength) >= maxFrames {
            totalFrames -= AVAudioFramePosition(first.frameLength)
            experimentalContextBuffers.removeFirst()
        }
    }

    private func emitBoundaryCenteredSnapshotIfReady(
        taskID: UUID,
        format: AVAudioFormat,
        frameCount: AVAudioFramePosition
    ) {
        guard let pendingExperimentalBoundary,
              frameCount - pendingExperimentalBoundary.frame >= AVAudioFramePosition(format.sampleRate * 9.5) else { return }
        let maxFrames = AVAudioFramePosition(format.sampleRate * 22.5)
        var selected: [AVAudioPCMBuffer] = []
        var selectedFrames: AVAudioFramePosition = 0
        for buffer in experimentalContextBuffers.reversed() {
            selected.insert(buffer, at: 0)
            selectedFrames += AVAudioFramePosition(buffer.frameLength)
            if selectedFrames >= maxFrames { break }
        }
        guard !selected.isEmpty else { return }
        self.pendingExperimentalBoundary = nil
        let end = Double(frameCount) / format.sampleRate
        let start = max(0, end - Double(selectedFrames) / format.sampleRate)
        let snapshot = ExperimentalPreviewAudioSnapshot(
            taskID: taskID,
            audioURL: latestURL.deletingLastPathComponent().appendingPathComponent(
                ".reconcile-\(taskID.uuidString)-\(pendingExperimentalBoundary.boundary.chunkID).wav"
            ),
            chunkIndex: pendingExperimentalBoundary.boundary.chunkID,
            audioRange: PreviewAudioRange(start: start, end: end),
            boundary: pendingExperimentalBoundary.boundary
        )
        emitBoundaryCenteredSnapshot(snapshot, format: format, buffers: selected)
    }

    private func emitBoundaryCenteredSnapshot(
        _ snapshot: ExperimentalPreviewAudioSnapshot,
        format: AVAudioFormat,
        buffers: [AVAudioPCMBuffer]
    ) {
        snapshotQueue.async { [weak self] in
            guard let self else { return }
            do {
                try? FileManager.default.removeItem(at: snapshot.audioURL)
                try self.writeRealtimeSnapshot(from: buffers, format: format, to: snapshot.audioURL)
                self.completedExperimentalSnapshots.append(snapshot)
                DispatchQueue.main.async { [weak self] in
                    guard let self,
                          let completed = self.claimCompletedExperimentalSnapshot(at: snapshot.audioURL) else { return }
                    self.onExperimentalPreviewSnapshot?(completed)
                }
            } catch {
                try? FileManager.default.removeItem(at: snapshot.audioURL)
                LaunchDiagnostics.mark("experimental_preview_snapshot_write_failed error=\(error.localizedDescription)")
            }
        }
    }

    func drainCompletedExperimentalSnapshots() -> [ExperimentalPreviewAudioSnapshot] {
        snapshotQueue.sync {
            defer { completedExperimentalSnapshots.removeAll(keepingCapacity: true) }
            return completedExperimentalSnapshots
        }
    }

    private func claimCompletedExperimentalSnapshot(at url: URL) -> ExperimentalPreviewAudioSnapshot? {
        snapshotQueue.sync {
            guard let index = completedExperimentalSnapshots.firstIndex(where: { $0.audioURL == url }) else { return nil }
            return completedExperimentalSnapshots.remove(at: index)
        }
    }

    private func writeRealtimeSnapshot(from buffers: [AVAudioPCMBuffer], format: AVAudioFormat, to destinationURL: URL) throws {
        let snapshot = try AVAudioFile(forWriting: destinationURL, settings: format.settings)
        for buffer in buffers {
            try snapshot.write(from: buffer)
        }
    }

    private func writeFinalRecording(from sourceURL: URL, to destinationURL: URL) throws {
        let source = try AVAudioFile(forReading: sourceURL)
        let format = source.processingFormat
        let destination = try AVAudioFile(forWriting: destinationURL, settings: source.fileFormat.settings)
        let chunkFrames: AVAudioFrameCount = 4096
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkFrames) else {
            try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
            return
        }
        while source.framePosition < source.length {
            let remaining = AVAudioFrameCount(min(Int64(chunkFrames), source.length - source.framePosition))
            try source.read(into: buffer, frameCount: remaining)
            guard buffer.frameLength > 0 else { break }
            try destination.write(from: buffer)
        }
        let tailFrames = AVAudioFrameCount(format.sampleRate * Finalization.tailPaddingSeconds)
        if tailFrames > 0, let silence = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: tailFrames) {
            silence.frameLength = tailFrames
            try destination.write(from: silence)
        }
    }

    private func copy(buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength) else { return nil }
        copy.frameLength = buffer.frameLength
        let sourceBuffers = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        let destinationBuffers = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
        for index in sourceBuffers.indices {
            guard let sourceData = sourceBuffers[index].mData, let destinationData = destinationBuffers[index].mData else { continue }
            memcpy(destinationData, sourceData, Int(sourceBuffers[index].mDataByteSize))
        }
        return copy
    }

    private func frequencyBands(from buffer: AVAudioPCMBuffer) -> [Float] {
        guard let samples = buffer.floatChannelData?[0] else { return Array(repeating: 0.08, count: 7) }
        let count = Int(buffer.frameLength)
        let sampleRate = Float(buffer.format.sampleRate)
        var sum: Float = 0
        for index in 0..<count {
            sum += samples[index] * samples[index]
        }
        let rms = count > 0 ? sqrt(sum / Float(count)) : 0
        guard count > 0, sampleRate > 0 else { return Array(repeating: 0.08, count: 7) }
        let bandFrequencies: [[Float]] = [
            [90, 140, 190],
            [230, 310, 390],
            [460, 600, 740],
            [820, 1050, 1280],
            [1400, 1750, 2100],
            [2300, 2900, 3500],
            [3800, 4700, 5600],
        ]
        let usableCount = min(count, 768)
        let twoPi = Float.pi * 2

        return bandFrequencies.map { frequencies in
            var bandMagnitude: Float = 0
            for frequency in frequencies {
                var real: Float = 0
                var imaginary: Float = 0
                for index in 0..<usableCount {
                    let window = 0.5 - 0.5 * cos(twoPi * Float(index) / Float(max(1, usableCount - 1)))
                    let phase = twoPi * frequency * Float(index) / sampleRate
                    let sample = samples[index] * window
                    real += sample * cos(phase)
                    imaginary -= sample * sin(phase)
                }
                bandMagnitude += sqrt(real * real + imaginary * imaginary) / Float(usableCount)
            }
            let spectral = min(1, (bandMagnitude / Float(frequencies.count)) / Self.lowLevelSpectralReference)
            let broadband = min(1, rms / Self.lowLevelSpeechReference)
            return max(Self.lowLevelSpeechFloor, min(1, spectral * 0.68 + broadband * 0.42))
        }
    }

    /// 协调器按 Silero 探测结果推送「当前是否有人声」；录音器据此在停顿处对齐分块边界（不切词）。
    func updateRealtimeVoiceActive(_ active: Bool) {
        processingQueue.async { [weak self] in
            guard let self else { return }
            self.realtimeVoiceActive = active
            if active { self.realtimeVoiceObserved = true }
        }
    }

    /// 把当前缓冲的单声道 PCM（取首声道）追加进滚动窗口，并裁剪到约 windowSeconds 长度。
    /// 全部在 processingQueue（串行）上调用，无需加锁。
    private func appendVoiceWindow(from buffer: AVAudioPCMBuffer) {
        guard let samples = buffer.floatChannelData?[0] else { return }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return }
        vadWindowSamples.append(contentsOf: UnsafeBufferPointer(start: samples, count: count))
        if vadWindowSamples.count > vadWindowCapacity {
            vadWindowSamples.removeFirst(vadWindowSamples.count - vadWindowCapacity)
        }
    }

    private func makeAudioFrame(
        from buffer: AVAudioPCMBuffer,
        startFrame: Int64
    ) -> AudioFrame? {
        guard let channels = buffer.floatChannelData else { return nil }
        let frameCount = Int(buffer.frameLength)
        let channelCount = max(1, Int(buffer.format.channelCount))
        var mono = [Float](repeating: 0, count: frameCount)
        if buffer.format.isInterleaved {
            let interleaved = channels[0]
            for frame in 0..<frameCount {
                var sum: Float = 0
                for channel in 0..<channelCount {
                    sum += interleaved[frame * channelCount + channel]
                }
                mono[frame] = sum / Float(channelCount)
            }
        } else {
            for frame in 0..<frameCount {
                var sum: Float = 0
                for channel in 0..<channelCount {
                    sum += channels[channel][frame]
                }
                mono[frame] = sum / Float(channelCount)
            }
        }
        return AudioFrame(
            samples: mono,
            sampleRate: Int(buffer.format.sampleRate),
            channelCount: 1,
            startFrame: startFrame
        )
    }

    private func peakLevel(from buffer: AVAudioPCMBuffer) -> Float {
        guard let channels = buffer.floatChannelData else { return 0 }
        let channelCount = Int(buffer.format.channelCount)
        let frameCount = Int(buffer.frameLength)
        guard channelCount > 0, frameCount > 0 else { return 0 }
        var peak: Float = 0
        for channel in 0..<channelCount {
            let samples = channels[channel]
            for index in 0..<frameCount {
                peak = max(peak, abs(samples[index]))
            }
        }
        return peak
    }
}
