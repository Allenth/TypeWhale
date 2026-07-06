import Foundation

enum AppBrand {
    static let displayName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
        ?? "TypeWhale Pro"
    static let supportDirectoryName = "TypeWhale Pro"
    static let logsDirectoryName = "TypeWhale Pro"
    static let crashReportFilePrefix = "typewhalepro"
    static let iconResourceName = "TypeWhale"
}
