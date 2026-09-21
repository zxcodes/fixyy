import AppKit
import ApplicationServices
import CoreGraphics

@MainActor
public final class SelectionIO: SelectionHandling {
    private let pasteboard = NSPasteboard.general
    private let source = CGEventSource(stateID: .privateState)
    private var previousApp: NSRunningApplication?

    public init() {}

    public var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    public func requestTrustPrompt() {
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        SettingsLinks.openAccessibility()
    }

    public func capture() async throws -> SelectionCapture {
        guard isTrusted else { throw AppError.accessibilityDenied }
        guard try await focusSourceAppIfNeeded() else { return .empty }
        if isSecureFieldFocused() { return .secure }

        let snapshot = PasteboardSnapshot(pasteboard: pasteboard)
        let sentinel = "fixyy.sentinel.\(UUID().uuidString)"
        pasteboard.clearContents()
        pasteboard.setString(sentinel, forType: .string)
        defer { snapshot.restore(to: pasteboard) }

        // Let the hotkey modifiers finish releasing.
        try await Task.sleep(for: .milliseconds(50))
        postCommand(virtualKey: 8) // C

        var text: String?
        for delay in [80, 120, 200] as [UInt64] {
            try await Task.sleep(for: .milliseconds(delay))
            let current = pasteboard.string(forType: .string) ?? ""
            if current != sentinel, !current.isEmpty {
                text = current
                break
            }
        }

        guard let text, !text.isEmpty else { return .empty }
        return .text(text)
    }

    public func paste(_ text: String) async {
        let snapshot = PasteboardSnapshot(pasteboard: pasteboard)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        defer { snapshot.restore(to: pasteboard) }
        previousApp?.activate()
        do {
            try await Task.sleep(for: .milliseconds(80))
            try Task.checkCancellation()
            postCommand(virtualKey: 9) // V
            try await Task.sleep(for: .milliseconds(350))
        } catch {
            return
        }
    }

    public func undoLastPaste() async {
        previousApp?.activate()
        try? await Task.sleep(for: .milliseconds(80))
        postCommand(virtualKey: 6) // Z
    }

    public func leaveOnClipboard(_ text: String) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    public func reactivateSourceApp() {
        previousApp?.activate()
    }

    public var isEditableField: Bool {
        guard let element = focusedElement() else { return true }
        var settable = DarwinBoolean(false)
        let selected = AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &settable)
        if selected == .success, settable.boolValue { return true }
        settable = DarwinBoolean(false)
        let value = AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable)
        if value == .success { return settable.boolValue }
        return true
    }

    private func focusSourceAppIfNeeded() async throws -> Bool {
        let front = NSWorkspace.shared.frontmostApplication
        if isOwnApp(front) {
            guard let source = previousApp, !isOwnApp(source) else { return false }
            source.activate()
            try await Task.sleep(for: .milliseconds(80))
            return true
        }
        previousApp = front
        return true
    }

    private func isOwnApp(_ app: NSRunningApplication?) -> Bool {
        guard let app else { return false }
        if app.processIdentifier == ProcessInfo.processInfo.processIdentifier { return true }
        if let mine = Bundle.main.bundleIdentifier, app.bundleIdentifier == mine { return true }
        return false
    }

    private func isSecureFieldFocused() -> Bool {
        guard let element = focusedElement() else { return false }
        if axString(element, kAXRoleAttribute as String) == "AXSecureTextField" { return true }
        if axString(element, kAXSubroleAttribute as String) == "AXSecureTextField" { return true }
        return false
    }

    private func axString(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }

    private func focusedElement() -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success else {
            return nil
        }
        return (focused as! AXUIElement)
    }

    private func postCommand(virtualKey: CGKeyCode) {
        let down = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: true)
        down?.flags = .maskCommand
        let up = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: false)
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}

public enum SettingsLinks {
    public static func openAccessibility() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    public static func openIntelligence() {
        if !open("x-apple.systempreferences:com.apple.Siri-Settings.extension") {
            open("x-apple.systempreferences:com.apple.preference.siri")
        }
    }

    @discardableResult
    private static func open(_ spec: String) -> Bool {
        guard let url = URL(string: spec) else { return false }
        return NSWorkspace.shared.open(url)
    }
}
