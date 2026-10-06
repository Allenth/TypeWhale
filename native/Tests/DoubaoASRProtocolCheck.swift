import Foundation

@main
struct DoubaoASRProtocolCheck {
    static func main() throws {
        let configuration = DoubaoASRRequestConfiguration(
            requestID: "fixture-request",
            userID: "fixture-user"
        )
        let encoder = DoubaoASRProtocolEncoder(configuration: configuration)

        precondition(encoder.pcm16LE([Float(-1), -0.5, 0, 0.5, 1]) == Data([
            0x00, 0x80, 0x00, 0xC0, 0x00, 0x00, 0x00, 0x40, 0xFF, 0x7F,
        ]))

        let initial = try encoder.initialConfigurationFrame()
        precondition(Array(initial.prefix(4)) == [0x11, 0x10, 0x10, 0x00])
        let initialJSON = try payloadJSON(initial)
        let audio = initialJSON["audio"] as? [String: Any]
        let request = initialJSON["request"] as? [String: Any]
        precondition(audio?["format"] as? String == "pcm")
        precondition(audio?["codec"] as? String == "raw")
        precondition(audio?["rate"] as? Int == 16_000)
        precondition(audio?["bits"] as? Int == 16)
        precondition(audio?["channel"] as? Int == 1)
        precondition(request?["sequence"] as? Int == 1)
        precondition(request?["show_utterances"] as? Bool == true)

        let ordinaryAudio = encoder.audioFrame(pcm16LE: Data([0x01, 0x02]), isFinal: false)
        let finalAudio = encoder.audioFrame(pcm16LE: Data(), isFinal: true)
        precondition(Array(ordinaryAudio.prefix(4)) == [0x11, 0x20, 0x00, 0x00])
        precondition(Array(finalAudio.prefix(4)) == [0x11, 0x22, 0x00, 0x00])
        precondition(readUInt32(ordinaryAudio, at: 4) == 2)
        precondition(Data(ordinaryAudio.dropFirst(8)) == Data([0x01, 0x02]))
        precondition(readUInt32(finalAudio, at: 4) == 0)

        let responsePayload = Data(#"{"reqid":"fixture-request","result":{"text":"今天讨论在线模型","utterances":[{"text":"今天讨论在线模型","start_time":0,"end_time":920,"definite":true}]}}"#.utf8)
        let response = serverFrame(flags: 1, sequence: 7, payload: responsePayload)
        let decoded = try DoubaoASRProtocolDecoder().decode(response)
        guard case .result(let result) = decoded else { preconditionFailure("expected result") }
        precondition(result.providerSequence == 7)
        precondition(result.text == "今天讨论在线模型")
        precondition(result.utterances.count == 1)
        precondition(result.utterances[0].isDefinite)
        precondition(result.utterances[0].startMilliseconds == 0)
        precondition(result.utterances[0].endMilliseconds == 920)

        let finalResponse = serverFrame(flags: 3, sequence: -8, payload: responsePayload)
        guard case .result(let finalResult) = try DoubaoASRProtocolDecoder().decode(finalResponse) else {
            preconditionFailure("expected final result")
        }
        precondition(finalResult.isFinalFrame)
        precondition(finalResult.providerSequence == 8)

        let errorPayload = Data(#"{"message":"fixture failure"}"#.utf8)
        let error = serverErrorFrame(code: 45000000, payload: errorPayload)
        guard case .error(let decodedError) = try DoubaoASRProtocolDecoder().decode(error) else {
            preconditionFailure("expected error")
        }
        precondition(decodedError.code == 45_000_000)
        precondition(decodedError.message == "fixture failure")

        for length in 0..<response.count {
            do {
                _ = try DoubaoASRProtocolDecoder().decode(response.prefix(length))
                preconditionFailure("prefix \(length) unexpectedly decoded")
            } catch let error as DoubaoASRProtocolError {
                switch error {
                case .truncatedFrame, .invalidPayload:
                    break
                default:
                    preconditionFailure("unexpected typed error for prefix \(length): \(error)")
                }
            }
        }

        print("DoubaoASRProtocolCheck passed")
    }

    private static func payloadJSON(_ frame: Data) throws -> [String: Any] {
        let size = Int(readUInt32(frame, at: 4))
        let payload = frame.subdata(in: 8..<(8 + size))
        return try JSONSerialization.jsonObject(with: payload) as! [String: Any]
    }

    private static func serverFrame(flags: UInt8, sequence: Int32, payload: Data) -> Data {
        var data = Data([0x11, 0x90 | flags, 0x10, 0x00])
        appendInt32(sequence, to: &data)
        appendUInt32(UInt32(payload.count), to: &data)
        data.append(payload)
        return data
    }

    private static func serverErrorFrame(code: UInt32, payload: Data) -> Data {
        var data = Data([0x11, 0xF0, 0x10, 0x00])
        appendUInt32(code, to: &data)
        appendUInt32(UInt32(payload.count), to: &data)
        data.append(payload)
        return data
    }

    private static func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
        data[offset..<(offset + 4)].reduce(0) { ($0 << 8) | UInt32($1) }
    }

    private static func appendUInt32(_ value: UInt32, to data: inout Data) {
        data.append(contentsOf: [
            UInt8((value >> 24) & 0xFF), UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF),
        ])
    }

    private static func appendInt32(_ value: Int32, to data: inout Data) {
        appendUInt32(UInt32(bitPattern: value), to: &data)
    }
}
