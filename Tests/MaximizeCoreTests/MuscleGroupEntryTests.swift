import Foundation
import XCTest
@testable import MaximizeCore

/// A22/MAX-145 — the athlete's own statement of what a strength session worked, and the
/// two distinctions the whole feature rests on: "I have not told you yet" is not "I
/// trained nothing", and changing an answer never destroys the previous one.
final class MuscleGroupEntryTests: XCTestCase {

    private func entry(
        id: UUID = Fixture.muscleGroupEntryID,
        workoutID: UUID = Fixture.workoutID,
        groups: Set<MuscleGroup>,
        at offsetSeconds: Double = 0
    ) throws -> MuscleGroupEntry {
        try MuscleGroupEntry(
            id: id,
            workoutID: workoutID,
            groups: groups,
            recordedAt: Fixture.at(offsetSeconds)
        )
    }

    // MARK: - "I trained nothing" is not representable

    /// The distinction A22 turns on. Absence of an entry is "not told yet" and it is
    /// what prompts; an entry saying zero groups would be a second spelling of the same
    /// state, and the prompt would then fire on a session already answered for.
    func testAnEntryCannotRecordZeroGroups() {
        XCTAssertThrowsError(try entry(groups: [])) { error in
            XCTAssertEqual(error as? DomainError, .empty(field: "MuscleGroupEntry.groups"))
        }
    }

    func testAnEntryRecordsEveryGroupTheAthleteNamed() throws {
        let recorded = try entry(groups: [.chest, .arms])
        XCTAssertEqual(recorded.groups, [.chest, .arms])
        XCTAssertEqual(recorded.workoutID, Fixture.workoutID)
        XCTAssertEqual(recorded.id, Fixture.muscleGroupEntryID)
    }

    /// `MuscleGroup.fullBody` is the whole set rather than a seventh case, so "I trained
    /// everything" has to be expressible as exactly that.
    func testFullBodyIsExpressible() throws {
        let recorded = try entry(groups: MuscleGroup.fullBody)
        XCTAssertEqual(recorded.groups.count, MuscleGroup.allCases.count)
    }

    // MARK: - Coding

    func testAnEntryRoundTripsThroughCoding() throws {
        let recorded = try entry(groups: [.legs, .core], at: 90)
        let data = try JSONEncoder().encode(recorded)
        XCTAssertEqual(try JSONDecoder().decode(MuscleGroupEntry.self, from: data), recorded)
    }

    /// The encoded form is a canonically ordered array, so an unchanged entry re-encodes
    /// to identical bytes — `PersistencePayload`'s requirement.
    func testTheEncodedGroupsAreCanonicallyOrdered() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let one = try encoder.encode(try entry(groups: [.core, .chest, .legs]))
        let other = try encoder.encode(try entry(groups: [.legs, .chest, .core]))
        XCTAssertEqual(one, other)
    }

    /// Decoding goes through the validating initializer, so a hand-edited or corrupted
    /// payload cannot introduce the state the type refuses to represent.
    func testDecodingRejectsAnEmptyGroupSet() throws {
        let payload = Data(
            #"{"id":"\#(Fixture.muscleGroupEntryID.uuidString)","workoutID":"\#(Fixture.workoutID.uuidString)","groups":[],"recordedAt":0}"#
                .utf8
        )
        XCTAssertThrowsError(try JSONDecoder().decode(MuscleGroupEntry.self, from: payload))
    }

    // MARK: - The log: additive, ordered, and absence-first

    func testAnEmptyLogIsAwaitingTheAthlete() throws {
        let log = try MuscleGroupLog(workoutID: Fixture.workoutID)
        XCTAssertTrue(log.isAwaitingEntry)
        XCTAssertNil(log.current)
        XCTAssertNil(log.currentGroups)
    }

    func testTheLatestEntryIsTheAnswerInForce() throws {
        let log = try MuscleGroupLog(
            workoutID: Fixture.workoutID,
            entries: [
                try entry(groups: [.chest], at: 0),
                try entry(id: UUID(), groups: [.chest, .shoulders], at: 60),
            ]
        )
        XCTAssertFalse(log.isAwaitingEntry)
        XCTAssertEqual(log.currentGroups, [.chest, .shoulders])
    }

    /// D8's discipline, applied to an input: correcting an answer appends and the
    /// earlier answer stays on file. This is the assertion that would fail if a later
    /// ticket "simplified" the log into a single stored set.
    func testRecordingAChangeKeepsTheEarlierAnswer() throws {
        let first = try entry(groups: [.legs], at: 0)
        let corrected = try entry(id: UUID(), groups: [.legs, .core], at: 120)

        let log = try MuscleGroupLog(workoutID: Fixture.workoutID, entries: [first])
            .recording(corrected)

        XCTAssertEqual(log.entries.count, 2)
        XCTAssertEqual(log.entries.first, first)
        XCTAssertEqual(log.currentGroups, [.legs, .core])
    }

    func testALogRejectsAnEntryBelongingToAnotherWorkout() throws {
        XCTAssertThrowsError(
            try MuscleGroupLog(
                workoutID: Fixture.workoutID,
                entries: [try entry(workoutID: Fixture.otherWorkoutID, groups: [.back])]
            )
        )
    }

    /// "The latest one wins" is only a rule if the entries are actually ordered.
    func testALogRejectsOutOfOrderEntries() throws {
        XCTAssertThrowsError(
            try MuscleGroupLog(
                workoutID: Fixture.workoutID,
                entries: [
                    try entry(groups: [.chest], at: 120),
                    try entry(id: UUID(), groups: [.back], at: 0),
                ]
            )
        ) { error in
            XCTAssertEqual(error as? DomainError, .outOfOrder(field: "MuscleGroupLog.entries", index: 1))
        }
    }
}
