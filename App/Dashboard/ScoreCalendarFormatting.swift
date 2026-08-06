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
/// - **Glyph shape**, which since MAX-135 is decided one level further down, in
///   `MaximizeCore.ScoreCalendarGlyph`, for the reason that type documents: a channel CI
///   cannot see is not a channel. `.scored`/`.awaitingScore`/`.noVerdict` show what
///   activity was done; `.missed` shows a dedicated "not done" mark; `.partiallyMet`
///   shows a half-filled disc; `.missedWithUnjudgedSession` (MAX-159) shows that mark
///   ringed — four states on the *same* red fill, told apart by shape alone.
///   `.scheduledRest` and `.convertedRest` use two distinct rest glyphs for the
///   same reason, even though both sit on the same neutral fill.
/// - **VoiceOver label.** Every state gets a full sentence, not just a glyph name —
///   the strongest channel of all, since it does not depend on shape recognition
///   either. This one *does* already name the band, and since MAX-105 it also names the
///   plan: what was prescribed, and whether what happened matches it. The mixed day's
///   sentence is composed in the core (`ScoreCalendarCopy`) because on that state the
///   sentence is the only place the whole truth exists — see §7.2.
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

    /// **The table moved to `MaximizeCore.ScoreCalendarGlyph` in MAX-135**, and this is
    /// the passthrough that keeps `ScoreCalendarView`'s call site unchanged. The reason is
    /// the one CLAUDE.md gives for the whole core: the glyph is the channel that separates
    /// a day that went badly from a day that did not happen from a day that half happened,
    /// all three of which draw the same red — and while the mapping lived here, no test
    /// could see it, because `swift test` never compiles this target. See that type for
    /// each glyph's argument; `WCAGContrastTests` now asserts the distinctness they claim.
    static func systemImageName(for state: ScoreCalendarDayState) -> String {
        ScoreCalendarGlyph.symbolName(for: state)
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
        case .partiallyMet(let met, let unmet):
            // Composed in the core (`ScoreCalendarCopy`), not here: on a mixed day the
            // sentence is the *only* channel carrying which half was dropped and what the
            // other half scored, which makes it part of the state rather than a rendering
            // of it — see LIFTING-SPEC §7.2. This layer still owns the date prefix, so a
            // month cell and a year cell keep speaking their own dates.
            return "\(dayText): \(ScoreCalendarCopy.partiallyMetOutcome(met: met, unmet: unmet))"
        case .awaitingScore(let activityType):
            return "\(dayText): \(WorkoutDisplayFormatting.describe(activityType)), awaiting score."
        case .noVerdict(let activityType):
            // Not "awaiting score", and the clause after the dash is why: without it the
            // sentence is the same absence VoiceOver already speaks for a run whose score
            // is minutes away, and the athlete would be waiting on nothing. The reason is
            // one short clause because a calendar is read cell after cell.
            return "\(dayText): \(WorkoutDisplayFormatting.describe(activityType)), "
                + "recorded. Not scored — the plan scores runs."
        case .missedWithUnjudgedSession(let scheduledKind, let recorded):
            // Composed in the core for the reason the mixed day is (MAX-159): this cell
            // draws one fill and one mark, so the sentence is the only channel that can
            // say a session was recorded at all, which one, and whether a score is still
            // coming for it. This layer supplies the activity's name — its own vocabulary,
            // shared with the workout list and detail — and nothing else.
            return "\(dayText): " + ScoreCalendarCopy.missedWithUnjudgedSessionOutcome(
                scheduledKind: scheduledKind,
                recorded: recorded,
                describedAs: WorkoutDisplayFormatting.describe(recorded)
            )
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
        // A mixed day's outcome clause already names **both** of the day's asks — it is
        // built out of them — so an agreement clause here would say a third time what the
        // sentence has said twice. It would also be the wrong subject: `agreement`
        // describes the day's best-scored workout, which on a mixed day is the half that
        // went *well*, and appending "As planned: easy run." to a sentence about a skipped
        // lift reads as approval of the day.
        if case .partiallyMet = day.state { return nil }
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
            // `.missedWithUnjudgedSession` is in this list rather than beside
            // `.awaitingScore`/`.noVerdict` above, even though it too is a day with a
            // recorded, unscored session: its outcome clause already names the plan's ask
            // — the missed one — so "Planned: easy run." would say it a second time, and
            // on a day whose *other* slot was the one recorded it would name the wrong ask
            // entirely (`planClause` reads the run slot). The same reasoning that gives the
            // mixed day no plan clause.
            case .scored, .partiallyMet, .missed, .missedWithUnjudgedSession,
                 .convertedRest, .scheduledRest, .forthcoming, .unplanned:
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
        // Reachable as of MAX-135, on a day whose lift slot is prescribed: "missed lift",
        // "lift scheduled, not yet due", "rest — converted from a missed lift".
        case .lift: return "lift"
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
        // Still unreachable, and MAX-135 narrowed the path rather than opening it. It
        // takes a `.divergent` agreement whose performance is a lift, and `agreement` now
        // compares a scored workout against **its own slot's** ask: a lift is compared
        // with the lift ask, which `ScheduledSessionKind.liftPrescribable` allows to be
        // only `.lift` or `.rest` — so a scored lift is either `.asPrescribed` or, on a
        // rested slot, `.unprescribed`, and never "planned X; ran a lift". The verb here
        // would still be wrong if that ever changed; rewording it belongs with MAX-104's
        // copy pass over the lifting surfaces.
        case .lift: return "a lift"
        }
    }
}
