import AppKit
import CoreText

enum StatusIcon {
    static func mark() -> NSImage {
        draw(size: 18) { rect, scale in
            let container = rect.insetBy(dx: 1.15 * scale, dy: 1.15 * scale)
            let shape = NSBezierPath(
                roundedRect: container,
                xRadius: container.width * 0.2237,
                yRadius: container.width * 0.2237
            )
            NSColor.black.setFill()
            shape.fill()

            guard let ctx = NSGraphicsContext.current?.cgContext else { return }
            ctx.saveGState()
            ctx.setBlendMode(.destinationOut)
            NSColor.black.setFill()
            NSColor.black.setStroke()

            let fRect = CGRect(
                x: container.minX + container.width * 0.25,
                y: container.minY + container.height * 0.18,
                width: container.width * 0.33,
                height: container.height * 0.64
            )
            if let glyph = fGlyphPath(in: fRect) {
                glyph.fill()
            }

            let check = NSBezierPath()
            check.lineWidth = max(1.1 * scale, container.width * 0.085)
            check.lineCapStyle = .round
            check.lineJoinStyle = .round
            check.move(to: point(0.48, 0.52, in: container))
            check.line(to: point(0.60, 0.40, in: container))
            check.line(to: point(0.78, 0.64, in: container))
            check.stroke()
            ctx.restoreGState()
        }
    }

    static func check() -> NSImage {
        symbol("checkmark", pointSize: 13)
    }

    static func error() -> NSImage {
        symbol("exclamationmark.triangle", pointSize: 12)
    }

    private static func fGlyphPath(in rect: CGRect) -> NSBezierPath? {
        let font = CTFontCreateWithName("AvenirNext-Heavy" as CFString, 1000, nil)
        var character = UniChar(0x66)
        var glyph = CGGlyph()
        guard CTFontGetGlyphsForCharacters(font, &character, &glyph, 1),
              let path = CTFontCreatePathForGlyph(font, glyph, nil)
        else { return nil }
        let box = path.boundingBoxOfPath
        let fit = min(rect.width / box.width, rect.height / box.height)
        var transform = CGAffineTransform(translationX: -box.minX, y: -box.minY)
            .scaledBy(x: fit, y: fit)
            .concatenating(CGAffineTransform(
                translationX: rect.minX + (rect.width - box.width * fit) / 2,
                y: rect.minY + (rect.height - box.height * fit) / 2
            ))
        guard let fitted = path.copy(using: &transform) else { return nil }
        return NSBezierPath(cgPath: fitted)
    }

    private static func point(_ x: CGFloat, _ y: CGFloat, in rect: NSRect) -> NSPoint {
        NSPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
    }

    private static func symbol(_ name: String, pointSize: CGFloat) -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
        let image = NSImage(systemSymbolName: name, accessibilityDescription: name)?
            .withSymbolConfiguration(config) ?? NSImage(size: NSSize(width: 18, height: 18))
        image.isTemplate = true
        image.size = NSSize(width: 18, height: 18)
        return image
    }

    private static func draw(size: CGFloat, body: @escaping (NSRect, CGFloat) -> Void) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            body(rect, size / 18)
            return true
        }
        image.isTemplate = true
        return image
    }
}
