import Foundation

@main
struct PreviewFinalChunkWriteFailureCheck {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            throw CheckError.missingSourcePath
        }
        let source = try String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)

        precondition(source.contains("pendingRealtimeChunk"))
        precondition(source.contains("finalChunkCommitMachine"))
        precondition(source.contains("emitFinalChunkSnapshot"))
        precondition(source.contains("recoverPendingFinalChunkFromFullRecording"))
        precondition(source.contains("final_chunk_snapshot_empty"))

        let finalBranch = try slice(
            source,
            from: "if isChunkFinal",
            through: "prepareFinalChunkCommit("
        )
        precondition(!finalBranch.contains("realtimeChunkIndex += 1"))
        precondition(!finalBranch.contains("realtimeBuffers.removeAll"))

        let emitFinal = try slice(
            source,
            from: "private func emitFinalChunkSnapshot",
            through: "private func commitPendingFinalChunk"
        )
        precondition(emitFinal.contains("pending.samples"))
        precondition(!emitFinal.contains("writeRealtimeSnapshot"))

        print("PreviewFinalChunkWriteFailureCheck passed")
    }

    private static func slice(
        _ source: String,
        from startMarker: String,
        through endMarker: String
    ) throws -> Substring {
        guard let start = source.range(of: startMarker),
              let end = source.range(of: endMarker, range: start.upperBound..<source.endIndex) else {
            throw CheckError.missingIntegrationBoundary
        }
        return source[start.lowerBound..<end.lowerBound]
    }
}

private enum CheckError: Error {
    case missingSourcePath
    case missingIntegrationBoundary
}
