#!/usr/bin/env swift
//
//  make-app-icon.swift
//  Draws Griffel's app icon and writes every size the app needs.
//
//  The icon is "Kreide auf Schiefer": one chalk stroke that starts as a spoken
//  wave on the left and settles into a written line on the right, with two
//  started lines underneath — the same staggered-lines motif the menu bar
//  icon carries.
//
//  Run from the repository root:
//      swift scripts/make-app-icon.swift
//
//  It writes the PNGs into Assets.xcassets/AppIcon.appiconset/ and rebuilds
//  Resources/AppIcon.icns, which build.sh copies into the bundle by hand.
//
//  Everything below is authored on Apple's 1024 pt macOS icon grid: the shape
//  is 824 × 824 centred, so 100 pt of margin all round. Nothing is drawn
//  outside it, and the corners stay transparent — macOS does not round the
//  icon for us.
//

import AppKit
import Foundation

// MARK: - Canvas

let canvas: CGFloat = 1024
let shapeSide: CGFloat = 824

// MARK: - Palette

/// Slate, lit from the top left.
let slateTop = CGColor(srgbRed: 0x28 / 255, green: 0x2F / 255, blue: 0x36 / 255, alpha: 1)
let slateBottom = CGColor(srgbRed: 0x0C / 255, green: 0x10 / 255, blue: 0x13 / 255, alpha: 1)
/// Chalk, slightly warm so it does not read as pure UI white.
let chalk = CGColor(srgbRed: 0xF2 / 255, green: 0xF0 / 255, blue: 0xEA / 255, alpha: 1)

// MARK: - The shape

/// Apple's continuous corner is a superellipse, not a rounded rectangle.
/// Sampling it beats guessing at Bézier control points.
func squirclePath(exponent n: CGFloat = 5, steps: Int = 1440) -> CGPath {
    let a = shapeSide / 2
    let c = canvas / 2
    let path = CGMutablePath()
    for i in 0...steps {
        let t = 2 * CGFloat.pi * CGFloat(i) / CGFloat(steps)
        let cs = cos(t), sn = sin(t)
        let x = a * copysign(pow(abs(cs), 2 / n), cs)
        let y = a * copysign(pow(abs(sn), 2 / n), sn)
        let p = CGPoint(x: c + x, y: c + y)
        i == 0 ? path.move(to: p) : path.addLine(to: p)
    }
    path.closeSubpath()
    return path
}

// MARK: - The stroke

/// Smoothstep, running from 1 down to 0.
func ease(_ t: CGFloat) -> CGFloat {
    let t = min(max(t, 0), 1)
    return 1 - (t * t * (3 - 2 * t))
}

/// The voice half oscillates, then the amplitude eases out and the line
/// carries on flat. The wavelength is deliberately long relative to the
/// amplitude: the radius of curvature at a sine's crest is λ² / (4π²A), and
/// once that drops near the half stroke width the crests render as blobs.
func chalkStroke() -> CGPath {
    let x0: CGFloat = 170
    let axis: CGFloat = 410
    let amplitude: CGFloat = 62
    let wavelength: CGFloat = 300
    let cycles: CGFloat = 1.5
    let hold: CGFloat = 0.40      // fraction held at full amplitude
    let flatEnd: CGFloat = 854

    let waveEnd = x0 + cycles * wavelength
    let path = CGMutablePath()
    var x = x0
    var started = false
    while x <= waveEnd {
        let f = (x - x0) / (waveEnd - x0)
        let a = f <= hold ? amplitude : amplitude * ease((f - hold) / (1 - hold))
        let y = axis - a * sin(2 * CGFloat.pi * (x - x0) / wavelength)
        let p = CGPoint(x: x, y: y)
        started ? path.addLine(to: p) : path.move(to: p)
        started = true
        x += 0.4
    }
    path.addLine(to: CGPoint(x: flatEnd, y: axis))
    return path
}

/// The two started lines below — the existing menu bar motif, quieted down.
let writtenLines: [(rect: CGRect, alpha: CGFloat)] = [
    (CGRect(x: 170, y: 562, width: 500, height: 40), 0.78),
    (CGRect(x: 170, y: 660, width: 310, height: 40), 0.52),
]

// MARK: - Drawing

func drawIcon(into ctx: CGContext, side: CGFloat) {
    ctx.saveGState()
    // Author in the 1024 grid with y pointing down, the way the drawing is specified.
    ctx.scaleBy(x: side / canvas, y: side / canvas)
    ctx.translateBy(x: 0, y: canvas)
    ctx.scaleBy(x: 1, y: -1)
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high

    let shape = squirclePath()

    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let gradient = CGGradient(colorsSpace: space,
                              colors: [slateTop, slateBottom] as CFArray,
                              locations: [0, 1])!
    let inset = (canvas - shapeSide) / 2
    ctx.drawLinearGradient(gradient,
                           start: CGPoint(x: inset, y: inset),
                           end: CGPoint(x: canvas - inset, y: canvas - inset),
                           options: [])
    ctx.restoreGState()

    ctx.setLineWidth(40)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.setStrokeColor(chalk)
    ctx.addPath(chalkStroke())
    ctx.strokePath()

    for line in writtenLines {
        ctx.setFillColor(chalk.copy(alpha: line.alpha)!)
        ctx.addPath(CGPath(roundedRect: line.rect,
                           cornerWidth: line.rect.height / 2,
                           cornerHeight: line.rect.height / 2,
                           transform: nil))
        ctx.fillPath()
    }

    ctx.restoreGState()
}

func renderPNG(side: Int) -> Data {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let ctx = CGContext(data: nil, width: side, height: side,
                              bitsPerComponent: 8, bytesPerRow: 0, space: space,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        fatalError("Kein Bitmap-Kontext für \(side) px")
    }
    drawIcon(into: ctx, side: CGFloat(side))
    guard let image = ctx.makeImage() else { fatalError("Kein Bild für \(side) px") }
    let rep = NSBitmapImageRep(cgImage: image)
    rep.size = NSSize(width: side, height: side)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        fatalError("Kein PNG für \(side) px")
    }
    return data
}

// MARK: - Where it goes

let fm = FileManager.default
let root = URL(fileURLWithPath: CommandLine.arguments.count > 1
               ? CommandLine.arguments[1]
               : fm.currentDirectoryPath)
let resources = root.appendingPathComponent("GriffelMac/Resources")
guard fm.fileExists(atPath: resources.path) else {
    FileHandle.standardError.write(
        "GriffelMac/Resources nicht gefunden — bitte aus dem Repository-Wurzelverzeichnis starten.\n"
            .data(using: .utf8)!)
    exit(1)
}

let appIconSet = resources.appendingPathComponent("Assets.xcassets/AppIcon.appiconset")
try fm.createDirectory(at: appIconSet, withIntermediateDirectories: true)

/// The names the asset catalog's Contents.json refers to, plus the loose 1024.
let catalogSizes: [(name: String, px: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_64x64", 64), ("icon_64x64@2x", 128),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
    ("icon_1024x1024", 1024),
]

/// iconutil only accepts these names — 64 pt is an asset catalog idea.
let icnsSizes: [(name: String, px: Int)] = catalogSizes.filter {
    !$0.name.hasPrefix("icon_64x64") && $0.name != "icon_1024x1024"
}

var rendered: [Int: Data] = [:]
func png(_ px: Int) -> Data {
    if let cached = rendered[px] { return cached }
    let data = renderPNG(side: px)
    rendered[px] = data
    return data
}

for entry in catalogSizes {
    try png(entry.px).write(to: appIconSet.appendingPathComponent("\(entry.name).png"))
}
print("✅ \(catalogSizes.count) PNGs in Assets.xcassets/AppIcon.appiconset/")

let iconset = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("Griffel-\(UUID().uuidString).iconset")
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)
for entry in icnsSizes {
    try png(entry.px).write(to: iconset.appendingPathComponent("\(entry.name).png"))
}

let icns = resources.appendingPathComponent("AppIcon.icns")
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", icns.path]
try iconutil.run()
iconutil.waitUntilExit()
try? fm.removeItem(at: iconset)

guard iconutil.terminationStatus == 0 else {
    FileHandle.standardError.write("iconutil ist fehlgeschlagen.\n".data(using: .utf8)!)
    exit(1)
}
print("✅ AppIcon.icns neu gebaut")
