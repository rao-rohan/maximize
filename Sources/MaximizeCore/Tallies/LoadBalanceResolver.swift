import Foundation

/// Assembles `LoadBalanceInput` from stored records and calls the calculator (MAX-178,
/// MAX-192).
///
/// `LoadBalanceCalculator` is a pure function and stays one; this is the small amount of
/// *fetching* it needs, in one place, because two surfaces now want the same reading and
/// two copies of the fetch is how they would come to disagree. The dashboard's tile
/// (`TrendTilesModel`) resolved it this way first, and this type is that resolution moved
/// down into the core where a unit test can drive it — CLAUDE.md's thin-shell rule
/// applied to the one part of the figure that was still living in a view model.
///
/// ## The two reads, and why the second one exists
///
/// The chronic window's own workouts are needed for the sums. `historyStart` — the
/// earliest day the app can vouch for — is what tells a genuinely empty month apart from
/// a month before the app was installed, and it cannot be read off the chronic window
/// alone: an athlete with two years of history who happens to have trained only in the
/// last five days would otherwise be told the app is still building a baseline, while the
/// dashboard tile beside the conversation showed a real ratio.
///
/// So a second, bounded probe asks whether *anything* exists before the chronic window.
/// Only the answer matters, never the day: `LoadBalanceCalculator`'s guard compares a
/// count against `chronicWindowDays`, so any day at or before the window's start settles
/// it identically, and the window's own start stands in rather than resolving a true
/// minimum over every workout ever stored.
public enum LoadBalanceResolver {

    /// A floor for the backward probe, bounded well before any HealthKit workout could
    /// plausibly exist rather than `Date.distantPast` — both are correct, and a concrete
    /// day keeps the query inside `DateInterval.covering(from:through:in:)`'s ordinary
    /// contract instead of leaning on an extreme sentinel `Date`.
    static let historyProbeFloor = try? CalendarDay(year: 2010, month: 1, day: 1)

    /// - Parameters:
    ///   - anchor: the day both windows end on, inclusive. **The caller's `today`**, never
    ///     a clock read in here (MAX-110), and never a frozen window's last day — see
    ///     `TrainingContext.loadBalance` for why a rolling read takes the current day even
    ///     when the surface around it does not.
    ///   - timeZone: the athlete's zone, matching `Workout.calendarDay(in:)`.
    public static func reading(
        anchor: CalendarDay,
        timeZone: TimeZone,
        workoutRepository: any WorkoutRepository
    ) async throws -> LoadBalanceReading {
        let chronicWindowStart = try anchor.adding(
            days: -(LoadBalanceCalculator.chronicWindowDays - 1)
        )

        let chronicInterval = try DateInterval.covering(
            from: chronicWindowStart, through: anchor, in: timeZone
        )
        let chronicWorkouts = try await workoutRepository.workouts(startingIn: chronicInterval)

        var historyStart = anchor
        if let earliest = try chronicWorkouts.map({ try $0.calendarDay(in: timeZone) }).min() {
            historyStart = earliest
        }

        // Only worth probing further back when the chronic window's own earliest workout
        // has not already proven sufficiency (a workout on the window's first day puts
        // `historyStart` at or before it).
        if historyStart > chronicWindowStart,
           let floor = historyProbeFloor,
           floor < chronicWindowStart {
            let priorInterval = try DateInterval.covering(
                from: floor,
                through: try chronicWindowStart.adding(days: -1),
                in: timeZone
            )
            let priorWorkouts = try await workoutRepository.workouts(startingIn: priorInterval)
            if !priorWorkouts.isEmpty {
                historyStart = chronicWindowStart
            }
        }

        var derivedMetricsByWorkoutID: [UUID: DerivedMetrics] = [:]
        for workout in chronicWorkouts {
            if let metrics = try await workoutRepository.derivedMetrics(forWorkout: workout.id) {
                derivedMetricsByWorkoutID[workout.id] = metrics
            }
        }

        return try LoadBalanceCalculator.compute(
            LoadBalanceInput(
                anchor: anchor,
                timeZone: timeZone,
                historyStart: historyStart,
                workouts: chronicWorkouts,
                derivedMetricsByWorkoutID: derivedMetricsByWorkoutID
            )
        )
    }
}
