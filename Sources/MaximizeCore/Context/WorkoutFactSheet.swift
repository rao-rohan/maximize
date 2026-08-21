import Foundation

extension WorkoutContext {
    /// The canonical rendering of this context — the exact text both the scorer and the
    /// chat put in front of Claude (D3).
    ///
    /// Neither consumer may reformat, trim or extend it. What they add is the
    /// *instruction* around it: a rubric in one case, a conversation in the other. If
    /// the scorer ever sees a differently-worded fact sheet from the one chat sees, the
    /// two have started to disagree about the run and nothing on screen will say so.
    ///
    /// ## One renderer, two payloads
    ///
    /// `audience` selects how much of the record is here, and this is the only thing it
    /// selects (MAX-068). Every section the two share is rendered by the same code from
    /// the same stored numbers, so the scorer and chat still cannot describe the same
    /// measurement differently — a chat prompt is a superset of a scoring one, never a
    /// second wording of it.
    ///
    /// ## Absent metrics are stated, never omitted
    ///
    /// MAX-012 models "not applicable" distinctly from zero, and that distinction has to
    /// survive into the prompt. A silently missing line invites Claude to treat the
    /// metric as unmeasured — or worse, to reason about a number it was never given. So
    /// every metric appears exactly once, and the ones that do not apply say so and say
    /// why. "Drift: not meaningful for a hard session" is information; a blank is not.
    ///
    /// ## …except where the discipline, not the record, is what is missing (MAX-136)
    ///
    /// The rule above is about *this workout's* record. It is the wrong rule for a
    /// figure that could never describe the workout at all, and LIFTING-SPEC §10.1 names
    /// the failure it produced: a lift rendered as a run with most lines saying they do
    /// not apply, and two of them — the heart-rate cap and the cadence band — printing
    /// the plan's *running* settings under "The plan" as if they governed the session.
    ///
    /// So the rule inverts rather than lapsing, exactly as `TrainingFactSheet` inverts it
    /// for a roll-up. A lift's sheet omits those lines outright and says once, in
    /// `disciplineFraming`, that the omission is a fact about the discipline rather than
    /// a gap in the record. That is one sentence instead of nine headings that exist only
    /// to disclaim themselves, and it still closes the hazard the rule exists for: Claude
    /// is told why the page is short, so it cannot reason from the shortness.
    ///
    /// This is **one renderer with a discipline branch**, not a second renderer and not a
    /// second entry point (A12). Every figure both branches carry goes through the same
    /// `FactSheetFormatting` function, so A12 rule 3 holds by construction.
    ///
    /// The branch is on the *discipline* — the slot the plan judges this workout against
    /// — and not on the narrower `ActivityType.isRun`. A hike and a ride sit in the run
    /// slot by A17, and they render exactly as they did before this ticket. Whether the
    /// running-form figures (`DerivedMetricKind`'s `.runningActivity` set) should be
    /// omitted for those too is a real question and a different one; it changes a
    /// scoring prompt for workouts A17 did not move, so it is not taken here.
    ///
    /// ## Deterministic by construction
    ///
    /// Fixed field order, fixed precision, no locale. The same context must render
    /// byte-identically every time or D2's "one set of stored numbers" quietly stops
    /// being true at the prompt boundary.
    public func factSheet() -> String {
        var lines: [String] = []
        // The one branch, read once and named, so every use below reads as the same
        // decision rather than as six independent ones.
        let describesARun = discipline == .run

        lines.append("## Workout")
        lines.append("Date: \(day) (\(weekdayName))")
        lines.append("Type: \(workout.activityType)")
        if describesARun {
            // A lift's setting is not a fact about the session: this line exists to say
            // why there is no route, and a lift's sheet asks after none.
            lines.append("Setting: \(workout.hasRoute ? "outdoor (GPS route recorded)" : "indoor (no route)")")
        }
        lines.append("Duration: \(FactSheetFormatting.duration(workout.durationSeconds))")
        if describesARun {
            lines.append("Distance: \(FactSheetFormatting.distance(workout.distanceMeters))")
        }
        lines.append("Active energy: \(Self.energy(workout.activeEnergyKilocalories))")
        // Kept for a lift. It is not running vocabulary — `WorkoutClassification` has a
        // `.lift` case (§9.3) — and it is the single input the rubric's bands select on,
        // so a prompt that hid it would hide what the scorer reasoned from. It reads
        // `other` until MAX-133 teaches the classifier to answer `.lift`; that is honest
        // about today's record rather than a claim this renderer should be making.
        lines.append("Classified as: \(classification.rawValue)")
        if !describesARun {
            lines.append(Self.disciplineFraming)
        }

        lines.append("")
        lines.append("## The plan")
        if let plan {
            lines.append("Plan version: \(plan.version)")
            if describesARun {
                // §10.1's sharpest finding: both of these are the plan's *run* settings.
                // `heartRateCapBPM` is documented as the easy-run ceiling and the cadence
                // band is steps per minute against a running gait, so printing either
                // under "The plan" on a lift asserts an ask that was never made.
                lines.append("Heart-rate cap: \(FactSheetFormatting.bpm(plan.heartRateCapBPM))")
                lines.append("Cadence target: \(FactSheetFormatting.number(plan.cadenceTarget.lowStepsPerMinute))–"
                    + "\(FactSheetFormatting.number(plan.cadenceTarget.highStepsPerMinute)) spm")
            }
            if let scheduledSession {
                lines.append("Scheduled for this day: \(prescriptionLine(scheduledSession))")
            }
            if !plan.goals.statements.isEmpty {
                lines.append("Goals: \(plan.goals.statements.joined(separator: "; "))")
            }
            if let target = plan.goals.targetDay {
                lines.append("Target event: \(target)")
            }
        } else {
            // Stated rather than left out. A run from before the plan existed has no ask
            // to be measured against, and a scorer that is not told this may invent one.
            lines.append("No plan version was in effect on this date, so the plan made no "
                + "ask for this day and there is nothing to compare against.")
        }

        lines.append("")
        lines.append("## Measured")
        // Both disciplines. A heart rate measured during a lift is a heart rate —
        // `DerivedMetricKind` says so, and it is the one rich signal a lift gives us free.
        lines.append("Average heart rate: \(FactSheetFormatting.bpm(metrics.averageHeartRateBPM))")
        lines.append("Maximum heart rate: \(FactSheetFormatting.bpm(metrics.maximumHeartRateBPM))")
        if describesARun {
            // `DerivedMetricKind`'s `.runDiscipline` pair, plus the two of its
            // `.runningActivity` set that this section prints. Every one of them is nil
            // for a lift after MAX-130 — but a lift ingested *before* MAX-130 has stored
            // numbers for the last two, so this is a guard and not a formality.
            lines.append("Time above cap: \(timeAboveCapLine)")
            lines.append("Heart-rate drift: \(driftLine)")
            lines.append("Average cadence: \(cadenceLine)")
            lines.append("Grade-adjusted pace: \(gradeAdjustedPaceLine)")
        }
        // §3.3 keeps zone splits for a lift: they are a neutral description of how the
        // session's heart rate was distributed, they cost nothing extra, and they are the
        // only thing in the record that could tell a lifting session apart from a walk.
        lines.append("Time in zones: \(zoneLine)")
        // MAX-176/MAX-177. Both disciplines, like the two heart-rate lines above it:
        // `DerivedMetricKind.strain` is `.anyDiscipline`, because it is a read of
        // `zoneSplits`, which is too. Its own line explains the unit and the two things
        // a bare number would invite Claude to assume — see `strainLine`.
        lines.append("Strain: \(strainLine)")

        if let heartRateShape {
            lines.append("")
            lines.append("## Heart-rate shape")
            lines.append("Average bpm per tenth of elapsed time, so the curve can be read "
                + "without the underlying samples:")
            lines.append(heartRateShape.buckets
                .map { "\(FactSheetFormatting.percent($0.startFraction)) \(FactSheetFormatting.number($0.averageBeatsPerMinute))" }
                .joined(separator: " · "))
        }

        // Chat only (MAX-068), and runs only (MAX-136). The section is absent from a
        // scoring prompt entirely — not stated-as-absent — because for the scorer this is
        // not a metric that happens to be missing, it is a part of the record the scorer
        // is never shown, like the route coordinates. It is absent from a lift's prompt
        // for a third reason again: §10.1 asks for no splits section at all, and the
        // three absences the wording below distinguishes are all facts about a *run*.
        if audience == .chat, describesARun {
            lines.append("")
            lines.append("## Pace by \(Self.unitName)")
            lines.append(contentsOf: paceBreakdownLines)
        }

        if let existingScore {
            lines.append("")
            lines.append("## Score already assigned")
            lines.append("\(existingScore.value) / 100 — \(existingScore.band.rawValue)")
            lines.append("Rationale given: \(existingScore.rationale)")
        }

        // Chat only (MAX-182), and last: the record of this session is complete above, and
        // what follows is orientation around it rather than more of it. Absent from a
        // scoring prompt entirely — not stated-as-absent — because for the scorer this is
        // not a fact that happens to be missing, it is data the rubric must not be able to
        // reach. See `WorkoutContext.surroundingWeek`.
        if audience == .chat, let surroundingWeek {
            lines.append("")
            lines.append("## The week around this session")
            lines.append(contentsOf: Self.surroundingWeekLines(surroundingWeek))
        }

        return lines.joined(separator: "\n")
    }

    private var weekdayName: String {
        FactSheetFormatting.weekdayName(day.weekday)
    }

    // MARK: - Discipline (LIFTING-SPEC §10.1)

    /// Why a lift's sheet is short, said once instead of nine times.
    ///
    /// The hazard this renderer's absence rule guards against is Claude reasoning from a
    /// gap, and omitting the running figures for a lift would reopen exactly that hazard
    /// if nothing were said. So the rule is not dropped, it is moved: one sentence at the
    /// top of the record instead of a disclaimer on every line it would have applied to.
    /// `TrainingFactSheet` makes the identical trade for the identical reason at the
    /// scale of a roll-up, and this is the same convention read at the scale of a page.
    ///
    /// Worded without naming the figures it is standing in for. Naming them would put
    /// "cadence", "pace" and "cap" back into a lift's prompt to say they do not apply,
    /// which is the token spend §10.1 objected to, in a different shape.
    private static let disciplineFraming =
        "This was a lift, not a run. The figures a run is measured by are absent below "
        + "rather than empty: they do not describe this session and were never computed "
        + "for it, so read nothing into their absence and do not judge the session by them."

    /// The day's ask, rendered in the vocabulary of the slot it came from.
    ///
    /// The one place this renderer's two branches meet a shared value, and they must not
    /// meet it the same way: a run's ask is written in kilometres and a lift's in minutes
    /// and muscle groups (MAX-131, A22).
    private func prescriptionLine(_ session: ScheduledSession) -> String {
        switch discipline {
        case .run: return FactSheetFormatting.scheduledSession(session)
        // Moved to `FactSheetFormatting.liftPrescription` (MAX-181) the moment
        // `TrainingFactSheet`'s plan block became its second caller — see that
        // function's own doc comment for why it lived here alone until then, and for
        // the omission rule §10.1 and this ticket both lean on.
        case .lift: return FactSheetFormatting.liftPrescription(session)
        }
    }

    // MARK: - Lines that must explain their own absence

    private var timeAboveCapLine: String {
        guard let seconds = metrics.timeAboveCapSeconds else {
            return "not applicable — this workout has no heart-rate data"
        }
        return FactSheetFormatting.duration(seconds)
    }

    private var driftLine: String {
        guard let drift = metrics.heartRateDriftFraction else {
            // §9: drift is near-meaningless on interval and hard sessions, so MAX-012
            // withholds it rather than emitting a number nobody should act on. Say which
            // reason applies — "no data" and "not meaningful here" are different facts.
            return metrics.hasHeartRateData
                ? "not meaningful for a \(classification.rawValue) session, so it was not computed"
                : "not applicable — this workout has no heart-rate data"
        }
        return FactSheetFormatting.signedPercent(drift)
    }

    private var cadenceLine: String {
        guard let cadence = metrics.averageCadenceStepsPerMinute else {
            return "not recorded for this workout"
        }
        guard let plan else { return "\(FactSheetFormatting.number(cadence)) spm" }
        let verdict = plan.cadenceTarget.contains(cadence) ? "within" : "outside"
        return "\(FactSheetFormatting.number(cadence)) spm (\(verdict) the target band)"
    }

    private var gradeAdjustedPaceLine: String {
        guard let pace = metrics.gradeAdjustedPaceSecondsPerKilometer else {
            // The common case is a treadmill run, which FR-0.6 treats as first-class.
            return workout.hasRoute
                ? "not available for this workout"
                : "not applicable — indoor run, so there is no grade to correct for"
        }
        return "\(FactSheetFormatting.pace(pace)) per km"
    }

    private var zoneLine: String {
        let present = HeartRateZone.allCases.compactMap { zone -> String? in
            let seconds = metrics.zoneSplits.seconds(in: zone)
            guard seconds > 0 else { return nil }
            return "zone \(zone.rawValue) \(FactSheetFormatting.duration(seconds))"
        }
        return present.isEmpty ? "not applicable — no heart-rate data" : present.joined(separator: ", ")
    }

    /// States its own absence — MAX-175's rule that the record says what it does not
    /// know rather than leaving Claude to supply a figure — and, when present, the two
    /// things a bare number invites a model to assume: that it is a bounded rating, and
    /// (A20) that it says anything about what was on the bar.
    ///
    /// **Two absences, worded apart, the same distinction `driftLine` already makes.**
    /// `strain == nil` while `hasHeartRateData` is true is a real, common state rather
    /// than a contradiction: MAX-176 rescored nothing already stored (D8), so a workout
    /// ingested before it shipped has heart-rate data and no strain until something puts
    /// it back through the metrics pipeline. Reading `metrics.strain` — never a fallback
    /// off `averageHeartRateBPM` — is what tells that state apart from a workout with no
    /// heart-rate series at all.
    ///
    /// Guarded on `metrics.strain` directly, never on `zoneSplits` being non-empty,
    /// which matters for a second, narrower case: `WorkoutStrain`'s doc comment names a
    /// curve that covers no span (a single sample) as a *recorded* strain of `0` and
    /// *empty* zone splits — one fact ("measured, and containing nothing") rather than
    /// two in tension — and reading `strain` itself keeps this line from misreading that
    /// workout as the same absence the line directly above states for it.
    private var strainLine: String {
        guard let strain = metrics.strain else {
            return metrics.hasHeartRateData
                ? "not yet computed for this workout, so there is no figure to read"
                : "not applicable — this workout has no heart-rate data"
        }
        guard strain.points > 0 else {
            return "0 zone-weighted minutes — its heart-rate curve covers no time span (a "
                + "single sample), which is a different fact from the line above having no "
                + "heart-rate data at all"
        }
        return "\(FactSheetFormatting.number(strain.points)) zone-weighted minutes. Unbounded, "
            + "not a 0–100 score: a bigger number can mean a longer session, a harder one, or "
            + "both, and it does not distinguish them. Heart rate only — it says nothing "
            + "about sets, reps, or load, on a lift or otherwise."
    }

    // MARK: - Pace breakdown (MAX-068)

    /// The splits, or a sentence saying which kind of nothing this is.
    ///
    /// Three absences, deliberately worded apart. "There was never a track to cut up"
    /// is a fact about the run; "we hold no breakdown for it" is a fact about our
    /// records, and a run captured before the app computed splits is the common case
    /// today. Collapsing them would tell Claude that a run had no per-kilometre
    /// variation when what we mean is that we did not measure it — and Claude would
    /// then reason confidently from a gap.
    private var paceBreakdownLines: [String] {
        guard let paceBreakdown else {
            guard workout.hasRoute else {
                return ["Not applicable — indoor run, so nothing recorded when each "
                    + "\(Self.unitName) fell. The distance and duration above are still real."]
            }
            return ["Not recorded for this run: either its GPS track could not be cut into "
                + "splits, or the run was captured before this app computed them. This is a "
                + "gap in what was stored, not a run that had no \(Self.unitName) splits — "
                + "do not read it as an even pace."]
        }

        let splits = paceBreakdown.splits
        guard splits.count <= WorkoutContext.maximumRenderedSplits else {
            // A count this high means the stored distance is wrong, not that somebody ran
            // an ultra. Say what is on file and list none of it.
            return ["\(splits.count) splits are on file for this run, which is beyond what a "
                + "plausible run produces and beyond what this summary carries, so none are "
                + "listed. Treat the distance above with suspicion."]
        }

        var lines = ["Pace over each \(Self.unitName) of the run, in order, as "
            + "minutes:seconds per \(Self.unitName). This is what relates a distance to a "
            + "point on the heart-rate shape above, which is on an elapsed-time axis."]
        // Both caveats are properties of how `DistanceSplitCalculator` measures, and both
        // change how a split should be read. Unstated, the first invites Claude to line
        // the splits up against the run's duration and the second to call a pause a fade.
        lines.append("Timed between GPS fixes, so they exclude any lead-in before the first "
            + "fix and can total less than the duration above; a pause falls inside whichever "
            + "split straddles it and makes that one read slow.")
        if splits.contains(where: { !$0.isComplete }) {
            lines.append("The final entry covers less than a full \(Self.unitName). Its pace is "
                + "extrapolated from that short stretch and is not comparable with the others.")
        }
        lines.append(splits.map(Self.splitEntry).joined(separator: " · "))
        return lines
    }

    private static func splitEntry(_ split: DistanceSplit) -> String {
        // The same stopwatch formatter grade-adjusted pace uses. Two paces in one prompt
        // rounded two different ways would be MAX-045's drift, in prose.
        let paceText = FactSheetFormatting.pace(split.paceSeconds(per: WorkoutContext.paceBreakdownUnit))
        guard split.isComplete else {
            return "final \(FactSheetFormatting.distance(split.distanceMeters)) \(paceText)"
        }
        return "\(split.ordinal) \(paceText)"
    }

    /// The prose name of `WorkoutContext.paceBreakdownUnit`, spelled once. Not the
    /// athlete's display unit — see that constant for why the prompt is unit-fixed.
    private static var unitName: String {
        switch WorkoutContext.paceBreakdownUnit {
        case .kilometers: return "kilometre"
        case .miles: return "mile"
        }
    }

    // MARK: - The surrounding week (MAX-182, A29)

    /// Where this session sits in the athlete's week: the window, the arc week, the week's
    /// tallies, how many sessions it holds, and what the plan asked of each of its days.
    ///
    /// Ordered widest-first — the window, then the block, then the week's figures, then the
    /// asks — so that every number is already inside a stated span by the time it appears.
    /// §3.6(b)'s rule, applied to a span the athlete did not choose: they opened a
    /// conversation about one session, and the week is this app's answer to "which week is
    /// that", so the answer is stated rather than assumed.
    ///
    /// **Fixed size.** Every branch below emits a bounded number of lines, and none of them
    /// is a function of how much the athlete trained — see `WorkoutContext.SurroundingWeek`
    /// for why the audit made that a constraint rather than a preference.
    private static func surroundingWeekLines(_ week: WorkoutContext.SurroundingWeek) -> [String] {
        var lines: [String] = []

        lines.append("\(FactSheetFormatting.weekdayName(week.from.weekday)) \(week.from) through "
            + "\(FactSheetFormatting.weekdayName(week.through.weekday)) \(week.through) — the "
            + "Monday-first training week this session falls in, in the athlete's own time "
            + "zone. Every figure in this section is measured over exactly those seven days "
            + "and describes no other week.")
        lines.append(arcWeekLine(week))

        if week.reachesBeyondToday {
            // Without this, an ask with nothing recorded against it reads the same whether
            // the day has been and gone or has not arrived — and only one of those is a
            // session the athlete skipped. `TalliesCalculator` already withholds an
            // undecided day from both sides of the effective ratio (MAX-110); this is the
            // same fact said in words, for the plan asks below, which have no ratio to hide
            // it in.
            lines.append("This week is not over: today is \(week.today). A day after that has "
                + "not happened yet, so an ask with no workout recorded against it has not "
                + "been missed.")
        }

        lines.append(contentsOf: weekTallyLines(week))
        lines.append(contentsOf: weekPlanLines(week))
        return lines
    }

    /// Where the week sits in the plan's progression — the "does this fit the block" half of
    /// the question, in one line.
    ///
    /// Both absences are stated rather than dropped, and they are different facts: a week no
    /// plan governs has no arc week at all, and a week past the end of a finite arc has one
    /// with nothing prescribed for it — which `PlanCalendar` documents as an expected state
    /// meaning the plan wants a new version (D1), not as a defect.
    private static func arcWeekLine(_ week: WorkoutContext.SurroundingWeek) -> String {
        guard let plan = week.plan, let index = week.arcWeekIndex else {
            return "No plan version governs the end of this week, so it has no arc week and "
                + "the plan prescribes no long run for it."
        }
        guard let distanceMeters = week.arcWeekLongRunMeters else {
            return "Arc week \(index) under plan \(plan.version). The arc has no entry for that "
                + "week, so it prescribes no long-run distance."
        }
        return "Arc week \(index) under plan \(plan.version), long run prescribed: "
            + "\(FactSheetFormatting.distance(distanceMeters))."
    }

    /// The week's four figures, every one of them `TalliesCalculator`'s own (§3.6(a)).
    ///
    /// **Deliberately not `TrainingFactSheet`'s tally block, and not a shared function with
    /// it — yet.** The two print the same three figures through the same formatters, so they
    /// cannot disagree about a *number*; what differs is the prose, because a week has
    /// absences a frozen window does not (a week that is not over) and a frozen window has
    /// one this does not (a streak it actually bounds). MAX-192 is rewriting the roll-up's
    /// tally block to carry strain and load, and factoring the two into one renderer while
    /// that is in flight would be a merge conflict bought for nothing. **When MAX-192 lands,
    /// these two blocks should be reconciled into `FactSheetFormatting`** — that is a real
    /// follow-up, recorded here rather than left to be noticed.
    private static func weekTallyLines(_ week: WorkoutContext.SurroundingWeek) -> [String] {
        let tallies = week.tallies
        var lines: [String] = []

        // The unit is the *session*, unlike `workoutDays` below, and the two are worth
        // keeping apart: a Tuesday holding a run and a lift is one day and two sessions.
        lines.append("Workouts recorded in this week: \(week.sessionCount)")
        lines.append("Days with at least one workout: \(tallies.workoutDays)")

        let effective = tallies.effectiveDays
        if effective.rate == nil {
            // `EffectiveObligationTally` refuses to report 0 for an empty denominator, and
            // the prompt must not turn that refusal back into a zero: "nothing was eligible"
            // and "you failed every session" are opposite statements.
            lines.append("Effective sessions: nothing in this week was eligible — the plan "
                + "asked for rest, no plan governed these days, or their outcome is not yet "
                + "known.")
        } else {
            // The exact numerator/denominator shape `TrendTileData` puts on the tile, so a
            // figure quoted here and a figure read on the dashboard cannot differ in shape
            // or in rounding (§3.6(a) and (c)). "Sessions" and not "days" since MAX-134: the
            // denominator counts prescribed obligations, and a label reading "days" would
            // hand the model a number and mislabel its unit.
            lines.append("Effective sessions: \(effective.effectiveCount)/\(effective.eligibleCount)")
        }

        // MAX-160: a score labelled miscategorised (A21) is excluded from the average. Three
        // states, and the model must be told which one it is looking at rather than left to
        // guess from a bare number or a bare absence.
        let excludedCount = tallies.averageScoreExcludedMiscategorisedCount
        if let averageScore = tallies.averageScore {
            // Through the tile's own formatter — §3.6(c): where a figure appears in both a
            // tile and a fact sheet, the fact sheet renders it at the tile's precision.
            var line = "Average score this week: \(TrendTileData.formattedAverageScore(averageScore))"
            if let note = MiscategorisedScoreCopy.averageExclusionNote(excludedCount: excludedCount) {
                line += " (\(note))"
            }
            lines.append(line)
        } else if excludedCount > 0 {
            lines.append(MiscategorisedScoreCopy.onlyExcludedScoresAverageLine(excludedCount: excludedCount))
        } else {
            lines.append("Average score this week: nothing in this week has been scored yet, so "
                + "there is no average. That is an absence of verdicts, not a low one.")
        }

        if week.holdsNoOtherSession {
            // Stated in words rather than left to be inferred from a count of 1 (MAX-175),
            // and worded as a fact about the record: what this app holds for a week and what
            // the athlete did in it are different claims, and only the first is one it can
            // make.
            lines.append("No workout other than this one is recorded anywhere in this week.")
        }

        // The exclusions, stated in the prompt rather than only in this file's
        // documentation, because a model told to say when it cannot answer cannot do that
        // without knowing what it was not given (§3.5).
        lines.append("These are the week's totals only. This section carries no per-session "
            + "detail for any other workout in the week — not its distance, its duration, its "
            + "heart rate, its drift or its score — so a question about a particular other "
            + "session is best answered in that session's own conversation. Say so rather "
            + "than estimating, and do not infer one session's figures from these totals.")
        return lines
    }

    /// What the plan asked of each of the week's seven days.
    ///
    /// **Always seven lines, and never any health data** — the athlete's own configuration,
    /// which §3.3 item 1 distinguishes from a measurement of their body for exactly this
    /// reason. They are what the figures above are measured against: "should I back off
    /// Thursday" is a question about Thursday's ask, and the fact sheet around this block
    /// carries only the subject day's.
    private static func weekPlanLines(_ week: WorkoutContext.SurroundingWeek) -> [String] {
        // Seven repetitions of "no plan version governed this day" is the prompt spending
        // its budget on absences — `TrainingFactSheet` inverts the same rule for the same
        // reason. Said once, the day lines carry no plan clause at all and nothing is left
        // for a model to read into their shortness.
        guard !week.days.allSatisfy({ $0.planDay == nil }) else {
            return ["No plan version governed any day of this week, so the plan made no ask for "
                + "these days and there is nothing here for a session to have met or missed."]
        }

        var lines = ["What the plan asked of each day of this week, Monday first. A day names a "
            + "lift ask (tagged \"Lift:\") only when the plan prescribes one — a day with no "
            + "lift clause prescribes no lifting that day. These are the asks, not a record "
            + "of what happened on them."]
        for day in week.days {
            var fields = ["\(FactSheetFormatting.weekdayName(day.date.weekday)) \(day.date)"]
            guard let planDay = day.planDay else {
                // A single day the plan does not reach, inside a week it otherwise does — a
                // session in the week a plan first took effect. Stated, because the
                // alternative is a line indistinguishable from a day the plan rested.
                fields.append("no plan version governed this day")
                lines.append(fields.joined(separator: " · "))
                continue
            }
            fields.append(FactSheetFormatting.scheduledSession(planDay.scheduledSession))
            if !planDay.liftSession.isRest {
                fields.append("Lift: \(FactSheetFormatting.liftPrescription(planDay.liftSession))")
            }
            lines.append(fields.joined(separator: " · "))
        }
        return lines
    }

    // MARK: - Formatting
    //
    // `bpm`, `distance`, `duration`, `pace`, `percent`, `signedPercent` and `number` moved
    // to `FactSheetFormatting` (MAX-094) so that a second renderer — MAX-095's roll-up
    // over many sessions — cannot format the same measurement a different way. MAX-095
    // then moved `weekdayName` and the scheduled-session formatter for the same reason,
    // the moment the roll-up gained a second caller for each: every line it prints names
    // a weekday and a prescription. MAX-181 moved `liftPrescription` the same way, the
    // moment the roll-up's plan block grew a second, lift-carrying caller for it too.
    //
    // What stays here is `energy`, the one formatter with exactly one caller — the
    // roll-up carries no active-energy figure — because moving a formatter nothing else
    // needs to agree with buys no shared guarantee. It still routes its numeric part
    // through `FactSheetFormatting.number` and inherits the locale-pinned-to-nil
    // discipline rather than repeating it; see that type's doc comment for why the pin
    // matters.

    private static func energy(_ kilocalories: Double?) -> String {
        guard let kilocalories else { return "not recorded" }
        return "\(FactSheetFormatting.number(kilocalories)) kcal"
    }
}
