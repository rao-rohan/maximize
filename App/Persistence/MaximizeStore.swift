import Foundation
import MaximizeCore
import SwiftData

/// The app's implementation of the core's repository protocols.
///
/// One actor rather than six, because the repositories share a `ModelContext` and a
/// context is not safe to touch from two isolation domains. `@ModelActor` gives the
/// actor its own context bound to the container, which is what makes a background
/// HealthKit wake and the foreground UI able to read and write without stepping on each
/// other.
///
/// ## What is in this file and what deliberately is not
///
/// Everything here is fetch, insert, update, delete, and translation through the
/// `Stored*` types. There is no validation, no unit arithmetic, no date computation and
/// no business rule — those live in `MaximizeCore` where CI runs them. The rules this
/// file *does* enforce are the two that are inherently about who is allowed to write:
///
/// - **Dedupe (FR-0.5)**, because CloudKit cannot express it as a constraint.
/// - **D8's immutable auto-score**, because no stored record can make itself immutable.
///
/// Both are single-chokepoint rules rather than schema constraints, and both are marked
/// where they happen.
///
/// **None of this file has ever executed.** CI compiles it and runs nothing: there is no
/// simulator or device in the pipeline (tracker R2), and `swift test` covers
/// `MaximizeCore` only. The mapping it depends on *is* tested — see
/// `StoredRecordRoundTripTests` — which is why the mapping lives there and not here.
@ModelActor
actor MaximizeStore {

    // MARK: - Shared fetches

    /// Records matching a workout identifier, oldest ingestion first.
    ///
    /// Returns an array rather than a single record because uniqueness is not
    /// enforceable in a CloudKit-mirrored store (see `MaximizeSchema`). Ordering by
    /// `ingestedAt` makes the choice of "which one" deterministic, so two reads can
    /// never disagree — the practical requirement, given a duplicate should be
    /// unreachable locally and is merely improbable across devices.
    private func workoutRecords(for identifier: UUID) throws -> [WorkoutRecord] {
        try modelContext.fetch(
            FetchDescriptor<WorkoutRecord>(
                predicate: #Predicate<WorkoutRecord> { $0.workoutUUID == identifier },
                sortBy: [SortDescriptor<WorkoutRecord>(\.ingestedAt, order: .forward)]
            )
        )
    }
}

// MARK: - Workouts

extension MaximizeStore: WorkoutRepository {

    func workout(id: UUID) async throws -> Workout? {
        try workoutRecords(for: id).first?.stored.toDomain()
    }

    func containsWorkout(id: UUID) async throws -> Bool {
        let descriptor = FetchDescriptor<WorkoutRecord>(
            predicate: #Predicate<WorkoutRecord> { $0.workoutUUID == id }
        )
        return try modelContext.fetchCount(descriptor) > 0
    }

    func workouts(startingIn interval: DateInterval) async throws -> [Workout] {
        let lowerBound = interval.start
        let upperBound = interval.end
        let records = try modelContext.fetch(
            FetchDescriptor<WorkoutRecord>(
                // Half-open, per the protocol's contract: `<` on the upper bound, not
                // `<=`. Closed would put a run starting exactly on an interval boundary
                // into both adjacent intervals.
                predicate: #Predicate<WorkoutRecord> {
                    $0.start >= lowerBound && $0.start < upperBound
                },
                sortBy: [SortDescriptor<WorkoutRecord>(\.start, order: .forward)]
            )
        )
        return try records.map { try $0.stored.toDomain() }
    }

    /// The dedupe chokepoint (FR-0.5).
    ///
    /// Looking the workout up before inserting is what stands in for the
    /// `@Attribute(.unique)` CloudKit will not accept. Being the *only* write path for a
    /// workout is what makes that sufficient — an insert made anywhere else would defeat
    /// it silently.
    ///
    /// If storage somehow already holds more than one record for this identifier, the
    /// oldest is updated and the others are left untouched rather than deleted. Reads
    /// resolve to that same oldest record, so the duplicate is invisible; deleting it
    /// here would be a reconciliation racing whichever device created it, which is
    /// MAX-021's problem to reason about with sync actually switched on.
    func store(_ workout: Workout) async throws {
        let stored = StoredWorkout(workout)
        if let existing = try workoutRecords(for: workout.id).first {
            existing.stored = stored
        } else {
            modelContext.insert(WorkoutRecord(stored))
        }
        try modelContext.save()
    }

    /// Deletes the workout and everything hanging off it.
    ///
    /// The switch is exhaustive over `WorkoutAttachedRecord` on purpose: there are no
    /// SwiftData relationships in this schema to cascade for us, so a ticket that adds a
    /// per-workout record type has to add a case here, and the compiler is what tells
    /// them. The bug this prevents — an orphaned heart-rate blob that is never read and
    /// syncs to iCloud forever — has no symptom that would ever surface on its own.
    func deleteWorkout(id: UUID) async throws {
        for attachment in WorkoutAttachedRecord.allCases {
            switch attachment {
            case .heartRateSeries:
                try modelContext.delete(
                    model: HeartRateSeriesRecord.self,
                    where: #Predicate<HeartRateSeriesRecord> { $0.workoutUUID == id }
                )
            case .route:
                try modelContext.delete(
                    model: RouteRecord.self,
                    where: #Predicate<RouteRecord> { $0.workoutUUID == id }
                )
            case .derivedMetrics:
                try modelContext.delete(
                    model: DerivedMetricsRecord.self,
                    where: #Predicate<DerivedMetricsRecord> { $0.workoutUUID == id }
                )
            case .automaticScore:
                try modelContext.delete(
                    model: ScoreRecord.self,
                    where: #Predicate<ScoreRecord> { $0.workoutUUID == id }
                )
            case .scoreAnnotations:
                try modelContext.delete(
                    model: ScoreAnnotationRecord.self,
                    where: #Predicate<ScoreAnnotationRecord> { $0.workoutUUID == id }
                )
            case .chatThread:
                try modelContext.delete(
                    model: ChatThreadRecord.self,
                    where: #Predicate<ChatThreadRecord> { $0.workoutUUID == id }
                )
            }
        }
        try modelContext.delete(
            model: WorkoutRecord.self,
            where: #Predicate<WorkoutRecord> { $0.workoutUUID == id }
        )
        try modelContext.save()
    }

    func heartRateSeries(forWorkout id: UUID) async throws -> HeartRateSeries? {
        try heartRateSeriesRecord(for: id)?.stored.toDomain()
    }

    func store(_ series: HeartRateSeries) async throws {
        let stored = try StoredHeartRateSeries(series)
        if let existing = try heartRateSeriesRecord(for: series.workoutID) {
            existing.stored = stored
        } else {
            modelContext.insert(HeartRateSeriesRecord(stored))
        }
        try modelContext.save()
    }

    func route(forWorkout id: UUID) async throws -> Route? {
        try routeRecord(for: id)?.stored.toDomain()
    }

    func store(_ route: Route) async throws {
        let stored = try StoredRoute(route)
        if let existing = try routeRecord(for: route.workoutID) {
            existing.stored = stored
        } else {
            modelContext.insert(RouteRecord(stored))
        }
        try modelContext.save()
    }

    func derivedMetrics(forWorkout id: UUID) async throws -> DerivedMetrics? {
        try derivedMetricsRecord(for: id)?.stored.toDomain()
    }

    func store(_ metrics: DerivedMetrics) async throws {
        let stored = try StoredDerivedMetrics(metrics)
        if let existing = try derivedMetricsRecord(for: metrics.workoutID) {
            existing.stored = stored
        } else {
            modelContext.insert(DerivedMetricsRecord(stored))
        }
        try modelContext.save()
    }

    private func heartRateSeriesRecord(for identifier: UUID) throws -> HeartRateSeriesRecord? {
        var descriptor = FetchDescriptor<HeartRateSeriesRecord>(
            predicate: #Predicate<HeartRateSeriesRecord> { $0.workoutUUID == identifier }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func routeRecord(for identifier: UUID) throws -> RouteRecord? {
        var descriptor = FetchDescriptor<RouteRecord>(
            predicate: #Predicate<RouteRecord> { $0.workoutUUID == identifier }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func derivedMetricsRecord(for identifier: UUID) throws -> DerivedMetricsRecord? {
        var descriptor = FetchDescriptor<DerivedMetricsRecord>(
            predicate: #Predicate<DerivedMetricsRecord> { $0.workoutUUID == identifier }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
}

// MARK: - Scores (D8)

extension MaximizeStore: ScoreRepository {

    /// D8's enforcement point.
    ///
    /// A stored record cannot make itself immutable — every SwiftData property is
    /// settable — so immutability has to be a property of the only door into it. There is
    /// deliberately no update path here and no `replaceAutomaticScore`: the divergence
    /// between the auto-score and a manual correction *is* the scorer-quality metric of
    /// PRD §2, and an overwrite destroys exactly the telemetry the project wants.
    func recordAutomaticScore(_ score: Score) async throws {
        guard try scoreRecord(for: score.workoutID) == nil else {
            throw PersistenceError.automaticScoreAlreadyRecorded
        }
        modelContext.insert(ScoreRecord(try StoredScore(score)))
        try modelContext.save()
    }

    func ledger(forWorkout id: UUID) async throws -> ScoreLedger? {
        guard let record = try scoreRecord(for: id) else { return nil }
        let annotations = try annotationRecords(for: id).map { try $0.stored.toDomain() }
        return try ScoreLedger(
            automatic: try record.stored.toDomain(),
            annotations: annotations
        )
    }

    /// Additive by construction: a new record, keyed by its own identifier. Nothing here
    /// can reach the auto-score.
    func annotate(_ annotation: ScoreAnnotation) async throws {
        modelContext.insert(ScoreAnnotationRecord(StoredScoreAnnotation(annotation)))
        try modelContext.save()
    }

    private func scoreRecord(for identifier: UUID) throws -> ScoreRecord? {
        var descriptor = FetchDescriptor<ScoreRecord>(
            predicate: #Predicate<ScoreRecord> { $0.workoutUUID == identifier }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    /// Ascending by `createdAt`, which is the order `ScoreLedger` requires — the last
    /// annotation is the correction in force.
    private func annotationRecords(for identifier: UUID) throws -> [ScoreAnnotationRecord] {
        try modelContext.fetch(
            FetchDescriptor<ScoreAnnotationRecord>(
                predicate: #Predicate<ScoreAnnotationRecord> { $0.workoutUUID == identifier },
                sortBy: [SortDescriptor<ScoreAnnotationRecord>(\.createdAt, order: .forward)]
            )
        )
    }
}

// MARK: - Plans (D1)

extension MaximizeStore: PlanRepository {

    func planCalendar() async throws -> PlanCalendar? {
        let records = try planRecords()
        guard !records.isEmpty else { return nil }
        return try PlanCalendar(records.map { try $0.stored.toDomain() })
    }

    /// Validates the resulting version set *before* writing any of it.
    ///
    /// `PlanCalendar.init` holds the rules that protect already-scored history: a later
    /// `effectiveFrom` must carry a higher `version`, and no two versions may start on
    /// the same day. Constructing the calendar that this write would produce, and letting
    /// it throw, rejects a history-rewriting plan while it is still just an argument.
    /// Writing first and discovering the problem on the next load would leave the store
    /// in a state where *every* read throws — with no way to author a plan that fixes it.
    func store(_ plan: Plan) async throws {
        let stored = try StoredPlan(plan)
        let existing = try planRecords()

        var resulting: [Plan] = []
        for record in existing where record.versionNumber != stored.versionNumber {
            resulting.append(try record.stored.toDomain())
        }
        resulting.append(plan)
        _ = try PlanCalendar(resulting)

        if let match = existing.first(where: { $0.versionNumber == stored.versionNumber }) {
            match.stored = stored
        } else {
            modelContext.insert(PlanRecord(stored))
        }
        try modelContext.save()
    }

    /// Ordered by the stored `YYYY-MM-DD` string, which sorts chronologically because the
    /// format is fixed-width and zero-padded. No date parsing, no time zone.
    private func planRecords() throws -> [PlanRecord] {
        try modelContext.fetch(
            FetchDescriptor<PlanRecord>(
                sortBy: [SortDescriptor<PlanRecord>(\.effectiveFromISO8601, order: .forward)]
            )
        )
    }
}

// MARK: - Chat threads (D6, A11)

/// **The only part of this ticket that reaches outside `MaximizeCore`, and it is here
/// under protest.** MAX-092 is a core ticket; the stored record is MAX-093's. But
/// `ChatThreadRepository` grew, and this type conforms to it, so leaving the file alone
/// would have failed the `ios-app` CI job — a knowingly red merge gate, which CLAUDE.md
/// does not permit. What is below is therefore the *minimum* that compiles: no new
/// column, no schema version, no migration, and no attempt at the training subject.
/// MAX-093 replaces the derivations marked below with stored fields.
extension MaximizeStore: ChatThreadRepository {

    /// Rows for §2.3's list, newest activity first.
    ///
    /// `lastActivityAt` and the subject are both derived from what the record already
    /// holds (see `StoredChatThread`) — every existing thread has a workout subject, per
    /// A11's "no migration". MAX-093 makes them columns.
    func threadSummaries() async throws -> [ChatThreadSummary] {
        var summaries: [ChatThreadSummary] = []
        for record in try modelContext.fetch(FetchDescriptor<ChatThreadRecord>()) {
            let thread = try record.stored.toDomain()
            let facts = try workoutFacts(for: thread.subject)
            summaries.append(ChatThreadSummary(thread, workoutFacts: facts))
        }
        return ChatThreadSummary.sortedByActivity(summaries)
    }

    func thread(id: UUID) async throws -> ChatThread? {
        try threadRecord(id: id)?.stored.toDomain()
    }

    /// Deterministic per MAX-048, which this does not move: `threadRecords(for:)`'s
    /// `(createdAt, threadUUID)` order still decides which of two duplicate rows for one
    /// workout wins, and it is still the *oldest* that does. With one thread per workout
    /// that choice is only ever visible for a CloudKit-race duplicate, so re-picking it
    /// here would change a decision MAX-048 made deliberately for no reason.
    ///
    /// Nil for a training subject because no record can hold one yet — a correct answer
    /// today, and MAX-093's to widen.
    func mostRecentThread(for subject: ChatSubject) async throws -> ChatThread? {
        guard let workoutID = subject.workoutID else { return nil }
        return try threadRecords(for: workoutID).first?.stored.toDomain()
    }

    /// The upsert chokepoint (D6), matching `store(_ workout:)`'s shape.
    ///
    /// `createdAt` is preserved across an update, never reset to "now": its only job is
    /// breaking a tie between duplicate rows deterministically (MAX-048), and
    /// resetting it on every edit would make that tie float with whichever replica
    /// wrote last — the opposite of the point. It is set once, on a record's first
    /// insert here, and carried forward unchanged after that.
    ///
    /// Still keyed on the workout rather than the thread's own id: that is what keeps
    /// "one thread per workout" true (§12, question 3) with no unique constraint to
    /// lean on. A training thread throws out of `StoredChatThread`'s initializer.
    func store(_ thread: ChatThread) async throws {
        let existing = try thread.subject.workoutID.flatMap { try threadRecords(for: $0).first }
        let stored = try StoredChatThread(thread, createdAt: existing?.stored.createdAt ?? Date())
        if let existing {
            existing.stored = stored
        } else {
            modelContext.insert(ChatThreadRecord(stored))
        }
        try modelContext.save()
    }

    func deleteThread(id: UUID) async throws {
        try modelContext.delete(
            model: ChatThreadRecord.self,
            where: #Predicate<ChatThreadRecord> { $0.threadUUID == id }
        )
        try modelContext.save()
    }

    /// The run a workout thread's title names (§2.4).
    ///
    /// `TimeZone.current` matches `WorkoutDetailModel`'s own default and its reasoning:
    /// the day a run belongs to is the day the athlete was in when they started it, and
    /// the device's zone is the app's only account of that.
    private func workoutFacts(for subject: ChatSubject) throws -> WorkoutThreadFacts? {
        guard let workoutID = subject.workoutID else { return nil }
        guard let record = try workoutRecords(for: workoutID).first else { return nil }
        let workout = try record.stored.toDomain()
        let day = try workout.calendarDay(in: TimeZone.current)
        return WorkoutThreadFacts(day: day, activityType: workout.activityType)
    }

    private func threadRecord(id: UUID) throws -> ChatThreadRecord? {
        var descriptor = FetchDescriptor<ChatThreadRecord>(
            predicate: #Predicate<ChatThreadRecord> { $0.threadUUID == id }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    /// Records matching a workout identifier, oldest `createdAt` first, `threadUUID`
    /// breaking a tie.
    ///
    /// Mirrors `workoutRecords(for:)`: CloudKit cannot enforce "one thread per
    /// workout" (see `MaximizeSchema`'s CloudKit notes), so a sync race between two
    /// devices can leave two `ChatThreadRecord`s for the same workout, and fetching
    /// without a sort left "which one does `.first` return" undefined — this makes it
    /// explicit and total instead.
    ///
    /// The `threadUUID` tiebreak is not a theoretical nicety: every record written
    /// before `createdAt` existed loads with the same default
    /// (`.distantPast`, see `MaximizeSchemaV1.ChatThreadRecord`), so a store holding two
    /// pre-migration duplicates ties on the primary key and needs the secondary one to
    /// stay deterministic. `UUID` has conformed to `Comparable` since iOS 17
    /// (this app's floor is iOS 26), so the ordering is well-defined even then.
    private func threadRecords(for identifier: UUID) throws -> [ChatThreadRecord] {
        try modelContext.fetch(
            FetchDescriptor<ChatThreadRecord>(
                predicate: #Predicate<ChatThreadRecord> { $0.workoutUUID == identifier },
                sortBy: [
                    SortDescriptor<ChatThreadRecord>(\.createdAt, order: .forward),
                    SortDescriptor<ChatThreadRecord>(\.threadUUID, order: .forward),
                ]
            )
        )
    }
}

// MARK: - Rest-day overrides (D9, A6)

extension MaximizeStore: RestDayOverrideRepository {

    /// Filtered in Swift rather than in a predicate.
    ///
    /// The whole table is at most one row per day, and D9's budget makes it far sparser
    /// than that — a few dozen rows a year. Fetching them and comparing `CalendarDay`
    /// values keeps the range comparison in the type that defines what a day *is*,
    /// instead of restating it as a string comparison in a predicate where an off-by-one
    /// at a month boundary would be invisible.
    func overrides(from start: CalendarDay, through end: CalendarDay) async throws -> [RestDayOverride] {
        try allOverrideRecords()
            .map { try $0.stored.toDomain() }
            .filter { $0.date >= start && $0.date <= end }
            .sorted { $0.date < $1.date }
    }

    func override(on day: CalendarDay) async throws -> RestDayOverride? {
        try overrideRecord(on: day)?.stored.toDomain()
    }

    func store(_ override: RestDayOverride) async throws {
        let stored = StoredRestDayOverride(override)
        if let existing = try overrideRecord(on: override.date) {
            existing.stored = stored
        } else {
            modelContext.insert(RestDayOverrideRecord(stored))
        }
        try modelContext.save()
    }

    func removeOverride(on day: CalendarDay) async throws {
        let key = day.description
        try modelContext.delete(
            model: RestDayOverrideRecord.self,
            where: #Predicate<RestDayOverrideRecord> { $0.dayISO8601 == key }
        )
        try modelContext.save()
    }

    private func allOverrideRecords() throws -> [RestDayOverrideRecord] {
        try modelContext.fetch(FetchDescriptor<RestDayOverrideRecord>())
    }

    private func overrideRecord(on day: CalendarDay) throws -> RestDayOverrideRecord? {
        let key = day.description
        var descriptor = FetchDescriptor<RestDayOverrideRecord>(
            predicate: #Predicate<RestDayOverrideRecord> { $0.dayISO8601 == key }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
}

// MARK: - Settings

extension MaximizeStore: SettingsRepository {

    /// `AppSettings.standard` when nothing has been written yet. Every caller wants an
    /// answer to "what are the settings", and the domain's defaults are the answer before
    /// the user has expressed a preference.
    func settings() async throws -> AppSettings {
        guard let record = try settingsRecord() else { return .standard }
        return try record.stored.toDomain()
    }

    func store(_ settings: AppSettings) async throws {
        let stored = StoredAppSettings(settings)
        if let record = try settingsRecord() {
            record.stored = stored
        } else {
            modelContext.insert(AppSettingsRecord(stored))
        }
        try modelContext.save()
    }

    /// The singleton rule. SwiftData cannot express "at most one row" and CloudKit could
    /// not enforce it if it could, so "the settings" means the first record and writes go
    /// back to that same one.
    private func settingsRecord() throws -> AppSettingsRecord? {
        var descriptor = FetchDescriptor<AppSettingsRecord>()
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
}
