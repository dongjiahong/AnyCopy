import AppKit
import CoreGraphics

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    
    // 1. 绘制背景底座 (Squircle)
    let rect = NSRect(x: size * 0.1, y: size * 0.1, width: size * 0.8, height: size * 0.8)
    let path = NSBezierPath(roundedRect: rect, xRadius: size * 0.18, yRadius: size * 0.18)
    
    let gradient = NSGradient(starting: NSColor(deviceRed: 0.0, green: 0.78, blue: 1.0, alpha: 1.0), 
                              ending: NSColor(deviceRed: 0.0, green: 0.45, blue: 1.0, alpha: 1.0))
    gradient?.draw(in: path, angle: -45)
    
    // 2. 绘制后页 (磨砂质感)
    let backRect = NSRect(x: size * 0.35, y: size * 0.35, width: size * 0.35, height: size * 0.4)
    let backPath = NSBezierPath(roundedRect: backRect, xRadius: size * 0.05, yRadius: size * 0.05)
    NSColor(white: 1.0, alpha: 0.4).set()
    backPath.fill()
    NSColor(white: 1.0, alpha: 0.3).set()
    backPath.lineWidth = size * 0.005
    backPath.stroke()
    
    // 3. 绘制前页 (纯白)
    let frontRect = NSRect(x: size * 0.3, y: size * 0.25, width: size * 0.35, height: size * 0.4)
    let frontPath = NSBezierPath(roundedRect: frontRect, xRadius: size * 0.05, yRadius: size * 0.05)
    NSColor.white.set()
    frontPath.fill()
    
    // 4. 绘制线条示意
    let linePath = NSBezierPath()
    linePath.lineWidth = size * 0.02
    linePath.lineCapStyle = .round
    NSColor(white: 0.88, alpha: 1.0).set()
    
    let lineYPositions: [CGFloat] = [0.55, 0.48, 0.41]
    for y in lineYPositions {
        linePath.move(to: NSPoint(x: size * 0.36, y: size * y))
        linePath.line(to: NSPoint(x: size * (y == 0.41 ? 0.5 : 0.58), y: size * y))
    }
    linePath.stroke()
    
    // 5. 绘制链接图标 (右下角)
    NSColor(deviceRed: 0.0, green: 0.45, blue: 1.0, alpha: 1.0).set()
    let linkRect = NSRect(x: size * 0.53, y: size * 0.28, width: size * 0.08, height: size * 0.08)
    let linkPath = NSBezierPath(ovalIn: linkRect)
    linkPath.lineWidth = size * 0.015
    linkPath.stroke()
    
    image.unlockFocus()
    return image
}

func saveImage(_ image: NSImage, to url: URL) {
    guard let tiffData = image.tiffRepresentation,
          let bitmapImage = NSBitmapImageRep(data: tiffData),
          let pngData = bitmapImage.representation(using: .png, properties: [:]) else { return }
    try? pngData.write(to: url)
}

let sizes = [16, 32, 128, 256, 512]
let outputDir = URL(fileURLWithPath: "AnyCopy/Resources/Assets.xcassets/AppIcon.appiconset")

for s in sizes {
    let img = drawIcon(size: CGFloat(s))
    if s == 16 {
        saveImage(img, to: outputDir.appendingPathComponent("icon_16x16.png"))
        let img2x = drawIcon(size: 32)
        saveImage(img2x, to: outputDir.appendingPathComponent("icon_16x16@2x.png"))
    } else if s == 32 {
        saveImage(img, to: outputDir.appendingPathComponent("icon_32x32.png"))
        let img2x = drawIcon(size: 64)
        saveImage(img2x, to: outputDir.appendingPathComponent("icon_32x32@2x.png"))
    } else if s == 128 {
        saveImage(img, to: outputDir.appendingPathComponent("icon_128x128.png"))
        let img2x = drawIcon(size: 256)
        saveImage(img2x, to: outputDir.appendingPathComponent("icon_128x128@2x.png"))
    } else if s == 256 {
        saveImage(img, to: outputDir.appendingPathComponent("icon_256x256.png"))
        let img2x = drawIcon(size: 512)
        saveImage(img2x, to: outputDir.appendingPathComponent("icon_256x256@2x.png"))
    } else if s == 512 {
        saveImage(img, to: outputDir.appendingPathComponent("icon_512x512.png"))
        let img2x = drawIcon(size: 1024)
        saveImage(img2x, to: outputDir.appendingPathComponent("icon_512x512@2x.png"))
    }
}
print("Icons generated successfully.")
