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
    ///
    /// ## The lift bands, and the shadow they close (MAX-132, A20, A21)
    ///
    /// §10.3 is a running rubric; it says nothing about a lift because nothing in the
    /// PRD does. `LIFTING-SPEC.md` §3.5 is what supplies the ask here: adherence bands
    /// (`lift.completed`, `lift.short`, `lift.happened`) for the `.lift` scheduled kind,
    /// none of them naming a load or a volume, because no such number exists in the
    /// record (A20). See the bands themselves for why each carries
    /// `.actualDiscipline(oneOf: [.lift])`.
    ///
    /// The same ticket adds that condition, in its `.run` form, to `easy.wellOverCap`
    /// below — the fix for the defect A21 records: a lift on an easy-run day cleared
    /// the band's only condition (average heart rate over cap + 8, which any lift does
    /// as a matter of course) and was permanently scored 20–45 as a failed easy run.
    ///
    /// **This seed change cannot reach a stored plan, and does not try to.** D1 makes
    /// the plan versioned data: every plan already saved keeps the bands it was saved
    /// with, seed included, and this file only ever supplies the *first* version an
    /// athlete's plan starts from. So the lifts already scored 20–45 or 40–69 by the
    /// unfixed bands stay scored that way (D8) — that is §11.4's escalation, tracked as
    /// MAX-143 and explicitly not this ticket's to resolve.
    ///
    /// **Nothing routed a workout to these bands at the time this was written.**
    /// `RubricEvaluator` still read `planDay.scheduledSession` — the **run** slot — for
    /// every workout, regardless of the workout's own discipline; matching a workout to
    /// the ask of its own discipline was MAX-133, landed afterward. So a lift stayed
    /// unscored under MAX-111's ingestion gate until MAX-133 landed, exactly as before
    /// this change. That was expected, not a bug in this ticket.
    ///
    /// ## `rest.ranAnyway`, and the shadow one band down (MAX-146)
    ///
    /// MAX-133's per-discipline routing closed `easy.wellOverCap` from the other side —
    /// a lift is now shown only the day's *lift* ask — and in doing so exposed the next
    /// one down. `PlanDay.scheduledSession(for:)` answers `.rest` for a discipline the
    /// day prescribes nothing for, which is the plan's own honest answer, not a gap. But
    /// no plan on disk, and no seeded weekday (`weeklySessions()` above), prescribes a
    /// lift, so a real lift resolves to `.rest` as a matter of course — and used to land
    /// on `rest.ranAnyway`, which carried no condition at all and read **"Ran on a
    /// scheduled rest day"** for a session that was not a run. Same shape of shadow as
    /// A21: a band whose only reach is the *scheduled* side, unconditional, matching any
    /// discipline that got routed to it.
    ///
    /// `.actualDiscipline(oneOf: [.run])` is the fix, for the same reason it was the fix
    /// for `easy.wellOverCap`: the band already meant "ran on a day that asked for
    /// rest", the condition is what makes that its actual meaning instead of an
    /// accident of unconditional placement. The alternative — a new band naming the
    /// lift-on-an-unprescribed-day case — was considered and rejected: it would need its
    /// own score range, and choosing one is a product opinion about how much an
    /// unscheduled lift should count for, which is not this ticket's to make. What this
    /// band's own condition change leaves behind for a lift is `fallback.recorded`, the
    /// seed's last row (see its own note below) — unconditional, honest
    /// ("Recorded, but the plan has no specific rule for this session"), and already the
    /// seed's designed answer for exactly this shape of gap, not a `noBandMatched`
    /// refusal. See `LiftRubricVocabularyTests` for the pinned regression and the
    /// fixture proving the fallback lands.
    ///
    /// **This seed change cannot reach a stored plan, and does not try to,** for the
    /// identical D1 reason the paragraph above states: it is the first version a plan
    /// starts from, never a rewrite of one already saved. Lifts already recorded with
    /// `rest.ranAnyway`'s rationale — which, per MAX-111's gate, is none yet, since a
    /// lift is not scored at all until that gate opens — stay however they were scored
    /// (D8). What to do about any that exist is MAX-143's, not this ticket's.
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
            // MAX-132 / A21: this band used to carry only the metric condition below,
            // which is a statement about heart rate and nothing about what was actually
            // done. A lift's average heart rate clears an easy-run cap + 8 as a matter
            // of course, so a lift scheduled on an easy-run day matched this band and
            // was permanently recorded as "Well above the easy cap for the whole run" —
            // the defect §11.4 escalates. `.actualDiscipline(oneOf: [.run])` closes it:
            // the band now says what it always meant to say, "an easy run whose heart
            // rate ran hot", rather than "anything with a hot heart rate". Nothing else
            // about the band changes — same identifier, same range, same rationale — so
            // a `Score` this band already produced for an actual easy run is unaffected
            // (see `LiftRubricVocabularyTests` for the pinned regression).
            try RubricBand(
                identifier: "easy.wellOverCap",
                appliesTo: [.easy],
                conditions: [
                    .actualDiscipline(oneOf: [.run]),
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
            // A20/MAX-131: a lift is judged on adherence — did the prescribed session
            // happen, on the day, for roughly the prescribed length — never on load or
            // volume, because HealthKit records neither. Three bands cover the three
            // shapes that ask can take, in the same "specific case, then a coarser
            // fallback" order the `long`/`hard` bands above already use.
            //
            // **Every one of these three carries `.actualDiscipline(oneOf: [.lift])`,
            // not only the one that needs it to resolve a metric.** `appliesTo: [.lift]`
            // filters by what the day *scheduled*, not by what the athlete actually did
            // — precisely the gap that let `easy.wellOverCap` match a lift above. A
            // scheduled lift day where the athlete did something else entirely (went
            // for a run instead) must not let that run's duration satisfy a lift band
            // just because it happened to be long enough; without this guard it could.
            // Omitting it here would plant the exact defect this ticket exists to fix,
            // one band down.
            //
            // The fraction is 0.7, not the run bands' 0.8 — a lift's clock more often
            // runs from the first warm-up set to racking the last plate, which pads the
            // prescribed length in a way a run's distance does not, so a slightly looser
            // floor is the honest match rather than reusing a number chosen for a
            // different measurement. Held loosely, like every number in this file.
            try RubricBand(
                identifier: "lift.completed",
                appliesTo: [.lift],
                conditions: [
                    .actualDiscipline(oneOf: [.lift]),
                    .metric(
                        metric: .durationSeconds,
                        comparison: .greaterThanOrEqual,
                        reference: .scheduledDuration(fraction: 0.7)
                    ),
                ],
                scoreRange: ScoreRange(lowest: 75, highest: 100),
                rationale: "Completed the prescribed lift."
            ),
            try RubricBand(
                identifier: "lift.short",
                appliesTo: [.lift],
                conditions: [
                    .actualDiscipline(oneOf: [.lift]),
                    .metric(
                        metric: .durationSeconds,
                        comparison: .lessThan,
                        reference: .scheduledDuration(fraction: 0.7)
                    ),
                ],
                scoreRange: ScoreRange(lowest: 40, highest: 74),
                rationale: "Cut the lift short of the prescribed length."
            ),
            // The day's lift ask can prescribe no duration at all (`ScheduledSession
            // .durationSeconds` is optional on a lift by design — "lift on Tuesday,
            // length unstated" is a real, distinct statement, not a gap). Both bands
            // above need `.scheduledDuration` to resolve, and it cannot when the ask
            // states no duration, so both silently fail to match rather than firing on
            // a comparison against nothing. This is the fallback that keeps such a day
            // scoreable — the same role `hard.completed` plays for a hard day prescribed
            // by structure ("6 × 800m") rather than by distance.
            try RubricBand(
                identifier: "lift.happened",
                appliesTo: [.lift],
                conditions: [.actualDiscipline(oneOf: [.lift])],
                scoreRange: ScoreRange(lowest: 70, highest: 95),
                rationale: "Lifted as scheduled; the plan named no target length."
            ),
            // MAX-146: this band used to carry no condition at all, so it matched any
            // discipline whose own slot resolved to `.rest` — which every unprescribed
            // lift does, since no seeded weekday and no plan on disk prescribes one. A
            // lift then landed here permanently, labelled "Ran on a scheduled rest day"
            // for a session that was not a run. `.actualDiscipline(oneOf: [.run])`
            // closes it the same way MAX-132 closed `easy.wellOverCap`: the band now
            // says what it always meant — a run on a day that asked for rest — and an
            // unprescribed lift falls through to `fallback.recorded` instead, which is
            // already the seed's honest answer for a session it has no specific rule
            // for. See the type note above for the full account and why a dedicated
            // lift band was considered and rejected.
            try RubricBand(
                identifier: "rest.ranAnyway",
                appliesTo: [.rest],
                conditions: [.actualDiscipline(oneOf: [.run])],
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
