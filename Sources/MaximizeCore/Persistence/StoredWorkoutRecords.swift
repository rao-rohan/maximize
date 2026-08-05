import Foundation

// MARK: - Why this layer exists
//
// The stored records in this file sit between the domain value types and the
// SwiftData `@Model` classes in `App/Persistence`. That is a third representation of
// data that already has two, so it owes an explanation.
//
// CI runs `swift test` against `MaximizeCore`. It never runs a SwiftData store —
// there is no simulator or device in the loop (tracker R2). So any mapping written
// directly between a domain type and an `@Model` class is mapping that no automated
// gate ever checks, on the one part of the system that is most expensive to get wrong:
// a schema, whose mistakes are only discoverable after data exists.
//
// Splitting the mapping in two moves the whole judgement into the tested half:
//
//   Workout  <--(here, unit tested)-->  StoredWorkout  <--(App/, 1:1)-->  WorkoutRecord
//
// Everything with a decision in it — which field carries which unit, how an enum
// becomes a string, which nested structure becomes a blob, what makes a stored record
// self-contradictory — lives here and is round-trip tested. What is left in the app
// layer is a field-for-field copy between a struct and a class with the same property
// names, containing no branches. That is CLAUDE.md's rule applied literally: push the
// logic down until the untestable part is a thin adapter with no decisions in it.
//
// # Shape rules these records follow
//
// 1. **Only SwiftData-native types**: `UUID`, `String`, `Int`, `Double`, `Bool`,
//    `Date`, `Data`, and optionals of those. No nested structs, no arrays, no enums.
//    The `@Model` class can therefore declare the identical property list, which is
//    what keeps the app-layer copy mechanical.
// 2. **No `@Attribute(.unique)` anywhere it would be needed.** See
//    `StoredWorkout.workoutUUID` — CloudKit cannot enforce uniqueness, so dedupe is a
//    write-path responsibility instead.
// 3. **Reconstruction goes through the domain initializer**, never around it. Every
//    `toDomain()` calls the same validating `init` an ingested workout does, so a
//    record that was corrupted on disk, mangled by a bad migration, or merged badly by
//    CloudKit is rejected at the boundary rather than flowing into the scorer as a
//    plausible-looking wrong number.

/// `Workout` as stored (PRD §8 `workout`).
///
/// Every field is a scalar, so this record needs no blob at all.
///
/// ## `workoutUUID` is the dedupe key, and it is *not* a unique constraint
///
/// FR-0.5 dedupes on the HealthKit workout UUID, and the natural expression of that in
/// SwiftData would be `@Attribute(.unique)`. That is not available here. Apple, on
/// defining a CloudKit-compatible schema: the framework "does include a small number of
/// features that CloudKit doesn't support natively, such as unique constraints and
/// nonoptional relationships", because "the framework synchronizes changes concurrently
/// and at opportune times, which means CloudKit is unable to enforce the [unique]
/// property option." Core Data's CloudKit model rules say the same thing more bluntly:
/// "Unique constraints aren't supported."
///
/// Since A1 makes CloudKit the backup story and MAX-021 turns it on, the constraint
/// cannot be used. Dedupe is therefore enforced on the **write path** — a single
/// fetch-then-insert chokepoint in the repository — and reads are written to tolerate a
/// duplicate deterministically rather than to assume one cannot exist. See
/// `WorkoutRepository`.
public struct StoredWorkout: Hashable, Sendable {
    public var workoutUUID: UUID
    public var activityTypeRawValue: String
    public var start: Date
    public var end: Date
    public var durationSeconds: Double
    public var distanceMeters: Double?
    public var activeEnergyKilocalories: Double?
    public var hasRoute: Bool
    public var sourceRawValue: String
    public var ingestedAt: Date

    public init(
        workoutUUID: UUID,
        activityTypeRawValue: String,
        start: Date,
        end: Date,
        durationSeconds: Double,
        distanceMeters: Double?,
        activeEnergyKilocalories: Double?,
        hasRoute: Bool,
        sourceRawValue: String,
        ingestedAt: Date
    ) {
        self.workoutUUID = workoutUUID
        self.activityTypeRawValue = activityTypeRawValue
        self.start = start
        self.end = end
        self.durationSeconds = durationSeconds
        self.distanceMeters = distanceMeters
        self.activeEnergyKilocalories = activeEnergyKilocalories
        self.hasRoute = hasRoute
        self.sourceRawValue = sourceRawValue
        self.ingestedAt = ingestedAt
    }

    public init(_ workout: Workout) {
        self.init(
            workoutUUID: workout.id,
            activityTypeRawValue: workout.activityType.rawValue,
            start: workout.start,
            end: workout.end,
            durationSeconds: workout.durationSeconds,
            distanceMeters: workout.distanceMeters,
            activeEnergyKilocalories: workout.activeEnergyKilocalories,
            hasRoute: workout.hasRoute,
            sourceRawValue: workout.source.rawValue,
            ingestedAt: workout.ingestedAt
        )
    }

    /// - Note: `ActivityType` and `WorkoutSource` are open string wrappers by design, so
    ///   an unrecognised raw value round-trips intact rather than failing to load. A
    ///   HealthKit activity type added after this build shipped must still read back as
    ///   the workout the athlete actually did.
    public func toDomain() throws -> Workout {
        try Workout(
            id: workoutUUID,
            activityType: ActivityType(rawValue: activityTypeRawValue),
            start: start,
            end: end,
            durationSeconds: durationSeconds,
            distanceMeters: distanceMeters,
            activeEnergyKilocalories: activeEnergyKilocalories,
            hasRoute: hasRoute,
            source: WorkoutSource(rawValue: sourceRawValue),
            ingestedAt: ingestedAt
        )
    }
}

/// `HeartRateSeries` as stored (PRD §8 `hr_series`, D7).
///
/// The samples are a JSON blob, which is D7 verbatim: "blob, not normalized rows". A
/// row per sample would be a few thousand records for one long run, and the only
/// consumers — the detail-view curve, time-above-cap, drift, and the cross-run overlay
/// (D5) — all read the entire curve.
///
/// Only the samples go in the blob; `workoutUUID` is a column because it is the key
/// every read is by. Storing it in both places would create two answers to "whose curve
/// is this" that a bad write could make disagree.
public struct StoredHeartRateSeries: Hashable, Sendable {
    public var workoutUUID: UUID

    /// A JSON-encoded `[HeartRateSample]`.
    ///
    /// The app layer marks the corresponding property `@Attribute(.externalStorage)`,
    /// for a CloudKit reason as much as a local one — see `MaximizeSchemaV1`.
    public var samplesJSON: Data

    public init(workoutUUID: UUID, samplesJSON: Data) {
        self.workoutUUID = workoutUUID
        self.samplesJSON = samplesJSON
    }

    public init(_ series: HeartRateSeries) throws {
        let samplesJSON = try PersistencePayload.encode(
            series.samples,
            field: "StoredHeartRateSeries.samplesJSON"
        )
        self.init(workoutUUID: series.workoutID, samplesJSON: samplesJSON)
    }

    public func toDomain() throws -> HeartRateSeries {
        let samples = try PersistencePayload.decode(
            [HeartRateSample].self,
            from: samplesJSON,
            field: "StoredHeartRateSeries.samplesJSON"
        )
        // The strict-ordering initializer, not the `sorting:` one. Samples were sorted
        // when they were ingested, so an unsorted blob means the bytes are wrong, and
        // silently repairing them here would hide that while producing a curve whose
        // drift number is a plausible-looking lie.
        return try HeartRateSeries(workoutID: workoutUUID, samples: samples)
    }
}

/// `Route` as stored (PRD §8 `route`).
///
/// Absent, not empty, for an indoor run (FR-0.6) — there is simply no record. The
/// domain forbids an empty `Route`, so "a row with zero points" is not a state this
/// schema can reach.
public struct StoredRoute: Hashable, Sendable {
    public var workoutUUID: UUID

    /// A JSON-encoded `[RoutePoint]`.
    public var pointsJSON: Data

    public init(workoutUUID: UUID, pointsJSON: Data) {
        self.workoutUUID = workoutUUID
        self.pointsJSON = pointsJSON
    }

    public init(_ route: Route) throws {
        let pointsJSON = try PersistencePayload.encode(
            route.points,
            field: "StoredRoute.pointsJSON"
        )
        self.init(workoutUUID: route.workoutID, pointsJSON: pointsJSON)
    }

    public func toDomain() throws -> Route {
        let points = try PersistencePayload.decode(
            [RoutePoint].self,
            from: pointsJSON,
            field: "StoredRoute.pointsJSON"
        )
        return try Route(workoutID: workoutUUID, points: points)
    }
}

/// `DerivedMetrics` as stored (PRD §8 `derived_metrics`, D2).
///
/// D2's "computed once at ingestion and stored" is the reason this is a record at all
/// rather than something a view recalculates. Each metric is a column so a future
/// dashboard query can filter on one without decoding a blob; `zoneSplits` and
/// `distanceSplits` are small nested values nothing queries into, so they stay JSON.
///
/// `planVersionNumber` is stored beside the numbers because, without it, "time above
/// cap" is a measurement with no stated cap — and a later plan version would silently
/// reinterpret it (D1).
public struct StoredDerivedMetrics: Hashable, Sendable {
    public var workoutUUID: UUID
    public var averageHeartRateBPM: Double?
    public var maximumHeartRateBPM: Double?
    public var timeAboveCapSeconds: Double?
    public var heartRateDriftFraction: Double?
    public var averageCadenceStepsPerMinute: Double?
    public var gradeAdjustedPaceSecondsPerKilometer: Double?

    /// A JSON-encoded `ZoneSplits`.
    public var zoneSplitsJSON: Data

    /// A JSON-encoded `DistanceSplits` (MAX-046), or **nil when this run has no pace
    /// breakdown** — an indoor run, a route that could not be cut up, or a workout whose
    /// metrics were computed before this column existed.
    ///
    /// Optional rather than a defaulted empty blob for two reasons that happen to agree.
    /// The domain reason: `DerivedMetrics.distanceSplits` is itself optional, and "absent"
    /// and "empty" are different facts (MAX-010) — `DistanceSplits` cannot hold zero
    /// series. The schema reason: an optional attribute is the one shape a store already
    /// holding rows can gain without a value to backfill, and CloudKit accepts it as-is
    /// (its rule is that a *non*-optional attribute must have a default).
    ///
    /// A blob rather than columns, matching `zoneSplitsJSON`: nothing filters, sorts or
    /// groups by a split, and a row per split would be a dozen records per run to serve a
    /// query nobody intends to make (the same reasoning D7 applies to the HR series).
    public var distanceSplitsJSON: Data?
    public var planVersionNumber: Int

    public init(
        workoutUUID: UUID,
        averageHeartRateBPM: Double?,
        maximumHeartRateBPM: Double?,
        timeAboveCapSeconds: Double?,
        heartRateDriftFraction: Double?,
        averageCadenceStepsPerMinute: Double?,
        gradeAdjustedPaceSecondsPerKilometer: Double?,
        zoneSplitsJSON: Data,
        distanceSplitsJSON: Data?,
        planVersionNumber: Int
    ) {
        self.workoutUUID = workoutUUID
        self.averageHeartRateBPM = averageHeartRateBPM
        self.maximumHeartRateBPM = maximumHeartRateBPM
        self.timeAboveCapSeconds = timeAboveCapSeconds
        self.heartRateDriftFraction = heartRateDriftFraction
        self.averageCadenceStepsPerMinute = averageCadenceStepsPerMinute
        self.gradeAdjustedPaceSecondsPerKilometer = gradeAdjustedPaceSecondsPerKilometer
        self.zoneSplitsJSON = zoneSplitsJSON
        self.distanceSplitsJSON = distanceSplitsJSON
        self.planVersionNumber = planVersionNumber
    }

    public init(_ metrics: DerivedMetrics) throws {
        let zoneSplitsJSON = try PersistencePayload.encode(
            metrics.zoneSplits,
            field: "StoredDerivedMetrics.zoneSplitsJSON"
        )
        let distanceSplitsJSON = try metrics.distanceSplits.map {
            try PersistencePayload.encode($0, field: "StoredDerivedMetrics.distanceSplitsJSON")
        }
        self.init(
            workoutUUID: metrics.workoutID,
            averageHeartRateBPM: metrics.averageHeartRateBPM,
            maximumHeartRateBPM: metrics.maximumHeartRateBPM,
            timeAboveCapSeconds: metrics.timeAboveCapSeconds,
            heartRateDriftFraction: metrics.heartRateDriftFraction,
            averageCadenceStepsPerMinute: metrics.averageCadenceStepsPerMinute,
            gradeAdjustedPaceSecondsPerKilometer: metrics.gradeAdjustedPaceSecondsPerKilometer,
            zoneSplitsJSON: zoneSplitsJSON,
            distanceSplitsJSON: distanceSplitsJSON,
            planVersionNumber: metrics.planVersion.number
        )
    }

    public func toDomain() throws -> DerivedMetrics {
        try DerivedMetrics(
            workoutID: workoutUUID,
            averageHeartRateBPM: averageHeartRateBPM,
            maximumHeartRateBPM: maximumHeartRateBPM,
            timeAboveCapSeconds: timeAboveCapSeconds,
            heartRateDriftFraction: heartRateDriftFraction,
            averageCadenceStepsPerMinute: averageCadenceStepsPerMinute,
            gradeAdjustedPaceSecondsPerKilometer: gradeAdjustedPaceSecondsPerKilometer,
            zoneSplits: try PersistencePayload.decode(
                ZoneSplits.self,
                from: zoneSplitsJSON,
                field: "StoredDerivedMetrics.zoneSplitsJSON"
            ),
            distanceSplits: try distanceSplitsJSON.map {
                try PersistencePayload.decode(
                    DistanceSplits.self,
                    from: $0,
                    field: "StoredDerivedMetrics.distanceSplitsJSON"
                )
            },
            planVersion: try PlanVersion(planVersionNumber)
        )
    }
}
