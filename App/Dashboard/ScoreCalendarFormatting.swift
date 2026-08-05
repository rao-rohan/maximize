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
/// athlete cannot read hue). Two of the three redundant channels are decided here
/// rather than left to the view to reinvent per call site:
///
/// - **Glyph shape.** `.scored`/`.awaitingScore`/`.noVerdict` show what activity was
///   done; `.missed` shows a dedicated "not done" mark rather than an activity icon, so a
///   scored-badly day (an activity glyph on red) and a missed day (an X on the same
///   red) never look alike even in grayscale. `.scheduledRest` and `.convertedRest`
///   use two visually distinct rest glyphs for the same reason, even though both sit
///   on the same neutral fill.
///
///   **What the glyph does not do, and used to claim it did.** It separates *day
///   states*. It does not separate *bands*, because `.scored` resolves to the
///   activity glyph regardless of how the run went — so an effective run and a
///   marginal run of the same type are the same mark on two fills that measure
///   1.02:1 against each other. That is what `ScoreBand.mark` is for (MAX-084); it
///   is decided in `MaximizeCore` and drawn by `ScoreBandMarkView`, deliberately not
///   folded into `systemImageName(for:)` — one glyph cannot encode two orthogonal
///   facts, and activity is the one this function is named for.
/// - **VoiceOver label.** Every state gets a full sentence, not just a glyph name —
///   the strongest channel of all, since it does not depend on shape recognition
///   either. This one *does* already name the band, and since MAX-105 it also names the
///   plan: what was prescribed, and whether what happened matches it.
///
/// ## Why the plan is spoken in more detail than it is drawn (MAX-105)
///
/// The plan layer draws one bit — the cell is ringed, or it is not. The core knows more
/// than that: `ScoreCalendarDay.prescription` carries the session the versioned plan
/// asked for, and `.agreement` carries whether the run performed was that kind. Neither
/// is drawn, because a ~42pt cell already holds a fill, a date, a glyph and a band pip,
/// and a fourth visual distinction is the cell that needs a legend.
///
/// A sentence has no such budget. So the spoken label carries the whole comparison — "as
/// planned: easy run", "planned a long run, ran easy", "not on the plan" — which means
/// the athlete using VoiceOver gets *more* of the plan layer than the sighted one, not
/// less. That is the right way round for the asymmetry to fall.
enum ScoreCalendarFormatting {

    // MARK: - Glyph

    static func systemImageName(for state: ScoreCalendarDayState) -> String {
        switch state {
        case .scored(_, let activityType):
            return systemImageName(for: activityType)
        case .awaitingScore(let activityType):
            return systemImageName(for: activityType)
        case .noVerdict(let activityType):
            // The activity, exactly as `.scored` and `.awaitingScore` show it. A lift is
            // a day the athlete trained, so the cell shows what they did; a mark meaning
            // "nothing to report here" would be the apology this state must not make.
            // The activity glyph is also the whole non-hue channel separating this state
            // from `.awaitingScore`, and it is free: the two can never carry the same
            // activity type (see `ScoreCalendarDayState.noVerdict`).
            return systemImageName(for: activityType)
        case .missed:
            return "xmark"
        case .convertedRest:
            return "moon.zzz"
        case .scheduledRest:
            return "moon.zzz.fill"
        case .forthcoming(let scheduledKind):
            return systemImageName(forScheduled: scheduledKind)
        case .unplanned:
            return "minus"
        }
    }

    /// The glyph a day that has not happened yet carries: **what the plan asks for**,
    /// since there is no activity to report.
    ///
    /// This is the one place the calendar's glyph channel points forward rather than
    /// back, and it is what makes a future day answer "what am I doing Thursday" without
    /// a tap. It cannot be confused with a performed activity even though `.easy` shares
    /// `figure.run` with a recorded run: a forthcoming cell is drawn unfilled
    /// (`ScoreCalendarDayState.isDrawnUnfilledInTheDayGrid`), and no cell showing a
    /// performed activity ever is.
    ///
    /// `.long` takes the same runner inside a ring — the week's headline session as
    /// "more of the same thing", which is what a long run is — rather than a second,
    /// unrelated figure. `.hard` takes a bolt because intensity, not distance, is what
    /// separates it.
    private static func systemImageName(forScheduled kind: ScheduledSessionKind) -> String {
        switch kind {
        case .easy: return "figure.run"
        case .long: return "figure.run.circle"
        case .hard: return "bolt"
        case .other: return "figure.mixed.cardio"
        // Unreachable: a scheduled rest day is `.scheduledRest` whether it is behind or
        // ahead of today, so `.forthcoming` never carries `.rest`. Mapped rather than
        // defaulted so a future `ScheduledSessionKind` case fails to compile here.
        case .rest: return "moon.zzz.fill"
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

    /// The whole day, not just its state: the plan clause below needs the day's
    /// prescription and its agreement, which live beside the state rather than inside
    /// it (see `ScoreCalendarDay`).
    static func accessibilityLabel(for day: ScoreCalendarDay) -> String {
        label(for: day, prefixedBy: "Day \(day.date.day)")
    }

    /// The same sentence, dated with its month.
    ///
    /// The year heatmap's cells carry no printed date at all, so "Day 14" would name one
    /// of twelve possible days — VoiceOver is the *only* channel that can disambiguate a
    /// heatmap cell, which makes it the one place the extra words are worth their
    /// length. See `ScoreCalendarRepresentation.weekColumnHeatmap`.
    ///
    /// It carries the plan clause too, and there it does more work than anywhere else:
    /// the year heatmap draws no plan layer at all
    /// (`ScoreCalendarRepresentation.drawsThePlanLayer`), so this sentence is the only
    /// place a year's prescriptions exist.
    static func heatmapAccessibilityLabel(for day: ScoreCalendarDay) -> String {
        label(
            for: day,
            prefixedBy: "\(TrendIntervalFormatting.shortMonthName(for: day.date)) \(day.date.day)"
        )
    }

    private static func label(for day: ScoreCalendarDay, prefixedBy dayText: String) -> String {
        let outcome = outcomeClause(for: day.state, prefixedBy: dayText)
        guard let plan = planClause(for: day) else { return outcome }
        return "\(outcome) \(plan)"
    }

    private static func outcomeClause(
        for state: ScoreCalendarDayState,
        prefixedBy dayText: String
    ) -> String {
        switch state {
        case .scored(let band, let activityType):
            return "\(dayText): \(WorkoutDisplayFormatting.describe(activityType)), \(bandLabel(band))."
        case .awaitingScore(let activityType):
            return "\(dayText): \(WorkoutDisplayFormatting.describe(activityType)), awaiting score."
        case .noVerdict(let activityType):
            // Not "awaiting score", and the clause after the dash is why: without it the
            // sentence is the same absence VoiceOver already speaks for a run whose score
            // is minutes away, and the athlete would be waiting on nothing. The reason is
            // one short clause because a calendar is read cell after cell.
            return "\(dayText): \(WorkoutDisplayFormatting.describe(activityType)), "
                + "recorded. Not scored — the plan scores runs."
        case .missed(let scheduledKind):
            return "\(dayText): missed \(kindLabel(scheduledKind))."
        case .convertedRest(let scheduledKind):
            return "\(dayText): rest — converted from a missed \(kindLabel(scheduledKind))."
        case .scheduledRest:
            return "\(dayText): scheduled rest day."
        case .forthcoming(let scheduledKind):
            // Not "missed", and not merely the absence of one: the sentence says what is
            // coming, in the future tense, because that is the difference the whole
            // state exists to carry.
            return "\(dayText): \(kindLabel(scheduledKind)) scheduled, not yet due."
        case .unplanned:
            return "\(dayText): no plan for this day."
        }
    }

    /// The plan clause, appended only where the outcome clause has not already said what
    /// the plan asked.
    ///
    /// `.missed`, `.convertedRest`, `.scheduledRest`, `.forthcoming` and `.unplanned`
    /// are each already a statement about the plan, so a second clause would repeat
    /// itself — "missed easy run. Planned: easy run." VoiceOver users hear every word,
    /// and a calendar is read cell after cell; a redundant clause per day is a real cost.
    private static func planClause(for day: ScoreCalendarDay) -> String? {
        switch day.agreement {
        case .asPrescribed(let kind)?:
            return "As planned: \(kindLabel(kind))."
        case .divergent(let prescribed, let performed)?:
            return "Planned \(kindLabel(prescribed)); ran \(classificationLabel(performed))."
        case .unprescribed?:
            return "Not on the plan."
        case nil:
            // No score, so no classification to compare against (D2) — whether one is
            // coming (`.awaitingScore`) or never will be (`.noVerdict`). The ask is still
            // worth speaking on both: it is the whole reason the cell is ringed, and on a
            // day the athlete lifted through a prescribed run it is the only channel that
            // says the run was asked for at all.
            switch day.state {
            case .awaitingScore, .noVerdict:
                guard let prescription = day.prescription, prescription.canBeMissed else {
                    return "Not on the plan."
                }
                return "Planned: \(kindLabel(prescription.scheduledSession.kind))."
            case .scored, .missed, .convertedRest, .scheduledRest, .forthcoming, .unplanned:
                return nil
            }
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

    /// What the athlete actually did, as MAX-013's classifier judged it. Kept separate
    /// from `kindLabel` even though the words coincide: one describes an ask and the
    /// other a performance, and `WorkoutClassification` has no `.rest` to describe.
    private static func classificationLabel(_ classification: WorkoutClassification) -> String {
        switch classification {
        case .easy: return "easy"
        case .long: return "long"
        case .hard: return "hard"
        case .other: return "something else"
        }
    }
}
