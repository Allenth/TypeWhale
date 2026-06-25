import AppKit
import ApplicationServices
import Foundation

enum HotkeyKeyCodes {
    static let leftCommand = 55
    static let rightCommand = 54
    static let leftShift = 56
    static let rightShift = 60
    static let leftOption = 58
    static let rightOption = 61
    static let leftControl = 59
    static let rightControl = 62
    static let function = 63
    static let backslash = 42

    static let modifierKeyCodes: Set<Int> = [
        leftCommand, rightCommand, leftShift, rightShift,
        leftOption, rightOption, leftControl, rightControl, function,
    ]

    static let names: [Int: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2",
        20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8",
        29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 36: "Return",
        37: "L", 38: "J", 39: "'", 40: "K", 41: ";", backslash: "\\", 43: ",", 44: "/", 45: "N",
        46: "M", 47: ".", 49: "Space", 50: "`", 51: "Delete", 53: "Esc",
        leftCommand: "左 Cmd", rightCommand: "右 Cmd",
        leftShift: "左 Shift", rightShift: "右 Shift",
        leftOption: "左 Option", rightOption: "右 Option",
        leftControl: "左 Control", rightControl: "右 Control",
        function: "Fn",
    ]

    static func displayName(for keyCode: Int) -> String {
        names[keyCode] ?? "Key \(keyCode)"
    }

    static func modifierFlags(for keyCode: Int) -> NSEvent.ModifierFlags {
        switch keyCode {
        case leftCommand, rightCommand:
            return .command
        case leftShift, rightShift:
            return .shift
        case leftOption, rightOption:
            return .option
        case leftControl, rightControl:
            return .control
        case function:
            return .function
        default:
            return []
        }
    }

    static func cgModifierFlags(for keyCode: Int) -> CGEventFlags {
        switch keyCode {
        case leftCommand, rightCommand:
            return .maskCommand
        case leftShift, rightShift:
            return .maskShift
        case leftOption, rightOption:
            return .maskAlternate
        case leftControl, rightControl:
            return .maskControl
        case function:
            return .maskSecondaryFn
        default:
            return []
        }
    }

    static func fallbackModifierKeyCodes(from flags: NSEvent.ModifierFlags) -> Set<Int> {
        var result: Set<Int> = []
        if flags.contains(.command) { result.insert(leftCommand) }
        if flags.contains(.option) { result.insert(leftOption) }
        if flags.contains(.control) { result.insert(leftControl) }
        if flags.contains(.shift) { result.insert(leftShift) }
        if flags.contains(.function) { result.insert(function) }
        return result
    }

    static func fallbackModifierKeyCodes(from flags: CGEventFlags) -> Set<Int> {
        var result: Set<Int> = []
        if flags.contains(.maskCommand) { result.insert(leftCommand) }
        if flags.contains(.maskAlternate) { result.insert(leftOption) }
        if flags.contains(.maskControl) { result.insert(leftControl) }
        if flags.contains(.maskShift) { result.insert(leftShift) }
        if flags.contains(.maskSecondaryFn) { result.insert(function) }
        return result
    }
}

struct HotkeyBinding: Codable, Equatable {
    enum Kind: String, Codable {
        case function
        case modifier
        case combo
        case mediaPlay
    }

    static let storageKey = "hotkeyBinding"
    static let chineseStorageKey = "chineseHotkeyBinding"
    static let secondaryChineseStorageKey = "secondaryChineseHotkeyBinding"
    static let screenshotStorageKey = "screenshotHotkeyBinding"
    static let secondaryScreenshotStorageKey = "secondaryScreenshotHotkeyBinding"
    static let autoTranslateStorageKey = "autoTranslateHotkeyBinding"
    static let mainWindowStorageKey = "mainWindowHotkeyBinding"
    static let fnDefaultMigrationKey = "hotkeyDefaultMigration.fnDefault.v1"
    let kind: Kind
    let keyCode: Int?
    let modifierKeyCodes: [Int]
    let tapCount: Int?

    init(kind: Kind, keyCode: Int?, modifierKeyCodes: [Int], tapCount: Int? = nil) {
        self.kind = kind
        self.keyCode = keyCode
        self.modifierKeyCodes = modifierKeyCodes
        self.tapCount = tapCount
    }

    static var defaultBinding: HotkeyBinding {
        HotkeyBinding(kind: .function, keyCode: HotkeyKeyCodes.function, modifierKeyCodes: [])
    }

    static var screenshotDefaultBinding: HotkeyBinding {
        HotkeyBinding(kind: .modifier, keyCode: HotkeyKeyCodes.rightOption, modifierKeyCodes: [])
    }

    static func load() -> HotkeyBinding {
        load(storageKey: storageKey, fallback: .defaultBinding)
    }

    static func load(storageKey: String, fallback: HotkeyBinding) -> HotkeyBinding {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let binding = try? JSONDecoder().decode(HotkeyBinding.self, from: data) else {
            if storageKey == chineseStorageKey {
                UserDefaults.standard.set(true, forKey: fnDefaultMigrationKey)
            }
            return fallback
        }
        if storageKey == chineseStorageKey,
           binding.kind == .modifier,
           binding.keyCode == HotkeyKeyCodes.rightCommand,
           !UserDefaults.standard.bool(forKey: fnDefaultMigrationKey) {
            fallback.save(storageKey: storageKey)
            UserDefaults.standard.set(true, forKey: fnDefaultMigrationKey)
            return fallback
        }
        return binding
    }

    static func loadOptional(storageKey: String) -> HotkeyBinding? {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(HotkeyBinding.self, from: data)
    }

    func save(storageKey: String = HotkeyBinding.storageKey) {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    static func clear(storageKey: String) {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    var displayName: String {
        switch kind {
        case .function:
            return "Fn"
        case .modifier:
            return keyCode.map { HotkeyKeyCodes.displayName(for: $0) } ?? "未设置"
        case .combo:
            let modifiers = modifierKeyCodes.map { HotkeyKeyCodes.displayName(for: $0) }
            let key = keyCode.map { HotkeyKeyCodes.displayName(for: $0) } ?? "未设置"
            return (modifiers + [key]).joined(separator: " + ")
        case .mediaPlay:
            return "耳机播放键"
        }
    }

    var screenshotDisplayName: String {
        switch kind {
        case .function, .modifier:
            return "双击\(displayName)"
        case .combo, .mediaPlay:
            return displayName
        }
    }

    var actionDisplayName: String {
        guard let tapCount, tapCount > 1, kind != .combo else { return displayName }
        let prefix: String
        switch tapCount {
        case 2: prefix = "双击"
        case 3: prefix = "三击"
        default: prefix = "\(tapCount)击"
        }
        return "\(prefix)\(displayName)"
    }

    var pressInstruction: String {
        "再次按下 \(displayName) 完成录音"
    }

    var holdInstruction: String {
        "松开 \(displayName) 完成录音"
    }

    static func fromCapture(keyCode: Int, modifierKeyCodes: Set<Int>) -> HotkeyBinding? {
        if keyCode == HotkeyKeyCodes.function {
            return HotkeyBinding(kind: .function, keyCode: HotkeyKeyCodes.function, modifierKeyCodes: [])
        }
        if HotkeyKeyCodes.modifierKeyCodes.contains(keyCode) {
            return HotkeyBinding(kind: .modifier, keyCode: keyCode, modifierKeyCodes: [])
        }
        guard !modifierKeyCodes.isEmpty else { return nil }
        return HotkeyBinding(kind: .combo, keyCode: keyCode, modifierKeyCodes: modifierKeyCodes.sorted())
    }

    static var mediaPlayBinding: HotkeyBinding {
        HotkeyBinding(kind: .mediaPlay, keyCode: nil, modifierKeyCodes: [])
    }
}

enum SpeechInputChannel {
    case chinese

    var languageMode: RecognitionLanguageMode {
        switch self {
        case .chinese: return .chinese
        }
    }

    var displayName: String {
        switch self {
        case .chinese: return "中文"
        }
    }
}
