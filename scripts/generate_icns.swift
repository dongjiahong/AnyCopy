import AppKit
import CoreGraphics
import Foundation

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    drawBackground(size: size)
    drawPages(size: size)
    drawLinkIcon(size: size)
    image.unlockFocus()
    return image
}

func drawBackground(size: CGFloat) {
    let rect = NSRect(x: size * 0.1, y: size * 0.1, width: size * 0.8, height: size * 0.8)
    let path = NSBezierPath(roundedRect: rect, xRadius: size * 0.18, yRadius: size * 0.18)
    let gradient = NSGradient(starting: NSColor(deviceRed: 0.0, green: 0.78, blue: 1.0, alpha: 1.0), 
                              ending: NSColor(deviceRed: 0.0, green: 0.45, blue: 1.0, alpha: 1.0))
    gradient?.draw(in: path, angle: -45)
}

func drawPages(size: CGFloat) {
    let backRect = NSRect(x: size * 0.35, y: size * 0.35, width: size * 0.35, height: size * 0.4)
    let backPath = NSBezierPath(roundedRect: backRect, xRadius: size * 0.05, yRadius: size * 0.05)
    NSColor(white: 1.0, alpha: 0.4).set()
    backPath.fill()
    NSColor(white: 1.0, alpha: 0.3).set()
    backPath.lineWidth = size * 0.005
    backPath.stroke()
    
    let frontRect = NSRect(x: size * 0.3, y: size * 0.25, width: size * 0.35, height: size * 0.4)
    let frontPath = NSBezierPath(roundedRect: frontRect, xRadius: size * 0.05, yRadius: size * 0.05)
    NSColor.white.set()
    frontPath.fill()
    
    let linePath = NSBezierPath()
    linePath.lineWidth = size * 0.018
    linePath.lineCapStyle = .round
    NSColor(white: 0.9, alpha: 1.0).set()
    let lineYPositions: [CGFloat] = [0.55, 0.48, 0.41]
    for y in lineYPositions {
        linePath.move(to: NSPoint(x: size * 0.36, y: size * y))
        linePath.line(to: NSPoint(x: size * 0.58, y: size * y))
    }
    linePath.stroke()
}

func drawLinkIcon(size: CGFloat) {
    let linkColor = NSColor(deviceRed: 0.0, green: 0.45, blue: 1.0, alpha: 1.0)
    linkColor.set()
    
    let linkWidth = size * 0.06
    let linkHeight = size * 0.035
    let centerX = size * 0.56
    let centerY = size * 0.31
    
    func drawLinkHalf(at offset: NSPoint, rotation: CGFloat) {
        let path = NSBezierPath()
        let rect = NSRect(x: -linkWidth/2, y: -linkHeight/2, width: linkWidth, height: linkHeight)
        path.appendRoundedRect(rect, xRadius: linkHeight/2, yRadius: linkHeight/2)
        
        var transform = AffineTransform.identity
        transform.translate(x: centerX + offset.x, y: centerY + offset.y)
        transform.rotate(byDegrees: rotation)
        path.transform(using: transform)
        
        path.lineWidth = size * 0.015
        path.stroke()
    }
    
    drawLinkHalf(at: NSPoint(x: -linkWidth * 0.2, y: linkWidth * 0.2), rotation: 45)
    drawLinkHalf(at: NSPoint(x: linkWidth * 0.2, y: -linkWidth * 0.2), rotation: 45)
    
    let bridgePath = NSBezierPath()
    bridgePath.move(to: NSPoint(x: centerX - linkWidth * 0.1, y: centerY + linkWidth * 0.1))
    bridgePath.line(to: NSPoint(x: centerX + linkWidth * 0.1, y: centerY - linkWidth * 0.1))
    bridgePath.lineWidth = size * 0.015
    bridgePath.lineCapStyle = .round
    bridgePath.stroke()
}

func saveImage(_ image: NSImage, to url: URL) throws {
    guard let tiffData = image.tiffRepresentation,
          let bitmapImage = NSBitmapImageRep(data: tiffData),
          let pngData = bitmapImage.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "ImageError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create PNG data"])
    }
    try pngData.write(to: url)
}

let iconsetDir = URL(fileURLWithPath: "AnyCopy.iconset")
try? FileManager.default.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

let sizes = [16, 32, 128, 256, 512]
for s in sizes {
    try saveImage(drawIcon(size: CGFloat(s)), to: iconsetDir.appendingPathComponent("icon_\(s)x\(s).png"))
    try saveImage(drawIcon(size: CGFloat(s * 2)), to: iconsetDir.appendingPathComponent("icon_\(s)x\(s)@2x.png"))
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", "AnyCopy.iconset", "-o", "AnyCopy/Resources/AppIcon.icns"]
try process.run()
process.waitUntilExit()

print("AppIcon.icns generated successfully.")
