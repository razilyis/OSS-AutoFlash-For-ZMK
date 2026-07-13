import AppKit
import SwiftUI

@MainActor
final class FirmwareFlashStore: ObservableObject {
    enum Stage { case repositories, branches, files, volumes }
    @Published var stage: Stage = .repositories
    @Published var repositories: [FirmwareRepository] = []
    @Published var branches: [String] = []
    @Published var files: [GitHubFirmwareAPI.DownloadedFirmware] = []
    @Published var volumes: [URL] = []
    @Published var selectedIndex = 0
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var commit = ""
    @Published var fromCache = false
    @Published var showRunWarning = false
    @Published var runWarningMessage = ""
    @Published var hasSuccessfulFallback = false
    var repository: FirmwareRepository?
    var branch = ""
    var file: GitHubFirmwareAPI.DownloadedFirmware?

    var title: String {
        switch stage {
        case .repositories: "Select a repository"
        case .branches: "Select a branch"
        case .files: "Select a UF2 to flash"
        case .volumes: "Select a destination"
        }
    }

    var rows: [(title: String, subtitle: String, warning: Bool)] {
        switch stage {
        case .repositories: return repositories.map { ($0.name, $0.repositoryURL, false) }
        case .branches: return branches.map { ($0, $0 == repository?.defaultBranch ? "default branch" : "", false) }
        case .files: return files.map {
            ($0.url.lastPathComponent,
             "\($0.artifactName) · \($0.relativePath) · commit \(commit)\(fromCache ? " · cached" : "")",
             isDangerous($0.url))
        }
        case .volumes: return volumes.map { ($0.lastPathComponent, $0.path, false) }
        }
    }

    func reset() {
        repositories = FirmwareRepositorySettings.repositories
        stage = .repositories; selectedIndex = 0; errorMessage = nil
        branches = []; files = []; volumes = []; repository = nil; file = nil
    }

    func move(_ delta: Int) { selectedIndex = min(max(0, selectedIndex + delta), max(0, rows.count - 1)) }

    func select() async -> (file: URL, volume: URL)? {
        guard rows.indices.contains(selectedIndex) else { return nil }
        switch stage {
        case .repositories:
            repository = repositories[selectedIndex]
            await loadBranches()
        case .branches:
            branch = branches[selectedIndex]
            await loadFiles()
        case .files:
            file = files[selectedIndex]
            volumes = Flasher.mountedUF2Volumes()
            if volumes.isEmpty { errorMessage = "Connect a UF2 drive, then press ⌘R to refresh." }
            else { stage = .volumes; selectedIndex = 0; errorMessage = nil }
        case .volumes:
            guard let file else { return nil }
            return (file.url, volumes[selectedIndex])
        }
        return nil
    }

    func back() {
        errorMessage = nil; selectedIndex = 0
        switch stage {
        case .repositories: break
        case .branches: stage = .repositories
        case .files: stage = .branches
        case .volumes: stage = .files
        }
    }

    func refresh() async {
        switch stage {
        case .repositories: repositories = FirmwareRepositorySettings.repositories
        case .branches: await loadBranches()
        case .files: await loadFiles()
        case .volumes:
            volumes = Flasher.mountedUF2Volumes(); errorMessage = volumes.isEmpty ? "No UF2 drive found." : nil
        }
    }

    private func loadBranches() async {
        guard let repository else { return }
        isLoading = true; errorMessage = nil
        do {
            var values = try await GitHubFirmwareAPI.branches(
                for: repository, token: FirmwareTokenStore.effectiveToken(for: repository.id))
            if let index = values.firstIndex(of: repository.defaultBranch) { values.insert(values.remove(at: index), at: 0) }
            branches = values; stage = .branches; selectedIndex = 0
        } catch { errorMessage = error.localizedDescription }
        isLoading = false
    }

    func loadFiles(allowFallback: Bool = false) async {
        guard let repository else { return }
        isLoading = true; errorMessage = nil
        do {
            let result = try await GitHubFirmwareAPI.latestUF2Files(
                for: repository, branch: branch,
                token: FirmwareTokenStore.effectiveToken(for: repository.id),
                allowLatestSuccessfulFallback: allowFallback)
            files = result.files; commit = result.commit; fromCache = result.fromCache
            stage = .files; selectedIndex = 0
        } catch let error as FirmwareAPIError {
            if case .latestRunNotSuccessful(_, _, let hasFallback) = error {
                runWarningMessage = error.localizedDescription
                hasSuccessfulFallback = hasFallback
                showRunWarning = true
            } else { errorMessage = error.localizedDescription }
        } catch { errorMessage = error.localizedDescription }
        isLoading = false
    }

    func isDangerous(_ url: URL) -> Bool {
        let name = url.lastPathComponent.lowercased()
        return name.contains("reset") || name.contains("clear") || name.contains("erase")
    }
}

struct FirmwareFlashView: View {
    @ObservedObject var store: FirmwareFlashStore
    let onSelect: (URL, URL, Bool) -> Void
    let onClose: () -> Void
    let onSettings: () -> Void
    let onSwitch: () -> Void
    @FocusState private var focused: Bool
    @AppStorage(Settings.windowOpacityKey) private var windowOpacity: Double = 1.0
    @AppStorage(Settings.windowThemeKey) private var themeStyle: AutoFlashThemeStyle = .light
    private var theme: ThemePalette { themeStyle.palette }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                ThemeBadge(systemImage: "memorychip", text: store.title, palette: theme)
                Spacer()
                if store.isLoading { ProgressView().controlSize(.small) }
                Button { onSettings() } label: { Image(systemName: "gearshape") }
                    .buttonStyle(.borderless).foregroundStyle(theme.textSecondary)
                    .help("Open Firmware settings (⌘K)")
                Button { onClose() } label: { Image(systemName: "xmark") }
                    .buttonStyle(.borderless).foregroundStyle(theme.textSecondary)
                    .help("Close")
            }.padding(14)
            Divider().overlay(theme.divider)
            List(selection: Binding<Int?>(
                get: { store.selectedIndex },
                set: { value in if let value { store.selectedIndex = value } }
            )) {
                ForEach(Array(store.rows.enumerated()), id: \.offset) { index, row in
                    HStack {
                        Image(systemName: row.warning ? "exclamationmark.triangle.fill" : icon)
                            .foregroundStyle(row.warning ? theme.orange : theme.purple)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.title).foregroundStyle(theme.textPrimary)
                            if !row.subtitle.isEmpty { Text(row.subtitle).font(.caption).foregroundStyle(theme.textSecondary) }
                        }
                    }
                    .tag(index)
                    .listRowBackground(index == store.selectedIndex ? theme.rowSelected : Color.clear)
                    .onTapGesture(count: 2) { Task { await select() } }
                }
            }
            .scrollContentBackground(.hidden)
            .tint(theme.purple)
            .focusable().focused($focused)
            .onKeyPress(phases: .down, action: handleKey)
            if let error = store.errorMessage {
                Text(error).font(.caption).foregroundStyle(theme.orange).padding(.horizontal, 14).padding(.vertical, 6)
            }
            Divider().overlay(theme.divider)
            HStack {
                Button("Select (↩)") { Task { await select() } }.keyboardShortcut(.return, modifiers: [])
                Button("Refresh (⌘R)") { Task { await store.refresh() } }.keyboardShortcut("r")
                Button("Settings (⌘K)") { onSettings() }.keyboardShortcut("k")
                Spacer()
                ThemeHintPill(text: "Tab Registered Files", tint: theme.mint)
                ThemeHintPill(text: "Esc Back/Close", tint: theme.orange)
                ThemeHintPill(text: Settings.hotKey(for: .githubFlash).label, tint: theme.purple)
            }.font(.caption).tint(theme.purple).padding(10)
        }
        .frame(width: 680, height: 440)
        .foregroundStyle(theme.textPrimary)
        .autoFlashPanelBackground(palette: theme, opacity: windowOpacity)
        .onAppear { focused = true }
        .alert("Can't use the latest workflow run", isPresented: $store.showRunWarning) {
            if store.hasSuccessfulFallback {
                Button("Use latest successful run") { Task { await store.loadFiles(allowFallback: true) } }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(store.runWarningMessage + (store.hasSuccessfulFallback
                ? "\nYou can fetch the UF2 from the latest successful run instead." : "\nNo successful run is available either."))
        }
    }

    private var icon: String {
        switch store.stage { case .repositories: "shippingbox"; case .branches: "arrow.triangle.branch"; case .files: "doc"; case .volumes: "externaldrive" }
    }
    private func select() async {
        if let result = await store.select() { onSelect(result.file, result.volume, store.isDangerous(result.file)) }
    }
    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        switch press.key {
        case .upArrow: store.move(-1); return .handled
        case .downArrow: store.move(1); return .handled
        case .return: Task { await select() }; return .handled
        case .escape:
            if store.stage == .repositories { onClose() } else { store.back() }
            return .handled
        case "r" where press.modifiers.contains(.command): Task { await store.refresh() }; return .handled
        case "k" where press.modifiers.contains(.command): onSettings(); return .handled
        case .tab: onSwitch(); return .handled
        default: return .ignored
        }
    }
}

@MainActor
final class FirmwareFlashPanelController {
    private let panel: FirmwareFlashPanel
    private let store = FirmwareFlashStore()
    private var hasPositioned = false
    var onOpenSettings: (() -> Void)?
    var onSwitchToRegistered: (() -> Void)?

    init() {
        panel = FirmwareFlashPanel(contentRect: NSRect(x: 0, y: 0, width: 680, height: 440), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isFloatingPanel = true; panel.level = .floating; panel.backgroundColor = .clear
        panel.isOpaque = false; panel.hasShadow = true; panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.onCancel = { [weak self] in
            guard let self else { return }
            if self.store.stage == .repositories { self.hide() } else { self.store.back() }
        }
        panel.contentView = NSHostingView(rootView: FirmwareFlashView(
            store: store,
            onSelect: { [weak self] file, volume, dangerous in self?.confirmAndWrite(file: file, volume: volume, dangerous: dangerous) },
            onClose: { [weak self] in self?.hide() },
            onSettings: { [weak self] in self?.hide(); self?.onOpenSettings?() },
            onSwitch: { [weak self] in self?.onSwitchToRegistered?() }))
    }

    var origin: NSPoint { panel.frame.origin }

    func show(at origin: NSPoint? = nil) {
        store.reset(); panel.alphaValue = 1
        if let origin {
            panel.setFrameOrigin(origin)
        } else if !hasPositioned, let screen = NSScreen.main {
            panel.setFrameOrigin(NSPoint(x: screen.visibleFrame.midX - 340, y: screen.visibleFrame.midY - 180))
        }
        hasPositioned = true
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
            store.file = nil
            store.volumes = []
            store.errorMessage = nil
            store.selectedIndex = 0
            panel.makeKeyAndOrderFront(nil)
            HUD.show("Flashed to \(volume.lastPathComponent). You can select the next UF2.")
        } catch { HUD.show("Flash failed: \(error.localizedDescription)") }
    }
}

final class FirmwareFlashPanel: NSPanel {
    var onCancel: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}
