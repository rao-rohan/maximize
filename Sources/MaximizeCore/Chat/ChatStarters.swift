import Foundation

/// The tappable questions offered on an empty thread (§6.7, MAX-200).
///
/// ## What this replaces
///
/// `ChatConversationCopy.emptyTranscriptInvitation(for:)` names three example topics in
/// prose — "pacing, drift, whether it matched the plan" — and leaves the athlete to turn
/// one of them into a typed question. That is real friction at the exact moment a person
/// has just finished a run and has nothing queued up to ask. This type is the tap that
/// removes it.
///
/// ## Why a starter is not a generic sentence
///
/// A starter that reads the same on every thread — *"How am I doing?"* — teaches nothing
/// and is worth the same as no starter at all. The point of this feature is closer to a
/// tutorial than a convenience: since MAX-182/A29 a workout thread's context carries the
/// week around the session, and since MAX-192/A30 a training thread's carries strain per
/// session and acute:chronic load balance, and most athletes have no way to discover
/// either fact except by already knowing to ask for it. Each starter below names
/// something a specific section of that subject's own fact sheet can actually answer —
/// see the section references beside each one — so tapping one both answers a real
/// question and demonstrates a capability the athlete did not know the thread had.
///
/// ## Why every starter must stay inside the frozen scope
///
/// MAX-175's honest-refusal rule means a question the fact sheet cannot answer is not
/// silently reinterpreted — it is declined, in words, on screen. A starter is the app's
/// own suggestion, so a starter that trips that rule reads as the feature being broken
/// rather than the model being honest. Concretely: nothing below asks a training thread
/// to compare against a window outside its own frozen `TrainingScope` (§3.4, A11), and
/// nothing asks a workout thread about a *different* session than the one it is about —
/// `WorkoutFactSheet`'s "the week around this session" section states its own sibling
/// sessions' figures are not carried, and no starter here asks past that boundary either.
///
/// ## One set per kind, not per discipline
///
/// A workout thread only ever reaches the state that offers starters (`ChatModel
/// .LoadState.ready`) for a run or a lift — a ride, a hike or a walk resolve to
/// `.noVerdict` first (MAX-126, MAX-168) and the transcript this type feeds never draws.
/// So the three workout starters below are worded to hold for both disciplines rather
/// than branching on one: none of them names a run-only figure like pace or cadence,
/// because `WorkoutFactSheet` itself omits those for a lift (§10.1) and a starter that
/// asked for one on a lift thread would be asking the fact sheet for a line it does not
/// carry.
///
/// ## Fixed count, fixed order
///
/// Three of each — enough to show the athlete a range of what the thread can do,
/// deliberately short of "every section this fact sheet has," which would crowd an empty
/// screen and stop reading as a glance-able set at large Dynamic Type. Order is fixed so
/// a re-run of this file produces the same three rows in the same place; nothing here is
/// randomised or weighted by anything about the workout or window.
public enum ChatStarters {

    /// The starters for a thread of this kind, or an empty array when the kind is not
    /// yet known.
    ///
    /// Mirrors `ChatConversationCopy`'s optional-kind pattern for the same reason: a
    /// model opened by thread id can be mid-`.loading` before its subject has been read
    /// off the stored thread. In practice the screen that draws these never reaches that
    /// window — `ChatConversationView` only offers starters from `LoadState.ready`,
    /// where `ChatModel.subject` is always resolved — but this stays total rather than
    /// asking every call site to unwrap a value one of them cannot actually supply yet.
    /// An empty array is the honest answer: there is nothing to suggest about a subject
    /// this call does not know.
    public static func starters(for kind: ChatSubjectKind?) -> [String] {
        switch kind {
        case .workout: return workout
        case .training: return training
        case nil: return []
        }
    }

    // MARK: - Workout (`WorkoutFactSheet`)

    /// - `matchedThePlan`: **"The plan"** (the day's `prescriptionLine`) against
    ///   **"Measured"** and **"Score already assigned"** — the day's ask, what actually
    ///   happened, and the verdict already reached about the gap between them. Always
    ///   answerable: `ContextBuilder` never opens a workout thread before a score exists
    ///   (FR-2.1), so the score section this reads is always on the sheet.
    /// - `whatStrainMeans`: **"Measured" → `Strain`**, MAX-177. Deliberately about the
    ///   figure itself rather than a verdict on it — `strainLine`'s own doc comment
    ///   states the number is unbounded and not a 0–100 rating, which is exactly the
    ///   thing an athlete seeing it for the first time would not otherwise know to ask.
    /// - `weekContext`: **"The week around this session"**, MAX-182/A29. The newest
    ///   section on this sheet and the one an athlete has the least reason to already
    ///   know exists — this is its own tap target for it.
    private static let workout: [String] = [
        "Did this match what today's plan asked for?",
        "What does this session's strain number actually mean?",
        "How does this fit into my week so far?",
    ]

    // MARK: - Training (`TrainingFactSheet`)

    /// - `planAcrossBothSlots`: **"The plan in effect"**'s weekly template, which has
    ///   named a lift slot beside the run slot on every line since MAX-181, against
    ///   **"The tallies"**'s effective-sessions ratio. Exercises the fact this ticket's
    ///   brief calls out by name — a training thread now knows about lifting as well as
    ///   running, and this is the plainest question that needs both slots to answer.
    /// - `loadBalance`: **"The tallies" → acute:chronic load balance**, MAX-178/MAX-192,
    ///   A30. `ChatModel.trainingContext(for:)` always resolves a `LoadBalanceReading`
    ///   for a training thread (never a nil `ContextInputs.loadBalance`), so this is
    ///   answerable even when the reading is `.buildingHistory` — "not enough history
    ///   yet" is a real, worded answer, not a refusal.
    /// - `scoreDrag`: **"The tallies" → average score**, together with the
    ///   miscategorised-exclusion note MAX-160 attaches to it when part of the average
    ///   was excluded. Chosen over a question that ranks individual sessions
    ///   ("which scored highest") because a wide window can hold more sessions than
    ///   `TrainingContext.maximumRenderedSessions` carries (`sessionsWereWithheldByTheCap`)
    ///   — the aggregate this starter asks about is never withheld by that cap, so it
    ///   stays answerable at every window size a training thread can have.
    private static let training: [String] = [
        "Am I hitting the plan's ask on both my runs and lifts this window?",
        "What does my acute:chronic load balance look like right now?",
        "What's dragging my average score down this window, if anything?",
    ]
}
