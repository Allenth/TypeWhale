struct SmartInputContext {
    let targetAppName: String?
    let targetBundleIdentifier: String?
    let windowTitle: String?

    init(
        targetAppName: String? = nil,
        targetBundleIdentifier: String? = nil,
        windowTitle: String? = nil
    ) {
        self.targetAppName = targetAppName
        self.targetBundleIdentifier = targetBundleIdentifier
        self.windowTitle = windowTitle
    }
}
