import AppKit
import Foundation

// SVG を各サイズの PNG にレンダリングする(NSImage は macOS 11+ で SVG 対応。Xcode 不要)。
// make_icon.sh から使う。usage: swift render_icon.swift <svg> <出力dir> [サイズ...]
let args = CommandLine.arguments
guard args.count >= 3 else {
    print("usage: render_icon <svg path> <out dir> [sizes...]")
    exit(1)
}
let svgURL = URL(fileURLWithPath: args[1])
let outDir = URL(fileURLWithPath: args[2], isDirectory: true)
let sizes = args.count > 3 ? args[3...].compactMap { Int($0) } : [1024]

guard let image = NSImage(contentsOf: svgURL) else {
    print("failed to load SVG")
    exit(1)
}
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

for size in sizes {
    guard
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
    else { continue }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    image.draw(
        in: NSRect(x: 0, y: 0, width: size, height: size),
        from: .zero, operation: .copy, fraction: 1.0)
    NSGraphicsContext.restoreGraphicsState()
    guard let png = rep.representation(using: .png, properties: [:]) else { continue }
    let out = outDir.appendingPathComponent("icon_\(size).png")
    try? png.write(to: out)
    print("wrote \(out.path)")
}
