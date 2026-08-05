import SwiftUI
import MaximizeCore

/// The chat sheet (§2.2): a full-height sheet whose toolbar carries a leading button to
/// the thread list (§2.3), the open thread's derived title and scope inline, a trailing
/// **New chat** for training subjects, and Done. The system supplies the sheet's own
/// glass; nothing here reapplies it — `SettingsToolbar.swift` documents why a sheet the
/// system already glasses does not get glass reapplied.
///
/// This type is deliberately thin: it owns the navigation stack and the identity of
/// "what is currently open," and nothing else. The toolbar's title, subtitle, and its
/// leading/trailing buttons are all defined on `ChatConversationView` itself, because
/// that is the one place `ChatModel` — and therefore `model.title`/`model.subtitle`
/// (§2.4, §3.6(b)) — actually lives; a title read up here would either be a second,
/// unloaded copy or force this type to reach into a child's private state.
///
/// ## Two ways to open something (§2.2 vs §2.3, MAX-097 review)
///
/// `Opening` below mirrors `ChatModel`'s own `Opening` (private to that type, so this is
/// a second, App-layer value of the same shape rather than a shared one): a `.subject`
/// is what the Ask button and **New chat** hand in, and `ChatConversationView(subject:...)`
/// resolves "the" thread for it exactly as `ChatModel.load()` already does
/// (`ChatThreadRepository.thread(for:newThreadID:at:)`, newest activity wins). A
/// `.threadID` is what selecting a row in the thread list hands in, and
/// `ChatConversationView(threadID:...)` opens *exactly* that thread.
///
/// **Why the second case has to exist.** Two training threads can legitimately share an
/// identical frozen `TrainingScope` — `ChatThreadRepository`'s own contract does not
/// deduplicate training subjects, because **New chat** over an unchanged window is still
/// a real, if unusual, thing to do. If the thread list resolved a tapped row *by
/// subject*, tapping the older of two such rows would silently reopen the newer one —
/// the list would show two conversations and only ever let you reach one. Carrying the
/// tapped row's own id through instead is what makes the list mean what it shows.
///
/// ## Reassigning `opening`, not rebuilding the sheet
///
/// Selecting a row, or tapping **New chat**, changes `opening` rather than presenting a
/// second sheet. `ChatConversationView` is recreated from scratch whenever it does —
/// `.id(opening)` below — because `ChatModel.subject` is immutable by design
/// ("re-subjecting a live model would leave a transcript answered from something it no
/// longer describes," `ChatModel`'s own documentation). A fresh `ChatModel` for the new
/// opening is the correct way to honour that, not a workaround around it.
///
/// ## Who presents this (MAX-098)
///
/// One caller: the persistent Ask button, from `RootTabView`. The workout detail
/// screen's card presented it until MAX-098 and no longer does — two chat buttons on one
/// screen opening the same conversation is worse than either alone (§2.1).
///
/// `currentInterval` is the dashboard's live `TrendIntervalSelectionModel` selection,
/// which `RootTabView` owns so that every tab's Ask button reads the same one (§3.4:
/// one control, one notion of "what period are we talking about"). It is read at
/// presentation rather than captured with the subject, because it is what §3.6(b)'s
/// mismatch note compares the thread's *frozen* window against and what **New chat**
/// freezes a fresh scope from — both of which want the window the dashboard is on now.
/// The parameter keeps its default so a caller with no such control still gets "this
/// week", matching `TrendIntervalSelectionModel`'s own default.
struct ChatSheet: View {
    private enum Route: Hashable {
        case threadList
    }

    /// See this type's "Two ways to open something." Hashable so `.id(opening)` can key
    /// `ChatConversationView`'s identity on it.
    private enum Opening: Hashable {
        case subject(ChatSubject)
        case threadID(UUID)
    }

    @State private var opening: Opening
    @State private var path = NavigationPath()

    /// The dashboard's currently-selected interval, or "this week" when nothing live
    /// was handed in. Frozen into a fresh `TrainingScope` when **New chat** is tapped,
    /// and the comparison point for §3.6(b)'s mismatch note. Nil only in the practical
    /// non-case where "today" itself could not be resolved (`CalendarDay`'s domain is
    /// 1...9999 AD) — mirrors `TrendIntervalSelectionModel.State.failed`.
    private let currentInterval: TrendInterval?

    @Environment(\.dismiss) private var dismiss

    init(subject: ChatSubject, currentInterval: TrendInterval? = nil) {
        _opening = State(initialValue: .subject(subject))
        self.currentInterval = currentInterval ?? Self.defaultInterval()
    }

    var body: some View {
        NavigationStack(path: $path) {
            conversation
                .id(opening)
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .threadList:
                        ChatThreadListView(chatThreadRepository: PersistenceComposition.store) { summary in
                            // The tapped row's own id, not its subject — see this
                            // type's "Two ways to open something" for why resolving by
                            // subject here would be the defect, not a simplification.
                            opening = .threadID(summary.id)
                            // Selecting a thread opens it — it does not leave the list
                            // on screen underneath it.
                            path = NavigationPath()
                        }
                    }
                }
        }
    }

    @ViewBuilder
    private var conversation: some View {
        switch opening {
        case let .subject(subject):
            ChatConversationView(
                subject: subject,
                currentInterval: currentInterval,
                onOpenThreadList: { path.append(Route.threadList) },
                onStartNewChatForCurrentWindow: startNewTrainingChat,
                onDone: { dismiss() }
            )
        case let .threadID(threadID):
            ChatConversationView(
                threadID: threadID,
                currentInterval: currentInterval,
                onOpenThreadList: { path.append(Route.threadList) },
                onStartNewChatForCurrentWindow: startNewTrainingChat,
                onDone: { dismiss() }
            )
        }
    }

    // MARK: - New chat

    /// §3.4: "New chat" gives a newer window a real job. Resolves the *current*
    /// dashboard interval into a fresh, frozen `TrainingScope` and reassigns the sheet
    /// to open it by subject — a distinct scope opens (or continues) a distinct
    /// thread; an unchanged scope resumes the thread already open, which is correct
    /// rather than a duplicate (`ChatThreadRepository.mostRecentThread(for:)` is what
    /// resolves that, unchanged).
    private func startNewTrainingChat() {
        guard let currentInterval, let scope = try? TrainingScope(resolving: currentInterval) else { return }
        opening = .subject(.training(scope))
        path = NavigationPath()
    }

    private static func defaultInterval() -> TrendInterval? {
        guard let today = try? CalendarDay(Date(), in: .current) else { return nil }
        return try? TrendInterval.thisWeek(today: today)
    }
}
