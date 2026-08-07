#!/usr/bin/env swift
import AppKit

/// Raster background for create-dmg. MUST be exactly 660×400 px at 1× — Finder scrolls if the PNG pixel size exceeds the window (NSImage→TIFF often produced @2x bitmaps).
guard CommandLine.arguments.count >= 3 else {
    FileHandle.standardError.write(Data("usage: render-dmg-background <cyclone.png> <out.png>\n".utf8))
    exit(1)
}

let cyclonePNG = CommandLine.arguments[1]
let outPNG = CommandLine.arguments[2]

let pw = 660
let ph = 400
let width = CGFloat(pw)
let height = CGFloat(ph)

guard let cyclone = NSImage(contentsOfFile: cyclonePNG) else {
    FileHandle.standardError.write(Data("error: could not load cyclone PNG\n".utf8))
    exit(1)
}

guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: pw,
    pixelsHigh: ph,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 32
) else {
    FileHandle.standardError.write(Data("error: could not create bitmap\n".utf8))
    exit(1)
}

// Keep points == pixels so Finder doesn’t treat this as a 2× slice wider than the window.
bitmap.size = NSSize(width: width, height: height)

guard let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap) else {
    FileHandle.standardError.write(Data("error: could not create graphics context\n".utf8))
    exit(1)
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = graphicsContext
// Bitmap contexts default to bottom-left origin; flip so coordinates match Finder-style y-down (same as before).
if let ctx = NSGraphicsContext.current?.cgContext {
    ctx.translateBy(x: 0, y: height)
    ctx.scaleBy(x: 1, y: -1)
}

// Canvas
NSColor(calibratedRed: 0.13, green: 0.13, blue: 0.14, alpha: 1).setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: width, height: height)).fill()

// Watermark — vertical flip only (no 180°: avoids L/R mirror)
let cycloneSide = min(width, height) * 0.72
let cx = width / 2
let cy = height / 2
let cycloneRect = NSRect(
    x: cx - cycloneSide / 2,
    y: cy - cycloneSide / 2,
    width: cycloneSide,
    height: cycloneSide
)
if let ctx = NSGraphicsContext.current?.cgContext {
    ctx.saveGState()
    ctx.translateBy(x: cx, y: cy)
    ctx.scaleBy(x: 1, y: -1)
    ctx.translateBy(x: -cx, y: -cy)
    cyclone.draw(in: cycloneRect, from: .zero, operation: .sourceOver, fraction: 0.085)
    ctx.restoreGState()
} else {
    cyclone.draw(in: cycloneRect, from: .zero, operation: .sourceOver, fraction: 0.085)
}

// Arrow
let arrowY: CGFloat = 202
let iconHalf: CGFloat = 52
let gap: CGFloat = 30
let tail = CGPoint(x: 180 + iconHalf + gap, y: arrowY)
let tip = CGPoint(x: 480 - iconHalf - gap, y: arrowY)
let stroke = NSColor.white.withAlphaComponent(0.38)
let headDepth: CGFloat = 18
let shaftEnd = CGPoint(x: tip.x - headDepth, y: arrowY)

let shaftPath = NSBezierPath()
shaftPath.move(to: tail)
shaftPath.line(to: shaftEnd)
shaftPath.lineWidth = 5
shaftPath.lineCapStyle = .round
stroke.setStroke()
shaftPath.stroke()

let wing: CGFloat = 13
let baseX = tip.x - headDepth
let arrowHead = NSBezierPath()
arrowHead.move(to: CGPoint(x: baseX, y: tip.y - wing))
arrowHead.line(to: tip)
arrowHead.line(to: CGPoint(x: baseX, y: tip.y + wing))
arrowHead.lineWidth = 5
arrowHead.lineCapStyle = .round
arrowHead.lineJoinStyle = .round
stroke.setStroke()
arrowHead.stroke()

NSGraphicsContext.restoreGraphicsState()

guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("error: could not encode PNG\n".utf8))
    exit(1)
}

do {
    try pngData.write(to: URL(fileURLWithPath: outPNG))
} catch {
    FileHandle.standardError.write(Data("error: write failed\n".utf8))
    exit(1)
}
