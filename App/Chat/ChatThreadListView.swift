import SwiftUI
import MaximizeCore

/// §2.3: the thread list, pushed inside `ChatSheet`'s own navigation stack.
///
/// Rows and sections are drawn entirely from `ChatThreadListPresentation`
/// (`MaximizeCore`) — the recency band a thread falls in, the order inside it, the
/// compact timestamp, whether a scope line is worth drawing, which sentence stands in for
/// a preview nobody wrote, and the VoiceOver sentence are all decided there and tested
/// there. This view lays out what it is handed.
///
/// ## Grouped by recency (MAX-153)
///
/// Before this ticket the list was one flat run of rows with a live-updating "3 hours
/// ago" beside each title. Two problems, both of which get worse the longer the app is
/// used: nothing separates this morning's conversation from one in March, and the
/// relative phrase is wider than the title it competes with at any Dynamic Type size
/// above default. Sections carry the coarse answer ("Today", "Previous 7 days") and a
/// Messages-style compact stamp carries the fine one ("12m", "Tue", "3 Aug"), which is
/// the division Apple's own list screens use.
///
/// ## Two ways to delete, neither of them the only one
///
/// `.onDelete(perform:)` on each section's `ForEach` gives the row both of the platform's
/// standard deletion affordances for free: the system's swipe-to-delete (§2.3 asks for
/// exactly this), and — through `EditButton()` toggling edit mode — the red minus-circle
/// control next to every row, which needs no gesture at all. VoiceOver exposes both as a
/// "Delete" custom action on the row regardless of which path produced it, so a person
/// using VoiceOver, Switch Control, or a finger all reach the same result. A hand-rolled
/// `.swipeActions` would replace that set with one of them.
///
/// ## Absence uses the platform's own empty state
///
/// `ContentUnavailableView` is what iOS draws for "there is nothing here", and all three
/// of this screen's absences are that (a fresh install, a failed load, and — since
/// MAX-201 — a search that found nothing). The copy is `ChatThreadListCopy`'s; what this
/// view supplies is the layout, which is the platform's.
///
/// ## Searchable over what a row already shows (§4.3, MAX-201)
///
/// `.searchable(text:prompt:)` on this screen, over `model.searchText`. The filter itself
/// runs in `ChatThreadListPresentation.sections(for:matching:now:timeZone:)` — the same
/// banding function the unfiltered list uses, given a narrower input — so a band with
/// rows filtered out of it collapses exactly as it does when a delete empties one
/// (MAX-189's `deletionOutcome`), rather than surviving as a heading over nothing. What
/// the query is matched against is `ChatThreadSummary`'s own stored `title` and
/// `preview` fields — never a transcript. MAX-188 stopped `threadSummaries()` from
/// decoding one to draw this list; a search box is not a reason to bring it back.
struct ChatThreadListView: View {
    @State private var model: ChatThreadListModel
    private let onSelect: (UUID) -> Void

    /// - Parameters:
    ///   - chatThreadRepository: forwarded from `ChatSheet`, which itself has no default
    ///     to fall back on (`ChatModel`'s own reasoning against a silently defaulted
    ///     store — MAX-049).
    ///   - onSelect: called with the tapped thread's own id — never its subject.
    ///     `ChatSheet` opens that exact thread (`ChatConversationView(threadID:...)`),
    ///     then pops back to the conversation. Resolving by subject instead would be the
    ///     review-caught defect this path exists to avoid: two threads can share an
    ///     identical subject, and only the id says which one was actually tapped.
    init(chatThreadRepository: (any ChatThreadRepository)?, onSelect: @escaping (UUID) -> Void) {
        _model = State(initialValue: ChatThreadListModel(chatThreadRepository: chatThreadRepository))
        self.onSelect = onSelect
    }

    var body: some View {
        content
            .navigationTitle(ChatThreadListCopy.title)
            .navigationBarTitleDisplayMode(.inline)
            .contentSurface(.screen)
            // §4.3: the current platform search affordance rather than a hand-rolled
            // field in a toolbar item — it gets the system's placement, cancel button
            // and keyboard handling for free, and `model.searchText` is the one thing
            // this view owns about it. Filtering itself never happens here; every
            // change re-presents through `ChatThreadListModel.searchText`'s `didSet`,
            // which asks `ChatThreadListPresentation` for the answer.
            .searchable(text: $model.searchText, prompt: ChatThreadListCopy.searchPrompt)

            .alert(
                ChatThreadListCopy.couldNotDeleteThreadTitle,
                isPresented: .constant(model.couldNotDeleteMessage != nil)
            ) {
                Button(ChatThreadListCopy.couldNotDeleteThreadDismiss) {
                    model.dismissDeleteFailure()
                }
            } message: {
                if let message = model.couldNotDeleteMessage {
                    Text(message)
                }
            }
            .task { await model.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed:
            ContentUnavailableView(
                ChatThreadListCopy.couldNotLoadConversationsTitle,
                systemImage: ChatThreadListCopy.couldNotLoadConversationsGlyphSystemImageName,
                description: Text(ChatThreadListCopy.couldNotLoadConversations)
            )
        // §4.3: a filtered-to-nothing list is a different absence than a genuinely
        // empty one — telling the athlete their history is empty when a search simply
        // found nothing in it would be inventing a fact the store does not hold. This
        // case has to precede the plain `sections.isEmpty` one below, since both match
        // the same pattern and Swift takes the first `where` clause that is true.
        case let .loaded(sections) where sections.isEmpty && model.isSearching:
            ContentUnavailableView(
                ChatThreadListCopy.noSearchResultsTitle,
                systemImage: ChatThreadListCopy.noSearchResultsGlyphSystemImageName,
                description: Text(ChatThreadListCopy.noConversationsMatch(model.searchText))
            )
        case let .loaded(sections) where sections.isEmpty:
            // Absence is a designed state (CLAUDE.md): a fresh install and a store that
            // has never been asked anything both look like this, and both deserve real
            // copy rather than an empty list nobody can tell apart from a loading one.
            ContentUnavailableView(
                ChatThreadListCopy.noConversationsTitle,
                systemImage: ChatThreadListCopy.noConversationsGlyphSystemImageName,
                description: Text(ChatThreadListCopy.noConversationsYet)
            )
        case let .loaded(sections):
            list(sections)
        }
    }

    private func list(_ sections: [ChatThreadListSection]) -> some View {
        List {
            ForEach(sections) { section in
                Section {
                    ForEach(section.rows) { row in
                        ChatThreadRow(row: row, onSelect: { onSelect(row.id) })
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
                        // Resolved to identifiers before the work starts: the deletes are
                        // awaited one at a time and each one re-presents the list, so
                        // offsets taken from the old array would address the wrong rows
                        // by the second iteration.
                        let identifiers = offsets.map { section.rows[$0].id }
                        Task {
                            for identifier in identifiers {
                                await model.delete(threadID: identifier)
                            }
                        }
                    }
                } header: {
                    Text(section.title)
                        .font(.metricLabel)
                        .foregroundStyle(Color.textSecondary)
                        // The band names are sentence case by design
                        // (`ChatThreadRecency.sectionTitle`); the plain list style would
                        // otherwise upper-case them and "PREVIOUS 30 DAYS" is a shout.
                        .textCase(nil)
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

/// One row: a subject glyph, the derived title, a compact timestamp, the thread's scope
/// when stating it adds something, and one line of the last message (§2.3).
///
/// Every one of those is a field of `ChatThreadListRow`. Nothing here decides what to
/// show — including the VoiceOver sentence, which the core composes so it cannot fall out
/// of step with the visible fields the way two hand-written copies did before MAX-150.
private struct ChatThreadRow: View {
    let row: ChatThreadListRow
    let onSelect: () -> Void

    @ScaledMetric(relativeTo: .body) private var glyphColumnWidth: CGFloat = 20

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: Spacing.compact) {
                Image(systemName: row.glyphSystemImageName)
                    .font(.bodyCopy)
                    .foregroundStyle(Color.textSecondary)
                    .frame(width: glyphColumnWidth)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: Spacing.tight) {
                    titleRow
                    // Nil for a workout thread, and for a training thread still titled by
                    // its own window — see `ChatThreadListRow.scope`. Absent rather than
                    // blank: the row simply has two lines instead of three.
                    if let scope = row.scope {
                        Text(scope)
                            .font(.microLabel)
                            .foregroundStyle(Color.textSecondary)
                            .lineLimit(1)
                    }
                    // Absence is a designed state: a thread nobody has spoken in yet says
                    // so, a step quieter than something that was actually said. The words
                    // already differ; the weight is a second channel, not the only one.
                    Text(row.preview)
                        .font(.metricLabel)
                        .foregroundStyle(row.previewIsAbsence ? Color.textTertiary : Color.textSecondary)
                        .lineLimit(1)
                }
            }
            .frame(minHeight: LayoutMetrics.minimumTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contentSurface(.tile)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenRow)
        .accessibilityAddTraits(.isButton)
    }

    private var spokenRow: String {
        row.accessibilityLabel(spokenTimestamp: RelativeTimestampFormatting.spoken(row.lastActivityAt))
    }

    /// Title and timestamp on one line.
    ///
    /// The timestamp takes `layoutPriority` and the title truncates, rather than the other
    /// way round: "3 Aug" is a few characters of irreplaceable information and a truncated
    /// title still identifies the conversation. `ViewThatFits` drops the stamp entirely at
    /// the text sizes where keeping it would leave the title one word wide — it is still
    /// spoken in full by the row's accessibility label, and the band heading above already
    /// says roughly when, so nothing is actually lost.
    private var titleRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.snug) {
                title
                Spacer(minLength: Spacing.snug)
                Text(row.timestamp)
                    .font(.microLabel)
                    .foregroundStyle(Color.textTertiary)
                    .lineLimit(1)
                    .layoutPriority(1)
            }
            title
        }
    }

    private var title: some View {
        Text(row.title)
            .font(.bodyCopy)
            .foregroundStyle(Color.textPrimary)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// VoiceOver's wording for a timestamp — independent of the compact "12m" a row draws, so
/// someone hearing the list gets the unabbreviated phrase where width costs nothing.
///
/// Kept in the app layer, with `ChatThreadListRow.accessibilityLabel(spokenTimestamp:)`
/// taking it as a parameter, because `RelativeDateTimeFormatter` is locale-driven and
/// OS-version-driven: a core test asserting its output would be asserting Foundation's
/// behaviour on whichever platform CI happened to run. The *sentence* is the core's
/// decision; this phrase inside it is the platform's.
///
/// Not `private`: MAX-098's workout-detail chat card shows the same relative timestamp
/// against the same thread, and two spellings of "3 hours ago" for one instant is the kind
/// of difference only a VoiceOver user ever hears.
enum RelativeTimestampFormatting {
    static func spoken(_ date: Date) -> String {
        formatter.localizedString(for: date, relativeTo: Date())
    }

    private static let formatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()
}
