import Foundation
import XCTest
@testable import MaximizeCore

final class CadenceBandTests: XCTestCase {
    func testRejectsAnInvertedBand() {
        assertThrows(.inconsistent, try CadenceBand(lowStepsPerMinute: 170, highStepsPerMinute: 165))
    }

    func testAcceptsADegenerateButOrderedBand() throws {
        let band = try CadenceBand(lowStepsPerMinute: 168, highStepsPerMinute: 168)
        XCTAssertTrue(band.contains(168))
        XCTAssertFalse(band.contains(167.9))
    }

    func testRejectsNonPositiveCadence() {
        assertThrows(.outOfRange, try CadenceBand(lowStepsPerMinute: 0, highStepsPerMinute: 170))
        assertThrows(.outOfRange, try CadenceBand(lowStepsPerMinute: -165, highStepsPerMinute: 170))
        assertThrows(.notFinite, try CadenceBand(lowStepsPerMinute: .nan, highStepsPerMinute: 170))
    }

    func testMembershipIsInclusive() throws {
        let band = try CadenceBand(lowStepsPerMinute: 165, highStepsPerMinute: 170)
        XCTAssertTrue(band.contains(165))
        XCTAssertTrue(band.contains(170))
        XCTAssertFalse(band.contains(164.9))
        XCTAssertFalse(band.contains(170.1))
    }
}

final class ScheduledSessionTests: XCTestCase {
    func testRestDayCannotCarryADistance() {
        assertThrows(.inconsistent, try ScheduledSession(kind: .rest, distanceMeters: 5_000))
    }

    func testRestConstantIsARestDay() {
        XCTAssertTrue(ScheduledSession.rest.isRest)
        XCTAssertNil(ScheduledSession.rest.distanceMeters)
    }

    func testRejectsNonPositiveDistance() {
        assertThrows(.outOfRange, try ScheduledSession(kind: .easy, distanceMeters: 0))
        assertThrows(.outOfRange, try ScheduledSession(kind: .easy, distanceMeters: -100))
    }

    func testDriftIsOnlyMeaningfulOnSteadyEfforts() {
        XCTAssertTrue(WorkoutClassification.easy.driftIsMeaningful)
        XCTAssertTrue(WorkoutClassification.long.driftIsMeaningful)
        XCTAssertFalse(WorkoutClassification.hard.driftIsMeaningful)
        XCTAssertFalse(WorkoutClassification.other.driftIsMeaningful)
    }
}

final class WeeklyTemplateTests: XCTestCase {
    func testEveryWeekdayResolvesToASession() throws {
        let template = try Fixture.weeklyTemplate()
        // Resolution is a total function: seven weekdays in, seven sessions out, no
        // optional to unwrap and no "unknown day" case for the scorer to invent.
        XCTAssertEqual(Weekday.allCases.map { template.session(on: $0, for: .run) }.count, 7)
        XCTAssertTrue(template.session(on: .monday, for: .run).isRest)
        XCTAssertEqual(template.session(on: .sunday, for: .run).kind, .long)
        XCTAssertEqual(template.scheduledRunCount, 5)
    }

    /// A17: totality now applies twice rather than being weakened once. Fourteen pairs
    /// in, fourteen sessions out — there is no (weekday, discipline) pair for which the
    /// plan has no answer, so nothing downstream ever has to invent one.
    func testEveryWeekdayResolvesToASessionForEveryDiscipline() throws {
        let template = try Fixture.weeklyTemplate()
        for weekday in Weekday.allCases {
            for discipline in Discipline.allCases {
                // Total: this simply cannot fail to produce a session. The assertion
                // that earns its place is the one below it.
                _ = template.session(on: weekday, for: discipline)
            }
            XCTAssertTrue(
                template.session(on: weekday, for: .lift).isRest,
                "a template authored without lifts prescribes rest on every lift slot"
            )
        }
        XCTAssertEqual(template.scheduledLiftCount, 0)
    }

    func testPrescribesBothDisciplinesOnOneWeekday() throws {
        let template = try Fixture.weeklyTemplate(lift: [
            .tuesday: ScheduledSession(kind: .lift, note: "Upper", muscleGroups: [.chest, .shoulders]),
        ])

        // The normal case, not an edge case (LIFTING-SPEC §5): Tuesday asks for both.
        XCTAssertEqual(template.session(on: .tuesday, for: .run).kind, .easy)
        XCTAssertEqual(template.session(on: .tuesday, for: .run).distanceMeters, 8_000)
        XCTAssertEqual(template.session(on: .tuesday, for: .lift).kind, .lift)
        XCTAssertEqual(template.session(on: .tuesday, for: .lift).muscleGroups, [.chest, .shoulders])

        // And the lift slot is still total on every other day.
        XCTAssertTrue(template.session(on: .wednesday, for: .lift).isRest)
        XCTAssertEqual(template.scheduledLiftCount, 1)
        XCTAssertEqual(template.scheduledRunCount, 5, "the run slot is untouched")
    }

    /// A partial template would push "I don't know what today was" into the scorer,
    /// which PRD §13 flags as the failure that poisons every downstream number.
    func testRejectsAnIncompleteWeek() {
        assertThrows(.inconsistent, try WeeklyTemplate([.monday: .rest, .tuesday: .rest]))
    }

    func testRejectsDuplicateWeekdayEntries() throws {
        let entries = [
            WeeklyTemplate.Entry(weekday: .monday, session: .rest),
            WeeklyTemplate.Entry(weekday: .monday, session: try ScheduledSession(kind: .easy)),
        ]
        assertThrows(.duplicate, try WeeklyTemplate(entries: entries))
    }

    func testEntriesAreCanonicallyOrderedSoEqualityIsMeaningful() throws {
        let template = try Fixture.weeklyTemplate()
        XCTAssertEqual(template.entries.map(\.weekday), Weekday.allCases)
        XCTAssertEqual(try WeeklyTemplate(entries: Array(template.entries.reversed())), template)
    }

    func testResolvesByCalendarDay() throws {
        let template = try Fixture.weeklyTemplate()
        // 2026-08-04 is a Tuesday: an easy 8k in this template.
        let session = template.session(on: try Fixture.day(2026, 8, 4), for: .run)
        XCTAssertEqual(session.kind, .easy)
        XCTAssertEqual(session.distanceMeters, 8_000)
    }

    /// The lift dictionary defaults per weekday; the run dictionary does not. The
    /// asymmetry is what lets a stored payload and a freshly authored template reach
    /// the same value — see `WeeklyTemplate.init(_:lift:)`.
    func testLiftSlotDefaultsToRestWhileTheRunSlotMustBeComplete() throws {
        let template = try Fixture.weeklyTemplate(lift: [.monday: ScheduledSession(kind: .lift)])
        XCTAssertEqual(template.session(on: .monday, for: .lift).kind, .lift)
        for weekday in Weekday.allCases where weekday != .monday {
            XCTAssertTrue(template.session(on: weekday, for: .lift).isRest)
        }
        assertThrows(.inconsistent, try WeeklyTemplate([.monday: .rest, .tuesday: .rest]))
    }
}

final class LongRunArcTests: XCTestCase {
    func testLooksUpTheWeeksAsk() throws {
        let arc = try LongRunArc(weeks: [
            LongRunArc.Week(index: 1, distanceMeters: 16_000),
            LongRunArc.Week(index: 3, distanceMeters: 20_000),
        ])
        XCTAssertEqual(arc.distanceMeters(forWeek: 1), 16_000)
        XCTAssertNil(arc.distanceMeters(forWeek: 2), "A gap in the arc is not an error, just no ask")
        XCTAssertEqual(arc.weekCount, 2)
    }

    func testRejectsUnorderedDuplicateOrEmptyArcs() throws {
        let descending = [
            try LongRunArc.Week(index: 3, distanceMeters: 20_000),
            try LongRunArc.Week(index: 1, distanceMeters: 16_000),
        ]
        assertThrows(.outOfOrder, try LongRunArc(weeks: descending))

        let repeated = [
            try LongRunArc.Week(index: 1, distanceMeters: 16_000),
            try LongRunArc.Week(index: 1, distanceMeters: 18_000),
        ]
        assertThrows(.duplicate, try LongRunArc(weeks: repeated))
        assertThrows(.empty, try LongRunArc(weeks: []))
    }

    func testRejectsNonsenseWeeks() {
        assertThrows(.outOfRange, try LongRunArc.Week(index: 0, distanceMeters: 16_000))
        assertThrows(.outOfRange, try LongRunArc.Week(index: 1, distanceMeters: 0))
    }
}

final class PlanTests: XCTestCase {
    func testRejectsAnImplausibleHeartRateCap() throws {
        assertThrows(.outOfRange, try Fixture.plan(heartRateCapBPM: 400))
        assertThrows(.outOfRange, try Fixture.plan(heartRateCapBPM: 0))
    }

    func testPlanVersionsStartAtOne() {
        assertThrows(.outOfRange, try PlanVersion(0))
        assertThrows(.outOfRange, try PlanVersion(-3))
    }

    /// D1, stated as a test: the cap is a *value inside a plan version*, so moving it
    /// is authoring version 2 — not editing Swift. Version 1 keeps answering the way
    /// it always did, which is what makes historical scores reproducible.
    func testChangingAThresholdMeansANewPlanVersionNotACodeChange() throws {
        let v1 = try Fixture.plan(version: 1, heartRateCapBPM: 150)
        let v2 = try Fixture.plan(version: 2, heartRateCapBPM: 145)

        XCTAssertEqual(v1.resolve(.heartRateCap(offsetBPM: 0)), 150)
        XCTAssertEqual(v2.resolve(.heartRateCap(offsetBPM: 0)), 145)
        XCTAssertLessThan(v1.version, v2.version)
    }

    func testResolvesRubricReferencesAgainstThePlan() throws {
        let plan = try Fixture.plan(heartRateCapBPM: 150)
        XCTAssertEqual(plan.resolve(.heartRateCap(offsetBPM: 8)), 158)
        XCTAssertEqual(plan.resolve(.constant(0.05)), 0.05)
        XCTAssertEqual(plan.resolve(.cadenceTargetLow(offsetStepsPerMinute: 0)), 165)
        XCTAssertEqual(plan.resolve(.cadenceTargetHigh(offsetStepsPerMinute: -2)), 168)
        XCTAssertEqual(
            plan.resolve(.scheduledDistance(fraction: 0.8), scheduledDistanceMeters: 10_000),
            8_000
        )
        XCTAssertNil(
            plan.resolve(.scheduledDistance(fraction: 0.8)),
            "Without a scheduled distance there is nothing to take a fraction of"
        )
    }

    func testRoundTripsThroughJSON() throws {
        let plan = try Fixture.plan()
        XCTAssertEqual(try roundTripped(plan), plan)
    }
}

final class PlanDayTests: XCTestCase {
    func testARestDayCannotBeMissed() throws {
        let restDay = PlanDay(
            date: try Fixture.day(2026, 1, 5),
            planVersion: try PlanVersion(1),
            scheduledSession: .rest
        )
        XCTAssertFalse(restDay.canBeMissed)

        let runDay = PlanDay(
            date: try Fixture.day(2026, 1, 6),
            planVersion: try PlanVersion(1),
            scheduledSession: try ScheduledSession(kind: .easy, distanceMeters: 8_000)
        )
        XCTAssertTrue(runDay.canBeMissed)
        XCTAssertEqual(runDay.id, runDay.date)
    }
}
