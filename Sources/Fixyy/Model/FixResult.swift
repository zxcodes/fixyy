import Foundation

/// Grammar-fix output. `hasChanges` is decided by comparing cleaned model text
/// to the original — not by `@Generable`. That macro’s plugin ships with full
/// Xcode, not Command Line Tools (same trap Handy / fm.cr hit).
public struct FixResult: Equatable, Sendable {
    public var hasChanges: Bool
    public var text: String

    public init(hasChanges: Bool, text: String) {
        self.hasChanges = hasChanges
        self.text = text
    }

    public static func from(original: String, modelOutput: String) -> FixResult {
        let cleaned = clean(modelOutput)
        let source = original.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty {
            return FixResult(hasChanges: false, text: original)
        }
        return FixResult(hasChanges: cleaned != source, text: cleaned)
    }

    public static func clean(_ string: String) -> String {
        var text = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.count >= 2, text.hasPrefix("\""), text.hasSuffix("\"") {
            text = String(text.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return stripEdgeWrappers(text)
    }

    private static func stripEdgeWrappers(_ string: String) -> String {
        var lines = string.components(separatedBy: "\n")
        var opened = false
        while let first = lines.first, isOpenWrapper(first) {
            lines.removeFirst()
            opened = true
        }
        if opened {
            while let last = lines.last, isCloseWrapper(last) {
                lines.removeLast()
            }
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isOpenWrapper(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.count >= 2 && trimmed.allSatisfy { $0 == "<" }
    }

    private static func isCloseWrapper(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.count >= 2 && trimmed.allSatisfy { $0 == ">" }
    }
}
