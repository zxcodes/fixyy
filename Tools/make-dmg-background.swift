import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Compact Finder window art for the drag-to-Applications disk image.
let width = 500
let height = 300
let output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Packaging/dmg-background.png")

guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
      let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
else {
    fputs("Could not create graphics context\n", stderr)
    exit(1)
}

context.setFillColor(CGColor(srgbRed: 0.145, green: 0.145, blue: 0.153, alpha: 1))
context.fill(CGRect(x: 0, y: 0, width: width, height: height))

let arrowY = CGFloat(height) * 0.48
let startX = CGFloat(width) * 0.40
let endX = CGFloat(width) * 0.60
let shaft = CGFloat(height) * 0.012
let head = CGFloat(height) * 0.055

context.setStrokeColor(CGColor(srgbRed: 0.62, green: 0.62, blue: 0.66, alpha: 0.9))
context.setFillColor(CGColor(srgbRed: 0.62, green: 0.62, blue: 0.66, alpha: 0.9))
context.setLineWidth(shaft * 2)
context.setLineCap(.round)
context.move(to: CGPoint(x: startX, y: arrowY))
context.addLine(to: CGPoint(x: endX - head, y: arrowY))
context.strokePath()

let tip = CGMutablePath()
tip.move(to: CGPoint(x: endX - head * 1.15, y: arrowY - head))
tip.addLine(to: CGPoint(x: endX, y: arrowY))
tip.addLine(to: CGPoint(x: endX - head * 1.15, y: arrowY + head))
context.addPath(tip)
context.fillPath()

guard let image = context.makeImage() else {
    fputs("Could not create image\n", stderr)
    exit(1)
}

try FileManager.default.createDirectory(
    at: output.deletingLastPathComponent(),
    withIntermediateDirectories: true
)
guard let dest = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    fputs("Could not write \(output.path)\n", stderr)
    exit(1)
}
CGImageDestinationAddImage(dest, image, nil)
guard CGImageDestinationFinalize(dest) else {
    fputs("Could not finalize \(output.path)\n", stderr)
    exit(1)
}
print("Wrote \(output.path)")
