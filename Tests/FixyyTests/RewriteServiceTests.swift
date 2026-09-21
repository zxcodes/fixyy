import XCTest
@testable import FixyyCore

@MainActor
final class RewriteServiceTests: XCTestCase {
    func testPartialsArriveInOrderAndCumulative() async throws {
        let model = FakeModel()
        model.rewritePartials = ["a", "a b", "a b c"]
        let service = RewriteService(model: model, prefs: makePrefs())
        var collected: [String] = []
        for try await partial in service.stream(text: "x", kind: .shorter) {
            collected.append(partial)
        }
        XCTAssertEqual(collected, ["a", "a b", "a b c"])
        XCTAssertEqual(model.lastSampling, .automatic)
    }

    func testCancelStopsStream() async {
        let model = FakeModel()
        model.rewritePartials = (0..<100).map { "partial \($0)" }
        let service = RewriteService(model: model, prefs: makePrefs())
        var seen = 0
        do {
            for try await _ in service.stream(text: "x", kind: .clearer) {
                seen += 1
                if seen == 1 { break }
            }
        } catch {}
        XCTAssertEqual(seen, 1)
    }

    func testOversizedTextThrowsTooLong() async {
        let model = FakeModel()
        let service = RewriteService(model: model, prefs: makePrefs())
        var thrown: Error?
        do {
            for try await _ in service.stream(
                text: String(repeating: "a", count: selectionCharacterLimit + 1),
                kind: .shorter
            ) {}
        } catch {
            thrown = error
        }
        guard case .tooLong = thrown as? AppError else {
            return XCTFail("expected tooLong, got \(String(describing: thrown))")
        }
    }

    private func makePrefs() -> Prefs {
        Prefs(defaults: UserDefaults(suiteName: "fixyy.tests.\(UUID().uuidString)")!)
    }
}
