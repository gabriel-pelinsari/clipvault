// Renders the app icon into an .iconset directory.
// Usage: swift scripts/make-icon.swift <output.iconset>
import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func render(pixels: Int) -> Data {
    let size = CGFloat(pixels)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // macOS icon grid: the body is ~80% of the canvas, with a soft drop shadow.
    let inset = size * 0.1
    let body = NSRect(x: inset, y: inset * 1.15, width: size - inset * 2, height: size - inset * 2)
    let radius = body.width * 0.225
    let path = NSBezierPath(roundedRect: body, xRadius: radius, yRadius: radius)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    shadow.shadowBlurRadius = size * 0.025
    shadow.shadowOffset = NSSize(width: 0, height: -size * 0.012)
    shadow.set()
    NSColor.black.setFill()
    path.fill()
    NSGraphicsContext.restoreGraphicsState()

    let gradient = NSGradient(colors: [
        NSColor(srgbRed: 0.42, green: 0.36, blue: 0.98, alpha: 1),
        NSColor(srgbRed: 0.20, green: 0.14, blue: 0.62, alpha: 1),
    ])!
    gradient.draw(in: path, angle: -70)

    // Subtle top highlight.
    NSGraphicsContext.saveGraphicsState()
    path.addClip()
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.18), NSColor.white.withAlphaComponent(0)])!
        .draw(in: NSRect(x: body.minX, y: body.midY, width: body.width, height: body.height / 2), angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    let config = NSImage.SymbolConfiguration(pointSize: size * 0.4, weight: .semibold)
        .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
    if let clipboard = NSImage(systemSymbolName: "list.clipboard.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {
        let s = clipboard.size
        clipboard.draw(in: NSRect(x: body.midX - s.width / 2, y: body.midY - s.height / 2 + size * 0.01, width: s.width, height: s.height))
    }

    // Lock badge, bottom right.
    let badgeSize = size * 0.26
    let badge = NSRect(x: body.maxX - badgeSize * 0.92, y: body.minY - badgeSize * 0.08, width: badgeSize, height: badgeSize)
    NSColor.white.setFill()
    NSBezierPath(ovalIn: badge).fill()
    let lockConfig = NSImage.SymbolConfiguration(pointSize: badgeSize * 0.5, weight: .bold)
        .applying(NSImage.SymbolConfiguration(paletteColors: [NSColor(srgbRed: 0.27, green: 0.2, blue: 0.75, alpha: 1)]))
    if let lock = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: nil)?.withSymbolConfiguration(lockConfig) {
        let s = lock.size
        lock.draw(in: NSRect(x: badge.midX - s.width / 2, y: badge.midY - s.height / 2, width: s.width, height: s.height))
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        try render(pixels: points * scale).write(to: output.appending(path: name))
    }
}
