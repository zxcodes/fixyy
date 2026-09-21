import Foundation

public struct TokenBudget: @unchecked Sendable {
    public enum Verdict: Equatable, Sendable {
        case ok(promptTokens: Int)
        case tooLong(estimated: Int, fits: Int)
    }

    public var contextSize: Int
    public var countTokens: (String) async -> Int?

    public init(contextSize: Int, countTokens: @escaping (String) async -> Int? = { _ in nil }) {
        self.contextSize = contextSize
        self.countTokens = countTokens
    }

    public func fits(selection: String, instructions: String) async -> Verdict {
        if let instructionTokens = await countTokens(instructions),
           let selectionTokens = await countTokens(selection) {
            let outputReserve = max(256, Int((Double(selectionTokens) * 1.3).rounded(.up)))
            let fits = contextSize - instructionTokens - outputReserve
            if selectionTokens > fits {
                return .tooLong(estimated: selectionTokens, fits: fits)
            }
            return .ok(promptTokens: instructionTokens + selectionTokens)
        }
        let estimated = selection.count / 4
        let fallbackFits = selectionCharacterLimit / 4
        if selection.count > selectionCharacterLimit {
            return .tooLong(estimated: estimated, fits: fallbackFits)
        }
        return .ok(promptTokens: estimated + instructions.count / 4)
    }
}
