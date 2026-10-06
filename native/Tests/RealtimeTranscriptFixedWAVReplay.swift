import Foundation

@main
struct RealtimeTranscriptFixedWAVReplay {
    private struct Recognition {
        let text: String
        let tokens: [String]
        let timestamps: [Float]?
    }

    static func main() throws {
        guard CommandLine.arguments.count == 4 else {
            throw failure("usage: RealtimeTranscriptFixedWAVReplay <wav> <model.onnx> <tokens.txt>")
        }
        let wavURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let modelURL = URL(fileURLWithPath: CommandLine.arguments[2])
        let tokensURL = URL(fileURLWithPath: CommandLine.arguments[3])
        let duration = try audioDuration(wavURL)
        let work = FileManager.default.temporaryDirectory.appendingPathComponent(
            "typewhale-fixed-wav-replay-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }

        var errorPointer: UnsafeMutablePointer<CChar>?
        let recognizer = modelURL.path.withCString { model in
            tokensURL.path.withCString { tokens in
                "".withCString { hotwords in
                    TypeSpeakerNativeRecognizerCreate(model, tokens, hotwords, &errorPointer)
                }
            }
        }
        defer {
            if let recognizer { TypeSpeakerNativeRecognizerDestroy(recognizer) }
            if let errorPointer { TypeSpeakerNativeStringFree(errorPointer) }
        }
        if let errorPointer { throw failure(String(cString: errorPointer)) }
        guard let recognizer else { throw failure("SenseVoice recognizer unavailable") }

        let sessionID = UUID()
        var reducer = PreviewTranscriptReducer(sessionID: sessionID, epoch: 1, visibleCharacterLimit: 160)
        let trace = RealtimeTranscriptTrace(
            sessionID: sessionID,
            directoryURL: work.appendingPathComponent("trace", isDirectory: true),
            developerTextSessionID: sessionID
        )

        // Boundaries reconstructed from the fixed recording's Build 800 request timeline.
        let boundaries: [TimeInterval] = [18, 34, 50, 60, 70, 86, 104]
        var chunkStart: TimeInterval = 0
        for (chunkID, boundaryTime) in boundaries.enumerated() {
            let fastRange = PreviewAudioRange(start: chunkStart, end: boundaryTime)
            try apply(
                recognition: transcribe(recognizer, wavURL: wavURL, range: fastRange, work: work),
                lane: .fast,
                chunkID: chunkID,
                range: fastRange,
                boundary: nil,
                sessionID: sessionID,
                reducer: &reducer,
                trace: trace
            )

            let correctionEnd = min(duration, boundaryTime + 9.5)
            let correctionRange = PreviewAudioRange(
                start: max(0, correctionEnd - 22.5),
                end: correctionEnd
            )
            try apply(
                recognition: transcribe(recognizer, wavURL: wavURL, range: correctionRange, work: work),
                lane: .correction,
                chunkID: chunkID,
                range: correctionRange,
                boundary: PreviewBoundary(
                    sessionID: sessionID,
                    chunkID: chunkID,
                    time: boundaryTime,
                    kind: .hardLimit
                ),
                sessionID: sessionID,
                reducer: &reducer,
                trace: trace
            )
            chunkStart = boundaryTime
        }

        let finalFastRange = PreviewAudioRange(start: chunkStart, end: duration)
        try apply(
            recognition: transcribe(recognizer, wavURL: wavURL, range: finalFastRange, work: work),
            lane: .fast,
            chunkID: boundaries.count,
            range: finalFastRange,
            boundary: nil,
            sessionID: sessionID,
            reducer: &reducer,
            trace: trace
        )
        let stopRange = PreviewAudioRange(start: max(0, duration - 22.5), end: duration)
        try apply(
            recognition: transcribe(recognizer, wavURL: wavURL, range: stopRange, work: work),
            lane: .stopTail,
            chunkID: .max,
            range: stopRange,
            boundary: nil,
            sessionID: sessionID,
            reducer: &reducer,
            trace: trace
        )

        let assembled = reducer.state.confirmedText + reducer.state.mutableTailText
        let full = try transcribe(recognizer, wavURL: wavURL, range: nil, work: work).text
        trace.recordFinalCache(text: assembled)
        trace.flushForTesting()

        let records = try trace.readRecordsForTesting()
        let promoted = records.filter { $0.promotedFastCharacterCount > 0 }
        precondition(!assembled.isEmpty)
        precondition(records.last?.kind == .finalCache)
        precondition(promoted.allSatisfy { $0.promotedFastRange != nil && $0.promotedFastTextHash != nil })
        print(
            "RealtimeTranscriptFixedWAVReplay duration_ms=\(Int(duration * 1_000)) full_chars=\(full.count) assembled_chars=\(assembled.count) confirmed_chars=\(reducer.state.confirmedText.count) volatile_chars=\(reducer.state.mutableTailText.count) promoted_events=\(promoted.count) trace=\(work.appendingPathComponent("trace/\(sessionID.uuidString).jsonl").path)"
        )
        for record in records where record.kind == .merge {
            print(
                "TRACE sequence=\(record.sequence) lane=\(record.lane?.rawValue ?? "none") chunk=\(record.chunkID ?? -1) input=\(range(record.audioRange)) decision=\(record.decision?.rawValue ?? "none") confirmed=\(range(record.confirmedRange)) promoted=\(range(record.promotedFastRange)) promoted_chars=\(record.promotedFastCharacterCount) removed=\(record.removedFastChunkIDs)"
            )
        }
        print("FULL=\(full)")
        print("ASSEMBLED=\(assembled)")
    }

    private static func apply(
        recognition: Recognition,
        lane: PreviewSourceLane,
        chunkID: Int,
        range: PreviewAudioRange,
        boundary: PreviewBoundary?,
        sessionID: UUID,
        reducer: inout PreviewTranscriptReducer,
        trace: RealtimeTranscriptTrace
    ) throws {
        let result = PreviewRecognitionResult(
            sessionID: sessionID,
            epoch: 1,
            requestID: UUID(),
            chunkID: chunkID,
            sourceLane: lane,
            audioRange: range,
            text: recognition.text,
            tokens: recognition.tokens,
            tokenTimestamps: recognition.timestamps,
            boundary: boundary
        )
        _ = reducer.apply(lane == .fast ? .fast(result) : .correction(result))
        guard let transition = reducer.lastOwnershipTransition else {
            throw failure("missing ownership transition for \(lane.rawValue) chunk \(chunkID)")
        }
        trace.recordMerge(
            result: result,
            transition: transition,
            confirmedCharacterCount: reducer.state.confirmedCharacterCount,
            volatileCharacterCount: reducer.state.mutableTailText.count
        )
    }

    private static func transcribe(
        _ recognizer: TypeSpeakerNativeRecognizer,
        wavURL: URL,
        range: PreviewAudioRange?,
        work: URL
    ) throws -> Recognition {
        let inputURL: URL
        if let range {
            inputURL = work.appendingPathComponent("\(Int(range.start * 1_000))-\(Int(range.end * 1_000)).wav")
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")
            process.arguments = [
                "-hide_banner", "-loglevel", "error", "-y",
                "-ss", String(format: "%.3f", range.start),
                "-t", String(format: "%.3f", range.duration),
                "-i", wavURL.path,
                "-ac", "1", "-ar", "16000", "-c:a", "pcm_f32le",
                inputURL.path,
            ]
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { throw failure("ffmpeg clip failed") }
        } else {
            inputURL = wavURL
        }

        var errorPointer: UnsafeMutablePointer<CChar>?
        let pointer = inputURL.path.withCString { audio in
            "auto".withCString { language in
                TypeSpeakerNativeRecognizerTranscribeDetailed(recognizer, audio, language, &errorPointer)
            }
        }
        defer {
            if let pointer { TypeSpeakerNativeRecognitionResultFree(pointer) }
            if let errorPointer { TypeSpeakerNativeStringFree(errorPointer) }
        }
        if let errorPointer { throw failure(String(cString: errorPointer)) }
        guard let pointer else { throw failure("SenseVoice returned no result") }
        let native = pointer.pointee
        let count = max(0, Int(native.count))
        let tokens = (0..<count).map { index in
            native.tokens?[index].map { String(cString: $0) } ?? ""
        }
        let timestamps = native.timestamps.map { values in
            (0..<count).map { values[$0] }
        }
        return Recognition(
            text: clean(native.text.map { String(cString: $0) } ?? ""),
            tokens: tokens,
            timestamps: timestamps
        )
    }

    private static func clean(_ text: String) -> String {
        text.replacingOccurrences(
            of: #"<\|[^|>]+\|>"#,
            with: "",
            options: .regularExpression
        ).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func audioDuration(_ url: URL) throws -> TimeInterval {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/ffprobe")
        process.arguments = [
            "-v", "error", "-show_entries", "format=duration",
            "-of", "default=noprint_wrappers=1:nokey=1", url.path,
        ]
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0,
              let value = Double(String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw failure("ffprobe duration failed")
        }
        return value
    }

    private static func failure(_ message: String) -> NSError {
        NSError(
            domain: "com.waykingah.typewhale.fixed-wav-replay",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }

    private static func range(_ range: PreviewAudioRange?) -> String {
        guard let range else { return "none" }
        return String(format: "%.3f-%.3f", range.start, range.end)
    }
}
