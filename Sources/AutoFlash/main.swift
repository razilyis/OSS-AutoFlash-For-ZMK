import AppKit

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    // NSApplication.delegate は強参照を持たないため run() の間 delegate を保持する
    withExtendedLifetime(delegate) {
        app.run()
    }
}
