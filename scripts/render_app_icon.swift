// 开瓶器正式图标：酒红渐变圆角底 + 白色「开」字（最初版本设计）
// 用法: swift scripts/render_app_icon.swift → Resources/AppIcon-1024.png
import AppKit

let canvas = CGSize(width: 1024, height: 1024)

func render(size: CGSize, draw: (CGContext) -> Void) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw(NSGraphicsContext.current!.cgContext)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let png = render(size: canvas) { ctx in
    // 酒红渐变圆角背景
    let rect = CGRect(origin: .zero, size: canvas).insetBy(dx: 48, dy: 48)
    let path = CGPath(roundedRect: rect, cornerWidth: 200, cornerHeight: 200, transform: nil)
    let grad = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [
            NSColor(calibratedRed: 0.55, green: 0.10, blue: 0.18, alpha: 1).cgColor,
            NSColor(calibratedRed: 0.30, green: 0.03, blue: 0.08, alpha: 1).cgColor,
        ] as CFArray,
        locations: [0, 1])!
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    ctx.drawLinearGradient(grad, start: CGPoint(x: 512, y: 1024),
                           end: CGPoint(x: 512, y: 0), options: [])
    ctx.restoreGState()

    // 居中白色「开」字
    let attr: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 460, weight: .bold),
        .foregroundColor: NSColor.white,
    ]
    let str = NSAttributedString(string: "开", attributes: attr)
    let bounds = str.boundingRect(with: canvas, options: [])
    str.draw(at: CGPoint(x: (1024 - bounds.width) / 2, y: (1024 - bounds.height) / 2 - 40))
}

try! png.write(to: URL(fileURLWithPath: "Resources/AppIcon-1024.png"))
print("✅ 已恢复最初版图标：酒红渐变 + 白色「开」字")
