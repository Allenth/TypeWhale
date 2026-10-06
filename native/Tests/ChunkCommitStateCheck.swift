import Foundation

@main
struct ChunkCommitStateCheck {
    static func main() throws {
        var machine = ChunkCommitStateMachine(chunkIndex: 0, startFrame: 0)
        let ticket = try machine.prepare(endFrame: 160, frozenBufferCount: 2)
        precondition(machine.state == .prepared(ticket))

        try machine.beginWriting()
        precondition(machine.state == .writing(ticket))
        try machine.failWriting(message: "disk full")
        precondition(machine.state == .retryableFailure(ticket, message: "disk full"))
        precondition(machine.ticket == ticket)

        try machine.beginWriting()
        precondition(machine.state == .writing(ticket.retrying()))
        try machine.commit()
        precondition(machine.state == .committed(ticket.retrying()))
        try machine.collectNextChunk()
        precondition(machine.state == .collecting(chunkIndex: 1, startFrame: 160))

        let fallback = try machine.prepare(endFrame: 320, frozenBufferCount: 3)
        try machine.beginWriting()
        try machine.failWriting(message: "volume unavailable")
        try machine.recoverFromFullRecording()
        precondition(machine.state == .recoveredFromFullRecording(fallback))
        try machine.collectNextChunk()
        precondition(machine.state == .collecting(chunkIndex: 2, startFrame: 320))

        print("ChunkCommitStateCheck passed")
    }
}
