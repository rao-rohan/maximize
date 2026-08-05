import Foundation

/// The starting content of a first plan (MAX-080).
///
/// ## This is authoring input, not a threshold the scorer reads
///
/// D1 forbids thresholds living in code, and there are numbers below. The distinction
/// that keeps them legal is *who reads them*:
///
/// - **Nothing on the scoring path consults this file.** `WorkoutScorer` reads the
///   rubric off the `Plan` record `PlanCalendar` resolved for the workout's date, and
///   that record was written to disk when the athlete saved a version. The seed's job
///   ends the moment the first version is stored.
/// - **Editing this file cannot change a stored plan.** Version 1 is a row in the
///   store; changing a constant here does not touch it, and cannot make a historical
///   score irreproducible. That is the property D1 actually protects.
/// - **Revisions do not re-read it.** `PlanAuthoringSession` prefills a revision from
///   the version being superseded, and carries that version's rubric bands forward
///   verbatim. So an athlete who tuned their plan never has this file's opinions
///   reintroduced behind their back.
///
/// The alternative — shipping no seed and asking the athlete to hand-assemble an
/// ordered list of rubric bands before the app can score anything — is not a defence of
/// D1, it is a product that does not start. The PRD hands us the values (FR-1.2's
/// 150 bpm cap, FR-1.3's 165–170 cadence band, §10.3's rubric, §10.4's effective
/// threshold of 70), so the seed writes down what the spec already says and then gets
/// out of the way.
///
/// ## What the PRD does not give us
///
/// The weekly template and the long-run arc. D1 names both ("weekly template, 16-week
/// arc") without ever saying what they contain, and no other section fills the gap. The
/// shapes below are therefore a *starting point chosen to be obviously editable*, not a
/// claim about the athlete's training: a five-run week with two rest days, and a
/// straight 16-week ramp. Both are the first things the authoring screen shows, and
/// both are fully editable there before the first save.
public enum StandardPlanSeed {

    /// FR-1.2: "the HR cap (currently 150 bpm)".
    public static let heartRateCapBPM: Double = 150

    /// FR-1.3: "cadence … against the target band (currently 165–170)".
    public static let cadenceLowStepsPerMinute: Double = 165
    public static let cadenceHighStepsPerMinute: Double = 170

    /// §10.4 / D4: "mark effective if score ≥ 70".
    public static let effectiveThresholdPoints = 70

    /// The amber/red cut. The PRD does not name it directly; it falls out of §10.3's
    /// worst band being "20–45", so 45 is the top of the range the rubric reserves for
    /// a session that went wrong. Versioned like everything else, and editable on the
    /// authoring screen, precisely because it is an inference rather than a quotation.
    public static let marginalThresholdPoints = 45

    /// Weeks in the seeded long-run arc — D1's "16-week arc".
    public static let arcWeekCount = 16
    public static let arcFirstWeekDistanceMeters: Double = 14_000
    public static let arcPeakWeekDistanceMeters: Double = 32_000

    /// The draft an athlete lands on before they have authored anything.
    public static func draft() throws -> PlanDraft {
        try PlanDraft(
            heartRateCapBPM: heartRateCapBPM,
            cadenceLowStepsPerMinute: cadenceLowStepsPerMinute,
            cadenceHighStepsPerMinute: cadenceHighStepsPerMinute,
            effectiveThresholdPoints: effectiveThresholdPoints,
            marginalThresholdPoints: marginalThresholdPoints,
            weeklySessions: weeklySessions(),
            longRunArcWeeks: PlanDraft.rampedArc(
                firstWeekDistanceMeters: arcFirstWeekDistanceMeters,
                peakWeekDistanceMeters: arcPeakWeekDistanceMeters,
                weekCount: arcWeekCount
            )
        )
    }

    /// A five-run week: two easy midweek days, one hard session, a shorter easy day,
    /// the long run on Sunday, and two rest days. See the type's note — the PRD does
    /// not specify this, and it is meant to be edited.
    public static func weeklySessions() throws -> [Weekday: ScheduledSession] {
        [
            .monday: .rest,
            .tuesday: try ScheduledSession(kind: .easy, distanceMeters: 8_000),
            .wednesday: try ScheduledSession(kind: .hard, note: "Intervals"),
            .thursday: try ScheduledSession(kind: .easy, distanceMeters: 8_000),
            .friday: .rest,
            .saturday: try ScheduledSession(kind: .easy, distanceMeters: 6_000),
            // The distance here is a fallback: `PlanCalendar` substitutes the arc's
            // distance for the week the day falls in, and only falls back to this once
            // the arc has run out.
            .sunday: try ScheduledSession(kind: .long, distanceMeters: 18_000),
        ]
    }

    /// PRD §10.3's worked rubric, written out as plan data.
    ///
    /// Ordered, and the order is load-bearing — `ScoringRubric` evaluates bands in
    /// sequence and the first match wins. "Ran hard when easy was asked for" is first
    /// so a session is judged on what it was before it is judged on where its heart
    /// rate landed; §10.3 states that disjunction ("avg ≥ 159 **or** hard-instead")
    /// as one band, and `RubricCondition` expresses a disjunction as two bands sharing
    /// a score range.
    ///
    /// Every threshold that has a plan-relative anchor is written as one
    /// (`.heartRateCap(offsetBPM:)`, `.scheduledDistance(fraction:)`) rather than as a
    /// literal, so moving the HR cap in a later version moves the bands with it instead
    /// of stranding a rubric that still tests against 150.
    ///
    /// ## Where this goes beyond §10.3, and why
    ///
    /// §10.3's list is introduced with "e.g." and covers easy days plus the skipped
    /// case. A rubric containing only those rows leaves `RubricEvaluator` with nothing
    /// to match for a long day that fell short, a hard day prescribed by structure
    /// rather than distance, a run on a scheduled rest day, or an easy day the athlete
    /// walked — and `noBandMatched` is a thrown error, so each of those is a workout
    /// that ends up with **no score**, hence no calendar colour and no chat (MAX-051
    /// gates on `Score.actualClassification`). Since the seeded week has two rest days
    /// in it, that gap is not hypothetical.
    ///
    /// So the seed adds rows for those cases and ends with a catch-all that always
    /// matches. The catch-all's range sits below the effective threshold deliberately:
    /// a session the rubric has no opinion about has not demonstrated an effective day,
    /// and saying so quietly is better than either refusing to score it or crediting it.
    ///
    /// None of this is load-bearing for anyone who disagrees — it is the *starting*
    /// rubric, versioned like everything else.
    public static func rubricBands() throws -> [RubricBand] {
        [
            try RubricBand(
                identifier: "easy.ranHardInstead",
                appliesTo: [.easy],
                conditions: [.actualClassification(oneOf: [.hard])],
                scoreRange: ScoreRange(lowest: 20, highest: 45),
                rationale: "Ran hard on an easy day."
            ),
            try RubricBand(
                identifier: "easy.onCap.lowDrift",
                appliesTo: [.easy],
                conditions: [
                    .actualClassification(oneOf: [.easy]),
                    .metric(
                        metric: .averageHeartRateBPM,
                        comparison: .lessThanOrEqual,
                        reference: .heartRateCap(offsetBPM: 0)
                    ),
                    .metric(
                        metric: .heartRateDriftFraction,
                        comparison: .lessThan,
                        reference: .constant(0.05)
                    ),
                ],
                scoreRange: ScoreRange(lowest: 90, highest: 100),
                rationale: "Held the cap with minimal drift."
            ),
            try RubricBand(
                identifier: "easy.onCap.lateDrift",
                appliesTo: [.easy],
                conditions: [
                    .actualClassification(oneOf: [.easy]),
                    .metric(
                        metric: .averageHeartRateBPM,
                        comparison: .lessThanOrEqual,
                        reference: .heartRateCap(offsetBPM: 0)
                    ),
                ],
                scoreRange: ScoreRange(lowest: 75, highest: 89),
                rationale: "Under cap, but drifted late."
            ),
            try RubricBand(
                identifier: "easy.slightlyOverCap",
                appliesTo: [.easy],
                conditions: [
                    .actualClassification(oneOf: [.easy]),
                    .metric(
                        metric: .averageHeartRateBPM,
                        comparison: .lessThanOrEqual,
                        reference: .heartRateCap(offsetBPM: 8)
                    ),
                ],
                scoreRange: ScoreRange(lowest: 55, highest: 74),
                rationale: "Ran above the easy cap."
            ),
            try RubricBand(
                identifier: "easy.wellOverCap",
                appliesTo: [.easy],
                conditions: [
                    .metric(
                        metric: .averageHeartRateBPM,
                        comparison: .greaterThan,
                        reference: .heartRateCap(offsetBPM: 8)
                    ),
                ],
                scoreRange: ScoreRange(lowest: 20, highest: 45),
                rationale: "Well above the easy cap for the whole run."
            ),
            try RubricBand(
                identifier: "long.completedTheDistance",
                appliesTo: [.long],
                conditions: [
                    .metric(
                        metric: .distanceMeters,
                        comparison: .greaterThanOrEqual,
                        reference: .scheduledDistance(fraction: 0.8)
                    ),
                ],
                scoreRange: ScoreRange(lowest: 75, highest: 100),
                rationale: "Covered the prescribed long-run distance."
            ),
            try RubricBand(
                identifier: "long.fellShort",
                appliesTo: [.long],
                conditions: [
                    .metric(
                        metric: .distanceMeters,
                        comparison: .lessThan,
                        reference: .scheduledDistance(fraction: 0.8)
                    ),
                ],
                scoreRange: ScoreRange(lowest: 40, highest: 74),
                rationale: "Fell short of the prescribed long-run distance."
            ),
            try RubricBand(
                identifier: "hard.executed",
                appliesTo: [.hard],
                conditions: [
                    .metric(
                        metric: .distanceMeters,
                        comparison: .greaterThanOrEqual,
                        reference: .scheduledDistance(fraction: 0.8)
                    ),
                ],
                scoreRange: ScoreRange(lowest: 75, highest: 100),
                rationale: "Executed the prescribed session."
            ),
            // A hard day is often prescribed by structure rather than distance
            // ("6 × 800m"), in which case `.scheduledDistance` resolves to nil and the
            // band above cannot match. This one keeps such a day scoreable instead of
            // leaving the scorer with no band at all.
            try RubricBand(
                identifier: "hard.completed",
                appliesTo: [.hard],
                conditions: [.actualClassification(oneOf: [.hard, .long])],
                scoreRange: ScoreRange(lowest: 70, highest: 95),
                rationale: "Completed a hard session as scheduled."
            ),
            try RubricBand(
                identifier: "rest.ranAnyway",
                appliesTo: [.rest],
                scoreRange: ScoreRange(lowest: 50, highest: 75),
                rationale: "Ran on a scheduled rest day."
            ),
            try RubricBand(
                identifier: "other.completed",
                appliesTo: [.other],
                scoreRange: ScoreRange(lowest: 60, highest: 90),
                rationale: "Completed the scheduled session."
            ),
            // §10.3's "skipped → 0–15" row, kept for completeness. It is unreachable
            // through `RubricEvaluator`: a `WorkoutContext` exists because a workout was
            // recorded, so `.noWorkoutRecorded` is always false there, and a day with no
            // workout has no `Score` record to carry (scores are keyed by workout).
            // Missed days surface through the calendar (D9/MAX-016) instead. It is
            // written down anyway so a future missed-day scorer finds the plan already
            // says what a skipped day is worth, rather than inventing a number.
            try RubricBand(
                identifier: "skipped",
                conditions: [.noWorkoutRecorded],
                scoreRange: ScoreRange(lowest: 0, highest: 15),
                rationale: "No workout recorded for a scheduled session."
            ),
            // Last, and unconditional: no band above it may be moved below it without
            // being shadowed. See the note above on why an unmatched workout is worse
            // than an imprecisely-scored one.
            try RubricBand(
                identifier: "fallback.recorded",
                scoreRange: ScoreRange(lowest: 40, highest: 69),
                rationale: "Recorded, but the plan has no specific rule for this session."
            ),
        ]
    }
}
