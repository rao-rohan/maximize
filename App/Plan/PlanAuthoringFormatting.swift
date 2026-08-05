import Foundation
import MaximizeCore

/// Plain-text labels for the plan-authoring screen (MAX-080).
///
/// The same split `WorkoutDisplayFormatting` makes: no decisions here, only copy.
/// Whether a version may take effect on a day, what it would govern, and whether a
/// draft converts are all `PlanAuthoringSession`'s answers; this turns an
/// already-decided value into words.
enum PlanAuthoringFormatting {

    static func describe(_ weekday: Weekday) -> String {
        switch weekday {
        case .monday: return "Monday"
        case .tuesday: return "Tuesday"
        case .wednesday: return "Wednesday"
        case .thursday: return "Thursday"
        case .friday: return "Friday"
        case .saturday: return "Saturday"
        case .sunday: return "Sunday"
        }
    }

    static func describe(_ kind: ScheduledSessionKind) -> String {
        switch kind {
        case .easy: return "Easy run"
        case .long: return "Long run"
        case .hard: return "Hard session"
        case .rest: return "Rest"
        case .other: return "Other"
        // Reachable now (MAX-137) through the lift slot's own picker, which is driven
        // by `ScheduledSessionKind.liftPrescribable` rather than `prescribable` — the
        // run slot's picker still excludes it, so this case never fires there.
        case .lift: return "Lift"
        }
    }

    static func describe(_ group: MuscleGroup) -> String {
        switch group {
        case .chest: return "Chest"
        case .back: return "Back"
        case .shoulders: return "Shoulders"
        case .arms: return "Arms"
        case .legs: return "Legs"
        case .core: return "Core"
        }
    }

    /// The lift slot's own empty-state copy — "Rest" and "Groups not stated" read as
    /// two different sentences on purpose, matching the distinction
    /// `LiftPrescriptionSummary` keeps in the core (A17).
    static func describe(_ summary: LiftPrescriptionSummary) -> String {
        switch summary {
        case .rest: return "Rest"
        case .unstatedGroups: return "Lift · groups not stated"
        case let .groups(groups):
            return "Lift · " + groups.ordered.map { describe($0) }.joined(separator: ", ")
        }
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
        var text = describe(session.liftPrescriptionSummary)
        if let note = session.note, !note.isEmpty {
            text += " · " + note
        }
        return text
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
        String(format: "%.1f %@", unit.converted(fromMeters: meters), unit.abbreviation)
    }

    static func describeSession(_ session: ScheduledSession, unit: DistanceUnit) -> String {
        var text = describe(session.kind)
        if let meters = session.distanceMeters {
            text += " · " + distance(meters, unit: unit)
        }
        if let note = session.note, !note.isEmpty {
            text += " · " + note
        }
        return text
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
