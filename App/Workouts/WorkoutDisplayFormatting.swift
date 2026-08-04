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
        }
    }

    /// - Parameter session: nil means no plan governs the day (`WorkoutVerdict.scheduledSession`).
    static func describeScheduledSession(_ session: ScheduledSession?) -> String {
        guard let session else { return "No plan for this day" }
        switch session.kind {
        case .rest:
            return "Rest day"
        case .easy:
            return distanceSuffixed("Easy run", session)
        case .long:
            return distanceSuffixed("Long run", session)
        case .hard:
            return session.note.map { "Hard: \($0)" } ?? "Hard session"
        case .other:
            return session.note ?? "Other"
        }
    }

    private static func distanceSuffixed(_ base: String, _ session: ScheduledSession) -> String {
        guard let meters = session.distanceMeters else { return base }
        return String(format: "%@ · %.1f km", base, meters / 1_000)
    }

    static func distance(meters: Double) -> String {
        String(format: "%.1f km", meters / 1_000)
    }

    static let dateAndTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
