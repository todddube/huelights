#!/usr/bin/env swift
//
//  make-icons.swift
//  scripts · HueBar
//
//  Renders the HueBar app icon (a glowing bulb inside a hue ring on an indigo squircle)
//  and writes the asset catalog iconset, an .icns for the SwiftPM bundle and a README banner.
//

import AppKit
import CoreGraphics

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
let appIconSet = root.appending(path: "HueBar/Assets.xcassets/AppIcon.appiconset")
let resources = root.appending(path: "Resources")
let fm = FileManager.default
try fm.createDirectory(at: appIconSet, withIntermediateDirectories: true)
try fm.createDirectory(at: resources, withIntermediateDirectories: true)

// MARK: - Drawing

/// Draws the icon at `size` points into a bitmap. `padded` leaves the HIG margin for the app icon.
func renderIcon(size: CGFloat, padded: Bool, transparent: Bool) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    let gc = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = gc
    let ctx = gc.cgContext

    let inset = padded ? size * 0.1 : 0
    let tile = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)

    if !transparent {
        // macOS squircle: corner radius ≈ 22.37% of the tile.
        let squircle = CGPath(roundedRect: tile, cornerWidth: tile.width * 0.2237, cornerHeight: tile.width * 0.2237, transform: nil)
        ctx.saveGState()
        ctx.addPath(squircle)
        ctx.clip()
        let bg = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
            NSColor(red: 0.11, green: 0.07, blue: 0.27, alpha: 1).cgColor,
            NSColor(red: 0.27, green: 0.13, blue: 0.52, alpha: 1).cgColor,
        ] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(bg, start: CGPoint(x: tile.minX, y: tile.maxY), end: CGPoint(x: tile.maxX, y: tile.minY), options: [])
        // Subtle vignette highlight top-left.
        let glow = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
            NSColor(white: 1, alpha: 0.18).cgColor, NSColor(white: 1, alpha: 0).cgColor,
        ] as CFArray, locations: [0, 1])!
        ctx.drawRadialGradient(glow, startCenter: CGPoint(x: tile.minX + tile.width * 0.3, y: tile.maxY - tile.height * 0.2), startRadius: 0,
                               endCenter: CGPoint(x: tile.minX + tile.width * 0.3, y: tile.maxY - tile.height * 0.2), endRadius: tile.width * 0.8, options: [])
        ctx.restoreGState()
    }

    let center = CGPoint(x: tile.midX, y: tile.midY)
    let ringRadius = tile.width * 0.33
    let ringWidth = tile.width * 0.075

    // Hue ring: 360 arc segments sweeping through the spectrum, with a soft glow underneath.
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: tile.width * 0.06, color: NSColor(white: 1, alpha: 0.35).cgColor)
    ctx.setLineWidth(ringWidth)
    ctx.setLineCap(.butt)
    let segments = 360
    for i in 0..<segments {
        let start = CGFloat(i) / CGFloat(segments) * 2 * .pi + .pi / 2
        let end = CGFloat(i + 1) / CGFloat(segments) * 2 * .pi + .pi / 2 + 0.01
        ctx.setStrokeColor(NSColor(hue: CGFloat(i) / CGFloat(segments), saturation: 0.85, brightness: 1, alpha: 1).cgColor)
        ctx.addArc(center: center, radius: ringRadius, startAngle: start, endAngle: end, clockwise: false)
        ctx.strokePath()
    }
    ctx.restoreGState()

    // Warm glow behind the bulb.
    let warm = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
        NSColor(red: 1, green: 0.85, blue: 0.45, alpha: 0.9).cgColor,
        NSColor(red: 1, green: 0.7, blue: 0.3, alpha: 0).cgColor,
    ] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(warm, startCenter: center, startRadius: 0, endCenter: center, endRadius: ringRadius * 0.95, options: [])

    // Bulb glyph from SF Symbols, rendered white with a soft shadow.
    let config = NSImage.SymbolConfiguration(pointSize: tile.width * 0.34, weight: .semibold)
        .applying(.init(paletteColors: [.white]))
    if let symbol = NSImage(systemSymbolName: "lightbulb.fill", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
        let symbolSize = symbol.size
        let origin = CGPoint(x: center.x - symbolSize.width / 2, y: center.y - symbolSize.height / 2)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -tile.width * 0.01), blur: tile.width * 0.04, color: NSColor(red: 0.4, green: 0.1, blue: 0.5, alpha: 0.6).cgColor)
        symbol.draw(in: CGRect(origin: origin, size: symbolSize))
        ctx.restoreGState()
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func writePNG(_ rep: NSBitmapImageRep, to url: URL) throws {
    try rep.representation(using: .png, properties: [:])!.write(to: url)
}

func scaled(_ master: NSBitmapImageRep, to pixels: Int) -> NSBitmapImageRep {
    let image = NSImage(size: NSSize(width: master.pixelsWide, height: master.pixelsHigh))
    image.addRepresentation(master)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

// MARK: - App icon set

let master = renderIcon(size: 1024, padded: true, transparent: false)
let entries: [(points: Int, scale: Int)] = [
    (16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2),
]
var images: [[String: String]] = []
for entry in entries {
    let pixels = entry.points * entry.scale
    let name = "icon_\(entry.points)x\(entry.points)\(entry.scale == 2 ? "@2x" : "").png"
    try writePNG(pixels == 1024 ? master : scaled(master, to: pixels), to: appIconSet.appending(path: name))
    images.append(["idiom": "mac", "size": "\(entry.points)x\(entry.points)", "scale": "\(entry.scale)x", "filename": name])
}
let contents: [String: Any] = ["images": images, "info": ["version": 1, "author": "xcode"]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    .write(to: appIconSet.appending(path: "Contents.json"))

// MARK: - .icns for the SwiftPM bundle

let iconset = resources.appending(path: "AppIcon.iconset")
try? fm.removeItem(at: iconset)
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)
for entry in entries {
    let pixels = entry.points * entry.scale
    let name = "icon_\(entry.points)x\(entry.points)\(entry.scale == 2 ? "@2x" : "").png"
    try writePNG(pixels == 1024 ? master : scaled(master, to: pixels), to: iconset.appending(path: name))
}
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", resources.appending(path: "AppIcon.icns").path]
try iconutil.run()
iconutil.waitUntilExit()
try? fm.removeItem(at: iconset)
guard iconutil.terminationStatus == 0 else {
    FileHandle.standardError.write(Data("iconutil failed with status \(iconutil.terminationStatus)\n".utf8))
    exit(1)
}

// MARK: - README banner and preview

try writePNG(master, to: resources.appending(path: "AppIcon-1024.png"))
try writePNG(renderIcon(size: 512, padded: false, transparent: true), to: resources.appending(path: "Logo.png"))

print("✓ Wrote \(appIconSet.path), Resources/AppIcon.icns, Resources/AppIcon-1024.png, Resources/Logo.png")
