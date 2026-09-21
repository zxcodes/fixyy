import XCTest
@testable import FixyyCore

final class FloatingPanelBehaviorTests: XCTestCase {
    func testStandardJoinsAllSpaces() {
        XCTAssertTrue(FloatingPanelBehavior.standard.contains(.canJoinAllSpaces))
    }

    func testStandardIsFullScreenAuxiliary() {
        XCTAssertTrue(FloatingPanelBehavior.standard.contains(.fullScreenAuxiliary))
    }

    func testStandardDoesNotMoveToActiveSpace() {
        XCTAssertFalse(FloatingPanelBehavior.standard.contains(.moveToActiveSpace))
    }
}
