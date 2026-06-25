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
    private var realtimeSequence = 0
    private var realtimeEnabled = false
    private var snapshotWriteInFlight = false
    private var snapshotRequestedWhileBusy = false
    private var inputRouteObserver: AudioInputRouteObserver?
    private var engineConfigurationObserver: NSObjectProtocol?
    private var inputFormatDescription = ""
    private var latestEmptyRecordingReason: String?
    private(set) var isRecording = false
    var onBands: (([Float]) -> Void)?
    var onRealtimeSnapshot: ((UUID, URL) -> Void)?
    var onInputRouteChanged: ((String) -> Void)?

    var emptyRecordingReason: String? {
        latestEmptyRecordingReason
    }

    var latestURL: URL {
        AppPaths.recordings.appendingPathComponent("latest.wav")
    }

    func start(taskID: UUID, realtimeEnabled: Bool, inputDeviceID: AudioDeviceID?) throws {
        guard !isRecording else { return }
        let directory = latestURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let pendingURL = directory.appendingPathComponent(".recording-\(taskID.uuidString).wav")
        try? FileManager.default.removeItem(at: pendingURL)

        let engine = AVAudioEngine()
        self.engine = engine
        let input = engine.inputNode
        if let inputDeviceID {
            try bind(input: input, to: inputDeviceID)
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
        realtimeSequence = 0
        self.realtimeEnabled = realtimeEnabled
        snapshotRequestedWhileBusy = false
        inputFormatDescription = "\(Int(format.sampleRate)) Hz / \(format.channelCount) ch"
        latestEmptyRecordingReason = nil
        nextRealtimeFrame = AVAudioFramePosition(format.sampleRate * RealtimeTiming.firstSnapshotSeconds)
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
                    self.state.observePeak(self.peakLevel(from: copy))
                    if self.realtimeEnabled {
                        self.realtimeBuffers.append(copy)
                        let (frameCount, _, _) = self.state.snapshot()
                        if frameCount >= self.nextRealtimeFrame {
                            self.scheduleRealtimeSnapshot(taskID: taskID, format: format)
                            self.nextRealtimeFrame = frameCount + AVAudioFramePosition(format.sampleRate * RealtimeTiming.snapshotIntervalSeconds)
                        }
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
        processingGroup.wait()
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

    private func scheduleRealtimeSnapshot(taskID: UUID, format: AVAudioFormat) {
        guard !snapshotWriteInFlight else {
            snapshotRequestedWhileBusy = true
            return
        }
        snapshotWriteInFlight = true
        snapshotRequestedWhileBusy = false
        realtimeSequence += 1
        let sequence = realtimeSequence
        let buffers = realtimeBuffers
        let directory = latestURL.deletingLastPathComponent()
        let url = directory.appendingPathComponent(".realtime-\(taskID.uuidString)-\(sequence).wav")
        snapshotQueue.async { [weak self] in
            guard let self else { return }
            do {
                try? FileManager.default.removeItem(at: url)
                let snapshot = try AVAudioFile(forWriting: url, settings: format.settings)
                for buffer in buffers {
                    try snapshot.write(from: buffer)
                }
                DispatchQueue.main.async { [weak self] in
                    self?.onRealtimeSnapshot?(taskID, url)
                }
            } catch {
                try? FileManager.default.removeItem(at: url)
            }
            self.processingQueue.async { [weak self] in
                guard let self else { return }
                self.snapshotWriteInFlight = false
                guard self.realtimeEnabled, self.currentTaskID == taskID else { return }
                if self.snapshotRequestedWhileBusy {
                    self.scheduleRealtimeSnapshot(taskID: taskID, format: format)
                }
            }
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
