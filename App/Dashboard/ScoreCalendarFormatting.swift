import Foundation
import MaximizeCore

/// Plain formatting for `ScoreCalendarDayState` (FR-3.2): SF Symbol names and
/// VoiceOver copy. No decisions live here — which case a day is in was already
/// decided by `MaximizeCore.ScoreCalendar`; this only turns an already-decided case
/// into a glyph and a sentence, so there is exactly one place `ScoreCalendarView` and
/// any future consumer can drift on wording.
///
/// ## The accessibility channel this exists to carry
///
/// Color alone cannot carry the calendar's meaning (constraint #4 — a colour-blind
/// athlete cannot read hue). Two independent, redundant channels stand in for it,
/// and both are decided here rather than left to the view to reinvent per call site:
///
/// - **Glyph shape.** `.scored`/`.awaitingScore` show what activity was done;
///   `.missed` shows a dedicated "not done" mark rather than an activity icon, so a
///   scored-badly day (an activity glyph on red) and a missed day (an X on the same
///   red) never look alike even in grayscale. `.scheduledRest` and `.convertedRest`
///   use two visually distinct rest glyphs for the same reason, even though both sit
///   on the same neutral fill.
/// - **VoiceOver label.** Every state gets a full sentence, not just a glyph name —
///   the strongest channel of all, since it does not depend on shape recognition
///   either.
enum ScoreCalendarFormatting {

    // MARK: - Glyph

    static func systemImageName(for state: ScoreCalendarDayState) -> String {
        switch state {
        case .scored(_, let activityType):
            return systemImageName(for: activityType)
        case .awaitingScore(let activityType):
            return systemImageName(for: activityType)
        case .missed:
            return "xmark"
        case .convertedRest:
            return "moon.zzz"
        case .scheduledRest:
            return "moon.zzz.fill"
        case .unplanned:
            return "minus"
        }
    }

    private static func systemImageName(for activityType: ActivityType) -> String {
        switch activityType {
        case .running: return "figure.run"
        case .treadmillRunning: return "figure.run.square.stack"
        case .walking: return "figure.walk"
        case .hiking: return "figure.hiking"
        case .cycling: return "figure.outdoor.cycle"
        case .traditionalStrengthTraining: return "figure.strengthtraining.traditional"
        default: return "figure.mixed.cardio"
        }
    }

    // MARK: - VoiceOver label

    /// - Parameter date: for the leading "day N" clause; the state describes the
    ///   rest of the sentence.
    static func accessibilityLabel(for state: ScoreCalendarDayState, on date: CalendarDay) -> String {
        label(for: state, prefixedBy: "Day \(date.day)")
    }

    /// The same sentence, dated with its month.
    ///
    /// The year heatmap's cells carry no printed date at all, so "Day 14" would name one
    /// of twelve possible days — VoiceOver is the *only* channel that can disambiguate a
    /// heatmap cell, which makes it the one place the extra words are worth their
    /// length. See `ScoreCalendarRepresentation.weekColumnHeatmap`.
    static func heatmapAccessibilityLabel(for state: ScoreCalendarDayState, on date: CalendarDay) -> String {
        label(for: state, prefixedBy: "\(TrendIntervalFormatting.shortMonthName(for: date)) \(date.day)")
    }

    private static func label(for state: ScoreCalendarDayState, prefixedBy dayText: String) -> String {
        switch state {
        case .scored(let band, let activityType):
            return "\(dayText): \(WorkoutDisplayFormatting.describe(activityType)), \(bandLabel(band))."
        case .awaitingScore(let activityType):
            return "\(dayText): \(WorkoutDisplayFormatting.describe(activityType)), awaiting score."
        case .missed(let scheduledKind):
            return "\(dayText): missed \(kindLabel(scheduledKind))."
        case .convertedRest(let scheduledKind):
            return "\(dayText): rest — converted from a missed \(kindLabel(scheduledKind))."
        case .scheduledRest:
            return "\(dayText): scheduled rest day."
        case .unplanned:
            return "\(dayText): no plan for this day."
        }
    }

    private static func bandLabel(_ band: ScoreBand) -> String {
        switch band {
        case .effective: return "effective"
        case .marginal: return "marginal"
        case .ineffective: return "ineffective"
        }
    }

    private static func kindLabel(_ kind: ScheduledSessionKind) -> String {
        switch kind {
        case .easy: return "easy run"
        case .long: return "long run"
        case .hard: return "hard session"
        case .other: return "session"
        case .rest: return "rest day" // unreachable — `PlanDay.canBeMissed` excludes it.
        }
    }
}
