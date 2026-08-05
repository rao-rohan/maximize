import Foundation
import MaximizeCore
import Observation

/// Loads and edits the thread list (§2.3). All it does is call the repository and hold
/// the result — see CLAUDE.md's "thin shell": there is no sorting, filtering or copy
/// decision here. `ChatThreadRepository.threadSummaries()` already returns newest
/// activity first (`ChatThreadSummary.sortedByActivity(_:)`, tiebreak included), so this
/// type does not re-sort what it is handed.
@MainActor
@Observable
final class ChatThreadListModel {
    enum LoadState: Equatable {
        case loading
        /// The store could not be opened, or the read failed — mirrors every sibling
        /// list's `.failed` (`WorkoutsListModel`).
        case failed
        case loaded([ChatThreadSummary])
    }

    private(set) var state: LoadState = .loading

    private let chatThreadRepository: (any ChatThreadRepository)?

    /// - Parameter chatThreadRepository: **required, with no default**, matching
    ///   `ChatModel`'s own reasoning: `MaximizeCore` cannot see `PersistenceComposition`,
    ///   so the caller supplies it explicitly rather than this type silently resolving
    ///   to a store nobody named. A caller with nothing to pass should pass `nil`, which
    ///   `load()` turns into `.failed`.
    init(chatThreadRepository: (any ChatThreadRepository)?) {
        self.chatThreadRepository = chatThreadRepository
    }

    func load() async {
        guard let chatThreadRepository else {
            state = .failed
            return
        }
        do {
            state = .loaded(try await chatThreadRepository.threadSummaries())
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
    func delete(_ summary: ChatThreadSummary) async {
        guard let chatThreadRepository, case .loaded(var summaries) = state else { return }
        summaries.removeAll { $0.id == summary.id }
        state = .loaded(summaries)
        // Best-effort: the row is already gone from what the athlete sees, and a
        // failed on-disk delete here is the same class of "local storage problem" that
        // does not warrant clawing back something already removed (`ChatModel`'s own
        // reasoning for a failed `store(_:)`, e.g. "This reply could not be saved").
        try? await chatThreadRepository.deleteThread(id: summary.id)
    }
}
