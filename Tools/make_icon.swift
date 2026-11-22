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

// Deep navy ground.
let gradient = NSGradient(colors: [
    NSColor(srgbRed: 0.075, green: 0.145, blue: 0.280, alpha: 1),
    NSColor(srgbRed: 0.035, green: 0.075, blue: 0.160, alpha: 1),
])!
gradient.draw(in: NSRect(x: 0, y: 0, width: size, height: size), angle: -60)

let gold = NSColor(srgbRed: 0.80, green: 0.67, blue: 0.42, alpha: 1)

// Fine inner frame.
gold.withAlphaComponent(0.55).setStroke()
let frame = NSBezierPath(roundedRect: NSRect(x: 84, y: 84, width: size - 168, height: size - 168), xRadius: 28, yRadius: 28)
frame.lineWidth = 5
frame.stroke()

// Serif "N" monogram.
let base = NSFont.systemFont(ofSize: 640, weight: .semibold)
let desc = base.fontDescriptor.withDesign(.serif) ?? base.fontDescriptor
let font = NSFont(descriptor: desc, size: 640) ?? base
let para = NSMutableParagraphStyle()
para.alignment = .center
let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: gold, .paragraphStyle: para]
let glyph = NSAttributedString(string: "N", attributes: attrs)
let gs = glyph.size()
glyph.draw(in: NSRect(x: 0, y: (size - gs.height) / 2 + 30, width: size, height: gs.height))

// Rule beneath the monogram.
gold.setFill()
NSBezierPath(rect: NSRect(x: size / 2 - 70, y: 232, width: 140, height: 6)).fill()

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
