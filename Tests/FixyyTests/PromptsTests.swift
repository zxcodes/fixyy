import XCTest
@testable import FixyyCore

final class PromptsTests: XCTestCase {
    func testStyleNoteLivesInInstructionsNotPrompt() {
        let note = "British English, no em dashes."
        let instructions = Prompts.fixInstructions(styleNote: note)
        let prompt = Prompts.fixPrompt("he go store")
        XCTAssertTrue(instructions.contains(note))
        XCTAssertFalse(prompt.contains(note))
        XCTAssertTrue(prompt.contains("he go store"))
    }

    func testEmptyStyleNoteOmitsBlock() {
        let instructions = Prompts.fixInstructions(styleNote: "   ")
        XCTAssertFalse(instructions.contains("style note"))
    }

    func testCustomRewritePutsInstructionInPrompt() {
        let prompt = Prompts.rewritePrompt("hello", kind: .custom("Slack-voice, keep the joke"))
        XCTAssertTrue(prompt.contains("Slack-voice, keep the joke"))
        XCTAssertTrue(prompt.contains("hello"))
    }

    func testFriendlyRewritePrompt() {
        let prompt = Prompts.rewritePrompt("hi", kind: .friendly)
        XCTAssertTrue(prompt.contains("warmer and more conversational"))
        XCTAssertTrue(prompt.contains("hi"))
    }

    func testRewriteInstructionsKeepMeaning() {
        let instructions = Prompts.rewriteInstructions(styleNote: "be brief")
        XCTAssertTrue(instructions.contains("Keep meaning"))
        XCTAssertTrue(instructions.contains("be brief"))
    }
}
