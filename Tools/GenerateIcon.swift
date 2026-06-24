import AppKit
import Foundation

let root = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? FileManager.default.currentDirectoryPath)
let resources = root.appendingPathComponent("Resources", isDirectory: true)
let iconset = resources.appendingPathComponent("CodexHub.iconset", isDirectory: true)
try? FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func makeImage(size: CGFloat, menuBar: Bool = false) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    defer { image.unlockFocus() }

    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: size, height: size).fill()

    if menuBar {
        NSColor.black.setFill()
        let font = NSFont.monospacedSystemFont(ofSize: size * 0.68, weight: .semibold)
        let text = NSAttributedString(string: "C", attributes: [.font: font, .foregroundColor: NSColor.black])
        let textSize = text.size()
        text.draw(at: NSPoint(x: (size - textSize.width) / 2, y: (size - textSize.height) / 2))
        return image
    }

    let outer = NSRect(x: size * 0.07, y: size * 0.07, width: size * 0.86, height: size * 0.86)
    let radius = size * 0.22
    let outerPath = NSBezierPath(roundedRect: outer, xRadius: radius, yRadius: radius)

    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.24)
    shadow.shadowBlurRadius = size * 0.055
    shadow.shadowOffset = NSSize(width: 0, height: -size * 0.025)
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    NSColor.black.withAlphaComponent(0.16).setFill()
    outerPath.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    outerPath.addClip()

    let background = NSGradient(colors: [
        NSColor(red: 0.07, green: 0.09, blue: 0.12, alpha: 1),
        NSColor(red: 0.09, green: 0.13, blue: 0.18, alpha: 1),
        NSColor(red: 0.03, green: 0.18, blue: 0.20, alpha: 1)
    ])
    background?.draw(in: outer, angle: -36)

    let glow = NSGradient(colors: [
        NSColor(red: 0.23, green: 0.86, blue: 0.43, alpha: 0.78),
        NSColor(red: 0.12, green: 0.52, blue: 0.95, alpha: 0.72)
    ])
    glow?.draw(in: NSRect(x: size * 0.12, y: size * 0.11, width: size * 0.76, height: size * 0.30), angle: 0)

    NSColor.white.withAlphaComponent(0.07).setFill()
    NSBezierPath(ovalIn: NSRect(x: size * 0.02, y: size * 0.55, width: size * 0.86, height: size * 0.50)).fill()

    let backCard = NSRect(x: size * 0.48, y: size * 0.34, width: size * 0.25, height: size * 0.36)
    NSColor(red: 0.16, green: 0.20, blue: 0.27, alpha: 0.95).setFill()
    NSBezierPath(roundedRect: backCard, xRadius: size * 0.055, yRadius: size * 0.055).fill()

    let frontCard = NSRect(x: size * 0.27, y: size * 0.28, width: size * 0.31, height: size * 0.44)
    let cardGradient = NSGradient(colors: [
        NSColor(red: 0.20, green: 0.82, blue: 0.38, alpha: 1),
        NSColor(red: 0.09, green: 0.59, blue: 0.85, alpha: 1)
    ])
    cardGradient?.draw(in: NSBezierPath(roundedRect: frontCard, xRadius: size * 0.07, yRadius: size * 0.07), angle: -28)

    let font = NSFont.monospacedSystemFont(ofSize: size * 0.29, weight: .heavy)
    let c = NSAttributedString(string: "C", attributes: [.font: font, .foregroundColor: NSColor.white])
    let cSize = c.size()
    c.draw(at: NSPoint(x: frontCard.midX - cSize.width / 2, y: frontCard.midY - cSize.height / 2 - size * 0.01))

    NSColor.white.withAlphaComponent(0.92).setFill()
    let barWidth = size * 0.045
    let gap = size * 0.025
    let baseX = size * 0.63
    let baseY = size * 0.30
    let heights = [size * 0.16, size * 0.25, size * 0.35]
    for index in 0..<3 {
        let rect = NSRect(x: baseX + CGFloat(index) * (barWidth + gap), y: baseY, width: barWidth, height: heights[index])
        NSBezierPath(roundedRect: rect, xRadius: barWidth * 0.48, yRadius: barWidth * 0.48).fill()
    }

    NSGraphicsContext.restoreGraphicsState()

    NSColor.white.withAlphaComponent(0.16).setStroke()
    outerPath.lineWidth = max(1, size * 0.012)
    outerPath.stroke()
    return image
}

func writePNG(_ image: NSImage, to url: URL) throws {
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let data = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "CodexHubIcon", code: 1)
    }
    try data.write(to: url)
}

let iconSizes: [(String, CGFloat)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for (name, size) in iconSizes {
    try writePNG(makeImage(size: size), to: iconset.appendingPathComponent(name))
}

try writePNG(makeImage(size: 128), to: resources.appendingPathComponent("CodexHubIcon.png"))
try writePNG(makeImage(size: 18, menuBar: true), to: resources.appendingPathComponent("CodexHubMenuIcon.png"))

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", resources.appendingPathComponent("CodexHub.icns").path]
try process.run()
process.waitUntilExit()
if process.terminationStatus != 0 {
    throw NSError(domain: "CodexHubIcon", code: Int(process.terminationStatus))
}
