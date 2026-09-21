import AppKit

enum StatusIcon {
    static func mark() -> NSImage {
        draw(size: 18) { rect, scale in
            NSColor.black.setStroke()
            let container = NSBezierPath(
                roundedRect: rect.insetBy(dx: 1.25 * scale, dy: 1.25 * scale),
                xRadius: 4 * scale,
                yRadius: 4 * scale
            )
            container.lineWidth = 1.15 * scale
            container.stroke()

            let font = NSFont(name: "AvenirNext-Heavy", size: 10.25 * scale)
                ?? NSFont.systemFont(ofSize: 10.25 * scale, weight: .heavy)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.black,
            ]
            let text = "f" as NSString
            let size = text.size(withAttributes: attributes)
            let origin = NSPoint(
                x: rect.minX + 0.28 * rect.width,
                y: rect.midY - size.height * 0.36
            )
            text.draw(at: origin, withAttributes: attributes)

            let check = NSBezierPath()
            check.lineWidth = 1.15 * scale
            check.lineCapStyle = .round
            check.lineJoinStyle = .round
            check.move(to: point(0.51, 0.50, in: rect))
            check.line(to: point(0.61, 0.40, in: rect))
            check.line(to: point(0.77, 0.59, in: rect))
            check.stroke()
        }
    }

    static func check() -> NSImage {
        symbol("checkmark", pointSize: 13)
    }

    static func error() -> NSImage {
        symbol("exclamationmark.triangle", pointSize: 12)
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
