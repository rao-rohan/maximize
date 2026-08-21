/// Which `ChatModel.DisplayMessage.Kind`s should be interpreted as Markdown when shown
/// (MAX-195, `docs/CHAT-AUDIT.md` §6.1/§6.2).
///
/// One line, and it lives here rather than as an `if` in `ChatConversationView` for the
/// same reason `ChatComposerSendControl.resolve` does: "which roles get which
/// treatment" is a product rule, not a rendering detail, and putting it in
/// `MaximizeCore` is what lets CI hold it under test instead of trusting a view
/// literal.
///
/// **Only the model's own words are Markdown.**
///
/// - `.assistant` is the one role whose text this app did not write — a coaching
///   reply's own structure (a pace called out in **bold**, a list of sessions) is
///   worth keeping rather than showing as literal punctuation, which is §6.1's finding.
/// - `.user` text is the athlete's, verbatim. A person who types `*hi*` meant two
///   asterisks and the word "hi" — reinterpreting their own words as formatting puts
///   something in their mouth they did not choose, and this app does not do that to a
///   message it did not write.
/// - `.notice` text is app copy — `ChatFailureNotice`, `ChatConversationCopy` — written
///   by this codebase as plain English sentences with no Markdown in them by
///   construction. Parsing it buys nothing and risks the opposite: a stray `*` inside
///   an athlete's own quoted words (MAX-191's dropped-turn notice, for instance) being
///   misread as syntax rather than shown as the character it is.
public enum ChatMessageRendering {
    /// Whether text belonging to `kind` should be parsed as Markdown before it is shown.
    public static func isMarkdown(for kind: ChatModel.DisplayMessage.Kind) -> Bool {
        kind == .assistant
    }
}
