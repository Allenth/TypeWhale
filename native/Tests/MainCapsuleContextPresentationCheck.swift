import Foundation

@main
struct MainCapsuleContextPresentationCheck {
    static func main() {
        mapsMissingAppNameToUnknownApp()
        mapsIconVisibility()
        mapsModeNameAndTranslationBadge()
        print("MainCapsuleContextPresentationCheck passed")
    }

    private static func mapsMissingAppNameToUnknownApp() {
        let blank = MainCapsuleContextPresentation(
            context: MainCapsuleContext(targetAppName: "  ", modeName: "原文", autoTranslateEnabled: false),
            hasAppIcon: false
        )
        precondition(blank.appNameText == "未知应用")

        let missing = MainCapsuleContextPresentation(
            context: MainCapsuleContext(targetAppName: nil, modeName: "原文", autoTranslateEnabled: false),
            hasAppIcon: false
        )
        precondition(missing.appNameText == "未知应用")
    }

    private static func mapsIconVisibility() {
        let withIcon = MainCapsuleContextPresentation(
            context: MainCapsuleContext(targetAppName: "ChatGPT", modeName: "原文", autoTranslateEnabled: false),
            hasAppIcon: true
        )
        precondition(withIcon.appIconHidden == false)

        let withoutIcon = MainCapsuleContextPresentation(
            context: MainCapsuleContext(targetAppName: "ChatGPT", modeName: "原文", autoTranslateEnabled: false),
            hasAppIcon: false
        )
        precondition(withoutIcon.appIconHidden == true)
    }

    private static func mapsModeNameAndTranslationBadge() {
        let presentation = MainCapsuleContextPresentation(
            context: MainCapsuleContext(targetAppName: "ChatGPT", modeName: "闪念胶囊", autoTranslateEnabled: true),
            hasAppIcon: true
        )
        precondition(presentation.appNameText == "ChatGPT")
        precondition(presentation.modeNameText == "闪念胶囊")
        precondition(presentation.translationBadgeHidden == false)
        precondition(presentation.translationDotHidden == false)
    }
}
