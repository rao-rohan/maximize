import Foundation
import MaximizeCore

/// Plain-text labels for the read-only plan screen (MAX-102).
///
/// Same split every other `*Formatting` file in this app makes (`WorkoutDisplayFormatting`,
/// `PlanAuthoringFormatting`, `TrendIntervalFormatting`): no decisions live here, only
/// copy over values `PlanDisplayData` already resolved. Weekday names, session kinds and
/// distance strings are **not** re-derived — they call straight through to
/// `PlanAuthoringFormatting`, the authoring screen's own vocabulary, so a "Long run · 18.0
/// km" reads identically whether it is on the form you are editing or the screen you are
/// only looking at.
enum PlanFormatting {

    static func versionTitle(_ version: PlanVersion) -> String {
        "Plan \(version.description)"
    }

    /// "In effect since Jun 1, 2026" while `effectiveThrough` is nil (still current);
    /// "In effect Jan 5 – May 31, 2026" once it has one (superseded). Used both for the
    /// header's status line and each history row's subtitle — one sentence shape for
    /// "when did this version govern," current or not.
    static func effectiveRangeLine(effectiveFrom: CalendarDay, effectiveThrough: CalendarDay?) -> String {
        guard let effectiveThrough else {
            return "In effect since \(dayLabel(effectiveFrom))"
        }
        return "In effect \(dayLabel(effectiveFrom)) – \(dayLabel(effectiveThrough))"
    }

    static func targetDay(_ day: CalendarDay) -> String {
        "Target: \(dayLabel(day))"
    }

    static func heartRateCap(_ bpm: Double) -> String {
        "\(Int(bpm)) bpm"
    }

    static func cadenceTarget(_ band: CadenceBand) -> String {
        "\(Int(band.lowStepsPerMinute))–\(Int(band.highStepsPerMinute)) spm"
    }

    static func weekday(_ weekday: Weekday) -> String {
        PlanAuthoringFormatting.describe(weekday)
    }

    static func sessionKind(_ kind: ScheduledSessionKind) -> String {
        PlanAuthoringFormatting.describe(kind)
    }

    static func distance(_ meters: Double, unit: DistanceUnit) -> String {
        PlanAuthoringFormatting.distance(meters, unit: unit)
    }

    // MARK: - A weekday's two asks (MAX-138)

    /// The **run** slot's ask — kind, distance and note, exactly the string this
    /// screen printed for a weekday before this ticket. Unchanged byte-for-byte so a
    /// run-only plan (every lift slot rest — which is every plan authored before
    /// MAX-129, and every plan an athlete simply chose not to schedule lifting in)
    /// keeps reading exactly as it always has.
    static func runAsk(_ day: PlanDisplayData.WeekdayRow, unit: DistanceUnit) -> String {
        var text = sessionKind(day.kind)
        if let meters = day.distanceMeters {
            text += " · " + distance(meters, unit: unit)
        }
        if let note = day.note, !note.isEmpty {
            text += " · " + note
        }
        return text
    }

    /// The **lift** slot's ask. Calls straight through to
    /// `PlanAuthoringFormatting.describeLiftSession` (MAX-137) — the authoring
    /// screen's own preview and this read-only row say a lift the same way, always.
    static func liftAsk(_ session: ScheduledSession) -> String {
        PlanAuthoringFormatting.describeLiftSession(session)
    }

    /// The lines a weekday's row should show: one for a day with a single ask (rest,
    /// run only, or lift only), two only for a day carrying both. `obligationSummary`
    /// is `WeekdayRow`'s own decision (A17/MAX-137's shared vocabulary) about which of
    /// those four shapes a day is — this reads it rather than re-deriving it from
    /// `kind` and `liftSession` a second time.
    ///
    /// A day whose lift slot is rest never gets a "Rest" line of its own here, on
    /// either branch: that is what keeps a run-only week — pre-MAX-129 or simply
    /// unscheduled, the two are indistinguishable on disk and the copy does not
    /// pretend otherwise (see `PlanDisplayData.WeekdayRow`) — visually identical to
    /// the run-only screen this ticket found.
    static func weekdayLines(_ day: PlanDisplayData.WeekdayRow, unit: DistanceUnit) -> [String] {
        switch day.obligationSummary {
        case .rest, .runOnly:
            return [runAsk(day, unit: unit)]
        case .liftOnly:
            return [liftAsk(day.liftSession)]
        case .both:
            return [runAsk(day, unit: unit), liftAsk(day.liftSession)]
        }
    }

    static func threshold(effective: ScoreValue, marginal: ScoreValue) -> String {
        "Effective at \(effective.description) · Marginal at \(marginal.description)"
    }

    static func scoreRange(_ range: ScoreRange) -> String {
        range.description
    }

    /// "Any scheduled kind" when a band has no restriction, otherwise the kinds it
    /// applies to, in `ScheduledSessionKind`'s own declared order.
    static func appliesTo(_ kinds: [ScheduledSessionKind]) -> String {
        guard !kinds.isEmpty else { return "Any scheduled kind" }
        return kinds.map(sessionKind).joined(separator: ", ")
    }

    /// "Aug 5, 2026" — pinned to GMT so the printed date never shifts against the
    /// device's own zone, matching `TrendIntervalFormatting.date(for:)`'s own note:
    /// this is a one-way bridge for display only, never read back into a `CalendarDay`.
    static func dayLabel(_ day: CalendarDay) -> String {
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
}
