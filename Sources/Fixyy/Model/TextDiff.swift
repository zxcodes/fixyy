import Foundation

public enum TextDiff {
    public enum Segment: Equatable, Sendable {
        case equal(String)
        case inserted(String)
        case removed(String)

        public var text: String {
            switch self {
            case .equal(let text), .inserted(let text), .removed(let text): text
            }
        }
    }

    public static func segments(from old: String, to new: String) -> [Segment] {
        let oldTokens = tokenize(old)
        let newTokens = tokenize(new)
        if oldTokens == newTokens {
            return new.isEmpty ? [] : [.equal(new)]
        }
        if oldTokens.isEmpty { return [.inserted(joined(newTokens))] }
        if newTokens.isEmpty { return [.removed(joined(oldTokens))] }

        let diff = newTokens.difference(from: oldTokens)
        var removedOffsets = Set<Int>()
        var insertedByOffset: [Int: [String]] = [:]
        for change in diff {
            switch change {
            case .remove(let offset, _, _):
                removedOffsets.insert(offset)
            case .insert(let offset, let element, _):
                insertedByOffset[offset, default: []].append(element)
            }
        }

        var segments: [Segment] = []
        var newIndex = 0
        for oldIndex in oldTokens.indices {
            if removedOffsets.contains(oldIndex) {
                append(&segments, kind: .removed, token: oldTokens[oldIndex])
                continue
            }
            while let inserted = insertedByOffset[newIndex] {
                for token in inserted { append(&segments, kind: .inserted, token: token) }
                insertedByOffset[newIndex] = nil
                newIndex += 1
            }
            append(&segments, kind: .equal, token: oldTokens[oldIndex])
            newIndex += 1
        }
        while newIndex < newTokens.count {
            if let inserted = insertedByOffset[newIndex] {
                for token in inserted { append(&segments, kind: .inserted, token: token) }
                insertedByOffset[newIndex] = nil
            } else {
                append(&segments, kind: .equal, token: newTokens[newIndex])
            }
            newIndex += 1
        }
        return segments
    }

    private enum Kind {
        case equal, inserted, removed
    }

    private static func append(_ segments: inout [Segment], kind: Kind, token: String) {
        switch (segments.last, kind) {
        case (.equal(let text), .equal):
            segments[segments.count - 1] = .equal(text + " " + token)
        case (.inserted(let text), .inserted):
            segments[segments.count - 1] = .inserted(text + " " + token)
        case (.removed(let text), .removed):
            segments[segments.count - 1] = .removed(text + " " + token)
        default:
            switch kind {
            case .equal: segments.append(.equal(token))
            case .inserted: segments.append(.inserted(token))
            case .removed: segments.append(.removed(token))
            }
        }
    }

    private static func tokenize(_ text: String) -> [String] {
        text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    private static func joined(_ tokens: [String]) -> String {
        tokens.joined(separator: " ")
    }
}
