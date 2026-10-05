// Rebuild the local, vector-drawn macOS asset catalog: swift scripts/make-app-icon.swift [output.appiconset]
import AppKit

let directory = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    : URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Resources/Assets.xcassets/AppIcon.appiconset", isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

func render(pixels: Int, to destination: URL) throws {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                 isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    let scale = CGFloat(pixels) / 1024
    context.cgContext.scaleBy(x: scale, y: scale)

    // Transparent margins follow the macOS app-icon silhouette.
    let tile = NSBezierPath(roundedRect: NSRect(x: 96, y: 96, width: 832, height: 832), xRadius: 184, yRadius: 184)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.24)
    shadow.shadowBlurRadius = 24
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.set()
    NSColor(calibratedRed: 0.29, green: 0.25, blue: 0.87, alpha: 1).setFill()
    tile.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(colors: [NSColor(calibratedRed: 0.23, green: 0.20, blue: 0.75, alpha: 1),
                        NSColor(calibratedRed: 0.39, green: 0.36, blue: 0.96, alpha: 1),
                        NSColor(calibratedRed: 0.24, green: 0.61, blue: 0.98, alpha: 1)])!
        .draw(in: tile, angle: 55)

    // A speech bubble with a waveform: narration at a glance, legible at 16 px.
    let bubble = NSBezierPath(roundedRect: NSRect(x: 236, y: 330, width: 552, height: 428), xRadius: 110, yRadius: 110)
    let tail = NSBezierPath()
    tail.move(to: NSPoint(x: 316, y: 375))
    tail.line(to: NSPoint(x: 316, y: 240))
    tail.curve(to: NSPoint(x: 333, y: 233), controlPoint1: NSPoint(x: 316, y: 230), controlPoint2: NSPoint(x: 324, y: 226))
    tail.line(to: NSPoint(x: 470, y: 351))
    tail.close()
    NSColor.white.setFill()
    bubble.fill()
    tail.fill()
    let heights: [CGFloat] = [94, 168, 256, 184, 112]
    NSColor(calibratedRed: 0.34, green: 0.32, blue: 0.86, alpha: 1).setFill()
    for (index, height) in heights.enumerated() {
        NSBezierPath(roundedRect: NSRect(x: 338 + CGFloat(index) * 76, y: 544 - height / 2,
                                        width: 44, height: height), xRadius: 22, yRadius: 22).fill()
    }
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: destination)
}

for points in [16, 32, 128, 256, 512] {
    try render(pixels: points, to: directory.appendingPathComponent("icon_\(points)x\(points).png"))
    try render(pixels: points * 2, to: directory.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}

let images = [16, 32, 128, 256, 512].flatMap { points in
    [1, 2].map { scale in
        ["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x",
         "filename": "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"]
    }
}
let manifest: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
    .write(to: directory.appendingPathComponent("Contents.json"))
