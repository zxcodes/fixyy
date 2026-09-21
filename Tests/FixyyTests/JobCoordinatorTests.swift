import XCTest
@testable import FixyyCore

final class JobCoordinatorTests: XCTestCase {
    func testCancelledCaptureIsNotStalled() {
        XCTAssertNil(JobCoordinator.rewriteError(from: CancellationError()))
        XCTAssertNil(JobCoordinator.rewriteError(from: AppError.cancelled))
    }

    func testAppErrorsPassThrough() {
        XCTAssertEqual(JobCoordinator.rewriteError(from: AppError.emptySelection), .emptySelection)
        XCTAssertEqual(JobCoordinator.rewriteError(from: AppError.secureField), .secureField)
    }

    func testUnknownErrorMapsToStalled() {
        XCTAssertEqual(JobCoordinator.rewriteError(from: NSError(domain: "x", code: 1)), .stalled)
    }
}
