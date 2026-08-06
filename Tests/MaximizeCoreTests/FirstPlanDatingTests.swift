import XCTest
import Foundation
@testable import MaximizeCore
import MaximizeCoreTestSupport

/// MAX-165 / A23 — the first plan's date covers what is already captured.
///
/// The defect these tests exist for is the quietest one on the board: the ingester
/// backfills ninety days, the authoring screen suggested this week's Monday, and a
/// workout on a day no plan governs can never acquire derived metrics because MAX-011
/// forbids a later version from reaching back. Accepting the suggested date on install
/// day therefore threw away almost the entire backfill, permanently, with nothing said.
///
/// Two halves are asserted here. The arithmetic — what a date suggests and what a date
/// costs — and the consequence, driven end to end through the real pipeline: a workout
/// captured before any plan exists acquires its metrics under a first plan dated by the
/// new suggestion, and does *not* under the old one.
final class FirstPlanDatingTests: XCTestCase {

    private func day(_ text: String) throws -> CalendarDay {
        try CalendarDay(iso8601: text)
    }

    /// A Thursday, so "the Monday of this week" (2026-08-03) is a distinct day. Same
    /// anchor `PlanAuthoringTests` uses, deliberately: these two files describe the same
    /// screen and should not disagree about what week it is.
    private var today: CalendarDay {
        get throws { try day("2026-08-06") }
    }

    private func history(_ days: String...) throws -> CapturedWorkoutHistory {
        CapturedWorkoutHistory(days: try days.map { try day($0) })
    }

    // MARK: - What the first plan suggests

    func testTheSuggestedDateCoversTheEarliestCapturedWorkout() throws {
        // The whole ticket in one assertion: 89 days of backfill, and the date offered
        // reaches all of it rather than stopping at Monday.
        let captured = try history("2026-05-09", "2026-06-20", "2026-08-04")

        let session = try PlanAuthoring.session(
            revising: nil,
            today: try today,
            capturedHistory: captured
        )

        XCTAssertEqual(session.suggestedEffectiveFrom, try day("2026-05-09"))
        XCTAssertEqual(session.workoutsExcluded(byEffectiveFrom: session.suggestedEffectiveFrom), 0)
    }

    func testWithNothingCapturedTheSuggestionIsStillThisWeeksMonday() throws {
        // A23's stated fallback, and the pre-existing behaviour. A fresh device with no
        // history has nothing to reach back for, and a plan dated arbitrarily far back
        // would claim days it has no business claiming.
        let session = try PlanAuthoring.session(
            revising: nil,
            today: try today,
            capturedHistory: .empty
        )

        XCTAssertEqual(session.suggestedEffectiveFrom, try day("2026-08-03"))
        XCTAssertNil(session.excludedWorkoutsNotice(forEffectiveFrom: session.suggestedEffectiveFrom))
    }

    func testACallerThatSuppliesNoHistoryGetsThePreviousSuggestion() throws {
        // The default parameter is the compatibility guarantee: chat's proposal card and
        // every other caller that has not read the workout store keeps exactly the answer
        // it had, rather than a guess dressed up as a recommendation.
        let session = try PlanAuthoring.session(revising: nil, today: try today)
        XCTAssertEqual(session.suggestedEffectiveFrom, try day("2026-08-03"))
    }

    func testHistoryEntirelyInsideThisWeekStillSuggestsTheMonday() throws {
        // The ceiling half of the rule. Monday covers a Wednesday run just as well as
        // Wednesday does, and it keeps the whole-week start that arc weeks and the
        // Monday-first template were designed around — so the earlier of the two wins.
        let session = try PlanAuthoring.session(
            revising: nil,
            today: try today,
            capturedHistory: try history("2026-08-05")
        )

        XCTAssertEqual(session.suggestedEffectiveFrom, try day("2026-08-03"))
    }

    func testTheSuggestionIsNeverLaterThanTheOneItReplaced() throws {
        // The invariant that makes this change safe to land without auditing every case:
        // whatever the history, the new suggestion is at or before the old one, so it can
        // only ever exclude fewer workouts than before — never more.
        let mondayOfThisWeek = try day("2026-08-03")
        let histories: [CapturedWorkoutHistory] = [
            .empty,
            try history("2026-08-05"),
            try history("2026-08-03"),
            try history("2026-08-02"),
            try history("2020-01-01", "2026-08-05"),
        ]

        for captured in histories {
            let suggested = try FirstPlanDating.suggestedEffectiveFrom(
                covering: captured,
                today: try today
            )
            XCTAssertLessThanOrEqual(suggested, mondayOfThisWeek)
            XCTAssertEqual(captured.workoutsExcluded(byEffectiveFrom: suggested), 0)
        }
    }

    func testASingleWorkoutOlderThanAnyBackfillWindowIsStillCovered() throws {
        // "Older than the backfill window" is not a case this has to defend against: a
        // workout the ingester never fetched is not in the store, so it is not in the
        // history either. What *is* here is what the device holds, and the suggestion
        // reaches all of it however old that is.
        let captured = try history("2019-03-01")
        let session = try PlanAuthoring.session(
            revising: nil,
            today: try today,
            capturedHistory: captured
        )

        XCTAssertEqual(session.suggestedEffectiveFrom, try day("2019-03-01"))
        XCTAssertEqual(session.workoutsExcluded(byEffectiveFrom: session.suggestedEffectiveFrom), 0)
    }

    // MARK: - What a candidate date costs, at the boundary

    func testAWorkoutOnTheEffectiveDayItselfIsNotExcluded() throws {
        // `PlanCalendar.plan(on:)` is inclusive of `effectiveFrom`, so this count must be
        // too. Getting it wrong would be wrong exactly once per athlete — rare enough to
        // survive casual testing and land on the one screen where the number decides
        // something.
        let captured = try history("2026-06-10")
        XCTAssertEqual(captured.workoutsExcluded(byEffectiveFrom: try day("2026-06-10")), 0)
    }

    func testAWorkoutTheDayBeforeIsExcluded() throws {
        let captured = try history("2026-06-10")
        XCTAssertEqual(captured.workoutsExcluded(byEffectiveFrom: try day("2026-06-11")), 1)
    }

    func testTheCountIsOfWorkoutsAndNotOfDays() throws {
        // Two runs on one day are two workouts a date can strand. A set of distinct days
        // would under-report by exactly the athlete's doubles.
        let captured = try history("2026-06-10", "2026-06-10", "2026-06-11")
        XCTAssertEqual(captured.workoutsExcluded(byEffectiveFrom: try day("2026-06-11")), 2)
        XCTAssertEqual(captured.count, 3)
    }

    func testTheCountWalksTheWholeBoundary() throws {
        let captured = try history("2026-06-09", "2026-06-10", "2026-06-11")

        XCTAssertEqual(captured.workoutsExcluded(byEffectiveFrom: try day("2026-06-08")), 0)
        XCTAssertEqual(captured.workoutsExcluded(byEffectiveFrom: try day("2026-06-09")), 0)
        XCTAssertEqual(captured.workoutsExcluded(byEffectiveFrom: try day("2026-06-10")), 1)
        XCTAssertEqual(captured.workoutsExcluded(byEffectiveFrom: try day("2026-06-11")), 2)
        XCTAssertEqual(captured.workoutsExcluded(byEffectiveFrom: try day("2026-06-12")), 3)
    }

    func testHistoryIsOrderedHoweverItArrives() throws {
        let captured = try history("2026-08-05", "2026-01-02", "2026-04-04")
        XCTAssertEqual(captured.earliestDay, try day("2026-01-02"))
        XCTAssertEqual(captured.days, [
            try day("2026-01-02"), try day("2026-04-04"), try day("2026-08-05"),
        ])
    }

    func testWorkoutsBecomeDaysInTheZoneTheCallerNames() throws {
        // A run at 23:40 in London is the 5th there and the 6th in UTC+1. The conversion
        // has one entry point and it demands the zone, so this cannot happen implicitly.
        // 216 days after `Fixture.epoch` (2026-01-01T00:00:00Z), at 23:20.
        let lateEvening = Fixture.epoch.addingTimeInterval(216 * 86_400 + 23 * 3_600 + 20 * 60)
        let workout = try Workout(
            id: UUID(),
            activityType: .running,
            start: lateEvening,
            end: lateEvening.addingTimeInterval(1_800),
            durationSeconds: 1_800,
            distanceMeters: 5_000,
            activeEnergyKilocalories: 350,
            hasRoute: false,
            source: .appleWatch,
            ingestedAt: lateEvening.addingTimeInterval(3_600)
        )

        let utc = try CapturedWorkoutHistory(workouts: [workout], in: XCTUnwrap(TimeZone(identifier: "UTC")))
        let berlin = try CapturedWorkoutHistory(workouts: [workout], in: XCTUnwrap(TimeZone(identifier: "Europe/Berlin")))

        XCTAssertEqual(utc.earliestDay, try day("2026-08-05"))
        XCTAssertEqual(berlin.earliestDay, try day("2026-08-06"))
    }

    // MARK: - The sentence the athlete reads

    func testTheNoticeStatesTheCountAndThePermanence() throws {
        let notice = try XCTUnwrap(PlanCopy.excludedWorkoutsNotice(count: 43))
        XCTAssertTrue(notice.contains("43 workouts"), notice)
        XCTAssertTrue(notice.contains("never"), notice)
    }

    func testTheNoticeIsSingularForOne() throws {
        let notice = try XCTUnwrap(PlanCopy.excludedWorkoutsNotice(count: 1))
        XCTAssertTrue(notice.contains("1 workout already recorded falls"), notice)
        XCTAssertFalse(notice.contains("workouts"), notice)
    }

    func testTheNoticeIsAbsentRatherThanZero() throws {
        // Absence is the designed state: a date that costs nothing has nothing to say,
        // and a rendered "0 workouts" would make the ordinary case look like a warning.
        XCTAssertNil(PlanCopy.excludedWorkoutsNotice(count: 0))
    }

    func testTheNoticeCarriesTheCountForACandidateDate() throws {
        let session = try PlanAuthoring.session(
            revising: nil,
            today: try today,
            capturedHistory: try history("2026-05-09", "2026-06-20", "2026-08-04")
        )

        XCTAssertNil(session.excludedWorkoutsNotice(forEffectiveFrom: try day("2026-05-09")))
        let notice = try XCTUnwrap(session.excludedWorkoutsNotice(forEffectiveFrom: try day("2026-08-03")))
        XCTAssertTrue(notice.contains("2 workouts"), notice)
    }

    // MARK: - A revision is untouched by all of this

    func testARevisionExcludesNothingAndSaysNothing() throws {
        // A revision cannot strand anything: every day before its effective date is
        // already governed by the version it supersedes. Running the first plan's
        // arithmetic here would put a large and entirely false number on the screen of an
        // athlete whose history is wholly covered.
        let start = try day("2026-06-01")
        let first = try PlanAuthoring.session(revising: nil, today: start)
        let stored = try PlanCalendar([first.plan(from: first.draft, effectiveFrom: start)])

        let revision = try PlanAuthoring.session(
            revising: stored,
            today: try today,
            capturedHistory: try history("2020-01-01", "2026-01-01", "2026-08-05")
        )

        XCTAssertEqual(revision.workoutsExcluded(byEffectiveFrom: try day("2026-08-03")), 0)
        XCTAssertNil(revision.excludedWorkoutsNotice(forEffectiveFrom: try day("2026-08-03")))
    }

    func testARevisionKeepsItsDateRulesAndItsSuggestion() throws {
        // D1's no-back-dating rule is not weakened by any of this, and supplying a
        // history does not move a revision's suggested date by a day.
        let start = try day("2026-06-01")
        let first = try PlanAuthoring.session(revising: nil, today: start)
        let stored = try PlanCalendar([first.plan(from: first.draft, effectiveFrom: start)])

        let revision = try PlanAuthoring.session(
            revising: stored,
            today: try today,
            capturedHistory: try history("2026-01-01")
        )

        XCTAssertEqual(revision.earliestEffectiveFrom, try day("2026-06-02"))
        XCTAssertEqual(revision.suggestedEffectiveFrom, try today)
        XCTAssertFalse(revision.permitsEffectiveFrom(try day("2026-01-01")))
        XCTAssertThrowsError(
            try revision.plan(from: revision.draft, effectiveFrom: try day("2026-01-01"))
        )
    }

    // MARK: - End to end: the workout the old default would have thrown away

    /// **The test that proves the ticket did its job.**
    ///
    /// A run is captured on 2026-01-01 with no plan authored — the install-day state —
    /// and is stored with no derived metrics. Sixty-three days later the athlete opens
    /// the authoring screen and accepts the suggested date. The run acquires its metrics.
    ///
    /// This is not a rescore and cannot become one (D8): the workout was never scored, so
    /// `completeIngestion(forWorkout:)`'s ledger check finds nothing and lets enrichment
    /// run. Nothing here overwrites an auto-score, and nothing here could.
    func testAWorkoutInsideTheBackfillWindowGetsMetricsUnderTheSuggestedFirstPlan() async throws {
        let harness = try StrandedWorkoutHarness()

        try await harness.pipeline.ingest(harness.workout)

        XCTAssertEqual(harness.store.storedWorkouts.map(\.id), [harness.workout.id])
        XCTAssertNil(harness.store.storedMetrics(forWorkout: harness.workout.id))
        XCTAssertEqual(harness.diagnostics.reported, [.storedWithoutPlan(reason: .noPlanAuthored)])

        let session = try await harness.authoringSession()
        XCTAssertEqual(session.suggestedEffectiveFrom, try day("2026-01-01"))

        let plan = try session.plan(from: session.draft, effectiveFrom: session.suggestedEffectiveFrom)
        harness.store.setPlanCalendar(try PlanCalendar([plan]))
        await harness.pipeline.completeIngestion(forWorkout: harness.workout.id)

        let metrics = try XCTUnwrap(
            harness.store.storedMetrics(forWorkout: harness.workout.id),
            "the run is inside the backfill window and the suggested first plan governs its day"
        )
        XCTAssertEqual(metrics.planVersion, try PlanVersion(1))
        XCTAssertFalse(
            harness.diagnostics.reported.contains(.storedWithoutPlan(reason: .workoutPredatesEveryPlan))
        )
    }

    /// The same run, under the date the screen used to suggest. This is the defect, and
    /// it is asserted rather than described so nobody reintroduces the old default
    /// believing it was harmless.
    func testTheOldSuggestionStrandsTheSameWorkoutPermanently() async throws {
        let harness = try StrandedWorkoutHarness()

        try await harness.pipeline.ingest(harness.workout)

        let session = try await harness.authoringSession()
        let oldSuggestion = try StrandedWorkoutHarness.today.startOfTrainingWeek()
        XCTAssertEqual(oldSuggestion, try day("2026-03-02"))
        XCTAssertEqual(session.workoutsExcluded(byEffectiveFrom: oldSuggestion), 1)

        let plan = try session.plan(from: session.draft, effectiveFrom: oldSuggestion)
        harness.store.setPlanCalendar(try PlanCalendar([plan]))
        await harness.pipeline.completeIngestion(forWorkout: harness.workout.id)

        XCTAssertNil(
            harness.store.storedMetrics(forWorkout: harness.workout.id),
            "a workout on a day no plan governs has nothing to be measured against"
        )
        XCTAssertTrue(
            harness.diagnostics.reported.contains(.storedWithoutPlan(reason: .workoutPredatesEveryPlan))
        )

        // And no later version can repair it — the rule this ticket deliberately does not
        // weaken. A second version dated to cover the run is refused outright.
        let revision = try PlanAuthoring.session(
            revising: try PlanCalendar([plan]),
            today: try StrandedWorkoutHarness.today
        )
        XCTAssertThrowsError(
            try revision.plan(from: revision.draft, effectiveFrom: try day("2026-01-01"))
        )
    }

    // MARK: - Harness

    /// The pipeline wired the way the app wires it, with the health store, the model and
    /// the database replaced by fakes, and — the point of this harness — **no plan
    /// authored**, which is the app's state on the day it is installed.
    private struct StrandedWorkoutHarness {
        /// 2026-03-05, a Thursday: 63 days after the captured run, so the run is inside
        /// `AnchoredIngestionPolicy.standard`'s ninety-day first-run window and outside
        /// the training week the screen used to suggest.
        static var today: CalendarDay {
            get throws { try CalendarDay(iso8601: "2026-03-05") }
        }

        /// The zone the pipeline and the history conversion both resolve days in. One
        /// value, used twice, so a workout cannot land on one side of a boundary in the
        /// pipeline and the other side on the screen.
        static let zone = TimeZone(identifier: "UTC") ?? .gmt

        let store: InMemoryWorkoutStore
        let samples: FakeWorkoutSampleFetcher
        let diagnostics: IngestionPipelineDiagnosticRecorder
        let pipeline: WorkoutIngestionPipeline
        let workout: Workout

        init() throws {
            // `Fixture.epoch` is 2026-01-01. The run is an ordinary easy hour at 140 bpm;
            // nothing about it is unusual, which is the point — it is stranded for where
            // it sits in time and for no other reason.
            let capturedWorkout = try Fixture.workout(activityType: .running, hasRoute: true)
            let workoutStore = InMemoryWorkoutStore(planCalendar: nil)
            let sampleFetcher = FakeWorkoutSampleFetcher()
            let recorder = IngestionPipelineDiagnosticRecorder()

            // Queued several times because the fake hands out one page per call while a
            // real health store answers the same window identically however often it is
            // asked — and `completeIngestion` genuinely re-extracts.
            let page = HeartRateSampleFetchPage(samples: [0.0, 1_800.0, 3_600.0].map {
                RawHeartRateSample(date: Fixture.epoch.addingTimeInterval($0), beatsPerMinute: 140)
            })
            for _ in 0..<4 {
                sampleFetcher.enqueueHeartRatePage(page)
            }
            sampleFetcher.setTotalStepCount(10_000)

            workout = capturedWorkout
            store = workoutStore
            samples = sampleFetcher
            diagnostics = recorder
            pipeline = WorkoutIngestionPipeline(
                workouts: workoutStore,
                scores: workoutStore,
                plans: workoutStore,
                samples: sampleFetcher,
                model: FakeScoringModel(),
                timeZone: { StrandedWorkoutHarness.zone },
                now: { Date(timeIntervalSince1970: 1_767_312_000) },
                report: recorder.handler()
            )
        }

        /// The session the authoring screen would build, against the store as it stands —
        /// the same call `PlanAuthoringModel.load()` makes, with the same inputs.
        func authoringSession() async throws -> PlanAuthoringSession {
            try PlanAuthoring.session(
                revising: try await store.planCalendar(),
                today: try StrandedWorkoutHarness.today,
                capturedHistory: try CapturedWorkoutHistory(
                    workouts: store.storedWorkouts,
                    in: StrandedWorkoutHarness.zone
                )
            )
        }
    }
}
