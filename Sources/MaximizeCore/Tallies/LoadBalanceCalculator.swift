import Foundation

/// Everything `LoadBalanceCalculator.compute` needs, in the shape `TalliesInput`
/// already established (MAX-178, HELIX-COMPETITIVE-READ §9).
public struct LoadBalanceInput: Sendable {
    /// The day both windows end on, inclusive. **An input, never a clock read**
    /// (MAX-110) — the same discipline `TalliesInput.today` and `MuscleFatigueInput.now`
    /// are held to, and for the same reason: a calculator that called `Date()` would be
    /// untestable by construction, and could disagree with a figure drawn beside it on
    /// the same screen the moment the two read the clock at different instants.
    ///
    /// Unlike `TalliesInput.today`, `anchor` is not treated as "not yet decided" — see
    /// `LoadBalanceCalculator`'s own documentation for why a load sum and an obligation
    /// judgement read `today` differently on purpose.
    public let anchor: CalendarDay

    /// The zone `workouts` are bucketed into days with. Matches `Workout.calendarDay(in:)`
    /// and `TalliesInput.timeZone`'s own requirement — the athlete's zone, not the
    /// device's.
    public let timeZone: TimeZone

    /// The earliest day this input can vouch for: the day of the athlete's very first
    /// recorded workout, or `anchor` itself when nothing has ever been recorded.
    ///
    /// This is what tells "no training happened here" apart from "we have no idea what
    /// happened here" — the distinction the chronic window's absence state depends on.
    /// A day with no workout is a real, zero-cost rest day only if the app's records
    /// reach back far enough to have seen it; a day before `historyStart` was never
    /// observed at all, and a sum that quietly treated it as zero would understate a
    /// short-history athlete's chronic load in exactly the direction MAX-176 warns
    /// against. See `LoadBalanceCalculator`'s "Partial history" section for how this is
    /// used.
    public let historyStart: CalendarDay

    /// Workouts covering at least `historyStart...anchor` when history is short, or at
    /// minimum the chronic window (`anchor` back `LoadBalanceCalculator.chronicWindowDays
    /// - 1` days) once `historyStart` is old enough that the window is fully covered.
    /// Workouts outside the chronic window are ignored, so a wider fetch is harmless —
    /// only a narrower one silently undercounts, the same one-directional obligation
    /// `TalliesInput.workouts` places on its own caller.
    public let workouts: [Workout]

    /// Keyed by `Workout.id`. A workout with no entry here, or an entry whose `.strain`
    /// is nil, is read identically: **no strain figure for that session**, skipped from
    /// both sums rather than counted as zero (MAX-176). The two causes — genuinely no
    /// heart-rate curve, and metrics simply not computed yet for an older record — are
    /// not distinguished, because neither licenses treating the session as free.
    public let derivedMetricsByWorkoutID: [UUID: DerivedMetrics]

    public init(
        anchor: CalendarDay,
        timeZone: TimeZone,
        historyStart: CalendarDay,
        workouts: [Workout],
        derivedMetricsByWorkoutID: [UUID: DerivedMetrics]
    ) throws {
        guard historyStart <= anchor else {
            throw DomainError.inconsistent(
                reason: "LoadBalanceInput.historyStart (\(historyStart)) must not be after anchor (\(anchor))"
            )
        }
        self.anchor = anchor
        self.timeZone = timeZone
        self.historyStart = historyStart
        self.workouts = workouts
        self.derivedMetricsByWorkoutID = derivedMetricsByWorkoutID
    }
}

/// One day's worth of acute-versus-chronic training load, the moment `anchor` describes.
/// Present only inside `LoadBalanceReading.available` — see that type for the absence
/// state this is not shown alongside.
public struct LoadBalance: Hashable, Sendable {
    public let anchor: CalendarDay

    /// `Σ strain.points` over the 7 days ending `anchor`, inclusive. Zone-weighted
    /// minutes, the same unit `WorkoutStrain.points` stores — this is a sum of that
    /// figure, not a new one.
    public let acuteStrainPoints: Double

    /// `Σ strain.points` over the 28 days ending `anchor`, inclusive. The raw sum, kept
    /// alongside `chronicWeeklyAveragePoints` because "28 days of load" and "a typical
    /// week of it" are both real questions and only one of them is what the ratio uses.
    public let chronicStrainPoints: Double

    /// `chronicStrainPoints` scaled to the acute window's length —
    /// `chronicStrainPoints / (chronicWindowDays / acuteWindowDays)`, i.e. divided by 4
    /// under the calculator's current windows. This, not the raw 28-day sum, is `ratio`'s
    /// denominator; see `LoadBalanceCalculator`'s documentation for why.
    public let chronicWeeklyAveragePoints: Double

    /// `acuteStrainPoints / chronicWeeklyAveragePoints`. Nil when
    /// `chronicWeeklyAveragePoints` is zero — no chronic baseline was recorded at all
    /// (every workout in the chronic window lacked a strain figure, or none happened),
    /// so any acute number over it would be a division by zero dressed up as a ratio.
    /// `acuteStrainPoints` is still reported on its own in that case; only the ratio is
    /// withheld.
    public let ratio: Double?

    /// How many workouts within the 7-day acute window had no strain figure to
    /// contribute (MAX-176: "say in the caption how many sessions in the window carried
    /// no strain — a 7-day sum missing two strapless runs is not the same fact as a
    /// 7-day sum of everything that happened"). Carried as a count, not folded silently
    /// into the sum, so a caption can say it.
    public let acuteWorkoutsWithoutStrain: Int

    /// The same count, over the full 28-day chronic window.
    public let chronicWorkoutsWithoutStrain: Int

    public init(
        anchor: CalendarDay,
        acuteStrainPoints: Double,
        chronicStrainPoints: Double,
        chronicWeeklyAveragePoints: Double,
        ratio: Double?,
        acuteWorkoutsWithoutStrain: Int,
        chronicWorkoutsWithoutStrain: Int
    ) throws {
        try Validate.nonNegative(acuteStrainPoints, "LoadBalance.acuteStrainPoints")
        try Validate.nonNegative(chronicStrainPoints, "LoadBalance.chronicStrainPoints")
        try Validate.nonNegative(chronicWeeklyAveragePoints, "LoadBalance.chronicWeeklyAveragePoints")
        // `ratio` and `chronicWeeklyAveragePoints == 0` are the same fact stated twice —
        // see `ratio`'s own documentation for why a zero baseline withholds the ratio
        // rather than dividing by it. Enforced here so the two cannot be constructed out
        // of step with each other, the same way `DerivedMetrics` refuses a strain with
        // no heart-rate series to have come from.
        if let ratio {
            try Validate.nonNegative(ratio, "LoadBalance.ratio")
            guard chronicWeeklyAveragePoints > 0 else {
                throw DomainError.inconsistent(
                    reason: "LoadBalance.ratio is present but chronicWeeklyAveragePoints is 0"
                )
            }
        } else {
            guard chronicWeeklyAveragePoints == 0 else {
                throw DomainError.inconsistent(
                    reason: "LoadBalance.ratio is nil but chronicWeeklyAveragePoints "
                        + "(\(chronicWeeklyAveragePoints)) is nonzero"
                )
            }
        }
        guard acuteWorkoutsWithoutStrain >= 0 else {
            throw DomainError.outOfRange(
                field: "LoadBalance.acuteWorkoutsWithoutStrain",
                value: Double(acuteWorkoutsWithoutStrain), lowerBound: 0, upperBound: nil
            )
        }
        guard chronicWorkoutsWithoutStrain >= 0 else {
            throw DomainError.outOfRange(
                field: "LoadBalance.chronicWorkoutsWithoutStrain",
                value: Double(chronicWorkoutsWithoutStrain), lowerBound: 0, upperBound: nil
            )
        }
        self.anchor = anchor
        self.acuteStrainPoints = acuteStrainPoints
        self.chronicStrainPoints = chronicStrainPoints
        self.chronicWeeklyAveragePoints = chronicWeeklyAveragePoints
        self.ratio = ratio
        self.acuteWorkoutsWithoutStrain = acuteWorkoutsWithoutStrain
        self.chronicWorkoutsWithoutStrain = chronicWorkoutsWithoutStrain
    }
}

/// What `LoadBalanceCalculator.compute` returns: either a real reading, or the reason
/// there is not yet one to show.
///
/// **This is the type that makes the absence state impossible to skip.** A `Double?` on
/// `LoadBalance` itself would let a caller reach for `?? 0` or print "—" without ever
/// being told *why* there was nothing — exactly the shape MAX-175 keeps naming as the
/// trap. An enum with no bare-`nil` case forces every caller to handle
/// `.buildingHistory` on purpose, the same way `SplitsListData`'s three cases force a
/// view to handle "no route" and "no stored breakdown" as different, named states rather
/// than as one collapsed optional.
public enum LoadBalanceReading: Hashable, Sendable {
    /// Fewer than `LoadBalanceCalculator.chronicWindowDays` days lie between
    /// `LoadBalanceInput.historyStart` and `anchor`, inclusive — the chronic window is
    /// not yet fully inside the app's own horizon, so a ratio computed from it would be
    /// confident about days it never observed. **Not a blank and not a misleading ratio
    /// computed from four days of data** — the ticket's own words for why this case
    /// exists at all.
    ///
    /// - `daysRecorded`: how many days of that horizon exist today, capped at
    ///   `daysNeeded` (it never needs to say more than "enough").
    /// - `daysNeeded`: `LoadBalanceCalculator.chronicWindowDays`, restated here so a
    ///   caller never hardcodes the number the calculator already knows.
    case buildingHistory(daysRecorded: Int, daysNeeded: Int)

    case available(LoadBalance)
}

/// Rolling acute (7-day) and chronic (28-day) strain sums, and their ratio, over
/// `DerivedMetrics.strain` as `DerivedMetricsRecord` already stores it (MAX-176, MAX-178,
/// HELIX-COMPETITIVE-READ §9).
///
/// A pure function over stored records, in the shape `TalliesCalculator` already has —
/// no clock, no storage, no framework, every input explicit. `TalliesCalculator`'s own
/// documentation is worth reading first; this follows its calling convention
/// (`*Input` struct, `*Calculator` enum, one `compute` entry point) on purpose, so a
/// reader who already knows one knows the shape of the other.
///
/// ## What this reports, and what it deliberately does not
///
/// Everything else the app measures is a comparison against a prescription — did the
/// athlete execute the ask. This is not that, for the same reason `WorkoutStrain` is
/// not: it is a ratio of two measured sums, with no rubric band, no threshold and no
/// verdict attached to it anywhere in this file or in `TrendTileData`. **This app does
/// not tell an athlete they are overtrained on the strength of a heart-rate integral
/// with no sleep, HRV, or load data behind it** — it reports the figure and what it is;
/// the coaching interpretation belongs in chat, where a model can hedge and ask
/// questions this calculator cannot. Nothing here computes a "risk", colours a band, or
/// says "high"/"low" — that is a deliberate omission, not an oversight, and a future
/// change that adds one should not read this file as having left room for it.
///
/// ## Windows anchor to `anchor`, and only `anchor` (not `Date()`)
///
/// Both windows end at `LoadBalanceInput.anchor`, inclusive, and are exactly
/// `acuteWindowDays` / `chronicWindowDays` long: `anchor` back 6 days for the acute
/// window, `anchor` back 27 days for the chronic one. `anchor` is supplied, never read
/// from the clock, for the reason every calculator in this package gives: a `Date()`
/// call inside `MaximizeCore` is untestable by construction and can disagree with
/// whatever else on screen resolved "today" a heartbeat earlier or later.
///
/// **`anchor` itself is always included, unlike `TalliesInput.today`.** `TalliesCalculator`
/// excludes `today` from obligation counting because a miss cannot be judged before the
/// day ends — that is a rule about *grading an outcome*. This calculator does not grade
/// anything; it sums a cost that is already known the moment a workout's metrics are
/// computed, whether that happened at 6 a.m. or 11 p.m. Excluding `anchor` here would
/// silently drop a real morning run's strain from today's own acute figure until
/// midnight, which is the same "known but shown as absent" defect MAX-110 fixed for the
/// streak, arrived at by copying a rule built for a different question.
///
/// ## The ratio's denominator: a scaled weekly average, not the raw 28-day sum (the
/// decision this ticket owns)
///
/// `ratio` is `acuteStrainPoints / chronicWeeklyAveragePoints`, where
/// `chronicWeeklyAveragePoints` is the 28-day sum divided by 4 — **not**
/// `acuteStrainPoints / chronicStrainPoints` over the raw sums. The two are not
/// interchangeable, and only one produces a ratio whose scale means anything at a
/// glance:
///
/// - Dividing two raw sums of unequal-length windows makes steady, unchanging training
///   read as roughly **0.25** forever — 7 days of a total against 28 days of the same
///   total is always about a quarter, regardless of whether the athlete is undertrained,
///   overreaching, or holding perfectly steady. The number would carry no information
///   beyond "sums", and every reading would cluster at the same place.
/// - Scaling the chronic sum to the acute window's own length turns it into "a typical
///   week over the last month", so the ratio reads as **how this week compares to the
///   athlete's recent normal** — steady training sits near **1.0**, a lighter week reads
///   below it, a loaded one above. This is the standard acute:chronic workload ratio
///   construction from the sports-science literature this feature is modelled on
///   (Edwards' own weighting is already borrowed for the same reason: read the
///   convention rather than invent a new curve), and it is the reading that makes "1.08"
///   a sentence a person can act on without doing the division themselves.
///
/// ## Partial history is a designed state, not a truncated sum (the other decision this
/// ticket owns)
///
/// `LoadBalanceInput.historyStart` is what tells "the athlete rested all month" (a real
/// zero, correctly summed) apart from "the athlete has only used this app for six days"
/// (an incomplete window, where a low sum would be a lie about how loaded they normally
/// are). Whenever `historyStart` puts fewer than `chronicWindowDays` days on record —
/// inclusive of `anchor` — `compute` returns `.buildingHistory` instead of a
/// `LoadBalance`, however few or many workouts happened to fall in that short span. Nine
/// days of hard training on a six-day-old account is not "1.4 ratio, alarmingly high" —
/// it is "not enough history yet", stated once and left there, in the voice
/// `SplitsListData` and `MuscleFatigueCopy` already use for "recorded, and truthfully
/// containing nothing yet" rather than a fabricated confident number.
///
/// ## Nil strain is skipped, never zeroed, and the coverage gap is counted (MAX-176)
///
/// A workout with `derivedMetricsByWorkoutID[id]?.strain == nil` — no entry at all, or
/// an entry whose strain was never computed — contributes nothing to either sum, exactly
/// as `WorkoutStrain`'s own documentation requires: a zero would read as "this session
/// cost nothing," and would be summed into the rolling load as a real day of training
/// (A18, MAX-175's invariant, restated at this new seam). What it *does* do is increment
/// `acuteWorkoutsWithoutStrain` / `chronicWorkoutsWithoutStrain`, because a 7-day sum
/// silently missing two strapless runs is a different fact from a 7-day sum of
/// everything that happened, and only the count lets a caption say which one this is.
///
/// ## What is not `MaximizeCore`'s job here
///
/// Formatting the ratio, deciding what a tile's caption says, and rendering any of it is
/// `TrendTileData` and `TrendTilesView`'s territory (D2/D3: one place reads the stored
/// figure, everything downstream formats it). This type stops at the arithmetic.
public enum LoadBalanceCalculator {
    /// The acute window's length in days, `anchor` inclusive.
    public static let acuteWindowDays = 7

    /// The chronic window's length in days, `anchor` inclusive.
    public static let chronicWindowDays = 28

    public static func compute(_ input: LoadBalanceInput) throws -> LoadBalanceReading {
        let daysOfHistory = try input.historyStart.days(until: input.anchor) + 1
        guard daysOfHistory >= chronicWindowDays else {
            return .buildingHistory(
                daysRecorded: min(daysOfHistory, chronicWindowDays),
                daysNeeded: chronicWindowDays
            )
        }

        let chronicStart = try input.anchor.adding(days: -(chronicWindowDays - 1))
        let acuteStart = try input.anchor.adding(days: -(acuteWindowDays - 1))
        let chronicDays = try CalendarDay.days(from: chronicStart, through: input.anchor)

        var workoutsByDay: [CalendarDay: [Workout]] = [:]
        for workout in input.workouts {
            let day = try workout.calendarDay(in: input.timeZone)
            // Outside the chronic window is outside anything this reading describes —
            // dropped here rather than trusted to the caller, the same defensive
            // narrowing `TrendTileData` already applies to its own wider `workouts`
            // input.
            guard chronicStart <= day, day <= input.anchor else { continue }
            workoutsByDay[day, default: []].append(workout)
        }

        var acutePoints = 0.0
        var chronicPoints = 0.0
        var acuteWorkoutsWithoutStrain = 0
        var chronicWorkoutsWithoutStrain = 0

        for day in chronicDays {
            let inAcuteWindow = day >= acuteStart
            for workout in workoutsByDay[day] ?? [] {
                guard let points = input.derivedMetricsByWorkoutID[workout.id]?.strain?.points else {
                    chronicWorkoutsWithoutStrain += 1
                    if inAcuteWindow { acuteWorkoutsWithoutStrain += 1 }
                    continue
                }
                chronicPoints += points
                if inAcuteWindow { acutePoints += points }
            }
        }

        let chronicWeeklyAveragePoints = chronicPoints / Double(chronicWindowDays) * Double(acuteWindowDays)
        let ratio = chronicWeeklyAveragePoints > 0 ? acutePoints / chronicWeeklyAveragePoints : nil

        return .available(
            try LoadBalance(
                anchor: input.anchor,
                acuteStrainPoints: acutePoints,
                chronicStrainPoints: chronicPoints,
                chronicWeeklyAveragePoints: chronicWeeklyAveragePoints,
                ratio: ratio,
                acuteWorkoutsWithoutStrain: acuteWorkoutsWithoutStrain,
                chronicWorkoutsWithoutStrain: chronicWorkoutsWithoutStrain
            )
        )
    }
}
