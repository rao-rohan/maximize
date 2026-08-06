import Foundation

/// Presentation-ready summary tiles for a selected `TrendInterval` (FR-3.4).
///
/// ## Which figures, and why that depends on the span (MAX-083)
///
/// FR-3.4 names four figures — mileage against the plan's arc, effective sessions,
/// current streak, average score — and they are the right four for a week. Two of them
/// stop carrying their meaning as the span grows, so the tile set is a function of
/// `TrendIntervalKind.trendTileSet`:
///
/// | | week | month | year |
/// |---|---|---|---|
/// | distance | actual / arc target | actual / arc target | total, no target |
/// | effective sessions | `4/5` | `18/22` | `68%`, denominator in the caption |
/// | days trained | — | `18` | `212` |
/// | streak | ✓ | ✓ | ✓ |
/// | avg score | ✓ | ✓ | ✓ |
///
/// `TrendTileSet`'s own documentation carries the argument for each change; the short
/// version is that a year's arc "target" is a sum over ~52 different weekly asks that the
/// plan probably did not govern for all of, and that a year's effective-session count is
/// a ratio you want as a rate.
///
/// ## MAX-140 — the effective tile's caption now says what it counts
///
/// **Since MAX-134 (A19/LIFTING-SPEC §6.2), `Tallies.effectiveDays` is an
/// `EffectiveObligationTally`: its denominator is prescribed *sessions*, not calendar
/// days.** A Tuesday asking for a run and a lift is two chances, not one, so a week with
/// three lift sessions reads `6/8` where it used to read `4/5` for the same training. The
/// number was already right — MAX-134 proved every single-discipline history keeps its
/// old value byte-for-byte — but the caption still said "effective days" over a figure
/// that no longer counted days. That was a lie on screen, and fixing it is this ticket's
/// first job: the caption now reads "effective sessions" (weekly/monthly) and "effective,
/// of N eligible sessions" (annual), which is also the exact word LIFTING-SPEC §6.2 uses
/// when it names this as the cost of the decision. Nothing else about the tile changed —
/// same value, same position, same nil rule.
///
/// ## What this reads versus what it computes
///
/// Four of the five figures are **read, not recomputed**: `effectiveDays`, `workoutDays`,
/// `streak` and `averageScore` come straight off a `Tallies` MAX-017 already computed
/// (D2) — this type never re-derives a streak, a workout-day count or an effective-session
/// count itself, for the same reason `SummaryTileData` never re-derives a metric
/// `DerivedMetrics` already stored. Changing the *presentation* of a tally with the span
/// (a count at a week, a rate at a year) is a formatting decision over one stored figure,
/// not a second measurement of it.
///
/// The distance figure is different: it is not one of MAX-017's five rollups, so it is
/// computed here from records nothing else already assembles together — the plan's
/// per-day distance ask (`PlanCalendar.planDays(from:through:)`, D1: never a hardcoded
/// target) and the workouts actually recorded in the interval. Both are read from stored
/// records, the same rule `Tallies` itself follows.
///
/// ## Absent is not zero (rule 3), at every span
///
/// - `mileage` is nil when no plan governs *any* day in the interval — "no arc to
///   measure against" is a different fact from "the arc asked for 0 km" — and nil at a
///   year, where the comparison is withheld deliberately rather than for want of data.
/// - `totalDistance` is nil when the interval contains no workouts at all. A year with no
///   runs in it has no distance to report; printing "0.00 km" would state a measurement
///   nobody took. It is *not* nil merely because the runs recorded no distance — a year
///   of treadmill runs with no distance recorded genuinely totals zero.
/// - `effectiveDays` is nil exactly when `EffectiveObligationTally.rate` is nil — nothing in
///   the interval was eligible to be effective at (see that type's own documentation).
/// - `workoutDays` carries **no denominator**, at either span that shows it. "18 / 31"
///   invites reading the month as 42% consistent, but the honest denominator is the days
///   the athlete was training at all, and nothing stored knows that: a year the app was
///   installed in October is not a year with nine bad months. The eligible-*session*
///   denominator that *is* measured stays where it belongs, on `effectiveDays`.
/// - `streak` is never nil. Zero is a real, measured streak — the day after a miss —
///   and omitting the tile would hide exactly the number a streak screen exists to show.
/// - `averageScore` is nil when `Tallies.averageScore` is nil — nothing in the interval
///   has been scored yet, an honest "no data" rather than a fabricated zero.
public struct TrendTileData: Hashable, Sendable {
    /// Reusing `SummaryTileData.Tile` rather than a near-identical duplicate: both
    /// screens want the same bare value/caption shape, and `SummaryTilesView` (MAX-045)
    /// already knows how to render one, so this type and that view can share a renderer
    /// without a second tile shape needing to exist.
    public typealias Tile = SummaryTileData.Tile

    /// Which set of figures this was built for.
    public let tileSet: TrendTileSet

    /// Actual distance covered vs. the plan's arc target for the interval, as
    /// `"<actual> / <target>"` in the athlete's chosen `DistanceUnit` (MAX-047). Nil at
    /// `.annual`, and nil at the other spans when no plan governs any day in the
    /// interval — see the type's own documentation for why neither is a zero.
    public let mileage: Tile?

    /// Total distance covered in the interval, with no target beside it. Present only at
    /// `.annual`, where the arc comparison is dropped. Nil when the interval holds no
    /// workouts.
    public let totalDistance: Tile?

    /// `Tallies.effectiveDays`. At `.weekly`/`.monthly`, `"<effective>/<eligible>"` — the
    /// numerator/denominator pair `EffectiveObligationTally` itself prefers over a bare
    /// percentage. At `.annual`, the rate, with the denominator moved into the caption so
    /// it is still on screen. Nil when nothing was eligible.
    ///
    /// **Captioned "effective sessions", not "effective days" (MAX-140).** Since MAX-134,
    /// `EffectiveObligationTally`'s denominator counts prescribed obligations — a day
    /// asking for a run and a lift is two — so a caption still reading "days" would state
    /// a unit the number no longer uses. See this type's own top-level documentation.
    public let effectiveDays: Tile?

    /// `Tallies.workoutDays` — distinct days with at least one recorded workout, scored
    /// or not. Present at `.monthly` and `.annual` only, and deliberately without a
    /// denominator.
    ///
    /// **Captioned "days trained", not "days run" (MAX-150).** The count includes a day
    /// whose only workout was a lift — `TalliesCalculator`'s own `workoutDays` counts
    /// "at least one recorded workout" with no discipline filter — so "days run" quietly
    /// became wrong the day a lift-only day could exist. Found in review as the same
    /// class of drift `RunsStripCopy`'s own MAX-150 note fixes.
    ///
    /// **MAX-140 checked this rather than re-fixing it.** MAX-150 had already landed the
    /// "days trained" caption before this ticket started — `testAMonthAddsDaysTrainedAnd...`
    /// below pins it — so this ticket's second listed job was already done; this doc
    /// comment and its test are the verification, not new work.
    public let workoutDays: Tile?

    /// `Tallies.currentStreak`. Always present — see the type's own documentation for
    /// why zero is a measurement here, not an absence. **Still correctly "day streak"**:
    /// unlike `effectiveDays`, the streak's own unit of account is genuinely the day —
    /// §6.3 rolls a day's obligations up with AND before the streak ever sees it, so what
    /// the streak walks is one entry per calendar day regardless of how many obligations
    /// that day carried. No MAX-140 change belongs here.
    public let streak: Tile

    /// `Tallies.averageScore`, to one decimal place. Nil when nothing has been scored.
    ///
    /// ## MAX-140 — per-workout, decided, and why (the ticket's real question)
    ///
    /// **This average is per scored *workout*, not per obligation or per day, and stays
    /// that way.** `TalliesCalculator.computeAverageScore` (unmoved by this ticket — it
    /// lives in MAX-134's files) sums `ScoreLedger.effectiveValue.points` over every
    /// scored workout in the interval and divides by that count. A day prescribing a run
    /// and a lift that are both scored contributes *two* terms, exactly as it would if a
    /// warm-up jog and the real run were both scored — because "how good was each thing I
    /// did" and "did I meet each thing the plan asked of me" are different questions.
    /// `effectiveDays` answers the second with best-of-per-obligation and AND-across-day
    /// rules (§5, §6.2, §6.3); this tile answers the first, and averaging every graded
    /// effort is the natural per-workout reading of "how am I scoring, generally." Per-
    /// obligation (one figure per day's best session, mirroring `effectiveDays`) was
    /// considered and rejected: it would silently discard a scored second session's own
    /// grade, which is data the athlete asked to see, for a distinction (best-of) that
    /// belongs to the *effective/ineffective* question, not the *how good* one.
    ///
    /// This is D2-compliant by construction: `TrendTileData` never recomputes the mean
    /// here, it formats what `Tallies` already carries (see this initializer's own doc).
    ///
    /// **Reported, not decided here: whether a `ScoreLedger` MAX-143 labelled
    /// miscategorised (a lift scored against the running rubric, A21) should be excluded
    /// from this mean.** `ScoreLedger.countsTowardScorerQuality` already excludes it from
    /// PRD §2's scorer-quality signal; MAX-134's own tracker note flags that whether it
    /// should *also* leave the athlete's average is a live, undecided question belonging
    /// to `Tallies`/`TalliesCalculator` — files this ticket's scope explicitly excludes
    /// (`PROJECT_TRACKER.md`'s MAX-140 row). Filing a second, competing average inside
    /// this display type instead would be exactly the D2 drift `WorkoutContextBuilder`'s
    /// own precedent warns against, so this ticket declines to widen scope and reports the
    /// question instead: today, a lift mis-scored against a running rubric still pulls
    /// this figure down, which A21 says is a verdict answering the wrong question.
    public let averageScore: Tile?

    /// - Parameters:
    ///   - kind: which span these tiles are for. The tile *set* follows from it via
    ///     `TrendIntervalKind.trendTileSet` — the single table in
    ///     `DashboardSpanPresentation.swift` — rather than being chosen at the call site,
    ///     so the dashboard cannot show one span's calendar beside another span's tiles.
    ///   - tallies: MAX-017's rollup for this exact interval (`tallies.from`...
    ///     `tallies.through` is treated as the interval's own bounds — the caller is
    ///     expected to have built it from the same `TrendInterval` this displays).
    ///   - workouts: every workout available to the caller for the interval. This may
    ///     be wider than `tallies.from...tallies.through` — `TalliesInput` requires the
    ///     whole Monday-first weeks touching the interval (C1) — so this initializer
    ///     filters to `tallies.from...tallies.through` itself rather than trusting the
    ///     caller to have narrowed it, the same defensive filtering `TalliesCalculator`
    ///     does internally against its own wider input.
    ///   - timeZone: the athlete's zone, not the device's — matches `Workout.calendarDay(in:)`,
    ///     `TalliesInput` and `TrendInterval.dateInterval(in:)`'s own requirement.
    ///   - planCalendar: nil before the first plan version is authored — a real state,
    ///     not "no data" (see `mileage`'s documentation).
    ///   - distanceUnit: MAX-047 — a display decision only. `Workout.distanceMeters` and
    ///     `ScheduledSession.distanceMeters` stay in metres regardless; this initializer
    ///     is the one place that converts for the tile. No default, matching
    ///     `SummaryTileData`'s initializer: every call site must say explicitly which
    ///     unit it means.
    public init(
        kind: TrendIntervalKind,
        tallies: Tallies,
        workouts: [Workout],
        timeZone: TimeZone,
        planCalendar: PlanCalendar?,
        distanceUnit: DistanceUnit
    ) throws {
        let tileSet = kind.trendTileSet
        self.tileSet = tileSet

        // One pass over the widened input, narrowed to the interval's own days.
        var actualMeters = 0.0
        var workoutsInInterval = 0
        for workout in workouts {
            let day = try workout.calendarDay(in: timeZone)
            guard day >= tallies.from, day <= tallies.through else { continue }
            workoutsInInterval += 1
            actualMeters += workout.distanceMeters ?? 0
        }

        switch tileSet {
        case .weekly, .monthly:
            var planDays: [PlanDay] = []
            if let planCalendar {
                planDays = try planCalendar.planDays(from: tallies.from, through: tallies.through)
            }
            if planDays.isEmpty {
                mileage = nil
            } else {
                let targetMeters = planDays.reduce(into: 0.0) { total, planDay in
                    total += planDay.scheduledSession.distanceMeters ?? 0
                }
                mileage = Tile(
                    value: "\(Self.formattedDistance(actualMeters, unit: distanceUnit)) / "
                        + "\(Self.formattedDistance(targetMeters, unit: distanceUnit))",
                    caption: "\(distanceUnit.abbreviation) vs. arc"
                )
            }
            totalDistance = nil

        case .annual:
            // The plan is deliberately not read at this span: there is no arc comparison
            // to make, so there is no reason to resolve 365 plan days to build a tile
            // that would not be shown.
            mileage = nil
            totalDistance = workoutsInInterval == 0
                ? nil
                : Tile(
                    value: Self.formattedDistance(actualMeters, unit: distanceUnit),
                    caption: "\(distanceUnit.abbreviation) total"
                )
        }

        let tally = tallies.effectiveDays
        if let rate = tally.rate {
            switch tileSet {
            case .weekly, .monthly:
                effectiveDays = Tile(
                    value: "\(tally.effectiveCount)/\(tally.eligibleCount)",
                    caption: "effective sessions"
                )
            case .annual:
                effectiveDays = Tile(
                    value: Self.formattedRate(rate),
                    caption: "effective, of \(tally.eligibleCount) eligible sessions"
                )
            }
        } else {
            effectiveDays = nil
        }

        switch tileSet {
        case .weekly:
            workoutDays = nil
        case .monthly, .annual:
            workoutDays = Tile(value: "\(tallies.workoutDays)", caption: "days trained")
        }

        streak = Tile(value: "\(tallies.currentStreak)", caption: "day streak")

        averageScore = tallies.averageScore.map {
            Tile(value: Self.formattedAverageScore($0), caption: "avg score")
        }
    }

    /// Every present tile, in FR-3.4's own order — the distance figure, then
    /// effectiveness, then consistency, then streak, then average score — with the tiles
    /// this span does not carry simply absent.
    public var tiles: [Tile] {
        [mileage, totalDistance, effectiveDays, workoutDays, streak, averageScore].compactMap { $0 }
    }

    // MARK: - Formatting
    //
    // Locale pinned to nil (POSIX), matching `SummaryTileData` — a comma-decimal
    // locale must not render a different number here than a point-decimal one.

    /// Two decimal places, matching `SummaryTileData.formattedDistance` — a distance
    /// printed here and one printed on the per-workout tiles must never round
    /// differently, and must convert to the same unit the same way. Delegated rather
    /// than duplicated (both live in `MaximizeCore`, so the internal helper is directly
    /// reachable). A year's total is a wide number in this format and stays in it
    /// anyway: one rounding rule for distance across the whole app is worth more than a
    /// shorter string on one tile.
    private static func formattedDistance(_ meters: Double, unit: DistanceUnit) -> String {
        SummaryTileData.formattedDistance(meters, unit: unit)
    }

    /// A whole-percent rate. No decimal: at a year the denominator is in the hundreds, so
    /// a tenth of a percent is a fraction of one day and reads as precision nobody
    /// measured.
    private static func formattedRate(_ rate: Double) -> String {
        "\(Int((rate * 100).rounded()))%"
    }

    /// One decimal place.
    ///
    /// Internal rather than private because `TrainingFactSheet` (MAX-095) calls it:
    /// CHAT-FIRST-SPEC.md §3.6(c) requires a figure that appears in both a tile and a
    /// fact sheet to render at the tile's precision or coarser, and the average score is
    /// the one figure that appears in both. Delegating is stronger than asserting the two
    /// agree — the same reasoning that has this type delegate to
    /// `SummaryTileData.formattedDistance` rather than repeat it — and it keeps the
    /// decision where the tile makes it.
    static func formattedAverageScore(_ score: Double) -> String {
        String(format: "%.1f", locale: nil, score)
    }
}
