import Foundation

@main
struct MiMoRequestPartialProjectionCheck {
    static func main() {
        suppressesAcceptedBaselineReplay()
        suppressesShorterNonPrefixRollback()
        emitsRealNonPrefixRevision()
        suppressesDuplicateRequestOutput()
        resetIsolatesTheNextSession()
        print("MiMoRequestPartialProjectionCheck passed")
    }

    private static func suppressesShorterNonPrefixRollback() {
        var projection = MiMoRequestPartialProjection()
        projection.begin(
            snapshotID: "s2-rollback",
            baselineText: String(repeating: "甲", count: 22)
        )
        precondition(
            projection.accept(
                snapshotID: "s2-rollback",
                incomingText: String(repeating: "乙", count: 11)
            ) == .suppressedReplay
        )
    }

    private static func suppressesAcceptedBaselineReplay() {
        var projection = MiMoRequestPartialProjection()
        projection.begin(snapshotID: "s2", baselineText: "在线模型")
        precondition(
            projection.accept(snapshotID: "s2", incomingText: "在")
                == .suppressedReplay
        )
        precondition(
            projection.accept(snapshotID: "s2", incomingText: "在线模型")
                == .suppressedReplay
        )
        precondition(
            projection.accept(snapshotID: "s2", incomingText: "在线模型支持")
                == .emit("在线模型支持")
        )
    }

    private static func emitsRealNonPrefixRevision() {
        var projection = MiMoRequestPartialProjection()
        projection.begin(snapshotID: "s3", baselineText: "今天讨论模型")
        precondition(
            projection.accept(snapshotID: "s3", incomingText: "今天改为方案")
                == .emit("今天改为方案")
        )
    }

    private static func suppressesDuplicateRequestOutput() {
        var projection = MiMoRequestPartialProjection()
        projection.begin(snapshotID: "s4", baselineText: "旧文本")
        precondition(
            projection.accept(snapshotID: "s4", incomingText: "新文本")
                == .emit("新文本")
        )
        precondition(
            projection.accept(snapshotID: "s4", incomingText: "新文本")
                == .suppressedReplay
        )
    }

    private static func resetIsolatesTheNextSession() {
        var projection = MiMoRequestPartialProjection()
        projection.begin(snapshotID: "old", baselineText: "旧会话")
        _ = projection.accept(snapshotID: "old", incomingText: "旧会话扩展")
        projection.reset()
        projection.begin(snapshotID: "new", baselineText: "")
        precondition(
            projection.accept(snapshotID: "new", incomingText: "新")
                == .emit("新")
        )
        precondition(
            projection.accept(snapshotID: "old", incomingText: "迟到")
                == .suppressedReplay
        )
    }
}
