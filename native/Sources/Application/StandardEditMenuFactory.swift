import AppKit

@MainActor
enum StandardEditMenuFactory {
    static func makeMenuItem() -> NSMenuItem {
        let item = NSMenuItem()
        item.submenu = makeMenu()
        return item
    }

    private static func makeMenu() -> NSMenu {
        let menu = NSMenu(title: "编辑")
        menu.addItem(command(title: "撤销", action: Selector(("undo:")), keyEquivalent: "z"))
        menu.addItem(command(
            title: "重做",
            action: Selector(("redo:")),
            keyEquivalent: "z",
            modifierMask: [.command, .shift]
        ))
        menu.addItem(.separator())
        menu.addItem(command(title: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        menu.addItem(command(title: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        menu.addItem(command(title: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        menu.addItem(.separator())
        menu.addItem(command(title: "全选", action: #selector(NSResponder.selectAll(_:)), keyEquivalent: "a"))
        return menu
    }

    private static func command(
        title: String,
        action: Selector,
        keyEquivalent: String,
        modifierMask: NSEvent.ModifierFlags = .command
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.keyEquivalentModifierMask = modifierMask
        item.target = nil
        return item
    }
}
