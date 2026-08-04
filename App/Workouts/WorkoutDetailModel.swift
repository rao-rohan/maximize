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

    /// The zone the athlete's day boundary is drawn in. `Workout.calendarDay(in:)`
    /// requires one rather than guessing (see its doc comment); `.current` is the
    /// honest answer for a single-user, single-device app with no stored preference
    /// for it (PRD's device-only scope, A1).
    private let timeZone: TimeZone

    /// - Parameters:
    ///   - workoutID: which workout to load.
    ///   - workoutRepository/scoreRepository/planRepository: each defaults to
    ///     `PersistenceComposition.store`. Overridable so a preview or a future test
    ///     can inject fakes instead of the real on-device store.
    init(
        workoutID: UUID,
        workoutRepository: (any WorkoutRepository)? = nil,
        scoreRepository: (any ScoreRepository)? = nil,
        planRepository: (any PlanRepository)? = nil,
        timeZone: TimeZone = .current
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
        self.timeZone = timeZone
    }

    func load() async {
        guard let workoutRepository, let scoreRepository, let planRepository else {
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
            let day = try workout.calendarDay(in: timeZone)
            let planDay = try planCalendar?.planDay(on: day)

            // Fetched once, here, and handed to every section below — MAX-042's D2
            // discipline: a metric read once at ingestion must also be read only once
            // per screen load, never re-fetched (let alone recomputed) per section.
            let metrics = try await workoutRepository.derivedMetrics(forWorkout: workoutID)

            let verdict = WorkoutVerdict(workout: workout, planDay: planDay, ledger: ledger)
            let chartData = try await heartRateChart(
                workoutRepository: workoutRepository,
                planCalendar: planCalendar,
                day: day,
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

            state = .loaded(
                WorkoutDetailData(verdict: verdict, heartRateChart: chartData, cadence: cadence, routeMap: routeMap)
            )
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
    private func heartRateChart(
        workoutRepository: any WorkoutRepository,
        planCalendar: PlanCalendar?,
        day: CalendarDay,
        metrics: DerivedMetrics?
    ) async throws -> HeartRateChartData? {
        guard let series = try await workoutRepository.heartRateSeries(forWorkout: workoutID) else {
            return nil
        }
        let capBPM = planCalendar?.plan(on: day)?.heartRateCapBPM
        return HeartRateChartData(series: series, capBPM: capBPM, timeAboveCapSeconds: metrics?.timeAboveCapSeconds)
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
}
