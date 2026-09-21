import Foundation

@MainActor
public final class FixService {
    private let model: LanguageGenerating
    private let selection: SelectionHandling
    private let prefs: Prefs
    private let hud: HUDPresenting
    private let budget: TokenBudget

    public var onJob: ((JobSummary) -> Void)?

    public init(
        model: LanguageGenerating,
        selection: SelectionHandling,
        prefs: Prefs,
        hud: HUDPresenting,
        budget: TokenBudget = TokenBudget(contextSize: 4096)
    ) {
        self.model = model
        self.selection = selection
        self.prefs = prefs
        self.hud = hud
        self.budget = budget
    }

    public func run() async {
        let start = ContinuousClock.now
        hud.showWorking()
        do {
            guard selection.isTrusted else { throw AppError.accessibilityDenied }
            if let availabilityError = model.availability.error { throw availabilityError }

            switch try await selection.capture() {
            case .empty:
                throw AppError.emptySelection
            case .secure:
                throw AppError.secureField
            case .text(let text):
                let instructions = Prompts.fixInstructions(styleNote: prefs.styleNote)
                var promptTokens: Int?
                switch await budget.fits(selection: text, instructions: instructions) {
                case .tooLong(let estimated, let fits):
                    throw AppError.tooLong(estimated: estimated, fits: fits)
                case .ok(let tokens):
                    promptTokens = tokens
                }
                let result = try await model.fixGrammar(text: text, styleNote: prefs.styleNote)
                try Task.checkCancellation()
                let latency = ContinuousClock.now - start
                let outputTokens = await model.tokenCount(instructions: "", prompt: result.text) ?? result.text.count / 4
                if result.hasChanges {
                    await selection.paste(result.text)
                    let original = text
                    let diff = TextDiff.segments(from: original, to: result.text)
                    hud.showFixed(diff: diff) { [weak self] in
                        self?.undo()
                    }
                    report(kind: .fix, promptTokens: promptTokens, outputTokens: outputTokens, latency: latency, outcome: .fixed)
                } else {
                    hud.showUnchanged()
                    report(kind: .fix, promptTokens: promptTokens, outputTokens: nil, latency: latency, outcome: .unchanged)
                }
            }
        } catch is CancellationError {
            hud.showCancelled()
        } catch let error as AppError where error == .cancelled {
            hud.showCancelled()
        } catch let error as AppError {
            present(error)
            report(kind: .fix, promptTokens: nil, outputTokens: nil, latency: ContinuousClock.now - start, outcome: .error(error))
        } catch {
            present(.stalled)
            report(kind: .fix, promptTokens: nil, outputTokens: nil, latency: ContinuousClock.now - start, outcome: .error(.stalled))
        }
    }

    public func undo() {
        guard hud.undoVisible else { return }
        Task { [weak self] in
            guard let self else { return }
            await self.selection.undoLastPaste()
            self.hud.hide()
        }
    }

    private func report(kind: JobSummary.Kind, promptTokens: Int?, outputTokens: Int?, latency: Duration, outcome: JobSummary.Outcome) {
        onJob?(JobSummary(
            kind: kind,
            promptTokens: promptTokens,
            outputTokens: outputTokens,
            latency: TimeInterval(latency.components.seconds) + TimeInterval(latency.components.attoseconds) / 1e18,
            outcome: outcome
        ))
    }

    private func present(_ error: AppError) {
        var retry: (@MainActor @Sendable () -> Void)?
        if error.action == .retry {
            retry = { @MainActor @Sendable [weak self] in
                _ = Task { await self?.run() }
            }
        }
        hud.showError(error, retry: retry)
        if error.opensAccessibilitySettings {
            selection.requestTrustPrompt()
        } else if error.opensIntelligenceSettings {
            SettingsLinks.openIntelligence()
        }
    }
}
