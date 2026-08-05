import Foundation
import XCTest
@testable import MaximizeCore

/// MAX-101, A13: `PlanDraft.applying(_:)` — what it carries, what it replaces, and the
/// thing it must not do.
///
/// The last of those is the reason this file exists at all. A13 names the near-miss by
/// name: *"a helper that applies a proposal to a draft **and also stores it**. Applying
/// is fine. Storing is D1's door, and it opens by hand."* So the negative is asserted
/// directly rather than left to a reading of the source.
final class PlanProposalApplyingTests: XCTestCase {

    // MARK: - Fixtures

    private static let weekEntries = [
        #"{"weekday": "monday", "kind": "rest"}"#,
        #"{"weekday": "tuesday", "kind": "easy", "distanceMeters": 8000}"#,
        #"{"weekday": "wednesday", "kind": "hard", "note": "6 × 800m"}"#,
        #"{"weekday": "thursday", "kind": "easy", "distanceMeters": 6000}"#,
        #"{"weekday": "friday", "kind": "rest"}"#,
        #"{"weekday": "saturday", "kind": "easy", "distanceMeters": 6000}"#,
        #"{"weekday": "sunday", "kind": "long", "distanceMeters": 20000}"#,
    ]

    private func reply(
        heartRateCapBPM: String = "148",
        week: [String] = PlanProposalApplyingTests.weekEntries,
        longRunArc: String = #"[{"index": 1, "distanceMeters": 16000}, {"index": 2, "distanceMeters": 18000}]"#,
        goalStatements: String = #"["Sub-1:45 half marathon"]"#
    ) -> String {
        """
        {
          "heartRateCapBPM": \(heartRateCapBPM),
          "cadenceLowStepsPerMinute": 168,
          "cadenceHighStepsPerMinute": 176,
          "effectiveThresholdPoints": 72,
          "marginalThresholdPoints": 44,
          "week": [\(week.joined(separator: ", "))],
          "longRunArc": \(longRunArc),
          "goalStatements": \(goalStatements),
          "goalTargetDay": "2026-11-15"
        }
        """
    }

    /// A plan already in force, with lift days on it, so the interesting case — a
    /// revision — is the default rather than the special one.
    private func storedPlan() throws -> Plan {
        try Plan(
            version: PlanVersion(3),
            effectiveFrom: Fixture.day(2026, 6, 1),
            weeklyTemplate: Fixture.weeklyTemplate(lift: [
                .tuesday: ScheduledSession(kind: .lift, muscleGroups: [.legs, .core]),
                .friday: ScheduledSession(kind: .lift, note: "45 minutes", muscleGroups: [.chest]),
            ]),
            longRunArc: LongRunArc(weeks: [
                LongRunArc.Week(index: 1, distanceMeters: 16_000),
                LongRunArc.Week(index: 2, distanceMeters: 18_000),
                LongRunArc.Week(index: 3, distanceMeters: 20_000),
            ]),
            heartRateCapBPM: 152,
            cadenceTarget: CadenceBand(lowStepsPerMinute: 165, highStepsPerMinute: 170),
            rubric: Fixture.rubric(),
            goals: PlanGoals(statements: ["Run a sub-4:00 marathon"], targetDay: Fixture.day(2026, 4, 20))
        )
    }

    private func revisionSession() throws -> PlanAuthoringSession {
        try PlanAuthoring.session(
            revising: try PlanCalendar([try storedPlan()]),
            today: try Fixture.day(2026, 8, 5)
        )
    }

    // MARK: - What it carries across

    func testEveryFieldTheProposalCarriesReachesTheDraft() throws {
        let proposal = try PlanProposal.parse(reply())
        let applied = try revisionSession().draft.applying(proposal)

        XCTAssertEqual(applied.heartRateCapBPM, 148)
        XCTAssertEqual(applied.cadenceLowStepsPerMinute, 168)
        XCTAssertEqual(applied.cadenceHighStepsPerMinute, 176)
        XCTAssertEqual(applied.effectiveThresholdPoints, 72)
        XCTAssertEqual(applied.marginalThresholdPoints, 44)
        XCTAssertEqual(applied.longRunArc.map(\.index), [1, 2])
        XCTAssertEqual(applied.longRunArc.map(\.distanceMeters), [16_000, 18_000])
        XCTAssertEqual(applied.goalStatements, "Sub-1:45 half marathon")
        XCTAssertEqual(applied.goalTargetDay, try Fixture.day(2026, 11, 15))

        for weekday in Weekday.allCases {
            XCTAssertEqual(try applied[weekday].session(), proposal[weekday])
        }
    }

    /// The revision case §4.2 leads with — "keep the long run on Sunday", "drop Thursday
    /// to 6k" — reaching the draft as the athlete asked, with the day they did not
    /// mention carried through by the model rather than reset by this mapping.
    func testTheDraftHoldsTheProposalsWeekNotThePlansOwn() throws {
        let applied = try revisionSession().draft.applying(try PlanProposal.parse(reply()))

        XCTAssertEqual(applied[.thursday].distanceMeters, 6_000)
        XCTAssertEqual(applied[.sunday].kind, .long)
        XCTAssertEqual(applied[.sunday].distanceMeters, 20_000)
        // The stored plan rests on Saturday-as-6k-easy too; the point is that the value
        // on the draft came from the proposal, which is what makes an unrequested edit
        // visible in the card rather than invisible behind a merge.
        XCTAssertEqual(applied[.saturday].kind, .easy)
    }

    // MARK: - Lifts (the slot a proposal cannot reach)

    /// `PlanProposal`'s vocabulary excludes `.lift` until MAX-141, so an applied proposal
    /// must leave the lift slot exactly as the athlete had it — including the note
    /// MAX-137 deliberately left uneditable.
    func testLiftDaysSurviveApplyingAProposalUntouched() throws {
        let applied = try revisionSession().draft.applying(try PlanProposal.parse(reply()))

        XCTAssertEqual(applied[.tuesday].liftKind, .lift)
        XCTAssertEqual(applied[.tuesday].liftMuscleGroups, [.legs, .core])
        XCTAssertEqual(applied[.friday].liftKind, .lift)
        XCTAssertEqual(applied[.friday].liftMuscleGroups, [.chest])
        XCTAssertEqual(applied[.friday].liftNote, "45 minutes")
        XCTAssertEqual(applied[.monday].liftKind, .rest)
        XCTAssertEqual(applied[.sunday].liftKind, .rest)
    }

    /// The same fact from the other side: the run slot moved and the lift slot did not,
    /// on the very day both are prescribed. Tuesday is an easy run *and* a leg lift in
    /// the stored plan, and the proposal changes only the run.
    func testARunSlotChangeOnALiftDayLeavesTheLiftAlone() throws {
        let proposal = try PlanProposal.parse(reply(week: [
            #"{"weekday": "monday", "kind": "rest"}"#,
            #"{"weekday": "tuesday", "kind": "hard", "note": "8 × 400m"}"#,
            #"{"weekday": "wednesday", "kind": "rest"}"#,
            #"{"weekday": "thursday", "kind": "easy", "distanceMeters": 6000}"#,
            #"{"weekday": "friday", "kind": "rest"}"#,
            #"{"weekday": "saturday", "kind": "easy", "distanceMeters": 6000}"#,
            #"{"weekday": "sunday", "kind": "long", "distanceMeters": 20000}"#,
        ]))
        let applied = try revisionSession().draft.applying(proposal)

        XCTAssertEqual(applied[.tuesday].kind, .hard)
        XCTAssertEqual(applied[.tuesday].note, "8 × 400m")
        XCTAssertEqual(applied[.tuesday].liftKind, .lift)
        XCTAssertEqual(applied[.tuesday].liftMuscleGroups, [.legs, .core])
    }

    /// A first plan has no lift days to carry, and applying must not invent any.
    func testAFirstPlanAppliesWithNoLiftDays() throws {
        let session = try PlanAuthoring.session(revising: nil, today: try Fixture.day(2026, 8, 5))
        let applied = try session.draft.applying(try PlanProposal.parse(reply()))

        for weekday in Weekday.allCases {
            XCTAssertEqual(applied[weekday].liftKind, .rest)
            XCTAssertTrue(applied[weekday].liftMuscleGroups.isEmpty)
        }
    }

    // MARK: - The run slot's duration (MAX-131's carried, uneditable field)

    /// `ScheduledSession.durationSeconds` is carried-but-uneditable on the run slot and
    /// `PlanProposal` has no field for it, so a naive mapping would silently delete a
    /// "45 minutes easy" — the exact failure that field's own documentation says a
    /// revision must not commit. It survives the proposal editing the day's distance.
    func testAPrescribedRunDurationSurvivesADistanceChangeOnTheSameKind() throws {
        let session = try sessionRevising(thursdayDurationSeconds: 2_700)
        let applied = try session.draft.applying(try PlanProposal.parse(reply()))

        // The proposal moves Thursday from 8 km to 6 km, and leaves it an easy run.
        XCTAssertEqual(applied[.thursday].kind, .easy)
        XCTAssertEqual(applied[.thursday].distanceMeters, 6_000)
        XCTAssertEqual(applied[.thursday].durationSeconds, 2_700)
    }

    /// And it does not survive the proposal *replacing* the session: carrying 45 minutes
    /// from a deleted easy run onto a newly proposed hard one would assert something no
    /// one said.
    func testAPrescribedRunDurationIsDroppedWhenTheProposalChangesTheKind() throws {
        let session = try sessionRevising(thursdayDurationSeconds: 2_700)
        let proposal = try PlanProposal.parse(reply(week: [
            #"{"weekday": "monday", "kind": "rest"}"#,
            #"{"weekday": "tuesday", "kind": "easy", "distanceMeters": 8000}"#,
            #"{"weekday": "wednesday", "kind": "rest"}"#,
            #"{"weekday": "thursday", "kind": "hard", "note": "8 × 400m"}"#,
            #"{"weekday": "friday", "kind": "rest"}"#,
            #"{"weekday": "saturday", "kind": "easy", "distanceMeters": 6000}"#,
            #"{"weekday": "sunday", "kind": "long", "distanceMeters": 20000}"#,
        ]))
        let applied = try session.draft.applying(proposal)

        XCTAssertEqual(applied[.thursday].kind, .hard)
        XCTAssertNil(applied[.thursday].durationSeconds)
    }

    /// A session opening on a plan whose Thursday carries a prescribed duration.
    private func sessionRevising(thursdayDurationSeconds: Double) throws -> PlanAuthoringSession {
        let plan = try Plan(
            version: PlanVersion(3),
            effectiveFrom: Fixture.day(2026, 6, 1),
            weeklyTemplate: WeeklyTemplate([
                .monday: .rest,
                .tuesday: ScheduledSession(kind: .easy, distanceMeters: 8_000),
                .wednesday: ScheduledSession(kind: .hard, note: "6 × 800m"),
                .thursday: ScheduledSession(
                    kind: .easy,
                    distanceMeters: 8_000,
                    durationSeconds: thursdayDurationSeconds
                ),
                .friday: .rest,
                .saturday: ScheduledSession(kind: .easy, distanceMeters: 6_000),
                .sunday: ScheduledSession(kind: .long, distanceMeters: 18_000),
            ]),
            longRunArc: LongRunArc(weeks: [LongRunArc.Week(index: 1, distanceMeters: 16_000)]),
            heartRateCapBPM: 152,
            cadenceTarget: CadenceBand(lowStepsPerMinute: 165, highStepsPerMinute: 170),
            rubric: Fixture.rubric()
        )
        return try PlanAuthoring.session(
            revising: try PlanCalendar([plan]),
            today: try Fixture.day(2026, 8, 5)
        )
    }

    // MARK: - The door still accepts it

    /// The property MAX-099 promised and this ticket has to keep: the mapping's output
    /// converts, through the same door and with no new key cut for it.
    func testAnAppliedProposalStillPassesTheAuthoringDoor() throws {
        let session = try revisionSession()
        let proposal = try PlanProposal.parse(reply())
        let plan = try session.plan(
            from: try session.draft.applying(proposal),
            effectiveFrom: session.suggestedEffectiveFrom
        )

        XCTAssertEqual(plan.version, try PlanVersion(4))
        XCTAssertEqual(plan.heartRateCapBPM, 148)
        // The lift slot the proposal never mentioned survives all the way into the plan.
        XCTAssertEqual(
            plan.weeklyTemplate.session(on: .tuesday, for: .lift).muscleGroups,
            [.legs, .core]
        )
        // And the rubric bands the athlete tuned are carried forward, not re-seeded
        // (§4.4) — the proposal carries no bands and cannot.
        XCTAssertEqual(plan.rubric.bands, try Fixture.rubric().bands)
    }

    // MARK: - A13: it applies, it does not store

    /// The near-miss, asserted rather than described.
    ///
    /// Applying a proposal to a draft, twice, against a store that would count any write
    /// — and the store's plan calendar is byte-for-byte what it was. There is no
    /// repository parameter on `applying(_:)` to pass one, which is the real guarantee;
    /// this is the test that fails if a future edit adds one.
    func testApplyingAProposalStoresNothing() async throws {
        let store = InMemoryStoreProbe(calendar: try PlanCalendar([try storedPlan()]))
        let session = try PlanAuthoring.session(
            revising: try await store.planCalendar(),
            today: try Fixture.day(2026, 8, 5)
        )
        let proposal = try PlanProposal.parse(reply())

        _ = try session.draft.applying(proposal)
        _ = try session.draft.applying(proposal)

        let versions = try await store.planCalendar()?.versions.map(\.version) ?? []
        XCTAssertEqual(store.writeCount, 0)
        XCTAssertEqual(versions, [try PlanVersion(3)])
    }

    /// A `PlanRepository` whose only job is to notice a write.
    ///
    /// Deliberately not `InMemoryWorkoutStore`: that one accepts writes and this test is
    /// about a call that must never happen, so a store which *fails loudly* on `store`
    /// is the honest instrument.
    private final class InMemoryStoreProbe: PlanRepository, @unchecked Sendable {
        private let calendar: PlanCalendar?
        private(set) var writeCount = 0

        init(calendar: PlanCalendar?) {
            self.calendar = calendar
        }

        func planCalendar() async throws -> PlanCalendar? { calendar }

        func store(_ plan: Plan) async throws {
            writeCount += 1
            XCTFail("A plan reached storage from the proposal path; A13 says that door opens by hand.")
        }
    }
}
