import Foundation
import XCTest
@testable import MaximizeCore

/// Round-trips every domain type through its stored representation and back.
///
/// This suite is the whole automated gate on MAX-020. CI has no simulator and no
/// device, so it never runs SwiftData (tracker R2) — but the stored records are pure
/// Swift, and the mapping between them and the domain is where every decision lives.
/// What is left in `App/Persistence` is a field-for-field copy into an `@Model` class
/// with no branches in it.
///
/// `XCTAssertEqual` on the reconstructed value is the real assertion. Every domain type
/// here is `Hashable` with value semantics, so equality compares every field — which
/// makes "I dropped a property in the mapping" a test failure rather than a number that
/// quietly reads as nil on a detail screen.
final class StoredRecordRoundTripTests: XCTestCase {

    // MARK: - Workout

    func testWorkoutRoundTripsUnchanged() throws {
        let workout = try Fixture.workout()
        XCTAssertEqual(try StoredWorkout(workout).toDomain(), workout)
    }

    /// The optional fields are the ones a mapping typo silently drops, because a nil
    /// reads as "this run had no distance" rather than as an error.
    func testWorkoutRoundTripsWithOptionalFieldsAbsent() throws {
        let workout = try Workout(
            id: Fixture.workoutID,
            activityType: .treadmillRunning,
            start: Fixture.epoch,
            end: Fixture.epoch.addingTimeInterval(1_800),
            durationSeconds: 1_800,
            distanceMeters: nil,
            activeEnergyKilocalories: nil,
            hasRoute: false,
            source: .iPhone,
            ingestedAt: Fixture.epoch
        )
        let restored = try StoredWorkout(workout).toDomain()
        XCTAssertEqual(restored, workout)
        XCTAssertNil(restored.distanceMeters)
        XCTAssertNil(restored.activeEnergyKilocalories)
        XCTAssertFalse(restored.hasRoute)
    }

    /// FR-0.6: an indoor run is a first-class workout, not a degraded one. It differs
    /// from an outdoor run only in carrying no route.
    func testTreadmillWorkoutRoundTripsAsAFirstClassRun() throws {
        let workout = try Fixture.workout(activityType: .treadmillRunning, hasRoute: false)
        let restored = try StoredWorkout(workout).toDomain()
        XCTAssertEqual(restored, workout)
        XCTAssertTrue(restored.activityType.isRun)
        XCTAssertFalse(restored.hasRoute)
    }

    /// `ActivityType` is an open string wrapper precisely so a HealthKit type added
    /// after this build shipped still decodes. Storage must not narrow that.
    func testUnknownActivityTypeSurvivesStorage() throws {
        let exotic = ActivityType(rawValue: "underwaterBasketWeaving")
        let workout = try Fixture.workout(activityType: exotic)
        XCTAssertEqual(try StoredWorkout(workout).toDomain().activityType, exotic)
    }

    /// Reconstruction goes through the validating initializer, so a record corrupted on
    /// disk — or merged badly by CloudKit — is rejected at the boundary rather than
    /// flowing into the scorer as a plausible-looking wrong number.
    func testCorruptedStoredWorkoutIsRejectedRatherThanLoaded() throws {
        var stored = StoredWorkout(try Fixture.workout())
        stored.end = stored.start.addingTimeInterval(-60)
        assertThrows(.inconsistent, try stored.toDomain())
    }

    func testStoredWorkoutWithNegativeDurationIsRejected() throws {
        var stored = StoredWorkout(try Fixture.workout())
        stored.durationSeconds = -1
        assertThrows(.outOfRange, try stored.toDomain())
    }

    // MARK: - Heart-rate series (D7)

    func testHeartRateSeriesRoundTripsUnchanged() throws {
        let series = try HeartRateSeries(
            workoutID: Fixture.workoutID,
            samples: Fixture.samples([(0, 120), (30, 135), (60, 141.5), (90, 149)])
        )
        XCTAssertEqual(try StoredHeartRateSeries(series).toDomain(), series)
    }

    /// The drift overlay (D5) reads whole curves, so a long one is the realistic case
    /// rather than an edge case. This also pins that the blob survives at a size where
    /// `.externalStorage` is in play on device.
    func testLongHeartRateSeriesRoundTripsExactly() throws {
        let samples = try Fixture.samples(
            (0..<3_600).map { (Double($0), 120 + Double($0 % 40)) }
        )
        let series = try HeartRateSeries(workoutID: Fixture.workoutID, samples: samples)
        let restored = try StoredHeartRateSeries(series).toDomain()
        XCTAssertEqual(restored, series)
        XCTAssertEqual(restored.count, 3_600)
    }

    /// Fractional bpm and offsets must survive bit-for-bit: `.deferredToDate` and JSON's
    /// double representation are exact here, and a lossy round-trip would move a drift
    /// number without anything reporting it.
    func testFractionalHeartRateValuesSurviveExactly() throws {
        let series = try HeartRateSeries(
            workoutID: Fixture.workoutID,
            samples: Fixture.samples([(0.5, 120.25), (1.75, 141.125)])
        )
        let restored = try StoredHeartRateSeries(series).toDomain()
        XCTAssertEqual(restored.samples[0].beatsPerMinute, 120.25)
        XCTAssertEqual(restored.samples[1].offsetSeconds, 1.75)
        XCTAssertEqual(restored, series)
    }

    /// Silently sorting on the way back in would hide a corrupted blob while producing
    /// a curve whose drift number is wrong but plausible. Loud is correct here.
    func testOutOfOrderSamplesInStorageAreRejectedNotRepaired() throws {
        let unordered = try Fixture.samples([(60, 140), (30, 130)])
        let stored = StoredHeartRateSeries(
            workoutUUID: Fixture.workoutID,
            samplesJSON: try PersistencePayload.encode(unordered, field: "test")
        )
        assertThrows(.outOfOrder, try stored.toDomain())
    }

    func testUndecodableHeartRateBlobIsReportedWithoutLeakingItsContents() throws {
        let stored = StoredHeartRateSeries(
            workoutUUID: Fixture.workoutID,
            samplesJSON: Data("not json".utf8)
        )
        assertThrows(.malformed, try stored.toDomain())

        // CLAUDE.md: health data must not reach logs. The error names the field and
        // nothing else, so it stays safe to log wherever it surfaces.
        do {
            _ = try stored.toDomain()
            XCTFail("Expected a malformed error")
        } catch let error as DomainError {
            XCTAssertFalse("\(error)".contains("not json"))
        }
    }

    // MARK: - Route

    func testRouteRoundTripsUnchanged() throws {
        let route = try Route(workoutID: Fixture.workoutID, points: [
            RoutePoint(
                offsetSeconds: 0,
                latitudeDegrees: 51.5007,
                longitudeDegrees: -0.1246,
                altitudeMeters: 11.5,
                speedMetersPerSecond: 3.2
            ),
            RoutePoint(
                offsetSeconds: 10,
                latitudeDegrees: 51.5010,
                longitudeDegrees: -0.1250,
                altitudeMeters: nil,
                speedMetersPerSecond: nil
            ),
        ])
        let restored = try StoredRoute(route).toDomain()
        XCTAssertEqual(restored, route)
        // The absent altitude is the load-bearing part: §9 makes grade-adjusted pace a
        // conditional metric, and storing a missing altitude as sea level would turn
        // "we cannot know the grade" into a confident wrong number.
        XCTAssertNil(restored.points[1].altitudeMeters)
        XCTAssertFalse(restored.hasUsableAltitude)
    }

    func testHighPrecisionCoordinatesSurviveExactly() throws {
        let latitude = 51.500729123456
        let longitude = -0.124625987654
        let route = try Route(workoutID: Fixture.workoutID, points: [
            RoutePoint(offsetSeconds: 0, latitudeDegrees: latitude, longitudeDegrees: longitude),
        ])
        let restored = try StoredRoute(route).toDomain()
        XCTAssertEqual(restored.points[0].latitudeDegrees, latitude)
        XCTAssertEqual(restored.points[0].longitudeDegrees, longitude)
    }

    // MARK: - Derived metrics (D2)

    func testDerivedMetricsRoundTripUnchanged() throws {
        let metrics = try DerivedMetrics(
            workoutID: Fixture.workoutID,
            averageHeartRateBPM: 148.5,
            maximumHeartRateBPM: 162,
            timeAboveCapSeconds: 214.5,
            heartRateDriftFraction: 0.043,
            averageCadenceStepsPerMinute: 167.2,
            gradeAdjustedPaceSecondsPerKilometer: 312.4,
            zoneSplits: ZoneSplits(splits: [
                ZoneSplits.Split(zone: .two, seconds: 1_200),
                ZoneSplits.Split(zone: .three, seconds: 900.5),
            ]),
            distanceSplits: DistanceSplits(series: [
                DistanceSplitSeries(
                    unit: .kilometers,
                    splits: [
                        DistanceSplit(ordinal: 1, distanceMeters: 1_000, elapsedSeconds: 312.4, isComplete: true),
                        DistanceSplit(ordinal: 2, distanceMeters: 420, elapsedSeconds: 131.2, isComplete: false),
                    ]
                ),
            ]),
            planVersion: PlanVersion(3)
        )
        XCTAssertEqual(try StoredDerivedMetrics(metrics).toDomain(), metrics)
    }

    /// MAX-046. Absent, not empty: a run with no pace breakdown stores a **nil** blob, not
    /// an empty one. `DistanceSplits` cannot hold zero series, so an empty blob would not
    /// decode — which is exactly why the column is optional rather than defaulted.
    ///
    /// This is also what every workout ingested before MAX-046 reads back as: the column
    /// did not exist when they were written, so it is NULL for them, and the detail screen
    /// says "no splits recorded for this run" rather than inventing a breakdown.
    func testDerivedMetricsWithNoDistanceSplitsStoreANilBlob() throws {
        let metrics = try DerivedMetrics(workoutID: Fixture.workoutID, planVersion: PlanVersion(1))
        let stored = try StoredDerivedMetrics(metrics)

        XCTAssertNil(stored.distanceSplitsJSON)
        XCTAssertNil(try stored.toDomain().distanceSplits)
    }

    /// The trailing partial split survives storage as a partial split. Losing the flag
    /// would turn a 420 m remainder into a kilometre the athlete never ran.
    func testDistanceSplitCompletenessSurvivesStorage() throws {
        let metrics = try DerivedMetrics(
            workoutID: Fixture.workoutID,
            distanceSplits: DistanceSplits(series: [
                DistanceSplitSeries(
                    unit: .miles,
                    splits: [
                        DistanceSplit(ordinal: 1, distanceMeters: 1_609.344, elapsedSeconds: 500, isComplete: true),
                        DistanceSplit(ordinal: 2, distanceMeters: 300, elapsedSeconds: 93, isComplete: false),
                    ]
                ),
            ]),
            planVersion: PlanVersion(1)
        )

        let restored = try XCTUnwrap(try StoredDerivedMetrics(metrics).toDomain().distanceSplits)
        let miles = try XCTUnwrap(restored.series(in: .miles))
        XCTAssertEqual(miles.splits.map(\.isComplete), [true, false])
        XCTAssertEqual(miles.splits.last?.distanceMeters, 300)
    }

    /// Optionality is meaningful throughout `DerivedMetrics`: an indoor run has no
    /// grade-adjusted pace, and drift on an interval session is left nil rather than
    /// computed and ignored. A mapping that turned any of those into a zero would be a
    /// lie the UI could not detect.
    func testAbsentDerivedMetricsStayAbsentRatherThanBecomingZero() throws {
        let metrics = try DerivedMetrics(
            workoutID: Fixture.workoutID,
            planVersion: PlanVersion(1)
        )
        let restored = try StoredDerivedMetrics(metrics).toDomain()
        XCTAssertEqual(restored, metrics)
        XCTAssertNil(restored.averageHeartRateBPM)
        XCTAssertNil(restored.timeAboveCapSeconds)
        XCTAssertNil(restored.heartRateDriftFraction)
        XCTAssertNil(restored.gradeAdjustedPaceSecondsPerKilometer)
        XCTAssertNil(restored.distanceSplits)
        XCTAssertFalse(restored.hasHeartRateData)
    }

    func testEmptyZoneSplitsRoundTrip() throws {
        let metrics = try DerivedMetrics(
            workoutID: Fixture.workoutID,
            zoneSplits: .empty,
            planVersion: PlanVersion(1)
        )
        let restored = try StoredDerivedMetrics(metrics).toDomain()
        XCTAssertEqual(restored.zoneSplits, ZoneSplits.empty)
        XCTAssertEqual(restored.zoneSplits.totalSeconds, 0)
    }

    /// D1: without the plan version, "time above cap" is a measurement with no stated
    /// cap, and a later plan version would silently reinterpret it.
    func testDerivedMetricsCarryTheirPlanVersionThroughStorage() throws {
        let metrics = try DerivedMetrics(
            workoutID: Fixture.workoutID,
            averageHeartRateBPM: 150,
            timeAboveCapSeconds: 60,
            planVersion: PlanVersion(7)
        )
        XCTAssertEqual(try StoredDerivedMetrics(metrics).toDomain().planVersion, try PlanVersion(7))
    }

    // MARK: - MAX-067: the backfill marker

    /// The load-bearing case: a `StoredDerivedMetrics` whose `distanceSplitsComputed` is
    /// `false` — what `DerivedMetricsRecord`'s migration default produces for every row
    /// written before this column existed — must read back as `false`, not silently
    /// upgrade to `true` on the trip through `toDomain()`. If it did, the backfill sweep
    /// would never find these rows as candidates and every run on the athlete's device
    /// today would stay unbackfilled forever.
    func testALegacyRowWithDistanceSplitsNotYetComputedRoundTripsAsNotComputed() throws {
        var stored = try StoredDerivedMetrics(
            DerivedMetrics(workoutID: Fixture.workoutID, planVersion: PlanVersion(1))
        )
        stored.distanceSplitsComputed = false

        let restored = try stored.toDomain()

        XCTAssertFalse(restored.distanceSplitsComputed)
        XCTAssertNil(restored.distanceSplits)
    }

    /// The ordinary, post-MAX-067 case: a freshly computed record — routed or not —
    /// carries `distanceSplitsComputed == true` through storage regardless of whether a
    /// breakdown was actually found.
    func testAFreshlyComputedRecordRoundTripsAsComputedEvenWithNoBreakdown() throws {
        let metrics = try DerivedMetrics(
            workoutID: Fixture.workoutID,
            distanceSplitsComputed: true,
            planVersion: PlanVersion(1)
        )
        let restored = try StoredDerivedMetrics(metrics).toDomain()

        XCTAssertTrue(restored.distanceSplitsComputed)
        XCTAssertNil(restored.distanceSplits, "an indoor run with no route still has none to store")
    }

    func testStoredDerivedMetricsWithInvalidPlanVersionAreRejected() throws {
        var stored = try StoredDerivedMetrics(
            DerivedMetrics(workoutID: Fixture.workoutID, planVersion: PlanVersion(1))
        )
        stored.planVersionNumber = 0
        assertThrows(.outOfRange, try stored.toDomain())
    }

    // MARK: - Score and annotations (D8)

    func testScoreRoundTripsUnchanged() throws {
        let score = try Fixture.score(points: 88)
        let restored = try StoredScore(score).toDomain()
        XCTAssertEqual(restored, score)
        XCTAssertEqual(restored.band, .effective)
        XCTAssertTrue(restored.isEffective)
    }

    func testScoreRoundTripsAcrossEveryBand() throws {
        for (points, expected) in [(90, ScoreBand.effective), (60, .marginal), (10, .ineffective)] {
            let score = try Fixture.score(points: points)
            let restored = try StoredScore(score).toDomain()
            XCTAssertEqual(restored, score)
            XCTAssertEqual(restored.band, expected)
        }
    }

    func testScoreWithoutRubricBandIdentifierRoundTrips() throws {
        let score = try Score(
            workoutID: Fixture.workoutID,
            planVersion: PlanVersion(1),
            scheduledSession: .rest,
            actualClassification: .other,
            value: ScoreValue(30),
            effectiveThreshold: ScoreValue(70),
            band: .ineffective,
            rubricBandIdentifier: nil,
            rationale: "No session was scheduled.",
            scoredAt: Fixture.epoch
        )
        let restored = try StoredScore(score).toDomain()
        XCTAssertEqual(restored, score)
        XCTAssertNil(restored.rubricBandIdentifier)
    }

    /// A stored band that contradicts the stored threshold is exactly the incoherent
    /// record `Score.init` refuses to build. Storage must not be a way around it.
    func testStoredScoreWithContradictoryBandIsRejected() throws {
        var stored = try StoredScore(Fixture.score(points: 88))
        stored.bandRawValue = ScoreBand.ineffective.rawValue
        assertThrows(.inconsistent, try stored.toDomain())
    }

    func testStoredScoreWithUnknownBandIsRejected() throws {
        var stored = try StoredScore(Fixture.score(points: 88))
        stored.bandRawValue = "excellent"
        assertThrows(.malformed, try stored.toDomain())
    }

    func testStoredScoreWithUnknownClassificationIsRejected() throws {
        var stored = try StoredScore(Fixture.score(points: 88))
        stored.actualClassificationRawValue = "swimming"
        assertThrows(.malformed, try stored.toDomain())
    }

    func testScoreAnnotationRoundTripsUnchanged() throws {
        let annotation = try Fixture.annotation(points: 55)
        XCTAssertEqual(try StoredScoreAnnotation(annotation).toDomain(), annotation)
    }

    func testScoreAnnotationWithoutNoteRoundTrips() throws {
        let annotation = try ScoreAnnotation(
            id: UUID(),
            workoutID: Fixture.workoutID,
            manualScore: ScoreValue(72),
            note: nil,
            createdAt: Fixture.epoch
        )
        let restored = try StoredScoreAnnotation(annotation).toDomain()
        XCTAssertEqual(restored, annotation)
        XCTAssertNil(restored.note)
    }

    /// D8's telemetry is the *gap* between the two scores. Reassembling a ledger from
    /// separately stored records has to preserve it exactly, or PRD §2's scorer-quality
    /// metric is measuring storage rounding instead of disagreement.
    func testLedgerReassembledFromStoredRecordsPreservesDivergence() throws {
        let score = try Fixture.score(points: 82)
        let first = try Fixture.annotation(points: 60, at: 100, id: Fixture.otherWorkoutID)
        let second = try Fixture.annotation(points: 55, at: 200, id: Fixture.workoutID)

        let restoredScore = try StoredScore(score).toDomain()
        let restoredAnnotations = try [first, second]
            .map { try StoredScoreAnnotation($0) }
            .map { try $0.toDomain() }
        let ledger = try ScoreLedger(automatic: restoredScore, annotations: restoredAnnotations)

        XCTAssertEqual(ledger.automatic.value, try ScoreValue(82))
        XCTAssertEqual(ledger.effectiveValue, try ScoreValue(55))
        XCTAssertEqual(ledger.divergence, -27)
        XCTAssertTrue(ledger.wasCorrected)
    }

    // MARK: - Plan (D1)

    func testPlanRoundTripsUnchanged() throws {
        let plan = try Fixture.plan()
        let restored = try StoredPlan(plan).toDomain()
        XCTAssertEqual(restored, plan)
    }

    /// The rubric is the part of the plan most expensive to lose: D1 makes it versioned
    /// data, so a stored plan whose rubric came back subtly different would make every
    /// historical score irreproducible.
    func testPlanRubricSurvivesStorageIntact() throws {
        let plan = try Fixture.plan()
        let restored = try StoredPlan(plan).toDomain()
        XCTAssertEqual(restored.rubric, plan.rubric)
        XCTAssertEqual(restored.rubric.bands.map(\.identifier), plan.rubric.bands.map(\.identifier))
        XCTAssertEqual(restored.heartRateCapBPM, 150)
        XCTAssertEqual(restored.cadenceTarget, plan.cadenceTarget)
        // Band order is part of the rubric's meaning — first match wins.
        XCTAssertEqual(restored.rubric.bands, plan.rubric.bands)
    }

    func testPlanReferencesStillResolveAfterStorage() throws {
        let plan = try Fixture.plan(heartRateCapBPM: 152)
        let restored = try StoredPlan(plan).toDomain()
        XCTAssertEqual(restored.resolve(.heartRateCap(offsetBPM: 8)), 160)
        XCTAssertEqual(restored.resolve(.cadenceTargetLow(offsetStepsPerMinute: 0)), 165)
        // Unchanged in meaning across MAX-131: `.scheduledDistance(fraction:)` is the
        // same stored reference, resolved by the same multiplication. Only the way the
        // day's ask is handed to `resolve` moved, from a loose `Double?` to the session
        // that carries it.
        XCTAssertEqual(
            restored.resolve(
                .scheduledDistance(fraction: 0.8),
                against: try ScheduledSession(kind: .long, distanceMeters: 10_000)
            ),
            8_000
        )
    }

    /// The lifted columns are duplicated data, and duplicated data can disagree. A plan
    /// that sorted into one position while governing a different range of days is D1
    /// failing silently.
    func testStoredPlanRejectsColumnsThatDisagreeWithThePayload() throws {
        var stored = try StoredPlan(Fixture.plan(version: 2))
        stored.versionNumber = 5
        assertThrows(.inconsistent, try stored.toDomain())

        var shifted = try StoredPlan(Fixture.plan())
        shifted.effectiveFromISO8601 = "2026-06-01"
        assertThrows(.inconsistent, try shifted.toDomain())
    }

    /// `YYYY-MM-DD` is fixed-width and zero-padded, so a lexicographic sort of the
    /// stored column is a chronological sort. That is what lets plan versions be ordered
    /// by a plain string comparison, with no date parsing and no time zone involved.
    func testEffectiveFromColumnSortsChronologicallyAsAString() throws {
        let days = [
            try Fixture.day(2026, 12, 1),
            try Fixture.day(2026, 1, 5),
            try Fixture.day(2027, 1, 1),
            try Fixture.day(2026, 1, 15),
        ]
        let sortedAsStrings = days.map(\.description).sorted()
        let sortedAsDays = days.sorted().map(\.description)
        XCTAssertEqual(sortedAsStrings, sortedAsDays)
        XCTAssertEqual(sortedAsStrings.first, "2026-01-05")
    }

    /// Loading every stored version must reproduce a calendar that resolves the same way
    /// it did before it was written — the whole of D1 in one assertion.
    func testPlanCalendarRebuiltFromStorageResolvesIdentically() throws {
        let first = try Fixture.plan(version: 1, heartRateCapBPM: 150)
        let second = try Plan(
            version: PlanVersion(2),
            effectiveFrom: Fixture.day(2026, 3, 1),
            weeklyTemplate: Fixture.weeklyTemplate(),
            longRunArc: LongRunArc(weeks: [LongRunArc.Week(index: 1, distanceMeters: 22_000)]),
            heartRateCapBPM: 146,
            cadenceTarget: CadenceBand(lowStepsPerMinute: 168, highStepsPerMinute: 172),
            rubric: Fixture.rubric()
        )

        let restored = try [first, second]
            .map { try StoredPlan($0) }
            .map { try $0.toDomain() }
        let calendar = try PlanCalendar(restored)

        XCTAssertEqual(calendar.plan(on: try Fixture.day(2026, 2, 28))?.version, try PlanVersion(1))
        XCTAssertEqual(calendar.plan(on: try Fixture.day(2026, 3, 1))?.version, try PlanVersion(2))
        XCTAssertEqual(calendar.plan(on: try Fixture.day(2026, 3, 1))?.heartRateCapBPM, 146)
        XCTAssertNil(calendar.plan(on: try Fixture.day(2025, 12, 31)))
    }

    // MARK: - Rest-day overrides, chat, settings

    func testRestDayOverrideRoundTripsUnchanged() throws {
        let override = RestDayOverride(
            date: try Fixture.day(2026, 2, 17),
            convertedFromMissed: true,
            createdAt: Fixture.epoch
        )
        let restored = try StoredRestDayOverride(override).toDomain()
        XCTAssertEqual(restored, override)
        XCTAssertTrue(restored.convertedFromMissed)
    }

    /// A6 makes conversion automatic, but the flag distinguishes an automatic
    /// conversion from a day simply recorded as rest — different facts, and A6 warns the
    /// heuristic may need revisiting.
    func testRestDayOverrideDistinguishesConvertedFromPlainRest() throws {
        let plain = RestDayOverride(
            date: try Fixture.day(2026, 2, 18),
            convertedFromMissed: false,
            createdAt: Fixture.epoch
        )
        XCTAssertFalse(try StoredRestDayOverride(plain).toDomain().convertedFromMissed)
    }

    func testChatThreadRoundTripsUnchanged() throws {
        let thread = try Fixture.thread(
            id: Fixture.otherWorkoutID,
            subject: .workout(Fixture.workoutID),
            messages: [
                try Fixture.message(.system, "Context", at: 0),
                try Fixture.message(.user, "Why was this scored 62?", at: 5),
                try Fixture.message(.assistant, "Your average HR was above the cap.", at: 9),
            ]
        )
        let restored = try StoredChatThread(thread, createdAt: Fixture.epoch).toDomain()
        XCTAssertEqual(restored, thread)
        // The seed context is not a bubble (FR-2.1); storage must not change that.
        XCTAssertEqual(restored.visibleMessages.count, 2)
        XCTAssertEqual(restored.messages.first?.role, .system)
    }

    func testEmptyChatThreadRoundTrips() throws {
        let thread = try Fixture.thread(lastActivityAt: Fixture.epoch)
        let restored = try StoredChatThread(thread, createdAt: Fixture.epoch).toDomain()
        XCTAssertEqual(restored, thread)
        XCTAssertTrue(restored.isEmpty)
    }

    func testChatMessageTimestampsSurviveExactly() throws {
        let precise = Fixture.epoch.addingTimeInterval(0.123456)
        let thread = try Fixture.thread(
            messages: [ChatMessage(id: UUID(), role: .user, content: "hi", timestamp: precise)]
        )
        XCTAssertEqual(
            try StoredChatThread(thread, createdAt: Fixture.epoch).toDomain().messages[0].timestamp,
            precise
        )
    }

    /// MAX-092: the record has no `lastActivityAt` column yet (MAX-093 adds one), so
    /// `toDomain()` derives it from what the record does hold. This pins the derivation,
    /// because it is what MAX-093 has to backfill existing rows with.
    ///
    /// For a thread anybody has spoken in, the value is not a guess at all — every turn
    /// carries its own timestamp, so the last one *is* the last activity.
    func testLastActivityIsDerivedFromTheLastTurn() throws {
        let thread = try Fixture.thread(
            messages: [
                try Fixture.message(.user, "Was that on plan?", at: 0),
                try Fixture.message(.assistant, "Yes.", at: 90),
            ],
            lastActivityAt: Fixture.at(90)
        )
        let restored = try StoredChatThread(thread, createdAt: Fixture.at(-1_000)).toDomain()
        XCTAssertEqual(restored.lastActivityAt, Fixture.at(90))
        XCTAssertEqual(restored, thread)
    }

    /// MAX-048: `createdAt` is pure storage bookkeeping for duplicate resolution — the
    /// dedupe tiebreak `MaximizeStore.workoutThreadRecords(for:)` sorts on. MAX-093 gives
    /// `lastActivityAt` its own column, so unlike MAX-092's stopgap (which derived it
    /// from `createdAt` because there was nowhere else to get it), `createdAt` no longer
    /// has any influence on a freshly-written thread's `lastActivityAt`.
    func testCreatedAtNoLongerInfluencesAFreshlyWrittenThreadsLastActivity() throws {
        let lastActivityAt = Fixture.epoch.addingTimeInterval(42)
        let thread = try Fixture.thread(lastActivityAt: lastActivityAt)

        let stored = try StoredChatThread(thread, createdAt: Fixture.epoch)
        XCTAssertEqual(stored.createdAt, Fixture.epoch)
        XCTAssertEqual(stored.lastActivityAt, lastActivityAt)
        XCTAssertEqual(try stored.toDomain().lastActivityAt, lastActivityAt)

        // As `MaximizeStore.store(_:)` does when it preserves `createdAt` across an
        // update: a different `createdAt` changes only the tiebreak column, never the
        // activity the thread itself reports.
        let later = try StoredChatThread(thread, createdAt: Fixture.epoch.addingTimeInterval(3_600))
        XCTAssertEqual(
            try later.toDomain().lastActivityAt,
            lastActivityAt,
            "lastActivityAt is now a real column and must not follow createdAt"
        )
    }

    /// The no-migration claim (A11, CLAUDE.md), proven as behaviour rather than
    /// asserted in prose: a `ChatThreadRecord` written before this ticket's columns
    /// existed loads `lastActivityAt` at its column default
    /// (`StoredChatThread.unsetLastActivityAt`), because that is what SwiftData hands
    /// back for an attribute a stored row never wrote. `toDomain()` has to fall back to
    /// exactly the derivation MAX-092 used — the last turn's timestamp, or `createdAt`
    /// for a thread nobody has spoken in — or every athlete's existing thread would
    /// silently jump to the bottom of the list the first time this build runs.
    func testALegacyRowWithNoLastActivityColumnDerivesItExactlyAsMAX092Did() throws {
        let messages = [
            try Fixture.message(.user, "Was that on plan?", at: 0),
            try Fixture.message(.assistant, "Yes.", at: 90),
        ]
        let spokenTo = StoredChatThread(
            threadUUID: Fixture.workoutID,
            subjectKindRawValue: ChatSubjectKind.workout.rawValue,
            workoutUUID: Fixture.workoutID,
            scopeFromISO8601: nil,
            scopeThroughISO8601: nil,
            messagesJSON: try PersistencePayload.encode(messages, field: "test"),
            createdAt: Fixture.at(-1_000),
            lastActivityAt: StoredChatThread.unsetLastActivityAt
        )
        XCTAssertEqual(try spokenTo.toDomain().lastActivityAt, Fixture.at(90))

        let neverSpokenTo = StoredChatThread(
            threadUUID: Fixture.otherWorkoutID,
            subjectKindRawValue: ChatSubjectKind.workout.rawValue,
            workoutUUID: Fixture.otherWorkoutID,
            scopeFromISO8601: nil,
            scopeThroughISO8601: nil,
            messagesJSON: try PersistencePayload.encode([ChatMessage](), field: "test"),
            createdAt: Fixture.epoch.addingTimeInterval(42),
            lastActivityAt: StoredChatThread.unsetLastActivityAt
        )
        XCTAssertEqual(
            try neverSpokenTo.toDomain().lastActivityAt,
            Fixture.epoch.addingTimeInterval(42),
            "with no turn to date it by, the record's own createdAt is the only answer"
        )
    }

    /// `MaximizeSchemaV1.ChatThreadRecord.subjectKindRawValue` defaults to the literal
    /// `"workout"` so a pre-MAX-093 row — which never wrote this column — loads as a
    /// workout thread (A11: "every existing thread has a workout subject"). Pinning the
    /// raw value here means a future rename of `ChatSubjectKind.workout` fails this test
    /// loudly instead of silently breaking that migration story in a file CI never runs.
    func testWorkoutSubjectKindRawValueMatchesTheSchemasColumnDefault() {
        XCTAssertEqual(ChatSubjectKind.workout.rawValue, "workout")
    }

    /// The load-bearing case MAX-093 exists for: a training thread — no workout at all —
    /// round trips through storage exactly like a workout thread always has.
    func testTrainingChatThreadRoundTripsUnchanged() throws {
        let thread = try Fixture.thread(
            subject: .training(try Fixture.scope(from: (2026, 8, 1), through: (2026, 8, 31))),
            messages: [
                try Fixture.message(.user, "Has my drift flattened this month?", at: 0),
                try Fixture.message(.assistant, "Yes — down from 6% to 3% over the window.", at: 12),
            ]
        )
        let stored = try StoredChatThread(thread, createdAt: Fixture.epoch)
        let restored = try stored.toDomain()

        XCTAssertEqual(restored, thread)
        XCTAssertNil(restored.subject.workoutID)
        XCTAssertEqual(restored.subject.trainingScope, thread.subject.trainingScope)
        // Deterministic, not a fresh UUID() per write — see `noWorkoutSentinel`'s doc.
        XCTAssertEqual(stored.workoutUUID, StoredChatThread.noWorkoutSentinel)
    }

    func testEmptyTrainingChatThreadRoundTrips() throws {
        let scope = try Fixture.scope(from: (2026, 9, 1), through: (2026, 9, 30))
        let thread = try Fixture.thread(subject: .training(scope), lastActivityAt: Fixture.epoch)
        let restored = try StoredChatThread(thread, createdAt: Fixture.epoch).toDomain()
        XCTAssertEqual(restored, thread)
        XCTAssertTrue(restored.isEmpty)
    }

    /// A record whose `subjectKindRawValue` says "training" but is missing a scope
    /// column is a corrupted or mid-write row, not a workout in disguise — it must be
    /// rejected, not silently reinterpreted as something it is not.
    func testTrainingRowMissingAScopeColumnIsRejected() throws {
        var stored = try StoredChatThread(
            Fixture.thread(subject: .training(try Fixture.scope(from: (2026, 8, 1), through: (2026, 8, 31)))),
            createdAt: Fixture.epoch
        )
        stored.scopeThroughISO8601 = nil
        assertThrows(.inconsistent, try stored.toDomain())
    }

    func testUnknownSubjectKindRawValueIsRejected() throws {
        var stored = try StoredChatThread(Fixture.thread(), createdAt: Fixture.epoch)
        stored.subjectKindRawValue = "coaching"
        assertThrows(.malformed, try stored.toDomain())
    }

    func testAppSettingsRoundTripUnchanged() throws {
        let settings = AppSettings(
            restDayBudget: try RestDayBudget(daysPerWeek: 2),
            distanceUnit: .kilometers,
            appearance: .light,
            reducesTransparency: true,
            increasesContrast: true,
            reducesMotion: true
        )
        XCTAssertEqual(try StoredAppSettings(settings).toDomain(), settings)
    }

    func testDefaultAppSettingsRoundTrip() throws {
        let restored = try StoredAppSettings(.standard).toDomain()
        XCTAssertEqual(restored, AppSettings.standard)
        // FR-4.3 is dark-first, so `.system` is deliberately not the default. A storage
        // round-trip that quietly normalised it would undo that decision.
        XCTAssertEqual(restored.appearance, .dark)
        XCTAssertEqual(restored.distanceUnit, .miles)
    }

    func testStoredSettingsWithUnknownEnumRawValuesAreRejected() throws {
        var stored = StoredAppSettings(.standard)
        stored.appearanceRawValue = "sepia"
        assertThrows(.malformed, try stored.toDomain())

        var other = StoredAppSettings(.standard)
        other.distanceUnitRawValue = "furlongs"
        assertThrows(.malformed, try other.toDomain())
    }

    func testStoredSettingsWithOutOfRangeRestBudgetAreRejected() throws {
        var stored = StoredAppSettings(.standard)
        stored.restDayBudgetDaysPerWeek = 8
        assertThrows(.outOfRange, try stored.toDomain())
    }

    // MARK: - Encoding stability

    /// The blob bytes outlive the process that wrote them. Encoding must be a
    /// deterministic function of the value: it keeps these tests stable, and it means an
    /// unchanged value re-encodes identically, so CloudKit sees no change to mirror.
    func testBlobEncodingIsDeterministic() throws {
        let series = try HeartRateSeries(
            workoutID: Fixture.workoutID,
            samples: Fixture.samples([(0, 120), (30, 135)])
        )
        XCTAssertEqual(
            try StoredHeartRateSeries(series).samplesJSON,
            try StoredHeartRateSeries(series).samplesJSON
        )

        let plan = try Fixture.plan()
        XCTAssertEqual(try StoredPlan(plan).payloadJSON, try StoredPlan(plan).payloadJSON)
    }

    /// Storing and reloading twice must be a fixed point. A mapping that lost precision
    /// or re-ordered a collection would drift a little further on every pass, which is
    /// the failure mode a single round-trip can miss.
    func testRepeatedRoundTripsAreStable() throws {
        let workout = try Fixture.workout()
        let once = try StoredWorkout(workout).toDomain()
        let twice = try StoredWorkout(once).toDomain()
        XCTAssertEqual(once, twice)

        let plan = try Fixture.plan()
        let planOnce = try StoredPlan(plan).toDomain()
        let planTwice = try StoredPlan(planOnce).toDomain()
        XCTAssertEqual(planOnce, planTwice)
        XCTAssertEqual(try StoredPlan(planOnce).payloadJSON, try StoredPlan(planTwice).payloadJSON)
    }

    // MARK: - Cascade coverage

    /// The cascade list is the thing that stops orphans accumulating in a synced store.
    /// If a later ticket adds a per-workout record type, this test is the reminder that
    /// deletion has to learn about it.
    func testEveryAttachedRecordKindIsAccountedFor() {
        XCTAssertEqual(
            Set(WorkoutAttachedRecord.allCases),
            [.heartRateSeries, .route, .derivedMetrics, .automaticScore, .scoreAnnotations, .chatThread]
        )
    }
}
