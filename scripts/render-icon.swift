// Renders the 1024 px app icon master. Usage:
//   swiftc -O scripts/render-icon.swift -o /tmp/render-icon && /tmp/render-icon icon.png
// then resize into Jiggle/Assets.xcassets/AppIcon.appiconset with `sips -z <px> <px>`.
import AppKit
import CoreGraphics

let size = 1024
let out = CommandLine.arguments[1]
guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(1) }
// Work in top-left coordinates.
ctx.translateBy(x: 0, y: CGFloat(size)); ctx.scaleBy(x: 1, y: -1)

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

// macOS icon grid: 824 pt rounded square centered in 1024, with a soft drop shadow.
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: 12), blur: 28, color: rgb(0x000000, 0.35))
ctx.addPath(tilePath); ctx.setFillColor(rgb(0x1E3A8A)); ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(tilePath); ctx.clip()
let gradient = CGGradient(colorsSpace: nil, colors: [rgb(0x2DD4BF), rgb(0x2563EB), rgb(0x4338CA)] as CFArray,
                          locations: [0, 0.6, 1])!
ctx.drawLinearGradient(gradient, start: CGPoint(x: 200, y: 100), end: CGPoint(x: 824, y: 924), options: [])
// Soft highlight on the top half.
let shine = CGGradient(colorsSpace: nil, colors: [rgb(0xFFFFFF, 0.18), rgb(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(shine, start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 520), options: [])
ctx.restoreGState()

// Motion lines trailing to the lower left.
ctx.setLineCap(.round)
ctx.setStrokeColor(rgb(0xFFFFFF, 0.85))
ctx.setLineWidth(40)
for (start, end) in [((250.0, 470.0), (380.0, 470.0)), ((210.0, 560.0), (380.0, 560.0)), ((270.0, 650.0), (400.0, 650.0))] {
    ctx.move(to: CGPoint(x: start.0, y: start.1)); ctx.addLine(to: CGPoint(x: end.0, y: end.1))
}
ctx.strokePath()

// Classic arrow pointer, tip at the top left.
let tip = CGPoint(x: 470, y: 250)
let unit: CGFloat = 520
let shape: [(CGFloat, CGFloat)] = [(0, 0), (0, 0.80), (0.19, 0.625), (0.32, 0.92), (0.45, 0.865), (0.325, 0.58), (0.565, 0.58)]
let arrow = CGMutablePath()
for (i, p) in shape.enumerated() {
    let point = CGPoint(x: tip.x + p.0 * unit, y: tip.y + p.1 * unit)
    i == 0 ? arrow.move(to: point) : arrow.addLine(to: point)
}
arrow.closeSubpath()
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: 10), blur: 24, color: rgb(0x0B1E5B, 0.45))
ctx.addPath(arrow); ctx.setFillColor(rgb(0xFFFFFF)); ctx.fillPath()
ctx.restoreGState()
ctx.addPath(arrow)
ctx.setLineJoin(.round); ctx.setLineWidth(22); ctx.setStrokeColor(rgb(0x0F172A))
ctx.strokePath()

guard let image = ctx.makeImage(),
      let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { exit(1) }
try data.write(to: URL(fileURLWithPath: out))
