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
        }
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
}
