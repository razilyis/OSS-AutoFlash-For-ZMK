import AppKit
import Carbon.HIToolbox

// ホットキー1つ分のキー割り当て。ユーザーが設定画面から任意に変更できる。
struct KeyCombo: Equatable {
    var keyCode: UInt32
    var carbonModifiers: UInt32
    var label: String  // 表示用(例: ⇧⌘V)
    var keyChar: String  // メニューの keyEquivalent 用(小文字1文字。特殊キーは空)

    // NSEvent(キー押下)から生成する
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard !flags.isEmpty else { return nil }

        var carbon: UInt32 = 0
        var prefix = ""
        if flags.contains(.control) {
            carbon |= UInt32(controlKey)
            prefix += "⌃"
        }
        if flags.contains(.option) {
            carbon |= UInt32(optionKey)
            prefix += "⌥"
        }
        if flags.contains(.shift) {
            carbon |= UInt32(shiftKey)
            prefix += "⇧"
        }
        if flags.contains(.command) {
            carbon |= UInt32(cmdKey)
            prefix += "⌘"
        }

        self.keyCode = UInt32(event.keyCode)
        self.carbonModifiers = carbon
        let name = KeyCombo.keyName(
            keyCode: event.keyCode, characters: event.charactersIgnoringModifiers)
        self.label = prefix + name
        // 印字可能な1文字のみ keyEquivalent に使う
        let chars = event.charactersIgnoringModifiers ?? ""
        self.keyChar = (chars.count == 1 && !KeyCombo.isSpecialKey(event.keyCode))
            ? chars.lowercased() : ""
    }

    init(keyCode: UInt32, carbonModifiers: UInt32, label: String, keyChar: String) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
        self.label = label
        self.keyChar = keyChar
    }

    // メニューの keyEquivalentModifierMask 用
    var cocoaModifiers: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if carbonModifiers & UInt32(cmdKey) != 0 { flags.insert(.command) }
        if carbonModifiers & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        if carbonModifiers & UInt32(optionKey) != 0 { flags.insert(.option) }
        if carbonModifiers & UInt32(controlKey) != 0 { flags.insert(.control) }
        return flags
    }

    // MARK: - 永続化(UserDefaults の辞書)

    var dictionary: [String: Any] {
        [
            "keyCode": Int(keyCode),
            "modifiers": Int(carbonModifiers),
            "label": label,
            "keyChar": keyChar,
        ]
    }

    init?(dictionary: [String: Any]) {
        guard let keyCode = dictionary["keyCode"] as? Int,
            let modifiers = dictionary["modifiers"] as? Int,
            let label = dictionary["label"] as? String
        else { return nil }
        self.init(
            keyCode: UInt32(keyCode),
            carbonModifiers: UInt32(modifiers),
            label: label,
            keyChar: dictionary["keyChar"] as? String ?? ""
        )
    }

    // MARK: - キー名

    private static func isSpecialKey(_ keyCode: UInt16) -> Bool {
        specialKeyNames[Int(keyCode)] != nil
    }

    private static let specialKeyNames: [Int: String] = [
        kVK_Space: "Space",
        kVK_Return: "↩",
        kVK_Tab: "⇥",
        kVK_Delete: "⌫",
        kVK_ForwardDelete: "⌦",
        kVK_UpArrow: "↑",
        kVK_DownArrow: "↓",
        kVK_LeftArrow: "←",
        kVK_RightArrow: "→",
        kVK_Home: "↖",
        kVK_End: "↘",
        kVK_PageUp: "⇞",
        kVK_PageDown: "⇟",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4",
        kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8",
        kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]

    private static func keyName(keyCode: UInt16, characters: String?) -> String {
        if let special = specialKeyNames[Int(keyCode)] {
            return special
        }
        if let characters, !characters.isEmpty {
            return characters.uppercased()
        }
        return "key\(keyCode)"
    }
}
