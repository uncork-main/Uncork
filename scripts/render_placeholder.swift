// 占位图标 / DMG 背景图生成器（CoreGraphics，无需 Xcode）
// 用法: swift scripts/render_placeholder.swift icon    → Resources/AppIcon-1024.png
//       swift scripts/render_placeholder.swift dmg-bg  → Resources/dmg-background.png
import AppKit

let mode = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon"

/// 以固定像素尺寸创建位图并绘图（不依赖屏幕 Retina 缩放，保证输出尺寸精确）
func render(size: CGSize, draw: (CGContext) -> Void) -> Data {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(size.width),
        pixelsHigh: Int(size.height),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        fputs("错误：创建位图失败\n", stderr)
        exit(1)
    }
    rep.size = size // 1 点 = 1 像素

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    guard let ctx = NSGraphicsContext.current?.cgContext else {
        fputs("错误：获取绘图上下文失败\n", stderr)
        exit(1)
    }
    draw(ctx)
    NSGraphicsContext.restoreGraphicsState()

    guard let png = rep.representation(using: .png, properties: [:]) else {
        fputs("错误：PNG 编码失败\n", stderr)
        exit(1)
    }
    return png
}

func drawGradient(_ ctx: CGContext, size: CGSize, inset: CGFloat) {
    let rect = CGRect(origin: .zero, size: size).insetBy(dx: inset, dy: inset)
    let path = CGPath(roundedRect: rect, cornerWidth: 200, cornerHeight: 200, transform: nil)
    let colors = [
        NSColor(calibratedRed: 0.55, green: 0.10, blue: 0.18, alpha: 1).cgColor,
        NSColor(calibratedRed: 0.30, green: 0.03, blue: 0.08, alpha: 1).cgColor,
    ] as CFArray
    let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    ctx.drawLinearGradient(grad, start: CGPoint(x: size.width / 2, y: size.height),
                           end: CGPoint(x: size.width / 2, y: 0), options: [])
    ctx.restoreGState()
}

func drawText(_ text: String, fontSize: CGFloat, size: CGSize, yOffset: CGFloat = 0, alpha: CGFloat = 1) {
    let attr: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: fontSize, weight: .bold),
        .foregroundColor: NSColor.white.withAlphaComponent(alpha),
    ]
    let str = NSAttributedString(string: text, attributes: attr)
    let bounds = str.boundingRect(with: size, options: [])
    str.draw(at: CGPoint(x: (size.width - bounds.width) / 2,
                         y: (size.height - bounds.height) / 2 + yOffset))
}

if mode == "icon" {
    let size = CGSize(width: 1024, height: 1024)
    let png = render(size: size) { ctx in
        drawGradient(ctx, size: size, inset: 48)
    }
    try! png.write(to: URL(fileURLWithPath: "Resources/AppIcon-1024.png"))
    print("生成 Resources/AppIcon-1024.png")

} else if mode == "dmg-bg" {
    let size = CGSize(width: 640, height: 400)
    let png = render(size: size) { ctx in
        drawGradient(ctx, size: size, inset: 0)
    }
    try! png.write(to: URL(fileURLWithPath: "Resources/dmg-background.png"))
    print("生成 Resources/dmg-background.png")

} else {
    print("用法: swift render_placeholder.swift [icon|dmg-bg]")
    exit(2)
}
