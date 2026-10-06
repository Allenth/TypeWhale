import Foundation

struct MainCapsuleContextPresentation: Equatable {
    let appNameText: String
    let appIconHidden: Bool
    let modeNameText: String
    let translationDotHidden: Bool
    let translationBadgeHidden: Bool

    init(context: MainCapsuleContext, hasAppIcon: Bool) {
        let trimmedName = context.targetAppName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.appNameText = trimmedName.isEmpty ? "未知应用" : trimmedName
        self.appIconHidden = !hasAppIcon
        self.modeNameText = context.modeName
        self.translationDotHidden = !context.autoTranslateEnabled
        self.translationBadgeHidden = !context.autoTranslateEnabled
    }
}
