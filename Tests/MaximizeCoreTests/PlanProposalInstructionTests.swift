import Foundation
import XCTest
@testable import MaximizeCore

/// MAX-099. The instruction half: that the four-way split holds, that the retry says what
/// went wrong, and that the seam MAX-100 implements is drivable without a network call.
final class PlanProposalInstructionTests: XCTestCase {

    private let factSheet = """
        # Training — 20 Jul 2026 – 2 Aug 2026
        Plan version 3, heart-rate cap 150 bpm.
        """

    private func turns() throws -> [ChatTurn] {
        [
            try ChatTurn(speaker: .user, text: "16 weeks, half marathon on 15 November."),
            try ChatTurn(speaker: .assistant, text: "How many days a week can you run?"),
            try ChatTurn(speaker: .user, text: "Four. Never Mondays."),
        ]
    }

    // MARK: - The split

    func testTheInstructionCarriesTheTaskTheSchemaTheFactSheetAndTheTurns() throws {
        let instruction = try PlanProposalInstruction(factSheet: factSheet, turns: turns())

        XCTAssertEqual(instruction.task, PlanProposalInstruction.taskDescription)
        XCTAssertEqual(instruction.schema, PlanProposal.schemaDescription)
        XCTAssertEqual(instruction.factSheet, factSheet)
        XCTAssertEqual(instruction.turns.count, 3)
        XCTAssertFalse(instruction.isRetry)
    }

    /// §4.9's invariant, as an assertion: `task` and `schema` say what to do and what
    /// shape to answer in; `factSheet` is the only part carrying anything about the
    /// athlete. A transport can therefore cache the first two and reason about the third.
    func testOnlyTheFactSheetCarriesAnythingAboutTheAthlete() throws {
        let instruction = try PlanProposalInstruction(factSheet: factSheet, turns: turns())

        XCTAssertFalse(instruction.task.contains("150"))
        XCTAssertFalse(instruction.task.contains("Plan version"))
        XCTAssertFalse(instruction.schema.contains("150"))
        XCTAssertFalse(instruction.schema.contains("Plan version"))
        XCTAssertTrue(instruction.factSheet.contains("150"))
    }

    // MARK: - What it refuses

    func testAnEmptyTranscriptIsRefused() {
        assertThrows(.empty, try PlanProposalInstruction(factSheet: factSheet, turns: []))
    }

    /// The Messages API requires it, and a conversation opening with the assistant is
    /// nonsense to replay. Caught here rather than as a 400 from a live server.
    func testATranscriptOpeningWithTheAssistantIsRefused() throws {
        let assistantFirst = [
            try ChatTurn(speaker: .assistant, text: "Shall I draft a plan?"),
            try ChatTurn(speaker: .user, text: "Yes."),
        ]
        assertThrows(
            .inconsistent,
            try PlanProposalInstruction(factSheet: factSheet, turns: assistantFirst)
        )
    }

    func testAnEmptyFactSheetIsRefused() throws {
        assertThrows(.empty, try PlanProposalInstruction(factSheet: "   ", turns: turns()))
    }

    // MARK: - The one retry (§4.5)

    /// The retry carries the rejection's own words, so the model is told what was wrong
    /// rather than simply asked again. The wording lives here because it is prompt text;
    /// *how many* retries to make is MAX-101's policy.
    func testARetryTellsTheModelWhatWasRejected() throws {
        let failure = PlanProposalError.rejectedByAuthoring(
            .heartRateCapImplausible(permitted: HeartRateSample.plausibleBPM)
        )
        let retry = try PlanProposalInstruction(
            factSheet: factSheet,
            turns: turns(),
            retryingAfter: failure
        )

        XCTAssertTrue(retry.isRetry)
        XCTAssertTrue(retry.task.contains(failure.description))
        // Still the same task underneath — a retry is a correction, not a new brief.
        XCTAssertTrue(retry.task.hasPrefix(PlanProposalInstruction.taskDescription))
        XCTAssertEqual(retry.schema, PlanProposal.schemaDescription)
        XCTAssertEqual(retry.factSheet, factSheet)
    }

    /// Every rejection has to read as something a model can act on, because every one of
    /// them can end up in a retry — and, on the second failure, on the athlete's screen.
    func testEveryRejectionReadsAsASentence() {
        let failures: [PlanProposalError] = [
            .malformedResponse(reason: "expected a single JSON object and nothing else"),
            .missingField(name: "week"),
            .forbiddenField(name: "version"),
            .unknownSessionKind(name: "tempo"),
            .unknownWeekday(name: "moonday"),
            .unknownLiftKind(name: "easy"),
            .unknownMuscleGroup(name: "abs"),
            .weekIsNotOneSessionPerWeekday(missing: [.sunday], duplicated: [.monday]),
            .restDayIsNotEmpty(weekday: .monday),
            .liftRestDayIsNotEmpty(weekday: .tuesday),
            .malformedGoalTargetDay(value: "15 November"),
            .longRunArcIsEmpty,
            .longRunArcWeekNotPositive(week: 0),
            .longRunArcOutOfOrder(week: 2),
            .rejectedByAuthoring(.cadenceBandInverted),
            .rejectedByAuthoring(.minimumSessionDurationNotPositive),
        ]
        for failure in failures {
            let text = failure.description
            XCTAssertFalse(text.isEmpty, "\(failure) has no description")
            XCTAssertTrue(text.hasSuffix("."), "\(failure) does not read as a sentence: \(text)")
        }
    }

    /// The two vocabulary errors name the whole permitted set, so a retry does not have
    /// to guess — and they take it from the enums, so a new case appears in the message
    /// without anyone editing it.
    func testAVocabularyRejectionListsTheWholeVocabulary() {
        let kinds = PlanProposalError.unknownSessionKind(name: "tempo").description
        // `prescribable`: the rejection lists what the model may actually propose for the
        // **run** slot — never `.lift`, which has its own separate vocabulary and its
        // own error case (`unknownLiftKind`, MAX-141) rather than a spot in this one.
        for kind in ScheduledSessionKind.prescribable {
            XCTAssertTrue(kinds.contains(kind.rawValue), "the message omits \(kind.rawValue)")
        }
        let weekdays = PlanProposalError.unknownWeekday(name: "moonday").description
        for weekday in Weekday.allCases {
            XCTAssertTrue(weekdays.contains(PlanProposal.wireName(for: weekday)))
        }
    }

    /// The lift slot's own vocabulary error (MAX-141), checked the same way.
    func testALiftKindRejectionListsTheWholeLiftVocabulary() {
        let kinds = PlanProposalError.unknownLiftKind(name: "easy").description
        for kind in ScheduledSessionKind.liftPrescribable {
            XCTAssertTrue(kinds.contains(kind.rawValue), "the message omits \(kind.rawValue)")
        }
        let groups = PlanProposalError.unknownMuscleGroup(name: "abs").description
        for group in MuscleGroup.allCases {
            XCTAssertTrue(groups.contains(group.rawValue), "the message omits \(group.rawValue)")
        }
    }

    // MARK: - The transport seam

    /// A stand-in for MAX-100's client, kept in the test rather than shipped in
    /// `MaximizeCoreTestSupport`: the real client is that ticket's, and so is the fake
    /// its own tests will want. This exists to prove the protocol is drivable and that a
    /// reply round-trips through `PlanProposal.parse` without a network call.
    private final class StubPlanProposalModel: PlanProposalModelInvoking, @unchecked Sendable {
        private let response: String
        private(set) var received: [PlanProposalInstruction] = []

        init(response: String) {
            self.response = response
        }

        func reply(to instruction: PlanProposalInstruction) async throws -> String {
            received.append(instruction)
            return response
        }
    }

    func testAReplyFromTheSeamParsesIntoAProposal() async throws {
        let response = """
            {"heartRateCapBPM": 148, "cadenceLowStepsPerMinute": 165, \
            "cadenceHighStepsPerMinute": 172, "effectiveThresholdPoints": 70, \
            "marginalThresholdPoints": 45, "week": [\
            {"weekday": "monday", "kind": "rest", "liftKind": "rest"}, \
            {"weekday": "tuesday", "kind": "easy", "distanceMeters": 8000, "liftKind": "rest"}, \
            {"weekday": "wednesday", "kind": "hard", "note": "6 × 800m", "liftKind": "rest"}, \
            {"weekday": "thursday", "kind": "easy", "distanceMeters": 6000, "liftKind": "rest"}, \
            {"weekday": "friday", "kind": "rest", "liftKind": "rest"}, \
            {"weekday": "saturday", "kind": "easy", "distanceMeters": 6000, "liftKind": "rest"}, \
            {"weekday": "sunday", "kind": "long", "distanceMeters": 20000, "liftKind": "rest"}], \
            "longRunArc": [{"index": 1, "distanceMeters": 16000}], \
            "goalStatements": ["Half marathon"], "goalTargetDay": "2026-11-15"}
            """
        let model = StubPlanProposalModel(response: response)
        let instruction = try PlanProposalInstruction(factSheet: factSheet, turns: turns())

        let proposal = try PlanProposal.parse(await model.reply(to: instruction))

        XCTAssertEqual(proposal.heartRateCapBPM, 148)
        XCTAssertEqual(proposal[.monday], .rest)
        XCTAssertEqual(proposal[.sunday].distanceMeters, 20_000)
        XCTAssertEqual(model.received.count, 1)
        XCTAssertEqual(model.received.first?.factSheet, factSheet)
        XCTAssertEqual(model.received.first?.schema, PlanProposal.schemaDescription)
    }
}
