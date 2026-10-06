import Foundation

enum AppBrand {
    static let displayName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
        ?? "TypeWhale Pro"
    static let supportDirectoryName = "TypeWhale Pro"
    static let logsDirectoryName = "TypeWhale Pro"
    static let crashReportFilePrefix = "typewhalepro"
    static let iconResourceName = "TypeWhale"
    static let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.waykingah.typewhale.pro"
    static let temporaryTTSNativeBundleIdentifier = "com.waykingah.typewhale.pro.tts-native"
    static var isTemporaryTTSNativeProfile: Bool {
        bundleIdentifier == temporaryTTSNativeBundleIdentifier || displayName.contains("TTS Native")
    }
}
