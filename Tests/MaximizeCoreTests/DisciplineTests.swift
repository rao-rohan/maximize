import Foundation
import XCTest
@testable import MaximizeCore

/// A17's vocabulary: `Discipline`, `.lift` on both classification enums, and the
/// relationship between `Discipline` and `ActivityType.isRun` that keeps them from
/// becoming two notions of the same thing.
///
/// MAX-128 adds no behaviour, so most of what is worth asserting here is that nothing
/// moved: the tiers the rest-day budget compares, the raw values a stored record
/// decodes from, and the kinds the authoring picker offers.
final class DisciplineTests: XCTestCase {

    /// Every activity type the app names, and the discipline each maps to. The table is
    /// the test: a type added without a decision about which slot judges it shows up
    /// here as a missing row rather than as a silent `.run`.
    private static let namedTypes: [(ActivityType, Discipline)] = [
        (.running, .run),
        (.treadmillRunning, .run),
        (.walking, .run),
        (.hiking, .run),
        (.cycling, .run),
        (.other, .run),
        (.traditionalStrengthTraining, .lift),
    ]

    // MARK: - The mapping

    func testALiftIsALiftAndARunIsARun() {
        XCTAssertEqual(ActivityType.traditionalStrengthTraining.discipline, .lift)
        XCTAssertEqual(ActivityType.running.discipline, .run)
        XCTAssertEqual(ActivityType.treadmillRunning.discipline, .run)
    }

    /// A17: cycling, swimming and mobility are not disciplines — they are `.other`
    /// sessions in the run slot, which is what they already are. This is not a
    /// multi-sport model, and the test says so rather than leaving it to the comment.
    func testEverythingThatIsNotStrengthWorkOccupiesTheRunSlot() {
        for (type, expected) in Self.namedTypes {
            XCTAssertEqual(type.discipline, expected, "\(type)")
        }
    }

    /// The mapping has to be total over an open string wrapper: HealthKit gains
    /// activity types every release, and one the app has never heard of still has to
    /// resolve to a slot rather than trap.
    func testAnUnrecognisedActivityTypeIsTotalAndFallsToTheRunSlot() {
        XCTAssertEqual(ActivityType(rawValue: "paddleboarding").discipline, .run)
        XCTAssertEqual(ActivityType(rawValue: "").discipline, .run)
    }

    // MARK: - `isRun` and `Discipline` cannot disagree

    /// The one-way containment that is the whole relationship between the two
    /// predicates: `isRun` implies the run slot, so nothing can ever be both a lift and
    /// a run. The converse deliberately does not hold — a ride is `.run` by slot and
    /// not a run — and that is why they stay two predicates rather than one.
    func testIsRunImpliesTheRunDisciplineForEveryNamedType() {
        for (type, _) in Self.namedTypes where type.isRun {
            XCTAssertEqual(type.discipline, .run, "\(type) is a run but not in the run slot")
        }
    }

    func testNothingInTheLiftDisciplineIsARun() {
        for (type, discipline) in Self.namedTypes where discipline == .lift {
            XCTAssertFalse(type.isRun, "\(type)")
        }
        XCTAssertFalse(ActivityType.traditionalStrengthTraining.isRun)
    }

    /// The containment holds for types the app has never named, too — the case the
    /// guard inside `isRun` is actually there for.
    func testTheContainmentHoldsForUnrecognisedTypes() {
        for raw in ["paddleboarding", "running ", "Running", "lift", ""] {
            let type = ActivityType(rawValue: raw)
            if type.isRun { XCTAssertEqual(type.discipline, .run, raw) }
            if type.discipline == .lift { XCTAssertFalse(type.isRun, raw) }
        }
    }

    /// MAX-128 changes no behaviour, and `isRun` is the predicate MAX-111's scoring gate
    /// gets its answer from. Rewriting it in terms of `discipline` must not have moved
    /// a single answer.
    func testIsRunAnswersExactlyWhatItAnsweredBefore() {
        XCTAssertTrue(ActivityType.running.isRun)
        XCTAssertTrue(ActivityType.treadmillRunning.isRun)
        XCTAssertFalse(ActivityType.walking.isRun)
        XCTAssertFalse(ActivityType.hiking.isRun)
        XCTAssertFalse(ActivityType.cycling.isRun)
        XCTAssertFalse(ActivityType.traditionalStrengthTraining.isRun)
        XCTAssertFalse(ActivityType.other.isRun)
        XCTAssertFalse(ActivityType(rawValue: "paddleboarding").isRun)
    }

    // MARK: - The closed set

    /// A third discipline is an amendment, not a ticket (A17). Pinned so adding one has
    /// to be a deliberate act with this test in the diff.
    func testDisciplineIsClosedAtTwoCases() {
        XCTAssertEqual(Discipline.allCases, [.run, .lift])
    }

    func testDisciplineEncodesAsItsBareName() throws {
        XCTAssertEqual(Discipline.run.rawValue, "run")
        XCTAssertEqual(Discipline.lift.rawValue, "lift")

        let encoded = try JSONEncoder().encode([Discipline.run, .lift])
        XCTAssertEqual(String(data: encoded, encoding: .utf8), #"["run","lift"]"#)
        XCTAssertEqual(try JSONDecoder().decode([Discipline].self, from: encoded), [.run, .lift])
    }

    // MARK: - `.lift` on the two classification enums

    func testTheScheduledKindMapsFromTheClassificationWithoutGoingThroughOther() {
        XCTAssertEqual(ScheduledSessionKind(.lift), .lift)
        // Unchanged, and the point of asserting it beside the new row: `.other` still
        // means what it meant.
        XCTAssertEqual(ScheduledSessionKind(.easy), .easy)
        XCTAssertEqual(ScheduledSessionKind(.long), .long)
        XCTAssertEqual(ScheduledSessionKind(.hard), .hard)
        XCTAssertEqual(ScheduledSessionKind(.other), .other)
    }

    /// Converting the `==` chain to a `switch` must not have changed an answer. Drift is
    /// meaningful on exactly the two cases it was meaningful on before, and `.lift`
    /// joins the majority — a lift holds no effort for a heart rate to creep at.
    func testDriftMeaningfulnessIsUnchangedAndFalseForALift() {
        XCTAssertTrue(WorkoutClassification.easy.driftIsMeaningful)
        XCTAssertTrue(WorkoutClassification.long.driftIsMeaningful)
        XCTAssertFalse(WorkoutClassification.hard.driftIsMeaningful)
        XCTAssertFalse(WorkoutClassification.other.driftIsMeaningful)
        XCTAssertFalse(WorkoutClassification.lift.driftIsMeaningful)
    }

    // MARK: - Nothing stored has to be migrated

    /// Both enums are `String`-backed and decoded by raw value out of a stored record —
    /// `ScheduledSessionKind` from `StoredPlan.payloadJSON`, `WorkoutClassification`
    /// from `StoredScore.actualClassificationRawValue`. Adding a case is additive on the
    /// wire because no stored record can say `"lift"`, and it is only additive as long
    /// as the raw values already written keep decoding to the same case.
    func testExistingRawValuesAreUnchangedSoNoStoredRecordNeedsMigrating() throws {
        XCTAssertEqual(
            ScheduledSessionKind.allCases.map(\.rawValue),
            ["easy", "long", "hard", "rest", "other", "lift"]
        )
        XCTAssertEqual(
            WorkoutClassification.allCases.map(\.rawValue),
            ["easy", "long", "hard", "other", "lift"]
        )

        // A payload written before `.lift` existed, decoded by today's code.
        let legacy = Data(#"["easy","long","hard","rest","other"]"#.utf8)
        XCTAssertEqual(
            try JSONDecoder().decode([ScheduledSessionKind].self, from: legacy),
            [.easy, .long, .hard, .rest, .other]
        )
        let legacyClassifications = Data(#"["easy","long","hard","other"]"#.utf8)
        XCTAssertEqual(
            try JSONDecoder().decode([WorkoutClassification].self, from: legacyClassifications),
            [.easy, .long, .hard, .other]
        )
    }

    /// `ScheduledSession` is stored inside the plan blob, so its round trip is the one
    /// that matters in practice.
    func testAScheduledLiftRoundTripsThroughTheStoredPlanShape() throws {
        let session = try ScheduledSession(kind: .lift, note: "45 min, lower body")
        let encoded = try JSONEncoder().encode(session)
        XCTAssertEqual(try JSONDecoder().decode(ScheduledSession.self, from: encoded), session)
    }

    // MARK: - Nothing can prescribe a lift yet

    /// The template still has one slot per weekday (MAX-111 gives it a second), so the
    /// authoring picker must offer exactly the five kinds it offered before `.lift`
    /// joined the vocabulary — in the same order, because the plan screen prints a
    /// band's `appliesTo` list in declaration order.
    func testTheAuthorablePrescriptionsAreUnchangedByTheNewCase() {
        XCTAssertEqual(ScheduledSessionKind.prescribable, [.easy, .long, .hard, .rest, .other])
        XCTAssertFalse(ScheduledSessionKind.prescribable.contains(.lift))
    }

    // MARK: - The rest-day budget's ordering

    private func planDay(_ dateText: String, _ kind: ScheduledSessionKind) throws -> PlanDay {
        PlanDay(
            date: try CalendarDay(iso8601: dateText),
            planVersion: try PlanVersion(1),
            scheduledSession: try ScheduledSession(kind: kind)
        )
    }

    /// A19 names the trap: the cost tiers are ordinals compared against each other, so
    /// inserting `.lift` is safe and *reordering* the existing cases would silently
    /// rewrite the calendar's past. This pins the relative order the existing cases had
    /// — `.other` cheapest, then `.easy`, then `.hard`, then `.long` — with `.lift`
    /// sitting between `.easy` and `.hard` where LIFTING-SPEC §2.4 puts it.
    ///
    /// The week is all-missed with a budget of 3, so the three cheapest convert.
    func testTheCostOrderingPutsALiftBetweenAnEasyRunAndAHardSession() throws {
        let week = [
            try planDay("2026-01-05", .other), // Mon — cheapest
            try planDay("2026-01-06", .easy),  // Tue
            try planDay("2026-01-07", .lift),  // Wed
            try planDay("2026-01-08", .hard),  // Thu
            try planDay("2026-01-09", .long),  // Fri — dearest
        ]

        let budget = try RestDayBudget(daysPerWeek: 3)
        let overrides = try RestDayBudgeting.convertingMissedObligations(
            planDays: week,
            // Nothing recorded anywhere, in either slot.
            workoutDisciplines: [:],
            budget: budget,
            createdAt: Date(timeIntervalSince1970: 1_767_312_000)
        )

        XCTAssertEqual(
            overrides.map(\.date.description),
            ["2026-01-05", "2026-01-06", "2026-01-07"],
            "other, then easy, then lift — the hard session and the long run stay red"
        )
    }
}
