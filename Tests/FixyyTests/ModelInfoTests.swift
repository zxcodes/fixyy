import XCTest
@testable import FixyyCore

final class ModelInfoTests: XCTestCase {
    func testStatusLineAvailable() {
        XCTAssertEqual(
            ModelInfo.statusLine(availability: .available, variantName: "Core 3", contextSize: 8192),
            "Core 3 · On-device · 8,192 ctx"
        )
    }

    func testStatusLineIntelligenceOff() {
        XCTAssertEqual(
            ModelInfo.statusLine(availability: .intelligenceOff, variantName: "Core 3", contextSize: 8192),
            "Unavailable · Apple Intelligence is off"
        )
    }

    func testStatusLineDownloading() {
        XCTAssertTrue(
            ModelInfo.statusLine(availability: .modelNotReady, variantName: "Core 3", contextSize: 8192)
                .hasPrefix("Unavailable ·")
        )
    }
}
