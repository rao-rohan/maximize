/// A category of health data the ingestion pipeline needs to read.
///
/// This is a *core* vocabulary, not a HealthKit one: the core decides which data the
/// pipeline needs, and the app layer maps each case onto the corresponding
/// `HKObjectType`. That mapping is the only part of authorization that CI cannot
/// verify, and it is a lookup table with no decisions in it.
///
/// Deliberately not an alias for a HealthKit identifier — `MaximizeCore` must not
/// import HealthKit (CLAUDE.md), and keeping the vocabulary here is what lets the
/// scope of the authorization request be unit tested at all.
public enum HealthDataType: String, CaseIterable, Hashable, Sendable {
    /// Completed workouts. The observer in `HKObserverQuery` watches this type, and
    /// it is the anchor for everything else the pipeline reads (PRD §7.0).
    case workout

    /// Per-sample heart-rate series. PRD §9's HR-drift and time-above-cap metrics are
    /// computed from this; summaries are not sufficient (PRD §3, "full-fidelity data").
    case heartRate

    /// Distance covered on foot, for pace and the weekly mileage arc.
    case distanceWalkingRunning

    /// Active energy burned, part of the per-workout summary in FR-0.3.
    case activeEnergyBurned

    /// Step count, from which running cadence is derived (PRD §9). HealthKit has no
    /// first-class "cadence" quantity for runs; steps over elapsed time is the
    /// standard derivation.
    case stepCount

    /// The GPS route series attached to an outdoor workout.
    ///
    /// Included in the authorization request even though route *extraction* is
    /// MAX-032's job: HealthKit's permission sheet is presented once per newly
    /// requested type, so asking for the route later would mean a second prompt on an
    /// app whose entire premise is that the user does nothing (PRD §2). Indoor runs
    /// legitimately have no route and stay first-class (FR-0.6).
    case workoutRoute
}

/// The exact scope of HealthKit access the ingestion pipeline asks for.
///
/// Split into read and write sets so that "this app never writes to HealthKit" is a
/// property CI checks on every commit rather than a claim in a comment. The app
/// layer derives both HealthKit sets from these values instead of hard-coding them —
/// see `HealthKitWorkoutObserver` — which is what makes the assertion load-bearing.
public enum WorkoutIngestionAuthorization {
    /// Everything the pipeline reads.
    public static let readTypes: Set<HealthDataType> = [
        .workout,
        .heartRate,
        .distanceWalkingRunning,
        .activeEnergyBurned,
        .stepCount,
        .workoutRoute,
    ]

    /// Empty, and required to stay empty.
    ///
    /// PRD §3 lists "writing to HealthKit" as an explicit non-goal: this app reads
    /// what Apple already recorded and never contributes to the store. A write scope
    /// would also widen the permission sheet, which is a cost paid by the user for a
    /// capability the product does not have.
    public static let writeTypes: Set<HealthDataType> = []
}
