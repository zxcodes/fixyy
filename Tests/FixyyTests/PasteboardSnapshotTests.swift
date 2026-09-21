import AppKit
import XCTest
@testable import FixyyCore

final class PasteboardSnapshotTests: XCTestCase {
    func testRestorePutsOriginalStringBack() {
        let board = NSPasteboard.withUniqueName()
        board.clearContents()
        board.setString("original", forType: .string)
        let snapshot = PasteboardSnapshot(pasteboard: board)
        board.clearContents()
        board.setString("sentinel", forType: .string)
        snapshot.restore(to: board)
        XCTAssertEqual(board.string(forType: .string), "original")
    }
}
