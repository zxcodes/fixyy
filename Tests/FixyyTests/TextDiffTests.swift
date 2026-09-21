import XCTest
@testable import FixyyCore

final class TextDiffTests: XCTestCase {
    func testIdenticalIsOneEqualSegment() {
        XCTAssertEqual(TextDiff.segments(from: "a b c", to: "a b c"), [.equal("a b c")])
    }

    func testSingleSubstitution() {
        XCTAssertEqual(
            TextDiff.segments(from: "he go store", to: "he went store"),
            [.equal("he"), .removed("go"), .inserted("went"), .equal("store")]
        )
    }

    func testInsertionAtEnd() {
        XCTAssertEqual(
            TextDiff.segments(from: "a b", to: "a b c"),
            [.equal("a b"), .inserted("c")]
        )
    }

    func testFullRewrite() {
        XCTAssertEqual(
            TextDiff.segments(from: "a b", to: "x y z"),
            [.removed("a b"), .inserted("x y z")]
        )
    }

    func testAdjacentSameKindSegmentsMerge() {
        XCTAssertEqual(
            TextDiff.segments(from: "a x y b", to: "a b"),
            [.equal("a"), .removed("x y"), .equal("b")]
        )
    }
}
