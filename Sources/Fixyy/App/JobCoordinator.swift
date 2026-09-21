import Foundation

@MainActor
public final class JobCoordinator {
    public enum Phase: Equatable {
        case idle
        case fixing
        case rewriting
    }

    public private(set) var phase: Phase = .idle
    public private(set) var lastJob: JobSummary?
    public var onJobCompleted: ((JobSummary) -> Void)?

    private let fix: FixService
    private let rewrite: RewriteService
    private let selection: SelectionHandling
    private let card: RewriteCardController
    private let budget: TokenBudget
    private var work: Task<Void, Never>?

    public init(
        fix: FixService,
        rewrite: RewriteService,
        selection: SelectionHandling,
        card: RewriteCardController,
        budget: TokenBudget = TokenBudget(contextSize: 4096)
    ) {
        self.fix = fix
        self.rewrite = rewrite
        self.selection = selection
        self.card = card
        self.budget = budget
        card.onDismiss = { [weak self] in
            self?.phase = .idle
        }
    }

    public func record(_ job: JobSummary) {
        lastJob = job
        onJobCompleted?(job)
    }

    public func handleFix() {
        if phase == .fixing {
            work?.cancel()
            phase = .idle
            return
        }
        if phase == .rewriting { return }
        work?.cancel()
        phase = .fixing
        work = Task { [weak self] in
            guard let self else { return }
            await self.fix.run()
            if self.phase == .fixing { self.phase = .idle }
        }
    }

    public func handleRewrite() {
        work?.cancel()
        phase = .rewriting
        work = Task { [weak self] in
            guard let self else { return }
            await self.openRewrite()
        }
    }

    private func openRewrite() async {
        if let error = rewrite.gate() {
            card.present(sourceText: "", editable: false, promptTokens: nil)
            card.presentError(error)
            if error == .accessibilityDenied { selection.requestTrustPrompt() }
            return
        }
        guard selection.isTrusted else {
            card.present(sourceText: "", editable: false, promptTokens: nil)
            card.presentError(.accessibilityDenied)
            selection.requestTrustPrompt()
            return
        }
        do {
            switch try await selection.capture() {
            case .empty:
                card.present(sourceText: "", editable: false, promptTokens: nil)
                card.presentError(.emptySelection)
            case .secure:
                card.present(sourceText: "", editable: false, promptTokens: nil)
                card.presentError(.secureField)
            case .text(let text):
                let instructions = rewrite.instructions
                var promptTokens: Int?
                switch await budget.fits(selection: text, instructions: instructions) {
                case .tooLong(let estimated, let fits):
                    card.present(sourceText: "", editable: false, promptTokens: nil)
                    card.presentError(.tooLong(estimated: estimated, fits: fits))
                    return
                case .ok(let tokens):
                    promptTokens = tokens
                }
                card.present(sourceText: text, editable: selection.isEditableField, promptTokens: promptTokens)
            }
        } catch let error as AppError {
            card.present(sourceText: "", editable: false, promptTokens: nil)
            card.presentError(error)
        } catch {
            card.present(sourceText: "", editable: false, promptTokens: nil)
            card.presentError(.stalled)
        }
    }
}
