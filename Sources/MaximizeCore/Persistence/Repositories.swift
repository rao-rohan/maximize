import Foundation

/// Failures that belong to storage rather than to a domain invariant.
///
/// Deliberately payload-free. `IngestionDiagnostic` already establishes the rule these
/// follow: an error can end up in a log, and CLAUDE.md rules health data out of logs
/// entirely — including workout identifiers, which are exactly what a naive
/// `case alreadyExists(id: UUID)` would carry into one.
public enum PersistenceError: Error, Hashable, Sendable, CustomStringConvertible {
    /// A second automatic score was offered for a workout that already has one (D8).
    ///
    /// This is a programming error, not a user-facing condition: the correct way to
    /// disagree with a score is a `ScoreAnnotation`.
    case automaticScoreAlreadyRecorded

    public var description: String {
        switch self {
        case .automaticScoreAlreadyRecorded:
            return "An automatic score already exists for this workout; corrections are additive (D8)"
        }
    }
}

/// The record kinds that belong to a workout and must not outlive it.
///
/// This exists to make orphaning a compile error rather than a slow leak. Deleting a
/// workout has to delete everything hanging off it, and there are no SwiftData
/// relationships in this schema to cascade for us (see `MaximizeSchemaV1` for why —
/// CloudKit requires every relationship to be optional, so a relationship could not
/// enforce the link anyway). The implementation switches over this enum exhaustively,
/// so a ticket that adds a new per-workout record type cannot compile without deciding
/// what deletion does to it.
///
/// The failure this prevents is quiet and permanent: an orphaned heart-rate blob in a
/// CloudKit-mirrored store is invisible, is never read, and syncs forever.
public enum WorkoutAttachedRecord: String, Hashable, Sendable, CaseIterable {
    case heartRateSeries
    case route
    case derivedMetrics
    case automaticScore
    case scoreAnnotations
    case chatThread
}

/// Reading and writing workouts and everything captured with them (PRD §8).
///
/// ## Dedupe is this protocol's job, because the schema cannot do it
///
/// FR-0.5 dedupes on `workoutUUID`. SwiftData's `@Attribute(.unique)` would express
/// that in the schema, and it is unavailable: CloudKit "is unable to enforce" it
/// (Apple, *Syncing model data across a person's devices*), and Core Data's CloudKit
/// model rules state flatly that "unique constraints aren't supported". Since A1 makes
/// CloudKit the backup and MAX-021 turns it on, the constraint is off the table.
///
/// So uniqueness is a **write-path invariant** instead:
///
/// - `store(_:)` is an upsert. It looks the workout up first and updates in place
///   rather than inserting a second record. Being the single write chokepoint is what
///   makes that sufficient locally.
/// - Reads **tolerate** a duplicate rather than assuming it cannot happen, and resolve
///   it deterministically (see `workout(id:)`). Locally a duplicate should be
///   unreachable; across CloudKit it is merely improbable, and "improbable" is not a
///   thing to write an app around. Two devices ingesting the same HealthKit workout
///   before either has synced is the concrete path, and it is not exotic — it is what
///   happens the first time the athlete sets up a second device.
public protocol WorkoutRepository: Sendable {
    /// The workout with this identifier, or nil.
    ///
    /// If storage somehow holds more than one record for the identifier, this returns
    /// one of them by a deterministic rule rather than failing or picking arbitrarily,
    /// so that two reads never disagree. See the implementation for the rule.
    func workout(id: UUID) async throws -> Workout?

    /// Whether a workout with this identifier has been stored — the `hasIngestedWorkout`
    /// half of FR-0.5's dedupe pair.
    func containsWorkout(id: UUID) async throws -> Bool

    /// Workouts that *started* within the interval, ascending by start.
    ///
    /// Start, not end: a workout belongs to the day it was begun, which is how a person
    /// describes it and how `Workout.calendarDay(in:)` resolves it.
    ///
    /// **Half-open: `start <= workout.start < end`.** This deliberately contradicts
    /// `DateInterval`, whose own `contains(_:)` is closed at both bounds — the type is a
    /// convenient pair of instants here, not a statement about membership. Closed would
    /// double-count: `TrendInterval.dateInterval(in:)` ends one interval at the same
    /// instant the next begins, so a run starting exactly at midnight would land in both
    /// the week that just ended and the week beginning, and every tally spanning that
    /// boundary would disagree with itself by one workout.
    func workouts(startingIn interval: DateInterval) async throws -> [Workout]

    /// Inserts the workout, or updates the existing record with the same identifier.
    /// Idempotent, per `WorkoutIngestionSink`'s contract.
    func store(_ workout: Workout) async throws

    /// Deletes the workout and every record listed in `WorkoutAttachedRecord`.
    ///
    /// A no-op for an identifier that was never stored — the health store can
    /// re-deliver a deletion, and the first fetch after a lost anchor can report the
    /// deletion of something this app never saw.
    func deleteWorkout(id: UUID) async throws

    func heartRateSeries(forWorkout id: UUID) async throws -> HeartRateSeries?
    func store(_ series: HeartRateSeries) async throws

    /// Nil for an indoor run, which is a first-class state and not a defect (FR-0.6).
    func route(forWorkout id: UUID) async throws -> Route?
    func store(_ route: Route) async throws

    func derivedMetrics(forWorkout id: UUID) async throws -> DerivedMetrics?
    func store(_ metrics: DerivedMetrics) async throws
}

/// The auto-score and the corrections layered on it (PRD §8, D8).
public protocol ScoreRepository: Sendable {
    /// Writes the immutable auto-score.
    ///
    /// - Throws: `PersistenceError.automaticScoreAlreadyRecorded` if one already
    ///   exists. This is the enforcement point for D8 — a stored record cannot make
    ///   itself immutable, so the only door into it refuses to overwrite. Collapsing
    ///   the auto-score into a correction would destroy the divergence signal that
    ///   PRD §2 names as the scorer-quality metric.
    func recordAutomaticScore(_ score: Score) async throws

    /// The auto-score together with its corrections, or nil if the workout is unscored.
    func ledger(forWorkout id: UUID) async throws -> ScoreLedger?

    /// Adds a correction. Additive: it cannot touch the auto-score.
    func annotate(_ annotation: ScoreAnnotation) async throws
}

/// Every plan version, as the resolvable calendar (D1).
public protocol PlanRepository: Sendable {
    /// All stored versions, assembled into a `PlanCalendar`.
    ///
    /// Nil when no plan has been authored yet — a real state on a fresh install, and
    /// distinct from "the plan prescribes nothing", which `PlanCalendar` cannot express
    /// because it rejects an empty version set.
    func planCalendar() async throws -> PlanCalendar?

    /// Stores a new plan version.
    ///
    /// The ordering invariants that protect already-scored history live in
    /// `PlanCalendar.init` (a later `effectiveFrom` must carry a higher `version`).
    /// Implementations validate a candidate by constructing a calendar including it, so
    /// a version that would rewrite the past is rejected before it reaches disk rather
    /// than after it has poisoned every subsequent load.
    func store(_ plan: Plan) async throws
}

/// Conversations, keyed on their own identifier and carrying a subject (A11, FR-2.3).
///
/// ## What MAX-092 changed, and what it deliberately did not
///
/// Until A11 this protocol had two methods and thread identity was the workout, so
/// "which thread" was never a question. Now it is, and the protocol grew the four
/// operations a thread list needs: enumerate, fetch one, resolve a subject to one, and
/// delete one.
///
/// **MAX-048's determinism survives, generalised.** MAX-048 fixed a real bug: the store
/// fetched a workout's thread with no sort, so two records left by a CloudKit sync race
/// resolved to whichever row came back first, and the thread the athlete saw depended on
/// fetch order. Its fix was an explicit `(createdAt, threadUUID)` ordering. That
/// reasoning is not weakened by keying on the thread's own id — it is *promoted*, from a
/// tiebreak between records that should not both exist into `mostRecentThread(for:)`'s
/// ordering rule, which is now load-bearing for a subject that legitimately has several
/// threads. The difference worth noting: MAX-048's rule lives in `MaximizeStore`, which
/// CI compiles and never runs; this one is a protocol contract that
/// `FakeChatThreadRepository` implements and `ChatThreadRepositoryTests` exercises on
/// every commit.
public protocol ChatThreadRepository: Sendable {

    /// Every stored thread as a list row, **newest activity first** (§2.3).
    ///
    /// Summaries rather than threads: a list of twenty conversations does not need
    /// twenty transcripts decoded to render twenty single lines, and health data should
    /// not be in memory for a screen that shows none of it.
    ///
    /// Ordering is the implementation's obligation, not the caller's, because it is the
    /// one thing that has to be total — `ChatThreadSummary.sortedByActivity(_:)` is the
    /// shared rule, tiebreak included.
    func threadSummaries() async throws -> [ChatThreadSummary]

    /// The thread with this identifier, or nil.
    func thread(id: UUID) async throws -> ChatThread?

    /// The most recently active thread with this subject, or nil.
    ///
    /// This is "which thread opens" (§2.2): tapping Ask on a workout screen lands in
    /// that run's conversation, and tapping it on the dashboard lands in the newest
    /// thread for the interval on screen — never in whatever was open last regardless of
    /// subject.
    ///
    /// **Must be deterministic**: newest `lastActivityAt`, `id` breaking a tie. See this
    /// protocol's note on MAX-048 for why an unordered answer is a bug rather than a
    /// tidiness question.
    func mostRecentThread(for subject: ChatSubject) async throws -> ChatThread?

    /// Inserts or replaces the thread, keyed on its own `id`. Threads are written whole
    /// — `ChatThread` is a value that grows by returning a new thread, not by mutation.
    ///
    /// **One thread per workout is a policy this method keeps, not a shape the type
    /// forbids** (§12, question 3). An implementation upserts a workout-subject thread
    /// onto the existing one for that workout; if the owner ever wants several, that is
    /// a change here and not a migration.
    func store(_ thread: ChatThread) async throws

    /// Deletes the thread with this identifier — §2.3's swipe.
    ///
    /// A no-op for an identifier that was never stored, matching
    /// `WorkoutRepository.deleteWorkout(id:)`: a row deleted on another device and again
    /// here is an ordinary race, not a failure.
    func deleteThread(id: UUID) async throws
}

extension ChatThreadRepository {

    /// Create-or-fetch: the thread the Ask button opens for a subject (§2.2).
    ///
    /// **"Create" means minted, not written.** A new thread is returned unstored, and
    /// reaches disk only when a completed turn is appended and `store(_:)` is called —
    /// the rule MAX-050 already follows ("only completed turns are persisted"). Writing
    /// on open would fill §2.3's list with empty threads from every stray tap of a
    /// button that is, after this pivot, on every screen.
    ///
    /// - Parameters:
    ///   - newThreadID: used only if nothing exists yet. Passed in rather than minted
    ///     here so a test can pin it, matching how `now` is injected everywhere else in
    ///     this package.
    ///   - instant: `lastActivityAt` for a thread with nothing in it yet, so a
    ///     just-opened conversation sorts to the top of the list before the athlete has
    ///     typed anything.
    public func thread(
        for subject: ChatSubject,
        newThreadID: UUID,
        at instant: Date
    ) async throws -> ChatThread {
        if let existing = try await mostRecentThread(for: subject) {
            return existing
        }
        return try ChatThread(id: newThreadID, subject: subject, lastActivityAt: instant)
    }
}

/// Missed-day → rest conversions against the weekly budget (D9, A6).
public protocol RestDayOverrideRepository: Sendable {
    func overrides(from start: CalendarDay, through end: CalendarDay) async throws -> [RestDayOverride]
    func override(on day: CalendarDay) async throws -> RestDayOverride?

    /// Inserts or replaces the override for its day. One per day: the day is the key.
    func store(_ override: RestDayOverride) async throws
    func removeOverride(on day: CalendarDay) async throws
}

/// The single settings record (PRD §8 `settings`).
public protocol SettingsRepository: Sendable {
    /// The stored settings, or `AppSettings.standard` if none has been written yet.
    ///
    /// Total rather than optional: every caller of "what are the settings" wants an
    /// answer, and the defaults on `AppSettings` are the answer before the user has
    /// expressed a preference.
    func settings() async throws -> AppSettings
    func store(_ settings: AppSettings) async throws
}
