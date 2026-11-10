// Renders icon/AppIcon.png (1024×1024). Run: swift icon/make-icon.swift
import AppKit
import CoreImage
import QuartzCore

let size = 1024
let S = CGFloat(size)
let space = CGColorSpace(name: CGColorSpace.sRGB)!

func context() -> CGContext {
    CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

let rainbow = [0xFF375F, 0xFF9F0A, 0xFFD60A, 0x30D158, 0x40C8E0, 0x0A84FF, 0xBF5AF2, 0xFF375F].map { rgb(UInt32($0)) }

// macOS icon grid: 824pt tile centred in 1024 canvas.
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)
let box = CGRect(x: 238, y: 300, width: 548, height: 424)
let boxPath = CGPath(roundedRect: box, cornerWidth: 64, cornerHeight: 64, transform: nil)
let center = CGPoint(x: box.midX, y: box.midY)

// Rainbow stroke of the box, as an image so it can be blurred for the glow.
func rainbowStroke(width: CGFloat) -> CGImage {
    let c = context()
    c.addPath(boxPath)
    c.setLineWidth(width)
    c.replacePathWithStrokedPath()
    c.clip()
    let g = CAGradientLayer()
    g.type = .conic
    g.colors = rainbow
    g.frame = CGRect(x: 0, y: 0, width: S, height: S)
    g.startPoint = CGPoint(x: center.x / S, y: center.y / S)
    g.endPoint = CGPoint(x: center.x / S, y: 1)
    g.render(in: c)
    return c.makeImage()!
}

func blurred(_ img: CGImage, _ radius: CGFloat) -> CGImage {
    let ci = CIImage(cgImage: img).clampedToExtent().applyingGaussianBlur(sigma: radius).cropped(to: CGRect(x: 0, y: 0, width: S, height: S))
    return CIContext().createCGImage(ci, from: ci.extent)!
}

let c = context()

// Tile: near-black with a soft top light.
c.saveGState()
c.addPath(tilePath)
c.clip()
let bg = CGGradient(colorsSpace: space, colors: [rgb(0x24242A), rgb(0x0B0B0E)] as CFArray, locations: [0, 1])!
c.drawLinearGradient(bg, start: CGPoint(x: 0, y: tile.maxY), end: CGPoint(x: 0, y: tile.minY), options: [])

// Glow, then crisp stroke.
let full = CGRect(x: 0, y: 0, width: S, height: S)
c.setAlpha(0.9)
c.draw(blurred(rainbowStroke(width: 64), 38), in: full)
c.setAlpha(1)
c.draw(blurred(rainbowStroke(width: 30), 10), in: full)
c.draw(rainbowStroke(width: 26), in: full)
c.restoreGState()

// Inner hairline so the tile edge reads on dark docks.
c.addPath(CGPath(roundedRect: tile.insetBy(dx: 1.5, dy: 1.5), cornerWidth: 184, cornerHeight: 184, transform: nil))
c.setStrokeColor(rgb(0xFFFFFF, 0.1))
c.setLineWidth(3)
c.strokePath()

// Cursor pointing into the box's lower-right corner.
let pts: [(CGFloat, CGFloat)] = [(0, 0), (0, 0.80), (0.205, 0.62), (0.335, 0.92), (0.465, 0.86), (0.34, 0.57), (0.6, 0.57)]
let h: CGFloat = 250
let tip = CGPoint(x: box.maxX - 96, y: box.minY + 96)
let cursor = CGMutablePath()
for (i, p) in pts.enumerated() {
    let q = CGPoint(x: tip.x + p.0 * h, y: tip.y - p.1 * h)
    i == 0 ? cursor.move(to: q) : cursor.addLine(to: q)
}
cursor.closeSubpath()
c.saveGState()
c.setShadow(offset: CGSize(width: 0, height: -10), blur: 30, color: rgb(0x000000, 0.55))
c.addPath(cursor)
c.setFillColor(rgb(0xFFFFFF))
c.fillPath()
c.restoreGState()
c.addPath(cursor)
c.setLineJoin(.round)
c.setLineWidth(14)
c.setStrokeColor(rgb(0x0B0B0E))
c.strokePath()
c.addPath(cursor)
c.setFillColor(rgb(0xFFFFFF))
c.fillPath()

let out = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "icon/AppIcon.png")
let rep = NSBitmapImageRep(cgImage: c.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: out)
print("Wrote \(out.path)")
