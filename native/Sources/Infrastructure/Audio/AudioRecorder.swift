import AVFoundation
import AudioToolbox
import CoreAudio
import Darwin
import Foundation

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

final class AudioRecorder: @unchecked Sendable {
    private enum RealtimeTiming {
        static let firstSnapshotSeconds: Double = 0.30
        static let snapshotIntervalSeconds: Double = 0.50
        /// 实时预览分块：到软目标后，等下一个停顿（Silero 判定当前无人声）再在停顿处冻结提交，
        /// 让块边界落在词/句间隙、不切词；若一直不停顿则到硬上限强制提交兜底。
        /// 既封住长录音的 O(n²) 重识别开销，也让已提交文本稳定不跳变。
        static let chunkSoftSeconds: Double = 10.0
        static let chunkHardSeconds: Double = 18.0
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

    private var engine: AVAudioEngine?
    private let processingQueue = DispatchQueue(label: "com.waykingah.typespeaker.audio-processing", qos: .userInteractive)
    private let snapshotQueue = DispatchQueue(label: "com.waykingah.typespeaker.audio-snapshots", qos: .userInitiated)
    private let processingGroup = DispatchGroup()
    private let state = LockedRecordingState()
    private var startedAt = Date()
    private var currentTaskID: UUID?
    private var currentPendingURL: URL?
    private var realtimeBuffers: [AVAudioPCMBuffer] = []
    private var nextRealtimeFrame: AVAudioFramePosition = 0
    private var realtimeChunkStartFrame: AVAudioFramePosition = 0
    private var realtimeChunkIndex = 0
    /// 由协调器按 Silero 探测结果实时推送：当前是否有人声。用于在停顿处对齐分块边界（不切词）。
    private var realtimeVoiceActive = true
    private var realtimeSequence = 0
    private var realtimeEnabled = false
    private var vadWindowSamples: [Float] = []
    private var vadWindowCapacity = 0
    private var nextVoiceProbeFrame: AVAudioFramePosition = 0
    private var recentPeakHold: Float = 0
    private var nextLevelFrame: AVAudioFramePosition = 0
    private var snapshotWriteInFlight = false
    private var snapshotRequestedWhileBusy = false
    private var inputRouteObserver: AudioInputRouteObserver?
    private var engineConfigurationObserver: NSObjectProtocol?
    private var inputFormatDescription = ""
    private var latestEmptyRecordingReason: String?
    private(set) var isRecording = false
    var onBands: (([Float]) -> Void)?
    /// (taskID, 快照音频URL, 块序号, 是否为该块的最终快照)。块最终快照用于冻结提交、不会被丢弃。
    var onRealtimeSnapshot: ((UUID, URL, Int, Bool) -> Void)?
    var onInputRouteChanged: ((String) -> Void)?
    /// 实时人声门控信号：(最近窗口的单声道 PCM, 采样率)。约每 0.4s 触发一次，在后台队列回调。
    var onVoiceProbe: (([Float], Int) -> Void)?
    /// 实时输入电平（dBFS，≤0）。约每 0.1s 在 main 回调一次，供胶囊显示。
    var onInputLevelDb: ((Float) -> Void)?

    var emptyRecordingReason: String? {
        latestEmptyRecordingReason
    }

    var latestURL: URL {
        AppPaths.recordings.appendingPathComponent("latest.wav")
    }

    func start(taskID: UUID, realtimeEnabled: Bool, inputDeviceID: AudioDeviceID?, voiceProcessingEnabled: Bool = false) throws {
        guard !isRecording else { return }
        let directory = latestURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let pendingURL = directory.appendingPathComponent(".recording-\(taskID.uuidString).wav")
        try? FileManager.default.removeItem(at: pendingURL)

        let engine = AVAudioEngine()
        self.engine = engine
        let input = engine.inputNode
        if let inputDeviceID {
            do {
                try bind(input: input, to: inputDeviceID)
            } catch {
                self.engine = nil
                try? FileManager.default.removeItem(at: pendingURL)
                throw error
            }
        }
        // 麦克风降噪（语音增强）：开启 Apple Voice Processing（回声消除 + 噪声抑制 + AGC）。
        // 失败则降级为不处理（仍可正常录音）。
        if voiceProcessingEnabled {
            do {
                try input.setVoiceProcessingEnabled(true)
            } catch {
                LaunchDiagnostics.mark("voice_processing_enable_failed error=\(error.localizedDescription)")
            }
        }
        let format = input.outputFormat(forBus: 0)
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
        let file = try AVAudioFile(forWriting: pendingURL, settings: format.settings)
        currentTaskID = taskID
        currentPendingURL = pendingURL
        realtimeBuffers = []
        realtimeChunkStartFrame = 0
        realtimeChunkIndex = 0
        realtimeVoiceActive = true
        realtimeSequence = 0
        self.realtimeEnabled = realtimeEnabled
        snapshotRequestedWhileBusy = false
        inputFormatDescription = "\(Int(format.sampleRate)) Hz / \(format.channelCount) ch"
        latestEmptyRecordingReason = nil
        nextRealtimeFrame = AVAudioFramePosition(format.sampleRate * RealtimeTiming.firstSnapshotSeconds)
        vadWindowSamples = []
        vadWindowCapacity = max(1, Int(format.sampleRate * VoiceProbe.windowSeconds))
        nextVoiceProbeFrame = AVAudioFramePosition(format.sampleRate * VoiceProbe.firstSeconds)
        recentPeakHold = 0
        nextLevelFrame = AVAudioFramePosition(format.sampleRate * LevelReadout.intervalSeconds)
        state.begin()
        isRecording = true
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            self.processingGroup.enter()
            guard self.state.shouldAcceptAudio(), let copy = self.copy(buffer: buffer) else {
                self.processingGroup.leave()
                return
            }
            self.processingQueue.async {
                defer { self.processingGroup.leave() }
                do {
                    try file.write(from: copy)
                    self.state.addFrames(AVAudioFramePosition(copy.frameLength))
                    let bufferPeak = self.peakLevel(from: copy)
                    self.state.observePeak(bufferPeak)
                    self.recentPeakHold = max(bufferPeak, self.recentPeakHold * LevelReadout.holdDecay)
                    let (frameCount, _, _) = self.state.snapshot()
                    if self.realtimeEnabled {
                        self.realtimeBuffers.append(copy)
                        if frameCount >= self.nextRealtimeFrame {
                            self.nextRealtimeFrame = frameCount + AVAudioFramePosition(format.sampleRate * RealtimeTiming.snapshotIntervalSeconds)
                            let chunkFrames = Double(frameCount - self.realtimeChunkStartFrame)
                            let softReached = chunkFrames >= format.sampleRate * RealtimeTiming.chunkSoftSeconds
                            let hardReached = chunkFrames >= format.sampleRate * RealtimeTiming.chunkHardSeconds
                            // 到软目标后遇到停顿（Silero 判定当前无人声）即在停顿处提交，避免切词；硬上限兜底。
                            let isChunkFinal = hardReached || (softReached && !self.realtimeVoiceActive)
                            let chunkIndex = self.realtimeChunkIndex
                            let chunkBuffers = self.realtimeBuffers
                            if isChunkFinal {
                                // 冻结当前块：下一块从此帧起算，丢掉已提交的缓冲（也封住长录音内存增长）。
                                self.realtimeChunkStartFrame = frameCount
                                self.realtimeChunkIndex += 1
                                self.realtimeBuffers.removeAll(keepingCapacity: true)
                            }
                            self.emitRealtimeSnapshot(
                                taskID: taskID, format: format, buffers: chunkBuffers,
                                chunkIndex: chunkIndex, isChunkFinal: isChunkFinal
                            )
                        }
                    }
                    self.appendVoiceWindow(from: copy)
                    if self.onVoiceProbe != nil, frameCount >= self.nextVoiceProbeFrame {
                        let window = self.vadWindowSamples
                        let rate = Int(format.sampleRate)
                        self.nextVoiceProbeFrame = frameCount + AVAudioFramePosition(format.sampleRate * VoiceProbe.intervalSeconds)
                        DispatchQueue.main.async { [weak self] in self?.onVoiceProbe?(window, rate) }
                    }
                    if self.onInputLevelDb != nil, frameCount >= self.nextLevelFrame {
                        self.nextLevelFrame = frameCount + AVAudioFramePosition(format.sampleRate * LevelReadout.intervalSeconds)
                        let db: Float = self.recentPeakHold > 1e-6 ? 20 * log10(self.recentPeakHold) : -100
                        DispatchQueue.main.async { [weak self] in self?.onInputLevelDb?(db) }
                    }
                    let bands = self.frequencyBands(from: copy)
                    DispatchQueue.main.async { [weak self] in self?.onBands?(bands) }
                } catch {
                    self.state.record(error: error)
                }
            }
        }
        engine.prepare()
        do {
            try engine.start()
            startedAt = Date()
            startInputRouteMonitoring()
        } catch {
            state.stopAccepting()
            isRecording = false
            currentTaskID = nil
            currentPendingURL = nil
            releaseInputNode()
            try? FileManager.default.removeItem(at: pendingURL)
            throw error
        }
    }

    private func bind(input: AVAudioInputNode, to deviceID: AudioDeviceID) throws {
        guard let audioUnit = input.audioUnit else {
            throw NSError(
                domain: "TypeWhale.AudioRecorder",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "无法绑定指定麦克风，请改用系统默认输入设备。"]
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
    }

    func stop() throws -> (URL, TimeInterval)? {
        guard isRecording, let taskID = currentTaskID, let pendingURL = currentPendingURL else { return nil }
        state.stopAccepting()
        isRecording = false
        releaseInputNode()
        let waitStart = Date()
        processingGroup.wait()
        let waitMs = Int(Date().timeIntervalSince(waitStart) * 1000)
        if waitMs >= 80 {
            LaunchDiagnostics.mark("recorder_stop_wait_ms=\(waitMs)")
        }
        currentTaskID = nil
        currentPendingURL = nil
        realtimeBuffers = []
        realtimeEnabled = false
        snapshotRequestedWhileBusy = false
        let (frameCount, writeError, peakLevel) = state.snapshot()
        if let writeError {
            try? FileManager.default.removeItem(at: pendingURL)
            throw writeError
        }
        guard frameCount >= 800 else {
            latestEmptyRecordingReason = "没有收到麦克风输入（\(inputFormatDescription)）。如果正在语音通话，请检查系统输入设备是否被通话软件切走或占用。"
            try? FileManager.default.removeItem(at: pendingURL)
            return nil
        }
        let duration = Date().timeIntervalSince(startedAt)
        latestEmptyRecordingReason = peakLevel < 0.002
            ? "麦克风输入接近静音（\(inputFormatDescription)）。如果正在语音通话，请检查系统输入设备、耳机麦克风或通话软件的降噪/独占设置。"
            : nil
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let taskURL = latestURL.deletingLastPathComponent().appendingPathComponent(
            "recording_\(formatter.string(from: Date()))_\(taskID.uuidString.prefix(8)).wav"
        )
        try writeFinalRecording(from: pendingURL, to: taskURL)
        try? FileManager.default.removeItem(at: pendingURL)
        try? FileManager.default.removeItem(at: latestURL)
        try FileManager.default.copyItem(at: taskURL, to: latestURL)
        return (taskURL, duration)
    }

    func cancel() {
        guard isRecording else {
            releaseInputNode()
            return
        }
        state.stopAccepting()
        isRecording = false
        releaseInputNode()
        processingGroup.wait()
        if let currentPendingURL {
            try? FileManager.default.removeItem(at: currentPendingURL)
        }
        currentTaskID = nil
        currentPendingURL = nil
        realtimeBuffers = []
        realtimeEnabled = false
        snapshotRequestedWhileBusy = false
    }

    private func releaseInputNode() {
        guard let engine else { return }
        stopInputRouteMonitoring()
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        engine.reset()
        self.engine = nil
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
                self?.handleInputRouteChanged("录音引擎配置已变化。")
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
        latestEmptyRecordingReason = "\(message)请重新开始录音。"
        state.stopAccepting()
        stopInputRouteMonitoring()
        releaseInputNode()
        onInputRouteChanged?(message)
    }

    /// 把「当前块」的音频缓冲写成快照文件并回调。普通中间快照受单写入节流（盘忙就跳过，下一拍再来）；
    /// 块最终快照（isChunkFinal）绕过节流，保证一定被写出，避免丢掉整块的提交文本。
    private func emitRealtimeSnapshot(
        taskID: UUID, format: AVAudioFormat, buffers: [AVAudioPCMBuffer],
        chunkIndex: Int, isChunkFinal: Bool
    ) {
        if !isChunkFinal {
            guard !snapshotWriteInFlight else { return }
            snapshotWriteInFlight = true
        }
        realtimeSequence += 1
        let sequence = realtimeSequence
        let directory = latestURL.deletingLastPathComponent()
        let url = directory.appendingPathComponent(".realtime-\(taskID.uuidString)-\(sequence).wav")
        snapshotQueue.async { [weak self] in
            guard let self else { return }
            do {
                try? FileManager.default.removeItem(at: url)
                try self.writeRealtimeSnapshot(from: buffers, format: format, to: url)
                DispatchQueue.main.async { [weak self] in
                    self?.onRealtimeSnapshot?(taskID, url, chunkIndex, isChunkFinal)
                }
            } catch {
                try? FileManager.default.removeItem(at: url)
            }
            if !isChunkFinal {
                self.processingQueue.async { [weak self] in
                    self?.snapshotWriteInFlight = false
                }
            }
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
            let spectral = min(1, (bandMagnitude / Float(frequencies.count)) / 0.0058)
            let broadband = min(1, rms / 0.026)
            return max(0.12, min(1, spectral * 0.92 + broadband * 0.28))
        }
    }

    /// 协调器按 Silero 探测结果推送「当前是否有人声」；录音器据此在停顿处对齐分块边界（不切词）。
    func updateRealtimeVoiceActive(_ active: Bool) {
        processingQueue.async { [weak self] in
            self?.realtimeVoiceActive = active
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
