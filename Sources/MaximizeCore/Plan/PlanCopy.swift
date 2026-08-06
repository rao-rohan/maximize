import Foundation

/// The athlete-facing vocabulary of a plan — weekdays, session kinds, distances, and
/// the one-line rendering of a day's ask (MAX-101).
///
/// ## Why this is in the core rather than beside the screen that first needed it
///
/// `PlanAuthoringFormatting` (App layer) has spoken this vocabulary since MAX-080, and
/// for as long as the only reader was a form on screen that was the right place for it.
/// MAX-101 adds a second reader that is **not** a screen: `PlanProposalReview` decides
/// what a proposal card says, including its per-field diff rows, and CHAT-FIRST-SPEC.md
/// §4.6 makes that a core decision under test — "a model asked to drop Thursday to 6 km
/// may also, helpfully, move the cap to 148", and whether that shows up as a row is not
/// something a view may be trusted to work out.
///
/// So the words move down and `PlanAuthoringFormatting` calls through, exactly as
/// `PlanFormatting` already calls through to `PlanAuthoringFormatting`. The alternative
/// — the card spelling a session one way and the form it hands off to spelling it
/// another — is A12 rule 3's divergence arriving on the one surface whose entire job is
/// to let an athlete compare two renderings of a plan.
///
/// ## Locale
///
/// Unlike `FactSheetFormatting`, this text is read by a person, not by the model, so
/// `String(format:)` is left on the device's locale — a comma decimal separator is
/// correct here and wrong there. That difference is the reason these are two types and
/// not one.
public enum PlanCopy {

    // MARK: - Vocabulary

    public static func weekday(_ weekday: Weekday) -> String {
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

    public static func sessionKind(_ kind: ScheduledSessionKind) -> String {
        switch kind {
        case .easy: return "Easy run"
        case .long: return "Long run"
        case .hard: return "Hard session"
        case .rest: return "Rest"
        case .other: return "Other"
        case .lift: return "Lift"
        }
    }

    public static func muscleGroup(_ group: MuscleGroup) -> String {
        switch group {
        case .chest: return "Chest"
        case .back: return "Back"
        case .shoulders: return "Shoulders"
        case .arms: return "Arms"
        case .legs: return "Legs"
        case .core: return "Core"
        }
    }

    /// "Rest" and "Lift · groups not stated" read as two different sentences on
    /// purpose, matching the distinction `LiftPrescriptionSummary` keeps (A17).
    public static func liftSummary(_ summary: LiftPrescriptionSummary) -> String {
        switch summary {
        case .rest: return "Rest"
        case .unstatedGroups: return "Lift · groups not stated"
        case let .groups(groups):
            return "Lift · " + groups.ordered.map { muscleGroup($0) }.joined(separator: ", ")
        }
    }

    // MARK: - Figures

    public static func distance(_ meters: Double, unit: DistanceUnit) -> String {
        String(format: "%.1f %@", unit.converted(fromMeters: meters), unit.abbreviation)
    }

    public static func heartRateCap(_ bpm: Double) -> String {
        "\(Int(bpm)) bpm"
    }

    public static func cadenceBand(lowStepsPerMinute: Double, highStepsPerMinute: Double) -> String {
        "\(Int(lowStepsPerMinute))–\(Int(highStepsPerMinute)) spm"
    }

    /// "45 min", or "1h 15m" past an hour — the lift slot's prescribed length (MAX-148),
    /// rounded to the nearest minute since that is the resolution its editor offers.
    public static func duration(_ seconds: Double) -> String {
        let totalMinutes = Int((seconds / 60).rounded())
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 {
            return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
        }
        return "\(minutes) min"
    }

    /// A score threshold, as points. Bare rather than "82 points" because the two
    /// threshold rows the card draws already say which threshold they are, and the unit
    /// repeated on every row is noise on a dense surface.
    public static func scorePoints(_ points: Int) -> String {
        "\(points)"
    }

    /// "Aug 5, 2026" — the plan screens' own rendering of a `CalendarDay`, so a date on
    /// the plan tab and the same date inside a validation message
    /// (`PlanAuthoringError.description`) read identically. Pinned to GMT so the printed
    /// date never shifts against the device's own zone — a one-way bridge for display
    /// only, never read back into a `CalendarDay`, matching
    /// `TrendIntervalFormatting.date(for:)`'s own note.
    ///
    /// **Not `CalendarDayLabel`.** That type's "3 Aug 2026" is chat and the dashboard's
    /// own voice (MAX-092); this screen has used `MMM d, yyyy` since MAX-102, and MAX-104
    /// found two call sites that had drifted onto `CalendarDay.description`'s bare
    /// `YYYY-MM-DD` wire format instead of calling through here — moving the formatter
    /// down is what makes that mistake fail to compile a second time
    /// (`PlanFormatting.dayLabel` now calls straight through, matching every other
    /// vocabulary function in this type).
    public static func day(_ day: CalendarDay) -> String {
        dayFormatter.string(from: date(for: day))
    }

    private static func date(for day: CalendarDay) -> Date {
        var components = DateComponents()
        components.year = day.year
        components.month = day.month
        components.day = day.day
        components.hour = 12
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        // Unreachable for a valid `CalendarDay`; `Date()` rather than a force unwrap
        // because non-test code may not force-unwrap.
        return calendar.date(from: components) ?? Date()
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        formatter.timeZone = .gmt
        return formatter
    }()

    // MARK: - What a first plan's date costs (MAX-165, A23)

    /// What a candidate first effective date leaves permanently outside every plan
    /// version, in figures — or nil when it leaves nothing.
    ///
    /// The sentence `PlanAuthoringFormatting.explain(.firstPlan)` already carries states
    /// the permanence in prose. What it cannot state is the number, because the number
    /// depends on what is stored on the device, and a count of one's own runs is the
    /// difference between a caveat and a decision (CLAUDE.md: numerals do the hierarchy
    /// work).
    ///
    /// **Nil at zero, rather than "0 workouts fall before this date".** Absence is a
    /// designed state here in the strict sense: a date that costs nothing has nothing to
    /// report, and rendering a zero would turn the ordinary, correct case into a warning
    /// the athlete has to read and dismiss on every screen.
    ///
    /// "Workouts", not "runs": a lift is captured by the same pipeline, stranded by the
    /// same boundary, and counted here for the same reason.
    public static func excludedWorkoutsNotice(count: Int) -> String? {
        guard count > 0 else { return nil }
        let subject = count == 1
            ? "1 workout already recorded falls"
            : "\(count) workouts already recorded fall"
        let object = count == 1 ? "It" : "They"
        return "\(subject) before this date. \(object) can never be measured or scored: "
            + "no later plan version is allowed to reach back past the first one's start date."
    }

    // MARK: - A day's ask

    /// "Long run · 18.0 km · steady", the run slot's one-line rendering.
    public static func session(_ session: ScheduledSession, unit: DistanceUnit) -> String {
        var text = sessionKind(session.kind)
        if let meters = session.distanceMeters {
            text += " · " + distance(meters, unit: unit)
        }
        if let note = session.note, !note.isEmpty {
            text += " · " + note
        }
        return text
    }

    /// The lift slot's one-line rendering, which reads through
    /// `LiftPrescriptionSummary` so a governed day and the draft that produced it never
    /// say the lift slot two different things. Duration and note (MAX-148) follow the
    /// groups, through `liftDetail(durationSeconds:note:)`.
    public static func liftSession(_ session: ScheduledSession) -> String {
        let summary = liftSummary(session.liftPrescriptionSummary)
        guard let detail = liftDetail(durationSeconds: session.durationSeconds, note: session.note) else {
            return summary
        }
        return summary + " · " + detail
    }

    /// The lift's duration and note, rendered together — "45 min · lower body focus",
    /// "45 min" alone, "lower body focus" alone, or nil when neither is prescribed
    /// (MAX-148). Nil rather than an empty string, so `liftSession(_:)` can tell
    /// "nothing to add" from "add an empty clause", and a caller that wants a
    /// standalone label (the authoring screen's collapsed control) supplies its own
    /// designed-absence text for the nil case.
    public static func liftDetail(durationSeconds: Double?, note: String?) -> String? {
        var parts: [String] = []
        if let durationSeconds { parts.append(duration(durationSeconds)) }
        if let note, !note.isEmpty { parts.append(note) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
