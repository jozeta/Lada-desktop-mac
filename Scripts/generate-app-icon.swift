#!/usr/bin/env swift
import AppKit
import CoreGraphics
import Foundation

let args = CommandLine.arguments
guard args.count >= 2 else {
    fputs("Usage: generate-app-icon.swift <output.iconset-directory>\n", stderr)
    exit(1)
}

let iconsetPath = args[1]
let fm = FileManager.default
try? fm.removeItem(atPath: iconsetPath)
try fm.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)

func renderIcon(size: Int) -> Data? {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { return nil }

    NSGraphicsContext.saveGraphicsState()
    guard let nsCtx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    NSGraphicsContext.current = nsCtx
    let ctx = nsCtx.cgContext

    let s = CGFloat(size)
    let pad = s * 0.085
    let rect = CGRect(x: pad, y: pad, width: s - pad * 2, height: s - pad * 2)
    let corner = rect.width * 0.225

    // Background squircle with Technical Nordic slate-fjord gradient
    let bgPath = CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner, transform: nil)
    ctx.saveGState()
    ctx.addPath(bgPath)
    ctx.clip()

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let colors = [
        CGColor(red: 0.08, green: 0.12, blue: 0.18, alpha: 1.0),
        CGColor(red: 0.13, green: 0.22, blue: 0.33, alpha: 1.0)
    ] as CFArray
    if let grad = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0.0, 1.0]) {
        ctx.drawLinearGradient(
            grad,
            start: CGPoint(x: rect.minX, y: rect.minY),
            end: CGPoint(x: rect.maxX, y: rect.maxY),
            options: []
        )
    }

    // Subtle inner Nordic grid lines
    ctx.setStrokeColor(CGColor(red: 0.35, green: 0.58, blue: 0.78, alpha: 0.12))
    ctx.setLineWidth(max(1.0, s * 0.004))
    let step = rect.width / 6.0
    for i in 1..<6 {
        let offset = rect.minX + CGFloat(i) * step
        ctx.move(to: CGPoint(x: offset, y: rect.minY))
        ctx.addLine(to: CGPoint(x: offset, y: rect.maxY))
        let yOffset = rect.minY + CGFloat(i) * step
        ctx.move(to: CGPoint(x: rect.minX, y: yOffset))
        ctx.addLine(to: CGPoint(x: rect.maxX, y: yOffset))
    }
    ctx.strokePath()
    ctx.restoreGState()

    // Outer metallic border
    ctx.addPath(bgPath)
    ctx.setStrokeColor(CGColor(red: 0.44, green: 0.68, blue: 0.88, alpha: 0.42))
    ctx.setLineWidth(max(1.0, s * 0.012))
    ctx.strokePath()

    // Isometric Nordic "Låda" (Crate / Container Cube) wireframe + internal VM core
    let cx = s * 0.5
    let cy = s * 0.5
    let r = s * 0.255
    let dx = r * 0.8660254
    let dy = r * 0.5

    let top = CGPoint(x: cx, y: cy + r)
    let topRight = CGPoint(x: cx + dx, y: cy + dy)
    let bottomRight = CGPoint(x: cx + dx, y: cy - dy)
    let bottom = CGPoint(x: cx, y: cy - r)
    let bottomLeft = CGPoint(x: cx - dx, y: cy - dy)
    let topLeft = CGPoint(x: cx - dx, y: cy + dy)
    let center = CGPoint(x: cx, y: cy)

    // Top face fill
    ctx.saveGState()
    ctx.move(to: top)
    ctx.addLine(to: topRight)
    ctx.addLine(to: center)
    ctx.addLine(to: topLeft)
    ctx.closePath()
    ctx.setFillColor(CGColor(red: 0.29, green: 0.56, blue: 0.78, alpha: 0.35))
    ctx.fillPath()
    ctx.restoreGState()

    // Left face fill
    ctx.saveGState()
    ctx.move(to: topLeft)
    ctx.addLine(to: center)
    ctx.addLine(to: bottom)
    ctx.addLine(to: bottomLeft)
    ctx.closePath()
    ctx.setFillColor(CGColor(red: 0.20, green: 0.42, blue: 0.62, alpha: 0.28))
    ctx.fillPath()
    ctx.restoreGState()

    // Right face fill
    ctx.saveGState()
    ctx.move(to: center)
    ctx.addLine(to: topRight)
    ctx.addLine(to: bottomRight)
    ctx.addLine(to: bottom)
    ctx.closePath()
    ctx.setFillColor(CGColor(red: 0.14, green: 0.30, blue: 0.46, alpha: 0.35))
    ctx.fillPath()
    ctx.restoreGState()

    // Outer hexagon stroke
    ctx.setStrokeColor(CGColor(red: 0.78, green: 0.90, blue: 0.98, alpha: 0.96))
    ctx.setLineWidth(max(1.5, s * 0.024))
    ctx.setLineJoin(.round)
    ctx.setLineCap(.round)

    ctx.move(to: top)
    ctx.addLine(to: topRight)
    ctx.addLine(to: bottomRight)
    ctx.addLine(to: bottom)
    ctx.addLine(to: bottomLeft)
    ctx.addLine(to: topLeft)
    ctx.closePath()
    ctx.strokePath()

    // Inner isometric Y-edges
    ctx.setStrokeColor(CGColor(red: 0.48, green: 0.78, blue: 0.96, alpha: 0.92))
    ctx.setLineWidth(max(1.2, s * 0.020))
    ctx.move(to: topLeft)
    ctx.addLine(to: center)
    ctx.addLine(to: topRight)
    ctx.move(to: center)
    ctx.addLine(to: bottom)
    ctx.strokePath()

    // Active status indicator dot at center vertex
    let dotR = max(2.0, s * 0.032)
    let dotRect = CGRect(x: cx - dotR, y: cy - dotR, width: dotR * 2, height: dotR * 2)
    ctx.setFillColor(CGColor(red: 0.22, green: 0.78, blue: 0.56, alpha: 1.0))
    ctx.fillEllipse(in: dotRect)

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

let specs: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for spec in specs {
    guard let png = renderIcon(size: spec.pixels) else {
        fputs("Failed to render \(spec.name)\n", stderr)
        exit(1)
    }
    let outURL = URL(fileURLWithPath: iconsetPath).appendingPathComponent(spec.name)
    try png.write(to: outURL)
}
print("Generated iconset at \(iconsetPath)")
