import AppKit
import Foundation

let root = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? FileManager.default.currentDirectoryPath)
let resources = root.appendingPathComponent("Resources", isDirectory: true)
let iconset = resources.appendingPathComponent("CodexHub.iconset", isDirectory: true)
let sourceURL = resources.appendingPathComponent("CodexHubIconSource.png")

try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

guard let sourceImage = NSImage(contentsOf: sourceURL) else {
    throw NSError(domain: "CodexHubIcon", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing Resources/CodexHubIconSource.png"])
}

func resized(_ image: NSImage, size: CGFloat) -> NSImage {
    let pixelSize = Int(size)
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        return image
    }
    bitmap.size = NSSize(width: size, height: size)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSGraphicsContext.current?.imageInterpolation = .high
    image.draw(in: NSRect(x: 0, y: 0, width: size, height: size), from: .zero, operation: .copy, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()

    let output = NSImage(size: NSSize(width: size, height: size))
    output.addRepresentation(bitmap)
    return output
}

func pngData(from image: NSImage) throws -> Data {
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let data = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "CodexHubIcon", code: 2)
    }
    return data
}

func writePNG(_ image: NSImage, to url: URL) throws {
    try pngData(from: image).write(to: url)
}

func inverted(_ image: NSImage) throws -> NSImage {
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let cgImage = bitmap.cgImage else {
        throw NSError(domain: "CodexHubIcon", code: 3)
    }

    let width = cgImage.width
    let height = cgImage.height
    let bytesPerPixel = 4
    let bytesPerRow = width * bytesPerPixel
    var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)

    guard let context = CGContext(
        data: &pixels,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw NSError(domain: "CodexHubIcon", code: 4)
    }

    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
    for index in stride(from: 0, to: pixels.count, by: bytesPerPixel) {
        pixels[index] = 255 - pixels[index]
        pixels[index + 1] = 255 - pixels[index + 1]
        pixels[index + 2] = 255 - pixels[index + 2]
    }

    guard let invertedCG = context.makeImage() else {
        throw NSError(domain: "CodexHubIcon", code: 5)
    }
    return NSImage(cgImage: invertedCG, size: image.size)
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
    try writePNG(resized(sourceImage, size: size), to: iconset.appendingPathComponent(name))
}

let lightIcon = resized(sourceImage, size: 256)
let darkIcon = try inverted(lightIcon)
try writePNG(lightIcon, to: resources.appendingPathComponent("CodexHubIcon.png"))
try writePNG(lightIcon, to: resources.appendingPathComponent("CodexHubIconLight.png"))
try writePNG(darkIcon, to: resources.appendingPathComponent("CodexHubIconDark.png"))

let menuIcon = resized(sourceImage, size: 36)
try writePNG(menuIcon, to: resources.appendingPathComponent("CodexHubMenuIcon.png"))

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", resources.appendingPathComponent("CodexHub.icns").path]
try process.run()
process.waitUntilExit()
if process.terminationStatus != 0 {
    throw NSError(domain: "CodexHubIcon", code: Int(process.terminationStatus))
}
