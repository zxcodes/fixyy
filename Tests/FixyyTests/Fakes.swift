import Foundation
@testable import FixyyCore

@MainActor
final class FakeModel: LanguageGenerating {
    var availability: ModelAvailability = .available
    var lastStyleNote: String?
    var lastFixText: String?
    var lastRewriteKind: RewriteKind?
    var fixDelayNanoseconds: UInt64 = 0
    var fixHandler: @MainActor (String, String) throws -> FixResult = { text, _ in
        FixResult(hasChanges: true, text: "fixed:\(text)")
    }
    var rewritePartials: [String] = []
    var rewriteError: Error?
    var lastSampling: RewriteSampling?
    var tokenCounts: Int?
    var prewarmed = false

    func fixGrammar(text: String, styleNote: String) async throws -> FixResult {
        lastFixText = text
        lastStyleNote = styleNote
        if fixDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: fixDelayNanoseconds)
        }
        try Task.checkCancellation()
        return try fixHandler(text, styleNote)
    }

    func rewrite(
        text: String,
        kind: RewriteKind,
        styleNote: String,
        sampling: RewriteSampling
    ) -> AsyncThrowingStream<String, Error> {
        lastRewriteKind = kind
        lastStyleNote = styleNote
        lastSampling = sampling
        let partials = rewritePartials.isEmpty ? ["rewritten:\(text)"] : rewritePartials
        let error = rewriteError
        return AsyncThrowingStream { continuation in
            let task = Task {
                for partial in partials {
                    if Task.isCancelled {
                        continuation.finish()
                        return
                    }
                    continuation.yield(partial)
                    try? await Task.sleep(nanoseconds: 5_000_000)
                }
                if let error {
                    continuation.finish(throwing: error)
                } else {
                    continuation.finish()
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func tokenCount(instructions: String, prompt: String) async -> Int? {
        tokenCounts
    }

    func prewarm() {
        prewarmed = true
    }
}

@MainActor
final class FakeSelection: SelectionHandling {
    var isTrusted = true
    var captureResult: SelectionCapture = .text("he go store")
    var pasted: [String] = []
    var undoCalls = 0
    var clipboard: String?
    var trustPrompts = 0
    var captureDelayNanoseconds: UInt64 = 0
    var captureCalls = 0

    func capture() async throws -> SelectionCapture {
        captureCalls += 1
        if captureDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: captureDelayNanoseconds)
        }
        try Task.checkCancellation()
        return captureResult
    }
    func paste(_ text: String) async { pasted.append(text) }
    func undoLastPaste() async { undoCalls += 1 }
    func leaveOnClipboard(_ text: String) { clipboard = text }
    func requestTrustPrompt() { trustPrompts += 1 }
}

@MainActor
final class HUDSpy: HUDPresenting {
    var events: [String] = []

    func showWorking() { events.append("working") }
    func showFixed() { events.append("fixed") }
    func showUnchanged() { events.append("unchanged") }
    func showCancelled() { events.append("cancelled") }
    func showError(_ error: AppError, retry: (@MainActor () -> Void)?) {
        events.append("error:\(error)")
        if retry != nil { events.append("retry") }
    }
    func hide() { events.append("hide") }
}
