import Foundation
import XCTest
@testable import MaximizeCore

/// A11 / §3.4: a thread's subject, and the frozen scope a training subject carries.
final class ChatSubjectTests: XCTestCase {

    // MARK: - TrainingScope

    func testAnInvertedScopeIsRejected() throws {
        assertThrows(
            .inconsistent,
            try TrainingScope(from: Fixture.day(2026, 8, 31), through: Fixture.day(2026, 8, 1))
        )
    }

    /// A one-day scope is legal — "how was today" is a question.
    func testASingleDayScopeIsAllowed() throws {
        let day = try Fixture.day(2026, 8, 3)
        let scope = try TrainingScope(from: day, through: day)
        XCTAssertEqual(scope.from, day)
        XCTAssertEqual(scope.through, day)
    }

    /// §3.4: the scope is resolved to absolute days at creation. The interval is a rule
    /// and a rule re-resolves; what the thread keeps must not.
    func testResolvingAnIntervalFreezesItsBounds() throws {
        let august = try TrendInterval.thisMonth(today: Fixture.day(2026, 8, 17))
        let scope = try TrainingScope(resolving: august)

        XCTAssertEqual(scope.from, try Fixture.day(2026, 8, 1))
        XCTAssertEqual(scope.through, try Fixture.day(2026, 8, 31))

        // The interval moving on does not move the scope: the thread is holding days,
        // not the rule that produced them.
        let september = try august.next()
        XCTAssertEqual(september.from, try Fixture.day(2026, 9, 1))
        XCTAssertEqual(scope.from, try Fixture.day(2026, 8, 1))
    }

    func testAWeekIntervalResolvesToItsMondayAndSunday() throws {
        let week = try TrendInterval.thisWeek(today: Fixture.day(2026, 8, 5))
        let scope = try TrainingScope(resolving: week)
        XCTAssertEqual(scope.from, week.from)
        XCTAssertEqual(scope.through, week.through)
        XCTAssertEqual(scope.from.weekday, .monday)
        XCTAssertEqual(scope.through.weekday, .sunday)
    }

    // MARK: - The scope's label (§3.6(b): the window is stated)

    func testScopeLabelStatesTheNarrowestUnambiguousWindow() throws {
        XCTAssertEqual(
            try Fixture.scope(from: (2026, 8, 3), through: (2026, 8, 3)).label,
            "3 Aug 2026"
        )
        XCTAssertEqual(
            try Fixture.scope(from: (2026, 8, 3), through: (2026, 8, 9)).label,
            "3 – 9 Aug 2026"
        )
        XCTAssertEqual(
            try Fixture.scope(from: (2026, 7, 28), through: (2026, 8, 3)).label,
            "28 Jul – 3 Aug 2026"
        )
    }

    /// The case worth having: a thread opened in the first week of January is
    /// permanently about a range that straddles two years, and "28 Dec – 3 Jan" would be
    /// read as the wrong December.
    func testScopeLabelSpellsOutBothYearsAcrossAYearBoundary() throws {
        XCTAssertEqual(
            try Fixture.scope(from: (2025, 12, 28), through: (2026, 1, 3)).label,
            "28 Dec 2025 – 3 Jan 2026"
        )
    }

    // MARK: - The subject

    func testKindAndPayloadAccessorsAgreeWithTheCase() throws {
        let workout = ChatSubject.workout(Fixture.workoutID)
        XCTAssertEqual(workout.kind, .workout)
        XCTAssertEqual(workout.workoutID, Fixture.workoutID)
        XCTAssertNil(workout.trainingScope)

        let scope = try Fixture.scope(from: (2026, 8, 1), through: (2026, 8, 31))
        let training = ChatSubject.training(scope)
        XCTAssertEqual(training.kind, .training)
        XCTAssertNil(training.workoutID)
        XCTAssertEqual(training.trainingScope, scope)
    }

    /// The subject is what decides which pile of the athlete's data enters a prompt, so
    /// two subjects that differ in *any* respect must not be treated as the same
    /// conversation — including two windows that merely overlap.
    func testEqualityAndHashingDistinguishEverySubject() throws {
        let august = ChatSubject.training(try Fixture.scope(from: (2026, 8, 1), through: (2026, 8, 31)))
        let augustAgain = ChatSubject.training(try Fixture.scope(from: (2026, 8, 1), through: (2026, 8, 31)))
        let shorterAugust = ChatSubject.training(try Fixture.scope(from: (2026, 8, 1), through: (2026, 8, 30)))
        let september = ChatSubject.training(try Fixture.scope(from: (2026, 9, 1), through: (2026, 9, 30)))
        let run = ChatSubject.workout(Fixture.workoutID)
        let otherRun = ChatSubject.workout(Fixture.otherWorkoutID)

        XCTAssertEqual(august, augustAgain)
        XCTAssertEqual(august.hashValue, augustAgain.hashValue)
        XCTAssertNotEqual(august, shorterAugust)
        XCTAssertNotEqual(august, september)
        XCTAssertNotEqual(run, otherRun)
        XCTAssertNotEqual(run, august)

        // Usable as a dictionary key — which is how a thread list groups by subject.
        let bySubject: [ChatSubject: String] = [august: "August", september: "September", run: "one run"]
        XCTAssertEqual(bySubject[augustAgain], "August")
        XCTAssertEqual(bySubject.count, 3)
    }

    // MARK: - The wire form (what MAX-093 splits into columns)

    func testBothSubjectsRoundTripThroughJSON() throws {
        let workout = ChatSubject.workout(Fixture.workoutID)
        let training = ChatSubject.training(try Fixture.scope(from: (2026, 8, 1), through: (2026, 8, 31)))
        XCTAssertEqual(try roundTripped(workout), workout)
        XCTAssertEqual(try roundTripped(training), training)
    }

    /// The discriminator and the field names are what MAX-093 will store as columns, so
    /// they are pinned rather than left to whatever the encoder happens to emit.
    func testTheEncodedFormIsTaggedWithAStableDiscriminator() throws {
        let training = ChatSubject.training(try Fixture.scope(from: (2026, 8, 1), through: (2026, 8, 31)))
        let data = try JSONEncoder().encode(CodableBox(wrapped: training))
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertTrue(text.contains("\"kind\":\"training\""), text)
        XCTAssertTrue(text.contains("2026-08-01"), "days travel in CalendarDay's own wire format: \(text)")
        XCTAssertTrue(text.contains("2026-08-31"), text)

        let workoutText = try XCTUnwrap(String(
            data: try JSONEncoder().encode(CodableBox(wrapped: ChatSubject.workout(Fixture.workoutID))),
            encoding: .utf8
        ))
        XCTAssertTrue(workoutText.contains("\"kind\":\"workout\""), workoutText)
    }

    /// A decoder that accepted an inverted range would produce a scope every consumer
    /// downstream reads as empty — a corrupt payload has to fail loudly at the boundary.
    func testDecodingAnInvertedScopeIsRejected() throws {
        let json = Data("""
            {"wrapped":{"kind":"training","from":"2026-08-31","through":"2026-08-01"}}
            """.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(CodableBox<ChatSubject>.self, from: json))
    }

    func testDecodingAnUnknownSubjectKindIsRejected() throws {
        let json = Data("""
            {"wrapped":{"kind":"nutrition"}}
            """.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(CodableBox<ChatSubject>.self, from: json))
    }

    /// A12 makes adding a subject an amendment, not a ticket. This fails the moment a
    /// third case appears, which is the point: it is a prompt to go and write the
    /// amendment, not an obstacle.
    func testTheSubjectSetIsClosedAtTwo() {
        XCTAssertEqual(ChatSubjectKind.allCases.count, 2)
    }

    // MARK: - The thread-list glyph (§2.3)

    /// "A run glyph for a workout thread, a chart glyph for a training thread" — the two
    /// have to differ, and neither is the empty string a view would silently render as
    /// nothing.
    func testEveryKindHasItsOwnNonEmptyGlyph() {
        let names = Set(ChatSubjectKind.allCases.map(\.glyphSystemImageName))
        XCTAssertEqual(names.count, ChatSubjectKind.allCases.count, "each kind draws a distinct glyph")
        XCTAssertTrue(names.allSatisfy { !$0.isEmpty })
    }

    func testEveryKindHasItsOwnAccessibilityLabel() {
        let labels = Set(ChatSubjectKind.allCases.map(\.accessibilityKindLabel))
        XCTAssertEqual(labels.count, ChatSubjectKind.allCases.count)
        XCTAssertTrue(labels.allSatisfy { !$0.isEmpty })
    }
}
