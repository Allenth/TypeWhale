import Foundation

@main
enum ASRButtonFlowLayoutCheck {
    static func main() {
        let compact = ASRButtonFlowLayout.layout(
            containerWidth: 320,
            itemWidths: [120, 180, 130]
        )
        precondition(compact.frames.count == 3)
        precondition(compact.frames[0].minY == compact.frames[1].minY)
        precondition(compact.frames[2].minY > compact.frames[1].minY)
        precondition(compact.frames[0].maxX < compact.frames[1].minX)
        precondition(compact.frames.allSatisfy { $0.minX >= 0 && $0.maxX <= 320 })
        precondition(compact.height > ASRButtonFlowLayout.rowHeight)

        let wide = ASRButtonFlowLayout.layout(
            containerWidth: 480,
            itemWidths: [120, 180, 130]
        )
        precondition(Set(wide.frames.map(\.minY)).count == 1)
        precondition(wide.height < compact.height)

        let oversized = ASRButtonFlowLayout.layout(
            containerWidth: 100,
            itemWidths: [180]
        )
        precondition(oversized.frames[0].width <= 96)
        precondition(oversized.frames[0].maxX <= 100)

        print("ASRButtonFlowLayoutCheck passed")
    }
}
