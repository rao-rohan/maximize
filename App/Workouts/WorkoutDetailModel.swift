import Foundation
import MaximizeCore
import Observation

/// Everything the detail screen's sections read for one workout. Bundled into a value
/// rather than several optional properties on the model so each ticket that adds a
/// section (MAX-042's `heartRateChart`, MAX-043's cadence, MAX-044's route, MAX-045's
/// splits) adds one field here instead of widening `LoadState.loaded`'s case itself.
struct WorkoutDetailData: Equatable {
    let verdict: WorkoutVerdict

    /// FR-1.2. Nil means no HR series was captured for this workout at all — a real,
    /// first-class state (MAX-010's "absent, not empty"), not a loading placeholder.
    /// `HRCurveView` renders that nil as "no chart to draw" rather than an empty axis.
    let heartRateChart: HeartRateChartData?

    /// FR-1.3. Unlike `heartRateChart`, always present — there is no "nothing to
    /// build from" case for cadence. A run with no step count, a day with no
    /// governing plan, and a run with both are all real states `CadenceChartData`
    /// carries rather than a reason to omit the section; see its own documentation
    /// and `CadenceBandView`'s for how each renders.
    let cadence: CadenceChartData

    /// FR-1.4. Always present, like `cadence` — `RouteMapData.resolve(hasRoute:route:)`
    /// is where the indoor / unavailable / available branch lives (see its own
    /// documentation), so this model only fetches what that decision needs and hands
    /// the result on. `RouteMapView` is what turns each case into the right on-screen
    /// state.
    let routeMap: RouteMapData

    /// FR-1.5's per-split pace breakdown. Always present, like `routeMap`:
    /// `SplitsListData.resolve(hasRoute:splits:unit:)` owns the indoor / no-breakdown /
    /// available branch, so this model only fetches what that decision needs.
    let splits: SplitsListData

    /// FR-1.5. Always present — `SummaryTileData.duration` is never absent (see its
    /// own documentation) — so there is no "nothing to build from" case here either.
    let summaryTiles: SummaryTileData

    /// A22/MAX-145. What the athlete has said this session worked, and — for a lift they
    /// have not answered for — the prompt that asks. `.notALift` on every run, which is
    /// what keeps the section off a screen it has no business being on;
    /// `MuscleGroupEntryData.resolve` is where that is decided.
    let muscleGroups: MuscleGroupEntryData

    /// MAX-047. The athlete's chosen `DistanceUnit`, threaded down to every section on
    /// this screen that shows a distance — `summaryTiles` already carries it into
    /// `SummaryTileData`'s own formatting, and `VerdictHeaderView` needs it separately
    /// for the scheduled session's distance, which lives outside `SummaryTileData`.
    let distanceUnit: DistanceUnit
}

/// Loads one workout and assembles `WorkoutDetailData` for the detail screen. Everything
/// that decides *what a section should say* — unscored vs. scored, plan vs. no plan,
/// auto-score vs. correction — lives in `WorkoutVerdict` and `HeartRateChartData` and is
/// unit tested there; this class only fetches the records each section needs and hands
/// the result to the view.
@MainActor
@Observable
final class WorkoutDetailModel {
    enum LoadState: Equatable {
        case loading
        case loaded(WorkoutDetailData)
        /// The store could not be opened, the workout no longer exists, or a read
        /// failed. See `WorkoutsListModel.LoadState.failed` for why this stays one
        /// case rather than several.
        case failed
    }

    private(set) var state: LoadState = .loading

    private let workoutID: UUID
    private let workoutRepository: (any WorkoutRepository)?
    private let scoreRepository: (any ScoreRepository)?
    private let planRepository: (any PlanRepository)?
    private let settingsRepository: (any SettingsRepository)?
    private let muscleGroupRepository: (any MuscleGroupEntryRepository)?

    /// Mints the identifier and the timestamp for a new muscle-group entry (A22).
    /// Injected for the reason `WorkoutIngestionPipeline` injects `now`: a record is
    /// then a pure function of its inputs, and a future test can assert on the whole of
    /// it rather than on everything except two fields.
    private let newEntryID: @Sendable () -> UUID
    private let now: @Sendable () -> Date

    /// The zone the athlete's day boundary is drawn in. `Workout.calendarDay(in:)`
    /// requires one rather than guessing (see its doc comment); `.current` is the
    /// honest answer for a single-user, single-device app with no stored preference
    /// for it (PRD's device-only scope, A1).
    private let timeZone: TimeZone

    /// - Parameters:
    ///   - workoutID: which workout to load.
    ///   - workoutRepository/scoreRepository/planRepository/settingsRepository: each
    ///     defaults to `PersistenceComposition.store`. Overridable so a preview or a
    ///     future test can inject fakes instead of the real on-device store.
    init(
        workoutID: UUID,
        workoutRepository: (any WorkoutRepository)? = nil,
        scoreRepository: (any ScoreRepository)? = nil,
        planRepository: (any PlanRepository)? = nil,
        settingsRepository: (any SettingsRepository)? = nil,
        muscleGroupRepository: (any MuscleGroupEntryRepository)? = nil,
        timeZone: TimeZone = .current,
        newEntryID: @escaping @Sendable () -> UUID = { UUID() },
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.workoutID = workoutID
        if let workoutRepository {
            self.workoutRepository = workoutRepository
        } else {
            self.workoutRepository = PersistenceComposition.store
        }
        if let scoreRepository {
            self.scoreRepository = scoreRepository
        } else {
            self.scoreRepository = PersistenceComposition.store
        }
        if let planRepository {
            self.planRepository = planRepository
        } else {
            self.planRepository = PersistenceComposition.store
        }
        if let settingsRepository {
            self.settingsRepository = settingsRepository
        } else {
            self.settingsRepository = PersistenceComposition.store
        }
        if let muscleGroupRepository {
            self.muscleGroupRepository = muscleGroupRepository
        } else {
            self.muscleGroupRepository = PersistenceComposition.store
        }
        self.timeZone = timeZone
        self.newEntryID = newEntryID
        self.now = now
    }

    func load() async {
        guard let workoutRepository, let scoreRepository, let planRepository, let settingsRepository,
              let muscleGroupRepository
        else {
            state = .failed
            return
        }
        do {
            guard let workout = try await workoutRepository.workout(id: workoutID) else {
                state = .failed
                return
            }
            let ledger = try await scoreRepository.ledger(forWorkout: workoutID)
            let planCalendar = try await planRepository.planCalendar()
            let distanceUnit = try await settingsRepository.settings().distanceUnit
            let day = try workout.calendarDay(in: timeZone)
            let planDay = try planCalendar?.planDay(on: day)

            // Fetched once, here, and handed to every section below — MAX-042's D2
            // discipline: a metric read once at ingestion must also be read only once
            // per screen load, never re-fetched (let alone recomputed) per section.
            let metrics = try await workoutRepository.derivedMetrics(forWorkout: workoutID)

            // A22: read once, here, and handed to both surfaces that speak about it —
            // the verdict header's waiting state and the section that answers it. Two
            // reads could disagree; one cannot.
            let muscleGroupLog = try await muscleGroupRepository.muscleGroupLog(forWorkout: workoutID)

            let verdict = WorkoutVerdict(
                workout: workout,
                planDay: planDay,
                ledger: ledger,
                muscleGroups: muscleGroupLog
            )
            let muscleGroups = MuscleGroupEntryData.resolve(
                activityType: workout.activityType,
                entry: muscleGroupLog.current
            )
            let chartData = try await heartRateChart(
                workoutRepository: workoutRepository,
                planCalendar: planCalendar,
                day: day,
                discipline: workout.activityType.discipline,
                metrics: metrics
            )
            let cadence = CadenceChartData(
                averageStepsPerMinute: metrics?.averageCadenceStepsPerMinute,
                band: planCalendar?.plan(on: day)?.cadenceTarget
            )
            // The read only happens when `hasRoute` says there is something to find —
            // `RouteMapData.resolve`'s contract (see its doc comment) — rather than
            // querying the store for every indoor run.
            let route = workout.hasRoute ? try await workoutRepository.route(forWorkout: workoutID) : nil
            let routeMap = RouteMapData.resolve(hasRoute: workout.hasRoute, route: route)
            // The splits are read from the stored metrics, never derived from the route
            // fetched above (D2) — `DistanceSplitCalculator` cut them at ingestion.
            //
            // MAX-046 passed `.kilometers` here and named this the one line MAX-047 would
            // change. This is that change. It is a one-liner precisely because MAX-046
            // stored *both* cuts: split boundaries in km and in miles do not align, and
            // re-cutting one into the other would mean going back to the GPS track at
            // display time, which is the D2 violation both tickets were written to avoid.
            let splits = SplitsListData.resolve(
                hasRoute: workout.hasRoute,
                splits: metrics?.distanceSplits,
                unit: distanceUnit
            )
            let summaryTiles = SummaryTileData(workout: workout, metrics: metrics, distanceUnit: distanceUnit)

            state = .loaded(WorkoutDetailData(
                verdict: verdict,
                heartRateChart: chartData,
                cadence: cadence,
                routeMap: routeMap,
                splits: splits,
                summaryTiles: summaryTiles,
                muscleGroups: muscleGroups,
                distanceUnit: distanceUnit
            ))
        } catch {
            state = .failed
        }
    }

    /// FR-1.2's inputs: the stored curve, the plan's cap for the workout's day (D1 —
    /// `PlanCalendar.plan(on:)`, never a literal), and the stored time-above-cap figure
    /// (D2 — `DerivedMetrics.timeAboveCapSeconds`, read, never recomputed here).
    ///
    /// Nil when no HR series was captured — MAX-010's "absent, not empty" distinction —
    /// which is the one case with nothing to build a chart from at all. A workout with a
    /// series but no governing plan, or a series but not-yet-computed metrics, still
    /// yields a `HeartRateChartData`; `capBPM` and `timeAboveCapSeconds` simply carry nil
    /// through it, and `HRCurveView` is what turns those into the right on-screen state.
    ///
    /// **`capBPM` is withheld for a lift (MAX-139, LIFTING-SPEC §10.1).**
    /// `Plan.heartRateCapBPM` is documented as the easy-run ceiling, and it is a single
    /// plan-level field with no per-discipline sibling — so without this guard, any day
    /// a plan governs hands a lift's curve the running cap regardless of which slot the
    /// day actually prescribed for lifting. `metrics?.timeAboveCapSeconds` needs no
    /// matching guard: `DerivedMetricKind` already gates that figure to `.runDiscipline`
    /// at ingestion, so it is nil for a lift already.
    private func heartRateChart(
        workoutRepository: any WorkoutRepository,
        planCalendar: PlanCalendar?,
        day: CalendarDay,
        discipline: Discipline,
        metrics: DerivedMetrics?
    ) async throws -> HeartRateChartData? {
        guard let series = try await workoutRepository.heartRateSeries(forWorkout: workoutID) else {
            return nil
        }
        let capBPM = discipline == .run ? planCalendar?.plan(on: day)?.heartRateCapBPM : nil
        return HeartRateChartData(
            series: series,
            discipline: discipline,
            capBPM: capBPM,
            timeAboveCapSeconds: metrics?.timeAboveCapSeconds
        )
    }

    /// R8's lazy path (MAX-033): scores a run the background wake could not score.
    ///
    /// Called unconditionally, and that is deliberate — whether this run needs anything
    /// is `WorkoutIngestionPipeline.completeIngestion(forWorkout:)`'s decision, made in
    /// `MaximizeCore` where CI runs it, and it returns immediately for a workout that
    /// already has a score. A view asking "is this unscored?" for itself would be a
    /// business rule in the shell.
    ///
    /// Reloads afterwards, because a score that arrives while the screen is open should
    /// appear on it. A no-op completion reloads too; a second read of three local records
    /// is cheaper than a rule for when to skip it.
    func scoreIfNeeded() async {
        await IngestionComposition.completeIngestion(forWorkout: workoutID)
        await load()
    }

    /// A22: records what the athlete says this session worked.
    ///
    /// **Additive.** This appends an entry; it never edits one, because
    /// `MuscleGroupEntryRepository` offers no path that could. Changing the answer later
    /// appends again and the earlier answer stays on file — `ScoreAnnotation`'s
    /// discipline, applied to an input.
    ///
    /// Goes through `MuscleGroupEntry`'s validating initializer, so an empty set cannot
    /// reach storage even though the picker's Save button is already disabled for one:
    /// "I trained nothing" is not a thing this record may say, and the type is what says
    /// so rather than the button.
    ///
    /// Reloads afterwards, because the header's waiting state and the section's copy
    /// both change the moment this lands. A failed write leaves the screen showing what
    /// is actually stored, which is the honest outcome — the athlete sees the prompt
    /// still asking rather than an answer that was never recorded.
    func setMuscleGroups(_ groups: Set<MuscleGroup>) async {
        guard let muscleGroupRepository else { return }
        do {
            let entry = try MuscleGroupEntry(
                id: newEntryID(),
                workoutID: workoutID,
                groups: groups,
                recordedAt: now()
            )
            try await muscleGroupRepository.record(entry)
        } catch {
            // Nothing useful to say here that reloading does not say better: the section
            // will render whatever is actually on file. A thrown `DomainError` means an
            // empty set got past the picker, which is a programming error, not a state
            // to narrate at the athlete.
        }
        await load()
    }
}
