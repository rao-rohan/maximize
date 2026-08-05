import Foundation
import MaximizeCore

/// An in-memory stand-in for `MaximizeStore` (MAX-020), covering the three repositories
/// the ingestion pipeline writes through.
///
/// One type rather than three for the same reason `MaximizeStore` is one actor: the
/// pipeline's behaviour is about the *combination* of what is stored — a workout with
/// metrics but no score is the state MAX-041 renders — and splitting it across three
/// fakes would make every assertion reach into three places.
///
/// The two rules the real store enforces at the write path are enforced here too, because
/// the pipeline's correctness depends on them and a fake that was more permissive would
/// let a broken pipeline pass:
///
/// - **Dedupe (FR-0.5)** — `store(_ workout:)` is an upsert keyed on `workoutUUID`.
/// - **D8** — `recordAutomaticScore` refuses a second automatic score.
///
/// `SettingsRepository` joined the list for MAX-096, for the same "one type rather than
/// several" reason: a training chat thread's roll-up is a function of the *combination*
/// of stored workouts, scores, the plan **and** the rest-day budget, and a test asserting
/// that a bubble and a dashboard tile agree should not have to wire four fakes together
/// to say so.
public final class InMemoryWorkoutStore: WorkoutRepository, ScoreRepository, PlanRepository,
                                         SettingsRepository, @unchecked Sendable {

    /// A failure the store can be told to raise, distinct from `DomainError` so a test
    /// can drive both sides of the pipeline's permanent/transient split.
    public enum Failure: Error, Hashable, Sendable {
        case storageUnavailable
    }

    private let lock = NSLock()

    private var workoutsByID: [UUID: Workout] = [:]
    private var workoutStoreOrder: [UUID] = []
    private var seriesByID: [UUID: HeartRateSeries] = [:]
    private var routesByID: [UUID: Route] = [:]
    private var metricsByID: [UUID: DerivedMetrics] = [:]
    private var scoresByID: [UUID: Score] = [:]
    private var annotationsByID: [UUID: [ScoreAnnotation]] = [:]
    private var labelsByID: [UUID: [MiscategorisedScoreLabel]] = [:]
    private var calendar: PlanCalendar?
    private var appSettings: AppSettings = .standard

    private var workoutStoreError: Error?
    private var workoutStoreErrorsByID: [UUID: Error] = [:]
    private var curveStoreError: Error?
    private var metricsStoreError: Error?
    private var scoreStoreError: Error?
    private var planReadError: Error?
    private var deleteError: Error?
    private var workoutStoredHook: (@Sendable (Workout) -> Void)?
    private var workoutWrites = 0
    private var planWrites = 0

    public init(planCalendar: PlanCalendar? = nil) {
        self.calendar = planCalendar
    }

    // MARK: - Inspection

    public var storedWorkouts: [Workout] {
        lock.locked { workoutStoreOrder.compactMap { workoutsByID[$0] } }
    }

    /// Every write of a workout, counting upserts — so "a replay ingested once" is an
    /// assertion about this and not about the set of identifiers.
    public var workoutWriteCount: Int { lock.locked { workoutWrites } }

    /// Every call to `store(_ plan:)`, so a test can assert D1's door stayed shut
    /// (MAX-101, A13). Counting writes rather than comparing calendars is the assertion
    /// that actually holds: a proposal restating the plan already in force would store an
    /// identical-looking version and leave the calendar looking untouched.
    public var planWriteCount: Int { lock.locked { planWrites } }

    // Named `all*` rather than `stored*` so none of them shares a base name with the
    // per-workout accessors below.
    public var allMetrics: [DerivedMetrics] { lock.locked { Array(metricsByID.values) } }
    public var allSeries: [HeartRateSeries] { lock.locked { Array(seriesByID.values) } }
    public var allRoutes: [Route] { lock.locked { Array(routesByID.values) } }
    public var allScores: [Score] { lock.locked { Array(scoresByID.values) } }

    public func storedMetrics(forWorkout id: UUID) -> DerivedMetrics? {
        lock.locked { metricsByID[id] }
    }

    public func storedScore(forWorkout id: UUID) -> Score? {
        lock.locked { scoresByID[id] }
    }

    // MARK: - Failure injection

    public func failWorkoutStores(with error: Error) {
        lock.locked { workoutStoreError = error }
    }

    /// Fails the write for one workout only, so a test can plant a poison pill in a batch
    /// and watch what happens to the workouts behind it (R11).
    public func failWorkoutStore(of id: UUID, with error: Error) {
        lock.locked { workoutStoreErrorsByID[id] = error }
    }

    /// Fails both curve writes — the heart-rate series and the route.
    public func failCurveStores(with error: Error) {
        lock.locked { curveStoreError = error }
    }

    public func failMetricStores(with error: Error) {
        lock.locked { metricsStoreError = error }
    }

    public func failScoreStores(with error: Error) {
        lock.locked { scoreStoreError = error }
    }

    public func failPlanReads(with error: Error) {
        lock.locked { planReadError = error }
    }

    public func failDeletes(with error: Error) {
        lock.locked { deleteError = error }
    }

    public func stopFailing() {
        lock.locked {
            workoutStoreError = nil
            workoutStoreErrorsByID = [:]
            curveStoreError = nil
            metricsStoreError = nil
            scoreStoreError = nil
            planReadError = nil
            deleteError = nil
        }
    }

    /// Runs inside `store(_ workout:)`, after the workout has landed — the vantage point
    /// from which a test can check what is durable at a given moment (C2).
    public func onWorkoutStored(_ hook: @escaping @Sendable (Workout) -> Void) {
        lock.locked { workoutStoredHook = hook }
    }

    public func setPlanCalendar(_ planCalendar: PlanCalendar?) {
        lock.locked { calendar = planCalendar }
    }

    /// Seeds a score without going through `recordAutomaticScore`, so a test can set up
    /// the already-scored replay case without asserting on how it got there.
    public func seedScore(_ score: Score) {
        lock.locked { scoresByID[score.workoutID] = score }
    }

    // MARK: - WorkoutRepository

    public func workout(id: UUID) async throws -> Workout? {
        lock.locked { workoutsByID[id] }
    }

    public func containsWorkout(id: UUID) async throws -> Bool {
        lock.locked { workoutsByID[id] != nil }
    }

    public func workouts(startingIn interval: DateInterval) async throws -> [Workout] {
        lock.locked {
            workoutsByID.values
                .filter { $0.start >= interval.start && $0.start <= interval.end }
                .sorted { $0.start < $1.start }
        }
    }

    public func store(_ workout: Workout) async throws {
        let hook = try lock.locked { () -> (@Sendable (Workout) -> Void)? in
            if let specific = workoutStoreErrorsByID[workout.id] { throw specific }
            if let workoutStoreError { throw workoutStoreError }
            if workoutsByID[workout.id] == nil {
                workoutStoreOrder.append(workout.id)
            }
            workoutsByID[workout.id] = workout
            workoutWrites += 1
            return workoutStoredHook
        }
        hook?(workout)
    }

    public func deleteWorkout(id: UUID) async throws {
        try lock.locked {
            if let deleteError { throw deleteError }
            workoutsByID[id] = nil
            workoutStoreOrder.removeAll { $0 == id }
            seriesByID[id] = nil
            routesByID[id] = nil
            metricsByID[id] = nil
            scoresByID[id] = nil
            annotationsByID[id] = nil
        }
    }

    public func heartRateSeries(forWorkout id: UUID) async throws -> HeartRateSeries? {
        lock.locked { seriesByID[id] }
    }

    public func store(_ series: HeartRateSeries) async throws {
        try lock.locked {
            if let curveStoreError { throw curveStoreError }
            seriesByID[series.workoutID] = series
        }
    }

    public func route(forWorkout id: UUID) async throws -> Route? {
        lock.locked { routesByID[id] }
    }

    public func store(_ route: Route) async throws {
        try lock.locked {
            if let curveStoreError { throw curveStoreError }
            routesByID[route.workoutID] = route
        }
    }

    public func derivedMetrics(forWorkout id: UUID) async throws -> DerivedMetrics? {
        lock.locked { metricsByID[id] }
    }

    public func store(_ metrics: DerivedMetrics) async throws {
        try lock.locked {
            if let metricsStoreError { throw metricsStoreError }
            metricsByID[metrics.workoutID] = metrics
        }
    }

    // MARK: - ScoreRepository

    /// D8's enforcement point, mirrored from `MaximizeStore`.
    public func recordAutomaticScore(_ score: Score) async throws {
        try lock.locked {
            if let scoreStoreError { throw scoreStoreError }
            guard scoresByID[score.workoutID] == nil else {
                throw PersistenceError.automaticScoreAlreadyRecorded
            }
            scoresByID[score.workoutID] = score
        }
    }

    /// The whole ledger, labels included — `ScoreRepository`'s contract, and the half a
    /// fake is most tempting to skip: a ledger returned without its labels puts every
    /// miscategorised lift back into the scorer-quality metric (A21, MAX-143).
    public func ledger(forWorkout id: UUID) async throws -> ScoreLedger? {
        let parts = lock.locked { () -> (Score, [ScoreAnnotation], [MiscategorisedScoreLabel])? in
            guard let score = scoresByID[id] else { return nil }
            return (score, annotationsByID[id] ?? [], labelsByID[id] ?? [])
        }
        guard let parts else { return nil }
        return try ScoreLedger(automatic: parts.0, annotations: parts.1, labels: parts.2)
    }

    public func annotate(_ annotation: ScoreAnnotation) async throws {
        lock.locked {
            annotationsByID[annotation.workoutID, default: []].append(annotation)
        }
    }

    /// Additive, exactly as the real store is: an append, with no path to the score.
    public func recordMiscategorisationLabel(_ label: MiscategorisedScoreLabel) async throws {
        lock.locked {
            labelsByID[label.workoutID, default: []].append(label)
        }
    }

    /// Every label written, so a test can assert on what a pass did without reading it
    /// back through a ledger.
    public var allMiscategorisationLabels: [MiscategorisedScoreLabel] {
        lock.locked { labelsByID.values.flatMap { $0 } }
    }

    // MARK: - PlanRepository

    public func planCalendar() async throws -> PlanCalendar? {
        try lock.locked {
            if let planReadError { throw planReadError }
            return calendar
        }
    }

    public func store(_ plan: Plan) async throws {
        var versions = lock.locked { calendar?.versions ?? [] }
        versions.removeAll { $0.version == plan.version }
        versions.append(plan)
        let updated = try PlanCalendar(versions)
        lock.locked {
            calendar = updated
            planWrites += 1
        }
    }

    // MARK: - SettingsRepository

    /// Total, like the real store's: the answer to "what are the settings" before the
    /// athlete has expressed a preference is `AppSettings.standard`, not nil.
    public func settings() async throws -> AppSettings {
        lock.locked { appSettings }
    }

    public func store(_ settings: AppSettings) async throws {
        lock.locked { appSettings = settings }
    }
}

/// A scripted `ScoringModelInvoking`.
///
/// The transport itself is MAX-023's, and this deliberately imitates only the shape of
/// it: a reply, or a failure, or a call that takes longer than the caller is willing to
/// wait. Those are the three things the pipeline branches on.
public final class FakeScoringModel: ScoringModelInvoking, @unchecked Sendable {
    private let lock = NSLock()
    private var queuedReplies: [String] = []
    private var standingReply = FakeScoringModel.acceptableReply(score: 92)
    private var error: Error?
    private var delaySeconds: TimeInterval?
    private var instructions: [ScoringInstruction] = []
    private var callHook: (@Sendable () -> Void)?

    public init() {}

    /// A reply that `WorkoutScorer` accepts, for a band that permits `score`.
    public static func acceptableReply(score: Int, rationale: String = "Held the cap throughout.") -> String {
        "{\"score\": \(score), \"rationale\": \"\(rationale)\"}"
    }

    public var receivedInstructions: [ScoringInstruction] {
        lock.locked { instructions }
    }

    public var callCount: Int { receivedInstructions.count }

    /// Replies handed out one per call, in order, before falling back to the standing
    /// reply. Lets a test drive "rejected once, then accepted".
    public func enqueueReplies(_ replies: String...) {
        lock.locked { queuedReplies.append(contentsOf: replies) }
    }

    public func setReply(_ reply: String) {
        lock.locked { standingReply = reply }
    }

    /// Every call throws this — a missing API key, or no network.
    public func failAllCalls(with error: Error) {
        lock.locked { self.error = error }
    }

    /// Stops failing, so a test can show that a workout left unscored by a missing key is
    /// scored once the key arrives.
    public func stopFailing() {
        lock.locked { error = nil }
    }

    /// Every call sleeps this long first. Cancellable, so a test that races it against a
    /// budget finishes as soon as the budget does.
    public func setDelaySeconds(_ seconds: TimeInterval?) {
        lock.locked { delaySeconds = seconds }
    }

    /// Runs at the top of every call, before the reply is produced.
    public func onCall(_ hook: @escaping @Sendable () -> Void) {
        lock.locked { callHook = hook }
    }

    public func reply(to instruction: ScoringInstruction) async throws -> String {
        typealias Call = (Error?, TimeInterval?, String, (@Sendable () -> Void)?)
        let (error, delay, reply, hook) = lock.locked { () -> Call in
            instructions.append(instruction)
            let next = queuedReplies.isEmpty ? standingReply : queuedReplies.removeFirst()
            return (self.error, delaySeconds, next, callHook)
        }

        hook?()
        if let delay {
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
        if let error { throw error }
        return reply
    }
}

/// Collects `IngestionPipelineDiagnostic`s reported while a workout is ingested.
public final class IngestionPipelineDiagnosticRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [IngestionPipelineDiagnostic] = []

    public init() {}

    public var reported: [IngestionPipelineDiagnostic] {
        lock.locked { events }
    }

    public func handler() -> @Sendable (IngestionPipelineDiagnostic) -> Void {
        { [self] event in
            lock.locked { events.append(event) }
        }
    }
}

private extension NSLock {
    func locked<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
