import Foundation

@main
struct RemoteATVVProtocolCheck {
    static func main() throws {
        parsesV10CapabilitiesAndCommands()
        parsesTheObservedXiaomiSwappedLayout()
        try parsesV04CapabilitiesAndFrames()
        try parsesControlEventsAndV10Frames()
        rejectsMalformedInput()
        print("RemoteATVVProtocolCheck passed")
    }

    private static func parsesV10CapabilitiesAndCommands() {
        let standard = Data([0x0B, 0x01, 0x00, 0x02, 0x03, 0x00, 0x78, 0x00, 0x00])
        let capabilities = RemoteATVVProtocol.parseCapabilities(standard)
        precondition(capabilities == RemoteATVVCapabilities(version: .v10, codecs: 0x02, interactionModel: 0x03, frameSize: 120))
        precondition(capabilities?.selectedCodec == .adpcm16k)
    }

    private static func parsesTheObservedXiaomiSwappedLayout() {
        let swapped = Data([0x0B, 0x01, 0x00, 0x00, 0x03, 0x00, 0x78, 0x00, 0x00])
        let capabilities = RemoteATVVProtocol.parseCapabilities(swapped)
        precondition(capabilities == RemoteATVVCapabilities(version: .v10, codecs: 0x03, interactionModel: 0x00, frameSize: 120))
        precondition(capabilities?.selectedCodec == .adpcm16k)
    }

    private static func parsesV04CapabilitiesAndFrames() throws {
        let capabilitiesData = Data([0x0B, 0x00, 0x04, 0x00, 0x03, 0x00, 0x86, 0x00, 0x00])
        let capabilities = try require(RemoteATVVProtocol.parseCapabilities(capabilitiesData))
        precondition(capabilities.version == .v04)
        precondition(capabilities.frameSize == 134)

        let protocolHandler = RemoteATVVProtocol()
        try protocolHandler.acceptCapabilities(capabilities)
        precondition(protocolHandler.getCapabilitiesCommand == Data([0x0A, 0x01, 0x00, 0x00, 0x03, 0x03]))
        let open = try protocolHandler.micOpenCommand()
        let close = try protocolHandler.micCloseCommand(streamID: 9)
        precondition(open == Data([0x0C, 0x00, 0x02]))
        precondition(close == Data([0x0D]))

        var bytes = [UInt8](repeating: 0, count: 134)
        bytes[0] = 0x00
        bytes[1] = 0x12
        bytes[3] = 0x00
        bytes[4] = 0x64
        bytes[5] = 0x00
        let frame = try require(protocolHandler.decodeAudio(Data(bytes)))
        precondition(frame.sequence == 0x0012)
        precondition(frame.samples.count == 257)
        precondition(frame.samples.first == 100)
        precondition(protocolHandler.decodeAudio(Data(bytes.dropLast())) == nil)
    }

    private static func parsesControlEventsAndV10Frames() throws {
        let protocolHandler = RemoteATVVProtocol()
        let capabilities = try require(RemoteATVVProtocol.parseCapabilities(
            Data([0x0B, 0x01, 0x00, 0x02, 0x03, 0x00, 0x78])
        ))
        try protocolHandler.acceptCapabilities(capabilities)
        let open = try protocolHandler.micOpenCommand()
        let close = try protocolHandler.micCloseCommand(streamID: 7)
        precondition(open == Data([0x0C, 0x00]))
        precondition(close == Data([0x0D, 0x07]))
        precondition(protocolHandler.parseControl(Data([0x08])) == .startSearch)
        precondition(protocolHandler.parseControl(Data([0x04, 0x00, 0x02, 0x07])) == .audioStart(reason: 0, codec: .adpcm16k, streamID: 7))
        precondition(protocolHandler.parseControl(Data([0x00, 0x03])) == .audioStop(reason: 3))

        let sync = protocolHandler.parseControl(Data([0x0A, 0x02, 0x00, 0x09, 0xFF, 0x9C, 0x0A]))
        precondition(sync == .audioSync(codec: .adpcm16k, sequence: 9, predictor: -100, stepIndex: 10))
        protocolHandler.applyAudioSync(codec: .adpcm16k, sequence: 9, predictor: -100, stepIndex: 10)
        let frame = try require(protocolHandler.decodeAudio(Data(repeating: 0x00, count: 120)))
        precondition(frame.sequence == 9)
        precondition(frame.samples.count == 240)
        precondition(protocolHandler.decodeAudio(Data([0x00])) == nil)
    }

    private static func rejectsMalformedInput() {
        precondition(RemoteATVVProtocol.parseCapabilities(Data()) == nil)
        precondition(RemoteATVVProtocol.parseCapabilities(Data([0x0B, 0x01])) == nil)
        precondition(RemoteATVVProtocol.parseCapabilities(Data([0x0B, 0x02, 0x00, 0x03, 0x03, 0x00, 0x78])) == nil)
        let protocolHandler = RemoteATVVProtocol()
        precondition(protocolHandler.decodeAudio(Data([0x00])) == nil)
        if case .unknown = protocolHandler.parseControl(Data([0x7F])) {} else { preconditionFailure("unknown opcode must remain unknown") }
    }

    private static func require<T>(_ value: T?) throws -> T {
        guard let value else { throw NSError(domain: "RemoteATVVProtocolCheck", code: 1) }
        return value
    }
}
