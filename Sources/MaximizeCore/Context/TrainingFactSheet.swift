import Foundation

extension TrainingContext {
    /// The canonical rendering of a training window — the exact text a training thread
    /// puts in front of Claude (D3, A12).
    ///
    /// The second renderer in `Context/`, and the reason `FactSheetFormatting` exists.
    /// Every measurement that also appears on a workout fact sheet is formatted by the
    /// same function here, so `+4.2%` cannot become `4.2 %` across the boundary A12 rule 3
    /// names — `FactSheetFormattingAgreementTests` checks that on every commit rather than
    /// trusting it.
    ///
    /// ## Absence is stated once, not per line
    ///
    /// `WorkoutFactSheet` states every absent metric in place, because a single run's
    /// prompt has room to say *which kind* of nothing each one is. A roll-up does not:
    /// forty lines each carrying "Grade-adjusted pace: not applicable — indoor run" is the
    /// prompt spending its whole budget on absences. So the convention is inverted and
    /// **stated once, in the sessions preamble**: a field missing from a line was not
    /// recorded for that session (A18's rule at the scale of a line). What is never
    /// omitted is the verdict — an unscored session says *"no verdict"* in words, because
    /// a silently missing score reads as a zero, and MAX-111 leaves every non-run unscored
    /// by design.
    ///
    /// ## Deterministic by construction
    ///
    /// Fixed section order, fixed field order, fixed precision, no locale — the same
    /// discipline `WorkoutFactSheet` documents, and for the same reason: the same stored
    /// window must render byte-identically every time or D3's determinism quietly stops
    /// being true at the prompt boundary.
    public func factSheet() -> String {
        var lines: [String] = []

        lines.append("## The window")
        lines.append(contentsOf: windowLines)

        lines.append("")
        lines.append("## The plan in effect")
        lines.append(contentsOf: planLines)

        lines.append("")
        lines.append("## The tallies over this window")
        lines.append(contentsOf: talliesLines)

        lines.append("")
        lines.append("## Sessions in this window")
        lines.append(contentsOf: sessionLines)

        return lines.joined(separator: "\n")
    }

    // MARK: - The window (§3.3 item 4, §3.6(b))

    private var windowLines: [String] {
        [
            "\(scope.label) — \(scope.from) through \(scope.through), inclusive.",
            // §3.6(b): freezing is deliberate and cannot be prevented, so it is made
            // legible instead. The model is told the window is fixed so that an answer
            // quoting an aggregate can name it, which is what turns an ambush — a July
            // thread answering while the dashboard shows August — into a labelled
            // difference.
            "Every figure below is measured over exactly these days. This window is frozen "
                + "at the conversation's creation and does not move with the calendar, so it "
                + "may differ from the interval the app is showing right now. Name the window "
                + "whenever you quote a figure from it.",
        ]
    }

    // MARK: - The plan in effect (§3.3 item 1)

    private var planLines: [String] {
        guard let plan else {
            // Stated rather than left out, matching `WorkoutFactSheet`'s no-plan line: a
            // window from before the plan existed has no ask to be measured against, and a
            // model not told this may invent one.
            return ["No plan version was in effect at the end of this window, so the plan made "
                + "no ask for these days and there is nothing to compare the sessions below "
                + "against."]
        }

        var lines: [String] = []
        lines.append("Plan version: \(plan.version)")
        // Identical wording and identical formatters to `WorkoutFactSheet`'s plan block.
        // A cap the two renderers spelled differently would be A12 rule 3 failing on the
        // one number every easy-run answer turns on.
        lines.append("Heart-rate cap: \(FactSheetFormatting.bpm(plan.heartRateCapBPM))")
        lines.append("Cadence target: \(FactSheetFormatting.number(plan.cadenceTarget.lowStepsPerMinute))–"
            + "\(FactSheetFormatting.number(plan.cadenceTarget.highStepsPerMinute)) spm")
        lines.append("Effective-day threshold: \(plan.rubric.effectiveThreshold) / 100")
        lines.append("Marginal threshold: \(plan.rubric.marginalThreshold) / 100")

        if !plan.goals.statements.isEmpty {
            lines.append("Goals: \(plan.goals.statements.joined(separator: "; "))")
        }
        if let target = plan.goals.targetDay {
            lines.append("Target event: \(target)")
        }

        lines.append(arcWeekLine)

        switch planCoverage {
        case .wholeWindow:
            break
        case .beganWithinTheWindow:
            lines.append("Version \(plan.version) took effect on \(plan.effectiveFrom), inside this "
                + "window. The days before that were governed by no plan at all, so the plan made "
                + "no ask for them and nothing on them can have been missed.")
        case let .revisedWithinTheWindow(earlier):
            lines.append("Plan version \(earlier) governed the opening days of this window; version "
                + "\(plan.version) took effect on \(plan.effectiveFrom). The settings above are "
                + "version \(plan.version)'s, so sessions before that date were measured against a "
                + "different cap and different thresholds.")
        }

        // The whole template, every weekday, rather than the days that happen to prescribe
        // a run. Rest is an explicit ask (`WeeklyTemplate` makes it one), and "what does
        // the plan want on a Friday" is a question job two exists to answer. Rendering the
        // stored template wholesale is also what makes LIFTING-SPEC §10.2's requirement —
        // that the plan block carry the lift slot — arrive for free the moment
        // `WeeklyTemplate` grows one, instead of needing this renderer edited again.
        lines.append("Weekly template, Monday first:")
        for entry in plan.weeklyTemplate.entries {
            lines.append("\(FactSheetFormatting.weekdayName(entry.weekday)): "
                + "\(FactSheetFormatting.scheduledSession(entry.session))")
        }

        return lines
    }

    private var arcWeekLine: String {
        let week = tallies.currentWeek
        let span = "\(week.start) to \(week.end)"
        guard let index = currentArcWeekIndex else {
            return "Training week at the end of this window: \(span). No plan governs it, so it "
                + "has no arc week."
        }
        guard let distanceMeters = currentArcWeekDistanceMeters else {
            // `PlanCalendar` documents this as expected rather than broken: the arc is a
            // finite progression, and a plan that has run past its end is a plan wanting a
            // new version (D1).
            return "Training week at the end of this window: \(span), arc week \(index). The "
                + "arc has no entry for that week, so it prescribes no long-run distance."
        }
        return "Training week at the end of this window: \(span), arc week \(index), long run "
            + "prescribed: \(FactSheetFormatting.distance(distanceMeters))."
    }

    // MARK: - The tallies (§3.3 item 2, §3.6(a) and (c))

    private var talliesLines: [String] {
        var lines: [String] = []

        lines.append("Days with at least one workout: \(tallies.workoutDays)")

        let effective = tallies.effectiveDays
        if effective.rate == nil {
            // `EffectiveObligationTally` refuses to report 0 for an empty denominator, and the
            // prompt must not turn that refusal back into a zero: "nothing was eligible"
            // and "you failed every session" are opposite statements.
            lines.append("Effective days: nothing in this window was eligible — the plan asked "
                + "for rest, no plan governed these days, or their outcome is not yet known.")
        } else {
            // The exact string `TrendTileData` puts on the tile, so a figure quoted here
            // and a figure read on the dashboard cannot differ in shape or in rounding
            // (§3.6(a) and (c)).
            lines.append("Effective days: \(effective.effectiveCount)/\(effective.eligibleCount)")
        }

        if let averageScore = tallies.averageScore {
            // Through the tile's own formatter — §3.6(c): where a figure appears in both a
            // tile and a fact sheet, the fact sheet renders it at the tile's precision.
            lines.append("Average score: \(TrendTileData.formattedAverageScore(averageScore))")
        } else {
            lines.append("Average score: nothing in this window has been scored yet, so there is "
                + "no average. That is an absence of verdicts, not a low one.")
        }

        lines.append("Current streak: \(tallies.currentStreak) days")

        return lines
    }

    // MARK: - One line per session (§3.3 item 3, LIFTING-SPEC §10.2)

    private var sessionLines: [String] {
        guard sessionCountInScope > 0 else {
            return ["No workout was recorded in this window."]
        }

        guard !sessionsWereWithheldByTheCap else {
            return ["\(sessionCountInScope) sessions are on file for this window — beyond what "
                + "this summary carries, so none are listed. The plan and the tallies above "
                + "still describe the whole window. A question about individual sessions needs "
                + "a shorter window."]
        }

        var lines = ["One line per session — per session, not per day, because a day can hold "
            + "both a run and a lift and the plan asks for each separately."]
        // The exclusions, stated in the prompt rather than only in this file's
        // documentation, because §3.5 makes "say when you cannot answer" the model's job
        // and it cannot do that without knowing what it was not given.
        lines.append("This is a summary. It carries no per-kilometre splits, no heart-rate "
            + "curve, no route and no scoring rationale for any session here. A question needing "
            + "any of those is best answered in that session's own conversation — say so rather "
            + "than estimating.")
        lines.append("A field missing from a line was not recorded for that session.")
        lines.append(contentsOf: sessions.map(Self.line))
        return lines
    }

    private static func line(_ session: TrainingContext.Session) -> String {
        // Fixed field order, absent fields dropped rather than printed as "—".
        var fields = [
            "\(session.day) (\(FactSheetFormatting.weekdayName(session.day.weekday)))",
            performed(session),
            planned(session),
        ]
        if let distanceMeters = session.distanceMeters {
            fields.append("Distance: \(FactSheetFormatting.distance(distanceMeters))")
        }
        fields.append("Duration: \(FactSheetFormatting.duration(session.durationSeconds))")
        if let averageHeartRateBPM = session.averageHeartRateBPM {
            fields.append("Average heart rate: \(FactSheetFormatting.bpm(averageHeartRateBPM))")
        }
        if let drift = session.heartRateDriftFraction {
            fields.append("Heart-rate drift: \(FactSheetFormatting.signedPercent(drift))")
        }
        fields.append(verdict(session))
        return fields.joined(separator: " · ")
    }

    /// The discipline tag LIFTING-SPEC §10.2 asks for, plus the stored classification.
    ///
    /// Both, not either: the classification is what the rubric reasoned about and the
    /// activity type is what the athlete did, and `.other` covers a lift, a hike and a
    /// ride alike. `WorkoutVerdict` already decides which of the two is knowable — a
    /// session nothing has scored has no plan-aware classification, and inventing one
    /// here would be a second classifier free to disagree with the scorer's.
    private static func performed(_ session: TrainingContext.Session) -> String {
        switch session.verdict.actual {
        case let .classified(classification):
            return "\(session.activityType.displayName), classified \(classification.rawValue)"
        case let .unclassified(activityType):
            return "\(activityType.displayName), not yet classified"
        }
    }

    private static func planned(_ session: TrainingContext.Session) -> String {
        guard let scheduled = session.verdict.scheduledSession else {
            return "Planned: no plan version governed this day"
        }
        return "Planned: \(FactSheetFormatting.scheduledSession(scheduled))"
    }

    /// The verdict, or the word for its absence.
    ///
    /// Never omitted, unlike every other field on the line. A missing score reads as a
    /// zero or as a gap in the record, and it is usually neither: MAX-111 leaves every
    /// non-run unscored **by design**, permanently, because no band in the plan's rubric
    /// measures anything but a run. Those two absences are worded apart for the same
    /// reason `WorkoutFactSheet` words its three split absences apart.
    ///
    /// This ticket originally drew that distinction here, by asking the session whether
    /// its activity type was a run. MAX-126 landed the same distinction as two first-class
    /// cases on `WorkoutVerdict.Scoring`, so the switch below reads them instead of
    /// re-deriving one — the model must never be told a verdict is coming when the app
    /// knows it is not, and there should be exactly one place that decides which is true.
    ///
    /// The rationale the scorer wrote is deliberately not here — see `TrainingContext`.
    /// The correction is, because it is what the tallies count (§8), and a line quoting
    /// only the automatic score beside an average built from corrections would be the
    /// disagreement §3.6 exists to prevent.
    private static func verdict(_ session: TrainingContext.Session) -> String {
        switch session.verdict.scoring {
        case .awaitingScore:
            return "Score: no verdict yet — this run has not been scored"
        // Unreachable from here today, and required by the compiler: `ContextBuilder`
        // passes no muscle-group log, and `WorkoutVerdict` will not assert a state a
        // caller has not read (A22, MAX-145). The wording is here so the state has an
        // honest sentence the day a builder does supply one.
        case .awaitingMuscleGroups:
            return "Score: none yet — this lift is not scored until its muscle groups are set"
        case .noVerdict:
            return "Score: none — the plan's rubric scores runs, so this session is not scored"
        case let .scored(automatic, annotation):
            let assigned = "Score: \(automatic.value)/100 (\(automatic.band.rawValue))"
            guard let annotation else { return assigned }
            // No band on the correction: `ScoreBand` cannot be computed from a raw score
            // (D1) — only the scorer, reading the plan version in force, may do that — and
            // a manual correction is exactly a raw number with no stored band to read.
            // `WorkoutVerdict.Scoring` makes the same refusal for the same reason.
            return "\(assigned), corrected by hand to \(annotation.manualScore)/100"
        }
    }
}
