import AppKit
import SwiftUI

final class ShortcutRecorderView: NSView {
    var shortcut: KeyShortcut {
        didSet { needsDisplay = true }
    }
    var onCommit: (KeyShortcut?) -> Void

    private(set) var recording = false {
        didSet { needsDisplay = true }
    }

    init(shortcut: KeyShortcut, onCommit: @escaping (KeyShortcut?) -> Void) {
        self.shortcut = shortcut
        self.onCommit = onCommit
        super.init(frame: NSRect(x: 0, y: 0, width: 120, height: 24))
    }

    required init?(coder: NSCoder) { nil }

    override var acceptsFirstResponder: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 120, height: 24) }

    override func mouseDown(with event: NSEvent) {
        recording = true
        window?.makeFirstResponder(self)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard recording else { return super.performKeyEquivalent(with: event) }
        return interpretRecordedKey(event)
    }

    override func keyDown(with event: NSEvent) {
        guard recording else {
            super.keyDown(with: event)
            return
        }
        _ = interpretRecordedKey(event)
    }

    @discardableResult
    private func interpretRecordedKey(_ event: NSEvent) -> Bool {
        if event.keyCode == 53 {
            cancelRecording()
            return true
        }
        if event.keyCode == 51 {
            let modifiers = KeyDisplay.carbonModifiers(from: event.modifierFlags)
            if modifiers == 0 {
                finish(committing: nil)
            } else {
                finish(committing: KeyShortcut(keyCode: UInt32(event.keyCode), modifiers: modifiers))
            }
            return true
        }
        let modifiers = KeyDisplay.carbonModifiers(from: event.modifierFlags)
        guard modifiers != 0 else { return true }
        finish(committing: KeyShortcut(keyCode: UInt32(event.keyCode), modifiers: modifiers))
        return true
    }

    override func resignFirstResponder() -> Bool {
        if recording { cancelRecording() }
        return super.resignFirstResponder()
    }

    private func finish(committing shortcut: KeyShortcut?) {
        recording = false
        window?.makeFirstResponder(nil)
        onCommit(shortcut)
    }

    private func cancelRecording() {
        recording = false
        window?.makeFirstResponder(nil)
    }

    override func draw(_ dirtyRect: NSRect) {
        let bounds = self.bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6)
        (recording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        path.lineWidth = recording ? 1.5 : 1
        path.stroke()

        let text = recording ? "Type shortcut" : shortcut.display
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: recording ? NSColor.secondaryLabelColor : NSColor.labelColor,
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        let origin = NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2)
        (text as NSString).draw(at: origin, withAttributes: attributes)
    }
}

struct ShortcutRecorder: NSViewRepresentable {
    let shortcut: KeyShortcut
    let onCommit: (KeyShortcut?) -> Void

    func makeNSView(context: Context) -> ShortcutRecorderView {
        ShortcutRecorderView(shortcut: shortcut, onCommit: onCommit)
    }

    func updateNSView(_ view: ShortcutRecorderView, context: Context) {
        view.shortcut = shortcut
        view.onCommit = onCommit
    }
}
