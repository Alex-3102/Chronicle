import AppKit
import Foundation

// Chronicle 应用图标：深色圆角底 + 橙色时钟弧（C）+ 白色指针
let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.icns"
let canvas: CGFloat = 1024
let contentInset: CGFloat = 100

func makeIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else { return image }
    let scale = size / canvas
    ctx.scaleBy(x: scale, y: scale)
    ctx.setShouldAntialias(true)

    let rect = CGRect(x: contentInset, y: contentInset,
                      width: canvas - contentInset * 2,
                      height: canvas - contentInset * 2)
    let shape = CGPath(roundedRect: rect, cornerWidth: 186, cornerHeight: 186, transform: nil)

    // 背景
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()

    let space = CGColorSpaceCreateDeviceRGB()
    let bgColors = [
        NSColor(srgbRed: 0.145, green: 0.157, blue: 0.184, alpha: 1).cgColor,
        NSColor(srgbRed: 0.063, green: 0.067, blue: 0.078, alpha: 1).cgColor
    ] as CFArray
    if let gradient = CGGradient(colorsSpace: space, colors: bgColors, locations: [0, 1]) {
        ctx.drawLinearGradient(
            gradient,
            start: CGPoint(x: rect.minX, y: rect.maxY),
            end: CGPoint(x: rect.maxX, y: rect.minY),
            options: []
        )
    }

    // 左上暖色光晕
    let glowColors = [
        NSColor(srgbRed: 0.949, green: 0.6, blue: 0.29, alpha: 0.30).cgColor,
        NSColor(srgbRed: 0.949, green: 0.6, blue: 0.29, alpha: 0.0).cgColor
    ] as CFArray
    if let glow = CGGradient(colorsSpace: space, colors: glowColors, locations: [0, 1]) {
        ctx.drawRadialGradient(
            glow,
            startCenter: CGPoint(x: rect.minX + 210, y: rect.maxY - 170),
            startRadius: 0,
            endCenter: CGPoint(x: rect.minX + 210, y: rect.maxY - 170),
            endRadius: 470,
            options: []
        )
    }
    ctx.restoreGState()

    // 内描边高光
    ctx.addPath(shape)
    ctx.setStrokeColor(NSColor(white: 1, alpha: 0.10).cgColor)
    ctx.setLineWidth(6)
    ctx.strokePath()

    // 时钟弧（C 形缺口朝右）
    let center = CGPoint(x: canvas / 2, y: canvas / 2)
    let radius: CGFloat = 236
    let arc = CGMutablePath()
    arc.addArc(center: center, radius: radius,
               startAngle: 55 * .pi / 180,
               endAngle: 305 * .pi / 180,
               clockwise: false)

    ctx.saveGState()
    ctx.addPath(arc)
    ctx.setLineWidth(58)
    ctx.setLineCap(.round)
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    let arcColors = [
        NSColor(srgbRed: 0.949, green: 0.6, blue: 0.29, alpha: 1).cgColor,
        NSColor(srgbRed: 0.949, green: 0.788, blue: 0.29, alpha: 1).cgColor,
        NSColor(srgbRed: 0.55, green: 0.36, blue: 0.95, alpha: 1).cgColor
    ] as CFArray
    if let gradient = CGGradient(colorsSpace: space, colors: arcColors, locations: [0, 0.62, 1]) {
        ctx.drawLinearGradient(
            gradient,
            start: CGPoint(x: center.x - radius, y: center.y - radius),
            end: CGPoint(x: center.x + radius, y: center.y + radius),
            options: []
        )
    }
    ctx.restoreGState()

    // 指针
    ctx.setLineCap(.round)
    ctx.setStrokeColor(NSColor(white: 1, alpha: 0.94).cgColor)
    ctx.setLineWidth(30)
    ctx.move(to: center)
    ctx.addLine(to: CGPoint(x: center.x, y: center.y + 148))
    ctx.move(to: center)
    ctx.addLine(to: CGPoint(x: center.x + 104, y: center.y - 74))
    ctx.strokePath()

    // 圆心
    ctx.setFillColor(NSColor(white: 1, alpha: 0.96).cgColor)
    ctx.fillEllipse(in: CGRect(x: center.x - 20, y: center.y - 20, width: 40, height: 40))

    // 弧缺口处的小圆点（时间记录标记）
    let dotAngle = 0.0
    let dotCenter = CGPoint(
        x: center.x + CGFloat(cos(dotAngle)) * radius,
        y: center.y + CGFloat(sin(dotAngle)) * radius
    )
    ctx.setFillColor(NSColor(srgbRed: 0.494, green: 0.827, blue: 0.129, alpha: 1).cgColor)
    ctx.fillEllipse(in: CGRect(x: dotCenter.x - 29, y: dotCenter.y - 29, width: 58, height: 58))

    image.unlockFocus()
    return image
}

func pngData(_ image: NSImage, pixelSize: CGFloat) -> Data? {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(pixelSize),
        pixelsHigh: Int(pixelSize),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { return nil }
    rep.size = NSSize(width: pixelSize, height: pixelSize)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(
        in: NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize),
        from: .zero,
        operation: .copy,
        fraction: 1
    )
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

let base = makeIcon(size: canvas)
let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Chronicle.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

let variants: [(String, CGFloat)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024)
]
for (name, pixels) in variants {
    guard let data = pngData(base, pixelSize: pixels) else { continue }
    try! data.write(to: iconset.appendingPathComponent("\(name).png"))
}

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", outputPath]
try! task.run()
task.waitUntilExit()
print("icon written: \(outputPath) exit=\(task.terminationStatus)")
