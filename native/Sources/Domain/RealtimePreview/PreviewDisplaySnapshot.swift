import Foundation

/// 展示快照（Presentation Snapshot）：预览权威状态投影给显示层的结构化结果。
///
/// 显示层依赖的契约：
/// - `stableCharacterCount` 在单次会话内单调递增；显示层据此把稳定区当作只追加流，
///   不再对整串文本做逐字符猜测式 diff。
/// - `stableWindowText` 是稳定文本的最近可见窗口；跨修订只允许"左侧裁剪 + 右侧追加"，
///   窗口内已有字符不得改写。
/// - `volatileTailText` 是可变尾部；允许整体原位替换，显示层可用弱化样式区分未定稿内容。
struct PreviewDisplaySnapshot: Equatable, Sendable {
    let revision: Int
    let stableCharacterCount: Int
    let stableWindowText: String
    let volatileTailText: String

    var displayText: String { stableWindowText + volatileTailText }

    static let empty = PreviewDisplaySnapshot(
        revision: 0,
        stableCharacterCount: 0,
        stableWindowText: "",
        volatileTailText: ""
    )
}
