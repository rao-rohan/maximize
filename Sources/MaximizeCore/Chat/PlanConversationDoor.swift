import Foundation

/// A run's conversation gains a door to the training conversation that covers its own
/// week (MAX-194, `docs/CHAT-AUDIT.md` §3.5).
///
/// ## The gate this does not touch
///
/// `ChatModel.canDraftPlan` requires a training subject, and that gate is correct: a
/// `PlanProposal` built from one run's fact sheet would be inventing most of its
/// fields, exactly what MAX-175's never-invent rule forbids, and exactly what
/// `PlanProposal`'s own deliberately weak typing exists to catch. This type does not
/// relax that gate — it answers a different question: not "can a plan be drafted
/// here", but "where does an athlete standing in a run's conversation go to *reach* the
/// conversation where it can be".
///
/// ## Which training thread (the decision this ticket owns)
///
/// **The run's own week — never the dashboard's current window.** A workout thread's
/// fact sheet already carries `WorkoutContext.SurroundingWeek`, the exact Monday-first
/// week the run sits in (MAX-182, PRD-AMENDMENTS.md A29). The door therefore opens
/// *that* week — the one the fact sheet already described to the athlete — reusing its
/// bounds rather than resolving a second, independent notion of "which week" that
/// could disagree with it.
///
/// The alternative — the dashboard's current interval, the way **New chat** freezes one
/// — was rejected. A run opened from three weeks back would land the athlete on a
/// training thread about *this* week, which is not what "was this run consistent with
/// my plan" was asking about, and it is exactly the kind of silent disagreement between
/// a frozen scope and a live one that `ChatScopeNotice` exists to flag rather than
/// manufacture on arrival.
///
/// `TrainingScope(from:through:)` is built straight from `week.from`/`week.through` —
/// never re-derived through `CalendarDay.startOfTrainingWeek()` a second time, so the
/// target cannot disagree with the week already on screen.
///
/// ## How much continuity is honest
///
/// `Offer.continuityNote` is the entire carry-over: one line, shown once at the top of
/// the training thread this opens, naming the run the athlete came from. **It never
/// enters a prompt.** A workout thread and a training thread have different contexts by
/// design (D3) — a training thread is not shown that run's splits or heart-rate curve —
/// so replaying any part of the workout transcript into the training thread would tell
/// the model it had seen something it had not, which is exactly what MAX-175's
/// never-invent rule forbids from the other direction. `ChatConversationView` renders
/// the note as a screen-only caption; nothing in `ChatInstruction` or `ContextBuilder`
/// ever reads it, and it is never written to the stored thread.
///
/// ## Always offered, worded to the plan's presence
///
/// The door is offered on every ready workout thread. There is always a week for a run
/// to sit in — plan or no plan — the same way `WorkoutContext.surroundingWeek` itself is
/// unconditional once a workout thread reaches `.ready` (MAX-182). What changes is the
/// button's own words: when no plan governs that week, the label says so, using the
/// canonical phrase the rest of the app already uses for the same fact
/// (`PlanAuthoringFormatting.describe(.firstPlan)`, "No plan has been authored yet")
/// rather than inventing a second wording of it. The training thread still opens in
/// that case — a training thread with no plan in force is a real, ordinary state, not a
/// wall (`ChatModelTests.testATrainingWindowOpensBeforeAnyPlanIsAuthored`).
public enum PlanConversationDoor {

    /// What the door says, and where it goes — decided once, from the same context the
    /// fact sheet already rendered, never a second lookup.
    public struct Offer: Hashable, Sendable {
        /// The training thread this opens. Resolves *the* thread for this scope — the
        /// same "open the thread for this subject" path the Ask button and the
        /// scope-mismatch banner already use — and never mints a fresh one. Minting is
        /// **New chat**'s mechanism; reusing it here would leave a fresh, empty
        /// conversation about the same week's plan every single time this door is
        /// opened from any of that week's runs.
        public let scope: TrainingScope

        /// The composer accessory's label.
        public let buttonLabel: String

        /// What VoiceOver reads for the button — names the destination, not merely the
        /// action, per CLAUDE.md's "a VoiceOver label naming what it opens".
        public let accessibilityHint: String

        /// The one honest line of continuity, shown once at the top of the training
        /// thread this opens — screen only, never sent to a prompt. See this type's own
        /// "How much continuity is honest".
        public let continuityNote: String

        public init(scope: TrainingScope, buttonLabel: String, accessibilityHint: String, continuityNote: String) {
            self.scope = scope
            self.buttonLabel = buttonLabel
            self.accessibilityHint = accessibilityHint
            self.continuityNote = continuityNote
        }
    }

    /// - Parameters:
    ///   - week: the run's own Monday-first training week — `WorkoutContext`'s own
    ///     `surroundingWeek`, reused rather than re-derived, so the target can never
    ///     disagree with what the fact sheet already told the athlete.
    ///   - day: the run's calendar day. Already resolved by `ChatModel.workoutFacts` for
    ///     the thread's own title, and reused here for exactly the same reason — one
    ///     source for "which run, which day" rather than a second.
    ///   - activityType: the run's kind, named in the continuity note the same way a
    ///     workout thread's own title already names it (`ChatThreadTitle.workout`).
    /// - Returns: nil only when the week's own bounds cannot become a `TrainingScope` —
    ///   unreachable in practice, since `SurroundingWeek`'s own initializer already
    ///   guarantees `from...through` is a genuine seven-day, Monday-first range, but
    ///   handled rather than force-unwrapped (CLAUDE.md).
    public static func offer(
        for week: WorkoutContext.SurroundingWeek,
        day: CalendarDay,
        activityType: ActivityType
    ) -> Offer? {
        guard let scope = try? TrainingScope(from: week.from, through: week.through) else {
            return nil
        }
        let planGoverns = week.plan != nil
        let destination = "the training conversation for the week of \(scope.label)"
        return Offer(
            scope: scope,
            buttonLabel: planGoverns ? "Ask about the plan" : "Ask about starting a plan",
            accessibilityHint: planGoverns
                ? "Opens \(destination)."
                : "Opens \(destination). No plan has been authored yet.",
            continuityNote: "Continued from "
                + ChatThreadTitle.workout(WorkoutThreadFacts(day: day, activityType: activityType))
                + "."
        )
    }
}
