import Foundation
import MaximizeCore
import Observation

/// Holds the app root's answer to one question: is there a store, and if not, what is the
/// athlete reading instead (MAX-169)?
///
/// **It decides nothing.** Which state the app is in is `PersistenceComposition
/// .availability`; what that state says is `FailureCopy.storeAvailability(_:)`; what a
/// press does is `StoreAvailability.afterTryingAgain(_:)`, applied inside
/// `PersistenceComposition.tryOpeningAgain()`. All three are `MaximizeCore` or a thin call
/// into SwiftData, and both halves are the shape CLAUDE.md asks for — this type exists to
/// give SwiftUI something observable to re-render from, which is the one thing a value in
/// the core cannot be.
///
/// The single piece of state genuinely owned here is `hasDismissedTheNotice`, and it is a
/// presentation fact rather than a decision: `RootTabView` owns
/// `isPresentingFirstRunCover` for the same reason, and `FirstRunChecklist`'s doc comment
/// explains why "already shown once" is deliberately not expressible in the core.
@MainActor
@Observable
final class StoreAvailabilityModel {

    private(set) var availability: StoreAvailability

    /// Set by **Continue**, which is offered only after a retry has succeeded. There is no
    /// path that dismisses a notice for a store that is still shut: the app behind it has
    /// nothing to show and nowhere to write, so letting the athlete past it would put them
    /// back among the nine screens each reporting their own version of one problem — the
    /// thing this ticket exists to stop.
    private var hasDismissedTheNotice = false

    /// - Parameter availability: defaults to `PersistenceComposition.availability`, which
    ///   is what opens the store on the first read. Injectable for previews only; there is
    ///   deliberately no other production source.
    init(availability: StoreAvailability = PersistenceComposition.availability) {
        self.availability = availability
    }

    /// What the root shows instead of the app, or nil to show the app.
    var notice: StoreAvailabilityNotice? {
        guard !hasDismissedTheNotice else { return nil }
        return FailureCopy.storeAvailability(availability)
    }

    /// Exhaustive over `StoreNoticeAction` with no `default`, so a control added to that
    /// enum cannot reach a screen without someone deciding here what pressing it does —
    /// which, for an enum whose whole point is that it never grows a destructive case, is
    /// where that decision should be made to fail loudly.
    func perform(_ action: StoreNoticeAction) {
        switch action {
        case .tryAgain:
            availability = PersistenceComposition.tryOpeningAgain()
        case .goToTheApp:
            hasDismissedTheNotice = true
        }
    }
}
