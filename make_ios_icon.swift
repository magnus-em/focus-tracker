#!/usr/bin/env swift
import Cocoa
import CoreGraphics

// Generates a single 1024x1024 PNG for FocusPad's iOS AppIcon. iOS 17+
// accepts a single 1024x1024 asset; the system resizes for every context.
// We build the bitmap with an explicit CGContext (rather than lockFocus
// on an NSImage) so the output is exactly 1024x1024 pixels on Retina
// machines, and we strip alpha for App Store compatibility.

let size = 1024

let colorSpace = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(
    data: nil,
    width: size, height: size,
    bitsPerComponent: 8, bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
) else { fatalError("Failed to create CGContext") }

let dim = CGFloat(size)
ctx.setFillColor(red: 0.96, green: 0.36, blue: 0.36, alpha: 1)
ctx.fill(CGRect(x: 0, y: 0, width: dim, height: dim))

let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: false)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = nsCtx

let pt = dim * 0.45
let cfg = NSImage.SymbolConfiguration(pointSize: pt, weight: .medium)
if let symbol = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: nil)?
    .withSymbolConfiguration(cfg) {

    let sw = symbol.size.width
    let sh = symbol.size.height

    let whiteSymbol = NSImage(size: symbol.size, flipped: false) { rect in
        NSColor.white.setFill()
        rect.fill()
        symbol.draw(in: rect, from: .zero,
                    operation: .destinationIn, fraction: 1.0,
                    respectFlipped: false, hints: nil)
        return true
    }

    let x = (dim - sw) / 2
    let y = (dim - sh) / 2
    whiteSymbol.draw(in: NSRect(x: x, y: y, width: sw, height: sh),
                     from: .zero, operation: .sourceOver, fraction: 1.0,
                     respectFlipped: false, hints: nil)
}

NSGraphicsContext.restoreGraphicsState()

guard let cgImage = ctx.makeImage() else { fatalError("makeImage failed") }
let rep = NSBitmapImageRep(cgImage: cgImage)
guard let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("PNG encode failed")
}

let outDir = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "/tmp/FocusPadIcon"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

let outPath = "\(outDir)/icon_1024.png"
try? png.write(to: URL(fileURLWithPath: outPath))
print("Wrote \(outPath) at \(rep.pixelsWide)x\(rep.pixelsHigh)")
