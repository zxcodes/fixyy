import XCTest
@testable import FixyyCore

final class TokenBudgetTests: XCTestCase {
    func testOkWithFakeCounter() async {
        let budget = TokenBudget(contextSize: 8192) { text in text.count }
        let verdict = await budget.fits(selection: "one hundred chars", instructions: "instr")
        guard case .ok(let tokens) = verdict else {
            return XCTFail("expected ok, got \(verdict)")
        }
        XCTAssertEqual(tokens, "one hundred chars".count + "instr".count)
    }

    func testTooLongWithFakeCounter() async {
        let budget = TokenBudget(contextSize: 8192) { _ in 10_000 }
        let verdict = await budget.fits(selection: "big", instructions: "i")
        guard case .tooLong(let estimated, let fits) = verdict else {
            return XCTFail("expected tooLong, got \(verdict)")
        }
        XCTAssertEqual(estimated, 10_000)
        XCTAssertLessThan(fits, 10_000)
    }

    func testFallbackWhenCounterIsNil() async {
        let budget = TokenBudget(contextSize: 8192)
        let ok = await budget.fits(selection: "short", instructions: "i")
        guard case .ok = ok else {
            return XCTFail("expected ok, got \(ok)")
        }
        let long = await budget.fits(
            selection: String(repeating: "a", count: selectionCharacterLimit + 1),
            instructions: "i"
        )
        guard case .tooLong(let estimated, let fits) = long else {
            return XCTFail("expected tooLong, got \(long)")
        }
        XCTAssertEqual(estimated, (selectionCharacterLimit + 1) / 4)
        XCTAssertEqual(fits, selectionCharacterLimit / 4)
    }
}
