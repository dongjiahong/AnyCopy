import Cocoa

// 简单的命令行参数获取
guard CommandLine.arguments.count == 3 else {
    print("Usage: mask_icon <input_path> <output_path>")
    exit(1)
}

let inputPath = CommandLine.arguments[1]
let outputPath = CommandLine.arguments[2]

guard let inputImage = NSImage(contentsOfFile: inputPath) else {
    print("Error: Could not load image at \(inputPath)")
    exit(1)
}

// 目标尺寸（假设我们处理的是最大的 1024x1024，或者基于原图尺寸）
let size = inputImage.size
let rect = NSRect(origin: .zero, size: size)

// 创建输出图像
let outputImage = NSImage(size: size)
outputImage.lockFocus()

// 创建上下文
guard let context = NSGraphicsContext.current?.cgContext else {
    print("Error: Could not get graphics context")
    exit(1)
}

// 绘制圆角矩形 Mask
// macOS Big Sur 风格图标圆角大概是尺寸的 22.5%
let cornerRadius = size.width * 0.225
let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
path.addClip()

// 绘制原图
inputImage.draw(in: rect, from: rect, operation: .sourceOver, fraction: 1.0)

outputImage.unlockFocus()

// 保存为 PNG
guard let tiffData = outputImage.tiffRepresentation,
      let bitmapImage = NSBitmapImageRep(data: tiffData),
      let pngData = bitmapImage.representation(using: .png, properties: [:]) else {
    print("Error: Could not convert to PNG")
    exit(1)
}

do {
    try pngData.write(to: URL(fileURLWithPath: outputPath))
    print("Successfully processed icon to \(outputPath)")
} catch {
    print("Error: Could not write file: \(error)")
    exit(1)
}
