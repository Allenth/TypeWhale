import Foundation

struct RemoteButtonActionGroup: Equatable {
    let title: String
    let actions: [RemoteButtonAction]
}

enum RemoteButtonActionPresentation {
    static func groups(for button: RemoteButton) -> [RemoteButtonActionGroup] {
        let allowed = Set(RemoteActionCatalog.builtIn.allowedActions(for: button))
        let candidates: [RemoteButtonActionGroup] = [
            RemoteButtonActionGroup(
                title: "默认",
                actions: button == .voice ? [.pushToTalk, .system] : [.system]
            ),
            RemoteButtonActionGroup(
                title: "键盘",
                actions: [.keyboardEscape, .keyboardDelete, .keyboardReturn]
            ),
            RemoteButtonActionGroup(
                title: "TypeWhale",
                actions: [.toggleMainWindow, .send, .cancel]
            ),
            RemoteButtonActionGroup(
                title: "Mac",
                actions: [.lockMac]
            ),
            RemoteButtonActionGroup(
                title: "关闭",
                actions: [.none]
            ),
        ]
        return candidates.compactMap { group in
            let filtered = group.actions.filter(allowed.contains)
            return filtered.isEmpty
                ? nil
                : RemoteButtonActionGroup(title: group.title, actions: filtered)
        }
    }
}
