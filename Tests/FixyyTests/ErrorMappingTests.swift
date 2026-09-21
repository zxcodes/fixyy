import Foundation
import FoundationModels
import XCTest
@testable import FixyyCore

final class ErrorMappingTests: XCTestCase {
    func testCancellationMapsToCancelled() {
        XCTAssertEqual(ModelClient.map(CancellationError()), .cancelled)
    }

    func testAppErrorPassesThrough() {
        XCTAssertEqual(ModelClient.map(AppError.guardrail), .guardrail)
    }

    func testUnknownErrorMapsToStalled() {
        XCTAssertEqual(ModelClient.map(NSError(domain: "x", code: 1)), .stalled)
    }

    func testGenerationErrorCases() {
        let ctx = LanguageModelSession.GenerationError.Context(debugDescription: "x")
        let refusal = LanguageModelSession.GenerationError.Refusal(transcriptEntries: [])
        XCTAssertEqual(
            ModelClient.map(LanguageModelSession.GenerationError.exceededContextWindowSize(ctx)),
            .tooLong(estimated: nil, fits: 4096)
        )
        XCTAssertEqual(ModelClient.map(LanguageModelSession.GenerationError.guardrailViolation(ctx)), .guardrail)
        XCTAssertEqual(ModelClient.map(LanguageModelSession.GenerationError.refusal(refusal, ctx)), .refusal)
        XCTAssertEqual(ModelClient.map(LanguageModelSession.GenerationError.rateLimited(ctx)), .rateLimited)
        XCTAssertEqual(ModelClient.map(LanguageModelSession.GenerationError.concurrentRequests(ctx)), .rateLimited)
        XCTAssertEqual(
            ModelClient.map(LanguageModelSession.GenerationError.unsupportedLanguageOrLocale(ctx)),
            .unsupportedLanguage
        )
        XCTAssertEqual(ModelClient.map(LanguageModelSession.GenerationError.assetsUnavailable(ctx)), .modelDownloading)
        XCTAssertEqual(ModelClient.map(LanguageModelSession.GenerationError.decodingFailure(ctx)), .stalled)
        XCTAssertEqual(ModelClient.map(LanguageModelSession.GenerationError.unsupportedGuide(ctx)), .stalled)
    }

    func testLanguageModelErrorCases() {
        guard #available(macOS 27.0, *) else { return }
        XCTAssertEqual(
            ModelClient.map(LanguageModelError.contextSizeExceeded(.init(contextSize: 8192, tokenCount: 9000, debugDescription: "x"))),
            .tooLong(estimated: nil, fits: 8192)
        )
        XCTAssertEqual(
            ModelClient.map(LanguageModelError.guardrailViolation(.init(debugDescription: "x"))),
            .guardrail
        )
        XCTAssertEqual(
            ModelClient.map(LanguageModelError.refusal(.init(explanation: "x", debugDescription: "x"))),
            .refusal
        )
        XCTAssertEqual(
            ModelClient.map(LanguageModelError.rateLimited(.init(resetDate: nil, debugDescription: "x"))),
            .rateLimited
        )
        XCTAssertEqual(ModelClient.map(LanguageModelSession.Error.concurrentRequests), .rateLimited)
        XCTAssertEqual(
            ModelClient.map(SystemLanguageModel.Error.assetsUnavailable(.init(debugDescription: "x"))),
            .modelDownloading
        )
    }
}
