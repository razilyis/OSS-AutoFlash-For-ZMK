import Carbon.HIToolbox
import Foundation
import ServiceManagement

// ホットキー識別子(HotKeyCenter の登録 ID と UserDefaults キーに使う)
enum HotKeyAction: String, CaseIterable {
    case githubFlash = "hotkey.githubFlash"
    case registeredFlash = "hotkey.registeredFlash"

    var title: String {
        switch self {
        case .githubFlash: return "GitHub Firmware Flash"
        case .registeredFlash: return "Registered File Flash"
        }
    }

    @MainActor
    var defaultCombo: KeyCombo {
        switch self {
        case .githubFlash:
            return KeyCombo(
                keyCode: UInt32(kVK_ANSI_U), carbonModifiers: UInt32(cmdKey | optionKey),
                label: "⌥⌘U", keyChar: "u")
        case .registeredFlash:
            return KeyCombo(
                keyCode: UInt32(kVK_ANSI_F), carbonModifiers: UInt32(cmdKey | optionKey),
                label: "⌥⌘F", keyChar: "f")
        }
    }
}

@MainActor
enum Settings {
    private static var defaults: UserDefaults { .standard }

    // ホットキー割り当て。未設定ならデフォルトを返す。
    static func hotKey(for action: HotKeyAction) -> KeyCombo {
        guard let dict = defaults.dictionary(forKey: action.rawValue),
            let combo = KeyCombo(dictionary: dict)
        else {
            return action.defaultCombo
        }
        return combo
    }

    static func setHotKey(_ combo: KeyCombo, for action: HotKeyAction) {
        defaults.set(combo.dictionary, forKey: action.rawValue)
    }

    static func resetHotKey(for action: HotKeyAction) {
        defaults.removeObject(forKey: action.rawValue)
    }
}

// ログイン時自動起動。SMAppService は .app バンドルからの起動が前提で、
// swift run の裸バイナリからは登録に失敗する(エラーを返す)。
@MainActor
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
