import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var settingsWindow: SettingsWindowController!
    private var githubFlash: FirmwareFlashPanelController!
    private var registeredFlash: RegisteredFlashPanelController!
    private var githubFlashMenuItem: NSMenuItem!
    private var registeredFlashMenuItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        settingsWindow = SettingsWindowController()
        githubFlash = FirmwareFlashPanelController()
        registeredFlash = RegisteredFlashPanelController()

        githubFlash.onOpenSettings = { [weak self] in
            self?.settingsWindow.show(tab: .firmware) { self?.githubFlash.show() }
        }
        registeredFlash.onOpenSettings = { [weak self] in
            self?.settingsWindow.show(tab: .registeredFiles) { self?.registeredFlash.show() }
        }

        setupStatusItem()
        registerHotKeys()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "memorychip", accessibilityDescription: "AutoFlash for ZMK")

        let menu = NSMenu()

        let githubCombo = Settings.hotKey(for: .githubFlash)
        let githubItem = NSMenuItem(
            title: "GitHub Firmware Flash", action: #selector(openGithubFlash), keyEquivalent: githubCombo.keyChar)
        githubItem.keyEquivalentModifierMask = githubCombo.cocoaModifiers
        githubItem.target = self
        githubFlashMenuItem = githubItem
        menu.addItem(githubItem)

        let registeredCombo = Settings.hotKey(for: .registeredFlash)
        let registeredItem = NSMenuItem(
            title: "登録ファイルFlash", action: #selector(openRegisteredFlash), keyEquivalent: registeredCombo.keyChar)
        registeredItem.keyEquivalentModifierMask = registeredCombo.cocoaModifiers
        registeredItem.target = self
        registeredFlashMenuItem = registeredItem
        menu.addItem(registeredItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(
            title: "設定…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let quitItem = NSMenuItem(
            title: "AutoFlash for ZMK を終了", action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q")
        menu.addItem(quitItem)

        menu.delegate = self
        statusItem.menu = menu
    }

    private func registerHotKeys() {
        let githubCombo = Settings.hotKey(for: .githubFlash)
        HotKeyCenter.shared.register(
            id: HotKeyAction.githubFlash.rawValue,
            keyCode: githubCombo.keyCode, modifiers: githubCombo.carbonModifiers
        ) { [weak self] in self?.githubFlash.show() }

        let registeredCombo = Settings.hotKey(for: .registeredFlash)
        HotKeyCenter.shared.register(
            id: HotKeyAction.registeredFlash.rawValue,
            keyCode: registeredCombo.keyCode, modifiers: registeredCombo.carbonModifiers
        ) { [weak self] in self?.registeredFlash.show() }
    }

    @objc private func openGithubFlash() {
        githubFlash.show()
    }

    @objc private func openRegisteredFlash() {
        registeredFlash.show()
    }

    @objc private func openSettings() {
        settingsWindow.show()
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        let githubCombo = Settings.hotKey(for: .githubFlash)
        githubFlashMenuItem.keyEquivalent = githubCombo.keyChar
        githubFlashMenuItem.keyEquivalentModifierMask = githubCombo.cocoaModifiers

        let registeredCombo = Settings.hotKey(for: .registeredFlash)
        registeredFlashMenuItem.keyEquivalent = registeredCombo.keyChar
        registeredFlashMenuItem.keyEquivalentModifierMask = registeredCombo.cocoaModifiers
    }
}
