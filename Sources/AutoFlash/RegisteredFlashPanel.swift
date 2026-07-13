import AppKit
import SwiftUI

@MainActor
final class RegisteredFlashStore: ObservableObject {
    enum Stage { case files, volumes }
    @Published var stage: Stage = .files
    @Published var firmwares: [RegisteredFirmware] = []
    @Published var volumes: [URL] = []
    @Published var selectedIndex = 0
    @Published var errorMessage: String?
    var file: RegisteredFirmware?

    var title: String {
        switch stage {
        case .files: "Select firmware to flash"
        case .volumes: "Select a destination"
        }
    }

    var rows: [(title: String, subtitle: String, warning: Bool)] {
        switch stage {
        case .files: return firmwares.map {
            ($0.name, $0.fileExists ? $0.filePath : "File not found: \($0.filePath)", isDangerous($0.fileName))
        }
        case .volumes: return volumes.map { ($0.lastPathComponent, $0.path, false) }
        }
    }

    func reset() {
        firmwares = RegisteredFirmwareSettings.firmwares
        stage = .files; selectedIndex = 0; errorMessage = nil
        volumes = []; file = nil
    }

    func move(_ delta: Int) { selectedIndex = min(max(0, selectedIndex + delta), max(0, rows.count - 1)) }

    func select() -> (file: URL, volume: URL)? {
        guard rows.indices.contains(selectedIndex) else { return nil }
        switch stage {
        case .files:
            let firmware = firmwares[selectedIndex]
            guard firmware.fileExists else {
                errorMessage = "File not found: \(firmware.filePath)"
                return nil
            }
            file = firmware
            volumes = Flasher.mountedUF2Volumes()
            if volumes.isEmpty { errorMessage = "Connect a UF2 drive, then press ⌘R to refresh." }
            else { stage = .volumes; selectedIndex = 0; errorMessage = nil }
        case .volumes:
            guard let file, let url = file.url else { return nil }
            return (url, volumes[selectedIndex])
        }
        return nil
    }

    func back() {
        errorMessage = nil; selectedIndex = 0
        switch stage {
        case .files: break
        case .volumes: stage = .files
        }
    }

    func refresh() {
        switch stage {
        case .files: firmwares = RegisteredFirmwareSettings.firmwares
        case .volumes:
            volumes = Flasher.mountedUF2Volumes(); errorMessage = volumes.isEmpty ? "No UF2 drive found." : nil
        }
    }

    func isDangerous(_ fileName: String) -> Bool {
        let name = fileName.lowercased()
        return name.contains("reset") || name.contains("clear") || name.contains("erase")
    }
}

struct RegisteredFlashView: View {
    @ObservedObject var store: RegisteredFlashStore
    let onSelect: (URL, URL, Bool) -> Void
    let onClose: () -> Void
    let onSettings: () -> Void
    let onSwitch: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "cpu")
                Text(store.title).font(.title3)
                Spacer()
                Button { onSettings() } label: { Image(systemName: "gearshape") }
                    .buttonStyle(.borderless).help("Open Registered Files settings (⌘K)")
                Button { onClose() } label: { Image(systemName: "xmark") }
                    .buttonStyle(.borderless).help("Close")
            }.padding(14)
            Divider()
            List(selection: Binding<Int?>(
                get: { store.selectedIndex },
                set: { value in if let value { store.selectedIndex = value } }
            )) {
                ForEach(Array(store.rows.enumerated()), id: \.offset) { index, row in
                    HStack {
                        Image(systemName: row.warning ? "exclamationmark.triangle.fill" : icon)
                            .foregroundStyle(row.warning ? .orange : .secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.title)
                            if !row.subtitle.isEmpty { Text(row.subtitle).font(.caption).foregroundStyle(.secondary) }
                        }
                    }.tag(index).onTapGesture(count: 2) { select() }
                }
            }
            .focusable().focused($focused)
            .onKeyPress(phases: .down, action: handleKey)
            if let error = store.errorMessage {
                Text(error).font(.caption).foregroundStyle(.red).padding(.horizontal, 14).padding(.vertical, 6)
            }
            Divider()
            HStack {
                Button("Select (↩)") { select() }.keyboardShortcut(.return, modifiers: [])
                Button("Refresh (⌘R)") { store.refresh() }.keyboardShortcut("r")
                Button("Settings (⌘K)") { onSettings() }.keyboardShortcut("k")
                Spacer()
                Text("Tab GitHub Firmware").foregroundStyle(.secondary)
                Text("Esc Back/Close").foregroundStyle(.secondary)
                Text(Settings.hotKey(for: .registeredFlash).label).foregroundStyle(.secondary)
            }.font(.caption).padding(10)
        }
        .frame(width: 680, height: 440)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .onAppear { focused = true }
    }

    private var icon: String {
        switch store.stage { case .files: "doc"; case .volumes: "externaldrive" }
    }
    private func select() {
        if let result = store.select() { onSelect(result.file, result.volume, store.isDangerous(result.file.lastPathComponent)) }
    }
    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        switch press.key {
        case .upArrow: store.move(-1); return .handled
        case .downArrow: store.move(1); return .handled
        case .return: select(); return .handled
        case .escape:
            if store.stage == .files { onClose() } else { store.back() }
            return .handled
        case "r" where press.modifiers.contains(.command): store.refresh(); return .handled
        case "k" where press.modifiers.contains(.command): onSettings(); return .handled
        case .tab: onSwitch(); return .handled
        default: return .ignored
        }
    }
}

@MainActor
final class RegisteredFlashPanelController {
    private let panel: RegisteredFlashPanel
    private let store = RegisteredFlashStore()
    var onOpenSettings: (() -> Void)?
    var onSwitchToGithub: (() -> Void)?

    init() {
        panel = RegisteredFlashPanel(contentRect: NSRect(x: 0, y: 0, width: 680, height: 440), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isFloatingPanel = true; panel.level = .floating; panel.backgroundColor = .clear
        panel.isOpaque = false; panel.hasShadow = true; panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.onCancel = { [weak self] in
            guard let self else { return }
            if self.store.stage == .files { self.hide() } else { self.store.back() }
        }
        panel.contentView = NSHostingView(rootView: RegisteredFlashView(
            store: store,
            onSelect: { [weak self] file, volume, dangerous in self?.confirmAndWrite(file: file, volume: volume, dangerous: dangerous) },
            onClose: { [weak self] in self?.hide() },
            onSettings: { [weak self] in self?.hide(); self?.onOpenSettings?() },
            onSwitch: { [weak self] in self?.onSwitchToGithub?() }))
    }

    func show() {
        store.reset(); panel.alphaValue = 1
        if let screen = NSScreen.main { panel.center(); panel.setFrameOrigin(NSPoint(x: screen.visibleFrame.midX - 340, y: screen.visibleFrame.midY - 180)) }
        panel.makeKeyAndOrderFront(nil)
    }
    func hide() { panel.orderOut(nil) }

    private func confirmAndWrite(file: URL, volume: URL, dangerous: Bool) {
        let alert = NSAlert()
        alert.alertStyle = dangerous ? .critical : .warning
        alert.messageText = dangerous ? "Flash the reset UF2?" : "Flash this firmware?"
        alert.informativeText = "\(file.lastPathComponent)\n→ \(volume.lastPathComponent)"
        alert.addButton(withTitle: "Flash"); alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try Flasher.write(fileAt: file, named: file.lastPathComponent, to: volume)
            store.stage = .files
            store.volumes = []
            store.errorMessage = nil
            store.selectedIndex = 0
            panel.makeKeyAndOrderFront(nil)
            HUD.show("Flashed to \(volume.lastPathComponent). You can select the next firmware.")
        } catch { HUD.show("Flash failed: \(error.localizedDescription)") }
    }
}

final class RegisteredFlashPanel: NSPanel {
    var onCancel: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}
