import Foundation
import SwiftUI
import MaximizeCore

/// Turns a `DisplayMessage`'s (or the in-flight reply's) raw text into the `Text` a
/// bubble draws — Markdown-parsed for the model's own words, verbatim for everything
/// else (MAX-195, `docs/CHAT-AUDIT.md` §6.1). **Which text is which is
/// `ChatMessageRendering`'s decision, in `MaximizeCore`, under test** — this file only
/// carries it out with the platform's own facility. No third-party Markdown parser: a
/// dependency for what `AttributedString(markdown:)` already does is the same argument
/// `ChatPendingReplyView`'s own doc comment makes about the shimmer.
///
/// ## What a half-arrived token does
///
/// A reply streams, so this is asked to parse the same growing string many times a
/// second, and most of those calls see a Markdown document that has not finished
/// arriving — an opened `**` with no closing pair yet, a `-` at the end of a line with
/// nothing after it. Two decisions handle that, in order of how often each is reached:
///
/// 1. **`.full` interpreted syntax with `.returnPartiallyParsedIfPossible`.** An
///    unmatched inline delimiter is left as the literal characters it is — a lone `**`
///    sits on screen as two asterisks, not as bold text that un-bolds itself a moment
///    later — so there is no flicker between bold and plain while the closing marker is
///    still in flight; the run gains its styling once the pair completes and not
///    before. That is the documented behaviour of Foundation's parser for an unpaired
///    delimiter, not something reconstructed here, so there is no delimiter-balancing
///    logic of this codebase's own to get subtly wrong under a partial token. `.full`
///    rather than an inline-only mode because a coaching reply's lists — "a list of
///    sessions," per the ticket — need block structure to render as a list at all;
///    inline-only would leave a `- ` exactly as literal as it is today.
/// 2. **A plain-text fallback for whatever even that cannot parse.**
///    `.returnPartiallyParsedIfPossible` is a best-effort policy, not a guarantee against
///    ever throwing. Should it throw anyway, the raw string is shown unformatted rather
///    than dropped — every character the model sent stays on screen either way, styled
///    if the parser could manage it and plain if it could not. Nothing here ever shows a
///    parse failure as a failure.
///
/// ## Why no heading size is hard-coded here
///
/// This file sets no font beyond the base `.bodyCopy` the call site already applies as a
/// default. Header, list and emphasis structure comes through as `PresentationIntent`
/// attributes on the parsed `AttributedString`, and SwiftUI's `Text` resolves those
/// against the system's own scaled text styles — the same mechanism that makes
/// `.bodyCopy` itself track Dynamic Type. A literal point size for a heading would be
/// exactly the bug CLAUDE.md calls out; the fix is not writing one.
enum ChatMarkdownText {
    /// `text`, ready for a bubble: Markdown-parsed if `isMarkdown`, verbatim otherwise.
    static func text(_ raw: String, isMarkdown: Bool) -> Text {
        Text(attributedString(from: raw, isMarkdown: isMarkdown))
    }

    static func attributedString(from raw: String, isMarkdown: Bool) -> AttributedString {
        guard isMarkdown else { return AttributedString(raw) }
        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .full
        options.failurePolicy = .returnPartiallyParsedIfPossible
        if let parsed = try? AttributedString(markdown: raw, options: options) {
            return parsed
        }
        // Constraint: never throw away content. Whatever Foundation could not parse at
        // all, even on a best-effort policy, is still shown — plain, not dropped.
        return AttributedString(raw)
    }
}
