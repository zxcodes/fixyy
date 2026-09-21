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
    private var jobToken = UUID()

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
        startJob(as: .fixing) { coordinator in
            await coordinator.fix.run()
            if coordinator.phase == .fixing { coordinator.phase = .idle }
        }
    }

    public func handleRewrite() {
        startJob(as: .rewriting) { coordinator in
            await coordinator.card.cancelJobs()
            await coordinator.openRewrite()
        }
    }

    private func startJob(as phase: Phase, body: @escaping (JobCoordinator) async -> Void) {
        work?.cancel()
        let previous = work
        let token = UUID()
        jobToken = token
        self.phase = phase
        work = Task { [weak self] in
            guard let self else { return }
            await previous?.value
            guard !Task.isCancelled, self.jobToken == token else { return }
            await body(self)
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
        } catch is CancellationError {
            return
        } catch let error as AppError {
            guard let error = Self.rewriteError(from: error) else { return }
            card.present(sourceText: "", editable: false, promptTokens: nil)
            card.presentError(error)
        } catch {
            if Task.isCancelled { return }
            guard let error = Self.rewriteError(from: error) else { return }
            card.present(sourceText: "", editable: false, promptTokens: nil)
            card.presentError(error)
        }
    }

    nonisolated static func rewriteError(from error: Error) -> AppError? {
        if error is CancellationError { return nil }
        if let error = error as? AppError {
            return error == .cancelled ? nil : error
        }
        return .stalled
    }
}
