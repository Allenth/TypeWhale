import Foundation

@main
struct CapsuleSnapshotBufferCheck {
    static func main() {
        let buffer = CapsuleTextBuffer(animatedTailLimit: 4, firstPreviewMinimumCharacters: 2)

        // 1. 首帧：与字符串路径一致的初始追赶与逐字推进。
        var update = buffer.setSnapshot(
            stableCharacterCount: 0,
            stableWindowText: "",
            volatileTailText: "今天我们讨论实时预览"
        )
        guard case .updated(let firstFade?, true, false) = update else {
            preconditionFailure("first snapshot must start the typewriter")
        }
        precondition(firstFade == 0)
        assert(buffer.displayedDraft, equals: "今天我们讨论")
        precondition(buffer.displayedVolatileStartIndex == 0, "all-volatile snapshot must dim from index 0")
        while buffer.displayedDraft != buffer.targetDraft {
            _ = buffer.advance()
        }
        assert(buffer.displayedDraft, equals: "今天我们讨论实时预览")

        // 2. 边界前移、内容不变：显示内容一个字不动，只移动稳定/可变分界。
        update = buffer.setSnapshot(
            stableCharacterCount: 10,
            stableWindowText: "今天我们讨论实时预览",
            volatileTailText: ""
        )
        assert(buffer.displayedDraft, equals: "今天我们讨论实时预览")
        precondition(buffer.displayedVolatileStartIndex == 10, "promotion must move the volatile boundary")
        guard case .updated(nil, false, true) = update else {
            preconditionFailure("boundary-only promotion must not restart animation")
        }

        // 3. 尾部追加：稳定区不动，新尾部走打字机。
        update = buffer.setSnapshot(
            stableCharacterCount: 10,
            stableWindowText: "今天我们讨论实时预览",
            volatileTailText: "接下来"
        )
        assert(buffer.displayedDraft, equals: "今天我们讨论实时预览")
        guard case .updated(let tailFade?, true, false) = update else {
            preconditionFailure("tail growth must animate")
        }
        precondition(tailFade == 10)
        while buffer.displayedDraft != buffer.targetDraft {
            _ = buffer.advance()
        }
        assert(buffer.displayedDraft, equals: "今天我们讨论实时预览接下来")
        precondition(buffer.displayedVolatileStartIndex == 10)

        // 4. 尾部原位修订：只有可变区内容变化，稳定区必须保持原字符。
        _ = buffer.setSnapshot(
            stableCharacterCount: 10,
            stableWindowText: "今天我们讨论实时预览",
            volatileTailText: "架构版"
        )
        assert(buffer.displayedDraft, equals: "今天我们讨论实时预览架构版")
        assert(String(buffer.displayedDraft.prefix(10)), equals: "今天我们讨论实时预览")

        // 5. 窗口左裁剪：稳定区继续追加、窗口左滚，已显示内容保持连续，不整体重排。
        update = buffer.setSnapshot(
            stableCharacterCount: 14,
            stableWindowText: "我们讨论实时预览架构版还",
            volatileTailText: "以及"
        )
        assert(buffer.displayedDraft, equals: "我们讨论实时预览架构版")
        guard case .updated(let trimFade?, true, false) = update else {
            preconditionFailure("left-trimmed append must keep animating the new tail")
        }
        precondition(trimFade == 11, "fade must anchor at the continuation point, not restart from 0")
        precondition(buffer.targetDraft.count - buffer.displayedDraft.count <= 4, "backlog must stay bounded")
        while buffer.displayedDraft != buffer.targetDraft {
            _ = buffer.advance()
        }
        assert(buffer.displayedDraft, equals: "我们讨论实时预览架构版还以及")
        precondition(buffer.displayedVolatileStartIndex == 12)

        // 6. 尾部收缩：允许收缩，但只允许发生在可变区。
        _ = buffer.setSnapshot(
            stableCharacterCount: 14,
            stableWindowText: "我们讨论实时预览架构版还",
            volatileTailText: ""
        )
        assert(buffer.displayedDraft, equals: "我们讨论实时预览架构版还")
        precondition(buffer.displayedVolatileStartIndex == 12)

        // 7. 空快照复位。
        update = buffer.setSnapshot(stableCharacterCount: 0, stableWindowText: "", volatileTailText: " ")
        guard case .reset = update else {
            preconditionFailure("blank snapshot must reset the buffer")
        }
        precondition(buffer.displayedDraft.isEmpty)
        precondition(buffer.displayedVolatileStartIndex == 0)

        // 8. 首帧最小字数门槛与字符串路径一致。
        let gated = CapsuleTextBuffer(animatedTailLimit: 4, firstPreviewMinimumCharacters: 3)
        let gatedUpdate = gated.setSnapshot(stableCharacterCount: 0, stableWindowText: "", volatileTailText: "嗯")
        guard case .ignored = gatedUpdate else {
            preconditionFailure("first too-short snapshot must be ignored")
        }

        print("CapsuleSnapshotBufferCheck passed")
    }

    private static func assert(_ actual: String, equals expected: String) {
        precondition(actual == expected, "Expected [\(expected)], got [\(actual)]")
    }
}
