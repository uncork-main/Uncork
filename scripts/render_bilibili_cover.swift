// B 站视频封面生成器：1146×717（16:9），酒红渐变 + 主题文案
// 用法: swift scripts/render_bilibili_cover.swift → build/bilibili-cover.png
import AppKit

let canvas = CGSize(width: 1146, height: 717)

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
    // 背景渐变（品牌酒红）
    let grad = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [
            NSColor(calibratedRed: 0.55, green: 0.10, blue: 0.18, alpha: 1).cgColor,
            NSColor(calibratedRed: 0.30, green: 0.03, blue: 0.08, alpha: 1).cgColor,
        ] as CFArray,
        locations: [0, 1])!
    ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: 717),
                           end: CGPoint(x: 0, y: 0), options: [])

    // 左上角 Logo 区：圆角方块 + 「开」
    let logoRect = CGRect(x: 60, y: 717 - 60 - 150, width: 150, height: 150)
    let logoPath = CGPath(roundedRect: logoRect, cornerWidth: 30, cornerHeight: 30, transform: nil)
    ctx.saveGState()
    ctx.addPath(logoPath)
    ctx.setFillColor(NSColor.white.withAlphaComponent(0.16).cgColor)
    ctx.fillPath()
    ctx.restoreGState()
    let logoAttr: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 96, weight: .bold),
        .foregroundColor: NSColor.white,
    ]
    let logoStr = NSAttributedString(string: "开", attributes: logoAttr)
    let lb = logoStr.boundingRect(with: canvas, options: [])
    logoStr.draw(at: CGPoint(x: logoRect.midX - lb.width/2,
                             y: logoRect.midY - lb.height/2))

    // 主标题
    let titleAttr: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 84, weight: .heavy),
        .foregroundColor: NSColor.white,
    ]
    let title = NSAttributedString(string: "在 Mac 上玩 Windows 游戏", attributes: titleAttr)
    let tb = title.boundingRect(with: canvas, options: [])
    title.draw(at: CGPoint(x: (1146 - tb.width) / 2, y: 420))

    // 副标题
    let subAttr: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 40, weight: .medium),
        .foregroundColor: NSColor.white.withAlphaComponent(0.92),
    ]
    let sub = NSAttributedString(string: "开瓶器 Uncork · 免费开源 · 类 CrossOver", attributes: subAttr)
    let sb = sub.boundingRect(with: canvas, options: [])
    sub.draw(at: CGPoint(x: (1146 - sb.width) / 2, y: 280))

    // 底部小字
    let footAttr: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 26, weight: .regular),
        .foregroundColor: NSColor.white.withAlphaComponent(0.75),
    ]
    let foot = NSAttributedString(string: "GitHub 开源 · 下载链接见简介", attributes: footAttr)
    let fb = foot.boundingRect(with: canvas, options: [])
    foot.draw(at: CGPoint(x: (1146 - fb.width) / 2, y: 70))
}

try? FileManager.default.createDirectory(atPath: "build", withIntermediateDirectories: true)
try! png.write(to: URL(fileURLWithPath: "build/bilibili-cover.png"))
print("✅ 生成 build/bilibili-cover.png（1146×717）")
