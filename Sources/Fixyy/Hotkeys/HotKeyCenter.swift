import Carbon
import Foundation

/// Global hotkeys via Carbon. Works while Fixyy is a menu-bar agent.
public final class HotKeyCenter: @unchecked Sendable {
    public static let shared = HotKeyCenter()

    private var handlers: [UInt32: @MainActor () -> Void] = [:]
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var nextID: UInt32 = 1
    private var installed = false
    private let lock = NSLock()

    @discardableResult
    public func register(keyCode: UInt32, modifiers: UInt32, action: @escaping @MainActor () -> Void) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        installHandlerIfNeeded()
        let id = nextID
        nextID += 1
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: fourCharCode("FIXY"), id: id)
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetEventDispatcherTarget(), 0, &ref)
        guard status == noErr, let ref else { return false }
        handlers[id] = action
        refs[id] = ref
        return true
    }

    public func unregisterAll() {
        lock.lock()
        defer { lock.unlock() }
        for ref in refs.values { UnregisterEventHotKey(ref) }
        refs.removeAll()
        handlers.removeAll()
        nextID = 1
    }

    fileprivate func fire(_ id: UInt32) {
        lock.lock()
        let action = handlers[id]
        lock.unlock()
        if let action {
            DispatchQueue.main.async { action() }
        }
    }

    private func installHandlerIfNeeded() {
        guard !installed else { return }
        installed = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetEventDispatcherTarget(), hotKeyHandler, 1, &spec, nil, nil)
    }
}

private func fourCharCode(_ string: String) -> OSType {
    var result: OSType = 0
    for ch in string.utf8.prefix(4) { result = (result << 8) + OSType(ch) }
    return result
}

private func hotKeyHandler(
    _ next: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    var hkID = EventHotKeyID()
    let err = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hkID
    )
    if err == noErr {
        HotKeyCenter.shared.fire(hkID.id)
    }
    return noErr
}
