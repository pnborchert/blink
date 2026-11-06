// Renders the Blink app icon. Run via `make icon`; writes
// Resources/AppIcon.icns and docs/logo.png.
//
//   swift scripts/make-icon.swift <output-dir>
//
// Motif: two screens; a dotted arc "blinks" the cursor from the dim one on the
// left to the bright one on the right, where it lands with a small sparkle.
import AppKit

let canvas: CGFloat = 1024

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

func drawIcon(in ctx: CGContext) {
    // Coordinates below assume a 1024×1024, y-up canvas.

    // Body: the standard macOS icon squircle (824pt inside a 1024 canvas).
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let bodyPath = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.35))
    ctx.addPath(bodyPath)
    ctx.setFillColor(color(0x4338CA))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(bodyPath)
    ctx.clip()
    let gradient = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
        colors: [color(0x8B5CF6), color(0x4F46E5), color(0x312E81)] as CFArray,
        locations: [0, 0.55, 1]
    )!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 220, y: 924), end: CGPoint(x: 804, y: 100), options: [])
    // Soft top highlight.
    let glow = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
        colors: [color(0xFFFFFF, 0.18), color(0xFFFFFF, 0)] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 512, y: 980), startRadius: 0,
                           endCenter: CGPoint(x: 512, y: 980), endRadius: 560, options: [])
    ctx.restoreGState()

    // Screens.
    let screenSize = CGSize(width: 290, height: 196)
    let left = CGRect(x: 168, y: 402, width: screenSize.width, height: screenSize.height)
    let right = CGRect(x: 566, y: 402, width: screenSize.width, height: screenSize.height)

    func drawScreen(_ rect: CGRect, bright: Bool) {
        let alpha: CGFloat = bright ? 1 : 0.42
        // Stand.
        ctx.setFillColor(color(0xFFFFFF, alpha))
        ctx.fill(CGRect(x: rect.midX - 22, y: rect.minY - 52, width: 44, height: 56))
        ctx.addPath(CGPath(roundedRect: CGRect(x: rect.midX - 72, y: rect.minY - 66, width: 144, height: 22),
                           cornerWidth: 11, cornerHeight: 11, transform: nil))
        ctx.fillPath()
        // Bezel + panel.
        let bezel = CGPath(roundedRect: rect, cornerWidth: 30, cornerHeight: 30, transform: nil)
        ctx.addPath(bezel)
        ctx.setFillColor(color(0xFFFFFF, bright ? 0.22 : 0.08))
        ctx.fillPath()
        ctx.addPath(bezel)
        ctx.setStrokeColor(color(0xFFFFFF, alpha))
        ctx.setLineWidth(20)
        ctx.strokePath()
    }
    drawScreen(left, bright: false)
    drawScreen(right, bright: true)

    // Cursor landing spot (arrow tip) inside the right screen.
    let tip = CGPoint(x: 676, y: 568)

    // Dotted teleport arc from the left screen's center to just before the tip.
    ctx.saveGState()
    ctx.setLineCap(.round)
    ctx.setLineWidth(22)
    ctx.setStrokeColor(color(0xFFFFFF, 0.9))
    ctx.setLineDash(phase: 0, lengths: [0.1, 46])
    ctx.move(to: CGPoint(x: left.midX, y: left.midY + 10))
    ctx.addCurve(to: CGPoint(x: tip.x - 30, y: tip.y + 64),
                 control1: CGPoint(x: 330, y: 830), control2: CGPoint(x: 560, y: 840))
    ctx.strokePath()
    ctx.restoreGState()

    // Origin marker: a faint ring where the cursor used to be.
    ctx.setStrokeColor(color(0xFFFFFF, 0.55))
    ctx.setLineWidth(10)
    ctx.strokeEllipse(in: CGRect(x: left.midX - 26, y: left.midY - 16, width: 52, height: 52))

    // Cursor arrow (classic macOS pointer shape), tip at `tip`, pointing up-left.
    let s: CGFloat = 1.12
    let arrow: [CGPoint] = [
        (0, 0), (0, -100), (24, -77), (40, -114), (56, -107), (40, -71), (72, -71),
    ].map { CGPoint(x: tip.x + $0.0 * s, y: tip.y + $0.1 * s) }
    let arrowPath = CGMutablePath()
    arrowPath.addLines(between: arrow)
    arrowPath.closeSubpath()
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 14, color: color(0x1E1B4B, 0.5))
    ctx.addPath(arrowPath)
    ctx.setFillColor(color(0xFFFFFF))
    ctx.fillPath()
    ctx.restoreGState()
    ctx.addPath(arrowPath)
    ctx.setLineJoin(.round)
    ctx.setLineWidth(10)
    ctx.setStrokeColor(color(0x1E1B4B))
    ctx.strokePath()

    // Sparkle rays around the tip: the "blink".
    ctx.setLineCap(.round)
    ctx.setLineWidth(18)
    ctx.setStrokeColor(color(0xFCD34D))
    for degrees in [100.0, 140.0, 180.0] {
        let a = degrees * .pi / 180
        let inner: CGFloat = 34, outer: CGFloat = 74
        ctx.move(to: CGPoint(x: tip.x + cos(a) * inner, y: tip.y + sin(a) * inner))
        ctx.addLine(to: CGPoint(x: tip.x + cos(a) * outer, y: tip.y + sin(a) * outer))
    }
    ctx.strokePath()
}

func render(size: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    )!
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    let ctx = context.cgContext
    ctx.interpolationQuality = .high
    ctx.setShouldAntialias(true)
    ctx.scaleBy(x: CGFloat(size) / canvas, y: CGFloat(size) / canvas)
    drawIcon(in: ctx)
    context.flushGraphics()
    return rep.representation(using: .png, properties: [:])!
}

let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
let iconset = outDir.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for base in [16, 32, 128, 256, 512] {
    try render(size: base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try render(size: base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
try render(size: 1024).write(to: outDir.appendingPathComponent("logo.png"))
print("Wrote \(iconset.path) and logo.png")
