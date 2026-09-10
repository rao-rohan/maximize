import XCTest
@testable import MaximizeCore

/// MAX-195: which `DisplayMessage.Kind`s render as Markdown. A one-line decision, and
/// the only one this ticket moved into the core rather than leaving as a view literal
/// — see that type's own documentation for why each answer is what it is.
final class ChatMessageRenderingTests: XCTestCase {

    func testOnlyTheAssistantsOwnWordsAreMarkdown() {
        XCTAssertTrue(ChatMessageRendering.isMarkdown(for: .assistant))
        XCTAssertFalse(ChatMessageRendering.isMarkdown(for: .user))
        XCTAssertFalse(ChatMessageRendering.isMarkdown(for: .notice))
    }

    /// The athlete's own words are never reinterpreted — a person who types `*hi*`
    /// meant asterisks.
    func testTheAthletesOwnMessagesAreNeverMarkdown() {
        XCTAssertFalse(ChatMessageRendering.isMarkdown(for: .user))
    }

    /// App copy — failure notices, "no key stored," the dropped-turn warning — is
    /// written by this codebase as plain sentences and is never Markdown either.
    func testNoticesAreNeverMarkdown() {
        XCTAssertFalse(ChatMessageRendering.isMarkdown(for: .notice))
    }
}
