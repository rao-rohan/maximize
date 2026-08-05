import Foundation
import MaximizeCore

/// Plain-text labels for domain vocabulary the workouts list and detail screen both
/// need to print.
///
/// Deliberately just string formatting — no decisions live here. Which case applies
/// (scheduled vs. no plan, classified vs. unclassified) is `WorkoutVerdict`'s job
/// (MaximizeCore, unit tested); this only turns an already-decided case into copy, so
/// there is exactly one place a row and the header can drift on wording, and it is
/// this file.
enum WorkoutDisplayFormatting {

    static func describe(_ activityType: ActivityType) -> String {
        switch activityType {
        case .running: return "Running"
        case .treadmillRunning: return "Treadmill running"
        case .walking: return "Walking"
        case .hiking: return "Hiking"
        case .cycling: return "Cycling"
        case .traditionalStrengthTraining: return "Strength training"
        default: return activityType.rawValue.capitalized
        }
    }

    static func describe(_ classification: WorkoutClassification) -> String {
        switch classification {
        case .easy: return "Easy run"
        case .long: return "Long run"
        case .hard: return "Hard session"
        case .other: return "Other"
        // Unreachable today: `WorkoutClassifier` answers `.other` for every non-run, so
        // no stored `Score` carries `.lift` and this string cannot be drawn yet.
        case .lift: return "Lift"
        }
    }

    /// - Parameters:
    ///   - session: nil means no plan governs the day (`WorkoutVerdict.scheduledSession`).
    ///   - unit: MAX-047 — the athlete's chosen `DistanceUnit`. `ScheduledSession.distanceMeters`
    ///     stays in metres always (D2); this is the one place that converts it for copy.
    static func describeScheduledSession(_ session: ScheduledSession?, unit: DistanceUnit) -> String {
        guard let session else { return "No plan for this day" }
        switch session.kind {
        case .rest:
            return "Rest day"
        case .easy:
            return distanceSuffixed("Easy run", session, unit: unit)
        case .long:
            return distanceSuffixed("Long run", session, unit: unit)
        case .hard:
            return session.note.map { "Hard: \($0)" } ?? "Hard session"
        case .other:
            return session.note ?? "Other"
        case .lift:
            // The note is where a lift's ask lives ("45 min, lower body") until
            // `ScheduledSession` learns durations — MAX-113 closes tracker gap P3. Same
            // shape as `.other` above, and unreachable until a template can prescribe one.
            return session.note ?? "Lift"
        }
    }

    private static func distanceSuffixed(_ base: String, _ session: ScheduledSession, unit: DistanceUnit) -> String {
        guard let meters = session.distanceMeters else { return base }
        return String(format: "%@ · %.1f %@", base, unit.converted(fromMeters: meters), unit.abbreviation)
    }

    /// - Parameter unit: MAX-047 — the athlete's chosen `DistanceUnit`. `meters` is
    ///   always the stored figure (D2); this is the one place `WorkoutRow` converts it.
    static func distance(meters: Double, unit: DistanceUnit) -> String {
        String(format: "%.1f %@", unit.converted(fromMeters: meters), unit.abbreviation)
    }

    static let dateAndTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
