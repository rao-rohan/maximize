import Foundation

/// Chart-ready — tile-ready — presentation of one workout's summary figures (FR-1.5):
/// distance, duration, avg/max HR, energy, drift %, grade-adjusted pace. Precomputed
/// here, mirroring `HeartRateChartData` (MAX-042) and `CadenceChartData` (MAX-043), so
/// CI verifies the formatting instead of a device.
///
/// ## Thin by design
///
/// FR-1.5 calls this section out explicitly as "thin — displayed because cheap, not
/// lovingly built." Every figure below is a straight read of an already-stored number
/// (`Workout` or `DerivedMetrics`, D2) run through a formatter; nothing here classifies,
/// judges, or compares against a threshold. There is deliberately no in-band/out-of-band
/// verdict, no color, no "good/bad" — `CadenceBandView` and `HRCurveView` already own
/// that kind of judgment for the figures that need it, and duplicating it here would be
/// exactly the second-source-of-truth problem D2 exists to prevent.
///
/// ## What "splits" does not mean here
///
/// FR-1.5's requirement is written as "**Splits** and summary tiles (distance,
/// duration, avg/max HR, energy, drift %, grade-adjusted pace)." The parenthetical names
/// summary-tile figures only — a per-kilometre or per-mile pace breakdown is a different
/// figure, and this type still does not build one. MAX-045 declined to derive it here
/// because nothing computed it at ingestion, and inventing a display-time pace would have
/// created a number nothing else in the app agrees with (D2).
///
/// **MAX-046 supplied the missing data source rather than moving that line.** Splits are
/// now cut once at ingestion by `DistanceSplitCalculator`, stored on
/// `DerivedMetrics.distanceSplits`, and rendered by `SplitsListData` — a sibling section,
/// not a tile. Note that `DerivedMetrics.zoneSplits` remains a different measurement
/// entirely: time spent in each *heart-rate zone*, which shares only the word.
///
/// ## Absent is not zero
///
/// Every tile but `duration` is optional, and nil means *this workout does not have
/// this figure* — no distance recorded, no heart-rate series to average, drift withheld
/// because this session's classification is not one drift is meaningful for (§9).
/// `SummaryTilesView` renders a nil by omitting the tile, never by printing a
/// fabricated zero. `duration` is the one figure `Workout` always carries, so it is
/// the one non-optional tile.
///
/// ## A lift is not a run with holes in it (LIFTING-SPEC §10.1, MAX-139)
///
/// Three of the seven tiles — distance, drift, grade-adjusted pace — describe a running
/// prescription rather than a measurement that merely happened to be missing. For a
/// lift these are gated **explicitly**, to `nil`, by discipline, rather than left to the
/// upstream absence MAX-130 already produces for most of them. Two reasons that is not
/// redundant:
///
/// - `distance` reads straight off `Workout.distanceMeters`, which `DerivedMetricKind`
///   has no opinion about at all — nothing upstream of this type stops a captured
///   lift from carrying one, however unlikely.
/// - A lift ingested **before** MAX-130 shipped can carry a stored drift or
///   grade-adjusted pace figure computed by the old, discipline-blind calculator — the
///   same "a lift ingested before this ticket has stored numbers for fields that no
///   longer apply" case `WorkoutFactSheet`'s `describesARun` branch guards against.
///
/// Explicit gating is what keeps this type's own promise — "the numbers a lift actually
/// has, not a run's screen with holes in it" — true regardless of what a caller hands
/// it, rather than true only by the accident of what happens to be nil today.
///
/// `showsRunOnlySections` and `disciplineNote` extend the same decision to the three
/// sibling sections `WorkoutDetailView` composes around these tiles — cadence, route,
/// splits, and the HR curve's cap line — none of which is a `SummaryTileData` tile, but
/// all of which the ticket that added those two properties needed one tested place to
/// decide, per CLAUDE.md's rule that a view must not branch on discipline to decide what
/// it shows.
public struct SummaryTileData: Hashable, Sendable {
    /// One rendered figure: a bare value and the caption that gives it meaning ("8.42"
    /// / "km"). Both are already formatted; `SummaryTilesView` only lays them out.
    public struct Tile: Hashable, Sendable {
        public let value: String
        public let caption: String

        public init(value: String, caption: String) {
            self.value = value
            self.caption = caption
        }
    }

    /// `Workout.distanceMeters`, converted and formatted in the athlete's chosen
    /// `DistanceUnit` (MAX-047 — the unit is a display decision, never a stored one).
    /// Nil when the workout recorded no distance at all (common for an indoor session
    /// with no GPS and no manually entered distance).
    public let distance: Tile?

    /// `Workout.durationSeconds`, formatted `H:MM:SS`/`M:SS`. Always present — a
    /// workout's duration is never optional in the domain model, so zero here is a real
    /// recorded duration, not an absence.
    public let duration: Tile

    /// `DerivedMetrics.averageHeartRateBPM`, unchanged. Nil when this run has no
    /// heart-rate series (MAX-010's "absent, not empty"), or when metrics have not been
    /// computed for this workout yet.
    public let averageHeartRate: Tile?

    /// `DerivedMetrics.maximumHeartRateBPM`, unchanged. Same absence rule as above.
    public let maximumHeartRate: Tile?

    /// `Workout.activeEnergyKilocalories`, unchanged. Nil when the capture source
    /// reported none.
    public let activeEnergy: Tile?

    /// `DerivedMetrics.heartRateDriftFraction`, unchanged, shown as a signed percentage.
    /// Nil both when there is no HR data and when drift was withheld as not meaningful
    /// for this session's classification (§9) — `SummaryTilesView` cannot and does not
    /// distinguish the two reasons from this type alone; it simply omits the tile.
    public let heartRateDrift: Tile?

    /// `DerivedMetrics.gradeAdjustedPaceSecondsPerKilometer`, converted to seconds per
    /// the athlete's chosen `DistanceUnit` and formatted as a pace. Stored as
    /// seconds-per-kilometre always (D2); the caption names which unit this particular
    /// figure is paced against, since "grade-adj. pace" alone is ambiguous once the
    /// unit varies. Nil for indoor runs, a route with no usable altitude, or metrics
    /// not yet computed.
    public let gradeAdjustedPace: Tile?

    /// Which of the plan's two prescriptions this workout belongs to (A17), read from
    /// `Workout.activityType.discipline` — the one place that mapping lives, the same
    /// source `WorkoutVerdict.discipline` reads, so the tiles and the header above them
    /// cannot disagree about which workout they describe.
    public let discipline: Discipline

    /// Whether the sections `WorkoutDetailView` composes around these tiles — cadence
    /// versus target, the route map, the pace splits, and the HR curve's cap line —
    /// belong on this workout's screen at all (LIFTING-SPEC §10.1, MAX-139).
    ///
    /// `false` for a lift. All four describe a *running* prescription: a cadence target
    /// is steps against a running gait, a route and its splits assume a distance, and
    /// `Plan.heartRateCapBPM` is documented as the easy-run ceiling. None of the four is
    /// meaningless by accident — MAX-130 already stopped computing the cadence and
    /// splits figures underneath two of them — and this is the one place the decision
    /// is made explicit and tested rather than left to whichever of those sections
    /// happens to resolve an empty state correctly today. `WorkoutDetailView` reads
    /// this rather than comparing `discipline` itself, so the rule pinned by the tests
    /// below cannot drift from what the screen composes.
    public let showsRunOnlySections: Bool

    /// Said once, in place of the four sections `showsRunOnlySections` turns off,
    /// rather than each carrying its own "not applicable" card — the summary-tile
    /// scale reading of the same trade `WorkoutFactSheet.disciplineFraming` makes for
    /// the prompt (MAX-136). Non-nil only for a lift; nil for a run, which has nothing
    /// to explain.
    ///
    /// **Its own sentence, not `WorkoutFactSheet`'s, and not `RouteMapView`'s "no route
    /// for an indoor run" either.** Those are facts about *this session* — the sensor
    /// simply was not there. This is a fact about the *discipline* — the figure could
    /// never have described this session, indoors or not — and CLAUDE.md is explicit
    /// that the two are different statements and must not share copy.
    public let disciplineNote: String?

    /// - Parameters:
    ///   - workout: supplies `distance`, `duration`, `activeEnergy` and `discipline`
    ///     directly. This initializer never derives any of the three figures from the
    ///     others.
    ///   - metrics: `DerivedMetrics` for this workout (D2 — read, never recomputed),
    ///     or nil if metrics have not been computed yet. Supplies `averageHeartRate`,
    ///     `maximumHeartRate`, `heartRateDrift`, `gradeAdjustedPace`.
    ///   - distanceUnit: MAX-047 — a display decision only. `Workout` and
    ///     `DerivedMetrics` stay in metres/seconds-per-kilometre regardless; this
    ///     initializer is the one place that converts for the tile. No default: every
    ///     call site must say explicitly which unit it means, rather than one silently
    ///     picking up a fallback (the shape MAX-049 removed for `SettingsRepository`).
    public init(workout: Workout, metrics: DerivedMetrics?, distanceUnit: DistanceUnit) {
        let discipline = workout.activityType.discipline
        self.discipline = discipline
        self.showsRunOnlySections = discipline == .run
        self.disciplineNote = discipline == .lift ? Self.disciplineNoteText : nil

        // Explicit, not incidental — see the type note on why a lift's distance,
        // drift and grade-adjusted pace are gated here rather than trusted to already
        // be nil.
        self.distance = discipline == .lift ? nil : workout.distanceMeters.map {
            Tile(value: Self.formattedDistance($0, unit: distanceUnit), caption: distanceUnit.abbreviation)
        }
        self.duration = Tile(value: Self.formattedDuration(seconds: workout.durationSeconds), caption: "duration")
        // Both disciplines. A heart rate measured during a lift is a heart rate
        // (LIFTING-SPEC §3.2), and it is the one rich signal a lift gives for free.
        self.averageHeartRate = metrics?.averageHeartRateBPM.map {
            Tile(value: Self.formattedBPM($0), caption: "avg bpm")
        }
        self.maximumHeartRate = metrics?.maximumHeartRateBPM.map {
            Tile(value: Self.formattedBPM($0), caption: "max bpm")
        }
        self.activeEnergy = workout.activeEnergyKilocalories.map {
            Tile(value: Self.formattedKilocalories($0), caption: "kcal")
        }
        // Explicit, not incidental — see the type note. `driftIsMeaningful` already
        // withholds this for `.lift`/`.other`, and MAX-130 already stops the calculator
        // computing it for a lift, so this guard only ever fires for a record ingested
        // before either existed.
        self.heartRateDrift = discipline == .lift ? nil : metrics?.heartRateDriftFraction.map {
            Tile(value: Self.formattedSignedPercent($0), caption: "% drift")
        }
        // Explicit, not incidental, for the identical reason.
        self.gradeAdjustedPace = discipline == .lift ? nil : metrics?.gradeAdjustedPaceSecondsPerKilometer.map {
            Tile(
                value: Self.formattedPace($0, unit: distanceUnit),
                caption: "grade-adj. pace /\(distanceUnit.abbreviation)"
            )
        }
    }

    /// Worded apart from `WorkoutFactSheet.disciplineFraming` and from `RouteMapView`'s
    /// indoor copy — see the type note on why the three must not share a sentence.
    /// Names the same four things the fact sheet's absence rule inverts for, at the
    /// screen's own scale: cadence, route, splits and the heart-rate cap line.
    private static let disciplineNoteText =
        "This is a lift, not a run, so the figures a run is measured by — cadence, route, "
        + "pace splits, and the heart-rate cap — are left off rather than shown empty."

    /// Every present tile, in FR-1.5's own order: distance, duration, avg/max HR,
    /// energy, drift %, grade-adjusted pace. `SummaryTilesView` reads only this — it
    /// never has to know which figures can be absent or reorder them itself.
    public var tiles: [Tile] {
        let all: [Tile?] = [
            distance, duration, averageHeartRate, maximumHeartRate, activeEnergy, heartRateDrift, gradeAdjustedPace,
        ]
        return all.compactMap { $0 }
    }

    // MARK: - Formatting
    //
    // Locale pinned to nil (POSIX) throughout, matching `WorkoutFactSheet` — a device
    // set to a comma-decimal locale must not render a different number here than one
    // set to a point-decimal locale.

    /// "7:42" under an hour, "1:02:03" at or beyond one hour. Deliberately a different
    /// shape from `HeartRateChartData.formattedDuration`'s "12m 34s": that format reads
    /// as prose inside a sentence ("12m 34s above cap"); this one is the headline value
    /// of a tile, and a stopwatch-style reading is the conventional shape for that.
    public static func formattedDuration(seconds: Double) -> String {
        let totalSeconds = Int(seconds.rounded())
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let remainderSeconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", locale: nil, hours, minutes, remainderSeconds)
        }
        return String(format: "%d:%02d", locale: nil, minutes, remainderSeconds)
    }

    /// "5:12" for a pace of 5 minutes 12 seconds per the given unit. `secondsPerKilometer`
    /// is always the stored figure (D2); this converts to seconds-per-unit before
    /// formatting, since a mile is longer than a kilometre and so takes proportionally
    /// longer to cover. The caption supplies the unit and "grade-adjusted" context, so
    /// the value stays a bare stopwatch reading, consistent with `formattedDuration`.
    static func formattedPace(_ secondsPerKilometer: Double, unit: DistanceUnit) -> String {
        let secondsPerUnit = secondsPerKilometer * (unit.metersPerUnit / 1_000)
        let totalSeconds = Int(secondsPerUnit.rounded())
        let minutes = totalSeconds / 60
        let remainderSeconds = totalSeconds % 60
        return String(format: "%d:%02d", locale: nil, minutes, remainderSeconds)
    }

    /// Two decimal places, matching the precision `WorkoutFactSheet` sends Claude for
    /// the underlying kilometre figure — `WorkoutFactSheet` is deliberately unit-fixed
    /// (D3: one deterministic fact sheet, independent of a display preference), so
    /// this is the only place the athlete's chosen `DistanceUnit` enters the number.
    static func formattedDistance(_ meters: Double, unit: DistanceUnit) -> String {
        String(format: "%.2f", locale: nil, unit.converted(fromMeters: meters))
    }

    static func formattedBPM(_ beatsPerMinute: Double) -> String {
        String(format: "%.0f", locale: nil, beatsPerMinute)
    }

    static func formattedKilocalories(_ kilocalories: Double) -> String {
        String(format: "%.0f", locale: nil, kilocalories)
    }

    /// "+3.1" or "-2.4" — the sign always shown, since an unsigned drift percentage
    /// would silently discard the direction (whether HR rose or fell across the run),
    /// which is the entire point of the figure (§9's "aerobic decoupling").
    static func formattedSignedPercent(_ fraction: Double) -> String {
        let sign = fraction >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.1f", locale: nil, fraction * 100))"
    }
}
