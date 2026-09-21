import AppKit

public enum KeyDisplay {
    public static let cmd: UInt32 = 256
    public static let option: UInt32 = 2048
    public static let control: UInt32 = 4096
    public static let shift: UInt32 = 512

    public static let keyNames: [UInt32: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 31: "O", 32: "U",
        34: "I", 35: "P", 37: "L", 38: "J", 40: "K", 45: "N", 46: "M",
        18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 25: "9", 26: "7", 28: "8", 29: "0",
        24: "=", 27: "-", 30: "]", 33: "[", 39: "'", 41: ";", 42: "\\", 43: ",", 44: "/", 47: ".", 50: "`",
        49: "Space", 36: "Return", 48: "Tab", 51: "Delete", 53: "Esc",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
    ]

    public static func string(keyCode: UInt32, modifiers: UInt32) -> String {
        modifierString(modifiers) + (keyNames[keyCode] ?? "·")
    }

    public static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= cmd }
        if flags.contains(.option) { modifiers |= option }
        if flags.contains(.control) { modifiers |= control }
        if flags.contains(.shift) { modifiers |= shift }
        return modifiers
    }

    private static func modifierString(_ modifiers: UInt32) -> String {
        var string = ""
        if modifiers & control != 0 { string += "⌃" }
        if modifiers & option != 0 { string += "⌥" }
        if modifiers & shift != 0 { string += "⇧" }
        if modifiers & cmd != 0 { string += "⌘" }
        return string
    }
}

public struct KeyShortcut: Codable, Equatable, Sendable {
    public var keyCode: UInt32
    public var modifiers: UInt32

    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public var display: String { KeyDisplay.string(keyCode: keyCode, modifiers: modifiers) }

    public static let fixDefault = KeyShortcut(keyCode: 5, modifiers: KeyDisplay.cmd | KeyDisplay.shift) // ⌘⇧G
    public static let rewriteDefault = KeyShortcut(keyCode: 15, modifiers: KeyDisplay.cmd | KeyDisplay.shift) // ⌘⇧R
}
