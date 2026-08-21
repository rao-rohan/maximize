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
/// ## Three ways to open something (§2.2 vs §2.3, MAX-097 review, MAX-185)
///
/// `Opening` below mirrors `ChatModel`'s own `Opening` (private to that type, so this is
/// a second, App-layer value of the same shape rather than a shared one): a `.subject`
/// is what the Ask button and the scope-mismatch banner hand in, and
/// `ChatConversationView(subject:...)` resolves "the" thread for it exactly as
/// `ChatModel.load()` already does (`ChatThreadRepository.thread(for:newThreadID:at:)`,
/// newest activity wins). A `.newThread` is what **New chat** hands in — same subject,
/// but `ChatConversationView(startingNewThreadFor:...)` mints a fresh thread rather than
/// resolving one, exactly the way `ChatModel.init(startingNewThreadFor:...)`'s own
/// documentation explains. A `.threadID` is what selecting a row in the thread list
/// hands in, and `ChatConversationView(threadID:...)` opens *exactly* that thread.
///
/// **Why the second and third cases both have to exist, and why they're not the same
/// case.** Two training threads can legitimately share an identical frozen
/// `TrainingScope` — `ChatThreadRepository`'s own contract does not deduplicate
/// training subjects, because **New chat** over an unchanged window is the entire
/// point of the button (MAX-185 — this repository already permitted several
/// threads per scope; the toolbar item is the door to the second one). If the thread
/// list resolved a tapped row *by subject*, tapping the older of two such rows would
/// silently reopen the newer one — the list would show two conversations and only ever
/// let you reach one. Carrying the tapped row's own id through instead is what makes
/// the list mean what it shows. And if **New chat** reassigned `opening` to the same
/// `.subject(scope)` value the Ask button already produced, `.id(opening)` below would
/// not change on an unchanged scope — the exact defect this ticket fixes — so minting
/// has to be its own case, carrying a nonce that makes every tap distinct even when the
/// scope is not (see `.newThread`'s own doc comment).
///
/// `.subject` also carries a `continuityNote` (MAX-194) — nil on the two ordinary paths
/// above, and set to the one line `PlanConversationDoor` composed when a run's
/// conversation walked through its door instead. It is still `.subject`, not a fourth
/// case: the door resolves *the* training thread for a scope exactly the way the Ask
/// button and the banner do, and never mints (`openPlanConversation` below). The note
/// is a passenger on the same reassignment, not a different way of opening something.
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
        /// §4.6's handoff: `PlanAuthoringView`, prefilled from the accepted proposal
        /// (MAX-101).
        ///
        /// The **proposal** is the payload, not a draft and not a plan. `PlanProposal` is
        /// `Hashable` and carries no repository, so a navigation value is a legitimate
        /// place for it — and the screen it opens builds its own authoring session
        /// against storage, exactly as it does when opened by hand. Nothing about this
        /// route writes anything (A13).
        ///
        /// MAX-190 (`docs/CHAT-AUDIT.md` §2.6): the authoring screen this pushes always
        /// carries a non-nil proposal, which is exactly what tells
        /// `PlanAuthoringConversationalRoute` to disable its own "describe it in a
        /// conversation" button rather than let it present a second `ChatSheet` here.
        /// The bound is enforced there, in `MaximizeCore`, not by anything this case
        /// does — this file only needs to keep handing the proposal through.
        case planAuthoring(PlanProposal)

        /// §6.2, MAX-103: a chip tapped in the "Runs in this conversation" strip. Pushed
        /// rather than dismissing the sheet — the athlete came from a conversation and
        /// Back should return to it, the same reasoning `.planAuthoring`'s doc comment
        /// gives for its own push.
        case workout(UUID)
    }

    /// See this type's "Three ways to open something." Hashable so `.id(opening)` can
    /// key `ChatConversationView`'s identity on it.
    private enum Opening: Hashable {
        /// The Ask button and the scope-mismatch banner (`continuityNote` nil), and
        /// MAX-194's door (`continuityNote` set). See this type's own note on why the
        /// door is a passenger on this case rather than a fourth one.
        case subject(ChatSubject, continuityNote: String?)
        /// **New chat** (MAX-185). The `UUID` is identity for SwiftUI only — a
        /// nonce that guarantees `.id(opening)` changes on *every* tap, including a
        /// second tap on an unchanged scope, which is exactly the case `.subject`
        /// reassignment used to collapse into a no-op. It is never read as the minted
        /// thread's actual id — `ChatModel.init(startingNewThreadFor:...)` mints that
        /// id itself, the same way the resolve path already mints its own.
        case newThread(ChatSubject, UUID)
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
        _opening = State(initialValue: .subject(subject, continuityNote: nil))
        self.currentInterval = currentInterval ?? Self.defaultInterval()
    }

    var body: some View {
        NavigationStack(path: $path) {
            conversation
                .id(opening)
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .threadList:
                        ChatThreadListView(chatThreadRepository: PersistenceComposition.store) { threadID in
                            // The tapped row's own id, not its subject — see this
                            // type's "Three ways to open something" for why resolving
                            // by subject here would be the defect, not a
                            // simplification.
                            opening = .threadID(threadID)
                            // Selecting a thread opens it — it does not leave the list
                            // on screen underneath it.
                            path = NavigationPath()
                        }
                    case let .planAuthoring(proposal):
                        // Pushed rather than presented as a second sheet: the athlete is
                        // still inside one task — reviewing a plan they asked for — and a
                        // Back button that returns to the card is the right way out of a
                        // form they have not saved.
                        PlanAuthoringView(proposal: proposal)
                    case let .workout(workoutID):
                        WorkoutDetailView(workoutID: workoutID)
                    }
                }
        }
        // MAX-153. A full-height sheet dismisses on a downward drag, and by default that
        // gesture wins over a scroll view already at its top. In a chat that is the
        // wrong precedence: scrolling up to re-read an earlier answer and then flicking
        // back down is the ordinary way to use this screen, and one over-shoot of that
        // flick would throw the conversation away. `.scrolls` gives the transcript the
        // drag; **Done** and the sheet's own grabber area still dismiss.
        //
        // Nothing here touches the sheet's material. The system glasses a sheet itself —
        // `SettingsToolbar.swift` carries the argument for why we do not reapply it, and
        // this ticket did not find a reason to depart from it.
        .presentationContentInteraction(.scrolls)
    }

    @ViewBuilder
    private var conversation: some View {
        switch opening {
        case let .subject(subject, continuityNote):
            ChatConversationView(
                subject: subject,
                currentInterval: currentInterval,
                continuityNote: continuityNote,
                onOpenThreadList: { path.append(Route.threadList) },
                onStartNewChatForCurrentWindow: startNewTrainingChat,
                onAcceptProposal: openAuthoring(with:),
                onSelectRun: openWorkout(_:),
                onOpenPlanConversation: openPlanConversation(_:),
                onDone: { dismiss() }
            )
        case let .newThread(subject, _):
            ChatConversationView(
                startingNewThreadFor: subject,
                currentInterval: currentInterval,
                onOpenThreadList: { path.append(Route.threadList) },
                onStartNewChatForCurrentWindow: startNewTrainingChat,
                onAcceptProposal: openAuthoring(with:),
                onSelectRun: openWorkout(_:),
                onOpenPlanConversation: openPlanConversation(_:),
                onDone: { dismiss() }
            )
        case let .threadID(threadID):
            ChatConversationView(
                threadID: threadID,
                currentInterval: currentInterval,
                onOpenThreadList: { path.append(Route.threadList) },
                onStartNewChatForCurrentWindow: startNewTrainingChat,
                onAcceptProposal: openAuthoring(with:),
                onSelectRun: openWorkout(_:),
                onOpenPlanConversation: openPlanConversation(_:),
                onDone: { dismiss() }
            )
        }
    }

    // MARK: - Accepting a proposal (MAX-101, §4.6)

    /// Pushes the authoring screen, prefilled.
    ///
    /// A push, not a reassignment of `opening`: the conversation stays underneath, so
    /// Back returns to the card the athlete just read rather than to a transcript with
    /// nothing on it. Note what this does **not** do — it does not store, does not
    /// dismiss the sheet, and does not clear the proposal. The plan in force is unchanged
    /// until the athlete taps Save on the screen this opens (A13).
    private func openAuthoring(with proposal: PlanProposal) {
        path.append(Route.planAuthoring(proposal))
    }

    // MARK: - The runs strip (§6.2, MAX-103)

    /// A chip tapped: pushes that run's own detail screen on top of the conversation.
    private func openWorkout(_ workoutID: UUID) {
        path.append(Route.workout(workoutID))
    }

    // MARK: - New chat

    /// §3.4, MAX-185: "New chat" mints a genuinely new thread on the window the
    /// dashboard is showing right now — never reopens whatever is already open,
    /// scope unchanged or not. Resolves the *current* dashboard interval into a fresh,
    /// frozen `TrainingScope` and reassigns `opening` to `.newThread`, which
    /// `ChatModel.init(startingNewThreadFor:...)` mints unconditionally
    /// (`ChatThreadRepository.mostRecentThread(for:)` is deliberately never consulted
    /// on this path — see `Opening.newThread`'s own doc comment for why an equal scope
    /// used to make this a no-op).
    private func startNewTrainingChat() {
        guard let currentInterval, let scope = try? TrainingScope(resolving: currentInterval) else { return }
        opening = .newThread(.training(scope), UUID())
        path = NavigationPath()
    }

    // MARK: - MAX-194: the door to the plan's conversation

    /// A run's conversation asked for the training thread covering its own week.
    /// Reassigns `opening` to `.subject`, exactly the way the Ask button and the
    /// scope-mismatch banner already do — resolving *the* thread for `offer.scope`,
    /// never minting one (minting is `startNewTrainingChat`'s job, above, and reusing it
    /// here would leave a fresh, empty thread every time this door is used). The
    /// continuity note travels as this reassignment's passenger; see `Opening.subject`'s
    /// own documentation for why it is not a fourth case.
    ///
    /// `offer.scope` — which week this opens — and every word `offer` carries were
    /// decided once, by `PlanConversationDoor` (`MaximizeCore`, under test); this
    /// forwards the decision rather than making a second one.
    private func openPlanConversation(_ offer: PlanConversationDoor.Offer) {
        opening = .subject(.training(offer.scope), continuityNote: offer.continuityNote)
        path = NavigationPath()
    }

    private static func defaultInterval() -> TrendInterval? {
        guard let today = try? CalendarDay(Date(), in: .current) else { return nil }
        return try? TrendInterval.thisWeek(today: today)
    }
}
