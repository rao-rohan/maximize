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
    /// ## Deterministic by construction
    ///
    /// Fixed field order, fixed precision, no locale. The same context must render
    /// byte-identically every time or D2's "one set of stored numbers" quietly stops
    /// being true at the prompt boundary.
    public func factSheet() -> String {
        var lines: [String] = []

        lines.append("## Workout")
        lines.append("Date: \(day) (\(weekdayName))")
        lines.append("Type: \(workout.activityType)")
        lines.append("Setting: \(workout.hasRoute ? "outdoor (GPS route recorded)" : "indoor (no route)")")
        lines.append("Duration: \(Self.duration(workout.durationSeconds))")
        lines.append("Distance: \(Self.distance(workout.distanceMeters))")
        lines.append("Active energy: \(Self.energy(workout.activeEnergyKilocalories))")
        lines.append("Classified as: \(classification.rawValue)")

        lines.append("")
        lines.append("## The plan")
        if let plan {
            lines.append("Plan version: \(plan.version)")
            lines.append("Heart-rate cap: \(Self.bpm(plan.heartRateCapBPM))")
            lines.append("Cadence target: \(Self.number(plan.cadenceTarget.lowStepsPerMinute))–"
                + "\(Self.number(plan.cadenceTarget.highStepsPerMinute)) spm")
            if let planDay {
                lines.append("Scheduled for this day: \(Self.session(planDay.scheduledSession))")
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
        lines.append("Average heart rate: \(Self.bpm(metrics.averageHeartRateBPM))")
        lines.append("Maximum heart rate: \(Self.bpm(metrics.maximumHeartRateBPM))")
        lines.append("Time above cap: \(timeAboveCapLine)")
        lines.append("Heart-rate drift: \(driftLine)")
        lines.append("Average cadence: \(cadenceLine)")
        lines.append("Grade-adjusted pace: \(gradeAdjustedPaceLine)")
        lines.append("Time in zones: \(zoneLine)")

        if let heartRateShape {
            lines.append("")
            lines.append("## Heart-rate shape")
            lines.append("Average bpm per tenth of elapsed time, so the curve can be read "
                + "without the underlying samples:")
            lines.append(heartRateShape.buckets
                .map { "\(Self.percent($0.startFraction)) \(Self.number($0.averageBeatsPerMinute))" }
                .joined(separator: " · "))
        }

        // Chat only (MAX-068). The section is absent from a scoring prompt entirely —
        // not stated-as-absent — because for the scorer this is not a metric that
        // happens to be missing, it is a part of the record the scorer is never shown,
        // like the route coordinates. Within a chat prompt the usual rule applies and
        // the section always appears, saying why it is empty when it is.
        if audience == .chat {
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
        switch day.weekday {
        case .monday: return "Monday"
        case .tuesday: return "Tuesday"
        case .wednesday: return "Wednesday"
        case .thursday: return "Thursday"
        case .friday: return "Friday"
        case .saturday: return "Saturday"
        case .sunday: return "Sunday"
        }
    }

    // MARK: - Lines that must explain their own absence

    private var timeAboveCapLine: String {
        guard let seconds = metrics.timeAboveCapSeconds else {
            return "not applicable — this workout has no heart-rate data"
        }
        return Self.duration(seconds)
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
        return Self.signedPercent(drift)
    }

    private var cadenceLine: String {
        guard let cadence = metrics.averageCadenceStepsPerMinute else {
            return "not recorded for this workout"
        }
        guard let plan else { return "\(Self.number(cadence)) spm" }
        let verdict = plan.cadenceTarget.contains(cadence) ? "within" : "outside"
        return "\(Self.number(cadence)) spm (\(verdict) the target band)"
    }

    private var gradeAdjustedPaceLine: String {
        guard let pace = metrics.gradeAdjustedPaceSecondsPerKilometer else {
            // The common case is a treadmill run, which FR-0.6 treats as first-class.
            return workout.hasRoute
                ? "not available for this workout"
                : "not applicable — indoor run, so there is no grade to correct for"
        }
        return "\(Self.pace(pace)) per km"
    }

    private var zoneLine: String {
        let present = HeartRateZone.allCases.compactMap { zone -> String? in
            let seconds = metrics.zoneSplits.seconds(in: zone)
            guard seconds > 0 else { return nil }
            return "zone \(zone.rawValue) \(Self.duration(seconds))"
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
        let paceText = Self.pace(split.paceSeconds(per: WorkoutContext.paceBreakdownUnit))
        guard split.isComplete else {
            return "final \(Self.distance(split.distanceMeters)) \(paceText)"
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
    // Locale is pinned to nil (POSIX) everywhere. A device set to a comma-decimal locale
    // must not send Claude a different fact sheet than one set to a point-decimal locale;
    // that would be D3's divergence arriving through `String(format:)`.

    private static func number(_ value: Double) -> String {
        String(format: "%.0f", locale: nil, value)
    }

    private static func bpm(_ value: Double?) -> String {
        guard let value else { return "not applicable — this workout has no heart-rate data" }
        return "\(number(value)) bpm"
    }

    private static func distance(_ meters: Double?) -> String {
        guard let meters else { return "not recorded (indoor runs may report none)" }
        return "\(String(format: "%.2f", locale: nil, meters / 1000)) km"
    }

    private static func energy(_ kilocalories: Double?) -> String {
        guard let kilocalories else { return "not recorded" }
        return "\(number(kilocalories)) kcal"
    }

    private static func duration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let remainder = total % 60
        if hours > 0 { return "\(hours)h \(minutes)m \(remainder)s" }
        if minutes > 0 { return "\(minutes)m \(remainder)s" }
        return "\(remainder)s"
    }

    private static func pace(_ secondsPerKilometer: Double) -> String {
        let total = Int(secondsPerKilometer.rounded())
        return "\(total / 60):\(String(format: "%02d", locale: nil, total % 60))"
    }

    private static func percent(_ fraction: Double) -> String {
        "\(String(format: "%.0f", locale: nil, fraction * 100))%"
    }

    private static func signedPercent(_ fraction: Double) -> String {
        let sign = fraction >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.1f", locale: nil, fraction * 100))%"
    }

    private static func session(_ session: ScheduledSession) -> String {
        var parts = [session.kind.rawValue]
        if let distanceMeters = session.distanceMeters {
            parts.append("\(String(format: "%.1f", locale: nil, distanceMeters / 1000)) km")
        }
        if let note = session.note, !note.isEmpty {
            parts.append("(\(note))")
        }
        return parts.joined(separator: ", ")
    }
}
