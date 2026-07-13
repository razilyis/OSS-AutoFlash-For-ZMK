import AppKit
import Carbon.HIToolbox
import SwiftUI
import UniformTypeIdentifiers

// 設定ウィンドウ。
enum SettingsTab: Hashable { case general, hotKeys, firmware, registeredFiles }

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var onClose: (() -> Void)?
    private var returnKeyMonitor: Any?

    func show(tab: SettingsTab = .general, onClose: (() -> Void)? = nil) {
        self.onClose = onClose
        removeReturnKeyMonitor()
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "AutoFlash for ZMK Settings"
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            self.window = window
        }
        window?.contentView = NSHostingView(rootView: SettingsView(initialTab: tab))
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        if onClose != nil {
            returnKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
                [weak self] event in
                guard let self, self.window?.isKeyWindow == true,
                    event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command),
                    event.charactersIgnoringModifiers?.lowercased() == "k"
                else { return event }
                self.window?.performClose(nil)
                return nil
            }
        }
    }

    func windowWillClose(_ notification: Notification) {
        removeReturnKeyMonitor()
        let callback = onClose
        onClose = nil
        callback?()
    }

    private func removeReturnKeyMonitor() {
        if let returnKeyMonitor {
            NSEvent.removeMonitor(returnKeyMonitor)
            self.returnKeyMonitor = nil
        }
    }
}

private struct SettingsView: View {
    @State private var selectedTab: SettingsTab

    init(initialTab: SettingsTab) {
        _selectedTab = State(initialValue: initialTab)
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralTab()
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsTab.general)
            HotKeysTab()
                .tabItem { Label("Hotkeys", systemImage: "keyboard") }
                .tag(SettingsTab.hotKeys)
            FirmwareSettingsTab()
                .tabItem { Label("GitHub Firmware", systemImage: "memorychip") }
                .tag(SettingsTab.firmware)
            RegisteredFilesTab()
                .tabItem { Label("Registered Files", systemImage: "doc") }
                .tag(SettingsTab.registeredFiles)
        }
        .frame(width: 640, height: 480)
    }
}

// MARK: - General tab

private struct GeneralTab: View {
    @State private var loginItemEnabled = LoginItem.isEnabled
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Launch at login", isOn: $loginItemEnabled)
                    .onChange(of: loginItemEnabled) { _, value in
                        do {
                            try LoginItem.setEnabled(value)
                            errorMessage = nil
                        } catch {
                            errorMessage = error.localizedDescription
                            loginItemEnabled = LoginItem.isEnabled
                        }
                    }
                if let errorMessage {
                    Text(errorMessage).font(.caption).foregroundStyle(.red)
                }
                Text("Only works when launched from a built .app (fails when run via `swift run`).")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Hotkeys tab

private struct HotKeysTab: View {
    var body: some View {
        Form {
            Section("Hotkeys") {
                ForEach(HotKeyAction.allCases, id: \.rawValue) { action in
                    HotKeyRecorderRow(action: action)
                }
                Text("Click, then press a new combination that includes ⌘ / ⌥ / ⌃. Press Esc to cancel.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct HotKeyRecorderRow: View {
    let action: HotKeyAction

    @State private var combo: KeyCombo?
    @State private var recording = false
    @State private var errorMessage: String?
    @State private var keyMonitor: Any?

    var body: some View {
        HStack {
            Text(action.title)
            Spacer()
            Button {
                recording ? cancelRecording() : startRecording()
            } label: {
                Text(recording ? "Press a key…" : (combo ?? action.defaultCombo).label)
                    .frame(minWidth: 120)
            }
            .tint(recording ? .accentColor : nil)

            Button {
                resetToDefault()
            } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .buttonStyle(.borderless)
            .help("Reset to default (\(action.defaultCombo.label))")
        }
        .onAppear { combo = Settings.hotKey(for: action) }
        .onDisappear { cancelRecording() }

        if let errorMessage {
            Text(errorMessage)
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    private func startRecording() {
        errorMessage = nil
        recording = true
        // 記録中は既存ホットキーが発火しないよう一時停止する
        HotKeyCenter.shared.pauseAll()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handleKeyDown(event)
            return nil  // 記録中のキー入力は他へ流さない
        }
    }

    private func handleKeyDown(_ event: NSEvent) {
        if Int(event.keyCode) == kVK_Escape {
            cancelRecording()
            return
        }
        guard let newCombo = KeyCombo(event: event),
            newCombo.carbonModifiers != 0,
            newCombo.cocoaModifiers.contains(.command)
                || newCombo.cocoaModifiers.contains(.option)
                || newCombo.cocoaModifiers.contains(.control)
        else {
            errorMessage = "Combination must include ⌘, ⌥, or ⌃."
            return
        }

        stopMonitor()
        recording = false

        if HotKeyCenter.shared.updateKey(
            id: action.rawValue,
            keyCode: newCombo.keyCode,
            modifiers: newCombo.carbonModifiers)
        {
            Settings.setHotKey(newCombo, for: action)
            combo = newCombo
            errorMessage = nil
        } else {
            errorMessage = "Couldn't register this combination (it conflicts with another hotkey or app)."
        }
        HotKeyCenter.shared.resumeAll()
    }

    private func cancelRecording() {
        stopMonitor()
        if recording {
            recording = false
            HotKeyCenter.shared.resumeAll()
        }
    }

    private func resetToDefault() {
        cancelRecording()
        let defaultCombo = action.defaultCombo
        if HotKeyCenter.shared.updateKey(
            id: action.rawValue,
            keyCode: defaultCombo.keyCode,
            modifiers: defaultCombo.carbonModifiers)
        {
            Settings.resetHotKey(for: action)
            combo = defaultCombo
            errorMessage = nil
        } else {
            errorMessage = "Couldn't reset to default (conflicts with another hotkey)."
        }
    }

    private func stopMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }
}

// MARK: - GitHub Firmware tab

private struct FirmwareSettingsTab: View {
    @State private var repositories = FirmwareRepositorySettings.repositories
    @State private var selectedID: UUID?
    @State private var commonToken = FirmwareTokenStore.commonToken
    @State private var repositoryToken = ""

    var body: some View {
        Form {
            Section {
                Text("GitHub Personal Access Token")
                    .font(.headline)
                Text("Required to download Actions artifacts. Create one at ") +
                    Text("github.com/settings/personal-access-tokens").bold() +
                    Text(" (Fine-grained token) with **Actions: Read-only** and **Contents: Read-only** permissions for the repositories below.")
                SecureField("Paste your token here", text: $commonToken)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: commonToken) { _, value in FirmwareTokenStore.commonToken = value }
                Text(commonToken.isEmpty ? "No common token set" : "Common token saved in the macOS Keychain")
                    .font(.caption).foregroundStyle(commonToken.isEmpty ? .red : .secondary)
                Text("Used automatically by any repository below that doesn't have its own override token.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("GitHub Repositories") {
                List(repositories, selection: $selectedID) { repository in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(repository.name)
                        Text(repository.repositoryURL).font(.caption).foregroundStyle(.secondary)
                    }.tag(repository.id)
                }.frame(minHeight: 120)
                HStack {
                    Button("Add") { add() }
                    Button("Remove") { remove() }.disabled(selectedID == nil)
                }
            }
            if let index = selectedIndex {
                Section("Repository Settings") {
                    TextField("Display Name", text: binding(index, \.name))
                    TextField("Repository URL", text: repositoryURLBinding(index))
                    TextField("Workflow (e.g. build.yml)", text: binding(index, \.workflow))
                    TextField("Default Branch", text: binding(index, \.defaultBranch))
                    SecureField("Token override (leave blank to use the common token)", text: $repositoryToken)
                        .onChange(of: repositoryToken) { _, value in
                            FirmwareTokenStore.setToken(value, for: repositories[index].id)
                        }
                    HStack {
                        Text(repositoryToken.isEmpty ? "Using common token" : "Overridden with its own token")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Use common token") { repositoryToken = "" }
                            .disabled(repositoryToken.isEmpty)
                    }.font(.caption)
                    Text("Grant only Actions: Read-only and Contents: Read-only for this repository. Press ⌘K to return if you opened this from Firmware Flash.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { repositories = FirmwareRepositorySettings.repositories; selectedID = repositories.first?.id }
        .onChange(of: selectedID) { _, id in
            repositoryToken = id.map(FirmwareTokenStore.token(for:)) ?? ""
        }
    }

    private var selectedIndex: Int? { selectedID.flatMap { id in repositories.firstIndex { $0.id == id } } }
    private func binding(_ index: Int, _ keyPath: WritableKeyPath<FirmwareRepository, String>) -> Binding<String> {
        Binding(get: { repositories[index][keyPath: keyPath] }, set: { value in
            repositories[index][keyPath: keyPath] = value
            FirmwareRepositorySettings.repositories = repositories
        })
    }
    private func repositoryURLBinding(_ index: Int) -> Binding<String> {
        Binding(get: { repositories[index].repositoryURL }, set: { value in
            let previousSuggestedName = repositories[index].suggestedName
            let shouldUpdateName = repositories[index].name.isEmpty
                || repositories[index].name == "New Firmware"
                || repositories[index].name == previousSuggestedName
            repositories[index].repositoryURL = value
            if shouldUpdateName, let suggestedName = repositories[index].suggestedName {
                repositories[index].name = suggestedName
            }
            FirmwareRepositorySettings.repositories = repositories
        })
    }
    private func add() {
        let repository = FirmwareRepository()
        repositories.append(repository); FirmwareRepositorySettings.repositories = repositories
        selectedID = repository.id
    }
    private func remove() {
        guard let selectedID else { return }
        FirmwareTokenStore.removeToken(for: selectedID)
        repositories.removeAll { $0.id == selectedID }; FirmwareRepositorySettings.repositories = repositories
        self.selectedID = repositories.first?.id
    }
}

// MARK: - Registered Files tab

private struct RegisteredFilesTab: View {
    @State private var firmwares = RegisteredFirmwareSettings.firmwares
    @State private var selectedID: UUID?

    var body: some View {
        Form {
            Section("Registered Firmware") {
                List(firmwares, selection: $selectedID) { firmware in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(firmware.name)
                        Text(firmware.filePath).font(.caption).foregroundStyle(.secondary)
                    }.tag(firmware.id)
                }.frame(minHeight: 160)
                HStack {
                    Button("Add File…") { addFromPicker() }
                    Button("Remove") { remove() }.disabled(selectedID == nil)
                }
            }
            if let index = selectedIndex {
                Section("Settings") {
                    TextField("Display Name", text: binding(index, \.name))
                    HStack {
                        Text(firmwares[index].filePath).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Change File…") { changeFile(index) }
                    }
                }
            }
            Text("Registered UF2 files can be flashed directly to a UF2 bootloader drive via hotkey. For split keyboards, register the left and right halves separately.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .onAppear { firmwares = RegisteredFirmwareSettings.firmwares; selectedID = firmwares.first?.id }
    }

    private var selectedIndex: Int? { selectedID.flatMap { id in firmwares.firstIndex { $0.id == id } } }
    private func binding(_ index: Int, _ keyPath: WritableKeyPath<RegisteredFirmware, String>) -> Binding<String> {
        Binding(get: { firmwares[index][keyPath: keyPath] }, set: { value in
            firmwares[index][keyPath: keyPath] = value
            RegisteredFirmwareSettings.firmwares = firmwares
        })
    }
    private func addFromPicker() {
        guard let url = pickFile() else { return }
        var firmware = RegisteredFirmware()
        firmware.filePath = url.path
        firmware.name = firmware.suggestedName ?? url.lastPathComponent
        firmwares.append(firmware); RegisteredFirmwareSettings.firmwares = firmwares
        selectedID = firmware.id
    }
    private func changeFile(_ index: Int) {
        guard let url = pickFile() else { return }
        firmwares[index].filePath = url.path
        RegisteredFirmwareSettings.firmwares = firmwares
    }
    private func pickFile() -> URL? {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        if let uf2 = UTType(filenameExtension: "uf2") {
            panel.allowedContentTypes = [uf2]
        }
        return panel.runModal() == .OK ? panel.url : nil
    }
    private func remove() {
        guard let selectedID else { return }
        firmwares.removeAll { $0.id == selectedID }; RegisteredFirmwareSettings.firmwares = firmwares
        self.selectedID = firmwares.first?.id
    }
}
