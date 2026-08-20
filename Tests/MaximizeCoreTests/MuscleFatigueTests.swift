import Foundation
import XCTest
@testable import MaximizeCore

/// MAX-179 — the decay model over the entries A22 collects.
///
/// **Every expected figure below is computed by hand from the curve, not read off the
/// implementation.** The standard model halves every 48 hours and counts a 45-minute
/// session as a full one, so each elapsed time here is a whole or half number of
/// half-lives and each expectation is a power of two written out. A test that asserted
/// whatever `compute` returned would pass just as happily against the wrong curve.
final class MuscleFatigueTests: XCTestCase {

    // MARK: - Fixtures

    private static let now = Date(timeIntervalSince1970: 1_767_225_600) // 2026-01-01T00:00:00Z
    private static let halfLife: Double = 48 * 3_600
    private static let fullSession: Double = 45 * 60

    /// A session that ended `hoursAgo` before `now`, lasting `minutes`.
    private func session(
        _ groups: Set<MuscleGroup>,
        hoursAgo: Double,
        minutes: Double = 45,
        id: UUID = UUID()
    ) throws -> MuscleFatigueSession {
        try MuscleFatigueSession(
            workoutID: id,
            groups: groups,
            endedAt: Self.now.addingTimeInterval(-hoursAgo * 3_600),
            durationSeconds: minutes * 60
        )
    }

    private func map(
        _ sessions: [MuscleFatigueSession],
        model: MuscleFatigueModel = .standard
    ) throws -> MuscleFatigueMap {
        try MuscleFatigueCalculator.compute(
            MuscleFatigueInput(now: Self.now, sessions: sessions, model: model)
        )
    }

    private func fraction(
        _ map: MuscleFatigueMap,
        _ group: MuscleGroup,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> Double {
        try XCTUnwrap(map[group].fraction, "expected a figure for \(group)", file: file, line: line)
    }

    // MARK: - The model itself

    /// `standard` is built through the unchecked initializer, as `RestDayBudget.standard`
    /// is. This is the test that keeps the two in step: the same arguments must satisfy
    /// the validating one.
    func testTheStandardModelSatisfiesItsOwnValidation() throws {
        let validated = try MuscleFatigueModel(
            halfLifeSeconds: MuscleFatigueModel.standard.halfLifeSeconds,
            fullSessionSeconds: MuscleFatigueModel.standard.fullSessionSeconds,
            negligibleFraction: MuscleFatigueModel.standard.negligibleFraction,
            weighting: MuscleFatigueModel.standard.weighting
        )
        XCTAssertEqual(validated, .standard)
        XCTAssertEqual(MuscleFatigueModel.standard.halfLifeSeconds, Self.halfLife)
        XCTAssertEqual(MuscleFatigueModel.standard.fullSessionSeconds, Self.fullSession)
        XCTAssertEqual(MuscleFatigueModel.standard.negligibleFraction, 0.01)
    }

    func testAModelWithoutAPositiveHalfLifeIsRejected() {
        assertThrows(
            .outOfRange,
            try MuscleFatigueModel(
                halfLifeSeconds: 0,
                fullSessionSeconds: Self.fullSession,
                negligibleFraction: 0.01,
                weighting: .duration
            )
        )
        assertThrows(
            .outOfRange,
            try MuscleFatigueModel(
                halfLifeSeconds: Self.halfLife,
                fullSessionSeconds: Self.fullSession,
                negligibleFraction: 1.5,
                weighting: .duration
            )
        )
    }

    // MARK: - The decay, by hand

    /// A full session that has only just finished is the model's ceiling: weight 1,
    /// decay 2^0 = 1.
    func testAFullSessionEndingNowIsTheCeiling() throws {
        let readings = try map([try session([.chest], hoursAgo: 0)])
        XCTAssertEqual(try fraction(readings, .chest), 1.0, accuracy: 1e-12)
        XCTAssertEqual(readings[.chest].fatigue?.sessionWeight, 1.0)
        XCTAssertEqual(readings[.chest].fatigue?.elapsedSeconds, 0)
    }

    /// One, two and three half-lives: 2^-1, 2^-2, 2^-3. Half a half-life is 2^-0.5,
    /// which is the assertion that would fail if the curve were linear rather than
    /// exponential — a linear ramp through the same two endpoints reads 0.75 at 24
    /// hours, not 0.707.
    func testAFullSessionHalvesEveryFortyEightHours() throws {
        let expected: [(Double, Double)] = [
            (24, 0.7071067811865476),   // 2^-0.5
            (48, 0.5),
            (96, 0.25),
            (144, 0.125)
        ]
        for (hoursAgo, figure) in expected {
            let readings = try map([try session([.legs], hoursAgo: hoursAgo)])
            XCTAssertEqual(
                try fraction(readings, .legs),
                figure,
                accuracy: 1e-12,
                "\(hoursAgo)h ago should read \(figure)"
            )
        }
    }

    /// Duration weighting, on its own: two sessions the same age, one two-thirds the
    /// length of the other.
    func testAShorterSessionWeighsLessInProportionToItsDuration() throws {
        let readings = try map([
            try session([.chest], hoursAgo: 0, minutes: 45),
            try session([.back], hoursAgo: 0, minutes: 30),
            try session([.arms], hoursAgo: 0, minutes: 20)
        ])
        XCTAssertEqual(try fraction(readings, .chest), 1.0, accuracy: 1e-12)
        XCTAssertEqual(try fraction(readings, .back), 0.6666666666666666, accuracy: 1e-12)
        XCTAssertEqual(try fraction(readings, .arms), 0.4444444444444444, accuracy: 1e-12)
    }

    /// Weighting and decay compose: a 30-minute session two days old is 2/3 × 1/2.
    func testWeightAndDecayMultiply() throws {
        let readings = try map([try session([.core], hoursAgo: 48, minutes: 30)])
        XCTAssertEqual(try fraction(readings, .core), 0.3333333333333333, accuracy: 1e-12)
        XCTAssertEqual(readings[.core].fatigue?.sessionWeight, 0.6666666666666666)
    }

    /// The ceiling in `Weighting.duration`: past 45 minutes, longer sessions do not
    /// count for more. Ninety minutes and forty-five read identically, and that is a
    /// stated limit rather than an accident.
    func testASessionLongerThanAFullOneSaturatesRatherThanScalingUp() throws {
        let long = try map([try session([.legs], hoursAgo: 0, minutes: 90)])
        let full = try map([try session([.legs], hoursAgo: 0, minutes: 45)])
        XCTAssertEqual(try fraction(long, .legs), 1.0, accuracy: 1e-12)
        XCTAssertEqual(try fraction(long, .legs), try fraction(full, .legs))
    }

    /// A session dated after `now` — a clock or time-zone artefact — is read as having
    /// just finished rather than as a negative elapsed time, which would put the figure
    /// above the model's ceiling.
    func testASessionDatedInTheFutureIsClampedToJustFinishedRatherThanExceedingTheCeiling() throws {
        let readings = try map([try session([.shoulders], hoursAgo: -6)])
        XCTAssertEqual(try fraction(readings, .shoulders), 1.0, accuracy: 1e-12)
        XCTAssertEqual(readings[.shoulders].fatigue?.elapsedSeconds, 0)
    }

    // MARK: - Ordering

    /// The ordering the muscle map is drawn from: worked today outranks worked a week
    /// ago, for the same session length. A week is 3.5 half-lives — 2^-3.5.
    func testAGroupWorkedTodayOutranksTheSameSessionAWeekAgo() throws {
        let readings = try map([
            try session([.chest], hoursAgo: 0),
            try session([.back], hoursAgo: 168)
        ])
        XCTAssertEqual(try fraction(readings, .chest), 1.0, accuracy: 1e-12)
        XCTAssertEqual(try fraction(readings, .back), 0.08838834764831845, accuracy: 1e-12)
        XCTAssertGreaterThan(try fraction(readings, .chest), try fraction(readings, .back))
        XCTAssertEqual(readings.mostFatiguedFirst.map(\.group), [.chest, .back])
    }

    /// Never-logged groups are absent from the ranking rather than sorted to the bottom
    /// — a group with no figure has no place on a ranking of that figure.
    func testTheRankingCarriesOnlyTheGroupsThatHaveAFigure() throws {
        let readings = try map([try session([.chest, .arms], hoursAgo: 24)])
        XCTAssertEqual(readings.mostFatiguedFirst.map(\.group), [.chest, .arms])
        XCTAssertEqual(readings.neverLogged, [.back, .shoulders, .legs, .core])
    }

    /// Only the most recent session naming a group is read. Two 45-minute chest days,
    /// two and four days ago, read as the later one — 0.5, not 0.5 + 0.25. The model
    /// does not accumulate, and this is the test that says so out loud.
    func testOnlyTheLastSessionNamingAGroupIsRead() throws {
        let readings = try map([
            try session([.chest], hoursAgo: 96),
            try session([.chest], hoursAgo: 48)
        ])
        XCTAssertEqual(try fraction(readings, .chest), 0.5, accuracy: 1e-12)
    }

    /// Input order must not decide the answer, and neither must a shared end instant.
    /// Same-instant sessions are ranked by duration, deterministically.
    func testTheLatestSessionWinsRegardlessOfInputOrderAndTiesAreDeterministic() throws {
        let older = try session([.legs], hoursAgo: 96)
        let newer = try session([.legs], hoursAgo: 48)
        XCTAssertEqual(try fraction(try map([older, newer]), .legs), 0.5, accuracy: 1e-12)
        XCTAssertEqual(try fraction(try map([newer, older]), .legs), 0.5, accuracy: 1e-12)

        let short = try session([.core], hoursAgo: 48, minutes: 30)
        let long = try session([.core], hoursAgo: 48, minutes: 45)
        XCTAssertEqual(try fraction(try map([short, long]), .core), 0.5, accuracy: 1e-12)
        XCTAssertEqual(try fraction(try map([long, short]), .core), 0.5, accuracy: 1e-12)
    }

    // MARK: - Where the curve runs out

    /// The boundary the floor draws, from both sides. A full session decays past 1% at
    /// 6.643 half-lives, so 6.5 half-lives (13 days) is still fatigue — 2^-6.5 =
    /// 0.01105 — and 7 half-lives (14 days) is not — 2^-7 = 0.0078125.
    func testTheFloorSeparatesThirteenDaysFromFourteen() throws {
        let thirteen = try map([try session([.back], hoursAgo: 13 * 24)])
        XCTAssertEqual(try fraction(thirteen, .back), 0.011048543456039806, accuracy: 1e-12)
        guard case .fatigued = thirteen[.back] else {
            return XCTFail("13 days is above the 1% floor and is still fatigue")
        }

        let fourteen = try map([try session([.back], hoursAgo: 14 * 24)])
        XCTAssertEqual(try fraction(fourteen, .back), 0.0078125, accuracy: 1e-12)
        guard case .fresh = fourteen[.back] else {
            return XCTFail("14 days is below the 1% floor and reads as fresh")
        }
    }

    /// The floor is a presentation boundary, not a clamp: below it the figure is still
    /// carried and still ordered, so a group worked a fortnight ago and one worked a
    /// year ago do not collapse into the same reading.
    func testAFigureBelowTheFloorIsStillCarriedAndStillOrders() throws {
        let readings = try map([
            try session([.back], hoursAgo: 14 * 24),
            try session([.legs], hoursAgo: 21 * 24)
        ])
        XCTAssertEqual(try fraction(readings, .back), 0.0078125, accuracy: 1e-12)
        XCTAssertGreaterThan(try fraction(readings, .back), try fraction(readings, .legs))
        XCTAssertGreaterThan(try fraction(readings, .legs), 0, "decayed is not gone")
        XCTAssertEqual(readings.mostFatiguedFirst.map(\.group), [.back, .legs])
    }

    /// **Fresh and never-logged are different facts and must not be read as one.** The
    /// group below was worked a fortnight ago; the app knows that, and says so with a
    /// figure. See `NoJudgementWithoutDataTests` for the other side of the pair.
    func testAFreshGroupIsNotTheSameStateAsAGroupNeverLogged() throws {
        let readings = try map([try session([.back], hoursAgo: 14 * 24)])
        XCTAssertTrue(readings[.back].isLogged)
        XCTAssertFalse(readings[.legs].isLogged)
        XCTAssertNotNil(readings[.back].fraction)
        XCTAssertNil(readings[.legs].fraction)
        XCTAssertNotEqual(
            MuscleFatigueCopy.detail(for: readings[.back]),
            MuscleFatigueCopy.detail(for: readings[.legs])
        )
    }

    // MARK: - The map is total

    func testEveryGroupHasAReadingAndTheUnworkedOnesSaySo() throws {
        let readings = try map([try session([.chest, .shoulders], hoursAgo: 12)])
        XCTAssertEqual(readings.ordered.map(\.group), MuscleGroup.allCases)
        XCTAssertEqual(readings.ordered.count, 6)
        XCTAssertEqual(readings.neverLogged, [.back, .arms, .legs, .core])
        XCTAssertFalse(readings.hasNoLoggedSessions)
        XCTAssertEqual(readings.computedAt, Self.now)
    }

    /// The map's own absence state: nothing logged at all is one sentence, not six
    /// empty regions.
    func testAMapWithNoSessionsAtAllSaysSoAsAWhole() throws {
        let readings = try map([])
        XCTAssertTrue(readings.hasNoLoggedSessions)
        XCTAssertEqual(readings.neverLogged, Set(MuscleGroup.allCases))
        XCTAssertTrue(readings.mostFatiguedFirst.isEmpty)
    }

    // MARK: - What a session may be

    /// `MuscleGroupEntry` forbids an empty set upstream; the calculator's own input
    /// refuses one too, so a caller building sessions by hand cannot introduce the
    /// state A22 designed out.
    func testASessionNamingNoGroupsIsRefused() {
        assertThrows(
            .empty,
            try MuscleFatigueSession(
                workoutID: UUID(),
                groups: [],
                endedAt: Self.now,
                durationSeconds: 2_700
            )
        )
    }

    /// A zero-duration session is refused rather than admitted as a zero weight: a
    /// fatigue figure of 0.0 reads as "fully recovered", which is a claim this record
    /// cannot support (MAX-175).
    func testASessionWithNoDurationIsRefusedRatherThanWeighedAsZero() {
        assertThrows(
            .outOfRange,
            try MuscleFatigueSession(
                workoutID: UUID(),
                groups: [.chest],
                endedAt: Self.now,
                durationSeconds: 0
            )
        )
    }

    // MARK: - The join with what is stored

    private func lift(
        id: UUID,
        durationSeconds: Double = 2_700,
        activityType: ActivityType = .traditionalStrengthTraining
    ) throws -> Workout {
        try Workout(
            id: id,
            activityType: activityType,
            start: Self.now.addingTimeInterval(-durationSeconds),
            end: Self.now,
            durationSeconds: durationSeconds,
            distanceMeters: nil,
            activeEnergyKilocalories: 300,
            hasRoute: false,
            source: .appleWatch,
            ingestedAt: Self.now
        )
    }

    private func log(_ workoutID: UUID, _ groups: Set<MuscleGroup>) throws -> MuscleGroupLog {
        try MuscleGroupLog(
            workoutID: workoutID,
            entries: [
                try MuscleGroupEntry(
                    id: UUID(),
                    workoutID: workoutID,
                    groups: groups,
                    recordedAt: Self.now
                )
            ]
        )
    }

    /// The join reads the entry in force and nothing else. A lift the athlete has not
    /// answered for contributes nothing — "I have not told you yet" is not "I trained
    /// nothing" (A22).
    func testALiftAwaitingAnEntryContributesNothing() throws {
        let answered = UUID()
        let awaiting = UUID()
        let readings = try MuscleFatigueCalculator.compute(
            try MuscleFatigueInput(
                now: Self.now,
                workouts: [try lift(id: answered), try lift(id: awaiting)],
                muscleGroupLogs: [answered: try log(answered, [.chest])]
            )
        )
        XCTAssertEqual(try fraction(readings, .chest), 1.0, accuracy: 1e-12)
        XCTAssertEqual(readings.neverLogged, [.back, .shoulders, .arms, .legs, .core])
    }

    /// Which workouts may carry groups is A22's rule, read off
    /// `MuscleGroupEntryData.resolve` rather than restated here — so a run carrying an
    /// entry (which the app has no path to create) still contributes nothing.
    func testARunIsNotASourceOfMuscleFatigueEvenIfAnEntryExistsForIt() throws {
        let run = UUID()
        let readings = try MuscleFatigueCalculator.compute(
            try MuscleFatigueInput(
                now: Self.now,
                workouts: [try lift(id: run, activityType: .running)],
                muscleGroupLogs: [run: try log(run, [.legs])]
            )
        )
        XCTAssertTrue(readings.hasNoLoggedSessions)
    }

    /// The latest entry is the answer in force: correcting *chest* to *chest and back*
    /// appends, and the map reads the correction.
    func testTheLatestEntryIsTheOneRead() throws {
        let workoutID = UUID()
        let corrected = try MuscleGroupLog(workoutID: workoutID)
            .recording(
                try MuscleGroupEntry(
                    id: UUID(),
                    workoutID: workoutID,
                    groups: [.chest],
                    recordedAt: Self.now.addingTimeInterval(-600)
                )
            )
            .recording(
                try MuscleGroupEntry(
                    id: UUID(),
                    workoutID: workoutID,
                    groups: [.chest, .back],
                    recordedAt: Self.now
                )
            )
        let readings = try MuscleFatigueCalculator.compute(
            try MuscleFatigueInput(
                now: Self.now,
                workouts: [try lift(id: workoutID)],
                muscleGroupLogs: [workoutID: corrected]
            )
        )
        XCTAssertEqual(try fraction(readings, .back), 1.0, accuracy: 1e-12)
        XCTAssertEqual(try fraction(readings, .chest), 1.0, accuracy: 1e-12)
    }

    /// A degenerate zero-duration record is skipped rather than thrown on: one
    /// malformed workout must not deny the athlete the other groups' figures.
    func testAZeroDurationRecordIsSkippedWithoutFailingTheWholeMap() throws {
        let degenerate = UUID()
        let good = UUID()
        let readings = try MuscleFatigueCalculator.compute(
            try MuscleFatigueInput(
                now: Self.now,
                workouts: [
                    try lift(id: degenerate, durationSeconds: 0),
                    try lift(id: good)
                ],
                muscleGroupLogs: [
                    degenerate: try log(degenerate, [.legs]),
                    good: try log(good, [.chest])
                ]
            )
        )
        XCTAssertEqual(try fraction(readings, .chest), 1.0, accuracy: 1e-12)
        XCTAssertFalse(readings[.legs].isLogged, "an unweighable record supports no figure")
    }

    // MARK: - Copy

    /// The two absences have two sentences, in one voice. Pinned so a later edit cannot
    /// quietly collapse them into one — which is the failure `MuscleFatigue` is written
    /// against.
    func testTheAbsenceCopyDistinguishesNeverLoggedFromFresh() {
        XCTAssertEqual(MuscleFatigueCopy.neverLoggedHeadline, "Not logged yet")
        XCTAssertEqual(
            MuscleFatigueCopy.neverLoggedDetail,
            "No session you've logged has named this group, so there's nothing to measure."
        )
        XCTAssertEqual(MuscleFatigueCopy.freshHeadline, "Fresh")
        XCTAssertEqual(
            MuscleFatigueCopy.freshDetail,
            "Enough time has passed since the last session that worked this group."
        )
        XCTAssertNotEqual(MuscleFatigueCopy.neverLoggedDetail, MuscleFatigueCopy.freshDetail)
    }

    /// The caption states the limit rather than gesturing at it. MAX-180 draws this
    /// sentence; the words are a product decision and are verified here (A20).
    func testTheCaptionNamesWhatTheModelCannotKnow() {
        XCTAssertTrue(MuscleFatigueCopy.modelCaption.contains("no sets, reps or weight"))
        XCTAssertTrue(MuscleFatigueCopy.modelCaption.contains("not how hard a session was"))
    }
}
