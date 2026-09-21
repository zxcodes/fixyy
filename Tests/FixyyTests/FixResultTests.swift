import XCTest
@testable import FixyyCore

final class FixResultTests: XCTestCase {
    func testIdenticalTextIsNoChange() {
        let result = FixResult.from(original: "Hello.", modelOutput: "Hello.")
        XCTAssertFalse(result.hasChanges)
        XCTAssertEqual(result.text, "Hello.")
    }

    func testDifferentTextIsAChange() {
        let result = FixResult.from(original: "he go store", modelOutput: "He goes to the store.")
        XCTAssertTrue(result.hasChanges)
        XCTAssertEqual(result.text, "He goes to the store.")
    }

    func testQuotedOutputIsUnwrapped() {
        let result = FixResult.from(original: "Hi", modelOutput: "\"Hi\"")
        XCTAssertFalse(result.hasChanges)
    }

    func testEmptyModelOutputKeepsOriginal() {
        let result = FixResult.from(original: "Keep me", modelOutput: "   ")
        XCTAssertFalse(result.hasChanges)
        XCTAssertEqual(result.text, "Keep me")
    }
}
