import AppKit

@main
struct StandardEditMenuCheck {
    static func main() {
        let editItem = StandardEditMenuFactory.makeMenuItem()
        guard let menu = editItem.submenu else {
            assertionFailure("edit menu item must own a submenu")
            return
        }

        assert(editItem.title == "编辑", "top-level edit menu title must be localized")
        assert(menu.title == "编辑", "edit menu title must be localized")
        assertCommand(menu, title: "全选", action: "selectAll:", key: "a", modifiers: .command)
        assertCommand(menu, title: "复制", action: "copy:", key: "c", modifiers: .command)
        assertCommand(menu, title: "粘贴", action: "paste:", key: "v", modifiers: .command)
        assertCommand(menu, title: "剪切", action: "cut:", key: "x", modifiers: .command)
        assertCommand(menu, title: "撤销", action: "undo:", key: "z", modifiers: .command)
        assertCommand(menu, title: "重做", action: "redo:", key: "z", modifiers: [.command, .shift])

        print("StandardEditMenuCheck passed")
    }

    private static func assertCommand(
        _ menu: NSMenu,
        title: String,
        action: String,
        key: String,
        modifiers: NSEvent.ModifierFlags
    ) {
        guard let item = menu.item(withTitle: title) else {
            assertionFailure("missing edit command: \(title)")
            return
        }
        assert(item.target == nil, "\(title) must route through the responder chain")
        assert(item.action == Selector((action)), "\(title) action must be \(action)")
        assert(item.keyEquivalent == key, "\(title) key equivalent must be \(key)")
        assert(item.keyEquivalentModifierMask.intersection([.command, .shift, .option, .control]) == modifiers,
               "\(title) modifier mask must be \(modifiers)")
    }
}
