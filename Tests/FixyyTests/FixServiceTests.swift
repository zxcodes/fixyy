import XCTest
@testable import FixyyCore

@MainActor
final class FixServiceTests: XCTestCase {
    func testUnchangedTextDoesNotPaste() async {
        let env = Env()
        env.model.fixHandler = { text, _ in FixResult(hasChanges: false, text: "DIFFERENT \(text)") }
        await env.service.run()
        XCTAssertTrue(env.selection.pasted.isEmpty)
        XCTAssertTrue(env.hud.events.contains("unchanged"))
    }

    func testChangedTextPastes() async {
        let env = Env()
        env.model.fixHandler = { _, _ in FixResult(hasChanges: true, text: "He goes to the store.") }
        await env.service.run()
        XCTAssertEqual(env.selection.pasted, ["He goes to the store."])
        XCTAssertTrue(env.hud.events.contains("fixed"))
    }

    func testModelErrorDoesNotPaste() async {
        let env = Env()
        env.model.fixHandler = { _, _ in throw AppError.guardrail }
        await env.service.run()
        XCTAssertTrue(env.selection.pasted.isEmpty)
        XCTAssertTrue(env.hud.events.contains("error:guardrail"))
    }

    func testEmptySelectionDoesNotPaste() async {
        let env = Env()
        env.selection.captureResult = .empty
        await env.service.run()
        XCTAssertTrue(env.selection.pasted.isEmpty)
        XCTAssertTrue(env.hud.events.contains("error:emptySelection"))
    }

    func testTooLongSelectionDoesNotCallModel() async {
        let env = Env()
        env.selection.captureResult = .text(String(repeating: "a", count: selectionCharacterLimit + 1))
        await env.service.run()
        XCTAssertNil(env.model.lastFixText)
        XCTAssertTrue(env.selection.pasted.isEmpty)
        XCTAssertTrue(env.hud.events.contains { $0.hasPrefix("error:tooLong") })
    }

    func testCancelledJobDoesNotPaste() async {
        let env = Env()
        env.model.fixDelayNanoseconds = 2_000_000_000
        env.model.fixHandler = { _, _ in FixResult(hasChanges: true, text: "should not paste") }
        let task = Task { await env.service.run() }
        try? await Task.sleep(nanoseconds: 50_000_000)
        task.cancel()
        await task.value
        XCTAssertTrue(env.selection.pasted.isEmpty)
    }

    func testRunAfterCancelStillPastes() async {
        let env = Env()
        env.selection.captureDelayNanoseconds = 400_000_000
        env.model.fixHandler = { _, _ in FixResult(hasChanges: true, text: "He goes to the store.") }
        let first = Task { await env.service.run() }
        try? await Task.sleep(nanoseconds: 50_000_000)
        first.cancel()
        await env.service.run()
        await first.value
        XCTAssertEqual(env.selection.pasted, ["He goes to the store."])
        XCTAssertGreaterThanOrEqual(env.selection.captureCalls, 2)
    }

    func testUndoInvokesHostUndo() async {
        let env = Env()
        env.model.fixHandler = { _, _ in FixResult(hasChanges: true, text: "He goes to the store.") }
        await env.service.run()
        env.service.undo()
        try? await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(env.selection.undoCalls, 1)
        XCTAssertEqual(env.selection.pasted, ["He goes to the store."])
        XCTAssertTrue(env.hud.events.contains("hide"))
    }

    func testRetryClosureOnlyForRetryableErrors() async {
        let retryable = Env()
        retryable.model.fixHandler = { _, _ in throw AppError.stalled }
        await retryable.service.run()
        XCTAssertTrue(retryable.hud.events.contains("error:stalled"))
        XCTAssertTrue(retryable.hud.events.contains("retry"))

        let plain = Env()
        plain.model.fixHandler = { _, _ in throw AppError.guardrail }
        await plain.service.run()
        XCTAssertTrue(plain.hud.events.contains("error:guardrail"))
        XCTAssertFalse(plain.hud.events.contains("retry"))
    }

    func testAccessibilityDeniedDoesNotCapture() async {
        let env = Env()
        env.selection.isTrusted = false
        await env.service.run()
        XCTAssertTrue(env.selection.pasted.isEmpty)
        XCTAssertEqual(env.selection.trustPrompts, 1)
        XCTAssertTrue(env.hud.events.contains("error:accessibilityDenied"))
    }

    func testUnavailableModelDoesNotPaste() async {
        let env = Env()
        env.model.availability = .intelligenceOff
        await env.service.run()
        XCTAssertTrue(env.selection.pasted.isEmpty)
        XCTAssertTrue(env.hud.events.contains("error:intelligenceOff"))
    }

    @MainActor
    private final class Env {
        let model = FakeModel()
        let selection = FakeSelection()
        let hud = HUDSpy()
        let prefs: Prefs
        let service: FixService

        init() {
            let prefs = Prefs(defaults: UserDefaults(suiteName: "fixyy.tests.\(UUID().uuidString)")!)
            self.prefs = prefs
            self.service = FixService(model: model, selection: selection, prefs: prefs, hud: hud)
        }
    }
}
