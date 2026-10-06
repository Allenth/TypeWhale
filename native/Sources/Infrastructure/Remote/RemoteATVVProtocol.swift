import Foundation

enum RemoteATVVVersion: Equatable {
    case v04
    case v10
}

enum RemoteATVVCodec: UInt8, Equatable {
    case adpcm8k = 0x01
    case adpcm16k = 0x02

    var sampleRate: Int {
        switch self {
        case .adpcm8k: return 8_000
        case .adpcm16k: return 16_000
        }
    }
}

struct RemoteATVVCapabilities: Equatable {
    let version: RemoteATVVVersion
    let codecs: UInt8
    let interactionModel: UInt8
    let frameSize: Int

    var selectedCodec: RemoteATVVCodec? {
        if codecs & RemoteATVVCodec.adpcm16k.rawValue != 0 { return .adpcm16k }
        if codecs & RemoteATVVCodec.adpcm8k.rawValue != 0 { return .adpcm8k }
        return nil
    }
}

enum RemoteATVVControlEvent: Equatable {
    case audioStop(reason: UInt8)
    case audioStart(reason: UInt8, codec: RemoteATVVCodec, streamID: UInt8)
    case startSearch
    case audioSync(codec: RemoteATVVCodec, sequence: UInt16, predictor: Int16, stepIndex: UInt8)
    case capabilities(RemoteATVVCapabilities)
    case micOpenError(UInt16)
    case unknown(Data)
}

enum RemoteATVVProtocolError: LocalizedError {
    case capabilitiesMissing
    case unsupportedCodec

    var errorDescription: String? {
        switch self {
        case .capabilitiesMissing: return "遥控器语音协议尚未协商完成"
        case .unsupportedCodec: return "遥控器不支持 ADPCM 8 kHz 或 16 kHz"
        }
    }
}

/// Independent implementation of the public Google TV Remote Voice-over-BLE protocol.
final class RemoteATVVProtocol {
    static let serviceUUID = "AB5E0001-5A21-4F05-BC7D-AF01F617B664"
    static let txUUID = "AB5E0002-5A21-4F05-BC7D-AF01F617B664"
    static let rxUUID = "AB5E0003-5A21-4F05-BC7D-AF01F617B664"
    static let controlUUID = "AB5E0004-5A21-4F05-BC7D-AF01F617B664"

    let getCapabilitiesCommand = Data([0x0A, 0x01, 0x00, 0x00, 0x03, 0x03])

    private(set) var capabilities: RemoteATVVCapabilities?
    private(set) var codec: RemoteATVVCodec?
    private var decoder = RemoteADPCMDecoder()
    private var nextV10Sequence: UInt16 = 0

    func acceptCapabilities(_ value: RemoteATVVCapabilities) throws {
        guard let selectedCodec = value.selectedCodec else {
            throw RemoteATVVProtocolError.unsupportedCodec
        }
        capabilities = value
        codec = selectedCodec
        nextV10Sequence = 0
        decoder.reset(predictor: 0, stepIndex: 0)
    }

    func micOpenCommand() throws -> Data {
        guard let capabilities, let codec else {
            throw RemoteATVVProtocolError.capabilitiesMissing
        }
        switch capabilities.version {
        case .v04: return Data([0x0C, 0x00, codec.rawValue])
        case .v10: return Data([0x0C, 0x00])
        }
    }

    func micCloseCommand(streamID: UInt8) throws -> Data {
        guard let capabilities else { throw RemoteATVVProtocolError.capabilitiesMissing }
        return capabilities.version == .v04 ? Data([0x0D]) : Data([0x0D, streamID])
    }

    func parseControl(_ data: Data) -> RemoteATVVControlEvent {
        let bytes = Array(data)
        guard let opcode = bytes.first else { return .unknown(data) }
        switch opcode {
        case 0x00:
            return .audioStop(reason: bytes.count > 1 ? bytes[1] : 0)
        case 0x04:
            if capabilities?.version == .v10 {
                guard bytes.count >= 4, let eventCodec = RemoteATVVCodec(rawValue: bytes[2]) else {
                    return .unknown(data)
                }
                return .audioStart(reason: bytes[1], codec: eventCodec, streamID: bytes[3])
            }
            return .audioStart(reason: 0, codec: codec ?? .adpcm8k, streamID: 0)
        case 0x08:
            return .startSearch
        case 0x0A:
            guard capabilities?.version == .v10,
                  bytes.count >= 7,
                  let syncCodec = RemoteATVVCodec(rawValue: bytes[1]) else {
                return .unknown(data)
            }
            let sequence = UInt16(bytes[2]) << 8 | UInt16(bytes[3])
            let predictorBits = UInt16(bytes[4]) << 8 | UInt16(bytes[5])
            return .audioSync(
                codec: syncCodec,
                sequence: sequence,
                predictor: Int16(bitPattern: predictorBits),
                stepIndex: bytes[6]
            )
        case 0x0B:
            guard let parsed = Self.parseCapabilities(data) else { return .unknown(data) }
            return .capabilities(parsed)
        case 0x0C:
            guard bytes.count >= 3 else { return .micOpenError(0xFFFF) }
            return .micOpenError(UInt16(bytes[1]) << 8 | UInt16(bytes[2]))
        default:
            return .unknown(data)
        }
    }

    static func parseCapabilities(_ data: Data) -> RemoteATVVCapabilities? {
        let bytes = Array(data)
        guard bytes.count >= 3, bytes[0] == 0x0B else { return nil }
        let versionValue = UInt16(bytes[1]) << 8 | UInt16(bytes[2])
        switch versionValue {
        case 0x0004:
            guard bytes.count >= 9 else { return nil }
            let frameSize = Int(UInt16(bytes[5]) << 8 | UInt16(bytes[6]))
            guard frameSize >= 6 else { return nil }
            return RemoteATVVCapabilities(
                version: .v04,
                codecs: bytes[4],
                interactionModel: 0,
                frameSize: frameSize
            )
        case 0x0100:
            guard bytes.count >= 7 else { return nil }
            let standardCodec = bytes[3]
            let standardInteraction = bytes[4]
            let standardIsKnown = standardCodec & 0x03 != 0
            let adjacentIsKnown = standardInteraction & 0x03 != 0
            let usesObservedXiaomiLayout = !standardIsKnown && adjacentIsKnown
            let frameSize = Int(UInt16(bytes[5]) << 8 | UInt16(bytes[6]))
            guard frameSize > 0 else { return nil }
            return RemoteATVVCapabilities(
                version: .v10,
                codecs: usesObservedXiaomiLayout ? standardInteraction : standardCodec,
                interactionModel: usesObservedXiaomiLayout ? standardCodec : standardInteraction,
                frameSize: frameSize
            )
        default:
            return nil
        }
    }

    func applyAudioSync(
        codec: RemoteATVVCodec,
        sequence: UInt16,
        predictor: Int16,
        stepIndex: UInt8
    ) {
        self.codec = codec
        nextV10Sequence = sequence
        decoder.reset(predictor: predictor, stepIndex: stepIndex)
    }

    func decodeAudio(_ data: Data) -> (sequence: UInt16, samples: [Int16])? {
        guard let capabilities, codec != nil else { return nil }
        let bytes = Array(data)
        guard bytes.count == capabilities.frameSize else { return nil }

        switch capabilities.version {
        case .v04:
            guard bytes.count >= 6 else { return nil }
            let sequence = UInt16(bytes[0]) << 8 | UInt16(bytes[1])
            let predictorBits = UInt16(bytes[3]) << 8 | UInt16(bytes[4])
            let predictor = Int16(bitPattern: predictorBits)
            decoder.reset(predictor: predictor, stepIndex: bytes[5])
            return (sequence, [predictor] + decoder.decode(bytes.dropFirst(6)))
        case .v10:
            let sequence = nextV10Sequence
            nextV10Sequence &+= 1
            return (sequence, decoder.decode(bytes))
        }
    }
}
