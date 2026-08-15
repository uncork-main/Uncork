// 开瓶器图标候选生成器：酒红渐变底 + 倒啤酒的瓶子，6 个变体
// 用法: swift scripts/render_icon_variants.swift → build/icon-candidates/icon-v1..v6.png
import AppKit

let outDir = "build/icon-candidates"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

let canvas = CGSize(width: 1024, height: 1024)

// MARK: - 画布与工具

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

func drawBackground(_ ctx: CGContext, inset: CGFloat, top: NSColor, bottom: NSColor) {
    let rect = CGRect(origin: .zero, size: canvas).insetBy(dx: inset, dy: inset)
    let path = CGPath(roundedRect: rect, cornerWidth: 200, cornerHeight: 200, transform: nil)
    let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: [top.cgColor, bottom.cgColor] as CFArray,
                          locations: [0, 1])!
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    ctx.drawLinearGradient(grad, start: CGPoint(x: canvas.width/2, y: canvas.height),
                           end: CGPoint(x: canvas.width/2, y: 0), options: [])
    ctx.restoreGState()
}

func drawChar(_ ctx: CGContext, _ char: String, fontSize: CGFloat, alpha: CGFloat,
              center: CGPoint) {
    let attr: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: fontSize, weight: .heavy),
        .foregroundColor: NSColor.white.withAlphaComponent(alpha),
    ]
    let str = NSAttributedString(string: char, attributes: attr)
    let bounds = str.boundingRect(with: canvas, options: [])
    str.draw(at: CGPoint(x: center.x - bounds.width/2, y: center.y - bounds.height/2))
}

// MARK: - 酒瓶（竖直，原点在瓶身底部中心）

/// 在局部坐标画一个竖立的酒瓶。返回瓶口（倒酒点）在局部坐标的位置。
func drawBottle(_ ctx: CGContext, bodyW: CGFloat, bodyH: CGFloat, fill: NSColor, outline: NSColor) -> CGPoint {
    let halfW = bodyW / 2
    let shoulderH: CGFloat = 92
    let neckW: CGFloat = 66
    let neckH: CGFloat = 96
    let capH: CGFloat = 40
    let bodyTop = bodyH
    let neckTop = bodyTop + shoulderH + neckH

    // 瓶身轮廓
    let path = CGMutablePath()
    path.move(to: CGPoint(x: -halfW, y: 0))
    // 底部到瓶肩（圆角）
    path.addLine(to: CGPoint(x: -halfW, y: bodyTop - 26))
    path.addQuadCurve(to: CGPoint(x: -halfW + 12, y: bodyTop),
                      control: CGPoint(x: -halfW, y: bodyTop))
    path.addLine(to: CGPoint(x: halfW - 12, y: bodyTop))
    path.addQuadCurve(to: CGPoint(x: halfW, y: bodyTop - 26),
                      control: CGPoint(x: halfW, y: bodyTop))
    // 右肩 → 瓶颈
    path.addQuadCurve(to: CGPoint(x: neckW/2, y: bodyTop + shoulderH),
                      control: CGPoint(x: halfW, y: bodyTop + 26))
    path.addLine(to: CGPoint(x: neckW/2, y: neckTop))
    // 瓶口外翻 + 盖
    path.addLine(to: CGPoint(x: neckW/2 + 8, y: neckTop + capH))
    path.addLine(to: CGPoint(x: neckW/2 + 8, y: neckTop + capH + 26))
    path.addLine(to: CGPoint(x: -neckW/2 - 8, y: neckTop + capH + 26))
    path.addLine(to: CGPoint(x: -neckW/2 - 8, y: neckTop + capH))
    path.addLine(to: CGPoint(x: -neckW/2, y: neckTop))
    path.addLine(to: CGPoint(x: -neckW/2, y: bodyTop + shoulderH))
    path.addQuadCurve(to: CGPoint(x: -halfW, y: bodyTop),
                      control: CGPoint(x: -halfW, y: bodyTop + 26))
    path.closeSubpath()

    // 填充（瓶体玻璃色）
    ctx.saveGState()
    ctx.addPath(path)
    ctx.setFillColor(fill.cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    // 瓶中酒液（裁在瓶内、占瓶身下 65%）
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    let liquid = CGColor(red: 0.95, green: 0.66, blue: 0.20, alpha: 0.92)
    ctx.setFillColor(liquid)
    ctx.fill(CGRect(x: -halfW, y: -10, width: bodyW, height: bodyH * 0.68))
    // 酒液顶部气泡线
    ctx.setFillColor(NSColor.white.withAlphaComponent(0.75).cgColor)
    for i in 0..<7 {
        let bx = -halfW + 26 + CGFloat(i) * (bodyW - 52) / 6
        ctx.fillEllipse(in: CGRect(x: bx - 5, y: bodyH * 0.68 - 14, width: 10, height: 6))
    }
    ctx.restoreGState()

    // 标签
    let label = CGRect(x: -halfW + 22, y: bodyH * 0.34, width: bodyW - 44, height: bodyH * 0.30)
    let labelPath = CGPath(roundedRect: label, cornerWidth: 10, cornerHeight: 10, transform: nil)
    ctx.saveGState()
    ctx.addPath(labelPath)
    ctx.setFillColor(NSColor(white: 0.97, alpha: 0.96).cgColor)
    ctx.fillPath()
    // 标签上小字「開」
    let attr: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: bodyW * 0.30, weight: .bold),
        .foregroundColor: NSColor(calibratedRed: 0.55, green: 0.12, blue: 0.18, alpha: 1),
    ]
    let t = NSAttributedString(string: "開", attributes: attr)
    let tb = t.boundingRect(with: canvas, options: [])
    t.draw(at: CGPoint(x: label.midX - tb.width/2, y: label.midY - tb.height/2))
    ctx.restoreGState()

    // 高光
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    ctx.setFillColor(NSColor.white.withAlphaComponent(0.22).cgColor)
    ctx.fill(CGRect(x: -halfW + 14, y: 20, width: 22, height: bodyH - 60))
    ctx.restoreGState()

    // 轮廓
    ctx.setStrokeColor(outline.cgColor)
    ctx.setLineWidth(7)
    ctx.addPath(path)
    ctx.strokePath()

    // 瓶口中心（倒酒点）
    return CGPoint(x: 0, y: neckTop + capH + 14)
}

/// 画一杯啤酒（品脱杯），origin 在杯底中心
func drawGlass(_ ctx: CGContext, topW: CGFloat, bottomW: CGFloat, h: CGFloat) {
    let halfT = topW/2, halfB = bottomW/2
    let path = CGMutablePath()
    path.move(to: CGPoint(x: -halfT, y: h))
    path.addLine(to: CGPoint(x: -halfB, y: 0))
    path.addLine(to: CGPoint(x: halfB, y: 0))
    path.addLine(to: CGPoint(x: halfT, y: h))
    path.closeSubpath()

    // 玻璃
    ctx.saveGState()
    ctx.addPath(path)
    ctx.setFillColor(NSColor(white: 0.93, alpha: 0.30).cgColor)
    ctx.fillPath()
    ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.85).cgColor)
    ctx.setLineWidth(7)
    ctx.strokePath()
    ctx.restoreGState()

    // 酒液
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    let beer = CGColor(red: 0.97, green: 0.70, blue: 0.22, alpha: 0.95)
    ctx.setFillColor(beer)
    ctx.fill(CGRect(x: -halfT, y: 0, width: topW, height: h * 0.82))
    // 泡沫
    ctx.setFillColor(NSColor.white.withAlphaComponent(0.92).cgColor)
    for i in 0..<8 {
        let fx = -halfT + 22 + CGFloat(i) * (topW - 44) / 7
        let r: CGFloat = 15 + CGFloat((i * 7) % 5) * 3
        ctx.fillEllipse(in: CGRect(x: fx - r, y: h * 0.80 - r*0.5, width: r*2, height: r*1.5))
    }
    ctx.restoreGState()

    // 杯柄
    ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.85).cgColor)
    ctx.setLineWidth(13)
    ctx.strokeEllipse(in: CGRect(x: halfB - 8, y: h * 0.32, width: 72, height: h * 0.55))
}

/// 完整构图：倾斜的酒瓶向杯中倒酒
func drawPour(_ ctx: CGContext, bottleScale: CGFloat = 1.0, showGlass: Bool = true) {
    // 酒瓶：倾斜约 -38°，瓶口朝左下的杯口
    let tilt = -38.0 * .pi / 180
    let pivot = CGPoint(x: 300, y: 620)
    ctx.saveGState()
    ctx.translateBy(x: pivot.x, y: pivot.y)
    ctx.rotate(by: tilt)
    ctx.scaleBy(x: bottleScale, y: bottleScale)
    let mouth = drawBottle(ctx, bodyW: 168, bodyH: 330,
                           fill: NSColor(calibratedRed: 0.36, green: 0.55, blue: 0.28, alpha: 1),
                           outline: NSColor(calibratedRed: 0.16, green: 0.30, blue: 0.12, alpha: 1))
    ctx.restoreGState()

    // 瓶口在画布坐标中的位置
    let mouthInCanvas = CGPoint(
        x: pivot.x + mouth.x * cos(tilt) - mouth.y * sin(tilt) * 1,
        y: pivot.y + mouth.x * sin(tilt) + mouth.y * cos(tilt)
    )
    // 瓶口实际位于旋转后的坐标（由于旋转了 bottleScale 缩放）
    let scaled = CGPoint(x: mouth.x * bottleScale, y: mouth.y * bottleScale)
    let mouthX = pivot.x + scaled.x * cos(tilt) - scaled.y * sin(tilt)
    let mouthY = pivot.y + scaled.x * sin(tilt) + scaled.y * cos(tilt)

    if showGlass {
        let glassBottom = CGPoint(x: 640, y: 300)
        drawGlass(ctx, topW: 230, bottomW: 170, h: 330)

        // 酒杯上沿中心
        let glassTop = CGPoint(x: 640, y: 300 + 330)

        // 酒柱：从瓶口到杯口的贝塞尔曲线
        let stream = CGMutablePath()
        stream.move(to: CGPoint(x: mouthX, y: mouthY))
        stream.addCurve(to: glassTop,
                        control1: CGPoint(x: mouthX + 60, y: mouthY - 120),
                        control2: CGPoint(x: glassTop.x - 90, y: glassTop.y + 160))
        ctx.saveGState()
        ctx.setStrokeColor(CGColor(red: 0.98, green: 0.72, blue: 0.24, alpha: 0.95))
        ctx.setLineWidth(30)
        ctx.setLineCap(.round)
        ctx.addPath(stream)
        ctx.strokePath()
        // 酒柱高光
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.5).cgColor)
        ctx.setLineWidth(8)
        ctx.strokePath()
        ctx.restoreGState()

        // 溅出的酒滴
        ctx.setFillColor(CGColor(red: 0.98, green: 0.72, blue: 0.24, alpha: 0.9))
        for (dx, dy, r) in [(34.0, -26.0, 13.0), (-20.0, 40.0, 10.0), (58.0, 70.0, 9.0), (16.0, -70.0, 8.0)] {
            ctx.fillEllipse(in: CGRect(x: glassTop.x + dx - r, y: glassTop.y + dy - r, width: r*2, height: r*2))
        }
    } else {
        // 无杯：酒柱画成弧线落下
        let stream = CGMutablePath()
        stream.move(to: CGPoint(x: mouthX, y: mouthY))
        stream.addCurve(to: CGPoint(x: mouthX + 130, y: mouthY - 420),
                        control1: CGPoint(x: mouthX + 40, y: mouthY - 200),
                        control2: CGPoint(x: mouthX + 120, y: mouthY - 300))
        ctx.saveGState()
        ctx.setStrokeColor(CGColor(red: 0.98, green: 0.72, blue: 0.24, alpha: 0.95))
        ctx.setLineWidth(30)
        ctx.setLineCap(.round)
        ctx.addPath(stream)
        ctx.strokePath()
        ctx.restoreGState()
    }
}

// MARK: - 六个变体

typealias Variant = (name: String, bgTop: NSColor, bgBottom: NSColor, bottleScale: CGFloat,
                     showGlass: Bool, showChar: Bool, charSize: CGFloat, charAlpha: CGFloat,
                     charCenter: CGPoint)

let wineTop = NSColor(calibratedRed: 0.55, green: 0.10, blue: 0.18, alpha: 1)
let wineBottom = NSColor(calibratedRed: 0.30, green: 0.03, blue: 0.08, alpha: 1)
let amberTop = NSColor(calibratedRed: 0.42, green: 0.24, blue: 0.10, alpha: 1)
let amberBottom = NSColor(calibratedRed: 0.20, green: 0.10, blue: 0.04, alpha: 1)
let greenTop = NSColor(calibratedRed: 0.10, green: 0.30, blue: 0.18, alpha: 1)
let greenBottom = NSColor(calibratedRed: 0.03, green: 0.12, blue: 0.07, alpha: 1)

let variants: [Variant] = [
    ("icon-v1", wineTop, wineBottom, 1.0, true, false, 0, 0, .zero),                                  // 经典酒红 + 瓶倒酒入杯
    ("icon-v2", wineTop, wineBottom, 0.92, true, true, 330, 0.35, CGPoint(x: 512, y: 300)),            // 酒红 + 大「开」衬底
    ("icon-v3", amberTop, amberBottom, 1.0, true, false, 0, 0, .zero),                                 // 琥珀棕 + 瓶倒酒入杯
    ("icon-v4", greenTop, greenBottom, 1.0, true, false, 0, 0, .zero),                                 // 墨绿 + 瓶倒酒入杯
    ("icon-v5", wineTop, wineBottom, 1.15, false, false, 0, 0, .zero),                                 // 酒红 + 单瓶弧线（极简）
    ("icon-v6", wineTop, wineBottom, 0.95, true, true, 380, 0.55, CGPoint(x: 760, y: 190)),            // 酒红 + 右下「开」水印
]

for (i, v) in variants.enumerated() {
    let png = render(size: canvas) { ctx in
        drawBackground(ctx, inset: 44, top: v.bgTop, bottom: v.bgBottom)
        if v.showChar {
            drawChar(ctx, "开", fontSize: v.charSize, alpha: v.charAlpha, center: v.charCenter)
        }
        drawPour(ctx, bottleScale: v.bottleScale, showGlass: v.showGlass)
    }
    let path = "\(outDir)/\(v.name).png"
    try! png.write(to: URL(fileURLWithPath: path))
    print("生成 \(path)")
}
print("完成：\(variants.count) 个候选图标")
