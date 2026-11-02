#!/usr/bin/env swift
// Draws the 1024x1024 app icon: glossy letter bubbles on the game's blue, opaque as the App Store requires.
//   swift scripts/make-icon.swift App/Assets.xcassets/AppIcon.appiconset/icon-1024.png
import AppKit
import CoreText

let size = 1024
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                    space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat(hex >> 16 & 255) / 255, green: CGFloat(hex >> 8 & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: a)
}
func gradient(_ colors: [CGColor], _ stops: [CGFloat]) -> CGGradient {
    CGGradient(colorsSpace: space, colors: colors as CFArray, locations: stops)!
}

ctx.drawLinearGradient(gradient([rgb(0x38B6E0), rgb(0x2C6FE3), rgb(0x1A3FB0)], [0, 0.55, 1]),
                       start: CGPoint(x: 0, y: 1024), end: CGPoint(x: 1024, y: 0), options: [])
// the page's soft colour blobs
for (x, y, r, c) in [(120.0, 900.0, 520.0, rgb(0xFFAAD6, 0.55)), (960.0, 760.0, 460.0, rgb(0xB2FFE2, 0.35)), (520.0, 40.0, 560.0, rgb(0xB2FFE2, 0.4))] {
    ctx.drawRadialGradient(gradient([c, c.copy(alpha: 0)!], [0, 1]), startCenter: CGPoint(x: x, y: y), startRadius: 0,
                           endCenter: CGPoint(x: x, y: y), endRadius: r, options: [])
}

func bubble(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, _ text: String) {
    let center = CGPoint(x: cx, y: cy)
    let rect = CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -r * 0.12), blur: r * 0.3, color: rgb(0x0B1E5A, 0.45))
    ctx.setFillColor(rgb(0xFFFFFF, 0.95))
    ctx.fillEllipse(in: rect)
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addEllipse(in: rect)
    ctx.clip()
    let light = CGPoint(x: cx - r * 0.36, y: cy + r * 0.44)
    ctx.drawRadialGradient(gradient([rgb(0xFFFFFF), rgb(0xF2F7FF), rgb(0xBED6FF)], [0, 0.5, 1]),
                           startCenter: light, startRadius: 0, endCenter: center, endRadius: r * 1.1,
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()

    let font = CTFontCreateWithFontDescriptor(
        CTFontDescriptorCreateWithAttributes([
            kCTFontFamilyNameAttribute: "SF Pro Rounded",
            kCTFontTraitsAttribute: [kCTFontWeightTrait: NSFont.Weight.heavy.rawValue],
        ] as CFDictionary), r * 1.05, nil)
    let rounded = NSFont.systemFont(ofSize: r * 1.05, weight: .heavy).fontDescriptor.withDesign(.rounded)
        .flatMap { NSFont(descriptor: $0, size: r * 1.05) } ?? (font as NSFont)
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [
        .font: rounded, .foregroundColor: NSColor(cgColor: rgb(0x172033))!,
    ]))
    let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
    ctx.textPosition = CGPoint(x: cx - bounds.midX, y: cy - bounds.midY)
    CTLineDraw(line, ctx)
}

bubble(420, 600, 300, "W")
bubble(778, 306, 176, "B")
bubble(196, 214, 110, "")
bubble(838, 716, 78, "")

let out = URL(fileURLWithPath: CommandLine.arguments[1])
let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try rep.representation(using: .png, properties: [:])!.write(to: out)
