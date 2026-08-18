import Foundation

/// The **non-hue channel** every day-grid cell carries: which mark is drawn on it.
///
/// ## Why the symbol names live in the core
///
/// The same argument `DesignPalette` makes for hex values (MAX-070). The calendar's
/// accessibility claim is that two states sharing a fill are always told apart by
/// something other than colour — a red cell showing an activity glyph is a run that went
/// badly, a red cell showing an "×" is a day nothing happened on, since MAX-135 a red
/// cell showing a half-filled disc is a day that did one of the two things it was asked
/// for, and since MAX-159 a red cell showing a ringed "×" is a day that missed its ask and
/// trained at something no verdict has reached. That claim is only worth making if
/// something checks it, and while the mapping sat
/// in `App/Dashboard/ScoreCalendarFormatting.swift` nothing could: `swift test` never
/// compiles the app target. `WCAGContrastTests` now reads this table and asserts the
/// property directly, which is the difference between a channel and an opinion.
///
/// The app layer keeps the drawing — `Image(systemName:)`, sizing, `@ScaledMetric` — and
/// nothing but the drawing.
///
/// ## What this channel does and does not separate
///
/// It separates **day states**. It does not separate **bands**: `.scored` resolves to the
/// activity glyph regardless of how the run went, so an effective run and a marginal run
/// of the same type carry the same mark on two fills that measure 1.02:1 against each
/// other. `ScoreBandMark` (MAX-084) is the channel for that, and `ScoreBandHeatmapMark`
/// (MAX-087) the one for it at year density. One glyph cannot encode two orthogonal facts.
public enum ScoreCalendarGlyph {

    /// The SF Symbol a day-grid cell draws for `state`.
    public static func symbolName(for state: ScoreCalendarDayState) -> String {
        switch state {
        case .scored(_, let activityType):
            return symbolName(for: activityType)
        case .awaitingScore(let activityType):
            return symbolName(for: activityType)
        case .noVerdict(let activityType):
            // The activity, exactly as `.scored` and `.awaitingScore` show it. A lift is
            // a day the athlete trained, so the cell shows what they did; a mark meaning
            // "nothing to report here" would be the apology this state must not make.
            // The activity glyph is also the whole non-hue channel separating this state
            // from `.awaitingScore`, and it is free: the two can never carry the same
            // activity type (see `ScoreCalendarDayState.noVerdict`).
            return symbolName(for: activityType)
        case .partiallyMet:
            // **The whole channel this state gets, and it costs nothing** (§7.2: the cell
            // gains a state, not a channel). The fill is the miss red `.missed` already
            // draws — the worse verdict colours the day — so hue separates a mixed day
            // from nothing, and the mark has to do all of it. A disc filled on one side is
            // the one figure in this vocabulary that says "half of what was asked", it is
            // a shape rather than a colour value so it survives greyscale, every kind of
            // colour vision, Increase Contrast and Reduce Transparency alike, and it can
            // be confused with nothing else the cell draws: not the activity glyphs (all
            // figures), not `.missed`'s "×", not the rest crescents, and not
            // `ScoreBandMark`'s corner pip, which is a quarter its size and in a corner.
            //
            // Chosen over reusing the corner pip for the met half, which was the other
            // candidate: that slot's vocabulary is "which band is this fill", and putting
            // a *different* obligation's band in it would make MAX-084's one channel mean
            // two things on a fill that is not a band at all.
            return "circle.lefthalf.filled"
        case .missedWithUnjudgedSession:
            // **A miss, with something around it** (MAX-159). The fill is `.missed`'s own
            // red — the settled outcome colours the day — so this is the fourth state on
            // that one token and the mark carries the whole difference, as it does for the
            // other three.
            //
            // `.missed`'s "×" inside an enclosure, rather than a new figure, because the
            // enclosure is already this vocabulary's way of saying *the same thing, plus
            // more*: `.long` takes `figure.run.circle` against an easy run's `figure.run`
            // for exactly that reason. The day is a miss and it is not empty, which is one
            // more thing than "×" alone can say.
            //
            // Chosen over the recorded activity's own figure, which was the other
            // candidate: an activity glyph on this red is already `.scored(.ineffective,
            // _)`'s cell — a run that went badly — and a recorded run can land in both
            // states, so the two would collapse onto one drawing exactly where the
            // difference matters most.
            return "xmark.circle"
        case .missed:
            return "xmark"
        case .convertedRest:
            return "moon.zzz"
        case .scheduledRest:
            return "moon.zzz.fill"
        case .forthcoming(let scheduledKind):
            return symbolName(forScheduled: scheduledKind)
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
    private static func symbolName(forScheduled kind: ScheduledSessionKind) -> String {
        switch kind {
        case .easy: return "figure.run"
        case .long: return "figure.run.circle"
        case .hard: return "bolt"
        case .other: return "figure.mixed.cardio"
        // Unreachable: a scheduled rest day is `.scheduledRest` whether it is behind or
        // ahead of today, so `.forthcoming` never carries `.rest`. Mapped rather than
        // defaulted so a future `ScheduledSessionKind` case fails to compile here.
        case .rest: return "moon.zzz.fill"
        // Reachable as of MAX-135: a day whose lift slot is prescribed and whose run slot
        // rests is `.forthcoming(.lift)` ahead of today. The same glyph a recorded
        // strength session draws below, so the ask and the performance read as one
        // activity across the substrate and the figure.
        case .lift: return "figure.strengthtraining.traditional"
        }
    }

    private static func symbolName(for activityType: ActivityType) -> String {
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
}

/// What a calendar cell **says**, where what it draws cannot carry it.
///
/// The mixed day is the case that forces this into the core. A ~42pt cell can show one
/// fill and one mark, so it can say *that* the day was partly met; it cannot say which
/// half was dropped, what the other half scored, or whether the dropped half was skipped
/// outright or performed and judged short. LIFTING-SPEC §7.2 puts that whole truth in the
/// spoken sentence — "the full truth lives in the VoiceOver sentence and one level down,
/// on the day's detail" — which makes the sentence a load-bearing part of the state rather
/// than decoration on it, and load-bearing decisions live where CI can see them
/// (`PlanCopy` moved down for the same reason in MAX-101).
///
/// MAX-159's settled-miss day is here for the same reason and it is the stronger case:
/// that cell draws one red fill and one ringed "×", which cannot say *which* ask was
/// missed, nor that anything was recorded at all, nor whether the thing recorded is still
/// waiting on a score. All three live in the sentence, so all three live where CI can see
/// them.
///
/// The vocabulary is `PlanCopy`'s, so these days name their asks with the same words the
/// plan screen uses for them. It is one word away from `ScoreCalendarFormatting.kindLabel`
/// — `.other` is "other" here and "session" there — which predates this type and belongs
/// to MAX-104's copy pass over the lifting surfaces rather than to a calendar ticket.
public enum ScoreCalendarCopy {

    /// The spoken outcome for `ScoreCalendarDayState.partiallyMet` — everything after the
    /// cell's date, which the app layer prefixes ("Day 6: …", "Jan 6: …").
    ///
    /// Reads, for a Tuesday whose easy run scored effective and whose lift never happened:
    /// *"one of two sessions met. Easy run, effective; lift missed."* The headline first,
    /// because a calendar is read cell after cell and the first clause is the one that
    /// survives skimming; then the two halves, met before unmet, in the slot order every
    /// other list of a day's obligations uses.
    ///
    /// **"one of two" is arithmetic, not a figure of speech.** A day cannot hold more than
    /// two obligations — `Discipline` is closed at two cases and A17 says a third is an
    /// amendment, not a ticket — and this state needs one met and one unmet, so the day it
    /// describes has exactly two. `ScoreCalendarCopyTests` fails if that ever stops being
    /// true, which is the point at which this sentence needs rewriting rather than
    /// quietly lying.
    public static func partiallyMetOutcome(
        met: ScoreCalendarDayState.MetObligation,
        unmet: ScoreCalendarDayState.UnmetObligation
    ) -> String {
        "one of two sessions met. \(metClause(met)); \(unmetClause(unmet))."
    }

    /// The spoken outcome for `ScoreCalendarDayState.missedWithUnjudgedSession` —
    /// everything after the cell's date, which the app layer prefixes.
    ///
    /// Reads, for a Tuesday whose run was skipped and whose lift was recorded and not yet
    /// judged: *"missed easy run. Strength training recorded, awaiting score."* The miss
    /// leads, because it is the settled half and the reason the
    /// cell is red; the session follows, because a calendar read cell after cell must not
    /// open by congratulating a day it is about to call a miss.
    ///
    /// **The tense of the second clause is `ActivityType.isScoreable`, decided here.** A
    /// recorded run's or lift's score may still arrive, so it is *awaiting*; a ride, a
    /// hike or a walk will never be judged, so saying "awaiting" would promise a verdict
    /// that is not coming — MAX-126's whole argument, applied to the sentence rather than
    /// to the fill. It is the same predicate `ScoreCalendar.dayState` splits
    /// `.awaitingScore` from `.noVerdict` on, read here rather than stored twice.
    ///
    /// The clause itself stopped naming running in MAX-168, because the sentence stopped
    /// being about running: what is left in the unjudged half is the set of activities the
    /// plan has no rule for, and *"the plan has no rule for it"* is what that says without
    /// implying a lift is in it.
    ///
    /// - Parameter describedAs: what the recorded session is called, capitalised — the
    ///   one word this sentence does not own. `WorkoutDisplayFormatting.describe` is the
    ///   app layer's vocabulary for activity names, and it says the same words on the
    ///   workout list and the workout detail; a second name for a treadmill run composed
    ///   down here would be exactly the drift `ScoreCalendarCopy` exists to prevent. The
    ///   *shape* of the sentence — order, punctuation, tense, and how the missed ask is
    ///   named — is entirely this function's.
    public static func missedWithUnjudgedSessionOutcome(
        scheduledKind: ScheduledSessionKind,
        recorded: ActivityType,
        describedAs activityText: String
    ) -> String {
        let missed = lowercasedFirst(PlanCopy.sessionKind(scheduledKind))
        let verdict = recorded.isScoreable
            ? "awaiting score"
            : "not scored — the plan has no rule for it"
        return "missed \(missed). \(activityText) recorded, \(verdict)."
    }

    private static func metClause(_ met: ScoreCalendarDayState.MetObligation) -> String {
        "\(PlanCopy.sessionKind(met.kind)), \(bandLabel(met.band))"
    }

    /// A band where one was reached, "missed" where nothing of that discipline was
    /// recorded at all. The two are different failures with different fixes — one is a
    /// session to do better, the other is a session to do — and the cell's single mark
    /// cannot tell them apart.
    private static func unmetClause(_ unmet: ScoreCalendarDayState.UnmetObligation) -> String {
        let kind = lowercasedFirst(PlanCopy.sessionKind(unmet.kind))
        guard let band = unmet.judgedBand else { return "\(kind) missed" }
        return "\(kind), \(bandLabel(band))"
    }

    /// The band as it is spoken elsewhere on this calendar — lower case, since it is never
    /// the first word of its clause.
    private static func bandLabel(_ band: ScoreBand) -> String {
        switch band {
        case .effective: return "effective"
        case .marginal: return "marginal"
        case .ineffective: return "ineffective"
        }
    }

    /// `PlanCopy`'s vocabulary is written for a row in a table, so it capitalises; these
    /// clauses use it mid-sentence. Deliberately not `String.lowercased()` over the whole
    /// word, which would flatten a proper noun if one ever entered this vocabulary.
    private static func lowercasedFirst(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.lowercased() + text.dropFirst()
    }
}
