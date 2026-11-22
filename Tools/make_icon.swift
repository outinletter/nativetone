// Generates App/Assets.xcassets/AppIcon.appiconset/icon-1024.png
//   swift Tools/make_icon.swift
import AppKit

let size: CGFloat = 1024
let out = "App/Assets.xcassets/AppIcon.appiconset/icon-1024.png"

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
else { fatalError("bitmap") }
rep.size = NSSize(width: size, height: size)

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// Background gradient (indigo -> violet).
let gradient = NSGradient(colors: [
    NSColor(srgbRed: 0.33, green: 0.27, blue: 0.86, alpha: 1),
    NSColor(srgbRed: 0.62, green: 0.36, blue: 0.95, alpha: 1),
])!
gradient.draw(in: NSRect(x: 0, y: 0, width: size, height: size), angle: -50)

// Speech bubble.
let bubble = NSBezierPath(roundedRect: NSRect(x: 190, y: 330, width: 644, height: 420), xRadius: 150, yRadius: 150)
let tail = NSBezierPath()
tail.move(to: NSPoint(x: 300, y: 345))
tail.line(to: NSPoint(x: 270, y: 215))
tail.line(to: NSPoint(x: 440, y: 335))
tail.close()
NSColor.white.setFill()
bubble.fill()
tail.fill()

// "Tone" waveform bars inside the bubble.
let heights: [CGFloat] = [90, 170, 250, 170, 90]
let barW: CGFloat = 52, gap: CGFloat = 40
let totalW = CGFloat(heights.count) * barW + CGFloat(heights.count - 1) * gap
var x = (size - totalW) / 2
let midY: CGFloat = 540
NSColor(srgbRed: 0.40, green: 0.30, blue: 0.88, alpha: 1).setFill()
for h in heights {
    NSBezierPath(roundedRect: NSRect(x: x, y: midY - h / 2, width: barW, height: h), xRadius: barW / 2, yRadius: barW / 2).fill()
    x += barW + gap
}

// Sparkle (top right).
func sparkle(center: NSPoint, r: CGFloat) {
    let p = NSBezierPath()
    let k = r * 0.22
    p.move(to: NSPoint(x: center.x, y: center.y + r))
    p.curve(to: NSPoint(x: center.x + r, y: center.y), controlPoint1: NSPoint(x: center.x + k, y: center.y + k), controlPoint2: NSPoint(x: center.x + k, y: center.y + k))
    p.curve(to: NSPoint(x: center.x, y: center.y - r), controlPoint1: NSPoint(x: center.x + k, y: center.y - k), controlPoint2: NSPoint(x: center.x + k, y: center.y - k))
    p.curve(to: NSPoint(x: center.x - r, y: center.y), controlPoint1: NSPoint(x: center.x - k, y: center.y - k), controlPoint2: NSPoint(x: center.x - k, y: center.y - k))
    p.curve(to: NSPoint(x: center.x, y: center.y + r), controlPoint1: NSPoint(x: center.x - k, y: center.y + k), controlPoint2: NSPoint(x: center.x - k, y: center.y + k))
    p.close()
    NSColor(srgbRed: 1.0, green: 0.86, blue: 0.35, alpha: 1).setFill()
    p.fill()
}
sparkle(center: NSPoint(x: 790, y: 800), r: 120)
sparkle(center: NSPoint(x: 650, y: 880), r: 50)

NSGraphicsContext.restoreGraphicsState()

// Flatten to an opaque image: App Store icons must not contain an alpha channel.
guard let cg = rep.cgImage,
      let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
else { fatalError("flatten") }
ctx.draw(cg, in: CGRect(x: 0, y: 0, width: size, height: size))
guard let flat = ctx.makeImage() else { fatalError("flat image") }
let flatRep = NSBitmapImageRep(cgImage: flat)
guard let png = flatRep.representation(using: .png, properties: [:]) else { fatalError("png") }
try png.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
