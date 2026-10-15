#!/usr/bin/env swift
// Renders the LocalFlow app icon (waveform on a gradient squircle) into an
// .iconset directory. Usage: make-icon.swift <output.iconset>
import AppKit

let sizes: [(name: String, px: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

func render(px: Int) -> Data? {
    let size = CGFloat(px)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // macOS icon grid: artwork fills ~80% of the canvas.
    let inset = size * 0.1
    let body = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let squircle = NSBezierPath(roundedRect: body, xRadius: body.width * 0.225, yRadius: body.width * 0.225)

    NSGraphicsContext.current?.cgContext.setShadow(
        offset: CGSize(width: 0, height: -size * 0.012), blur: size * 0.03,
        color: NSColor.black.withAlphaComponent(0.3).cgColor)
    NSColor.black.setFill()
    squircle.fill()
    NSGraphicsContext.current?.cgContext.setShadow(offset: .zero, blur: 0, color: nil)

    NSGradient(colors: [
        NSColor(red: 0.36, green: 0.30, blue: 0.95, alpha: 1),
        NSColor(red: 0.10, green: 0.62, blue: 0.95, alpha: 1),
    ])?.draw(in: squircle, angle: -60)

    // Waveform bars, tallest in the middle.
    let heights: [CGFloat] = [0.20, 0.38, 0.62, 0.38, 0.20].map { $0 * 1.0 }
    let barWidth = body.width * 0.075
    let gap = body.width * 0.062
    let total = CGFloat(heights.count) * barWidth + CGFloat(heights.count - 1) * gap
    var x = body.midX - total / 2
    NSColor.white.setFill()
    for h in heights {
        let barHeight = body.height * h
        let bar = NSRect(x: x, y: body.midY - barHeight / 2, width: barWidth, height: barHeight)
        NSBezierPath(roundedRect: bar, xRadius: barWidth / 2, yRadius: barWidth / 2).fill()
        x += barWidth + gap
    }
    return rep.representation(using: .png, properties: [:])
}

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: make-icon.swift <output.iconset>\n".utf8))
    exit(2)
}
let outDir = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
for (name, px) in sizes {
    guard let png = render(px: px) else {
        FileHandle.standardError.write(Data("failed to render \(name)\n".utf8))
        exit(1)
    }
    try png.write(to: outDir.appendingPathComponent("\(name).png"))
}
