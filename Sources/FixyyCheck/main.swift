import AppKit
import Foundation
import FoundationModels
import FixyyCore

/// Service checks without XCTest. `swift test` on this machine mixes Xcode 16’s
/// XCTest with CLT 27’s Testing.framework and dies at dlopen.
@main
enum FixyyCheck {
    static func main() async {
        var failures = 0
        failures += await unchangedDoesNotPaste()
        failures += await changedPastes()
        failures += await errorDoesNotPaste()
        failures += await retryClosureOnlyForRetryable()
        failures += await emptySelection()
        failures += await tooLong()
        failures += await cancelDoesNotPaste()
        failures += await undoInvokesHostUndo()
        failures += await rewriteStreamsPartials()
        failures += await rewriteCancelStopsStream()
        failures += prompts()
        failures += fixResult()
        failures += pasteboard()
        failures += textDiff()
        failures += await tokenBudget()
        failures += statusLine()
        failures += errorMapping()
        if failures > 0 {
            fputs("\(failures) check(s) failed\n", stderr)
            exit(1)
        }
        print("All checks passed")
    }

    static func unchangedDoesNotPaste() async -> Int {
        let ctx = await MainActor.run { () -> Ctx in
            let ctx = Ctx()
            ctx.model.fixHandler = { text, _ in FixResult(hasChanges: false, text: "DIFFERENT \(text)") }
            return ctx
        }
        await ctx.service.run()
        return await MainActor.run {
            expect(ctx.selection.pasted.isEmpty, "unchanged must not paste")
                + expect(ctx.hud.events.contains("unchanged"), "unchanged HUD")
        }
    }

    static func changedPastes() async -> Int {
        let ctx = await MainActor.run { () -> Ctx in
            let ctx = Ctx()
            ctx.model.fixHandler = { _, _ in FixResult(hasChanges: true, text: "He goes to the store.") }
            return ctx
        }
        await ctx.service.run()
        return await MainActor.run {
            expect(ctx.selection.pasted == ["He goes to the store."], "paste corrected text")
                + expect(ctx.hud.events.contains("fixed"), "fixed HUD")
        }
    }

    static func errorDoesNotPaste() async -> Int {
        let ctx = await MainActor.run { () -> Ctx in
            let ctx = Ctx()
            ctx.model.fixHandler = { _, _ in throw AppError.guardrail }
            return ctx
        }
        await ctx.service.run()
        return await MainActor.run {
            expect(ctx.selection.pasted.isEmpty, "error must not paste")
                + expect(ctx.hud.events.contains("error:guardrail"), "guardrail HUD")
        }
    }

    static func retryClosureOnlyForRetryable() async -> Int {
        let retryable = await MainActor.run { () -> Ctx in
            let ctx = Ctx()
            ctx.model.fixHandler = { _, _ in throw AppError.stalled }
            return ctx
        }
        await retryable.service.run()
        let plain = await MainActor.run { () -> Ctx in
            let ctx = Ctx()
            ctx.model.fixHandler = { _, _ in throw AppError.guardrail }
            return ctx
        }
        await plain.service.run()
        return await MainActor.run {
            expect(retryable.hud.events.contains("error:stalled") && retryable.hud.events.contains("retry"), "stalled error carries retry")
                + expect(plain.hud.events.contains("error:guardrail") && !plain.hud.events.contains("retry"), "guardrail has no retry")
        }
    }

    static func emptySelection() async -> Int {
        let ctx = await MainActor.run { () -> Ctx in
            let ctx = Ctx()
            ctx.selection.captureResult = .empty
            return ctx
        }
        await ctx.service.run()
        return await MainActor.run {
            expect(ctx.selection.pasted.isEmpty, "empty must not paste")
                + expect(ctx.hud.events.contains("error:emptySelection"), "empty HUD")
        }
    }

    static func tooLong() async -> Int {
        let ctx = await MainActor.run { () -> Ctx in
            let ctx = Ctx()
            ctx.selection.captureResult = .text(String(repeating: "a", count: selectionCharacterLimit + 1))
            return ctx
        }
        await ctx.service.run()
        return await MainActor.run {
            expect(ctx.model.lastFixText == nil, "too long must not call model")
                + expect(ctx.hud.events.contains { $0.hasPrefix("error:tooLong") }, "too-long HUD")
        }
    }

    static func cancelDoesNotPaste() async -> Int {
        let ctx = await MainActor.run { () -> Ctx in
            let ctx = Ctx()
            ctx.model.fixDelayNanoseconds = 2_000_000_000
            ctx.model.fixHandler = { _, _ in FixResult(hasChanges: true, text: "should not paste") }
            return ctx
        }
        let task = Task { await ctx.service.run() }
        try? await Task.sleep(nanoseconds: 100_000_000)
        task.cancel()
        await task.value
        return await MainActor.run {
            expect(ctx.selection.pasted.isEmpty, "cancel must not paste")
                + expect(ctx.hud.events.contains("cancelled"), "cancelled HUD")
        }
    }

    static func undoInvokesHostUndo() async -> Int {
        let ctx = await MainActor.run { () -> Ctx in
            let ctx = Ctx()
            ctx.model.fixHandler = { _, _ in FixResult(hasChanges: true, text: "He goes to the store.") }
            return ctx
        }
        await ctx.service.run()
        await MainActor.run { ctx.service.undo() }
        try? await Task.sleep(nanoseconds: 200_000_000)
        return await MainActor.run {
            expect(ctx.selection.undoCalls == 1, "undo uses host-app undo")
                + expect(ctx.selection.pasted == ["He goes to the store."], "undo does not re-paste")
                + expect(ctx.hud.events.contains("hide"), "undo hides HUD")
        }
    }

    static func rewriteStreamsPartials() async -> Int {
        let (service, model) = await MainActor.run { () -> (RewriteService, FakeModel) in
            let model = FakeModel()
            model.rewritePartials = ["a", "a b", "a b c"]
            let prefs = Prefs(defaults: UserDefaults(suiteName: "fixyy.check.\(UUID().uuidString)")!)
            return (RewriteService(model: model, prefs: prefs), model)
        }
        var collected: [String] = []
        do {
            for try await partial in await service.stream(text: "x", kind: .shorter) {
                collected.append(partial)
            }
        } catch {
            return expect(false, "stream threw \(error)")
        }
        let sampling = await MainActor.run { model.lastSampling }
        return expect(collected == ["a", "a b", "a b c"], "partials arrive in order, cumulative")
            + expect(sampling == .automatic, "first run uses automatic sampling")
    }

    static func rewriteCancelStopsStream() async -> Int {
        let (service, model) = await MainActor.run { () -> (RewriteService, FakeModel) in
            let model = FakeModel()
            model.rewritePartials = (0..<100).map { "partial \($0)" }
            let prefs = Prefs(defaults: UserDefaults(suiteName: "fixyy.check.\(UUID().uuidString)")!)
            return (RewriteService(model: model, prefs: prefs), model)
        }
        var seen = 0
        do {
            for try await _ in await service.stream(text: "x", kind: .clearer) {
                seen += 1
                if seen == 1 { break }
            }
        } catch {}
        try? await Task.sleep(nanoseconds: 300_000_000)
        let cancelled = await MainActor.run { model.rewriteSawCancel }
        return expect(seen == 1, "consumer sees only first partial")
            + expect(cancelled, "cancel stops the stream")
    }

    static func prompts() -> Int {
        let note = "British English, no em dashes."
        let instructions = Prompts.fixInstructions(styleNote: note)
        let prompt = Prompts.fixPrompt("he go store")
        let friendly = Prompts.rewritePrompt("hi", kind: .friendly)
        return expect(instructions.contains(note), "style note in instructions")
            + expect(!prompt.contains(note), "style note not in prompt")
            + expect(prompt.contains("he go store"), "selection in prompt")
            + expect(friendly.contains("warmer and more conversational"), "friendly prompt")
    }

    static func fixResult() -> Int {
        let same = FixResult.from(original: "Hello.", modelOutput: "Hello.")
        let diff = FixResult.from(original: "he go", modelOutput: "He goes.")
        let quoted = FixResult.from(original: "Hi", modelOutput: "\"Hi\"")
        return expect(!same.hasChanges, "identical is no change")
            + expect(diff.hasChanges, "different is a change")
            + expect(!quoted.hasChanges, "quoted unwrap")
    }

    static func pasteboard() -> Int {
        let board = NSPasteboard.withUniqueName()
        board.clearContents()
        board.setString("original", forType: .string)
        let snapshot = PasteboardSnapshot(pasteboard: board)
        board.clearContents()
        board.setString("sentinel", forType: .string)
        snapshot.restore(to: board)
        return expect(board.string(forType: .string) == "original", "pasteboard restore")
    }

    static func textDiff() -> Int {
        let identical = TextDiff.segments(from: "a b c", to: "a b c")
        let substitution = TextDiff.segments(from: "he go store", to: "he went store")
        let insertion = TextDiff.segments(from: "a b", to: "a b c")
        let rewrite = TextDiff.segments(from: "a b", to: "x y z")
        let merge = TextDiff.segments(from: "a x y b", to: "a b")
        return expect(identical == [.equal("a b c")], "identical is one equal segment")
            + expect(substitution == [.equal("he"), .removed("go"), .inserted("went"), .equal("store")], "substitution")
            + expect(insertion == [.equal("a b"), .inserted("c")], "insertion at end")
            + expect(rewrite == [.removed("a b"), .inserted("x y z")], "full rewrite")
            + expect(merge == [.equal("a"), .removed("x y"), .equal("b")], "adjacent removed tokens merge")
    }

    static func tokenBudget() async -> Int {
        let counting = TokenBudget(contextSize: 8192) { text in text.count }
        let ok = await counting.fits(selection: "one hundred chars", instructions: "instr")
        let long = TokenBudget(contextSize: 8192) { _ in 10_000 }
        let tooLong = await long.fits(selection: "big", instructions: "i")
        let fallback = TokenBudget(contextSize: 8192)
        let fallbackOk = await fallback.fits(selection: "short", instructions: "i")
        let fallbackLong = await fallback.fits(
            selection: String(repeating: "a", count: selectionCharacterLimit + 1),
            instructions: "i"
        )
        var failures = 0
        if case .ok(let tokens) = ok {
            failures += expect(tokens == "one hundred chars".count + "instr".count, "ok carries prompt tokens")
        } else {
            failures += expect(false, "small selection should fit")
        }
        if case .tooLong(let estimated, let fits) = tooLong {
            failures += expect(estimated == 10_000 && fits < 10_000, "tooLong carries estimate and fits")
        } else {
            failures += expect(false, "oversized selection should be tooLong")
        }
        if case .ok = fallbackOk {} else { failures += expect(false, "fallback ok") }
        if case .tooLong(let estimated, let fits) = fallbackLong {
            failures += expect(estimated == (selectionCharacterLimit + 1) / 4 && fits == selectionCharacterLimit / 4, "fallback tooLong")
        } else {
            failures += expect(false, "fallback long selection should be tooLong")
        }
        return failures
    }

    static func statusLine() -> Int {
        let ready = ModelInfo.statusLine(availability: .available, variantName: "Core 3", contextSize: 8192)
        let off = ModelInfo.statusLine(availability: .intelligenceOff, variantName: "Core 3", contextSize: 8192)
        let downloading = ModelInfo.statusLine(availability: .modelNotReady, variantName: "Core 3", contextSize: 8192)
        return expect(ready == "Core 3 · On-device · 8,192 ctx", "statusLine available")
            + expect(off == "Unavailable · Apple Intelligence is off", "statusLine off")
            + expect(downloading.hasPrefix("Unavailable ·"), "statusLine downloading")
    }

    static func errorMapping() -> Int {
        var failures = 0
        failures += expect(ModelClient.map(CancellationError()) == .cancelled, "cancel maps")
        failures += expect(ModelClient.map(AppError.guardrail) == .guardrail, "AppError passthrough")
        failures += expect(ModelClient.map(NSError(domain: "x", code: 1)) == .stalled, "unknown maps to stalled")

        let ctx = LanguageModelSession.GenerationError.Context(debugDescription: "x")
        let refusal = LanguageModelSession.GenerationError.Refusal(transcriptEntries: [])
        failures += expect(ModelClient.map(LanguageModelSession.GenerationError.exceededContextWindowSize(ctx)) == .tooLong(estimated: nil, fits: 4096), "exceededContextWindowSize")
        failures += expect(ModelClient.map(LanguageModelSession.GenerationError.guardrailViolation(ctx)) == .guardrail, "guardrailViolation")
        failures += expect(ModelClient.map(LanguageModelSession.GenerationError.refusal(refusal, ctx)) == .refusal, "refusal")
        failures += expect(ModelClient.map(LanguageModelSession.GenerationError.rateLimited(ctx)) == .rateLimited, "rateLimited")
        failures += expect(ModelClient.map(LanguageModelSession.GenerationError.concurrentRequests(ctx)) == .rateLimited, "concurrentRequests")
        failures += expect(ModelClient.map(LanguageModelSession.GenerationError.unsupportedLanguageOrLocale(ctx)) == .unsupportedLanguage, "unsupportedLanguageOrLocale")
        failures += expect(ModelClient.map(LanguageModelSession.GenerationError.assetsUnavailable(ctx)) == .modelDownloading, "assetsUnavailable")
        failures += expect(ModelClient.map(LanguageModelSession.GenerationError.decodingFailure(ctx)) == .stalled, "decodingFailure")
        failures += expect(ModelClient.map(LanguageModelSession.GenerationError.unsupportedGuide(ctx)) == .stalled, "unsupportedGuide")

        if #available(macOS 27.0, *) {
            failures += expect(
                ModelClient.map(LanguageModelError.contextSizeExceeded(.init(contextSize: 8192, tokenCount: 9000, debugDescription: "x"))) == .tooLong(estimated: nil, fits: 8192),
                "LanguageModelError.contextSizeExceeded"
            )
            failures += expect(
                ModelClient.map(LanguageModelError.guardrailViolation(.init(debugDescription: "x"))) == .guardrail,
                "LanguageModelError.guardrailViolation"
            )
            failures += expect(
                ModelClient.map(LanguageModelError.refusal(.init(explanation: "x", debugDescription: "x"))) == .refusal,
                "LanguageModelError.refusal"
            )
            failures += expect(
                ModelClient.map(LanguageModelError.rateLimited(.init(resetDate: nil, debugDescription: "x"))) == .rateLimited,
                "LanguageModelError.rateLimited"
            )
            failures += expect(
                ModelClient.map(LanguageModelSession.Error.concurrentRequests) == .rateLimited,
                "LanguageModelSession.Error.concurrentRequests"
            )
            failures += expect(
                ModelClient.map(SystemLanguageModel.Error.assetsUnavailable(.init(debugDescription: "x"))) == .modelDownloading,
                "SystemLanguageModel.Error.assetsUnavailable"
            )
        }
        return failures
    }
}

@MainActor
final class Ctx {
    let model = FakeModel()
    let selection = FakeSelection()
    let hud = HUDSpy()
    let service: FixService

    init() {
        let prefs = Prefs(defaults: UserDefaults(suiteName: "fixyy.check.\(UUID().uuidString)")!)
        service = FixService(model: model, selection: selection, prefs: prefs, hud: hud)
    }
}

@MainActor
final class FakeModel: LanguageGenerating {
    var availability: ModelAvailability = .available
    var lastFixText: String?
    var fixDelayNanoseconds: UInt64 = 0
    var fixHandler: @MainActor (String, String) throws -> FixResult = { text, _ in
        FixResult(hasChanges: true, text: "fixed:\(text)")
    }
    var rewritePartials: [String] = []
    var rewriteError: Error?
    var rewriteSawCancel = false
    var lastSampling: RewriteSampling?
    var tokenCounts: Int?
    var prewarmed = false

    func fixGrammar(text: String, styleNote: String) async throws -> FixResult {
        lastFixText = text
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
        lastSampling = sampling
        let partials = rewritePartials
        let error = rewriteError
        return AsyncThrowingStream { [weak self] continuation in
            let task = Task { [weak self] in
                for partial in partials {
                    if Task.isCancelled {
                        self?.rewriteSawCancel = true
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
    func capture() async throws -> SelectionCapture { captureResult }
    func paste(_ text: String) async { pasted.append(text) }
    func undoLastPaste() async { undoCalls += 1 }
    func leaveOnClipboard(_ text: String) {}
    func requestTrustPrompt() {}
}

@MainActor
final class HUDSpy: HUDPresenting {
    var events: [String] = []
    var undoVisible = false
    func showWorking() { events.append("working") }
    func showFixed(diff: [TextDiff.Segment], undo: @escaping @MainActor () -> Void) {
        events.append("fixed")
        undoVisible = true
    }
    func showUnchanged() { events.append("unchanged") }
    func showCancelled() { events.append("cancelled"); undoVisible = false }
    func showError(_ error: AppError, retry: (@MainActor () -> Void)?) {
        events.append("error:\(error)")
        if retry != nil { events.append("retry") }
        undoVisible = false
    }
    func hide() { events.append("hide"); undoVisible = false }
}

func expect(_ condition: Bool, _ message: String) -> Int {
    if condition { return 0 }
    fputs("FAIL: \(message)\n", stderr)
    return 1
}
