import Foundation
import XCTest
import MaximizeCoreTestSupport
@testable import MaximizeCore

/// MAX-101: asking for a plan inside a training thread, end to end through `ChatModel`.
///
/// This is where the ticket's boundary is actually enforced, so it is where it is
/// asserted: **chat proposes, the athlete taps.** There is no path here from a model
/// reply to stored data, nothing pre-drafts, nothing drafts on appear, and a rejected
/// proposal leaves the plan in force completely untouched (§4.10, A13, A14).
@MainActor
final class ChatPlanDraftingTests: XCTestCase {

    // MARK: - Fixtures

    private let utc = TimeZone(identifier: "UTC") ?? .current

    private static let proposalReply = """
    {
      "heartRateCapBPM": 148,
      "cadenceLowStepsPerMinute": 168,
      "cadenceHighStepsPerMinute": 176,
      "effectiveThresholdPoints": 70,
      "marginalThresholdPoints": 45,
      "week": [
        {"weekday": "monday", "kind": "rest", "liftKind": "rest"},
        {"weekday": "tuesday", "kind": "easy", "distanceMeters": 8000, "liftKind": "rest"},
        {"weekday": "wednesday", "kind": "hard", "note": "6 × 800m", "liftKind": "rest"},
        {"weekday": "thursday", "kind": "easy", "distanceMeters": 6000, "liftKind": "rest"},
        {"weekday": "friday", "kind": "rest", "liftKind": "rest"},
        {"weekday": "saturday", "kind": "easy", "distanceMeters": 6000, "liftKind": "rest"},
        {"weekday": "sunday", "kind": "long", "distanceMeters": 18000, "liftKind": "rest"}
      ],
      "longRunArc": [{"index": 1, "distanceMeters": 16000}, {"index": 2, "distanceMeters": 18000}],
      "goalStatements": ["Sub-1:45 half marathon"]
    }
    """

    private func scope() throws -> TrainingScope {
        try Fixture.scope(from: (2026, 1, 1), through: (2026, 1, 7))
    }

    /// A thread with one exchange already in it, which is what makes drafting possible at
    /// all — §4.2's conversation is the input.
    private func seededThread() throws -> ChatThread {
        var thread = try Fixture.thread(subject: .training(try scope()), messages: [])
        thread = try thread.appending(try Fixture.message(.user, "Four runs a week, long run Sunday.", at: 1))
        thread = try thread.appending(try Fixture.message(.assistant, "Understood.", at: 2))
        return thread
    }

    private func makeModel(
        planCalendar: PlanCalendar?,
        proposalOutcome: FakePlanProposalModelInvoking.Outcome = .reply(ChatPlanDraftingTests.proposalReply),
        seedConversation: Bool = true
    ) async throws -> (ChatModel, InMemoryWorkoutStore, FakePlanProposalModelInvoking) {
        let store = InMemoryWorkoutStore(planCalendar: planCalendar)
        let threads = FakeChatThreadRepository()
        if seedConversation {
            try await threads.store(try seededThread())
        }
        let proposalClient = FakePlanProposalModelInvoking(outcome: proposalOutcome)
        let chatModel = ChatModel(
            subject: .training(try scope()),
            workoutRepository: store,
            scoreRepository: store,
            planRepository: store,
            settingsRepository: store,
            chatThreadRepository: threads,
            chatClient: FakeStreamingChatModelInvoking(),
            planProposalClient: proposalClient,
            timeZone: utc,
            now: { Fixture.epoch }
        )
        return (chatModel, store, proposalClient)
    }

    private func storedPlan() throws -> Plan {
        try Plan(
            version: PlanVersion(2),
            effectiveFrom: Fixture.day(2025, 12, 1),
            weeklyTemplate: Fixture.weeklyTemplate(lift: [
                .tuesday: ScheduledSession(kind: .lift, muscleGroups: [.legs]),
            ]),
            longRunArc: LongRunArc(weeks: [
                LongRunArc.Week(index: 1, distanceMeters: 16_000),
                LongRunArc.Week(index: 2, distanceMeters: 18_000),
            ]),
            heartRateCapBPM: 152,
            cadenceTarget: CadenceBand(lowStepsPerMinute: 165, highStepsPerMinute: 170),
            rubric: Fixture.rubric(),
            goals: PlanGoals(statements: ["Run a sub-4:00 marathon"])
        )
    }

    // MARK: - Asking

    /// The happy path: one tap, one call, a card to review — and nothing else.
    func testDraftingProducesAReviewableProposal() async throws {
        let (chatModel, store, client) = try await makeModel(
            planCalendar: try PlanCalendar([try storedPlan()])
        )
        await chatModel.load()
        XCTAssertTrue(chatModel.canDraftPlan)

        await chatModel.draftPlan()

        guard case let .proposed(review) = chatModel.planDrafting else {
            return XCTFail("expected a proposal, got \(chatModel.planDrafting)")
        }
        XCTAssertEqual(client.callCount, 1)
        XCTAssertTrue(review.isRevision)
        XCTAssertEqual(review.standing, .revision(supersedes: try PlanVersion(2), inEffectSince: try Fixture.day(2025, 12, 1)))
        XCTAssertEqual(chatModel.proposalAwaitingReview?.heartRateCapBPM, 148)
        XCTAssertEqual(store.planWriteCount, 0)
    }

    /// The revision case §4.2 leads with, all the way to the card: the cap moved and the
    /// diff says so, against the version actually in force.
    func testTheCardDiffsAgainstThePlanInForce() async throws {
        let (chatModel, _, _) = try await makeModel(planCalendar: try PlanCalendar([try storedPlan()]))
        await chatModel.load()
        await chatModel.draftPlan()

        guard case let .proposed(review) = chatModel.planDrafting else {
            return XCTFail("expected a proposal, got \(chatModel.planDrafting)")
        }
        let cap = try XCTUnwrap(review.sections.flatMap(\.rows).first { $0.id == "heartRateCap" })
        XCTAssertEqual(cap.change, .changed(from: "152 bpm"))
        // And the lift day this reply does not restate is a visible, named change
        // (MAX-141) rather than a silent carry-forward — see `PlanProposalReviewTests`.
        let tuesdayLift = try XCTUnwrap(review.sections.flatMap(\.rows).first { $0.id == "lift.tuesday" })
        XCTAssertEqual(tuesdayLift.value, "Rest")
        XCTAssertEqual(tuesdayLift.change, .changed(from: "Lift · Legs"))
    }

    /// A fresh install: no plan in force, so the card states the plan rather than
    /// diffing it, and the handoff will open on a first-plan session.
    func testDraftingBeforeAnyPlanExistsProducesAFirstPlanCard() async throws {
        let (chatModel, _, _) = try await makeModel(planCalendar: nil)
        await chatModel.load()
        await chatModel.draftPlan()

        guard case let .proposed(review) = chatModel.planDrafting else {
            return XCTFail("expected a proposal, got \(chatModel.planDrafting)")
        }
        XCTAssertEqual(review.standing, .firstPlan)
        XCTAssertEqual(review.changedRowCount, 0)
    }

    // MARK: - The boundary

    /// The ticket's central assertion. Drafting, reviewing, and then **discarding** must
    /// leave the plan in force byte-for-byte what it was — and the way that is guaranteed
    /// is that no write ever happens, not that a write is undone.
    func testNoPlanIsEverStoredByTheProposalPath() async throws {
        let (chatModel, store, _) = try await makeModel(
            planCalendar: try PlanCalendar([try storedPlan()])
        )
        await chatModel.load()

        await chatModel.draftPlan()
        chatModel.discardProposal()
        await chatModel.draftPlan()

        XCTAssertEqual(store.planWriteCount, 0)
        let versions = try await store.planCalendar()?.versions ?? []
        XCTAssertEqual(versions, [try storedPlan()])
    }

    /// Accepting does not store either. All it yields is the proposal, which the
    /// authoring screen applies to a session it builds itself — the athlete still has to
    /// set a date and save.
    func testAcceptingHandsOverAProposalAndStoresNothing() async throws {
        let (chatModel, store, _) = try await makeModel(
            planCalendar: try PlanCalendar([try storedPlan()])
        )
        await chatModel.load()
        await chatModel.draftPlan()

        let handedOver = try XCTUnwrap(chatModel.proposalAwaitingReview)

        XCTAssertEqual(handedOver.heartRateCapBPM, 148)
        XCTAssertEqual(store.planWriteCount, 0)
    }

    /// Discarding is a real, stated outcome rather than a card that silently vanishes.
    func testDiscardingSaysSoAndLeavesNothingBehind() async throws {
        let (chatModel, _, _) = try await makeModel(planCalendar: try PlanCalendar([try storedPlan()]))
        await chatModel.load()
        await chatModel.draftPlan()

        chatModel.discardProposal()

        XCTAssertEqual(chatModel.planDrafting, .idle)
        XCTAssertNil(chatModel.proposalAwaitingReview)
        XCTAssertEqual(chatModel.messages.last?.kind, .notice)
        XCTAssertEqual(chatModel.messages.last?.text, "Proposal discarded. Your plan is unchanged.")
    }

    /// A proposal is not a turn. It is never written to the thread, so a card on screen
    /// leaves the stored conversation exactly as it was.
    func testAProposalIsNeverWrittenToTheThread() async throws {
        let store = InMemoryWorkoutStore(planCalendar: try PlanCalendar([try storedPlan()]))
        let threads = FakeChatThreadRepository()
        try await threads.store(try seededThread())
        let chatModel = ChatModel(
            subject: .training(try scope()),
            workoutRepository: store,
            scoreRepository: store,
            planRepository: store,
            settingsRepository: store,
            chatThreadRepository: threads,
            chatClient: FakeStreamingChatModelInvoking(),
            planProposalClient: FakePlanProposalModelInvoking(outcome: .reply(Self.proposalReply)),
            timeZone: utc,
            now: { Fixture.epoch }
        )
        await chatModel.load()
        let writesBefore = threads.writes

        await chatModel.draftPlan()

        XCTAssertEqual(threads.writes, writesBefore)
        let stored = try XCTUnwrap(threads.allThreads.first)
        XCTAssertEqual(stored.visibleMessages.count, 2)
    }

    // MARK: - A14 — nothing unattended, nothing on appear

    /// `load()` reads storage and returns. It must not draft, because a proposal nobody
    /// asked for is a model call nobody attended (A14).
    func testLoadingDoesNotDraftAnything() async throws {
        let (chatModel, _, client) = try await makeModel(planCalendar: nil)

        await chatModel.load()

        XCTAssertEqual(client.callCount, 0)
        XCTAssertEqual(chatModel.planDrafting, .idle)
    }

    /// And the action is not offered where it cannot mean anything: a workout thread has
    /// one run's context, and a plan drafted from one run is a plan drafted from almost
    /// nothing (§4.2).
    func testAWorkoutThreadNeverOffersPlanDrafting() async throws {
        let store = InMemoryWorkoutStore(planCalendar: try PlanCalendar([Fixture.plan()]))
        try await store.store(Fixture.workout())
        try await store.store(try DerivedMetrics(
            workoutID: Fixture.workoutID,
            averageHeartRateBPM: 142,
            maximumHeartRateBPM: 161,
            timeAboveCapSeconds: 250,
            heartRateDriftFraction: 0.032,
            averageCadenceStepsPerMinute: 167,
            gradeAdjustedPaceSecondsPerKilometer: 308,
            zoneSplits: ZoneSplits(splits: [ZoneSplits.Split(zone: .two, seconds: 3_000)]),
            planVersion: PlanVersion(1)
        ))
        store.seedScore(try Fixture.score(points: 88))

        let client = FakePlanProposalModelInvoking(outcome: .reply(Self.proposalReply))
        let chatModel = ChatModel(
            subject: .workout(Fixture.workoutID),
            workoutRepository: store,
            scoreRepository: store,
            planRepository: store,
            settingsRepository: store,
            chatThreadRepository: FakeChatThreadRepository(),
            chatClient: FakeStreamingChatModelInvoking(),
            planProposalClient: client,
            timeZone: utc,
            now: { Fixture.epoch }
        )
        await chatModel.load()

        XCTAssertEqual(chatModel.loadState, .ready)
        XCTAssertFalse(chatModel.canDraftPlan)

        await chatModel.draftPlan()
        XCTAssertEqual(client.callCount, 0, "draftPlan() is a no-op when canDraftPlan is false")
    }

    /// Drafting needs something said. An empty thread offers no action and costs no call.
    func testAnEmptyThreadOffersNoDraftAction() async throws {
        let (chatModel, _, client) = try await makeModel(planCalendar: nil, seedConversation: false)
        await chatModel.load()

        XCTAssertEqual(chatModel.loadState, .ready)
        XCTAssertFalse(chatModel.canDraftPlan)
        await chatModel.draftPlan()
        XCTAssertEqual(client.callCount, 0)
    }

    /// A model with no plan-drafting transport does not offer an action that cannot work.
    func testNoProposalClientMeansNoAction() async throws {
        let store = InMemoryWorkoutStore(planCalendar: nil)
        let threads = FakeChatThreadRepository()
        try await threads.store(try seededThread())
        let chatModel = ChatModel(
            subject: .training(try scope()),
            workoutRepository: store,
            scoreRepository: store,
            planRepository: store,
            settingsRepository: store,
            chatThreadRepository: threads,
            chatClient: FakeStreamingChatModelInvoking(),
            timeZone: utc,
            now: { Fixture.epoch }
        )
        await chatModel.load()

        XCTAssertFalse(chatModel.canDraftPlan)
    }

    // MARK: - Failure is a state

    /// §4.5 step 2 and the ticket's "failure is a state": every failure gets one honest
    /// sentence in the transcript, as a notice — never written to the thread.
    func testEveryFailureGetsASentenceInTheTranscript() async throws {
        let cases: [(FakePlanProposalModelInvoking.Outcome, String)] = [
            (.failure(.noAPIKeyStored), "Settings"),
            (.failure(.requestFailed), "connectivity"),
            (.failure(.refused), "declined"),
            (.reply("Sure, here you go!"), "Nothing has changed"),
        ]

        for (outcome, fragment) in cases {
            let (chatModel, store, _) = try await makeModel(planCalendar: nil, proposalOutcome: outcome)
            await chatModel.load()

            await chatModel.draftPlan()

            XCTAssertEqual(chatModel.planDrafting, .idle)
            XCTAssertEqual(chatModel.messages.last?.kind, .notice)
            let text = chatModel.messages.last?.text ?? ""
            XCTAssertTrue(text.contains(fragment), "expected \"\(fragment)\" in: \(text)")
            XCTAssertEqual(store.planWriteCount, 0)
        }
    }

    /// A reply the app cannot use is asked for again once — the policy is
    /// `PlanProposalDrafting`'s, and this asserts `ChatModel` actually goes through it
    /// rather than making a call of its own.
    func testAnUnusableReplyCostsExactlyTwoCallsAndNoMore() async throws {
        let (chatModel, _, client) = try await makeModel(
            planCalendar: nil,
            proposalOutcome: .reply("not a proposal")
        )
        await chatModel.load()

        await chatModel.draftPlan()

        XCTAssertEqual(client.callCount, PlanProposalDrafting.maximumAttempts)
        XCTAssertEqual(chatModel.planDrafting, .idle)
    }

    /// A reload discards a card, because the card describes a conversation the reload has
    /// just replaced.
    func testReloadingClearsAPendingProposal() async throws {
        let (chatModel, _, _) = try await makeModel(planCalendar: nil)
        await chatModel.load()
        await chatModel.draftPlan()
        guard case .proposed = chatModel.planDrafting else {
            return XCTFail("expected a proposal before reloading")
        }

        await chatModel.load()

        XCTAssertEqual(chatModel.planDrafting, .idle)
    }
}
