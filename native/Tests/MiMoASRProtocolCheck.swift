import Foundation

@main
struct MiMoASRProtocolCheck {
    static func main() throws {
        try requestMatchesOfficialV25Contract()
        try oversizedAudioIsRejectedWithoutCredentialLeak()
        try everySSEFragmentationProducesTheSameEvents()
        try commentsMultilineAndTerminalIdempotencyWork()
        try malformedAndOversizedStreamsFailTyped()
        print("MiMoASRProtocolCheck passed")
    }

    private static func requestMatchesOfficialV25Contract() throws {
        let key = "mimo-sentinel-never-log"
        let wav = minimalWAV()
        let request = try MiMoASRRequestBuilder(apiKey: key).makeRequest(
            wavData: wav,
            language: .auto
        )
        precondition(request.url == URL(string: "https://api.xiaomimimo.com/v1/chat/completions"))
        precondition(request.httpMethod == "POST")
        precondition(request.value(forHTTPHeaderField: "api-key") == key)
        precondition(request.value(forHTTPHeaderField: "Content-Type") == "application/json")

        let json = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        precondition(json["model"] as? String == "mimo-v2.5-asr")
        precondition(json["stream"] as? Bool == true)
        let messages = json["messages"] as! [[String: Any]]
        let content = messages[0]["content"] as! [[String: Any]]
        precondition(content[0]["type"] as? String == "input_audio")
        let inputAudio = content[0]["input_audio"] as! [String: Any]
        let dataURL = inputAudio["data"] as! String
        precondition(dataURL.hasPrefix("data:audio/wav;base64,"))
        precondition(Data(base64Encoded: String(dataURL.dropFirst("data:audio/wav;base64,".count))) == wav)
        let options = json["asr_options"] as! [String: Any]
        precondition(options["language"] as? String == "auto")
    }

    private static func oversizedAudioIsRejectedWithoutCredentialLeak() throws {
        let key = "oversize-sentinel-never-log"
        // 6,750,001 raw bytes expand beyond the stricter 9,000,000-byte Data URL cap.
        let oversized = Data(repeating: 0x41, count: 6_750_001)
        do {
            _ = try MiMoASRRequestBuilder(apiKey: key).makeRequest(wavData: oversized, language: .zh)
            preconditionFailure("oversized Base64 request must fail locally")
        } catch let error as MiMoASRProtocolError {
            precondition(error == .audioTooLarge)
            let description = String(describing: error)
            precondition(!description.contains(key))
            precondition(!description.contains(oversized.base64EncodedString().prefix(32)))
        }
    }

    private static func everySSEFragmentationProducesTheSameEvents() throws {
        let lf = Data((
            "data: {\"choices\":[{\"delta\":{\"content\":\"今天\"}}]}\n\n" +
            "data: {\"choices\":[{\"delta\":{\"content\":\"讨论\"}}]}\n\n" +
            "data: [DONE]\n\n"
        ).utf8)
        let expected: [MiMoASRDelta] = [.text("今天"), .text("讨论"), .completed]

        var whole = MiMoSSEParser()
        let wholeEvents = try whole.append(lf)
        precondition(wholeEvents == expected)

        var bytewise = MiMoSSEParser()
        var bytewiseEvents: [MiMoASRDelta] = []
        for byte in lf { bytewiseEvents += try bytewise.append(Data([byte])) }
        precondition(bytewiseEvents == expected)

        let crlf = Data(String(decoding: lf, as: UTF8.self).replacingOccurrences(of: "\n", with: "\r\n").utf8)
        for split in 0...crlf.count {
            var parser = MiMoSSEParser()
            var events = try parser.append(crlf.prefix(split))
            events += try parser.append(crlf.dropFirst(split))
            precondition(events == expected, "CR/LF split \(split) changed events")
        }
    }

    private static func commentsMultilineAndTerminalIdempotencyWork() throws {
        let stream = Data((
            ": keep-alive\n" +
            "event: message\n" +
            "data: {\"choices\":[{\"delta\":\n" +
            "data: {\"content\":\"多行\"}}]}\n\n" +
            "data: [DONE]\n\n" +
            "data: {\"choices\":[{\"delta\":{\"content\":\"不能出现\"}}]}\n\n"
        ).utf8)
        var parser = MiMoSSEParser()
        let events = try parser.append(stream)
        precondition(events == [.text("多行"), .completed])
        let lateDone = try parser.append(Data("data: [DONE]\n\n".utf8))
        precondition(lateDone.isEmpty)
    }

    private static func malformedAndOversizedStreamsFailTyped() throws {
        var malformed = MiMoSSEParser()
        do {
            _ = try malformed.append(Data("data: {bad-json}\n\n".utf8))
            preconditionFailure("malformed SSE JSON must fail")
        } catch let error as MiMoASRProtocolError {
            precondition(error == .invalidJSON)
        }

        var oversized = MiMoSSEParser(maximumBufferedBytes: 32)
        do {
            _ = try oversized.append(Data(repeating: 0x41, count: 33))
            preconditionFailure("oversized SSE buffer must fail")
        } catch let error as MiMoASRProtocolError {
            precondition(error == .streamBufferOverflow)
        }

        var oversizedCompleteEvent = MiMoSSEParser(maximumBufferedBytes: 32)
        do {
            _ = try oversizedCompleteEvent.append(Data(("data: " + String(repeating: "A", count: 33) + "\n\n").utf8))
            preconditionFailure("oversized complete SSE event must fail before parsing")
        } catch let error as MiMoASRProtocolError {
            precondition(error == .streamBufferOverflow)
        }
    }

    private static func minimalWAV() -> Data {
        Data([
            0x52, 0x49, 0x46, 0x46, 0x24, 0x00, 0x00, 0x00,
            0x57, 0x41, 0x56, 0x45, 0x66, 0x6D, 0x74, 0x20,
            0x10, 0x00, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00,
            0x80, 0x3E, 0x00, 0x00, 0x00, 0x7D, 0x00, 0x00,
            0x02, 0x00, 0x10, 0x00, 0x64, 0x61, 0x74, 0x61,
            0x00, 0x00, 0x00, 0x00,
        ])
    }
}
