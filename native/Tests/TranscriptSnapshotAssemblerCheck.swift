import Foundation

@main
struct TranscriptSnapshotAssemblerCheck {
    static func main() {
        precondition(
            TranscriptSnapshotAssembler.deliveryText(
                confirmed: "用户体验",
                volatile: "体验不要了吗"
            ) == "用户体验不要了吗"
        )
        precondition(
            TranscriptSnapshotAssembler.deliveryText(
                confirmed: "代码设计",
                volatile: "计排查一下"
            ) == "代码设计排查一下"
        )
        precondition(
            TranscriptSnapshotAssembler.deliveryText(
                confirmed: "今天我们讨论",
                volatile: "功能优化"
            ) == "今天我们讨论功能优化"
        )
        precondition(
            TranscriptSnapshotAssembler.deliveryText(
                confirmed: "已经稳定",
                volatile: "已经稳定"
            ) == "已经稳定"
        )
        precondition(
            TranscriptSnapshotAssembler.deliveryText(
                confirmed: "好好",
                volatile: "学习"
            ) == "好好学习"
        )
        precondition(
            TranscriptSnapshotAssembler.deliveryText(
                confirmed: "用户体验",
                volatile: "不要了吗"
            ) == "用户体验不要了吗"
        )

        print("TranscriptSnapshotAssemblerCheck passed")
    }
}
