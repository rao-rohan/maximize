import Foundation

/// The formatters shared by every fact-sheet renderer in `Context/` (CHAT-FIRST-SPEC.md
/// §3.2, PRD-AMENDMENTS.md A12 rule 3).
///
/// `WorkoutFactSheet` was, until MAX-094, the only renderer, and it formatted its own
/// numbers. MAX-095 adds a second — a roll-up over many runs — and the two must not be
/// free to spell the same measurement two ways: `+4.2%` against `4.2 %` is a divergence
/// at the exact boundary D3 exists to close, even though both still live inside "one
/// context module" (D3/A12 §3.2: *"the two fact sheets must render the same measurement
/// identically... enforced mechanically or this claim rots"*). So every renderer calls
/// through here instead of formatting its own numbers, and there is exactly one place a
/// rounding or wording decision can be made — and one place `FactSheetFormattingAgreementTests`
/// can check it was made the same way twice.
///
/// ## Locale pinned to nil, always
///
/// A fact sheet is machine-facing text, not UI: it is read by Claude, not rendered on a
/// screen. `String(format:)` with a `nil` locale forces the POSIX ("C") locale — a point
/// decimal separator, ASCII digits — regardless of the device's region settings.
/// Without that pin, the same stored run would render a different prompt for an athlete
/// whose phone is set to a comma-decimal locale than for one set to a point-decimal
/// locale: what Claude is told about a run would change depending on where the athlete
/// is standing. That is D3's determinism guarantee failing quietly at a boundary nothing
/// else checks, so every formatter here pins locale rather than trusting a caller to.
enum FactSheetFormatting {
    static func number(_ value: Double) -> String {
        String(format: "%.0f", locale: nil, value)
    }

    static func bpm(_ value: Double?) -> String {
        guard let value else { return "not applicable — this workout has no heart-rate data" }
        return "\(number(value)) bpm"
    }

    static func distance(_ meters: Double?) -> String {
        guard let meters else { return "not recorded (indoor runs may report none)" }
        return "\(String(format: "%.2f", locale: nil, meters / 1000)) km"
    }

    static func duration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let remainder = total % 60
        if hours > 0 { return "\(hours)h \(minutes)m \(remainder)s" }
        if minutes > 0 { return "\(minutes)m \(remainder)s" }
        return "\(remainder)s"
    }

    static func pace(_ secondsPerKilometer: Double) -> String {
        let total = Int(secondsPerKilometer.rounded())
        return "\(total / 60):\(String(format: "%02d", locale: nil, total % 60))"
    }

    static func percent(_ fraction: Double) -> String {
        "\(String(format: "%.0f", locale: nil, fraction * 100))%"
    }

    static func signedPercent(_ fraction: Double) -> String {
        let sign = fraction >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.1f", locale: nil, fraction * 100))%"
    }

    /// "Monday".
    ///
    /// A fixed English table rather than a `DateFormatter`, for the same three reasons
    /// `CalendarDayLabel` gives for month names — chiefly that a prompt must not change
    /// with the device's region settings, which is the locale pin above restated for a
    /// word instead of a number.
    ///
    /// Moved here from `WorkoutFactSheet`'s private `weekdayName` (MAX-095) when
    /// `TrainingFactSheet` became its second caller: a roll-up that called a day
    /// "Tuesday" where the workout sheet called it "Tue" would be A12 rule 3 failing on
    /// a word rather than a figure.
    static func weekdayName(_ weekday: Weekday) -> String {
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

    /// The plan's ask for one day — "easy, 8.0 km", "hard (6 × 800m)", "rest".
    ///
    /// Moved here from `WorkoutFactSheet` (MAX-095) for the same reason as
    /// `weekdayName`: the training roll-up prints a scheduled session on every line, and
    /// two renderings of the same prescription is exactly the divergence A12 rule 3
    /// forbids.
    ///
    /// **The `%.1f` is deliberate and is not `distance(_:)`'s two places.** This is what
    /// the workout fact sheet has printed since MAX-014, and that sheet is the scorer's
    /// prompt: changing the rounding here would change every scoring call's input, which
    /// D3 forbids doing as a side effect of adding a second renderer. The two precisions
    /// coexist because they describe different things — a prescription written in whole
    /// and half kilometres, and a measured distance.
    static func scheduledSession(_ session: ScheduledSession) -> String {
        var parts = [session.kind.rawValue]
        if let distanceMeters = session.distanceMeters {
            parts.append("\(String(format: "%.1f", locale: nil, distanceMeters / 1000)) km")
        }
        if let note = session.note, !note.isEmpty {
            parts.append("(\(note))")
        }
        return parts.joined(separator: ", ")
    }

    /// The **lift** slot's ask — "lift, 45m 0s, muscle groups: chest, shoulders".
    ///
    /// Moved here from `WorkoutFactSheet` (MAX-181) the moment `TrainingFactSheet`'s plan
    /// block became its second caller — exactly what that private function's own doc
    /// comment said would happen. Not `scheduledSession(_:)` above: that function renders
    /// a prescribed *distance*, which no lift carries, and is silent about the two fields
    /// a lift's ask is actually written in, `durationSeconds` and `muscleGroups`.
    ///
    /// **Absences are omitted, not stated** — the opposite of `scheduledSession(_:)`'s own
    /// convention, and deliberately so: "lift on Tuesday, length unstated" and "lift on
    /// Tuesday, groups unstated" are ordinary asks a plan really makes (`ScheduledSession`
    /// documents both as distinct from rest), not gaps in a record, so there is nothing for
    /// a disclaimer to tell either reader that the short line does not already say.
    static func liftPrescription(_ session: ScheduledSession) -> String {
        var parts = [session.kind.rawValue]
        if let durationSeconds = session.durationSeconds {
            parts.append(duration(durationSeconds))
        }
        if !session.muscleGroups.isEmpty {
            // `ordered`, never the set's own iteration order: a prompt that shuffled its
            // muscle groups between two builds of the same context would be D3's
            // determinism failing on a word rather than on a number.
            parts.append("muscle groups: "
                + session.muscleGroups.ordered.map(\.rawValue).joined(separator: ", "))
        }
        let prescription = parts.joined(separator: ", ")
        // The note trails the list rather than joining it: it is a gloss on the whole
        // ask, not another item in it, and ", (upper body)" reads as a fourth field.
        guard let note = session.note, !note.isEmpty else { return prescription }
        return "\(prescription) (\(note))"
    }
}
