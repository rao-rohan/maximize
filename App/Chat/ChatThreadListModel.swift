import Foundation
import MaximizeCore
import Observation

/// Loads and edits the thread list (§2.3). All it does is call the repository, hand what
/// comes back to `ChatThreadListPresentation`, and hold the result — see CLAUDE.md's
/// "thin shell": there is no sorting, banding, date formatting, filtering, or copy
/// decision here. `searchText` (§4.3, MAX-201) is no exception — it is state to hold and
/// a trigger to re-present, and the decision of which rows a query matches, and that the
/// banding above them survives being filtered, is `ChatThreadListPresentation`'s.
///
/// ## Why the presented sections are stored rather than computed in the view
///
/// `ChatThreadListPresentation.sections(for:now:timeZone:)` needs a *notion of now*, and a
/// view's `body` runs whenever SwiftUI feels like it. Computing there would re-band every
/// row on every layout pass and — worse — would let a row silently move from "Today" to
/// "Yesterday" mid-scroll at midnight, which is a list reordering itself under a finger.
/// The window is resolved once, when the list is loaded, and stays put until it is loaded
/// again.
@MainActor
@Observable
final class ChatThreadListModel {
    enum LoadState: Equatable {
        case loading
        /// The store could not be opened, or the read failed — mirrors every sibling
        /// list's `.failed` (`WorkoutsListModel`).
        case failed
        /// Empty exactly when there are no threads: `ChatThreadListPresentation` never
        /// emits a band with nothing in it, so `[]` is the absence state rather than a
        /// list of empty headings.
        case loaded([ChatThreadListSection])
    }

    private(set) var state: LoadState = .loading

    /// §4.3: bound to `.searchable`'s field. Every change re-presents from `summaries`,
    /// the same way a delete does — filtering runs in `ChatThreadListPresentation`
    /// (`MaximizeCore`), this only decides *when* to ask for it again.
    var searchText: String = "" {
        didSet {
            guard case .loaded = state else { return }
            present()
        }
    }

    /// Whether `searchText` is actively filtering, for the view to choose which absence
    /// state to draw. Not a second filtering decision — the core still solely decides
    /// which rows match — just the same blank-means-nothing-typed rule
    /// `ChatThreadListPresentation.sections(for:matching:now:timeZone:)` already applies,
    /// read back so the view is not left re-deriving it to pick a headline.
    var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Kept alongside the presented sections so a delete can re-present from the same
    /// source the load did, rather than surgically removing a row from a banded structure
    /// and hoping the bands still make sense afterwards.
    private var summaries: [ChatThreadSummary] = []

    private let chatThreadRepository: (any ChatThreadRepository)?
    private let now: () -> Date
    private let timeZone: TimeZone

    /// - Parameters:
    ///   - chatThreadRepository: **required, with no default**, matching `ChatModel`'s own
    ///     reasoning: `MaximizeCore` cannot see `PersistenceComposition`, so the caller
    ///     supplies it explicitly rather than this type silently resolving to a store
    ///     nobody named. A caller with nothing to pass should pass `nil`, which `load()`
    ///     turns into `.failed`.
    ///   - now / timeZone: injected so the banding is a pure function of what this type is
    ///     told, the same shape `ChatModel` uses for its own clock.
    init(
        chatThreadRepository: (any ChatThreadRepository)?,
        now: @escaping () -> Date = Date.init,
        timeZone: TimeZone = .current
    ) {
        self.chatThreadRepository = chatThreadRepository
        self.now = now
        self.timeZone = timeZone
    }

    func load() async {
        guard let chatThreadRepository else {
            state = .failed
            return
        }
        do {
            summaries = try await chatThreadRepository.threadSummaries()
            present()
        } catch {
            state = .failed
        }
    }

    /// Deletes a row, updating what is on screen immediately rather than waiting on a
    /// reload — §2.3's swipe (and its no-gesture equivalent) should feel instant, and a
    /// second read of the whole list for one row leaving it is wasted work.
    ///
    /// A no-op if `state` is not `.loaded` (the delete affordance is not on screen
    /// otherwise) or the repository is unavailable.
    ///
    /// Takes the thread's id rather than a whole row: the list is keyed by thread identity,
    /// and re-presenting from `summaries` is what makes deleting the last row of a band
    /// collapse that band rather than leave a heading behind.
    func delete(threadID: UUID) async {
        guard let chatThreadRepository, case .loaded = state else { return }
        summaries.removeAll { $0.id == threadID }
        present()
        // Best-effort: the row is already gone from what the athlete sees, and a failed
        // on-disk delete here is the same class of "local storage problem" that does not
        // warrant clawing back something already removed (`ChatModel`'s own reasoning for
        // a failed `store(_:)`, e.g. "This reply could not be saved").
        try? await chatThreadRepository.deleteThread(id: threadID)
    }

    private func present() {
        state = .loaded(
            ChatThreadListPresentation.sections(
                for: summaries,
                matching: searchText,
                now: now(),
                timeZone: timeZone
            )
        )
    }
}
