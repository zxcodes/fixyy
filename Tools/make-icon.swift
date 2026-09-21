import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let packaging = root.appendingPathComponent("Packaging")
let candidates = packaging.appendingPathComponent("icon-candidates")
let iconset = packaging.appendingPathComponent("AppIcon.iconset")
let output = packaging.appendingPathComponent("AppIcon.icns")

let chosenVariant = 0

func point(_ x: CGFloat, _ y: CGFloat, in rect: CGRect) -> CGPoint {
    CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
}

func fGlyphPath(in rect: CGRect) -> CGPath? {
    let font = CTFontCreateWithName("AvenirNext-Heavy" as CFString, 1000, nil)
    var character = UniChar(0x66) // f
    var glyph = CGGlyph()
    guard CTFontGetGlyphsForCharacters(font, &character, &glyph, 1),
          let path = CTFontCreatePathForGlyph(font, glyph, nil)
    else { return nil }
    let box = path.boundingBoxOfPath
    let scale = min(rect.width / box.width, rect.height / box.height)
    let transform = CGAffineTransform(translationX: -box.minX, y: -box.minY)
        .scaledBy(x: scale, y: scale)
        .concatenating(CGAffineTransform(
            translationX: rect.minX + (rect.width - box.width * scale) / 2,
            y: rect.minY + (rect.height - box.height * scale) / 2
        ))
    var t = transform
    return path.copy(using: &t)
}

func checkPath(in rect: CGRect, variant: Int) -> CGPath {
    let path = CGMutablePath()
    switch variant {
    case 1:
        path.move(to: point(0.48, 0.48, in: rect))
        path.addLine(to: point(0.62, 0.62, in: rect))
        path.addLine(to: point(0.82, 0.32, in: rect))
    case 2:
        path.move(to: point(0.48, 0.48, in: rect))
        path.addLine(to: point(0.58, 0.58, in: rect))
        path.addLine(to: point(0.72, 0.42, in: rect))
    default:
        path.move(to: point(0.48, 0.48, in: rect))
        path.addLine(to: point(0.60, 0.60, in: rect))
        path.addLine(to: point(0.78, 0.36, in: rect))
    }
    return path
}

func render(size: Int, variant: Int) -> CGImage? {
    let side = CGFloat(size)
    guard let context = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    context.translateBy(x: 0, y: side)
    context.scaleBy(x: 1, y: -1)

    let bounds = CGRect(x: 0, y: 0, width: side, height: side)
    let inset = side * 0.02
    let iconRect = bounds.insetBy(dx: inset, dy: inset)
    let radius = iconRect.width * 0.2237
    let mask = CGPath(roundedRect: iconRect, cornerWidth: radius, cornerHeight: radius, transform: nil)

    context.saveGState()
    context.addPath(mask)
    context.clip()

    let gradient = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
        colors: [
            CGColor(srgbRed: 0.09, green: 0.13, blue: 0.40, alpha: 1),
            CGColor(srgbRed: 0.32, green: 0.27, blue: 0.80, alpha: 1),
        ] as CFArray,
        locations: [0, 1]
    )!
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: iconRect.midX, y: iconRect.maxY),
        end: CGPoint(x: iconRect.midX, y: iconRect.minY),
        options: []
    )

    let highlight = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
        colors: [
            CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.16),
            CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0),
        ] as CFArray,
        locations: [0, 1]
    )!
    context.drawLinearGradient(
        highlight,
        start: CGPoint(x: iconRect.midX, y: iconRect.maxY),
        end: CGPoint(x: iconRect.midX, y: iconRect.maxY - iconRect.height * 0.45),
        options: []
    )

    let shadow = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
        colors: [
            CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0),
            CGColor(srgbRed: 0, green: 0, blue: 0.1, alpha: 0.18),
        ] as CFArray,
        locations: [0, 1]
    )!
    context.drawLinearGradient(
        shadow,
        start: CGPoint(x: iconRect.midX, y: iconRect.minY + iconRect.height * 0.30),
        end: CGPoint(x: iconRect.midX, y: iconRect.minY),
        options: []
    )

    let fRect = CGRect(
        x: iconRect.minX + iconRect.width * 0.25,
        y: iconRect.minY + iconRect.height * 0.18,
        width: iconRect.width * 0.33,
        height: iconRect.height * 0.64
    )
    if let glyph = fGlyphPath(in: fRect) {
        var upright = CGAffineTransform(
            a: 1,
            b: 0,
            c: 0,
            d: -1,
            tx: 0,
            ty: fRect.minY + fRect.maxY
        )
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.addPath(glyph.copy(using: &upright) ?? glyph)
        context.fillPath()
    }
    context.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
    context.setLineWidth(iconRect.width * 0.085)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.addPath(checkPath(in: iconRect, variant: variant))
    context.strokePath()

    context.restoreGState()
    return context.makeImage()
}

func writePNG(_ image: CGImage, to url: URL) throws {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw CocoaError(.fileWriteUnknown)
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw CocoaError(.fileWriteUnknown)
    }
}

try FileManager.default.createDirectory(at: candidates, withIntermediateDirectories: true)
for variant in 0..<3 {
    guard let image = render(size: 512, variant: variant) else {
        fatalError("failed to render variant \(variant)")
    }
    try writePNG(image, to: candidates.appendingPathComponent("candidate-\(variant).png"))
}
print("wrote 3 candidates to \(candidates.path)")

try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

let sizes: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]
for (name, pixels) in sizes {
    guard let image = render(size: pixels, variant: chosenVariant) else {
        fatalError("failed to render \(name)")
    }
    try writePNG(image, to: iconset.appendingPathComponent(name))
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else {
    fatalError("iconutil failed with status \(process.terminationStatus)")
}
try? FileManager.default.removeItem(at: iconset)
print("wrote \(output.path) (variant \(chosenVariant))")
