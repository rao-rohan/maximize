import Foundation
import MaximizeCore
import Observation

/// Loads and edits the thread list (§2.3). All it does is call the repository, hand what
/// comes back to `ChatThreadListPresentation`, and hold the result — see CLAUDE.md's
/// "thin shell": there is no sorting, banding, date formatting or copy decision here.
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

    /// Kept alongside the presented sections so a delete can re-present from the same
    /// source the load did, rather than surgically removing a row from a banded structure
    /// and hoping the bands still make sense afterwards.
    private var summaries: [ChatThreadSummary] = []

    /// The message when a thread deletion fails (§2.5). Cleared on the next successful
    /// delete or when the list is reloaded.
    private(set) var couldNotDeleteMessage: String?

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
            couldNotDeleteMessage = nil
            present()
        } catch {
            state = .failed
        }
    }

    /// Deletes a row, updating what is on screen immediately rather than waiting on a
    /// reload — §2.3's swipe (and its no-gesture equivalent) should feel instant, and a
    /// second read of the whole list for one row leaving it is wasted work.
    ///
    /// If the deletion fails, the row is restored and an error message is set (§2.5).
    /// The decision of what to show is made in the core; this method is plumbing.
    ///
    /// A no-op if `state` is not `.loaded` (the delete affordance is not on screen
    /// otherwise) or the repository is unavailable.
    ///
    /// Takes the thread's id rather than a whole row: the list is keyed by thread identity,
    /// and re-presenting from `summaries` is what makes deleting the last row of a band
    /// collapse that band rather than leave a heading behind.
    func delete(threadID: UUID) async {
        guard let chatThreadRepository, case .loaded = state else { return }

        var deleteError: Error? = nil
        do {
            try await chatThreadRepository.deleteThread(id: threadID)
        } catch {
            deleteError = error
        }

        // Hand the outcome to the core to decide what to show
        let outcome = ChatThreadListPresentation.deletionOutcome(
            from: summaries,
            attemptedThreadID: threadID,
            error: deleteError,
            now: now(),
            timeZone: timeZone
        )

        summaries = outcome.summaries
        state = .loaded(outcome.sections)
        couldNotDeleteMessage = outcome.errorMessage
    }

    /// Dismisses the delete-failure alert. A method rather than a settable property so
    /// the view cannot put this model into a state it did not compute — the same reason
    /// `couldNotDeleteMessage` is `private(set)`.
    func dismissDeleteFailure() {
        couldNotDeleteMessage = nil
    }

    private func present() {
        state = .loaded(
            ChatThreadListPresentation.sections(for: summaries, now: now(), timeZone: timeZone)
        )
    }
}
