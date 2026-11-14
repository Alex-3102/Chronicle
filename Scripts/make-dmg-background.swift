import AppKit
import Foundation

// 生成 DMG 安装窗口的背景图（含安装指引）
// 用法: swift make-dmg-background.swift <版本号> <输出png> [图标路径]

let args = CommandLine.arguments
let version = args.count > 1 ? args[1] : "1.0"
let output = args.count > 2 ? args[2] : "background.png"
let iconPath = args.count > 3 ? args[3] : ""

let width: CGFloat = 704
let height: CGFloat = 440

let image = NSImage(size: NSSize(width: width, height: height))
image.lockFocus()
guard let ctx = NSGraphicsContext.current?.cgContext else {
    print("no context")
    exit(1)
}
let space = CGColorSpaceCreateDeviceRGB()

// 背景：深色渐变
let bgColors = [
    NSColor(srgbRed: 0.106, green: 0.114, blue: 0.133, alpha: 1).cgColor,
    NSColor(srgbRed: 0.059, green: 0.063, blue: 0.075, alpha: 1).cgColor
] as CFArray
if let gradient = CGGradient(colorsSpace: space, colors: bgColors, locations: [0, 1]) {
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: 0, y: height),
        end: CGPoint(x: 0, y: 0),
        options: []
    )
}

// 顶部暖色光晕
let glowColors = [
    NSColor(srgbRed: 0.949, green: 0.6, blue: 0.29, alpha: 0.16).cgColor,
    NSColor(srgbRed: 0.949, green: 0.6, blue: 0.29, alpha: 0).cgColor
] as CFArray
if let glow = CGGradient(colorsSpace: space, colors: glowColors, locations: [0, 1]) {
    ctx.drawRadialGradient(
        glow,
        startCenter: CGPoint(x: width / 2, y: height + 40),
        startRadius: 0,
        endCenter: CGPoint(x: width / 2, y: height + 40),
        endRadius: 320,
        options: []
    )
}

func drawText(
    _ text: String,
    rect: NSRect,
    font: NSFont,
    color: NSColor,
    alignment: NSTextAlignment = .center,
    lineSpacing: CGFloat = 0
) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = alignment
    paragraph.lineSpacing = lineSpacing
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: color,
        .paragraphStyle: paragraph
    ]
    (text as NSString).draw(in: rect, withAttributes: attributes)
}

// 图标 + 标题 + 口号
if !iconPath.isEmpty, let icon = NSImage(contentsOfFile: iconPath) {
    icon.draw(in: NSRect(x: width / 2 - 30, y: height - 80, width: 60, height: 60),
              from: .zero, operation: .sourceOver, fraction: 1)
}

drawText(
    "Chronicle \(version)",
    rect: NSRect(x: 0, y: height - 110, width: width, height: 26),
    font: .systemFont(ofSize: 15, weight: .semibold),
    color: NSColor(white: 0.95, alpha: 1)
)

drawText(
    "让每一段时间，都清晰可见",
    rect: NSRect(x: 0, y: height - 134, width: width, height: 20),
    font: .systemFont(ofSize: 12.5),
    color: NSColor(white: 0.6, alpha: 1)
)

drawText(
    "把 Chronicle 拖到「应用程序」文件夹",
    rect: NSRect(x: 0, y: 268, width: width, height: 26),
    font: .systemFont(ofSize: 15, weight: .medium),
    color: NSColor(white: 0.93, alpha: 1)
)

// 拖拽箭头
let arrowColor = NSColor(srgbRed: 0.949, green: 0.6, blue: 0.29, alpha: 0.9)
ctx.setStrokeColor(arrowColor.cgColor)
ctx.setLineWidth(5)
ctx.setLineCap(.round)
ctx.move(to: CGPoint(x: 300, y: 214))
ctx.addCurve(to: CGPoint(x: 404, y: 214),
             control1: CGPoint(x: 336, y: 240),
             control2: CGPoint(x: 368, y: 240))
ctx.strokePath()

// 箭头头部
ctx.setFillColor(arrowColor.cgColor)
let head = CGMutablePath()
head.move(to: CGPoint(x: 412, y: 214))
head.addLine(to: CGPoint(x: 392, y: 224))
head.addLine(to: CGPoint(x: 392, y: 204))
head.closeSubpath()
ctx.addPath(head)
ctx.fillPath()

// 底部说明
drawText(
    "首次打开若提示「无法验证开发者」，请到 系统设置 › 隐私与安全性 点击「仍要打开」。",
    rect: NSRect(x: 40, y: 92, width: width - 80, height: 40),
    font: .systemFont(ofSize: 11.5),
    color: NSColor(white: 0.62, alpha: 1)
)
drawText(
    "你的时间记录保存在本机，更新版本不会影响已有数据。",
    rect: NSRect(x: 40, y: 68, width: width - 80, height: 20),
    font: .systemFont(ofSize: 11),
    color: NSColor(white: 0.45, alpha: 1)
)

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let data = rep.representation(using: .png, properties: [:]) else {
    print("render failed")
    exit(1)
}
try! data.write(to: URL(fileURLWithPath: output))
print("background written: \(output)")
