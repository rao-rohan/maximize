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
        case .lift: return Self.liftPrescription(session)
        }
    }

    /// The lift slot's ask — "lift, 45m 0s, muscle groups: chest, shoulders".
    ///
    /// Not `FactSheetFormatting.scheduledSession(_:)`. That function renders a prescribed
    /// *distance*, which no lift carries, and is silent about the two fields a lift's ask
    /// is actually written in: `durationSeconds`, which MAX-131 added to `ScheduledSession`
    /// precisely so a lift could be prescribed in minutes, and `muscleGroups`.
    ///
    /// Here rather than in `FactSheetFormatting` for the reason `energy` is (see the
    /// formatting note at the foot of this file): a formatter with one caller buys no
    /// shared guarantee by moving. Its numeric part still routes through
    /// `FactSheetFormatting.duration`, so the one figure it shares with every other
    /// renderer is already spelled the one way. It moves the moment
    /// `TrainingFactSheet`'s plan block carries the lift slot and becomes its second
    /// caller.
    ///
    /// **Absences are omitted, not stated** — this renderer's rule inverted again, and
    /// §10.1's instruction. "Lift on Tuesday, length unstated" and "lift on Tuesday,
    /// groups unstated" are ordinary asks a plan really makes (`ScheduledSession`
    /// documents both as distinct from rest), not gaps in a record, so there is nothing
    /// for a disclaimer to tell Claude that the short line does not.
    private static func liftPrescription(_ session: ScheduledSession) -> String {
        var parts = [session.kind.rawValue]
        if let durationSeconds = session.durationSeconds {
            parts.append(FactSheetFormatting.duration(durationSeconds))
        }
        if !session.muscleGroups.isEmpty {
            // `ordered`, never the set's own iteration order: a prompt that shuffled its
            // muscle groups between two builds of the same context would be D3's
            // determinism failing on a word rather than on a number.
            parts.append("muscle groups: "
                + session.muscleGroups.ordered.map(\.rawValue).joined(separator: ", "))
        }
        if let note = session.note, !note.isEmpty {
            parts.append("(\(note))")
        }
        return parts.joined(separator: ", ")
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

    // MARK: - Formatting
    //
    // `bpm`, `distance`, `duration`, `pace`, `percent`, `signedPercent` and `number` moved
    // to `FactSheetFormatting` (MAX-094) so that a second renderer — MAX-095's roll-up
    // over many sessions — cannot format the same measurement a different way. MAX-095
    // then moved `weekdayName` and the scheduled-session formatter for the same reason,
    // the moment the roll-up gained a second caller for each: every line it prints names
    // a weekday and a prescription.
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
