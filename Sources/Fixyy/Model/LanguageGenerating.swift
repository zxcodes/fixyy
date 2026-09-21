import Foundation

@MainActor
public protocol LanguageGenerating: AnyObject {
    var availability: ModelAvailability { get }
    func fixGrammar(text: String, styleNote: String) async throws -> FixResult
    func rewrite(
        text: String,
        kind: RewriteKind,
        styleNote: String,
        sampling: RewriteSampling
    ) -> AsyncThrowingStream<String, Error>
    func tokenCount(instructions: String, prompt: String) async -> Int?
    func prewarm()
}

public extension LanguageGenerating {
    func tokenCount(instructions: String, prompt: String) async -> Int? { nil }
    func prewarm() {}
}

@MainActor
public protocol SelectionHandling: AnyObject {
    var isTrusted: Bool { get }
    var isEditableField: Bool { get }
    func capture() async throws -> SelectionCapture
    func paste(_ text: String) async
    func undoLastPaste() async
    func leaveOnClipboard(_ text: String)
    func requestTrustPrompt()
    func reactivateSourceApp()
}

public extension SelectionHandling {
    var isEditableField: Bool { true }
    func undoLastPaste() async {}
    func reactivateSourceApp() {}
}

@MainActor
public protocol HUDPresenting: AnyObject {
    var undoVisible: Bool { get }
    func showWorking()
    func showFixed(diff: [TextDiff.Segment], undo: @escaping @MainActor () -> Void)
    func showUnchanged()
    func showCancelled()
    func showError(_ error: AppError, retry: (@MainActor () -> Void)?)
    func hide()
}

public extension HUDPresenting {
    var undoVisible: Bool { false }
    func showError(_ error: AppError) {
        showError(error, retry: nil)
    }
}
