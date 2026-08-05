import Foundation
import MaximizeCore

/// Plain-text labels for the plan-authoring screen (MAX-080).
///
/// The same split `WorkoutDisplayFormatting` makes: no decisions here, only copy.
/// Whether a version may take effect on a day, what it would govern, and whether a
/// draft converts are all `PlanAuthoringSession`'s answers; this turns an
/// already-decided value into words.
///
/// ## The plan's vocabulary moved down to `PlanCopy` (MAX-101)
///
/// Weekday names, session kinds, muscle groups, distances and the one-line rendering of
/// a day's ask now live in `MaximizeCore.PlanCopy`, and the functions below call through
/// rather than restating them. They moved because a second reader appeared that is not a
/// screen: `PlanProposalReview` decides what the proposal card says, including its
/// per-field diff rows, and §4.6 makes that a core decision under test. Two renderings of
/// "Long run · 18.0 km" — one on the card, one on the form the card hands off to — would
/// be A12 rule 3's divergence arriving on the exact surface whose job is to let an
/// athlete compare two statements of a plan.
///
/// The names are kept here so no call site changed, and so this file stays the one place
/// the authoring screen's own copy (`describe(_ mode:)`, `explain(_ mode:)`,
/// `describeBothSessions`) is written.
enum PlanAuthoringFormatting {

    static func describe(_ weekday: Weekday) -> String {
        PlanCopy.weekday(weekday)
    }

    static func describe(_ kind: ScheduledSessionKind) -> String {
        PlanCopy.sessionKind(kind)
    }

    static func describe(_ group: MuscleGroup) -> String {
        PlanCopy.muscleGroup(group)
    }

    /// The lift slot's own empty-state copy — "Rest" and "Groups not stated" read as
    /// two different sentences on purpose, matching the distinction
    /// `LiftPrescriptionSummary` keeps in the core (A17).
    static func describe(_ summary: LiftPrescriptionSummary) -> String {
        PlanCopy.liftSummary(summary)
    }

    /// The compact caption above a weekday's two pickers — what a scanning eye reads
    /// before either slot's own detail.
    static func describe(_ summary: PlanDraft.DayDraft.ObligationSummary) -> String {
        switch summary {
        case .rest: return "Rest"
        case .runOnly: return "Run only"
        case .liftOnly: return "Lift only"
        case .both: return "Run + lift"
        }
    }

    /// A resolved lift `ScheduledSession`'s copy, for the preview section — reads
    /// identically to `describe(_ summary:)` above by going through the same
    /// `LiftPrescriptionSummary`, so a governed day and the draft that produced it never
    /// say the lift slot two different things.
    static func describeLiftSession(_ session: ScheduledSession) -> String {
        PlanCopy.liftSession(session)
    }

    static func describe(_ mode: PlanAuthoringSession.Mode) -> String {
        switch mode {
        case .firstPlan:
            return "No plan has been authored yet."
        case let .revision(supersedes, inEffectSince):
            return "Plan \(supersedes) has been in effect since \(inEffectSince)."
        }
    }

    /// Why authoring a first plan matters, stated as the consequence rather than as an
    /// instruction — the athlete's runs are already on the device and already unscored.
    static func explain(_ mode: PlanAuthoringSession.Mode) -> String {
        switch mode {
        case .firstPlan:
            return "Until a plan exists, runs are captured but not measured against anything: "
                + "no derived metrics, no score, and no chat. Runs already recorded on or "
                + "after the date below are completed the next time you open them. Runs "
                + "before it stay unscored permanently, because no later plan version is "
                + "ever allowed to reach further back — so choose the date with care."
        case .revision:
            return "Changing anything here saves a new plan version rather than editing the "
                + "current one. Runs already scored keep the plan, the cap and the rubric "
                + "they were scored under, so their scores stay reproducible."
        }
    }

    static func distance(_ meters: Double, unit: DistanceUnit) -> String {
        PlanCopy.distance(meters, unit: unit)
    }

    static func describeSession(_ session: ScheduledSession, unit: DistanceUnit) -> String {
        PlanCopy.session(session, unit: unit)
    }

    /// One line for a resolved day, both slots — what the "first week this version
    /// governs" preview shows, so reviewing a week means reading seven rows rather than
    /// fourteen (MAX-137). The lift half is omitted entirely when the day prescribes
    /// none, matching the run slot's own "just say what's asked" shape.
    static func describeBothSessions(_ planDay: PlanDay, unit: DistanceUnit) -> String {
        let run = describeSession(planDay.scheduledSession, unit: unit)
        guard !planDay.liftSession.isRest else { return run }
        return run + "  +  " + describeLiftSession(planDay.liftSession)
    }
}
