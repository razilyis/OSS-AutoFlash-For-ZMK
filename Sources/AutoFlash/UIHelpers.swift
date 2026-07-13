import AppKit
import SwiftUI

// 書き込み完了/失敗の一時フィードバック(HUD)。
// 非アクティブ化パネルなのでフォーカスを奪わず、クリックも透過する。
@MainActor
enum HUD {
    private static var currentPanel: NSPanel?

    static func show(_ message: String) {
        currentPanel?.orderOut(nil)

        let content = NSHostingView(
            rootView:
                Text(message)
                .font(.system(size: 14, weight: .medium))
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(.separator, lineWidth: 1))
        )
        content.frame.size = content.fittingSize

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: content.frame.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = content

        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            panel.setFrameOrigin(
                NSPoint(
                    x: frame.midX - content.frame.width / 2,
                    y: frame.minY + frame.height * 0.16
                ))
        }

        panel.alphaValue = 1
        panel.orderFrontRegardless()
        currentPanel = panel

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            guard panel == currentPanel else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.35
                panel.animator().alphaValue = 0
            } completionHandler: {
                Task { @MainActor in
                    panel.orderOut(nil)
                    if panel == currentPanel {
                        currentPanel = nil
                    }
                }
            }
        }
    }
}

// UF2/bin/hex等ファイルの表示アイコン
enum FileIcon {
    static func symbol(for fileExtension: String) -> String {
        switch fileExtension.lowercased() {
        case "uf2", "bin", "hex":
            return "cpu"
        case "zip", "gz", "tar":
            return "doc.zipper"
        default:
            return "doc"
        }
    }
}
