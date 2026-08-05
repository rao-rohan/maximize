import SwiftUI
import MaximizeCore

/// §2.3: the thread list, pushed inside `ChatSheet`'s own navigation stack.
///
/// Rows are drawn entirely from `ChatThreadSummary` (`MaximizeCore`) — title, subject
/// glyph, relative timestamp and last-message preview are every one of that type's
/// fields, and none of them is decided here. This view only lays them out.
///
/// ## Two ways to delete, neither of them the only one
///
/// `.onDelete(perform:)` on the `ForEach` gives the row both of the platform's standard
/// deletion affordances for free: the system's swipe-to-delete (§2.3 asks for exactly
/// this), and — through `EditButton()` toggling edit mode — the red minus-circle control
/// next to every row, which needs no gesture at all. VoiceOver exposes both as a
/// "Delete" custom action on the row regardless of which path produced it, so a person
/// using VoiceOver, Switch Control, or a finger all reach the same result.
struct ChatThreadListView: View {
    @State private var model: ChatThreadListModel
    private let onSelect: (ChatThreadSummary) -> Void

    /// - Parameters:
    ///   - chatThreadRepository: forwarded from `ChatSheet`, which itself has no
    ///     default to fall back on (`ChatModel`'s own reasoning against a silently
    ///     defaulted store — MAX-049).
    ///   - onSelect: called with the tapped row's full summary. `ChatSheet` reads
    ///     `summary.id` — never `summary.subject` — and opens that exact thread by id
    ///     (`ChatConversationView(threadID:...)`), then pops back to the conversation.
    ///     Resolving by subject instead would be the review-caught defect this whole
    ///     path exists to avoid: two threads can share an identical subject, and only
    ///     the id says which one was actually tapped.
    init(chatThreadRepository: (any ChatThreadRepository)?, onSelect: @escaping (ChatThreadSummary) -> Void) {
        _model = State(initialValue: ChatThreadListModel(chatThreadRepository: chatThreadRepository))
        self.onSelect = onSelect
    }

    var body: some View {
        content
            .navigationTitle("Chats")
            .navigationBarTitleDisplayMode(.inline)
            .contentSurface(.screen)
            .task { await model.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed:
            absence("Conversations could not be loaded.")
        case let .loaded(summaries) where summaries.isEmpty:
            // Absence is a designed state (CLAUDE.md): a fresh install and a store that
            // has never been asked anything both look like this, and both deserve real
            // copy rather than an empty list nobody can tell apart from a loading one.
            absence("No conversations yet — ask about a run or your training to start one.")
        case let .loaded(summaries):
            List {
                ForEach(summaries) { summary in
                    ChatThreadRow(summary: summary, onSelect: { onSelect(summary) })
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(
                            top: Spacing.tight,
                            leading: LayoutMetrics.screenMargin,
                            bottom: Spacing.tight,
                            trailing: LayoutMetrics.screenMargin
                        ))
                }
                .onDelete { offsets in
                    let toDelete = offsets.map { summaries[$0] }
                    Task {
                        for summary in toDelete {
                            await model.delete(summary)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { EditButton() }
            }
        }
    }

    private func absence(_ text: String) -> some View {
        Text(text)
            .font(.bodyCopy)
            .foregroundStyle(Color.textSecondary)
            .multilineTextAlignment(.center)
            .screenMargins()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// One row: a subject glyph, the derived title, a relative timestamp, and one line of
/// the last message — every field `ChatThreadSummary` carries (§2.3).
private struct ChatThreadRow: View {
    let summary: ChatThreadSummary
    let onSelect: () -> Void

    @ScaledMetric(relativeTo: .body) private var glyphSize: CGFloat = 20

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: Spacing.compact) {
                Image(systemName: summary.subject.kind.glyphSystemImageName)
                    .font(.bodyCopy)
                    .foregroundStyle(Color.textSecondary)
                    .frame(width: glyphSize)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: Spacing.tight) {
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.snug) {
                        Text(summary.title)
                            .font(.bodyCopy)
                            .foregroundStyle(Color.textPrimary)
                            .lineLimit(1)
                        Spacer(minLength: Spacing.snug)
                        Text(summary.lastActivityAt, style: .relative)
                            .font(.microLabel)
                            .foregroundStyle(Color.textTertiary)
                            .lineLimit(1)
                            .layoutPriority(1)
                    }
                    // Absence is a designed state: a thread nobody has spoken in yet
                    // says so, rather than leaving the second line blank — the same
                    // register `ChatConversationCopy.emptyTranscriptInvitation` uses on
                    // the screen this row opens.
                    Text(summary.preview ?? "No messages yet")
                        .font(.metricLabel)
                        .foregroundStyle(summary.preview == nil ? Color.textTertiary : Color.textSecondary)
                        .lineLimit(1)
                }
            }
            .frame(minHeight: LayoutMetrics.minimumTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contentSurface(.tile)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isButton)
    }

    private var accessibilityLabel: String {
        let relative = RelativeTimestampFormatting.spoken(summary.lastActivityAt)
        let preview = summary.preview ?? "No messages yet"
        return "\(summary.subject.kind.accessibilityKindLabel). \(summary.title). \(relative). \(preview)"
    }
}

/// VoiceOver's wording for a row's timestamp — independent of `Text(_:style:.relative)`'s
/// own (undocumented, and locale-driven) visual phrasing, so the accessibility label is
/// something this file controls rather than inherits.
private enum RelativeTimestampFormatting {
    static func spoken(_ date: Date) -> String {
        formatter.localizedString(for: date, relativeTo: Date())
    }

    private static let formatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()
}
