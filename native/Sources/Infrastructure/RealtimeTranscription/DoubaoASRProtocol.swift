import Foundation

struct DoubaoASRRequestConfiguration: Sendable, Equatable {
    let requestID: String
    let userID: String
    let sampleRate: Int
    let channelCount: Int
    let bitDepth: Int
    let modelName: String
    let showUtterances: Bool

    init(
        requestID: String,
        userID: String,
        sampleRate: Int = 16_000,
        channelCount: Int = 1,
        bitDepth: Int = 16,
        modelName: String = "bigmodel",
        showUtterances: Bool = true
    ) {
        self.requestID = requestID
        self.userID = userID
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.bitDepth = bitDepth
        self.modelName = modelName
        self.showUtterances = showUtterances
    }
}

enum DoubaoASRProtocolError: Error, Sendable, Equatable {
    case truncatedFrame
    case unsupportedVersion(UInt8)
    case invalidHeaderSize(Int)
    case unsupportedMessageType(UInt8)
    case unsupportedSerialization(UInt8)
    case unsupportedCompression(UInt8)
    case invalidPayload
}

struct DoubaoASRUtterance: Sendable, Equatable {
    let text: String
    let startMilliseconds: Int
    let endMilliseconds: Int
    let isDefinite: Bool
}

struct DoubaoASRResult: Sendable, Equatable {
    let requestID: String?
    let text: String
    let utterances: [DoubaoASRUtterance]
    let providerSequence: Int
    let isFinalFrame: Bool
}

struct DoubaoASRServerError: Sendable, Equatable {
    let code: UInt32
    let message: String
}

enum DoubaoDecodedMessage: Sendable, Equatable {
    case result(DoubaoASRResult)
    case error(DoubaoASRServerError)
}

struct DoubaoASRProtocolEncoder: Sendable {
    private let configuration: DoubaoASRRequestConfiguration

    init(configuration: DoubaoASRRequestConfiguration) {
        self.configuration = configuration
    }

    func pcm16LE(_ samples: [Float]) -> Data {
        var data = Data(capacity: samples.count * 2)
        for sample in samples {
            let clamped = min(1, max(-1, sample))
            let value: Int16
            if clamped <= -1 {
                value = .min
            } else if clamped >= 1 {
                value = .max
            } else {
                value = Int16((clamped * 32_768).rounded())
            }
            let bits = UInt16(bitPattern: value)
            data.append(UInt8(bits & 0xFF))
            data.append(UInt8((bits >> 8) & 0xFF))
        }
        return data
    }

    func initialConfigurationFrame() throws -> Data {
        let body: [String: Any] = [
            "user": ["uid": configuration.userID],
            "audio": [
                "format": "pcm",
                "codec": "raw",
                "rate": configuration.sampleRate,
                "bits": configuration.bitDepth,
                "channel": configuration.channelCount,
            ],
            "request": [
                "reqid": configuration.requestID,
                "sequence": 1,
                "model_name": configuration.modelName,
                "show_utterances": configuration.showUtterances,
            ],
        ]
        guard JSONSerialization.isValidJSONObject(body) else {
            throw DoubaoASRProtocolError.invalidPayload
        }
        let payload = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        return frame(messageType: 0x1, flags: 0x0, serialization: 0x1, payload: payload)
    }

    func audioFrame(pcm16LE: Data, isFinal: Bool) -> Data {
        frame(
            messageType: 0x2,
            flags: isFinal ? 0x2 : 0x0,
            serialization: 0x0,
            payload: pcm16LE
        )
    }

    private func frame(
        messageType: UInt8,
        flags: UInt8,
        serialization: UInt8,
        payload: Data
    ) -> Data {
        var data = Data([
            0x11,
            (messageType << 4) | flags,
            serialization << 4,
            0x00,
        ])
        data.appendBigEndian(UInt32(payload.count))
        data.append(payload)
        return data
    }
}

struct DoubaoASRProtocolDecoder: Sendable {
    func decode<D: DataProtocol>(_ source: D) throws -> DoubaoDecodedMessage where D.Element == UInt8 {
        let data = Data(source)
        guard data.count >= 4 else { throw DoubaoASRProtocolError.truncatedFrame }

        let version = data[0] >> 4
        guard version == 1 else { throw DoubaoASRProtocolError.unsupportedVersion(version) }
        let headerSize = Int(data[0] & 0x0F) * 4
        guard headerSize >= 4 else { throw DoubaoASRProtocolError.invalidHeaderSize(headerSize) }
        guard data.count >= headerSize else { throw DoubaoASRProtocolError.truncatedFrame }

        let messageType = data[1] >> 4
        let flags = data[1] & 0x0F
        let serialization = data[2] >> 4
        let compression = data[2] & 0x0F
        guard compression == 0 else {
            throw DoubaoASRProtocolError.unsupportedCompression(compression)
        }

        var cursor = headerSize
        if messageType == 0xF {
            let code = try readUInt32(data, cursor: &cursor)
            let payload = try readPayload(data, cursor: &cursor)
            let object = try jsonObject(payload, serialization: serialization)
            let message = object["message"] as? String ?? "provider error"
            return .error(DoubaoASRServerError(code: code, message: message))
        }

        guard messageType == 0x9 else {
            throw DoubaoASRProtocolError.unsupportedMessageType(messageType)
        }

        var sequence: Int32?
        if flags == 0x1 || flags == 0x3 {
            sequence = Int32(bitPattern: try readUInt32(data, cursor: &cursor))
        }
        let payload = try readPayload(data, cursor: &cursor)
        let object = try jsonObject(payload, serialization: serialization)
        guard let result = object["result"] as? [String: Any] else {
            throw DoubaoASRProtocolError.invalidPayload
        }

        let utterances = (result["utterances"] as? [[String: Any]] ?? []).compactMap { value -> DoubaoASRUtterance? in
            guard let text = value["text"] as? String else { return nil }
            return DoubaoASRUtterance(
                text: text,
                startMilliseconds: Self.integer(value["start_time"]),
                endMilliseconds: Self.integer(value["end_time"]),
                isDefinite: value["definite"] as? Bool ?? false
            )
        }
        let rawSequence = sequence ?? 0
        let providerSequence = rawSequence == .min ? Int(Int32.max) + 1 : abs(Int(rawSequence))
        return .result(DoubaoASRResult(
            requestID: object["reqid"] as? String,
            text: result["text"] as? String ?? utterances.map(\.text).joined(),
            utterances: utterances,
            providerSequence: providerSequence,
            isFinalFrame: flags == 0x2 || flags == 0x3 || rawSequence < 0
        ))
    }

    private func readUInt32(_ data: Data, cursor: inout Int) throws -> UInt32 {
        guard cursor >= 0, data.count - cursor >= 4 else {
            throw DoubaoASRProtocolError.truncatedFrame
        }
        let end = cursor + 4
        let value = data[cursor..<end].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        cursor = end
        return value
    }

    private func readPayload(_ data: Data, cursor: inout Int) throws -> Data {
        let size = Int(try readUInt32(data, cursor: &cursor))
        guard size >= 0, data.count - cursor >= size else {
            throw DoubaoASRProtocolError.truncatedFrame
        }
        let payload = data.subdata(in: cursor..<(cursor + size))
        cursor += size
        return payload
    }

    private func jsonObject(_ payload: Data, serialization: UInt8) throws -> [String: Any] {
        guard serialization == 0x1 else {
            throw DoubaoASRProtocolError.unsupportedSerialization(serialization)
        }
        do {
            guard let object = try JSONSerialization.jsonObject(with: payload) as? [String: Any] else {
                throw DoubaoASRProtocolError.invalidPayload
            }
            return object
        } catch let error as DoubaoASRProtocolError {
            throw error
        } catch {
            throw DoubaoASRProtocolError.invalidPayload
        }
    }

    private static func integer(_ value: Any?) -> Int {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        return 0
    }
}

private extension Data {
    mutating func appendBigEndian(_ value: UInt32) {
        append(contentsOf: [
            UInt8((value >> 24) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8(value & 0xFF),
        ])
    }
}
