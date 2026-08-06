import Foundation
import XCTest
@testable import MaximizeCore

/// MAX-099. The half of conversational plan authoring CI can prove: that a well-formed
/// reply parses, that each malformed one is refused for the right specific reason, that
/// the schema cannot go stale behind the enums it describes, and — the property the whole
/// design rests on — that anything which parses is something
/// `PlanAuthoringSession.plan(from:effectiveFrom:)` will accept.
final class PlanProposalTests: XCTestCase {

    // MARK: - Fixtures

    private func day(_ text: String) throws -> CalendarDay {
        try CalendarDay(iso8601: text)
    }

    /// The seven days of a plausible proposal, as JSON fragments, so a test can replace
    /// exactly one of them and leave the rest alone.
    private static let weekEntries = [
        #"{"weekday": "monday", "kind": "rest", "liftKind": "rest"}"#,
        #"{"weekday": "tuesday", "kind": "easy", "distanceMeters": 8000, "liftKind": "rest"}"#,
        #"{"weekday": "wednesday", "kind": "hard", "note": "6 × 800m", "liftKind": "rest"}"#,
        #"{"weekday": "thursday", "kind": "easy", "distanceMeters": 8000, "liftKind": "rest"}"#,
        #"{"weekday": "friday", "kind": "rest", "liftKind": "rest"}"#,
        #"{"weekday": "saturday", "kind": "other", "note": "Strength", "liftKind": "rest"}"#,
        #"{"weekday": "sunday", "kind": "long", "distanceMeters": 18000, "liftKind": "rest"}"#,
    ]

    /// A reply the model could plausibly send, with named fields overridable one at a
    /// time. Every malformed-shape test below is this reply with one thing wrong, so a
    /// failure names the difference rather than the whole payload.
    private func reply(
        heartRateCapBPM: String = "150",
        cadenceLow: String = "165",
        cadenceHigh: String = "170",
        effective: String = "70",
        marginal: String = "45",
        week: [String] = PlanProposalTests.weekEntries,
        longRunArc: String = #"[{"index": 1, "distanceMeters": 14000}, {"index": 2, "distanceMeters": 16000}]"#,
        goalStatements: String = #"["Sub-1:45 half marathon", "Stay under the cap on easy days"]"#,
        goalTargetDay: String? = #""2026-11-15""#,
        extra: String = ""
    ) -> String {
        var fields = [
            #""heartRateCapBPM": \#(heartRateCapBPM)"#,
            #""cadenceLowStepsPerMinute": \#(cadenceLow)"#,
            #""cadenceHighStepsPerMinute": \#(cadenceHigh)"#,
            #""effectiveThresholdPoints": \#(effective)"#,
            #""marginalThresholdPoints": \#(marginal)"#,
            #""week": [\#(week.joined(separator: ", "))]"#,
            #""longRunArc": \#(longRunArc)"#,
            #""goalStatements": \#(goalStatements)"#,
        ]
        if let goalTargetDay {
            fields.append(#""goalTargetDay": \#(goalTargetDay)"#)
        }
        if !extra.isEmpty {
            fields.append(extra)
        }
        return "{\(fields.joined(separator: ", "))}"
    }

    private func assertParseFails(
        _ raw: String,
        _ expected: PlanProposalError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try PlanProposal.parse(raw), "", file: file, line: line) { error in
            XCTAssertEqual(error as? PlanProposalError, expected, file: file, line: line)
        }
    }

    // MARK: - A well-formed reply

    func testAWellFormedReplyParsesEveryField() throws {
        let proposal = try PlanProposal.parse(reply())

        XCTAssertEqual(proposal.heartRateCapBPM, 150)
        XCTAssertEqual(proposal.cadenceLowStepsPerMinute, 165)
        XCTAssertEqual(proposal.cadenceHighStepsPerMinute, 170)
        XCTAssertEqual(proposal.effectiveThresholdPoints, 70)
        XCTAssertEqual(proposal.marginalThresholdPoints, 45)

        XCTAssertEqual(proposal.week.count, 7)
        XCTAssertEqual(proposal[.tuesday].kind, .easy)
        XCTAssertEqual(proposal[.tuesday].distanceMeters, 8000)
        XCTAssertEqual(proposal[.wednesday].kind, .hard)
        XCTAssertEqual(proposal[.wednesday].note, "6 × 800m")
        XCTAssertNil(proposal[.wednesday].distanceMeters)
        XCTAssertEqual(proposal[.monday], .rest)

        XCTAssertEqual(proposal.longRunArc.map(\.index), [1, 2])
        XCTAssertEqual(proposal.longRunArc.map(\.distanceMeters), [14_000, 16_000])

        XCTAssertEqual(proposal.goals.statements.count, 2)
        XCTAssertEqual(proposal.goals.targetDay, try day("2026-11-15"))
    }

    /// Monday-first, whatever order the model listed the week in — `WeeklyTemplate` and
    /// `PlanDraft.week` both canonicalise, and two proposals prescribing the same week
    /// should be one value.
    func testTheWeekIsCanonicalisedMondayFirst() throws {
        let shuffled = Array(PlanProposalTests.weekEntries.reversed())
        let proposal = try PlanProposal.parse(reply(week: shuffled))

        XCTAssertEqual(proposal.week.map(\.weekday), Weekday.allCases.sorted())
        XCTAssertEqual(proposal, try PlanProposal.parse(reply()))
    }

    /// Tolerant about formatting: a fenced object is the same object, and refusing one
    /// would burn the single permitted retry on punctuation.
    func testACodeFencedReplyParses() throws {
        let fenced = "```json\n\(reply())\n```"
        XCTAssertEqual(try PlanProposal.parse(fenced), try PlanProposal.parse(reply()))
    }

    /// The same tolerance `ScoreProposal.parse` has, pinned side by side because the two
    /// envelope handlers are, for now, separate copies.
    func testTheTwoModelParsersTolerateTheSameFormatting() throws {
        let score = #"{"score": 50, "rationale": "Fine."}"#
        let wrappings: [(String) -> String] = [
            { $0 },
            { "```\n\($0)\n```" },
            { "```json\n\($0)\n```" },
            { "  \($0)\n" },
        ]
        for wrap in wrappings {
            XCTAssertNoThrow(try ScoreProposal.parse(wrap(score)))
            XCTAssertNoThrow(try PlanProposal.parse(wrap(reply())))
        }
    }

    /// Strict about content: prose around the object is not salvaged by hunting for the
    /// first `{`, because a model that explained itself did not follow the contract and
    /// digging the object out hides that from the retry logic.
    func testProseAroundTheObjectIsRefusedRatherThanSalvaged() {
        assertParseFails(
            "Here is the plan you asked for:\n\(reply())",
            .malformedResponse(reason: "expected a single JSON object and nothing else")
        )
    }

    func testAReplyThatIsNotJSONIsRefused() {
        assertParseFails(
            "I can't draft that.",
            .malformedResponse(reason: "expected a single JSON object and nothing else")
        )
    }

    /// Weakly typed on the wire, in `ScoreProposal`'s spirit: `"150"` is a string where a
    /// number belongs, and the reply is refused as malformed rather than coerced.
    func testAStringWhereANumberBelongsIsRefusedNotCoerced() {
        XCTAssertThrowsError(try PlanProposal.parse(reply(heartRateCapBPM: #""150""#))) { error in
            guard let planError = error as? PlanProposalError,
                  case .malformedResponse = planError
            else {
                return XCTFail("expected malformedResponse, got \(error)")
            }
            // The reason names the field, so a retry knows what to fix — and names
            // nothing else, so the error stays safe wherever it is logged.
            XCTAssertTrue(planError.description.contains("heartRateCapBPM"))
        }
    }

    // MARK: - Missing and forbidden fields

    func testAnAbsentFieldIsNamed() {
        assertParseFails(
            #"{"cadenceLowStepsPerMinute": 165}"#,
            .missingField(name: "heartRateCapBPM")
        )
    }

    func testANullFieldReadsAsAnAbsentOne() {
        assertParseFails(
            reply(heartRateCapBPM: "null"),
            .missingField(name: "heartRateCapBPM")
        )
    }

    func testAnAbsentWeekIsNamed() {
        assertParseFails(
            #"{"heartRateCapBPM": 150, "cadenceLowStepsPerMinute": 165, "cadenceHighStepsPerMinute": 170, "effectiveThresholdPoints": 70, "marginalThresholdPoints": 45}"#,
            .missingField(name: "week")
        )
    }

    /// §4.4. A version number anything can propose is a back-dated version waiting to
    /// happen, so it is refused rather than dropped — see `forbiddenField` for why
    /// silence is the worse outcome.
    func testTheModelMayNotProposeAVersionOrAStartDate() {
        assertParseFails(reply(extra: #""version": 3"#), .forbiddenField(name: "version"))
        assertParseFails(
            reply(extra: #""effectiveFrom": "2026-01-01""#),
            .forbiddenField(name: "effectiveFrom")
        )
    }

    /// §4.4's third exclusion. A hallucinated band does not produce a visibly wrong plan;
    /// it produces one that looks fine and quietly mis-scores for sixteen weeks.
    func testTheModelMayNotProposeRubricBands() {
        assertParseFails(reply(extra: #""rubricBands": []"#), .forbiddenField(name: "rubricBands"))
        assertParseFails(reply(extra: #""bands": []"#), .forbiddenField(name: "bands"))
        assertParseFails(reply(extra: #""rubric": {}"#), .forbiddenField(name: "rubric"))
    }

    // MARK: - Vocabulary

    func testAnUnknownSessionKindIsRefusedByName() {
        let week = PlanProposalTests.weekEntries.map {
            $0.replacingOccurrences(of: #""kind": "hard""#, with: #""kind": "tempo""#)
        }
        assertParseFails(reply(week: week), .unknownSessionKind(name: "tempo"))
    }

    func testAnUnknownWeekdayIsRefusedByName() {
        let week = PlanProposalTests.weekEntries.map {
            $0.replacingOccurrences(of: #""weekday": "monday""#, with: #""weekday": "moonday""#)
        }
        assertParseFails(reply(week: week), .unknownWeekday(name: "moonday"))
    }

    /// The leak this ticket closes: `.lift` is a real `ScheduledSessionKind` now that
    /// `liftKind` gives a model a legitimate reason to type the word, so `"kind": "lift"`
    /// in the **run** slot has to be caught rather than silently decoding — a lift
    /// judged as the day's run ask is the exact cross-discipline confusion A17 exists to
    /// prevent. See `PlanProposal.sessionKind(named:)`.
    func testALiftProposedIntoTheRunSlotIsRefused() {
        let week = PlanProposalTests.weekEntries.map {
            $0.replacingOccurrences(of: #""kind": "hard""#, with: #""kind": "lift""#)
        }
        assertParseFails(reply(week: week), .unknownSessionKind(name: "lift"))
    }

    /// Formatting, not content: capitalisation is the model's business.
    func testWeekdayAndKindNamesAreCaseInsensitive() throws {
        let week = PlanProposalTests.weekEntries.map {
            $0.replacingOccurrences(of: #""weekday": "monday""#, with: #""weekday": "Monday""#)
                .replacingOccurrences(of: #""kind": "easy""#, with: #""kind": "EASY""#)
        }
        XCTAssertEqual(try PlanProposal.parse(reply(week: week)), try PlanProposal.parse(reply()))
    }

    // MARK: - The week

    /// Unrepresentable in a `PlanDraft`, whose initializer fills every weekday — so the
    /// door has no case for it and this boundary must.
    func testAWeekMissingADayIsRefusedAndSaysWhich() {
        let week = PlanProposalTests.weekEntries.filter { !$0.contains("sunday") }
        assertParseFails(
            reply(week: week),
            .weekIsNotOneSessionPerWeekday(missing: [.sunday], duplicated: [])
        )
    }

    func testAWeekNamingADayTwiceIsRefusedAndSaysWhich() {
        var week = PlanProposalTests.weekEntries
        week[6] = #"{"weekday": "monday", "kind": "long", "distanceMeters": 18000, "liftKind": "rest"}"#
        assertParseFails(
            reply(week: week),
            .weekIsNotOneSessionPerWeekday(missing: [.sunday], duplicated: [.monday])
        )
    }

    /// A draft clears the distance when a day becomes rest, because a screen sets the two
    /// with separate taps. A proposal arrives whole, so there is nothing to protect and
    /// nothing to clear on the athlete's behalf — the model said two contradictory things.
    func testARestDayCarryingWorkIsRefusedRatherThanTrimmed() {
        var week = PlanProposalTests.weekEntries
        week[0] = #"{"weekday": "monday", "kind": "rest", "distanceMeters": 5000, "liftKind": "rest"}"#
        assertParseFails(reply(week: week), .restDayIsNotEmpty(weekday: .monday))

        week[0] = #"{"weekday": "monday", "kind": "rest", "note": "Easy shakeout if I feel good", "liftKind": "rest"}"#
        assertParseFails(reply(week: week), .restDayIsNotEmpty(weekday: .monday))
    }

    /// The door's own vocabulary, because the door's own rule.
    func testAZeroDistanceOnAScheduledDayIsRejectedInTheDoorsWords() {
        var week = PlanProposalTests.weekEntries
        week[1] = #"{"weekday": "tuesday", "kind": "easy", "distanceMeters": 0, "liftKind": "rest"}"#
        assertParseFails(
            reply(week: week),
            .rejectedByAuthoring(.scheduledDistanceNotPositive(weekday: .tuesday))
        )
    }

    /// A session with no distance is legal — `ScheduledSession` documents "6 × 800m" as
    /// exactly this case — so an omitted distance must not read as a zero one.
    func testAnOmittedDistanceIsNotAZeroDistance() throws {
        let proposal = try PlanProposal.parse(reply())
        XCTAssertNil(proposal[.wednesday].distanceMeters)
    }

    // MARK: - The lift slot (MAX-141)

    /// A weekday that prescribes both a run and a lift round-trips: the ticket's own
    /// acceptance criterion, and the normal case per LIFTING-SPEC §5 ("a day prescribing
    /// both is the normal case, not an edge case").
    func testADayPrescribingBothSlotsRoundTrips() throws {
        var week = PlanProposalTests.weekEntries
        week[1] = #"{"weekday": "tuesday", "kind": "easy", "distanceMeters": 8000, "liftKind": "lift", "liftMuscleGroups": ["legs", "core"]}"#
        let proposal = try PlanProposal.parse(reply(week: week))

        XCTAssertEqual(proposal[.tuesday].kind, .easy)
        XCTAssertEqual(proposal[.tuesday].distanceMeters, 8000)
        XCTAssertEqual(proposal.liftSession(for: .tuesday).kind, .lift)
        XCTAssertEqual(proposal.liftSession(for: .tuesday).muscleGroups, [.legs, .core])

        let data = try JSONEncoder().encode(proposal)
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertEqual(try PlanProposal.parse(text), proposal)
    }

    /// A day that prescribes a lift and nothing else — the run slot stays rest.
    func testADayPrescribingALiftOnlyParses() throws {
        var week = PlanProposalTests.weekEntries
        week[4] = #"{"weekday": "friday", "kind": "rest", "liftKind": "lift", "liftMuscleGroups": ["chest"]}"#
        let proposal = try PlanProposal.parse(reply(week: week))

        XCTAssertEqual(proposal[.friday], .rest)
        XCTAssertEqual(proposal.liftSession(for: .friday).kind, .lift)
        XCTAssertEqual(proposal.liftSession(for: .friday).muscleGroups, [.chest])
    }

    /// A lift with no muscle groups named is a real, legal statement — "lift on Tuesday,
    /// groups unstated" — not an error. `ScheduledSession.muscleGroups`' own doc makes
    /// this the honest reading: rest and "a lift with no groups named" stay distinct.
    func testALiftWithNoMuscleGroupsNamedIsAccepted() throws {
        var week = PlanProposalTests.weekEntries
        week[1] = #"{"weekday": "tuesday", "kind": "easy", "distanceMeters": 8000, "liftKind": "lift"}"#
        let proposal = try PlanProposal.parse(reply(week: week))

        XCTAssertEqual(proposal.liftSession(for: .tuesday).kind, .lift)
        XCTAssertTrue(proposal.liftSession(for: .tuesday).muscleGroups.isEmpty)
    }

    /// The rule `ScheduledSession` itself enforces — only a lift may name muscle
    /// groups — reaching the proposal boundary in its own vocabulary.
    func testARestLiftCarryingMuscleGroupsIsRefused() {
        var week = PlanProposalTests.weekEntries
        week[1] = #"{"weekday": "tuesday", "kind": "easy", "distanceMeters": 8000, "liftKind": "rest", "liftMuscleGroups": ["legs"]}"#
        assertParseFails(reply(week: week), .liftRestDayIsNotEmpty(weekday: .tuesday))
    }

    /// `liftKind` is required, exactly as `kind` is: the lift slot's totality is
    /// "rest included and explicit" (LIFTING-SPEC §2.2), and a proposal is a whole
    /// plan restated every time rather than a patch — see `PlanDraft.applying(_:)`.
    func testAnAbsentLiftKindIsNamed() {
        let week = PlanProposalTests.weekEntries.map {
            $0.replacingOccurrences(of: #", "liftKind": "rest""#, with: "")
        }
        assertParseFails(reply(week: week), .missingField(name: "liftKind"))
    }

    /// The lift slot's own, smaller vocabulary — not the run slot's.
    func testAnUnknownLiftKindIsRefusedByName() {
        var week = PlanProposalTests.weekEntries
        week[1] = #"{"weekday": "tuesday", "kind": "easy", "distanceMeters": 8000, "liftKind": "easy"}"#
        assertParseFails(reply(week: week), .unknownLiftKind(name: "easy"))
    }

    func testAnUnknownMuscleGroupIsRefusedByName() {
        var week = PlanProposalTests.weekEntries
        week[1] = #"{"weekday": "tuesday", "kind": "easy", "distanceMeters": 8000, "liftKind": "lift", "liftMuscleGroups": ["abs"]}"#
        assertParseFails(reply(week: week), .unknownMuscleGroup(name: "abs"))
    }

    /// Formatting tolerance extends to the lift slot's own vocabulary too.
    func testLiftKindAndMuscleGroupNamesAreCaseInsensitive() throws {
        var week = PlanProposalTests.weekEntries
        week[1] = #"{"weekday": "tuesday", "kind": "easy", "distanceMeters": 8000, "liftKind": "LIFT", "liftMuscleGroups": ["Legs", "CORE"]}"#
        let proposal = try PlanProposal.parse(reply(week: week))
        XCTAssertEqual(proposal.liftSession(for: .tuesday).kind, .lift)
        XCTAssertEqual(proposal.liftSession(for: .tuesday).muscleGroups, [.legs, .core])
    }

    // MARK: - The lift's duration and note (MAX-148)

    /// The ticket's own acceptance criterion: a lift's duration and note round-trip
    /// through the wire the same way its kind and muscle groups already do.
    func testADayPrescribingALiftDurationAndNoteRoundTrips() throws {
        var week = PlanProposalTests.weekEntries
        week[1] =
            #"{"weekday": "tuesday", "kind": "easy", "distanceMeters": 8000, "liftKind": "lift", "liftMuscleGroups": ["legs", "core"], "liftDurationSeconds": 2700, "liftNote": "Lower body"}"#
        let proposal = try PlanProposal.parse(reply(week: week))

        XCTAssertEqual(proposal.liftSession(for: .tuesday).durationSeconds, 2_700)
        XCTAssertEqual(proposal.liftSession(for: .tuesday).note, "Lower body")

        let data = try JSONEncoder().encode(proposal)
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertEqual(try PlanProposal.parse(text), proposal)
    }

    /// A lift with no duration or note named is a real, legal statement — length and
    /// focus unstated — the same reading `testALiftWithNoMuscleGroupsNamedIsAccepted`
    /// gives the groups.
    func testALiftWithNoDurationOrNoteIsAccepted() throws {
        var week = PlanProposalTests.weekEntries
        week[1] = #"{"weekday": "tuesday", "kind": "easy", "distanceMeters": 8000, "liftKind": "lift"}"#
        let proposal = try PlanProposal.parse(reply(week: week))

        XCTAssertNil(proposal.liftSession(for: .tuesday).durationSeconds)
        XCTAssertNil(proposal.liftSession(for: .tuesday).note)
    }

    /// The rule `ScheduledSession` itself enforces — a rest day carries no length —
    /// reaching the lift slot's own vocabulary the same way it already does for
    /// muscle groups.
    func testARestLiftCarryingADurationIsRefused() {
        var week = PlanProposalTests.weekEntries
        week[1] =
            #"{"weekday": "tuesday", "kind": "easy", "distanceMeters": 8000, "liftKind": "rest", "liftDurationSeconds": 1800}"#
        assertParseFails(reply(week: week), .liftRestDayIsNotEmpty(weekday: .tuesday))
    }

    /// And the same for a note.
    func testARestLiftCarryingANoteIsRefused() {
        var week = PlanProposalTests.weekEntries
        week[1] =
            #"{"weekday": "tuesday", "kind": "easy", "distanceMeters": 8000, "liftKind": "rest", "liftNote": "Lower body"}"#
        assertParseFails(reply(week: week), .liftRestDayIsNotEmpty(weekday: .tuesday))
    }

    /// The door's own rule reaching this boundary in its own vocabulary — the lift
    /// slot's twin of `testAZeroDistanceOnAScheduledDayIsRejectedInTheDoorsWords`.
    func testAZeroLiftDurationIsRejectedInTheDoorsWords() {
        var week = PlanProposalTests.weekEntries
        week[1] =
            #"{"weekday": "tuesday", "kind": "easy", "distanceMeters": 8000, "liftKind": "lift", "liftDurationSeconds": 0}"#
        assertParseFails(reply(week: week), .rejectedByAuthoring(.liftSessionInvalid(weekday: .tuesday)))
    }

    /// The schema cannot go stale behind the two fields this ticket adds, matching
    /// `testTheSchemaNamesEveryLiftKindAndMuscleGroup`'s coverage of the lift's other
    /// two fields.
    func testTheSchemaNamesTheLiftsDurationAndNote() {
        let schema = PlanProposal.schemaDescription
        XCTAssertTrue(schema.contains("liftDurationSeconds"))
        XCTAssertTrue(schema.contains("liftNote"))
    }

    // MARK: - The long-run arc

    func testAnEmptyArcIsRefused() {
        assertParseFails(reply(longRunArc: "[]"), .longRunArcIsEmpty)
    }

    func testAnArcWeekBelowOneIsRefusedAsAWeekNumber() {
        assertParseFails(
            reply(longRunArc: #"[{"index": 0, "distanceMeters": 14000}]"#),
            .longRunArcWeekNotPositive(week: 0)
        )
    }

    func testAnArcThatDoesNotAscendIsRefused() {
        assertParseFails(
            reply(longRunArc: #"[{"index": 3, "distanceMeters": 14000}, {"index": 2, "distanceMeters": 16000}]"#),
            .longRunArcOutOfOrder(week: 2)
        )
        assertParseFails(
            reply(longRunArc: #"[{"index": 3, "distanceMeters": 14000}, {"index": 3, "distanceMeters": 16000}]"#),
            .longRunArcOutOfOrder(week: 3)
        )
    }

    func testAZeroArcDistanceIsRejectedInTheDoorsWords() {
        assertParseFails(
            reply(longRunArc: #"[{"index": 1, "distanceMeters": 0}]"#),
            .rejectedByAuthoring(.longRunDistanceNotPositive(week: 1))
        )
    }

    /// An arc need not start at week 1 or be contiguous — `LongRunArc` only requires
    /// strict ascent — and the parser must not invent a rule the domain does not have.
    func testASparseArcIsAccepted() throws {
        let proposal = try PlanProposal.parse(
            reply(longRunArc: #"[{"index": 2, "distanceMeters": 14000}, {"index": 9, "distanceMeters": 30000}]"#)
        )
        XCTAssertEqual(proposal.longRunArc.map(\.index), [2, 9])
    }

    // MARK: - The plan's own numbers, in the door's vocabulary

    func testAnImplausibleHeartRateCapIsRejected() {
        assertParseFails(
            reply(heartRateCapBPM: "400"),
            .rejectedByAuthoring(.heartRateCapImplausible(permitted: HeartRateSample.plausibleBPM))
        )
    }

    func testAnInvertedCadenceBandIsRejected() {
        assertParseFails(
            reply(cadenceLow: "180", cadenceHigh: "170"),
            .rejectedByAuthoring(.cadenceBandInverted)
        )
    }

    func testANonPositiveCadenceBandIsRejected() {
        assertParseFails(reply(cadenceLow: "0"), .rejectedByAuthoring(.cadenceBandNotPositive))
    }

    func testAThresholdOutsideThePermittedRangeIsRejected() {
        assertParseFails(
            reply(effective: "120"),
            .rejectedByAuthoring(.scoreThresholdOutOfRange(permitted: ScoreValue.permittedRange))
        )
    }

    func testInvertedThresholdsAreRejected() {
        assertParseFails(
            reply(effective: "40", marginal: "70"),
            .rejectedByAuthoring(.thresholdsInverted)
        )
    }

    // MARK: - Goals

    func testABadTargetDayIsRefusedAsADate() {
        assertParseFails(
            reply(goalTargetDay: #""15 November""#),
            .malformedGoalTargetDay(value: "15 November")
        )
    }

    func testGoalsAreOptional() throws {
        let proposal = try PlanProposal.parse(reply(goalStatements: "[]", goalTargetDay: nil))
        XCTAssertTrue(proposal.goals.statements.isEmpty)
        XCTAssertNil(proposal.goals.targetDay)
    }

    /// The same normalisation `PlanAuthoringSession` applies to the draft's newline-joined
    /// text, so the proposal's `PlanGoals` and the saved plan's are one value.
    func testBlankAndMultiLineGoalStatementsAreNormalised() throws {
        let proposal = try PlanProposal.parse(
            reply(goalStatements: #"["  Sub-1:45  ", "", "Two goals\nin one entry"]"#)
        )
        XCTAssertEqual(proposal.goalStatements, ["Sub-1:45", "Two goals", "in one entry"])
    }

    // MARK: - The schema cannot go stale (§4.8a)

    /// The test §4.8 names explicitly. Adding a `ScheduledSessionKind` and forgetting the
    /// prompt fails here rather than silently producing a model that cannot propose the
    /// new kind.
    /// **`prescribable`, not `allCases`** (MAX-128/MAX-129). The **run** slot's
    /// vocabulary stays five kinds — `.lift` is deliberately not offered here, because a
    /// lift proposed into the run slot would be a plan the athlete cannot mean (A17).
    /// The lift slot has its own, separate coverage test below, over its own vocabulary.
    func testTheSchemaNamesEveryProposableSessionKind() {
        for kind in ScheduledSessionKind.prescribable {
            XCTAssertTrue(
                PlanProposal.schemaDescription.contains("\"\(kind.rawValue)\""),
                "the plan schema never mentions the \(kind.rawValue) session kind"
            )
        }
    }

    /// The lift slot's own enum-coverage guarantee (MAX-141): a case added to
    /// `ScheduledSessionKind.liftPrescribable` or to `MuscleGroup` has to appear in the
    /// rendered schema, exactly as `testTheSchemaNamesEveryProposableSessionKind` pins
    /// for the run slot.
    func testTheSchemaNamesEveryLiftKindAndMuscleGroup() {
        for kind in ScheduledSessionKind.liftPrescribable {
            XCTAssertTrue(
                PlanProposal.schemaDescription.contains("\"\(kind.rawValue)\""),
                "the plan schema never mentions the \(kind.rawValue) lift kind"
            )
        }
        for group in MuscleGroup.allCases {
            XCTAssertTrue(
                PlanProposal.schemaDescription.contains("\"\(group.rawValue)\""),
                "the plan schema never mentions the \(group.rawValue) muscle group"
            )
        }
    }

    func testTheSchemaNamesEveryWeekday() {
        for weekday in Weekday.allCases {
            XCTAssertTrue(
                PlanProposal.schemaDescription.contains(PlanProposal.wireName(for: weekday)),
                "the plan schema never mentions \(weekday)"
            )
        }
    }

    /// The wire spelling is a contract with the model, so it is pinned as a literal rather
    /// than derived from the same function the schema derives it from — otherwise renaming
    /// the mapping would change the contract and pass its own test.
    func testTheWireSpellingOfAWeekdayIsPinned() {
        XCTAssertEqual(
            Weekday.allCases.sorted().map { PlanProposal.wireName(for: $0) },
            ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]
        )
    }

    /// The bounds come from the same constants the validation reads, so a change to either
    /// moves the prompt with it.
    func testTheSchemaStatesTheBoundsItWillEnforce() {
        let schema = PlanProposal.schemaDescription
        XCTAssertTrue(schema.contains("\(Int(HeartRateSample.plausibleBPM.lowerBound))"))
        XCTAssertTrue(schema.contains("\(Int(HeartRateSample.plausibleBPM.upperBound))"))
        XCTAssertTrue(schema.contains("\(ScoreValue.permittedRange.upperBound)"))
    }

    /// §4.4 again, this time as instruction rather than as enforcement: a model that is
    /// never told not to send a version will send one, and spend the retry.
    func testTheSchemaTellsTheModelWhatItMayNotSend() {
        let schema = PlanProposal.schemaDescription
        XCTAssertTrue(schema.contains("version"))
        XCTAssertTrue(schema.contains("effectiveFrom"))
        XCTAssertTrue(schema.contains("rubric band"))
    }

    /// §4.9. The schema travels next to `task` precisely because it holds nothing about
    /// the athlete; if it ever did, it would belong behind `WorkoutContext.Audience`,
    /// which is a health-data minimisation switch and must stay one.
    ///
    /// The numbers below are the seeded plan's — a real athlete's configuration. The only
    /// figures the schema may state are the *type's* bounds, which are the same for
    /// everybody.
    func testTheSchemaCarriesNoAthleteData() {
        let schema = PlanProposal.schemaDescription
        let planValues = [
            "\(Int(StandardPlanSeed.heartRateCapBPM))",
            "\(Int(StandardPlanSeed.cadenceLowStepsPerMinute))",
            "\(Int(StandardPlanSeed.cadenceHighStepsPerMinute))",
            "\(Int(StandardPlanSeed.arcPeakWeekDistanceMeters))",
        ]
        for value in planValues {
            XCTAssertFalse(schema.contains(value), "the plan schema states \(value)")
        }
    }

    // MARK: - Round trip

    func testAProposalRoundTripsThroughItsOwnWireFormat() throws {
        let proposal = try PlanProposal.parse(reply())
        let data = try JSONEncoder().encode(proposal)
        guard let text = String(data: data, encoding: .utf8) else {
            return XCTFail("proposal did not encode as UTF-8")
        }
        XCTAssertEqual(try PlanProposal.parse(text), proposal)
    }

    // MARK: - The property the design rests on

    /// **A proposal that parses is one the storage door accepts.**
    ///
    /// A proposal that parsed and then failed at
    /// `PlanAuthoringSession.plan(from:effectiveFrom:)` would be a card the athlete can
    /// see, tap, and get nowhere with. This runs a parsed proposal through a real session
    /// and asserts the plan that comes out is the plan that was proposed.
    ///
    /// The draft is assembled here rather than by a core helper on purpose: turning a
    /// proposal into a `PlanDraft` is `PlanDraft.applying(_:)`, and that belongs to
    /// MAX-101. What this ticket owes is the guarantee that the mapping will succeed.
    func testAParsedProposalSatisfiesTheAuthoringSessionsOwnValidation() throws {
        let proposal = try PlanProposal.parse(reply())
        let session = try PlanAuthoring.session(revising: nil, today: try day("2026-08-05"))
        let plan = try session.plan(
            from: try draft(from: proposal),
            effectiveFrom: session.suggestedEffectiveFrom
        )

        XCTAssertEqual(plan.heartRateCapBPM, proposal.heartRateCapBPM)
        XCTAssertEqual(plan.cadenceTarget.lowStepsPerMinute, proposal.cadenceLowStepsPerMinute)
        XCTAssertEqual(plan.cadenceTarget.highStepsPerMinute, proposal.cadenceHighStepsPerMinute)
        XCTAssertEqual(plan.rubric.effectiveThreshold.points, proposal.effectiveThresholdPoints)
        XCTAssertEqual(plan.rubric.marginalThreshold.points, proposal.marginalThresholdPoints)
        XCTAssertEqual(plan.goals, proposal.goals)
        XCTAssertEqual(
            plan.longRunArc.weeks.map(\.index),
            proposal.longRunArc.map(\.index)
        )
        for weekday in Weekday.allCases {
            XCTAssertEqual(
                plan.weeklyTemplate.session(on: weekday, for: .run),
                proposal[weekday]
            )
            // MAX-141: the lift slot goes through the same door and comes out the same
            // way, since none of the fixture's lift asks is anything but rest.
            XCTAssertEqual(
                plan.weeklyTemplate.session(on: weekday, for: .lift),
                proposal.liftSession(for: weekday)
            )
        }
    }

    /// The seeded plan is a plan the app itself authored, so a proposal restating it must
    /// parse. If it did not, the model would be held to a stricter standard than the
    /// screen — and the athlete could not ask for the plan they already have.
    func testAProposalRestatingTheSeededPlanParses() throws {
        let session = try PlanAuthoring.session(revising: nil, today: try day("2026-08-05"))
        let seeded = try session.plan(from: session.draft, effectiveFrom: try day("2026-08-03"))

        let week = try seeded.weeklyTemplate.entries.map { entry in
            try PlanProposal.Day(weekday: entry.weekday, session: entry.session)
        }
        let proposal = try PlanProposal(
            heartRateCapBPM: seeded.heartRateCapBPM,
            cadenceLowStepsPerMinute: seeded.cadenceTarget.lowStepsPerMinute,
            cadenceHighStepsPerMinute: seeded.cadenceTarget.highStepsPerMinute,
            effectiveThresholdPoints: seeded.rubric.effectiveThreshold.points,
            marginalThresholdPoints: seeded.rubric.marginalThreshold.points,
            week: week,
            longRunArc: try seeded.longRunArc.weeks.map {
                try PlanProposal.ArcWeek(index: $0.index, distanceMeters: $0.distanceMeters)
            }
        )

        XCTAssertEqual(proposal.heartRateCapBPM, StandardPlanSeed.heartRateCapBPM)
        XCTAssertEqual(proposal.longRunArc.count, StandardPlanSeed.arcWeekCount)
    }

    /// The other direction of the same property: a value the *door* refuses must not get
    /// as far as the door. Each pair below is one rule, checked at both ends — the
    /// proposal boundary reporting it, and `PlanAuthoringSession` reporting it identically
    /// for a draft that expresses it.
    func testEveryRuleTheDoorEnforcesIsEnforcedAtTheProposalBoundaryToo() throws {
        let session = try PlanAuthoring.session(revising: nil, today: try day("2026-08-05"))

        var capped = session.draft
        capped.heartRateCapBPM = 400
        assertAuthoringRejects(
            session, capped,
            .heartRateCapImplausible(permitted: HeartRateSample.plausibleBPM)
        )
        assertParseFails(
            reply(heartRateCapBPM: "400"),
            .rejectedByAuthoring(.heartRateCapImplausible(permitted: HeartRateSample.plausibleBPM))
        )

        var inverted = session.draft
        inverted.cadenceLowStepsPerMinute = 180
        assertAuthoringRejects(session, inverted, .cadenceBandInverted)
        assertParseFails(
            reply(cadenceLow: "180", cadenceHigh: "170"),
            .rejectedByAuthoring(.cadenceBandInverted)
        )

        var thresholds = session.draft
        thresholds.marginalThresholdPoints = 90
        assertAuthoringRejects(session, thresholds, .thresholdsInverted)
        assertParseFails(
            reply(effective: "40", marginal: "70"),
            .rejectedByAuthoring(.thresholdsInverted)
        )

        var outOfRange = session.draft
        outOfRange.effectiveThresholdPoints = 120
        assertAuthoringRejects(
            session, outOfRange,
            .scoreThresholdOutOfRange(permitted: ScoreValue.permittedRange)
        )
        assertParseFails(
            reply(effective: "120"),
            .rejectedByAuthoring(.scoreThresholdOutOfRange(permitted: ScoreValue.permittedRange))
        )
    }

    // MARK: - Helpers for the property above

    /// The mapping MAX-101 will own, written here so this ticket can assert its result is
    /// acceptable to the door.
    private func draft(from proposal: PlanProposal) throws -> PlanDraft {
        var sessions: [Weekday: ScheduledSession] = [:]
        var liftSessions: [Weekday: ScheduledSession] = [:]
        for day in proposal.week {
            sessions[day.weekday] = day.session
            liftSessions[day.weekday] = day.liftSession
        }
        return try PlanDraft(
            heartRateCapBPM: proposal.heartRateCapBPM,
            cadenceLowStepsPerMinute: proposal.cadenceLowStepsPerMinute,
            cadenceHighStepsPerMinute: proposal.cadenceHighStepsPerMinute,
            effectiveThresholdPoints: proposal.effectiveThresholdPoints,
            marginalThresholdPoints: proposal.marginalThresholdPoints,
            weeklySessions: sessions,
            longRunArcWeeks: proposal.longRunArc.map {
                PlanDraft.ArcWeekDraft(index: $0.index, distanceMeters: $0.distanceMeters)
            },
            liftSessions: liftSessions,
            goalStatements: proposal.goalStatements.joined(separator: "\n"),
            goalTargetDay: proposal.goalTargetDay
        )
    }

    private func assertAuthoringRejects(
        _ session: PlanAuthoringSession,
        _ draft: PlanDraft,
        _ expected: PlanAuthoringError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(
            try session.plan(from: draft, effectiveFrom: session.suggestedEffectiveFrom),
            "",
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(error as? PlanAuthoringError, expected, file: file, line: line)
        }
    }
}
