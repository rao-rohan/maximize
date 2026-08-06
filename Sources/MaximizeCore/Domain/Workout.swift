import Foundation

/// The kind of activity a workout was, as reported by the capture source.
///
/// Deliberately an open string wrapper rather than a closed `enum`: HealthKit has
/// dozens of activity types and gains more each release, and an unknown one must
/// degrade to "some other activity" rather than fail to decode a run the user
/// actually did. The cases we reason about are named constants.
public struct ActivityType: RawRepresentable, Hashable, Sendable, Codable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let running = ActivityType(rawValue: "running")
    /// Indoor / treadmill running. First-class, not a degraded run: it simply has no
    /// route (FR-0.6).
    public static let treadmillRunning = ActivityType(rawValue: "treadmillRunning")
    public static let walking = ActivityType(rawValue: "walking")
    public static let hiking = ActivityType(rawValue: "hiking")
    public static let cycling = ActivityType(rawValue: "cycling")
    public static let traditionalStrengthTraining = ActivityType(rawValue: "traditionalStrengthTraining")
    public static let other = ActivityType(rawValue: "other")

    /// Which of the plan's two prescriptions a workout of this type is judged against
    /// (A17). Total by construction: every activity type, named or not, maps to exactly
    /// one, because `PlanDay` has to be able to resolve an ask for either slot.
    ///
    /// **The one place this mapping lives.** `Discipline`'s own documentation explains
    /// why `.run` is the residual: a ride, a hike and a walk occupy the run slot as
    /// `.other` sessions, which is what they are today, and A17 is explicit that they
    /// are not disciplines of their own.
    ///
    /// Only `.traditionalStrengthTraining` is a lift so far. HealthKit's
    /// `.functionalStrengthTraining` is not mapped to an `ActivityType` at all yet — it
    /// arrives as `.other` — so naming it here would be a case nothing can produce; the
    /// ticket that maps it in `HealthKitWorkoutFetcher` adds it here in the same change.
    public var discipline: Discipline {
        switch self {
        case .traditionalStrengthTraining: return .lift
        default: return .run
        }
    }

    /// Whether this type is one the plan's rubric scores as a run. Strength work is
    /// explicitly out of scope for HR scoring (PRD §3 non-goals, narrowed by A16).
    ///
    /// **Narrower than `discipline == .run`, and that gap is the whole relationship
    /// between the two.** `discipline` says which slot's ask a workout is measured
    /// against; this says which activities the run rubric's bands — written about
    /// distance, cadence and an easy-run heart-rate cap — actually describe. A ride is
    /// `.run` by slot and `false` here, so neither predicate is a rename of the other
    /// and collapsing them would score a bike ride as a bad easy run.
    ///
    /// The guard is what stops them disagreeing rather than merely happening to agree:
    /// nothing that is a lift can reach the comparison below, whatever activity types
    /// are named later. It is redundant today by inspection, and `DisciplineTests` pins
    /// the implication over every named type so it stays that way.
    public var isRun: Bool {
        guard discipline == .run else { return false }
        return self == .running || self == .treadmillRunning
    }

    /// Whether a plan's rubric can describe a workout of this type **at all** (MAX-168).
    ///
    /// The successor to `isRun` at the four places that used it to answer "will a score
    /// ever be reached for this?" — the ingestion gate, the verdict header, the calendar
    /// cell and chat's load state. Until MAX-168 those four asked `isRun` and the answer
    /// was right, because the rubric's only vocabulary was running vocabulary. MAX-131
    /// gave it `.actualDiscipline` and `.scheduledDuration`, MAX-132 wrote lift bands with
    /// them, and MAX-133 routes a lift to its own slot's ask — so a lift is now something
    /// a plan can judge, and the old predicate would have those four surfaces telling the
    /// athlete a verdict is never coming for a session that is being scored.
    ///
    /// **A ride, a hike and a walk are still `false` here, and permanently.** They occupy
    /// the run slot by A17 without being runs, the run bands are written about a distance
    /// and an easy-run heart-rate cap that describe none of them, and `Discipline` is
    /// closed at two cases — so no band naming them can be written, and there is no
    /// authoring screen that could write one. Their absent score really is settled.
    ///
    /// **Type-level, and therefore not the whole gate.** This says the *vocabulary*
    /// exists; whether a particular workout is scored also depends on the plan version in
    /// effect on its day (whether the day asked for a lift, and whether its rubric carries
    /// the bands that judge one) and, for a lift, on the athlete having said what it
    /// worked (A22). Those are facts about a plan and a record, not about an activity
    /// type, and `WorkoutIngestionPipeline.applyScore` is where they are asked.
    public var isScoreable: Bool { isRun || discipline == .lift }

    /// Whether the activity is expected to carry a GPS route. Indoor runs answering
    /// `false` here is the point of FR-0.6.
    public var isOutdoorByNature: Bool {
        self == .running || self == .walking || self == .hiking || self == .cycling
    }

    public var description: String { rawValue }

    /// The athlete-facing name — "Treadmill running", not `treadmillRunning`.
    ///
    /// In the core because a chat thread's title is derived here (§2.4, MAX-092) and a
    /// title is stored data's shadow: it must read the same on every launch and be
    /// assertable in a unit test. An unrecognised type degrades to its capitalised raw
    /// value for the same reason this is a string wrapper and not an `enum` — HealthKit
    /// gains activity types every release, and one we have never heard of must still
    /// print something a person can read.
    ///
    /// `App/Workouts/WorkoutDisplayFormatting.describe(_:)` predates this and produces
    /// the same strings. Collapsing it onto this property belongs to whichever ticket
    /// next opens that file; it is not this one's, and the wording is pinned by a test
    /// here so the two cannot drift silently in the meantime.
    public var displayName: String {
        switch self {
        case .running: return "Running"
        case .treadmillRunning: return "Treadmill running"
        case .walking: return "Walking"
        case .hiking: return "Hiking"
        case .cycling: return "Cycling"
        case .traditionalStrengthTraining: return "Strength training"
        default: return rawValue.capitalized
        }
    }

    // Written out rather than left to the RawRepresentable/Codable default so the
    // encoded form is unambiguously a bare string.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(rawValue: try container.decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// Where a workout came from. Recorded for provenance; the app never writes to
/// HealthKit (PRD §3), so every workout originates outside it.
public struct WorkoutSource: RawRepresentable, Hashable, Sendable, Codable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let appleWatch = WorkoutSource(rawValue: "appleWatch")
    public static let iPhone = WorkoutSource(rawValue: "iPhone")
    public static let unknown = WorkoutSource(rawValue: "unknown")

    public var description: String { rawValue }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(rawValue: try container.decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// A completed workout as captured from the health store (PRD §8 `workout`).
///
/// This is the raw record only. Everything computed from it lives in
/// `DerivedMetrics`, which is calculated once at ingestion and stored (D2) — never
/// recomputed here at display time.
public struct Workout: Hashable, Sendable, Codable, Identifiable {
    /// HealthKit's workout UUID. It is the primary key and the dedupe key for
    /// idempotent ingestion (FR-0.5, A2).
    public let id: UUID
    public let activityType: ActivityType
    public let start: Date
    public let end: Date

    /// Active duration in seconds. Stored separately from `end - start` on purpose:
    /// a paused workout has a wall-clock span longer than its duration, and the
    /// metrics care about the latter.
    public let durationSeconds: Double

    /// Total distance in **meters**. Nil for activities that do not measure distance.
    /// Meters is the storage unit everywhere in the core; miles/kilometers are a
    /// display concern (`AppSettings.distanceUnit`).
    public let distanceMeters: Double?

    /// Active energy burned in **kilocalories** (the "calories" a fitness app shows).
    public let activeEnergyKilocalories: Double?

    /// Whether the capture source recorded a GPS route for this workout. Kept as a
    /// stored flag rather than derived from a `Route` value because ingestion learns
    /// it before it fetches the route, and an indoor run legitimately has none.
    public let hasRoute: Bool

    public let source: WorkoutSource

    /// When this record entered the local store. Distinct from `end`: HealthKit sync
    /// and background-delivery throttling can put minutes or hours between them
    /// (PRD §13).
    public let ingestedAt: Date

    public init(
        id: UUID,
        activityType: ActivityType,
        start: Date,
        end: Date,
        durationSeconds: Double,
        distanceMeters: Double? = nil,
        activeEnergyKilocalories: Double? = nil,
        hasRoute: Bool,
        source: WorkoutSource,
        ingestedAt: Date
    ) throws {
        guard end >= start else {
            throw DomainError.inconsistent(reason: "Workout.end must not precede Workout.start")
        }
        try Validate.nonNegative(durationSeconds, "Workout.durationSeconds")
        // A tolerance, not a rounding fudge: HealthKit's duration and its
        // start/end stamps are recorded independently and disagree by fractions of a
        // second on real workouts. A duration meaningfully longer than the elapsed
        // span, though, means the two fields describe different workouts.
        let elapsed = end.timeIntervalSince(start)
        guard durationSeconds <= elapsed + 1 else {
            throw DomainError.inconsistent(
                reason: "Workout.durationSeconds (\(durationSeconds)) exceeds elapsed time (\(elapsed))"
            )
        }
        try Validate.optionalNonNegative(distanceMeters, "Workout.distanceMeters")
        try Validate.optionalNonNegative(activeEnergyKilocalories, "Workout.activeEnergyKilocalories")

        self.id = id
        self.activityType = activityType
        self.start = start
        self.end = end
        self.durationSeconds = durationSeconds
        self.distanceMeters = distanceMeters
        self.activeEnergyKilocalories = activeEnergyKilocalories
        self.hasRoute = hasRoute
        self.source = source
        self.ingestedAt = ingestedAt
    }

    /// Wall-clock span in seconds, including any paused time.
    public var elapsedSeconds: Double {
        end.timeIntervalSince(start)
    }

    /// The calendar day this workout is scored against, in the given time zone. The
    /// *start* is what anchors it: a run beginning at 23:50 belongs to the day it was
    /// started, which is how a person describes it.
    public func calendarDay(in timeZone: TimeZone) throws -> CalendarDay {
        try CalendarDay(start, in: timeZone)
    }

    private enum CodingKeys: String, CodingKey {
        case id, activityType, start, end, durationSeconds, distanceMeters
        case activeEnergyKilocalories, hasRoute, source, ingestedAt
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: container.decode(UUID.self, forKey: .id),
            activityType: container.decode(ActivityType.self, forKey: .activityType),
            start: container.decode(Date.self, forKey: .start),
            end: container.decode(Date.self, forKey: .end),
            durationSeconds: container.decode(Double.self, forKey: .durationSeconds),
            distanceMeters: container.decodeIfPresent(Double.self, forKey: .distanceMeters),
            activeEnergyKilocalories: container.decodeIfPresent(Double.self, forKey: .activeEnergyKilocalories),
            hasRoute: container.decode(Bool.self, forKey: .hasRoute),
            source: container.decode(WorkoutSource.self, forKey: .source),
            ingestedAt: container.decode(Date.self, forKey: .ingestedAt)
        )
    }
}
