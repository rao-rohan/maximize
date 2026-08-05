import Foundation
import XCTest
@testable import MaximizeCore

final class ChatThreadTests: XCTestCase {
    private let threadID = UUID()

    private func message(_ role: ChatRole, _ content: String, at offsetSeconds: Double) throws -> ChatMessage {
        try ChatMessage(
            id: UUID(),
            role: role,
            content: content,
            timestamp: Fixture.epoch.addingTimeInterval(offsetSeconds)
        )
    }

    func testMessagesMustSaySomething() throws {
        assertThrows(.empty, try message(.user, "", at: 0))
        assertThrows(.empty, try message(.user, "   \n ", at: 0))
    }

    /// A thread that goes backwards in time renders as nonsense and, worse, misleads
    /// the model when it is replayed as context.
    func testRejectsMessagesOutOfTimeOrder() throws {
        let messages = [
            try message(.user, "Why did my HR drift at mile 3?", at: 60),
            try message(.assistant, "Your second half averaged 8 bpm higher.", at: 30),
        ]
        assertThrows(.outOfOrder, try ChatThread(id: threadID, workoutID: Fixture.workoutID, messages: messages))
    }

    func testAppendingRejectsATurnFromThePast() throws {
        let thread = try ChatThread(
            id: threadID,
            workoutID: Fixture.workoutID,
            messages: [try message(.user, "Why did my HR drift?", at: 60)]
        )
        assertThrows(.outOfOrder, try thread.appending(message(.assistant, "Because…", at: 30)))
        XCTAssertNoThrow(try thread.appending(message(.assistant, "Because…", at: 90)))
    }

    func testAppendingReturnsANewThreadAndLeavesTheOldOneAlone() throws {
        let thread = try ChatThread(id: threadID, workoutID: Fixture.workoutID)
        let extended = try thread.appending(message(.user, "How was that run?", at: 0))
        XCTAssertEqual(thread.messages.count, 0)
        XCTAssertEqual(extended.messages.count, 1)
        XCTAssertEqual(extended.id, thread.id)
    }

    /// The context-builder seed (FR-2.1) is part of the thread but is not a bubble.
    func testSeedContextIsNotAVisibleTurn() throws {
        let thread = try ChatThread(
            id: threadID,
            workoutID: Fixture.workoutID,
            messages: [
                try message(.system, "Workout context: 10km easy, avg HR 142…", at: 0),
                try message(.user, "Was that on plan?", at: 10),
            ]
        )
        XCTAssertEqual(thread.messages.count, 2)
        XCTAssertEqual(thread.visibleMessages.count, 1)
        XCTAssertEqual(thread.visibleMessages.first?.role, .user)
        XCTAssertFalse(thread.isEmpty)
    }

    func testSimultaneousTurnsAreAllowed() throws {
        let messages = [
            try message(.user, "Ping", at: 60),
            try message(.assistant, "Pong", at: 60),
        ]
        XCTAssertNoThrow(try ChatThread(id: threadID, workoutID: Fixture.workoutID, messages: messages))
    }

    func testRoundTripsThroughJSON() throws {
        let thread = try ChatThread(
            id: threadID,
            workoutID: Fixture.workoutID,
            messages: [try message(.user, "Was that on plan?", at: 0)]
        )
        XCTAssertEqual(try roundTripped(thread), thread)
    }
}

final class SettingsTests: XCTestCase {
    func testRestDayBudgetCannotExceedAWeek() {
        assertThrows(.outOfRange, try RestDayBudget(daysPerWeek: 8))
        assertThrows(.outOfRange, try RestDayBudget(daysPerWeek: -1))
    }

    func testRestDayBudgetAcceptsItsWholeRange() throws {
        XCTAssertEqual(try RestDayBudget(daysPerWeek: 0).daysPerWeek, 0)
        XCTAssertEqual(try RestDayBudget(daysPerWeek: 7).daysPerWeek, 7)
        XCTAssertEqual(RestDayBudget.standard.daysPerWeek, 1)
    }

    func testDecodingRejectsAnImpossibleBudget() throws {
        struct Box: Decodable {
            let wrapped: RestDayBudget
        }
        let data = try XCTUnwrap(#"{"wrapped":9}"#.data(using: .utf8))
        assertThrows(.outOfRange, try JSONDecoder().decode(Box.self, from: data))
    }

    /// Storage is metres everywhere; the unit is a display preference only.
    func testDistanceUnitConvertsFromMetres() {
        XCTAssertEqual(DistanceUnit.kilometers.converted(fromMeters: 5_000), 5, accuracy: 0.0001)
        XCTAssertEqual(DistanceUnit.miles.converted(fromMeters: 1_609.344), 1, accuracy: 0.0001)
    }

    /// MAX-080 drives a plan's distances from controls the athlete steps in their own
    /// unit, so the conversion has to round-trip exactly.
    func testDistanceUnitConvertsBackToMetres() {
        for unit in DistanceUnit.allCases {
            XCTAssertEqual(unit.meters(fromConverted: 5), 5 * unit.metersPerUnit, accuracy: 0.0001)
            XCTAssertEqual(
                unit.converted(fromMeters: unit.meters(fromConverted: 13.5)),
                13.5,
                accuracy: 0.0001
            )
        }
    }

    func testDefaultsFollowTheDesignDirection() {
        let settings = AppSettings.standard
        XCTAssertEqual(settings.appearance, .dark, "FR-4.3 is dark-first")
        XCTAssertEqual(settings.restDayBudget, RestDayBudget.standard)
        XCTAssertFalse(settings.reducesTransparency)
        XCTAssertFalse(settings.increasesContrast)
        XCTAssertFalse(settings.reducesMotion)
    }

    func testRoundTripsThroughJSON() throws {
        let settings = AppSettings(
            restDayBudget: try RestDayBudget(daysPerWeek: 2),
            distanceUnit: .kilometers,
            appearance: .system,
            reducesTransparency: true,
            increasesContrast: true,
            reducesMotion: true
        )
        XCTAssertEqual(try roundTripped(settings), settings)
    }

    // MARK: - AppearancePreference → ResolvedColorScheme (MAX-086)

    /// `.system` must impose nothing, not default to the app's dark-first design.
    /// `nil` here is what tells SwiftUI's `.preferredColorScheme` to leave the OS's
    /// choice alone — a `.dark` fallback would silently override an athlete who
    /// deliberately asked to follow the system.
    func testSystemImposesNoColorScheme() {
        XCTAssertNil(AppearancePreference.system.resolvedColorScheme)
    }

    func testLightResolvesToLight() {
        XCTAssertEqual(AppearancePreference.light.resolvedColorScheme, .light)
    }

    func testDarkResolvesToDark() {
        XCTAssertEqual(AppearancePreference.dark.resolvedColorScheme, .dark)
    }
}

final class RestDayOverrideTests: XCTestCase {
    /// A6 makes conversion automatic, but the record still distinguishes "the budget
    /// was spent on a missed day" from "this was simply a rest day" — A6 warns the
    /// heuristic may need revisiting, and that needs the distinction preserved.
    func testConversionProvenanceIsRecorded() throws {
        let converted = RestDayOverride(
            date: try Fixture.day(2026, 1, 7),
            convertedFromMissed: true,
            createdAt: Fixture.epoch
        )
        XCTAssertTrue(converted.convertedFromMissed)
        XCTAssertEqual(converted.id, converted.date)
        XCTAssertEqual(try roundTripped(converted), converted)
    }
}
