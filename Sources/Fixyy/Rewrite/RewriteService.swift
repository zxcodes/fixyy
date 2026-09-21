import Foundation

@MainActor
public final class RewriteService {
    private let model: LanguageGenerating
    private let prefs: Prefs

    public init(model: LanguageGenerating, prefs: Prefs) {
        self.model = model
        self.prefs = prefs
    }

    public func gate() -> AppError? {
        model.availability.error
    }

    public var instructions: String {
        Prompts.rewriteInstructions(styleNote: prefs.styleNote)
    }

    public func stream(
        text: String,
        kind: RewriteKind,
        sampling: RewriteSampling = .automatic
    ) -> AsyncThrowingStream<String, Error> {
        if text.count > selectionCharacterLimit {
            return AsyncThrowingStream {
                $0.finish(throwing: AppError.tooLong(estimated: text.count / 4, fits: selectionCharacterLimit / 4))
            }
        }
        if case .custom(let line) = kind, line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return AsyncThrowingStream { $0.finish(throwing: AppError.stalled) }
        }
        return model.rewrite(
            text: text,
            kind: kind,
            styleNote: prefs.styleNote,
            sampling: sampling
        )
    }
}
