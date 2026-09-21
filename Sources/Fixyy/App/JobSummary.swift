import Foundation

public struct JobSummary: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case fix
        case rewrite
    }

    public enum Outcome: Equatable, Sendable {
        case fixed
        case unchanged
        case applied
        case copied
        case error(AppError)
    }

    public var kind: Kind
    public var promptTokens: Int?
    public var outputTokens: Int?
    public var latency: TimeInterval
    public var outcome: Outcome

    public init(kind: Kind, promptTokens: Int? = nil, outputTokens: Int? = nil, latency: TimeInterval, outcome: Outcome) {
        self.kind = kind
        self.promptTokens = promptTokens
        self.outputTokens = outputTokens
        self.latency = latency
        self.outcome = outcome
    }

    public var outcomeLabel: String {
        switch outcome {
        case .fixed: "Fixed"
        case .unchanged: "Looks good"
        case .applied: "Applied"
        case .copied: "Copied"
        case .error(let error): error.message.isEmpty ? "Error" : error.message
        }
    }

    public var menuLabel: String {
        var parts = [outcomeLabel]
        if let promptTokens {
            var tokens = promptTokens.formatted()
            if let outputTokens {
                tokens += "→\(outputTokens.formatted())"
            }
            parts.append("\(tokens) tok")
        }
        parts.append(String(format: "%.1f s", latency))
        return parts.joined(separator: " · ")
    }
}
