import Foundation

struct ChunkCommitTicket: Equatable, Sendable {
    let id: UUID
    let chunkIndex: Int
    let startFrame: Int64
    let endFrame: Int64
    let frozenBufferCount: Int
    let attempt: Int

    func retrying() -> ChunkCommitTicket {
        ChunkCommitTicket(
            id: id,
            chunkIndex: chunkIndex,
            startFrame: startFrame,
            endFrame: endFrame,
            frozenBufferCount: frozenBufferCount,
            attempt: attempt + 1
        )
    }
}

enum ChunkCommitState: Equatable, Sendable {
    case collecting(chunkIndex: Int, startFrame: Int64)
    case prepared(ChunkCommitTicket)
    case writing(ChunkCommitTicket)
    case retryableFailure(ChunkCommitTicket, message: String)
    case committed(ChunkCommitTicket)
    case recoveredFromFullRecording(ChunkCommitTicket)
}

enum ChunkCommitTransitionError: Error, Equatable {
    case invalidTransition
    case invalidRange
    case emptyFrozenBuffers
}

struct ChunkCommitStateMachine: Sendable {
    private(set) var state: ChunkCommitState

    init(chunkIndex: Int, startFrame: Int64) {
        state = .collecting(chunkIndex: chunkIndex, startFrame: startFrame)
    }

    var ticket: ChunkCommitTicket? {
        switch state {
        case .collecting:
            return nil
        case .prepared(let ticket),
             .writing(let ticket),
             .retryableFailure(let ticket, _),
             .committed(let ticket),
             .recoveredFromFullRecording(let ticket):
            return ticket
        }
    }

    mutating func prepare(
        endFrame: Int64,
        frozenBufferCount: Int
    ) throws -> ChunkCommitTicket {
        guard case .collecting(let chunkIndex, let startFrame) = state else {
            throw ChunkCommitTransitionError.invalidTransition
        }
        guard endFrame > startFrame else {
            throw ChunkCommitTransitionError.invalidRange
        }
        guard frozenBufferCount > 0 else {
            throw ChunkCommitTransitionError.emptyFrozenBuffers
        }
        let ticket = ChunkCommitTicket(
            id: UUID(),
            chunkIndex: chunkIndex,
            startFrame: startFrame,
            endFrame: endFrame,
            frozenBufferCount: frozenBufferCount,
            attempt: 1
        )
        state = .prepared(ticket)
        return ticket
    }

    mutating func beginWriting() throws {
        switch state {
        case .prepared(let ticket):
            state = .writing(ticket)
        case .retryableFailure(let ticket, _):
            state = .writing(ticket.retrying())
        default:
            throw ChunkCommitTransitionError.invalidTransition
        }
    }

    mutating func failWriting(message: String) throws {
        guard case .writing(let ticket) = state else {
            throw ChunkCommitTransitionError.invalidTransition
        }
        state = .retryableFailure(ticket, message: message)
    }

    mutating func commit() throws {
        guard case .writing(let ticket) = state else {
            throw ChunkCommitTransitionError.invalidTransition
        }
        state = .committed(ticket)
    }

    mutating func recoverFromFullRecording() throws {
        guard case .retryableFailure(let ticket, _) = state else {
            throw ChunkCommitTransitionError.invalidTransition
        }
        state = .recoveredFromFullRecording(ticket)
    }

    mutating func collectNextChunk() throws {
        let completedTicket: ChunkCommitTicket
        switch state {
        case .committed(let ticket), .recoveredFromFullRecording(let ticket):
            completedTicket = ticket
        default:
            throw ChunkCommitTransitionError.invalidTransition
        }
        state = .collecting(
            chunkIndex: completedTicket.chunkIndex + 1,
            startFrame: completedTicket.endFrame
        )
    }
}
