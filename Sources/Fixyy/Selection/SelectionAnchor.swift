import AppKit
import ApplicationServices

public enum SelectionAnchor {
    public static func rect() -> NSRect? {
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let element = focused
        else { return nil }

        var rangeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element as! AXUIElement,
            kAXSelectedTextRangeAttribute as CFString,
            &rangeValue
        ) == .success, let rangeValue else { return nil }

        var boundsValue: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element as! AXUIElement,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeValue,
            &boundsValue
        ) == .success, let boundsValue else { return nil }

        var rect = CGRect.zero
        guard AXValueGetValue(boundsValue as! AXValue, .cgRect, &rect) else { return nil }
        return toAppKit(rect)
    }

    public static func panelOrigin(width: CGFloat, height: CGFloat, gap: CGFloat = 8) -> NSPoint {
        let anchor = rect()
        let fallback = NSEvent.mouseLocation
        let anchorX = anchor?.midX ?? fallback.x
        let screen = screen(containing: anchor ?? NSRect(x: fallback.x, y: fallback.y, width: 0, height: 0))
            ?? NSScreen.main
            ?? NSScreen.screens.first
        let frame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)

        var x = anchorX - width / 2
        var y: CGFloat
        if let anchor {
            y = anchor.minY - gap - height
            if y < frame.minY + gap {
                y = anchor.maxY + gap
            }
        } else {
            y = fallback.y - gap - height
            if y < frame.minY + gap {
                y = fallback.y + gap
            }
        }
        x = min(max(x, frame.minX + 12), frame.maxX - width - 12)
        y = min(max(y, frame.minY + 12), frame.maxY - height - 12)
        return NSPoint(x: x, y: y)
    }

    private static func screen(containing rect: NSRect) -> NSScreen? {
        NSScreen.screens.first { $0.frame.intersects(rect) || $0.frame.contains(NSPoint(x: rect.midX, y: rect.midY)) }
    }

    private static func toAppKit(_ axRect: CGRect) -> NSRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return NSRect(
            x: axRect.origin.x,
            y: primaryHeight - axRect.origin.y - axRect.height,
            width: axRect.width,
            height: axRect.height
        )
    }
}
