import Foundation

/// §3.6(b) — the quiet note shown when a training thread's frozen scope no longer
/// matches the window the dashboard is currently showing.
///
/// ## Why this exists
///
/// A training thread's `TrainingScope` is resolved to absolute days once, at creation,
/// and never slides (`TrainingScope`'s own documentation). The dashboard's selected
/// interval keeps moving — a step of the chevron, a day passing under "this week." Both
/// are correct; they can still disagree, and a number quoted from the frozen window can
/// read as contradicting a tile the athlete is looking at right now. §3.6(b)'s fix is
/// not to prevent the mismatch — freezing is deliberate — but to make it legible: this
/// is the one place that decides *whether* to say so, so a view never has to compare two
/// windows itself.
///
/// ## Why a workout thread never gets one
///
/// A workout thread's scope is the run itself, which does not move with the dashboard's
/// interval selector at all — there is no second notion of "which run" for it to
/// disagree with. `subject.trainingScope` being nil is exactly that case, and this type
/// answers nil rather than asking a caller to have known not to call it.
public enum ChatScopeNotice {

    /// - Parameters:
    ///   - subject: the open thread's subject. Nil for anything but a training subject.
    ///   - currentInterval: the dashboard's selection right now, resolved the same way
    ///     `TrainingScope(resolving:)` freezes one at thread creation — so a match here
    ///     is a genuine match, not two labels that happen to render the same.
    /// - Returns: nil when the thread is a workout thread, or when the two windows
    ///   agree; otherwise a one-line note naming both.
    public static func text(for subject: ChatSubject, currentInterval: TrendInterval) -> String? {
        guard let threadScope = subject.trainingScope else { return nil }
        guard let currentScope = try? TrainingScope(resolving: currentInterval) else { return nil }
        guard threadScope != currentScope else { return nil }
        return "This chat is scoped to \(threadScope.label). The dashboard is now showing "
            + "\(currentScope.label) — start a new chat to ask about that window."
    }
}
